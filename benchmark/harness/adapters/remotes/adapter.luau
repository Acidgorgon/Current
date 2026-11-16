--!optimize 2
-- Plain-RemoteEvent baseline ("no library"): one RemoteEvent (or
-- UnreliableRemoteEvent where the Blink schema is Unreliable) per event,
-- created by the server under ReplicatedStorage.Remotes and found by clients
-- with WaitForChild. Luau values and tables are fired as they are
-- (FireClient / FireAllClients / FireServer) and listeners connect straight to
-- OnClientEvent / OnServerEvent. No serialization and no batching: every
-- Fire is one remote call.
--
-- Each schema's modules live in adapters/remotes/modules/<schema>/ and return
-- the contract API themselves; fire functions are one-line wrappers around
-- the remote's method call (the call a game would write at the call site).
--
-- two_way runs natively: a RemoteEvent works in both directions.
--
-- Caveat: the mock does not model Roblox's C++ cost of serializing table
-- arguments, so this adapter's CPU numbers are a lower bound; its wire bytes
-- are the mock's estimate of Roblox's encoding (string keys sent in full,
-- 9 bytes per number). See README.md, "Caveats".

local A = ... -- { Mock = Mock, outDir = string, benchRoot = string }

local Adapter = {}

function Adapter.compile(schema: string, side: "server" | "client")
	local dir = `{A.outDir}/{schema}`
	if readfile(`{dir}/ok`) == nil then
		return nil, `schema {schema} was not built (see {dir}/compile.log)`
	end
	local path = `{dir}/{side}.luau`
	if readfile(path) == nil then
		return nil, `remotes adapter has no {side} module for schema {schema}`
	end
	A.Mock.compileFile(path)
	return { schema = schema, side = side, path = path }
end

function Adapter.start(handle, env)
	return env:requireFile(handle.path)
end

return Adapter
