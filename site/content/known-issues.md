---
title: Known Issues
description: Current known problems on NCM Online, with workarounds, so you can tell what is known from what is new.
---

# Known Issues

NCM Online is an **alpha**. This page lists the known problems players are most likely to meet, so you can tell
"this is known" from "something new broke". Last reviewed **2026-10-22**.

The complete defect ledger, with every investigation, is public at
[`docs/ncm-online/KNOWN_BUGS.md`](https://github.com/evengineer1ng/ncm-online/blob/main/docs/ncm-online/KNOWN_BUGS.md).
Security problems are not listed anywhere public; see the
[security policy](https://github.com/evengineer1ng/ncm-online/blob/main/SECURITY.md).

**Found something new?** F6 → HELP → report a problem, or
[open an issue](https://github.com/evengineer1ng/ncm-online/issues/new/choose).

## Progression

| Issue | What to know |
|---|---|
| **Progression is temporary.** | Alpha money, machines, parts and records reset for NCM 1.0, and further resets can happen before then. This is a rule, not a bug. |
| **Race Week reset not yet fully live.** | The end-of-run reset of wallets and cars has run as a dry run so far. Its first live execution is waiting on a server maintenance step. See [Race Week](systems/race-week.md). |

## Racing and the HUD

| Issue | Workaround |
|---|---|
| The interaction card only shows the keyboard key (E). | On a controller, hold X. |
| `/ncm.gps` sets the venue, but the minimap route may not draw until you open and close the map once. | Open and close the map. The race HUD does this automatically at grid forming. |
| Some routes are withheld while their racing lines are rebuilt, so the calendar can look thinner at times. | None needed; the calendar only posts routes that pass its checks. |

## Performance

| Issue | Workaround |
|---|---|
| A session can slow down after a while in game, and NCM panels may stop updating. | Rejoin the server. Report it with F6 → HELP if it keeps happening. |

## Cars and engineering

| Issue | Workaround |
|---|---|
| No wings, spoilers or splitters can be attached yet: the platform's attachable catalogue has none. | None yet. |
| F9 → BUILD can say "Build is not running on this server" when it is. | Build is reserved for future player infrastructure and has nothing to do yet. |
| Manual gearbox feel and sound are still being tuned. | Report anything that feels wrong, with the car and its gear count. |

## Wheels and controllers

| Issue | Workaround |
|---|---|
| With a configured wheel unplugged, older Rig Bridge versions re-acquired every controller every 2 seconds and buttons stopped working. | Fixed in Rig Bridge 0.1.9, which the launcher installs; confirmation in play is pending. Remove bindings to devices you don't have. |
| A wheel-rim pause button can stop working when Rig Bridge loses the rim. | Use F6 on the keyboard or Start on a controller. |
| Cyberpunk sees no devices at all. | Check device-hiding tools such as HidHide; they can block the game. |

## Experimental systems

Flight, AVs and the high-altitude systems are the least stable parts of NCM. Known problems include:

- AVs rocking in flight, wrong speed readouts and running out of fuel unexpectedly;
- thrust dropping out at high altitude, and view glitches there;
- slow orbital energy drift in the off-screen simulation.

All of these are tracked as KB-429 to KB-479 in the ledger. None of it affects normal racing.
