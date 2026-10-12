# 56 - R&D overhaul: flight parts arrive through manufacturer R&D, not through typing

> **STATUS: SPEC** - Q1-Q6 ruled by the owner on 2026-10-07 (L342). Implementation and live validation are tracked separately.
> Decision: [DECISION_RECORD.md](DECISION_RECORD.md) L341-L342. Authority map: [INDEX.md](INDEX.md).
> Governing docs it builds on: [54_ENGINEERING_II.md](54_ENGINEERING_II.md) §E (lineage), [50_ENGINEERING_ARCHITECTURE.md](50_ENGINEERING_ARCHITECTURE.md), [17_MARKET_NETWORK.md](17_MARKET_NETWORK.md).

**In one paragraph.** On 2026-10-07 the owner ruled (L341) that *"all parts buying defines flight and race potential"*
and that R&D should *"handle flight parts organically"*. Every typed shortcut that changed a Machine was removed, and Deep
and flight shipped to Online. But today's R&D (`parts.rnd`) can only invent **handling scalars** -- a `power_unit 1.18`, a
`brakes 1.24` -- and the five flight components (RP-16, IA-10, AC-6, FD-1, PT-500) exist only as a static table that
development fabricates for free. **So right now no Online player can obtain anything that flies.** This proposal makes
manufacturer R&D the only source of flight hardware: physical designs, derived from lineages, bounded by physics, with
competency that grows and failures that are real, listed on markets and bought with eddies.

**Build status (2026-10-07):** the shared core, migrations 071-072, five physical programmes, database/client spec delivery,
market stock and fitment, Panel Parts purchase tiles, and WIRE release stories are built and headless-green. Single-player
tapes replay missed physical runs in order. Online and dev have been restarted with this code; the live acceptance rows
are `wp/MASTER_TEST.md` §RN1-§RN6, and none has a live gameplay PASS.

---

## 1. What exists today (read before changing anything)

| Piece | Where | What it does | Limitation for flight |
|---|---|---|---|
| Scalar R&D | `ncm/core/parts/rnd.lua` (`logicVersion=1`), run by `ncm_league/server/components.lua` `runRnd` | 3 makers (makigai, thorton, archer), one evaluation per maker every 72 h, 50 % "no candidate", else a family + an `effect` multiplier + price + distribution. Seeded by `partsRndSecret`; claim-nonce idempotent; no catch-up burst. Base-distribution results get `component_supply_state` and go on Base Market. | Families are the 11 factory-interface scalars only. No `propulsor`, `impulse_actuator`, `attitude`, `tank`. A candidate is one number, not a physical device. |
| Flight designs | `ncm/core/engineering/installation.lua` `M.DESIGNS` | 5 authored revision-1 designs with SI physics (`perf`: thrustN, ispS, propellant, heatKw; `thermal`; massKg; envelope; price). `Install.design(id)` is a **static lookup**. | A design not in the table cannot be installed, simulated, or drawn -- an R&D-made design would have no physics. |
| Design rows | `component_design` (seeded by `ncm_world/server/engineering.lua seedDesigns`) | The FK every component asset needs: code, family, price, `fitment_json = {standard="hardpoint.h1"}`. | No column carries the physical spec. |
| Acquisition | `NcmEngineering` fabricate (dev only); Panel -> Parts bench lists `fabricable` (dev only) | Free on dev. On Online: "components come from markets". | No market lists these designs; no production line; no R&D path. |
| Lineage + reverse engineering | `ncm/core/engineering/lineage.lua` (doc 54 §E) | Immutable design points with parents and relations; estimation by knowledge x competency; physics ceilings (`ISP_CEILING`); seeded; failure is real. | Built in core, tested, **not wired to anything that persists or sells**. |
| Competency | `ncm/core/engineering/competency.lua` | 0..1000 internal scale, asymptotic headroom, disciplines incl. `design` and `fabrication`. | Not applied to makers. |

