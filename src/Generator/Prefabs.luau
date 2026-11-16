--!native
--!optimize 2

local Blocks = require("./Blocks")
local Parser = require("../Parser")

type Block = Blocks.Block
type Writer = (Value: string, Block: Block, Range: NumberRange?, Components: { string }?) -> ()
type Reader = (Variable: string, Block: Block, Range: NumberRange?, Components: { string }?) -> ()
type Generate = (
	Declaration: Parser.Primitive,
	Variable: string?,
	Read: Block,
	Write: Block,
	WriteValidations: boolean?
) -> ()

type TypePrefab = {
	Read: Reader,
	Write: Writer,
}

type AssertPrefab = {
	Lower: string,
	Upper: string,
	Exact: string?,
}

type AssertGenerator = (Variable: string, ...any) -> AssertPrefab

local SEND_BUFFER = "SendBuffer"
local RECIEVE_BUFFER = "RecieveBuffer"
--> Where the last Allocate(Length) started (Allocate is inlined, so it returns no offset here)
local SEND_POSITION = "SendCursor - Length"

local BYTE = 1
local SHORT = 2
local INTEGER = 4
local HALF_FLOAT = 2
local FLOAT = 4
local DOUBLE = 8

--> Extra checks on data received from clients, only in the server module (see SetStrict).
--> The client trusts the server and pays nothing for these.
local Strict = {
	Floats = false, --> reject NaN and +-inf
	Strings = false, --> reject invalid UTF-8
	Sizes = false, --> check wire-supplied lengths against the bytes left before allocating
}

local FLOAT_TYPES = { f16 = true, f32 = true, f64 = true }

--> x - x is 0 for every finite number and NaN for NaN and +-inf
local function NonFiniteCheck(Variables: { string }): string
	local Terms = {}
	for _, Variable in Variables do
		table.insert(Terms, `({Variable} - {Variable})`)
	end
	return `if {table.concat(Terms, " + ")} ~= 0 then error("Expected a finite number") end`
end

local Types = {}
local Asserts = {
	float = function(Variable: string, Min: number, Max: number): AssertPrefab
		return {
			Lower = `if not ({Variable} >= {Min}) then error(\`Expected "{Variable}" to be larger than or equal to {Min}, got \{{Variable}} instead.\`) end`,
			Upper = `if not ({Variable} <= {Max}) then error(\`Expected "{Variable}" to be smaller than or equal to {Max}, got \{{Variable}} instead.\`) end`,
			Exact = `if {Variable} ~= {Max} then error(\`Expected "{Variable}" to be equal to {Max}, got \{{Variable}\} instead.\`) end`,
		}
	end,

	integer = function(Variable: string, Min: number, Max: number): AssertPrefab
		return {
			Lower = `if {Variable} < {Min} then error(\`Expected "{Variable}" to be larger than or equal to {Min}, got \{{Variable}} instead.\`) end`,
			Upper = `if {Variable} > {Max} then error(\`Expected "{Variable}" to be smaller than or equal to {Max}, got \{{Variable}} instead.\`) end`,
			Exact = `if {Variable} ~= {Max} then error(\`Expected "{Variable}" to be equal to {Max}, got \{{Variable}\} instead.\`) end`,
		}
	end,

	string = function(Variable: string, Min: number, Max: number): AssertPrefab
		return {
			Lower = `if #{Variable} < {Min} then error(\`Expected length of "{Variable}" to be larger than or equal to {Min}, got \{#{Variable}} instead.\`) end`,
			Upper = `if #{Variable} > {Max} then error(\`Expected length of "{Variable}" to be smaller than or equal to  {Max}, got \{#{Variable}} instead.\`) end`,
			Exact = `if #{Variable} ~= {Max} then error(\`Expected length of "{Variable}" to equal to {Max}, got \{#{Variable}} instead.\`) end`,
		}
	end,

	vector = function(Variable: string, Min: number, Max: number): AssertPrefab
		return {
			Lower = `if not ({Variable}.Magnitude >= {Min}) then error(\`Expected magnitude of "{Variable}" to be larger than or equal to {Min}, got \{{Variable}.Magnitude} instead.\`) end`,
			Upper = `if not ({Variable}.Magnitude <= {Max}) then error(\`Expected magnitude of "{Variable}" to be smaller than or equal to {Max}, got \{{Variable}.Magnitude} instead.\`) end`,
			Exact = `if {Variable}.Magnitude ~= {Max} then error(\`Expected magnitude of "{Variable}" to equal to {Max}, got \{{Variable}.Magnitude} instead.\`) end`,
		}
	end,

	buffer = function(Variable: string, Min: number, Max: number): AssertPrefab
		return {
			Lower = `if buffer.len({Variable}) < {Min} then error(\`Expected size of "{Variable}" to be larger than or equal to {Min}, got \{buffer.len({Variable})} instead.\`) end`,
			Upper = `if buffer.len({Variable}) > {Max} then error(\`Expected size of "{Variable}" to be smaller than or equal to {Max}, got \{buffer.len({Variable})} instead.\`) end`,
			Exact = `if buffer.len({Variable}) ~= {Max} then error(\`Expected size of "{Variable}" to equal to {Max}, got \{buffer.len({Variable})} instead.\`) end`,
		}
	end,

	Instance = function(Variable: string, Class: string): AssertPrefab
		local TypeAssertion =
			`if typeof({Variable}) ~= "Instance" then error(\`Expected an Instance, got \{typeof({Variable})} instead.\`) end`
		return {
			Lower = `error("Something has gone wrong")`,
			Upper = `error("Something has gone wrong")`,
			Exact = if Class == "Instance"
				then TypeAssertion
				else `{TypeAssertion}\nif not {Variable}:IsA("{Class}") then error(\`Expected an Instance of type "{Class}", got "\{{Variable}.ClassName}" instead.\`) end`,
		}
	end,
}
local Structures = {
	Array = nil :: any,
}
local Primitives: { [string]: {
	Type: string | (Declaration: Parser.Primitive) -> string,
	Generate: Generate,
} } = {}

