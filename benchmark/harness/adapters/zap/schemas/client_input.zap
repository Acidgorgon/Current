-- client_input: every client streams its input each frame (Unreliable) and
-- occasionally sends a reliable gameplay action.
-- Zap equivalent of adapters/blink/schemas/client_input.blink.
-- Difference: Buttons is a struct of 6 booleans (Zap has no bitfield set of
-- named flags; Zap packs the booleans into a shared bit byte).
opt server_output = "@SERVER_OUTPUT@"
opt client_output = "@CLIENT_OUTPUT@"
opt write_checks = false

type Buttons = struct {
    Sprint: boolean,
    Shoot: boolean,
    Pass: boolean,
    Tackle: boolean,
    Jump: boolean,
    Dive: boolean,
}

type ActionKind = enum { Shoot, Pass, Tackle, Header, Emote }

type InputFrame = struct {
    Seq: u8,
    Dir: vector(f32, f32, f32),
    Buttons: Buttons,
}

type Action = struct {
    Kind: ActionKind,
    Target: u16,
    Power: f32,
}

event Input = {
    from: Client,
    type: Unreliable,
    call: SingleSync,
    data: InputFrame,
}

event PlayerAction = {
    from: Client,
    type: Reliable,
    call: ManyAsync,
    data: Action,
}
