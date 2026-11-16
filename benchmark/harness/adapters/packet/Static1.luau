return { -- Packet's Static1 list (u8 index on the wire), set to the benchmark's enum names.
	-- match_state Phase
	"Warmup", "Kickoff", "Play", "Goal", "HalfTime", "FullTime",
	-- match_state Stance
	"Idle", "Jogging", "Sprinting", "Dribbling", "Tackling", "Diving",
	-- client_input ActionKind
	"Shoot", "Pass", "Tackle", "Header", "Emote",
}
