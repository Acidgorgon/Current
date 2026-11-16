# Schema language

A schema is a text file (`.blink`, `.current` or `.txt`) of declarations: [options](./options) at the top, then types, [events](./events), [functions](./functions), scopes and imports. The language is Blink's, unchanged, so anything written for Blink works here.

```blink
option ServerOutput = "net/server.luau"
option ClientOutput = "net/client.luau"

type Health = u8(0..100)

struct Player {
    Name: string(3..20),
    Health: Health,
    Position: vector
}

event Spawned {
    From: Server,
    Type: Reliable,
    Call: ManyAsync,
    Data: Player
}
```

Comments start with `--`. Keywords are lowercase (`type`, `struct`, `enum`, `map`, `set`, `event`, `function`, `scope`, `import`, `export`, `option`); event and function fields are written `From`, `Type`, and so on.

## Declaring types

| Keyword | Declares | Generics |
|---|---|---|
| `type Name = …` | an alias for any type | no |
| `struct Name { … }` | a [struct](#structs) | yes |
| `enum Name = { … }` / `enum Name = "Tag" { … }` | a [unit](#unit-enums) or [tagged](#tagged-enums) enum | tagged only |
| `map Name = { [K]: V }` | a [map](#maps) | yes |
| `set Name = { … }` | a [set](#sets) | no |

Every declared type becomes an exported Luau type in the generated modules (`Net.Health`, and so on for TypeScript). Types can also be written inline, anywhere a type is expected: `Data: struct { A: u8, B: u8 }`.

## Ranges

Ranges limit numbers, string and buffer lengths, array sizes and vector magnitudes. Values outside the range are rejected when the data is read, so a range on client data is also validation.

| Range | Min | Max |
|---|---|---|
| `0..100` | `0` | `100` |
| `0..` | `0` | no limit |
| `..100` | no limit | `100` |
| `5` | `5` | `5` (exact) |

Ranges may be decimal (`f32(-5.5..10.5)`) or negative (`i8(-5..10)`) where the type allows it.

## Numbers

The name is the kind (`u` unsigned, `i` signed, `f` float) followed by the size in bits, which is also its cost on the wire.

| Type | Size | Min | Max |
|---|---|---|---|
| `u8` | 1 byte | 0 | 255 |
| `u16` | 2 bytes | 0 | 65,535 |
| `u32` | 4 bytes | 0 | 4,294,967,295 |
| `i8` | 1 byte | -128 | 127 |
| `i16` | 2 bytes | -32,768 | 32,767 |
| `i32` | 4 bytes | -2,147,483,648 | 2,147,483,647 |
| `f16` | 2 bytes | -65,504 | 65,504 |
| `f32` | 4 bytes | ±16,777,216 exactly as integers | |
| `f64` | 8 bytes | ±9,007,199,254,740,992 exactly as integers | |

For floats the bit size sets the precision rather than a hard limit; the table lists the largest integer each one represents exactly (`f16` holds integers exactly up to ±2048). Luau numbers are `f64` internally.

::: tip f16
Half-precision floats (2 bytes) are ideal for velocities, angles and other values that don't need much precision. The buffer library has no native `f16`, so Current encodes it itself; it is a little slower to read and write than `f32`.
:::

Bound a number with a [range](#ranges) in parentheses:

```blink
type Health = u8(0..100)
type Percent = f32(0..1)
type UserId = f64
```

## Strings

`string` is a length-prefixed string. Bound its length (in bytes) with a range:

```blink
type UUID = string(36)
type Username = string(3..20)
```

## Booleans

```blink
type Success = boolean
```

## Buffers

`buffer` sends your own serialized bytes while still taking part in Current's batching. Bound its size in bytes with a range:

```blink
type Blob = buffer
type SmallBlob = buffer(..900)
```

## Vectors

`vector` is a Luau `vector` (Roblox `Vector3`). A range bounds its magnitude, and a number type in angle brackets sets the encoding of each component (default `f32`):

```blink
type Position = vector
type Direction = vector(0..1)
type GridCell = vector<i16>
type Velocity = vector<f16>
```

::: warning
Luau stores vectors as three `f32`s, so an encoding larger than `f32` (such as `f64`) adds bytes without adding precision.
:::

## CFrames

`CFrame` sends a position and a rotation. Two number types in angle brackets set the position and rotation encodings:

```blink
type Location = CFrame
type CheapCFrame = CFrame<i16, f16>
```

::: warning
The vector precision limits apply to CFrames too, and an integer rotation encoding zeroes the rotation.
:::

## Other Roblox types

`Color3`, `BrickColor`, `DateTime` (seconds) and `DateTimeMillis` (milliseconds) are supported as they are:

```blink
type TeamColor = Color3
type Created = DateTime
```

## Instances

`Instance` sends a reference to a Roblox instance. Narrow it to a class in parentheses; subclasses are accepted (a `BasePart` accepts a `Part`), and anything else is rejected:

```blink
type AnyInstance = Instance
type Target = Instance(Player)
type Sounds = Instance(Sound)[..10]
```

::: danger Instances can arrive as nil
An instance that does not exist on the receiving side (streamed out, created only on the sender, destroyed in flight) arrives as `nil`. For a non-optional `Instance` that is a read error, and the rest of that packet is dropped. Mark instances that might not exist as [optional](#optionals): `Instance(Model)?`.
:::

## Unknown

`unknown` is any Luau value, sent through Roblox's own serialization. It skips Current's packing and validation, so use it sparingly. For "one of several shapes", use a [tagged enum](#tagged-enums) instead.

```blink
type Anything = unknown
```

## Optionals

Append `?` after the whole type to allow `nil`:

```blink
type MaybeName = string(3..20)?
type MaybeTarget = Instance(Player)?
```

## Arrays

A type followed by square brackets is an array of that type. A range inside the brackets bounds its length; arrays can be nested:

```blink
type Names = string[]
type Squad = f64[1..50]
type Grid = u8[][]
```

## Maps

```blink
map Scores = { [string]: f64 }
map Owners = { [u16]: Instance(Player) }
```

Keys and values can be any type except optionals. Inline, write the keyword in front: `Scores: map { [string]: u8 }` (the same goes for `struct`, `enum` and `set`). Map sizes can't be bounded with a range.

## Sets

A set is a fixed list of names, each `true` or `false` (the Luau type is `{ CanTrade: boolean, … }`). It is sent as a bit field, so it is far smaller than a map:

```blink
set Flags = {
    CanTrade,
    CanChat,
    IsPremium
}
```

```lua
Net.Settings.Fire(Player, { CanTrade = true, CanChat = false, IsPremium = true })
```

## Enums

### Unit enums

A unit enum is one of a list of string values:

```blink
enum CharacterState = { Idle, Walking, Running, Jumping }
```

In Luau the value is the string: `"Idle"`, `"Walking"`, …

### Tagged enums

A tagged enum is one of several struct variants. The string after `=` names the field that holds the variant's tag:

```blink
enum MouseEvent = "Type" {
    Move {
        Delta: vector,
        Position: vector
    },
    Click {
        Button: enum { Left, Right, Middle },
        Position: vector
    }
}
```

```lua
Net.Mouse.Fire({ Type = "Click", Button = "Left", Position = Hit })
```

Tagged enums are how you write unions:

```blink
enum NumberOrString = "Type" {
    Number { Value: f64 },
    String { Value: string }
}
```

which generates `{ Type: "Number", Value: number } | { Type: "String", Value: string }`.

## Structs

A struct is a table with fixed, named fields:

```blink
struct Entity {
    Health: u8(0..100),
    Position: vector,
    Animations: struct {
        First: u8?,
        Second: u8
    }
}
```

### Merging

`..Name` copies the fields of another struct into this one (a table union):

```blink
struct Named {
    Name: string
}

struct Positioned {
    Position: vector
}

struct NamedThing {
    ..Named,
    ..Positioned,
    Id: u16
}
```

## Generics

Structs, maps and tagged enums take type parameters in angle brackets:

```blink
struct Fragment<T> {
    Index: u8,
    Count: u8,
    Data: T
}

map Dictionary<K, V> = { [K]: V }

enum Result<T> = "Kind" {
    Ok { Value: T },
    Err { Message: string }
}

map Scores = Dictionary<string, f64>
enum SaveResult = Result<u32>

event Positions {
    From: Server,
    Type: Unreliable,
    Call: ManySync,
    Data: Fragment<vector[..50]>
}
```

Generic maps and enums are named with `map Name = …` and `enum Name = …`. A generic struct is used directly where a type is expected, as in `Data` above or a struct field.

## Scopes

A scope groups declarations under a name. Scopes see everything declared in the scopes around them.

```blink
type Id = u16

scope Combat {
    type Damage = u8
    event Hit {
        From: Client,
        Type: Unreliable,
        Call: SingleSync,
        Data: (Id, Damage)
    }
}

struct Report {
    Last: Combat.Damage
}
```

In Luau, a scoped event lives in a nested table and a scoped type is prefixed with the scope name:

```lua
Net.Combat.Hit.Fire(Target, 10)
local Amount: Net.Combat_Damage = 10
```

## Imports

`import` pulls in another schema file as a scope named after the file, or after the name given with `as`:

```blink
import "./shared/items"
import "./shared/items" as Items

struct Loadout {
    Primary: items.Weapon,
    Secondary: Items.Weapon
}
```

The path is relative to the importing file, and the extension can be left out. Imports behave like scopes in Luau (`Net.Items.SomeEvent`, `Net.Items_Weapon`). In the Studio plugin, imports only support sibling files (`./name`). `--watch` also watches imported files.

## Exports

`export` in front of a type also generates a `Read` and `Write` pair for it, so you can serialize the type yourself (to save it, send it through another channel, or replicate ECS components):

```blink
export struct SaveData {
    Coins: u32,
    Level: u8
}
```

```lua
local Bytes: buffer = Net.SaveData.Write({ Coins = 10, Level = 2 })
local Data = Net.SaveData.Read(Bytes)
```

Exports don't support `Instance` or `unknown` fields.
