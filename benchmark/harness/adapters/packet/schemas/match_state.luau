--!optimize 2
-- match_state for Packet (see adapters/blink/schemas/match_state.blink).
-- Enums are Static1 (u8 index); Vel is Vector3F24 (3 bytes per component;
-- Packet has no f16 vector); Players length is a u16. Packet has no
-- unreliable channel: MatchUnreliable is sent reliably.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packet = require(ReplicatedStorage:WaitForChild("Packet"))

local function MatchState()
	return {
		Ball = Packet.Vector3F32,
		Clock = Packet.NumberF32,
		HomeScore = Packet.NumberU8,
		AwayScore = Packet.NumberU8,
		Phase = Packet.Static1,
		Players = {
			{
				Id = Packet.NumberU16,
				Pos = Packet.Vector3F32,
				Vel = Packet.Vector3F24,
				Stamina = Packet.NumberU8,
				State = Packet.Static1,
			},
		},
	}
end

return {
	MatchReliable = Packet("MatchReliable", MatchState()),
	MatchUnreliable = Packet("MatchUnreliable", MatchState()),
}