**Online R&D state, read 2026-10-07 (read-only):** 9 runs across the three makers (4 `accepted / novel_tradeoff`, 5
`no_candidate`); `component_design` holds 495 factory, 40 autofixer, 25 launch and 4 rnd designs; next runs
2026-10-08 (makigai), 10-09 (thorton), 10-10 (archer). Supply tiers and ceilings: `parts.catalogue.SUPPLY`.

**Balance warning.** RP-16 carries `ispS = 2000` on `propellant = "fuel"` -- dev balance (owner 2026-10-06 raised thrust
to 30 kN). `engineering.lineage.ISP_CEILING` caps kerosene at 360 s. An R&D generator that honours the ceiling will not
reproduce the dev Hella's flight; the owner must rule which number is the world's (Q3).

## 2. Target shape

### 2.1 Two programme kinds, one scheduler
Keep `runRnd`'s claim/nonce/cadence machinery exactly; dispatch per maker programme:
- **scalar** -- today's `parts.rnd` v1, unchanged and replayable (existing `component_rnd_run` rows must re-evaluate identically).
- **physical** -- new `parts.rnd` v2 path (`logicVersion=2`): the candidate is a **design point** of an `engineering.systems`
  kind (`reaction_engine`, `ground_ram`, `propellant_tank`, an attitude kind ...), produced by `engineering.lineage` from a
  parent, validated by `engineering.systems` and the physics ceilings. Invalid or failed = `no_design` with the reason.

### 2.2 Lineage roots, not a shop of finished parts
The five authored designs become **lineage roots** held by their makers (Zetatech: RP-16, AC-6, FD-1, PT-500; Archer:
IA-10). A physical run picks a root or any later design of that maker's lineage and makes a `successor` or
`derived_from` point: thrust, Isp, mass, heat, envelope and price drawn within the maker's competency band, biased the
doc 54 §E way (benefits low, costs high), physics-capped. Novelty test = not dominated on (thrust/mass, Isp, heat, price)
by any existing design of the same kind -- the physical analogue of `isNovel`.

Whether the roots themselves are ever sold is Q1. "Organically" suggests not: the first flight hardware on a market is
whatever the first successful physical run produced.

### 2.3 Makers and competency
- Add the flight families to makers rather than inventing a new maker: Zetatech (`zetatech`, already the `makerKey`
  of four roots) and Archer (`archer`, already a scalar maker). A new `component_rnd_state` row per (maker, programme).
- Each maker carries a `design` competency (0..1000, `engineering.competency` headroom curve). An accepted run grows it;
  a failed run grows it less. Competency narrows the error band and lowers failure chance (`lineage.errorBand`,
  `lineage.failureChance` with knowledge = `documents`, since a maker owns its own drawings).
- Cadence per programme (proposal: 48 h for physical programmes, offset from the scalar 72 h). Same no-burst rule.

### 2.4 The one structural change: physics comes from the database
`Install.design(id)` must resolve designs it has never seen. Proposal:
- Migration **071**: `component_design.spec_json` (MEDIUMTEXT, nullable) holding the full physical record
  (`perf`, `thermal`, `massKg`, `envelope`, `interface`, `family`, `name`).
- `engineering.installation` gains `M.register(design)` (validated through `engineering.systems`); the static table
  registers itself at load; `ncm_world` registers every `spec_json` row at start and on each new R&D design
  (`ncm:rnd:design` server event + a `GlobalState` revision counter so clients fetch new specs).
- Clients (`client/engineering.lua`, `client/deep.lua`) must get specs from the server, never from the static table only,
  or a bought R&D thruster simulates as nothing. Single player (`ncm_host`, SQLite) inherits this unchanged.

### 2.5 Markets, price and supply
- Physical designs with `distribution = "base"` get `component_supply_state` on Base Market, like scalar ones.
- Price: from physical value, not `Catalogue.priceFor(family, effect)` -- e.g. reaction engines by total impulse per kg
  and thrust; tanks by capacity; a floor so nothing is free. Proposed function `parts.catalogue.pricePhysical(design)`.