local NumberTypeBounds = {
	{ Bits = 8, Maximum = 255, Type = "u8" },
	{ Bits = 16, Maximum = 65535, Type = "u16" },
	{ Bits = 32, Maximum = 4294967295, Type = "u32" },
}

local function GetTypeToUse(UpperSize: number): TypePrefab
	for _, NumberType in NumberTypeBounds do
		if NumberType.Maximum >= UpperSize then
			return Types[NumberType.Type]
		end
	end

	error("Value is too large to be written to a buffer.")
end

local function GetTypeToUseByBits(UpperBits: number): TypePrefab
	for _, NumberType in NumberTypeBounds do
		if NumberType.Bits >= UpperBits then
			return Types[NumberType.Type]
		end
	end

	error("Value is too large to be written to a buffer.")
end

local function GeneratePrimitivePrefab(Type: string, Prefab: TypePrefab, AssertGenerator: AssertGenerator?): Generate
	return function(
		Declaration: Parser.Primitive,
		Variable: string?,
		Read: Block,
		Write: Block,
		WriteValidations: boolean?
	)
		local Value = Declaration.Value
		local Tokens = Declaration.Tokens
		local Variable = Variable or "Value"

		local Range = Value.Range
		local Class = Value.Class
		local Components = Value.Components
		local Primitive = Tokens.Primitive.Value
		local IsVariableSize = (Range and Range.Max ~= Range.Min)

		local function GenerateValidation(Block: Block, Variable: string)
			if Block == Write and WriteValidations ~= true then
				return
			end

			if Block == Write and Type ~= "any" then
				Block:Compare(`typeof({Variable})`, `"{Type}"`, "Not")
					:Line(`error(\`Expected {Variable} to be of type {Type}, got \{type({Variable})} instead.\`)`)
					:End()
			end

			if not AssertGenerator then
				return
			end

			if Block == Read and Strict.Floats and FLOAT_TYPES[Primitive] then
				--> A range with finite bounds already rejects NaN and +-inf
				local Bounded = Range ~= nil and Range.Min > -math.huge and Range.Max < math.huge
				if not Bounded then
					Block:Line(NonFiniteCheck({ Variable }))
				end
			end

			if Block == Read and Strict.Strings and Primitive == "string" then
				Block:Line(`if utf8.len({Variable}) == nil then error("Expected a valid UTF-8 string") end`)
			end

			if Range then
				local Assert = AssertGenerator(Variable, Range.Min, Range.Max)
				if not IsVariableSize and Assert.Exact then
					Block:Line(Assert.Exact)
				else
					--> Reads of unsigned numbers and of lengths are never negative: a lower bound
					--> of 0 needs no check there (floats keep it, it also rejects NaN)
					local NeverNegative = Block == Read
						and Range.Min <= 0
						and (Type == "string" or Type == "buffer" or Primitive == "u8" or Primitive == "u16" or Primitive == "u32")
					if not NeverNegative then
						Block:Line(Assert.Lower)
					end
					Block:Line(Assert.Upper)
				end
			elseif Primitive == "Instance" and Class then
				local Assert = AssertGenerator(Variable, Class)
				if Block == Write then
					Block:Compare(Variable, "nil", "Not"):Multiline(Assert.Exact, Block.Indent + 1):End()
				else
					Block:Multiline(Assert.Exact, Block.Indent)
				end
			end
		end

		GenerateValidation(Write, Variable)
		Prefab.Read(Variable, Read, Range, Components)
		Prefab.Write(Variable, Write, Range, Components)
		GenerateValidation(Read, Variable)
	end
