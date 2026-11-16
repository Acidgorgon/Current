--!optimize 2
-- client_input for Packet (see adapters/blink/schemas/client_input.blink).
-- Differences: Buttons is a struct of Boolean8 (no set type); Input is sent
-- reliably (Packet has no unreliable channel).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packet = require(ReplicatedStorage:WaitForChild("Packet"))

return {
	Input = Packet("Input", {
		Seq = Packet.NumberU8,
		Dir = Packet.Vector3F32,
		Buttons = {
			Sprint = Packet.Boolean8,
			Shoot = Packet.Boolean8,
			Pass = Packet.Boolean8,
			Tackle = Packet.Boolean8,
			Jump = Packet.Boolean8,
			Dive = Packet.Boolean8,
		},
	}),
	PlayerAction = Packet("PlayerAction", { Kind = Packet.Static1, Target = Packet.NumberU16, Power = Packet.NumberF32 }),
}
