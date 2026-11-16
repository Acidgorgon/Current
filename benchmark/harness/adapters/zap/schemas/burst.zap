-- burst: one client receives 200 events in a single frame, once through a
-- ManyAsync listener and once through a SingleSync listener.
-- Zap equivalent of adapters/blink/schemas/burst.blink (identical types).
opt server_output = "@SERVER_OUTPUT@"
opt client_output = "@CLIENT_OUTPUT@"
opt write_checks = false

type Hit = struct {
    Id: u16,
    Pos: vector(f32, f32, f32),
    Damage: u8,
}

event HitAsync = {
    from: Server,
    type: Reliable,
    call: ManyAsync,
    data: Hit,
}

event HitSync = {
    from: Server,
    type: Reliable,
    call: SingleSync,
    data: Hit,
}