end

local function GenerateNumberGenerator(
	Type: string,
	Size: number,
	Assert: AssertGenerator
): (TypePrefab, { Type: string, Generate: Generate })
	local Prefab = {
		Read = function(Variable: string, Block: Block)
			Block:Line(`{Block:Declare(Variable)} = buffer.read{Type}({RECIEVE_BUFFER}, {Block:Read(Size)})`)
		end,
		Write = function(Value: string, Block: Block)
			Block:Line(`buffer.write{Type}({SEND_BUFFER}, {Block:Allocate(Size)}, {Value})`)
		end,
	}

	local Primitive = {
		Type = "number",
		Generate = GeneratePrimitivePrefab("number", Prefab, Assert),
	}

	return Prefab, Primitive
end

--> Numbers
Types.u8, Primitives.u8 = GenerateNumberGenerator("u8", BYTE, Asserts.integer)
Types.u16, Primitives.u16 = GenerateNumberGenerator("u16", SHORT, Asserts.integer)
Types.u32, Primitives.u32 = GenerateNumberGenerator("u32", INTEGER, Asserts.integer)

Types.i8, Primitives.i8 = GenerateNumberGenerator("i8", BYTE, Asserts.integer)
Types.i16, Primitives.i16 = GenerateNumberGenerator("i16", SHORT, Asserts.integer)
Types.i32, Primitives.i32 = GenerateNumberGenerator("i32", INTEGER, Asserts.integer)

Types.f32, Primitives.f32 = GenerateNumberGenerator("f32", FLOAT, Asserts.float)
Types.f64, Primitives.f64 = GenerateNumberGenerator("f64", DOUBLE, Asserts.float)

Types.f16 = {
	Read = function(Variable: string, Block: Block)
		local Offset = Block:Read(HALF_FLOAT)
		Block:Declare(Variable, true)
		--> Normal: (0x400 + mantissa) * 2^(exponent - 25), subnormal: mantissa * 2^-24.
		--> In a do block so repeated f16 reads do not pile up registers.
		Block:Line("do")
		Block:Lines({
			`local Encoded = buffer.readu16({RECIEVE_BUFFER}, {Offset})\n`,
			"local Exponent = Encoded // 0x400 % 0x20\n",
			"local Result = Encoded % 0x400\n",
			"if Exponent == 0 then\n",
			"	Result *= 0.000000059604644775390625\n",
			"elseif Exponent == 0x1F then\n",
			"	Result = if Result == 0 then math.huge else 0 / 0\n",
			"else\n",
			"	Result = math.ldexp(Result + 0x400, Exponent - 25)\n",
			"end\n",
			`{Variable} = if Encoded >= 0x8000 then -Result else Result\n`,
		}, Block.Indent + 1)
		Block:Line("end")
	end,
	Write = function(Value: string, Block: Block)
		local Allocation = Block:Allocate(HALF_FLOAT)
		Block:Compare(Value, "65504", "Greater")
			:Line(`buffer.writeu16({SEND_BUFFER}, {Allocation}, 0b0_11111_0000000000)`)
			:Branch("Conditional", Value, "-65504", "Less")
			:Line(`buffer.writeu16({SEND_BUFFER}, {Allocation}, 0b1_11111_0000000000)`)
			:Branch("Conditional", Value, Value, "Not")
			:Line(`buffer.writeu16({SEND_BUFFER}, {Allocation}, 0b1_11111_0000000001)`)
			:Branch("Conditional", Value, "0", "Equals")
			:Line(`buffer.writeu16({SEND_BUFFER}, {Allocation}, 0)`)
			:Branch("Default")
			:Lines({
				--> Same bits as the reference encoder (truncating), without math.log
				`local Absolute = math.abs({Value})\n`,
				"local _, Exponent = math.frexp(Absolute)\n",
				"local Biased = Exponent + 14\n",
				"local Result\n",
				"if Biased > 0 then\n",
				"	Result = math.floor(math.ldexp(Absolute, 11 - Exponent)) % 0x400 + Biased * 0x400\n",
				"else\n",
				"	Result = math.round(math.ldexp(math.floor(math.ldexp(Absolute, 11 - Exponent)), Exponent + 13)) % 0x400\n",
				"end\n",
				`if {Value} < 0 then Result += 0x8000 end\n`,
			}, Block.Indent + 1)
			:Line(`buffer.writeu16({SEND_BUFFER}, {Allocation}, Result)`)
			:End()
	end,
}

