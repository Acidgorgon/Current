-- two_way: Zap has no two-way events ("from" is Server or Client only), so the
-- Blink `From: Both` Ping event needs 2 declarations here: PingDown
-- (server -> client) and PingUp (client -> server), same type and call mode.
opt server_output = "@SERVER_OUTPUT@"
opt client_output = "@CLIENT_OUTPUT@"
opt write_checks = false

event PingDown = {
    from: Server,
    type: Reliable,
    call: ManySync,
    data: u32,
}

event PingUp = {
    from: Client,
    type: Reliable,
    call: ManySync,
    data: u32,
}
