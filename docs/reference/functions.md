# Functions

Functions are request and response, Current's version of `RemoteFunction`: a client invokes, the server answers, and the client gets the server's return value. They go through the reliable channel, batched like reliable events.

```blink
function GetInventory {
    Yield: Coroutine,
    Data: u16,
    Return: struct {
        Items: u16[..100],
        Coins: u32
    }
}
```

| Field | Values | Required |
|---|---|---|
| [`Yield`](#yield) | `Coroutine`, `Future`, `Promise` | yes |
| [`Data`](#data-and-return) | any type or type pack | no |
| [`Return`](#data-and-return) | any type or type pack | no |
| [`Rate`](#rate) | a positive number | no |

Functions are always invoked by a client and answered by the server.

## `Yield`

How the client waits for the answer.

- `Coroutine`: `Invoke` yields the calling thread and returns the values.
- `Future`: `Invoke` returns a future. Needs [`option FutureLibrary`](./options#futurelibrary-and-promiselibrary); [redblox's Future](https://github.com/red-blox/Util/tree/main/libs/Future) is recommended.
- `Promise`: `Invoke` returns a promise. Needs [`option PromiseLibrary`](./options#futurelibrary-and-promiselibrary); [evaera's Promise](https://github.com/evaera/roblox-lua-promise) (or a fork) is recommended.

## `Data` and `Return`

`Data` is what the client sends, `Return` is what the server sends back. Both work like an event's [`Data`](./events#data): any type, a type pack in parentheses, or nothing. The request is validated on the server before your handler runs.

## `Rate`

A per-player limit in calls per second for this function, enforced on the server. Burst is max(`Rate`, 1). Over it, the call is answered with an error (so the client's `Invoke` fails instead of hanging) and reported as `RateLimited` (see [Security](/guide/security#per-event-rates)).

```blink
function Purchase {
    Yield: Coroutine,
    Data: u16,
    Return: boolean,
    Rate: 2
}
```

This field is Current only; upstream Blink rejects it.

## Using functions in Luau

::: code-group

```lua [server.luau]
-- One handler per function; it runs in its own thread and may yield
Net.GetInventory.On(function(Player, Page)
    local Data = Profiles[Player]
    return { Items = Data.Items, Coins = Data.Coins }
end)
```

```lua [client (Coroutine)]
local Inventory = Net.GetInventory.Invoke(1)
print(Inventory.Coins)
```

```lua [client (Future)]
local Future = Net.GetInventory.Invoke(1)
local Success, Inventory = Future:Await()
```

```lua [client (Promise)]
Net.GetInventory.Invoke(1)
    :andThen(function(Inventory)
        print(Inventory.Coins)
    end)
    :catch(warn)
```

:::

## Errors and limits

- **Handler errors.** If the server handler errors, the server prints a warning naming the function and the client's call fails: `Invoke` errors with `There was an exception while processing "GetInventory".` (a `Promise` rejects with it).
- **Before a handler exists.** Requests that arrive before `On` is called are queued and answered once a handler is set; more than 256 queued requests print a warning, and on the server at most 1024 are queued per function (calls beyond that are answered with an error).
- **256 calls in flight.** A client can have at most 256 invocations waiting for an answer at once. Invoking beyond that errors instead of sending.
- **Server to client.** There is no server-invokes-client function (just as Roblox discourages `InvokeClient`). Use a pair of events, or a [two-way event](/guide/two-way-events), instead.