- Supply tier by price band (street / sport / premium -> `SUPPLY` ceilings), so expensive hardware is scarce.
- Fitment: the mount standard (`hardpoint.h1`), resolved by `engineering.installation.check` per owned Machine, so
  `marketOfferings`' "fits a car you own" flag works for add-ons too.
- Purchase: the existing `NcmComponents.purchase` transaction is already design-agnostic; it needs `partsEnabled` on.

### 2.6 Surfaces (no typing, no new modal layer)
- Panel -> Parts: Online shows **owned** add-ons and **market** add-ons (dev keeps the `fabricable` list). Buy, then
  mount/facing/remove by the holds the bench already has (KB-363). No chat commands (L341; memory "no chat commands").
- Race Guide / Messages: an accepted physical run is news ("Zetatech released the RP-18 -- 28 kN, 310 s, €$7,900").

### 2.7 NPCs
Paddock NPC buyers (`ncm_paddock/server/markets.lua`) may buy add-ons later; out of scope for the first cut, but the
supply ceiling must assume they will (doc 17 scarcity).

## 3. What Online looks like until this lands
Baseline 3 (L341): Deep, the altitude doorway (snowglobe) and the Racing Week loop are enabled on Online; dev fuel,
dev heat, dev attitude, fabrication and the dev grant are development-only; every typed tuning command is gone.
**Consequence:** an Online Machine has no flight hardware, so it cannot reach Deep under its own power. The first flight
on Online is the first physical R&D design someone buys. Note also: no attitude part exists, and on Online the dev
attitude waiver is off -- a Machine in Deep has no way to turn (Q4).

## 4. Build order (each step: core tests + stub scenario + dev boot; L69 -- nothing is done without a live PASS)
1. `installation.register` + `spec_json` (migration 071) + server->client spec delivery. Static designs still work.
   Test: a design known only from the DB installs, simulates and draws on dev.
2. `parts.rnd` v2 physical evaluation in core (pure, seeded, replayable), lineage-driven, physics-capped, competency-banded.
   Tests: determinism across Lua 5.4 / LuaJIT (KB-343/KB-380 hash rules), v1 replay unchanged, ceilings hold, failure rate.
3. Scheduler dispatch + `component_rnd_state` programme rows + maker competency persistence (migration 072).
4. Physical pricing + supply + `marketOfferings` fitment for add-ons.
5. Panel -> Parts market/owned add-ons on Online; news line.
6. Dev soak with `partsRndSecret` set and cadence shortened by convar; then MASTER_TEST cases (proposed §RD1-§RD6:
   a physical run lands; the design is buyable; bought + mounted it flies; a second client sees it; restart keeps it;
   v1 scalar runs replay identically).

## 5. Owner rulings (L342, 2026-10-07)
- **Q1.** The five roots are lineage references, never direct market stock. Only successful R&D descendants are sold.
- **Q2.** Manufacturers perform the first physical R&D. Player reverse engineering is a later feature and cannot bypass the first Online flight ladder.
- **Q3.** Physical ceilings govern: a fuelled RP-16 class engine is capped at about 360 s, not the dev value of 2000 s. L342 explicitly retires the RP-16's 2000 s and IA-10's 3000 s development balance on the existing revision-1 roots; their fuel use changes on dev. The development fuel waiver remains explicit. Online players never held these roots. Fusion fuel is a separate system.
- **Q4.** Begin with an attitude programme alongside propulsion and tank programmes. Attitude alone is not a flight kit. The attitude waiver stays development-only.
- **Q5.** Target a first buyable flight part within 48 hours and a plausible complete kit within one Racing Week. Measure the actual outcome distribution in the dev soak; a 50% no-candidate roll on serial programmes cannot meet these targets reliably.
- **Q6.** Single player uses the same rules independently per tape, seeded and persisted under that tape's `server_id`. Resolve missed runs in order on return.

## 6. Do not
- Do not reintroduce a typed path to any of this (L341).
- Do not let a client report or choose a design's physics; specs are server truth.
- Do not change `logicVersion=1` behaviour -- existing Online runs must replay.
- Do not grant or seed flight parts to Online players to "get things going"; that is the shortcut L341 removed.
