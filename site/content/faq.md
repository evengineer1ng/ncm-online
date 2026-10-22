---
title: FAQ
description: Answers to the questions new NCM Online players ask first.
---

# FAQ

### What is NCM Online?
A multiplayer motorsports server for Cyberpunk 2077 running on OPEN//77. It turns Night City into a persistent racing
world: scheduled races, an NPC league, serialized cars, engineering, fuel, weather and an economy. See the
[home page](index.md).

### Is this the same as the NCM mod on Nexus Mods?
No, but they are related. **Night City Motorsports** on Nexus is the single-player mod NCM started as. **NCM Online**
is the multiplayer branch, built on OPEN//77, and it is where NCM is actively developed. Work here also informs a
future **NCM 3.0** single-player release, which is not NCM Online. See [The NCM Family](about.md).

### What is OPEN//77?
A multiplayer platform for Cyberpunk 2077 with its own launcher and community servers. NCM Online is one of those
servers. [open2077.net](https://open2077.net)

### Is NCM Online free?
Yes. You need your own copy of Cyberpunk 2077 on PC and the OPEN//77 launcher. NCM charges nothing.

### Do I need extra mods?
None that you install by hand. NCM's required mods (its native plugins plus loaders like ArchiveXL, TweakXL and
Codeware) are installed by the OPEN//77 launcher when you join. It shows you the list first.

### Can I play when nobody else is online?
Yes. The Paddock NPC league races on its own calendar, NPC racers fill empty grid places around start time, and
there are time trials. See [NPC Racing](systems/npc-racing.md).

### Are there NPC racers?
Yes: about 870 NPC drivers in teams across several tiers, with careers, cars, money and news. Near you they drive
physically on the road. Far from any player, their races are simulated and labelled that way.

### Do I need a steering wheel?
No. Keyboard and controller both work. Wheels, pedals and custom rigs are supported through NCM Rig Bridge.

### Can I use a controller or keyboard?
Yes. <kbd>Start</kbd> opens the NCM Menu on a controller, the D-pad navigates, Confirm selects and Back closes. On a
keyboard, <kbd>F6</kbd>, arrows and <kbd>Enter</kbd>. See [Controls](commands.md).

### How do I get a car?
F6 → MARKET, buy a base car, then F6 → MACHINE INDEX → select it → CALL VEHICLE. Hold <kbd>E</kbd> at it to get in.

### How do I make money?
Race in scheduled events: they charge an entry fee and pay on completion and placement, with bonuses for field size
and clean driving. Practice, qualifying and custom street races pay nothing. You can also sell Workshop production
and trade with other drivers.

### How do I enter a race?
Find it in the Race Guide, drive to its venue, enter there, then join the grid before it closes. *Interested* only
tracks it. See [Racing](systems/racing.md).

### What happens if I run out of fuel?
The engine stops. Get to a pump and use `/ncm.refuel`; `/ncm.fuel` routes you to the nearest station. You can also
call another car you own.

### Why can't my car enter this event?
Events have regulations: a class, a specific model (a MaiMai cup admits MaiMais), or a ground-only rule that keeps
flying machines out. The Race Guide shows eligibility before you travel. Also check that entry has not closed.

### Is the server persistent?
Yes. Your money, cars, parts, damage, knowledge and results are stored on the server. But this is an **alpha**:
progression resets for NCM 1.0 and may reset before then, and each [Race Week](systems/race-week.md) has its own
reset rules.

### Is NCM open source?
Yes, under the [MIT License](https://github.com/evengineer1ng/ncm-online/blob/main/LICENSE). The source is on
[GitHub](https://github.com/evengineer1ng/ncm-online). Bundled third-party components keep their own licences.

### Can I run or build my own version?
You may, under the MIT License. Be realistic about what it is: an actively developed server codebase with
project-specific assumptions, not a turnkey framework. Start with [Developers](developers/index.md) and
[Running NCM](developers/running.md).

### Where do I report a bug?
In game: F6 → HELP → report a problem. Or on
[GitHub Issues](https://github.com/evengineer1ng/ncm-online/issues/new/choose). Check
[Known Issues](known-issues.md) first. For security problems, see the
[security policy](https://github.com/evengineer1ng/ncm-online/blob/main/SECURITY.md), not a public issue.

### Is there a Discord?
No. This site and GitHub are NCM's public home, and the game itself takes problem reports.