Primitives.f16 = {
	Type = "number",
	Generate = GeneratePrimitivePrefab("number", Types.f16, Asserts.float),
}

--> Boolean
do
	Types.boolean = {
		Read = function(Variable: string, Block: Block)
			Block:Line(`{Block:Declare(Variable)} = (buffer.readu8({RECIEVE_BUFFER}, {Block:Read(BYTE)}) == 1)`)
		end,
		Write = function(Value: string, Block: Block)
			Block:Line(`buffer.writeu8({SEND_BUFFER}, {Block:Allocate(BYTE)}, {Value} and 1 or 0)`)
		end,
	}

	Primitives.boolean = {
		Type = "boolean",
		Generate = GeneratePrimitivePrefab("boolean", Types.boolean),
	}
end

--> String
do
	Types.string = {
		Read = function(Variable: string, Block: Block, Range: NumberRange?)
			--> Fixed size string
			if Range and Range.Min == Range.Max then
				Block:Line(
					`{Block:Declare(Variable)} = buffer.readstring({RECIEVE_BUFFER}, {Block:Read(Range.Min)}, {Range.Min})`
				)
				return
			end

			local Upper = Range and Range.Max or (2 ^ 16 - 1)
			local LengthType = GetTypeToUse(Upper)

			LengthType.Read("Length", Block)
			Block:Line(`{Block:Declare(Variable)} = buffer.readstring({RECIEVE_BUFFER}, Read(Length), Length)`)
		end,
		Write = function(Value: string, Block: Block, Range: NumberRange?)
			if Range and Range.Min == Range.Max then
				Block:Line(`buffer.writestring({SEND_BUFFER}, {Block:Allocate(Range.Min)}, {Value}, {Range.Min})`)
				return
			end

			local Upper = Range and Range.Max or (2 ^ 16 - 1)
			local LengthType = GetTypeToUse(Upper)

			Block:Line(`local Length = #{Value}`)
			LengthType.Write("Length", Block)
			Block:Line(`Allocate(Length)`)
			Block:Line(`buffer.writestring({SEND_BUFFER}, {SEND_POSITION}, {Value}, Length)`)
		end,
	}

	Primitives.string = {
		Type = "string",
		Generate = GeneratePrimitivePrefab("string", Types.string, Asserts.string),
	}
end

