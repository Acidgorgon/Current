---
layout: home

hero:
  name: Current
  text: Fast, typed Roblox networking
  tagline: Describe your events once. Current generates buffer-packed server and client modules, with two-way events and validated client data.
  image:
    src: /family/current.svg
    alt: Current
  actions:
    - theme: brand
      text: Get started
      link: /guide/getting-started
    - theme: alt
      text: Install
      link: /guide/installation
    - theme: alt
      text: GitHub
      link: https://github.com/Acidgorgon/current

features:
  - icon: <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M13 2 4 14h7l-1 8 9-12h-7z"/></svg>
    title: Fastest in the benchmarks
    details: The fastest of nine serializing libraries in every benchmark scenario, 2.8x faster than upstream Blink on a 44-player match snapshot (6.2x with ReuseReceiveTables) and 3.4x on 120 events per frame.
    link: /guide/performance
    linkText: See the numbers
  - icon: <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M7 4 3 8l4 4"/><path d="M3 8h14"/><path d="m17 20 4-4-4-4"/><path d="M21 16H7"/></svg>
    title: Two-way events
    details: "From: Both declares one event that the server and clients can both fire and both listen to. It shares one event index, so it costs no more than a one-way event."
    link: /guide/two-way-events
    linkText: Two-way events
  - icon: <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/><path d="m9 12 2 2 4-4"/></svg>
    title: Validated by your schema
    details: Client data is checked against your schema (types, ranges, lengths, instance classes, finite floats, UTF-8) before your listeners run. Per-player size and rate limits stop floods, and a bad packet is dropped and reported, never thrown.
    link: /guide/security
    linkText: Security
---

## Install

::: code-group

```sh [rokit]
rokit add Acidgorgon/current
```

```toml [rokit.toml]
[tools]
current = "Acidgorgon/current@0.1.0"
```

:::

Then write a schema and compile it:

::: code-group

```blink [net.blink]
option ServerOutput = "src/shared/net/server.luau"
option ClientOutput = "src/shared/net/client.luau"

event Ping {
    From: Both,
    Type: Reliable,
    Call: ManyAsync,
    Data: u32
}
```

```sh [terminal]
current net
```

:::

Current reads Blink's schema language, so existing `.blink` files compile unchanged. It is a fork of [Blink](https://github.com/1Axen/blink) by 1Axen: see the [introduction](/guide/introduction) for what it adds.
