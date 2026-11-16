--!optimize 2
-- per_player for Lync (see adapters/blink/schemas/per_player.blink).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lync = require(ReplicatedStorage:WaitForChild("Lync"))
local U8, U16, U32 = Lync.int(0, 255), Lync.int(0, 65535), Lync.int(0, 4294967295)

return {
	Lync = Lync,
	net = Lync.define("per_player", {
		Wallet = Lync.packet(U32),
		Notify = Lync.packet(Lync.str(0, 64)),
		Inventory = Lync.packet(Lync.array(Lync.struct({ Item = U16, Count = U8 }), 0, 16)),
		PlayerFlags = Lync.packet(Lync.bitfield({ "Muted", "Spectating", "Captain", "Ready", "Away", "Premium" })),
		BoostApplied = Lync.packet(Lync.struct({
			Kind = U8,
			Duration = Lync.optional(Lync.f32()),
			Source = Lync.optional(U16),
		})),
	}),
}
