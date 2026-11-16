--!optimize 2
-- match_state for QuickNet (see adapters/blink/schemas/match_state.blink).
-- Enums are Data.literal (u8 index); struct fields go in sorted key order;
-- the Players array length is a u16.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local QuickNet = require(ReplicatedStorage:WaitForChild("QuickNet"))
local D = QuickNet.Data

-- One event: registered on both sides (the server assigns the id), rate limit
-- lifted as BlinkBlox and QuickNet's own benchmarks do. QuickNet rewrites the
-- schema tables it is given, so every event gets fresh ones.
local function event(name: string, unreliable: boolean, ...)
	local object = QuickNet:register(name, ...):SetRateLimit(math.huge, 1)
	if unreliable then
		object = object:Unreliable()
	end
	return object
end

local function MatchState()
	return {
		Ball = D.Vector3F32,
		Clock = D.NumberF32,
		HomeScore = D.NumberU8,
		AwayScore = D.NumberU8,
		Phase = D.literal("Warmup", "Kickoff", "Play", "Goal", "HalfTime", "FullTime"),
		Players = {
			{
				Id = D.NumberU16,
				Pos = D.Vector3F32,
				Vel = D.Vector3F16,
				Stamina = D.NumberU8,
				State = D.literal("Idle", "Jogging", "Sprinting", "Dribbling", "Tackling", "Diving"),
			},
		},
	}
end

return {
	MatchReliable = event("MatchReliable", false, MatchState()),
	MatchUnreliable = event("MatchUnreliable", true, MatchState()),
}
