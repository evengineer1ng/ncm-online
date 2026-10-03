# NPC economy audit: "when you see SOLD OUT, where did they go?"

> **STATUS: CURRENT** - authority for: *the NPC economy's actual state, as measured on dev* - affirmed 2026-10-02
> Authority map: [INDEX.md](../INDEX.md) - classified 2026-10-02 (L297)

Measured 2026-10-02 against the live dev database and server logs. The world audited is `ncm-devbox`; the same
database also holds a stale world, `ncm-dev`, which is left out. Re-run any time with
`powershell -NoProfile -ExecutionPolicy Bypass -File tools/npc-economy-audit.ps1`. It is read-only and writes
`tools/open77/server/npc-economy-audit-<stamp>.txt`. The figures here come from
`npc-economy-audit-20261002-215746.txt`.

## The answer

**No. SOLD OUT cannot say where they went, because nothing went anywhere.**

- **Every autofixer vehicle shelf has never held a car.** Each of the 44 autofixer production lines has ticked
  18-60 times and minted **0**. Every one of those ticks wanted to mint (`ticks_wanting_but_zero` = all of them).
- **Only `base_market` has ever had stock:** 7 MaiMai, 5 Galena and 4 Hella (the last minted on 2026-09-24).
- **One vehicle has ever been sold, in the whole world.** That was the owner's Archer Hella, #4, on 2026-09-24.
  No NPC has ever bought a vehicle.
- **The cause (probable, confirmed when fixed, KB-311).** `NcmOwnership.manufacture`
  (`ncm_league/server/ownership.lua:236-244`) writes `allocation_slot` as `NULLIF(?, '')` with an integer slot.
  Under the server's `STRICT_TRANS_TABLES`, comparing an INT to `''` is "Truncated incorrect DOUBLE value", and
  inside an INSERT that is error **1292**. The INSERT is statement 1 of the 33-statement birth transaction (the
  car plus its 11 factory parts), so no car is born. The line arrived in commit `44c22d6` on 2026-09-26; minting
  stopped after 09-24, and every line added since has never minted. This is KB-281.

"SOLD OUT · 0/4" at Arroyo is therefore a line that has never produced. The market reads "available = 0" as sold
out. It is a cardboard wall with no stock decrement behind it at all.

## What NPCs actually did

The `npc_money` ledger holds every NPC market movement ever:

| who | what | count | total |
|---|---|---|---|
| independent persons | part purchases | 161 | −€$191,550 |
| teams | anything | **0** | 0 |
| anyone | vehicle purchases | **0** | 0 |
| anyone | Exchange settlements | **0** | 0 |

### A traced purchase, end to end: Parth Grewal (p01290), independent, street_c

1. **18:52:48:** bought a sport `power_unit`, asset `039b9e44`, at `autofixer_coastview_01` for €$2,400.
   - Transfer row written; `npc_money` row −2,400.
   - Cash is now €$1,809, real and persistent.
2. **Why:** `PaddockMarkets.shop` came round to them on its 5-minute cursor, and power unit was their weakest
   area. That is the whole reason.
3. **Compatibility:** "sport tier, a family that serves power_unit". No car model was consulted.
   - The part's `manufacturer_key` is `autofixer_coastview_01`: the shop, not a maker.
4. **Where it went:**
   - `component_asset.location_kind = 'npc_fitted'`, `machine_asset_id = NULL`. It is fitted to a person, not a car.
   - Their car is `{power_unit 3, aero 3, chassis 3, tires 2}` plus 3,120 eddies of power-unit "progress". The
     part became `price × 1.3` development money; **no level was gained**.
5. **Physical race, 19:36:** p01290 spawned as `Vehicle.ncm_racer_v_standard2_villefort_cortes`.
   - **Six of the race's independents** spawned as the same Cortes.
   - The record is `Hash.pick(tier pool, "livecar", org.id)` (`ncm_paddock/server/live.lua:251`), and an
     independent's key is the constant `"none"`.
   - Pace's scales are the same for every NPC (drive ×1.25, brakes ×1.30, drag ×0.80).
   - **Nothing they bought reached the car on the road.**

