---
title: Weather & Time
description: A shared sky, wet roads that dry, and Night City on US Eastern real time.
status: live
---

# Weather & Time

## Weather

- **The sky is world state.** Everyone in a session sees the same weather, and NCM never makes weather up for a story.
- **Rain soaks the road.** Less grip, longer braking, and a car that gets loose under heavy throttle. Roads dry over a
  few minutes.
- **Races show their weather** in the Race Guide before you commit.

{{status:experimental}} Grip and braking under weather are still being tuned.

## Time

- **Night City runs on US Eastern real time.** Night is night where the city is.
- **The Paddock keeps a daily rhythm:** street racing at night, sanctioned racing by day.
- Race Week boundaries are at 12:00 Eastern. See [Race Week](race-week.md).

## For developers

- Weather: `ncm_league/server/` (`NcmWeather`), core `ncm/core/world/conditions*`; authority `docs/ncm-online/11_WEATHER.md`.
- Clock: core `world.clock` (`eastern(utc)`), DECISION_RECORD L231.
