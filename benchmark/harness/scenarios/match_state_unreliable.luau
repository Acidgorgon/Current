-- match_state, Unreliable variant (SingleSync listener): FireAll of the full
-- 22-player snapshot to 44 clients every frame.
local H = ...
return H.import("scenarios/common/match_state.luau", H)("Unreliable")
