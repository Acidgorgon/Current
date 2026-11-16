--!optimize 2
-- per_player for Packet (see adapters/blink/schemas/per_player.blink).
-- Differences: no set type (struct of Boolean8, 1 byte per flag); no optional
-- type (Duration/Source use Packet.Any: a type tag byte, then the value in the
-- smallest fitting form; nil is the tag alone); arrays have a u16 length.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packet = require(ReplicatedStorage:WaitForChild("Packet"))

return {
	Wallet = Packet("Wallet", Packet.NumberU32),
	Notify = Packet("Notify", Packet.String),
	Inventory = Packet("Inventory", { { Item = Packet.NumberU16, Count = Packet.NumberU8 } }),
	PlayerFlags = Packet("PlayerFlags", {
		Muted = Packet.Boolean8,
		Spectating = Packet.Boolean8,
		Captain = Packet.Boolean8,
		Ready = Packet.Boolean8,
		Away = Packet.Boolean8,
		Premium = Packet.Boolean8,
	}),
	BoostApplied = Packet("BoostApplied", { Kind = Packet.NumberU8, Duration = Packet.Any, Source = Packet.Any }),
}
