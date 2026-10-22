---
title: Controls & Commands
description: Every player control and chat command on NCM Online, generated from the game's own Help catalogue.
status: live
---

# Controls & Commands

NCM is played through keys and menus. Chat commands exist as a backup and for a few small things, but nothing in NCM
should need typing. Use the search box in the menu to find a command.

## Keys

| Key | Controller | What it does |
|---|---|---|
| <kbd>F6</kbd> | <kbd>Start</kbd> | NCM Menu: Driver File, Race Guide, Paddock, Market, Exchange, Machine Index, Devices, Messages, Help |
| hold <kbd>B</kbd> | hold <kbd>Start</kbd> | Quick menu: aim and release for Hub, Race graph, Call a race, Map, GPS |
| <kbd>F5</kbd> | quick menu | Call a custom street race |
| <kbd>F7</kbd> | — | At the grid: snap to your exact starting spot |
| <kbd>F8</kbd> | quick menu | Live race graph |
| <kbd>F9</kbd> | — | Engineering panel (service, parts, Workshop) |
| <kbd>F10</kbd> | — | Machine Index |
| <kbd>Tab</kbd> / <kbd>Caps Lock</kbd> | — | Scanner (hold on a car within 60 m to discover it) |
| <kbd>X</kbd> / <kbd>Z</kbd> / hold <kbd>G</kbd> | — | While scanning: next hack / previous hack / upload ([experimental](systems/experimental.md)) |
| hold <kbd>E</kbd> | hold <kbd>X</kbd> | Interact: get in your car, connect to an Autofixer, talk to Paddock people |
| <kbd>Esc</kbd> | <kbd>Back</kbd> | Close an NCM panel |
| arrows, <kbd>Enter</kbd> | D-pad, Confirm | Move and select inside NCM menus |

Function keys can collide with other mods' bindings. If one does nothing, check your other mods first.

## The Help catalogue

This table is **generated from the game's own Help page** (`ncm/core/player/help.lua`), the single list NCM uses to
tell players what they can do. If it changes in the game, it changes here at the next build.

{{generated:commands}}

## Other player commands

Small commands that are not in Help. All are safe to use; none affects other players.

| Command | What it does |
|---|---|
| `/ncm.refuel` | Fill the tank when parked at a pump in your car. €$2 a litre. |
| `/ncm.fuel` | Route your GPS to the nearest fuel station. |
| `/ncm.balance` | Print your balance in chat. |
| `/ncm.results` | Your last five results. |
| `/ncm.best` | Your best time per route. |
| `/ncm.withdraw` | Leave a race you entered but have not started (same as Withdraw at the venue). |
| `/ncm.tower` | Toggle the timing tower. |
| `/ncm.names` | Toggle names over NPC race cars. |
| `/ncm.whatsnew` | Reopen the How to Play / patch notes panel. |
| `/ncm.alpha` | Print the alpha contract, today's capabilities and the newest release in chat. |
| `/ncm lost`, `/ncm docs` | Orientation help, listed on the Help page. |

**Not listed on purpose:** server-console, administrator, QA and debugging commands. They are refused for players or
only work from the server console. Developers can find them with
`grep -rn RegisterCommand ncm/online/resources`.