### The re-buy vacuum: Gi-Tae Myung (p01226) and Carlo Gonzalez (p01227)

- **p01226 owns four structure parts.**
  - A **sport** structure, fitted since 00:52.
  - Then three identical **street** Archer structures, bought at 15:15, 15:56 and 16:55. Two are in storage;
    the third is fitted *alongside* the sport part.
  - So they downgraded and kept both. Cash: €$393.
- **p01227 owns three identical street Makigai cooling parts** (two stored). Cash: €$443.
- **The cause.**
  - The shopping cursor restarts at the first independents on every server boot. The 15:15, 15:56 and 16:55
    purchases are boots.
  - `npc_market.displaced` treats an equal-tier part as replaceable.
  - Nothing checks that a better part of that family is already fitted.
- 25 owners hold such duplicates (audit C3).

## The six areas

### 1. Ownership and provenance: **exists for parts; nothing to trace for cars**

- **Parts are serialized assets with a real owner principal.** Every NPC purchase is one guarded transaction:
  - shelf row claimed (`sold_to_principal`);
  - asset owner set;
  - transfer row;
  - cash debited;
  - `npc_money` row.

  See `ncm_paddock/server/markets.lua:92-115`. This is the strongest part of the system.
- **The vehicle path has the same shape** (`buyVehicle`). It has never run, because no car exists to buy.
- **Teams own no parts.** All 161 NPC-held parts belong to independents (audit E1).
- **Missing:**
  - which car a part is on;
  - which driver a team car is assigned to (teams own no cars);
  - why a transaction happened.

### 2. The 11-part car: **disconnected at the purchase**

- **Players:** an 11-part `machine_configuration` on a `vehicle_asset`. Wear and service exist, and
  `ncm_world/handling` turns the parts into grip/drive/brake scales on the car you drive.
- **NPCs:** `paddock.car` is four abstract levels (`core/paddock/car.lua`).
  - A part is converted to development eddies (`Car.invest`) and parked as `npc_fitted` with no machine.
  - Levels drive the **sim and qualifying only** (`Car.performance` → `paddock.sim`).
  - The physical car is a hash of the team id with uniform Pace scales.
- **The chain breaks three times:**
  - the part is not on a car;
  - the levels are not the car;
  - the physical car is not the NPC's.

### 3. Purchase eligibility: **family + tier only**

- `npc_market.choose` asks whether the family serves the needed area and whether the tier suits the racer's tier.
- It never asks about manufacturer/model compatibility (`parts.compat` exists, for players).
- It never checks whether something better is already fitted, so it buys downgrades.
- The independents' vehicle rule (`cash ≥ 9000 and performance < 45`) has no "already owns a car" guard. A
  street car lifts the levels only to 4 (performance 40), so once production works the same NPC would buy car
  after car.

### 4. Money: **real balances, but leaking and pooling**

- **Independents (244 active, avg €$2,858, max €$6,079).**
  - Money comes almost entirely from a one-time seed of €$1,500-6,000 (`seedCash`).
  - Purses to independents total **€$15,277** over 1,033 results, about €$15 a race.
  - They have spent €$191,550, so they are **burning their seed money down**. When it's gone they stop.
  - They have no expenses besides parts: no entry fees, repairs or fuel.
- **Teams (170 active).** Cash comes in from genesis, sponsors and purses, and goes out on wages and upkeep.
  - Premier teams average **€$2.8M** (max €$3.77M); pro teams €$556k.
  - **Teams have never bought a part**, and the weekly `invest_dev` has never reached a shelf. Their money pools.
  - No team has folded.
- **Wages vanish.**
  - Team wages leave the team every day, but all 640 team drivers hold **€$0**.
  - The wage is debited and credited to no one.
  - That is synthetic bookkeeping: a sink into nothing.
