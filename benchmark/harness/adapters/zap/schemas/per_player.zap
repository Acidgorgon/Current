-- per_player: small reliable events addressed to one player at a time
-- (Fire(player, ...)), five different event types per player per frame.
-- Zap equivalent of adapters/blink/schemas/per_player.blink.
-- Differences: Zap has no bitfield `set` of named flags (its `set` is a
-- dynamic map of keys to true), so Flags is a struct of 6 booleans (Zap packs
-- booleans into a shared bit byte); Notify is string.binary(..64) (Blink's
-- string is not UTF-8 validated either).
opt server_output = "@SERVER_OUTPUT@"
opt client_output = "@CLIENT_OUTPUT@"
opt write_checks = false

type InventoryDelta = struct {
    Item: u16,
    Count: u8,
}

type Flags = struct {
    Muted: boolean,
    Spectating: boolean,
    Captain: boolean,
    Ready: boolean,
    Away: boolean,
    Premium: boolean,
}

type Boost = struct {
    Kind: u8,
    Duration: f32?,
    Source: u16?,
}

event Wallet = {
    from: Server,
    type: Reliable,
    call: SingleSync,
    data: u32,
}

event Notify = {
    from: Server,
    type: Reliable,
    call: ManyAsync,
    data: string.binary(0..64),
}

event Inventory = {
    from: Server,
    type: Reliable,
    call: SingleSync,
    data: InventoryDelta[0..16],
}

event PlayerFlags = {
    from: Server,
    type: Reliable,
    call: SingleSync,
    data: Flags,
}

event BoostApplied = {
    from: Server,
    type: Reliable,
    call: ManySync,
    data: Boost,
}
