# NCM Online

**Motorsports in Night City**

NCM Online is a multiplayer motorsports and simulation server for **Cyberpunk 2077**, built on
**[OPEN//77](https://open2077.net)**. It turns Night City into a persistent racing world: scheduled races across the
city, a league of NPC teams and drivers that races whether or not anyone is online, serialized cars you own, an
engineering bench, fuel, weather, a conserved economy with receipts, Race Week championships and wheel/rig support.

> **Status: active development, alpha.** Systems change quickly and progression is temporary. The website labels
> every system **LIVE**, **EXPERIMENTAL**, **IN DEVELOPMENT**, **PLANNED** or **HISTORICAL**.

**[Website & player guide](https://evengineer1ng.github.io/ncm-online/)** ·
**[Getting Started](https://evengineer1ng.github.io/ncm-online/getting-started.html)** ·
**[Developer docs](https://evengineer1ng.github.io/ncm-online/developers/index.html)** ·
**[Changelog](https://evengineer1ng.github.io/ncm-online/changelog.html)** ·
**[Known issues](https://evengineer1ng.github.io/ncm-online/known-issues.html)** ·
**[OPEN//77](https://open2077.net)** ·
**[MIT License](LICENSE)**

## Play

Install the OPEN//77 launcher, find **NCM Online** in the server list and join. The launcher installs NCM's required
mods for you. Then press **F6**, buy a base car, call it from Machine Index and enter a race from the Race Guide.
Full guide: [Getting Started](https://evengineer1ng.github.io/ncm-online/getting-started.html).

## What's in it

| System | |
|---|---|
| Racing | Scheduled point-to-point, circuit and oval races; qualifying; mixed NPC/human grids; penalties; settlement |
| The Paddock | A persistent NPC league: teams, drivers, careers, money, news, betting, team management |
| Race Week | Multi-day runs, a social curve, advertised speed limits, championships, a hall of champions, a reset |
| Machines | Serialized cars, Machine Index, the Scanner, persistent condition |
| Engineering | Damage, self and shop repair with workmanship rolls, serialized parts with fitment, the Workshop, manual gearboxes |
| Economy | One ledger, entry fees and payouts, the Market, Autofixer terminals, the player Exchange |
| World | Shared weather, US Eastern real time, fuel, road scars |
| Hardware | NCM Rig Bridge: DirectInput wheels, pedals and rigs with force feedback |
| Presentation | Timing tower, NPC car names, Race Week Live (an in-game radio station) |
| Experimental | Slipstream, vehicle quickhacks, machines built from physical parts, flight, AVs, and stranger things |

## Night City Motorsports, NCM Online and NCM 3.0

- **Night City Motorsports (NCM)** began as a single-player racing mod on Nexus Mods. Its release payload is kept
  in `ncm-localized/`.
- **NCM Online** is the multiplayer branch on OPEN//77: this repository, where NCM is actively developed.
- **NCM 3.0** is a planned single-player release that brings NCM Online's systems back to single player. It is in
  development and on hold. **NCM Online is not NCM 3.0.**

## Repository

| Path | What |
|---|---|
| `ncm/online/resources/` | The OPEN//77 server resources: `ncm_league`, `ncm_world`, `ncm_paddock` and more |
| `ncm/core/` | ncm-core: pure, tested Lua shared by the resources (vendored into them by `tools/ncm-build.ps1`) |
| `ncm/<plugin>/` | Native RED4ext plugins: Carrier, Rig Bridge, Gearbox, Pace, Broadcast, Radio, Audio, Sky, Vision... |
| `docs/ncm-online/` | The design record. Start at `INDEX.md` |
| `tools/` | Build, test, deploy and ops scripts |
| `site/` | The website |

A guided tour: [Repository Map](https://evengineer1ng.github.io/ncm-online/developers/repo-map.html) ·
[Architecture](https://evengineer1ng.github.io/ncm-online/developers/architecture.html).

```powershell
# the offline gate: ncm-core under Lua 5.4 and LuaJIT, resource tests, syntax, sandbox and docs checks
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\ncm-test.ps1
```

This is an actively developed server codebase, not a polished framework. You are welcome to study it, fork it and
build on it under the [MIT License](LICENSE). Bundled third-party components keep their own licences
([THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)).

## Contributing, problems and security

- **Bugs:** report from inside the game (F6 → HELP), or [open an issue](https://github.com/evengineer1ng/ncm-online/issues/new/choose).
- **Contributing:** see [CONTRIBUTING.md](CONTRIBUTING.md).
- **Security:** see [SECURITY.md](SECURITY.md). Please don't open public issues for vulnerabilities.

NCM is a fan project, not affiliated with or endorsed by CD PROJEKT RED or OPEN//77. Cyberpunk 2077 is a trademark
of CD PROJEKT S.A.