- **Purses don't add up.** €$303k paid to teams across 4,003 results is far below the team balances; those are
  mostly genesis cash and sponsors.

### 5. Intent: **a heuristic, no goals**

- An independent shops because the cursor reached them, for whatever area is weakest.
- A team "invests" from the owner's weekly decision.
- Nothing models repair, replacement, a class change, a championship target, a wrecked car, or trading.
- Nothing records why on the transaction.

### 6. Sinks and lifecycle: **thin**

- **NPC parts never wear or fail.** A fitted part stays fitted forever unless an upgrade displaces it.
- **Teams lose a quarter step per area each season** (`Car.depreciate`, `life.lua:516`). Independents never do.
- **Stored parts can be posted on the Exchange.**
  - Teams posted 170 "wants" and persons 55 posts.
  - **Zero settlements ever.** Teams own no parts to offer, and nobody fills their wants.
- **There is no resale downmarket, scrap, or retirement of machinery.**
- **Production of vehicles is broken** (above). Part production runs, and NPCs drain it at up to 2 an hour per
  market (`npcPartsPerMarketHour`).

## The cardboard walls

1. SOLD OUT on vehicles = never produced (SQL 1292, KB-311).
2. The NPC car is four levels, not a car (`paddock.car`).
3. Fitted parts are fitted to a person, not a machine (`machine_asset_id NULL`).
4. The physical racer is `Hash(org)`; every independent in a tier shares one model (`"none"`).
5. Pace scales are uniform for every NPC; owned parts never touch the physical car.
6. A restart makes the same independents re-buy the same parts (cursor reset + equal-tier "displaced").
7. Downgrades are bought beside a better fitted part.
8. Team wages leave the team and arrive nowhere.
9. Teams accumulate millions and never spend them in a market.
10. Independents live on a one-time seed; purses are about €$15.
11. NPC parts never wear; nothing leaves service except by being displaced.
12. 225 Exchange posts and zero settlements.

## What exists and works (the bones)

- Serialized assets with owner principals.
- One-transaction purchases with idempotency keys.
- An NPC money ledger.
- A real vehicle production ledger with supply profiles that react to sellouts.
- The Exchange's gated settlement.
- The player 11-part machine with wear, service and handling.

Every door below cuts into these. None needs a parallel system.

## Doors to cut (ranked; for the owner to choose)

1. **Fix vehicle production (KB-311).** Write `allocation_slot` as a plain integer and re-check every
   `NULLIF(?, '')` on a numeric column. This is small and unblocks every market observation.
2. **Stop the vacuums.**
   - Restart-safe shopping (a persisted last-shopped time per NPC).
   - Never buy a part equal to or worse than the one fitted.
   - "Owns a car" guard on vehicles.
3. **One car model.**
   - Every NPC race car is a real `vehicle_asset` with the same 11-part configuration as a player's.
   - Purchases are installed on that machine.
   - `paddock.car` levels are derived from it.
   - The bubble spawns the model the NPC owns.
   - Pace takes per-car drive/brake/grip from `parts.handling`, which is a Pace build. This is the big one.
4. **Money that circulates.**
   - Wages arrive at drivers.
   - Independents pay entry fees and repairs and earn real purses.
   - Teams spend on development through the shelves, and can go broke.
5. **Intent.**
   - A goal per actor: repair, upgrade the current car, replace a wreck, move class.
   - Each purchase carries its reason and goal.
   - Eligibility uses `parts.compat`.
6. **Sinks.**
   - NPC part wear through `parts.wear` on raced distance.
   - Worn parts are retired to the Exchange or scrap.
   - Cars are sold downmarket.
7. **Provenance surfaces.** "SOLD OUT · 0/4 · Last batch: 4 units · Majestic Auto Sport 2 · Omega Elite 1 ·
   Privateer 1", read from `market_inventory`, then Wire/Scanner hooks.
