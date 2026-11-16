--!optimize 2
-- client_input for Lync (see adapters/blink/schemas/client_input.blink).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lync = require(ReplicatedStorage:WaitForChild("Lync"))
local U8, U16, U32 = Lync.int(0, 255), Lync.int(0, 65535), Lync.int(0, 4294967295)

return {
	Lync = Lync,
	net = Lync.define("client_input", {
		Input = Lync.packet(Lync.struct({
			Seq = U8,
			Dir = Lync.vec3(),
			Buttons = Lync.bitfield({ "Sprint", "Shoot", "Pass", "Tackle", "Jump", "Dive" }),
		})):unreliable(),
		PlayerAction = Lync.packet(Lync.struct({
			Kind = Lync.enum({ "Shoot", "Pass", "Tackle", "Header", "Emote" }),
			Target = U16,
			Power = Lync.f32(),
		})),
	}),
}
