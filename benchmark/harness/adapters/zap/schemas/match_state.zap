-- match_state: the 30 Hz authoritative match snapshot of a 22-player football
-- match, broadcast to every client. Sent both as a Reliable and as an
-- Unreliable event (the driver picks one per scenario variant).
-- Zap equivalent of adapters/blink/schemas/match_state.blink.
-- Difference: Zap has no f16, so PlayerState.Vel is vector(f32, f32, f32)
-- (12 bytes per player instead of Blink's 6).
opt server_output = "@SERVER_OUTPUT@"
opt client_output = "@CLIENT_OUTPUT@"
opt write_checks = false

type Phase = enum { Warmup, Kickoff, Play, Goal, HalfTime, FullTime }
type Stance = enum { Idle, Jogging, Sprinting, Dribbling, Tackling, Diving }

type PlayerState = struct {
    Id: u16,
    Pos: vector(f32, f32, f32),
    Vel: vector(f32, f32, f32),
    Stamina: u8,
    State: Stance,
}

type MatchState = struct {
    Ball: vector(f32, f32, f32),
    Clock: f32,
    HomeScore: u8,
    AwayScore: u8,
    Phase: Phase,
    Players: PlayerState[0..32],
}

event MatchReliable = {
    from: Server,
    type: Reliable,
    call: ManyAsync,
    data: MatchState,
}

event MatchUnreliable = {
    from: Server,
    type: Unreliable,
    call: SingleSync,
    data: MatchState,
}
