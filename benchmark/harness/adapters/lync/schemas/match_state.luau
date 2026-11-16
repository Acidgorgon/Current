--!optimize 2
-- match_state for Lync (see adapters/blink/schemas/match_state.blink).
-- Lync packs fields to the bit: u8/u16 as int ranges (8/16 bits), enums in
-- 3 bits, the Players count (0..32) in 6 bits. Vel is f32 (Lync has no f16).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lync = require(ReplicatedStorage:WaitForChild("Lync"))
local U8, U16, U32 = Lync.int(0, 255), Lync.int(0, 65535), Lync.int(0, 4294967295)

local PlayerState = Lync.struct({
	Id = U16,
	Pos = Lync.vec3(),
	Vel = Lync.vec3(),
	Stamina = U8,
	State = Lync.enum({ "Idle", "Jogging", "Sprinting", "Dribbling", "Tackling", "Diving" }),
})
local MatchState = Lync.struct({
	Ball = Lync.vec3(),
	Clock = Lync.f32(),
	HomeScore = U8,
	AwayScore = U8,
	Phase = Lync.enum({ "Warmup", "Kickoff", "Play", "Goal", "HalfTime", "FullTime" }),
	Players = Lync.array(PlayerState, 0, 32),
})

return {
	Lync = Lync,
	net = Lync.define("match_state", {
		MatchReliable = Lync.packet(MatchState),
		MatchUnreliable = Lync.packet(MatchState):unreliable(),
	}),
}
