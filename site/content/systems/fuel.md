---
title: Fuel
description: Fuel burn, the gauge, finding a station and refuelling on NCM Online.
status: live
---

# Fuel

- **Your machine burns fuel as you drive.** The level sits under the odometer on your HUD, and it is stored with
  the car on the server.
- **Fuel stations are on your map.** `/ncm.fuel` sets your GPS to the nearest one and tells you how far it is.
- **Refuel** by parking at the pumps, in your car, and using `/ncm.refuel`. It fills the tank at **€$2 a litre** and
  tells you how much it cost.
- **Running out** stops the engine. Drive (or coast) to a pump, or call another car you own.

## For developers

- Server: `ncm/online/resources/ncm_world/server/fuel.lua` (burn, persistence, the station list, both commands).
- The HUD gauge is drawn by `ncm_world/client/`.
