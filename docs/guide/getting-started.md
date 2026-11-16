# Getting started

This page takes you from an empty folder to a server and a client talking to each other. It assumes the [CLI is installed](./installation); with the [Studio plugin](/reference/plugin) the schema is the same, only the output paths are chosen in Studio instead.

## 1. Write a schema

Create a file called `net.blink` (the `.current` extension works too) next to your project's source folder:

```blink [net.blink]
-- Where to write the generated modules, relative to this file.
-- (Not needed in the Studio plugin, which asks where to put them.)
option ServerOutput = "src/shared/net/server.luau"
option ClientOutput = "src/shared/net/client.luau"

-- Reusable types
type Coins = u32
struct Item {
    Id: u16,
    Name: string(1..32),
    Price: Coins
}

-- The server tells one player what is in the shop
event ShopStock {
    From: Server,
    Type: Reliable,
    Call: SingleAsync,
    Data: Item[..20]
}

-- A client asks to buy an item; the server validates the id before your code runs
event Buy {
    From: Client,
    Type: Reliable,
    Call: SingleAsync,
    Data: u16
}

-- The client asks the server for its balance and waits for the answer
function GetCoins {
    Yield: Coroutine,
    Return: Coins
}
```

Every declaration is explained in the reference: [types](/reference/schema), [events](/reference/events), [functions](/reference/functions) and [options](/reference/options).

## 2. Compile it

Open a terminal in the folder that holds `net.blink` and run:

```sh
current net
```

Current finds `net`, `net.txt`, `net.blink` or `net.current`, and writes `src/shared/net/server.luau` and `src/shared/net/client.luau`. It asks before creating a folder that does not exist; pass `--yes` to skip the prompt. While you are editing the schema, `current net --watch` recompiles on every save (see [CLI](/reference/cli)).

::: warning Don't edit the generated files
They are overwritten on every compile. Change the schema instead. Many projects commit them anyway so that a fresh clone runs without compiling first.
:::

Put the output somewhere both the server and the client can `require`, such as `ReplicatedStorage`. The server module errors if it is required on a client and vice versa.

## 3. Use the generated modules

Each module returns a frozen table with one entry per event and function.

::: code-group

```lua [Server.server.luau]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Net = require(ReplicatedStorage.Shared.net.server)

local SHOP = {
    { Id = 1, Name = "Sword", Price = 100 },
    { Id = 2, Name = "Shield", Price = 75 },
}
local Balances: { [Player]: number } = {}

Players.PlayerAdded:Connect(function(Player)
    Balances[Player] = 250
    Net.ShopStock.Fire(Player, SHOP)
end)

-- Id is already known to be a u16 here: anything else was rejected
Net.Buy.On(function(Player, Id)
    local Item = SHOP[Id]
    if Item and Balances[Player] >= Item.Price then
        Balances[Player] -= Item.Price
    end
end)

-- Functions return the answer to the caller
Net.GetCoins.On(function(Player)
    return Balances[Player] or 0
end)
```

```lua [Client.client.luau]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage.Shared.net.client)

Net.ShopStock.On(function(Items)
    for _, Item in Items do
        print(Item.Name, Item.Price)
    end
    Net.Buy.Fire(Items[1].Id)
end)

-- Yields until the server answers
local Coins = Net.GetCoins.Invoke()
print("I have", Coins, "coins")
```

:::

A few things to know about the generated code:

- **Sends are batched.** Reliable events fired during a frame are packed into one buffer and sent at the end of the frame (on `Heartbeat`). Unreliable events are sent right away. See [Generated API](/reference/generated-api#replication).
- **Events wait for a listener.** A reliable event that arrives before anything is listening is queued and delivered when the first listener connects.
- **Everything is typed.** `Item`, `Coins` and every listener parameter carry their Luau types, so your editor completes them and checks your calls.

## Next steps

- Let both sides fire the same event with [two-way events](./two-way-events).
- Coming from Blink? Read [Migrating from Blink](./migrating-from-blink).
- Browse the [schema language](/reference/schema) for every type you can send.
