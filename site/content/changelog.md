---
title: Changelog
description: NCM Online's development history: in-game release notes and the project's milestones since September 2026.
---

# Changelog

NCM Online started development around **18 September 2026**, as public OPEN//77 servers became available. It has
changed almost daily since. This page has two parts:

1. **Release notes as the game shows them.** Generated from the in-game patch notes, so they match what players were
   told.
2. **Project milestones.** The larger changes, reconstructed from the git history and the public
   [decision record](https://github.com/evengineer1ng/ncm-online/blob/main/docs/ncm-online/DECISION_RECORD.md).
   Dates are the day a change was decided or shipped, as recorded. Where only the build is known, nothing more
   exact is claimed.

## In-game release notes

{{generated:releases}}

## Project milestones

### October 2026

- **22 Oct:** NCM Online's source and this website are prepared for public release under the MIT License. Online
  development resumes after a five-day pause. [Infrastructure]
- **17 Oct:** Work pauses on Online while a native single-player host for NCM 3.0 is started. It is now on hold
  again. [Infrastructure]
- **13 Oct:** The Race Week reset is decided to go live from the end of run 4. Flying machines are barred from
  street races. Rig Bridge 0.1.9 stops re-acquiring every controller every 2 seconds. [Racing, Hardware]
- **12 Oct:** AVs fly on NCM engineering. Markets that behave, and cars on the Exchange. The experimental propulsion
  laboratory. [Experimental, Economy]
- **10 Oct:** NCM Gearbox 0.4.0 slices every manual gear across seven native gears. The **Workshop**: reverse
  engineering, fabrication, design promotion and production runs on one F9 bench. Codeware joins the required mods.
  [Engineering]
- **9 Oct:** **F9 Engineering** becomes its own docked panel. Self repair costs materials only, workmanship rolls
  per section, and the job sheet is drawn in ink. The slipstream becomes a continuous aerodynamic wake. Scouting
  reports for team managers. [Engineering, NPCs]
- **8-9 Oct:** **Race Week Live**, NCM's own in-game radio station, goes live. Persistent **vehicle damage**
  through the week, for players and NPCs alike, with physical trunk cargo. Online moves to Baseline 3: the
  development server's full tree. [World, Engineering]
- **4 Oct:** NPC race cars become real cars with owners, and money circulates through the Paddock. NCM Gearbox,
  NCM's own manual transmission, is designed and its first phases built. The Observer spectator mode is built, as
  are Race Week's verdicts and seven-day timeline. [NPCs, Economy, Racing]
- **3 Oct:** **Race Week** is specified and built: the three-day run, advertised speed limits, a continuous social
  curve, championships crowned at hour 72, the hall of champions, the collapse (as a dry run). Online is updated
  from the development server with its mod stack. [Racing]
- **1-2 Oct:** **Paddock races become the player-facing organised races**: qualifying at the venue, mixed NPC/human
  grids presented as one field, fair grids, F7 grid snap, DNS at green, the flag and a penalty ceremony. Authored
  ovals with rebuilt racing splines. OPEN//77 platform upgrade to 2.31.21+op77.124. [Racing, NPCs]

### September 2026

- **29 Sep:** Fuel and refuelling. Autofixer terminals as local markets. Map markers for stations and NCM
  locations. Arriving where you left off. **The Paddock**, NCM's NPC motorsport world, is adopted, and its first
  phases are built on the development server. [World, NPCs]
- **28 Sep:** The Scanner. The quick menu. The **Player Exchange**. Health regeneration. Keyboard-only menus.
  [Cars, Economy]
- **27 Sep:** **Economy v1**: entry fees, payouts, itemised receipts, refunds, Race Tags and the clean-driving
  bounty. [Economy]
- **26 Sep:** Lap ghosts in practice and time trials. [Racing]
- **25 Sep:** Serialized **parts** with fitment rules; the **Machine Index**. [Engineering, Cars]
- **23 Sep:** The project moves into a git repository. [Infrastructure]
- **22 Sep:** Session weather synchronised for everyone. Multi-vendor wheel and rig support with force feedback. NCM
  locations on the map and a real GPS race route. [World, Hardware]
- **~18-21 Sep:** Reconnaissance of OPEN//77, the first server experiments, and the first tester sessions. [Infrastructure]

## Adding to this page

- **Player-facing release notes** are authored once, in
  `ncm/online/resources/ncm_world/client/landing_content.lua`. The game shows them on its landing panel, and this
  site generates the list above from the same file.
- **Milestones** are added here, in `site/content/changelog.md`, newest first, one line each, with a category.
  A server restart is not a release.