--> Vector
do
	Types.vector = {
		Read = function(Variable: string, Block: Block, _, Components: { string }?)
			local Prefab: TypePrefab = Types.f32
			if Components then
				Prefab = Types[Components[#Components]] or Prefab
			end

			Prefab.Read("X", Block)
			Prefab.Read("Y", Block)
			Prefab.Read("Z", Block)
			if Strict.Floats and (Components == nil or FLOAT_TYPES[Components[#Components]]) then
				Block:Line(NonFiniteCheck({ "X", "Y", "Z" }))
			end
			Block:Line(`{Block:Declare(Variable)} = Vector3.new(X, Y, Z)`)
		end,
		Write = function(Value: string, Block: Block, _, Components: { string }?)
			local Prefab: TypePrefab = Types.f32
			if Components then
				Prefab = Types[Components[#Components]] or Prefab
			end

			Block:Line(`local Vector = {Value}`)
			Prefab.Write("Vector.X", Block)
			Prefab.Write("Vector.Y", Block)
			Prefab.Write("Vector.Z", Block)
		end,
	}

	Primitives.vector = {
		Type = "Vector3",
		Generate = GeneratePrimitivePrefab("Vector3", Types.vector, Asserts.vector),
	}
end

--> Buffer
do
	Types.buffer = {
		Read = function(Variable: string, Block: Block, Range: NumberRange?)
			if Range and Range.Min == Range.Max then
				local Length = Range.Max
				Block:Line(`{Block:Declare(Variable)} = buffer.create({Length})`)
				Block:Line(`buffer.copy({Variable}, 0, {RECIEVE_BUFFER}, {Block:Read(Length)}, {Length})`)
				return
			end

			local Upper = Range and Range.Max or (2 ^ 16 - 1)
			local LengthType = GetTypeToUse(Upper)
			LengthType.Read("Length", Block)
			if Strict.Sizes then
				--> Before buffer.create, so a forged length cannot make the server allocate it
				Block:Line(`if Length > buffer.len({RECIEVE_BUFFER}) - RecieveCursor then error("Buffer length exceeds the packet") end`)
			end
			Block:Line(`{Block:Declare(Variable)} = buffer.create(Length)`)
			Block:Line(`buffer.copy({Variable}, 0, {RECIEVE_BUFFER}, Read(Length), Length)`)
		end,
		Write = function(Value: string, Block: Block, Range: NumberRange?)
			if Range and Range.Min == Range.Max then
				Block:Line(`buffer.copy({SEND_BUFFER}, {Block:Allocate(Range.Max)}, {Value}, 0, {Range.Max})`)
				return
			end

			local Upper = Range and Range.Max or (2 ^ 16 - 1)
			local LengthType = GetTypeToUse(Upper)
			Block:Line(`local Length = buffer.len({Value})`)
			LengthType.Write("Length", Block)
			Block:Line(`Allocate(Length)`)
			Block:Line(`buffer.copy({SEND_BUFFER}, {SEND_POSITION}, {Value}, 0, Length)`)
		end,
	}

	Primitives.buffer = {
		Type = "buffer",
		Generate = GeneratePrimitivePrefab("buffer", Types.buffer, Asserts.buffer),
	}
end

--> CFrame
do
	Types.CFrame = {
		Read = function(Variable: string, Block: Block, _, Components: { string }?)
			local Prefab: TypePrefab = Types.f32
			if Components then
				Prefab = Types[Components[1]]
			end

			Types.vector.Read("Position", Block, nil, Components)
			Prefab.Read("rX", Block)
			Prefab.Read("rY", Block)
			Prefab.Read("rZ", Block)
			if Strict.Floats and (Components == nil or FLOAT_TYPES[Components[1]]) then
				Block:Line(NonFiniteCheck({ "rX", "rY", "rZ" }))
			end
			Block:Line(`{Block:Declare(Variable)} = CFrame.new(Position) * CFrame.fromOrientation(rX, rY, rZ)`)
		end,
		Write = function(Value: string, Block: Block, _, Components: { string }?)
			local Prefab: TypePrefab = Types.f32
			if Components then
				Prefab = Types[Components[1]]
			end

			Types.vector.Write(`{Value}.Position`, Block, nil, Components)
			Block:Line(`local rX, rY, rZ = {Value}:ToOrientation()`)
			Prefab.Write("rX", Block)
			Prefab.Write("rY", Block)
			Prefab.Write("rZ", Block)
		end,
	}

	Primitives.CFrame = {
		Type = "CFrame",
		Generate = GeneratePrimitivePrefab("CFrame", Types.CFrame),
	}
end

--> Color3
do
	Types.Color3 = {
		Read = function(Variable: string, Block: Block)
			local R = Block:Read(BYTE)
			local G = Block:Read(BYTE)
			local B = Block:Read(BYTE)
			Block:Line(
				`{Block:Declare(Variable)} = Color3.fromRGB(buffer.readu8({RECIEVE_BUFFER}, {R}), buffer.readu8({RECIEVE_BUFFER}, {G}), buffer.readu8({RECIEVE_BUFFER}, {B}))`
			)
		end,
		Write = function(Value: string, Block: Block)
			Block:Line(`local Color = {Value}`)
			Types.u8.Write("Color.R * 255", Block)
			Types.u8.Write("Color.G * 255", Block)
			Types.u8.Write("Color.B * 255", Block)
		end,
	}

	Primitives.Color3 = {
		Type = "Color3",
		Generate = GeneratePrimitivePrefab("Color3", Types.Color3),
	}
end

--> DateTime
do
	Types.DateTime = {
		Read = function(Variable: string, Block: Block)
			local UnixTimestamp = Block:Read(DOUBLE)
			if Strict.Floats then
				Block:Line(`{Block:Declare("Timestamp")} = buffer.readf64({RECIEVE_BUFFER}, {UnixTimestamp})`)
				Block:Line(NonFiniteCheck({ "Timestamp" }))
				Block:Line(`{Block:Declare(Variable)} = DateTime.fromUnixTimestamp(Timestamp)`)
				return
			end
			Block:Line(
				`{Block:Declare(Variable)} = DateTime.fromUnixTimestamp(buffer.readf64({RECIEVE_BUFFER}, {UnixTimestamp}))`
			)
		end,
		Write = function(Value: string, Block: Block)
			Block:Line(`local DateTime = {Value}`)
			Types.f64.Write(`DateTime.UnixTimestamp`, Block)
		end,
	}

	Primitives.DateTime = {
		Type = "DateTime",
		Generate = GeneratePrimitivePrefab("DateTime", Types.DateTime),
	}
end

--> DateTimeMillis
do
	Types.DateTimeMillis = {
		Read = function(Variable: string, Block: Block)
			local UnixTimestampMillis = Block:Read(DOUBLE)
			if Strict.Floats then
				Block:Line(`{Block:Declare("Timestamp")} = buffer.readf64({RECIEVE_BUFFER}, {UnixTimestampMillis})`)
				Block:Line(NonFiniteCheck({ "Timestamp" }))
				Block:Line(`{Block:Declare(Variable)} = DateTime.fromUnixTimestampMillis(Timestamp)`)
				return
			end
			Block:Line(
				`{Block:Declare(Variable)} = DateTime.fromUnixTimestampMillis(buffer.readf64({RECIEVE_BUFFER}, {UnixTimestampMillis}))`
			)
		end,
		Write = function(Value: string, Block: Block)
			Block:Line(`local DateTimeMillis = {Value}`)
			Types.f64.Write(`DateTimeMillis.UnixTimestampMillis`, Block)
		end,
	}

	Primitives.DateTimeMillis = {
		Type = "DateTime",
		Generate = GeneratePrimitivePrefab("DateTime", Types.DateTimeMillis),
	}
end

--> BrickColor
do
	Types.BrickColor = {
		Read = function(Variable: string, Block: Block)
			local Number = Block:Read(SHORT)
			Block:Line(`{Block:Declare(Variable)} = BrickColor.new(buffer.readu16({RECIEVE_BUFFER}, {Number}))`)
		end,
		Write = function(Value: string, Block: Block)
			Block:Line(`local BrickColor = {Value}`)
			Types.u16.Write("BrickColor.Number", Block)
		end,
	}

	Primitives.BrickColor = {
		Type = "BrickColor",
		Generate = GeneratePrimitivePrefab("BrickColor", Types.BrickColor),
	}
end

--> Instance
do
	Types.Instance = {
		Read = function(Variable: string, Block: Block)
			--Block:Line("RecieveInstanceCursor += 1")
			Block:Line(`{Block:Declare(Variable)} = RecieveInstances[RecieveInstanceCursor]`)
		end,
		Write = function(Value: string, Block: Block)
			Block:Line(`table.insert(SendInstances, {Value} or Null)`)
		end,
	}

	Primitives.Instance = {
		Type = function(Declaration)
			return Declaration.Value.Class
		end,
		Generate = GeneratePrimitivePrefab("any", Types.Instance, Asserts.Instance),
	}
end

--> unknown
do
	Types.unknown = {
		Read = function(Variable: string, Block: Block)
			Block:Line("RecieveInstanceCursor += 1")
			Block:Line(`{Block:Declare(Variable)} = RecieveInstances[RecieveInstanceCursor]`)
		end,
		Write = function(Value: string, Block: Block)
			Block:Line(`table.insert(SendInstances, if {Value} == nil then Null else {Value})`)
		end,
	}

	Primitives.unknown = {
		Type = "any",
		Generate = GeneratePrimitivePrefab("any", Types.unknown),
	}
end

local function SetStrict(Floats: boolean, Strings: boolean, Sizes: boolean)
	Strict.Floats = Floats
	Strict.Strings = Strings
	Strict.Sizes = Sizes
end

--> Bytes on the wire of each primitive, before any variable-size part
local COMPONENT_BYTES = { u8 = 1, i8 = 1, u16 = 2, i16 = 2, f16 = 2, u32 = 4, i32 = 4, f32 = 4, f64 = 8 }
local FIXED_BYTES = { boolean = 1, Color3 = 3, DateTime = 8, DateTimeMillis = 8, BrickColor = 2 }

--> The fewest bytes and instance slots a value of this type can take on the wire
local function MinimumSize(Declaration: any): (number, number)
	local Kind = Declaration.Type
	local Value = Declaration.Value
	if Kind == "Primitive" then
		local Primitive = Declaration.Tokens.Primitive.Value
		local Range = Value.Range
		local Components = Value.Components
		if COMPONENT_BYTES[Primitive] then
			return COMPONENT_BYTES[Primitive], 0
		elseif FIXED_BYTES[Primitive] then
			return FIXED_BYTES[Primitive], 0
		elseif Primitive == "string" or Primitive == "buffer" then
			if Range and Range.Min == Range.Max then
				return Range.Min, 0
			end
			local Upper = Range and Range.Max or (2 ^ 16 - 1)
			local Prefix = if Upper <= 255 then 1 elseif Upper <= 65535 then 2 else 4
			return Prefix + (Range and Range.Min or 0), 0
		elseif Primitive == "vector" then
			local Component = Components and Components[#Components] or "f32"
			return 3 * (COMPONENT_BYTES[Component] or 4), 0
		elseif Primitive == "CFrame" then
			local Position = Components and Components[#Components] or "f32"
			local Rotation = Components and Components[1] or "f32"
			return 3 * (COMPONENT_BYTES[Position] or 4) + 3 * (COMPONENT_BYTES[Rotation] or 4), 0
		elseif Primitive == "Instance" or Primitive == "unknown" then
			return 0, 1
		end
		return 0, 0
	elseif Kind == "Enum" or Kind == "Optional" then
		if Kind == "Optional" then
			local Of = Value.Of
			if Of.Type == "Primitive" and Of.Tokens.Primitive.Value == "Instance" then
				return 0, 1
			end
		end
		return 1, 0
	elseif Kind == "Map" then
		return 2, 0
	elseif Kind == "Set" then
		local Bytes = 0
		local Remaining = #Value.Values
		while Remaining > 0 do
			local Partition = math.min(Remaining, 32)
			Bytes += if Partition <= 8 then 1 elseif Partition <= 16 then 2 else 4
			Remaining -= Partition
		end
		return Bytes, 0
	elseif Kind == "Struct" or Kind == "Tuple" then
		local Bytes, Instances = 0, 0
		for _, Field in Value.Values do
			local FieldBytes, FieldInstances = MinimumSize(Field)
			Bytes += FieldBytes
			Instances += FieldInstances
		end
		return Bytes, Instances
	elseif Kind == "TagEnum" then
		local Bytes, Instances = math.huge, math.huge
		for _, Variant in Value.Values do
			local VariantBytes, VariantInstances = MinimumSize(Variant)
			Bytes = math.min(Bytes, VariantBytes)
			Instances = math.min(Instances, VariantInstances)
		end
		if Bytes == math.huge then
			Bytes, Instances = 0, 0
		end
		return 1 + Bytes, Instances
	elseif Kind == "Array" then
		local Range = Value.Range
		local Count = Range and Range.Min or 0
		local Bytes, Instances = MinimumSize(Value.Of)
		local Prefix = 0
		if Range and Range.Min ~= Range.Max then
			Prefix = if Range.Max <= 255 then 1 elseif Range.Max <= 65535 then 2 else 4
		end
		return Prefix + Count * Bytes, Count * Instances
	end
	return 0, 0
end

return {
	Strict = Strict,
	SetStrict = SetStrict,
	MinimumSize = MinimumSize,
	Types = Types,
	Asserts = Asserts,
	Primitives = Primitives,
	Structures = Structures,
	GetTypeToUse = GetTypeToUse,
	GetTypeToUseByBits = GetTypeToUseByBits,
}
