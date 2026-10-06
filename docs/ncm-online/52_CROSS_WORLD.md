# 52 - Cross-World: Night City, Los Santos and the Snowglobe between them

> **STATUS: SPEC** - authority for: *the long-term cross-world direction (a possible second NCM racing server on GTA V / FiveM, Snowglobe as a shared protocol, cross-world identity and transfer) and the interface boundaries today's NCM should preserve for it* - owner direction 2026-10-05 (L318 + addendum: one Online Race Week across two cities, SP vs Online topology, the wormhole's two meanings).
> Owner intent, explicitly **not authorised to build**: "DESIGN + ARCHITECTURAL EXPLORATION ONLY. DO NOT BUILD A FIVEM SERVER."
> Public NCM Online remains a Night City racing server first; this does not change current priorities. Ideas: IDEA-1054 to IDEA-1065 (L318), IDEA-1066 to IDEA-1077 (addendum).

## 1. The direction (condensed from the owner's text)

**Two servers, at most.**
- NCM / Night City runs on Cyberpunk 2077 + OPEN//77.
- NCM / Los Santos would run on GTA V + FiveM.
- Each would be a genuine NCM racing simulation in its own right, with NPC and player racing, point-to-point, circuits and ovals, machine index, engineering, serialized parts and machines, dynamic rules, progression through world activity, and in time its own Race Week. It is not a thin proxy.
- There is **no third Snowglobe server.** Snowglobe is a **shared protocol and coordinate domain** that both servers implement.

**Authority stays home.**
- A player who enters Snowglobe stays owned and simulated by their origin server until they explicitly transfer.
- The servers exchange enough state to show each other's entities as **proxies** (non-colliding ghosts at first).
- No engine rigid-body internals are synchronised. Cross-engine collision is not required.

**Transfer is explicit, consensual and transactional:**
1. The source prepares a ticket and serializes the portable state.
2. The source client yields; the destination client launches or connects.
3. An NCM loading or atmospheric-entry presentation covers the runtime switch.
4. The destination validates the ticket and instantiates the player.
5. **Only on acceptance does authority move.**

A failed launch, a crash, a missing game or a rejected ticket must never strand or destroy persistent state. Declining, or not owning the other game, leaves the player in Snowglobe.

**Identity survives; representation may not.** Cross-world continuity preserves semantic identity: machine id, serial, ownership, provenance, history, engineering state, capability, installed parts, wear where transferable, accomplishments and lineage. It does not preserve exact geometry. A machine maps to an approximately analogous local chassis through a **curated correspondence table** ("squint at these two cars"). This is LittleBigPlanet / toybox continuity, not Star Citizen asset literalism.

**Parts may be the most portable objects.** A serialized part has no geometry of its own, so each runtime can implement its mechanical effect locally. Not every part must transfer: some are world-specific, need adaptation, or become a different but analogous component. That is an engineering problem, never a magic inventory converter.

**Machine index across worlds:** one canonical NCM machine identity, with embodiments in Night City, in Snowglobe and in Los Santos.

**Time and setting mismatch is no blocker.** It belongs to the NCM cosmology (seeds, loops, wormholes). There must be understandable transition rules, not a calendar proof.

**Motorsport remains the point.** Los Santos is only worth building as a good NCM racing server first. Cross-world events (atmospheric, orbital, cross-city, launch and landing stages) **emerge**: physical possibility, then discovery, then diffusion, then a viable competitor population, then motorsport, then regulation, then infrastructure. None exists on a fresh seed because the code supports it.

**No spoilers.** A new player should conclude "this is a surprisingly deep Cyberpunk (or FiveM) racing server". There are no locked Los Santos / Moon / Space buttons and no empty flying championships.

**Worlds are not wormholes:**
- Los Santos is another reachable world in the **same** universe.
- A wormhole is a transition to **another seed** (L315 amendment, L316 Q3).
- They may share transfer and persistence plumbing; they stay semantically distinct.

**The proof of concept:**
1. Machine A leaves Night City under OPEN//77 authority; machine B leaves Los Santos under FiveM authority. Both enter Snowglobe.
2. Each server receives the other's canonical state; each client renders the other as a local proxy.
3. The two players rendezvous at the same universe coordinates, see each other and race. Each stays authoritative at home.
4. Then A approaches Los Santos, consents, and reappears in the FiveM NCM world with its identity and history intact.

## 2. The minimum interfaces to preserve

**(a) Canonical identities, minted by NCM and never by an engine:**
- the driver (`ncm_driver_id`);
- the machine (`vehicle_asset.asset_id`);
- the part (`component_asset.asset_id`) and its design (`component_design.design_id`, immutable, with lineage);
- the universe / seed (L316 IDEA-1042).

Engine handles (REDengine EntityIDs, OPEN//77 `vehicleId`s, TweakDB records, FiveM net ids) are **local embodiment handles**, never identity.

**(b) Embodiment is per world.** A machine has zero or more embodiments, each `(asset_id, world, local model, local handle)`. The correspondence between worlds is a curated table keyed by the NCM catalogue key (`vehicle_key`), not by a universal taxonomy.

**(c) Part state splits in two:**

| Universal (travels with the serial) | World adaptation (re-derived by each runtime) |
|---|---|
| `design_id`, lineage, family, tier, effect | fitment and positions (`positions_json`, `fitment_json`: the Night City envelope, L162) |
| provenance: origin `server_id` + its ordinals | how the effect is actuated (Carrier levers here; something else in FiveM) |
| exposure, wear, lifecycle, history | |

**(d) The Snowglobe entity state** (the owner's field list, in `space.universe` terms):

    { ncmDriverId, assetId, seedId, frame, position (universe, metres, double), velocity, orientation,
      capability envelope, visible state, originAuthority (server_id), transfer state, t }

Universe positions never pass through REDengine coordinates. Night City is one **anchor** of `space.universe`; Los Santos would be another.

**(e) Authority** is the `server_id` that owns the canonical row. Transfer is two-phase: prepared, then accepted, then committed. The source keeps authority until the destination acknowledges.

**(f) Proxies** are rendered from the remote server's canonical state. They don't collide and are never simulated as owned.

**(g) Worlds are anchors in one universe; a wormhole is a new seed.**

## 3. What today's tree already preserves (audit, 2026-10-05)

| Boundary | Where | Verdict |
|---|---|---|
| Driver identity | `ncm_league/server/schema/001_identity.lua`: `ncm_driver` (NCM-minted UUID), `ncm_driver_binding(server_id, user_id)` | **open.** Narrowing: `origin ENUM('sp','online')`; a third origin is an ALTER. |
| Machine identity | `015_vehicle_assets.lua`: `asset_id` UUID, `vehicle_key`, `server_id` | **open, one fusion:** `record` (TweakDB) is `NOT NULL` on the identity row, so the Night City embodiment lives inside the identity. |
| Part identity | `031_component_assets.lua`: `component_asset.asset_id` UUID; `component_design` immutable | **mostly open.** Narrowings: serial ordinals are unique per `server_id`; positions and fitment are world adaptation (§2c). |
| Engineering | L314; `ncm/core/engineering/` (`body` describes, `actuate` adapts) | **open.** A FiveM actuator would be a sibling of `actuate`. |
| Universe coordinates | `ncm/core/space/universe.lua` (Earth frame, anchors, bubble, rebase) | **open.** |
| Snowglobe bookkeeping | `ncm_world/server/snowglobe.lua` | **narrowing:** keyed by OPEN//77 `vehicleId`, memory only, forgotten on disconnect (§SG8 log: "removed while in space -- forgotten"). |
| Authority | `server_id` on every persistent row | **open.** |
| Transfer | `vehicle_asset_transfer` is ownership transfer, not world transfer | **nothing closed.** |
| Remote proxies | the Paddock bubble (sim-owned racers rendered near players); Observer (watching without participating) | **precedent exists.** |

## 4. Door-keeping rules for today's work

1. **No new engine-specific columns on identity rows** (`ncm_driver`, `vehicle_asset`, `component_asset`). An engine-specific fact goes in an embodiment or adaptation table, or stays in runtime memory.
2. **A part's serial is always shown with its origin server** (ordinals are per `server_id`).
3. **The next time Snowglobe's server state is touched**, key it by the NCM `asset_id` and carry `{seed, frame, position, velocity, t, originAuthority}`, not the OPEN//77 `vehicleId` alone. Not now.
4. **No Los Santos, space or Moon UI**, and no cross-world events on a default seed.
5. **Engineering stays physical description plus per-runtime actuation** (L314). Nothing in `engineering.body` may name an engine.

## 5. The update (L318 addendum): one Race Week, two cities; SP and Online share rules, not topology

**One Online Race Week; local consequences stay local.**
- If NCM: Los Santos exists, there is conceptually **one** Online Race Week: the same number, start, end, rollover and broad day/phase.
- Night City and Los Santos are two populations generating evidence for it. Each runtime translates its own simulation into a **common evidence vocabulary**, for example racing intensity, public disruption, regulatory pressure, casualties/damage, infrastructure readiness, organization, economic activity, public acceptance, technological capability and participation.
- A **shared resolver** weighs severity, population, confidence, infrastructure, extremes and momentum, not a literal average. One city can pull the shared week shorter or longer.
- **Global clock, local consequences:** the calendar is shared; enforcement, speed tolerance, damage, availability and public mood stay properties of each city's own history ("shared calendar, different weather").

**The link starts invisible.** Nothing tells players the cities affect each other. Each population gets local explanations; correlations are for the community to discover.

**Each world has its own language for the loop.** Night City may say braindance ("This braindance again?"); Los Santos may say "Same movie again?" or "We've done this before". There is no universal exposition term. The architecture knows seeds and lineage; characters don't need it.

**SP and Online share the simulation grammar, not the topology.** SP can make another private world; Online cannot make a server for one player. The ceiling stays two Online servers: no third, no winner or greener-pasture server, no per-player instances.

**Three conceptual paths:**
1. Night City to Los Santos: ordinary travel in the connected universe, once the technology exists.
2. The reverse.
3. The **wormhole**, discovered by going physically away from comfortable infrastructure.

There is no galaxy-map UI.

**The anomaly.**
- **Character:** small, dark, ambiguous at first, noticeable up close, unsettling, and moving. Hard enough to reach that racers don't stumble into it; not a second lottery after reaching space.
- **Motion:** deterministic, seeded and (quasi-)orbital, never random. Players can record sightings, predict intercepts and build vehicles to reach it.
- **No quest marker** unless tracking infrastructure is causally built.

**The wormhole's two meanings: mirrors, not copies.**
- **Single player, "WHAT ELSE COULD THERE BE?"** Seed A is saved and wrapped, traversed, and seed B is generated or selected. Seed A stays addressable. This is distinct from travel between cities.
- **Online, "WHAT DO YOU WANT?"**
  - No new city, server or reset. The presentation breaks down to a question and about four answers drawn from the player's simulated life (for example "I never want to be passed again", "I want them to remember my name", "Show me something nobody has built", "I want to be left alone"), plus a refusal such as "Nothing".
  - "Okay. Goodbye." Then black, then the player wakes in the world they entered from.
  - **It fulfils meaning, not menu rewards.** It changes causal state and initial conditions within multiplayer-safe envelopes:
    - a serialized, provenanced prototype that is the fastest demonstrated machine at the moment of creation, and can then be beaten, wear or break;
    - social-memory variables for fame;
    - visibility and approach behaviour for obscurity, which is not deletion of history.
  - **Safety boundary:** a wish may alter the player, their possessions, relationships, reputation, knowledge, opportunities, engineering circumstances, bounded probabilities, and possibly bounded local effects. It never rewrites everyone else's reality. Only desires whose causal envelope can be honoured safely are offered; free text is not required.
  - **Not a farm:** no vendor, token or 24-hour respawn. Repeat behaviour derives from world rules: the anomaly moves, interception takes effort, the player's history changes, so the question changes.

**One identity, one authoritative location.** Night City, OR Snowglobe under Night City, OR Snowglobe under Los Santos, OR Los Santos. Transfer changes it transactionally. Developer and test accounts are exempt, with no lore needed.

**Don't over-physics it.** It's a coherent systemic toybox. Keep cause and effect, identity, deterministic-enough geography, understandable engineering, navigation, provenance and consequences. Allow stylized scale and approximate translation.

**The core model, as the owner states it:**
- **Racing owns the calendar.** Night City and Los Santos contribute to one Online Race Week, and each city owns its consequences.
- **Snowglobe owns the distance between worlds.** It is a shared protocol and domain, not a third server.
- **The wormhole owns possibility.** In SP that means another seed; Online, it asks the player what they want from the world they already have.
- **NCM owns continuity.**

### 5.1 Audit additions: what in today's Race Week would make this harder

| Invariant | Today | Verdict |
|---|---|---|
| Shared Race Week id | `ncm_world/server/week.lua` `runSeed(index) = Hash(serverId, "racing-week", index)`; `racing_week_run` and its children keyed `(server_id, run_index)` (schema 060) | **narrowing.** The week's identity is per server. A shared Online week needs a network-level week id that a server joins; the per-server row would become that city's local record of it. |
| Local evidence vs shared resolution | `week.curve.impulse(facts, expected)` turns local facts into impulses on one standing; `week.continuation.judge` reads only `st.deviation` | **open.** One scalar per city is resolver-shaped. The common-vocabulary adapter belongs at `facts -> impulse`. |
| Local consequences vs global clock | local consequences (sensitivity, Moody's conditions, speed limits) and the continuation verdict read the same `run.st` | **narrowing (benign for one city).** Rule: consequence functions read LOCAL state; only the verdict may read combined evidence. |
| World-specific loop language | the voice and radio lexicons are Night City's; no universal term is baked into core | **open.** Keep loop vocabulary in each world's lexicon, never in `week.*`. |
| SP seed traversal vs Online wish | nothing built; L316's dev server-wide wormhole (IDEA-1039) is a DEV seed swap | **open, one tension to keep honest:** the dev server-wide swap is a test harness for SP seed traversal, NOT the Online wormhole, which never swaps seeds. |
| Deterministic anomaly motion | `space.universe` has fixed v0 bodies and carries `t` for later motion | **open.** The anomaly needs a seeded ephemeris(seed, t), never RNG per visit. |
| One identity, one location | `driver_location` per (driver, server); no cross-server location exists | **open.** |
| Bounded wish mutation | the Paddock life sim (`ncm/core/life/*`) already keeps per-person history; NCM serialized machines and parts exist | **open; nothing to change.** |

**Further door-keeping rules (with §4):**
6. A Racing Week's identity must not be assumed to equal (server, index) in new code. Take the week id from one place (`week.lua` today), so a network id can replace it.
7. The continuation verdict consumes a **standing derived from evidence**, never raw city-specific facts. City-specific facts stop at the `facts -> impulse` adapter.
8. Consequence functions (enforcement, limits, sensitivity) read **local** state only.
9. Loop and world vocabulary lives in per-world lexicons, never in core identifiers or rules.
10. Anomaly motion is a pure function of (seed, t).

## 6. Not authorised

- Anything FiveM.
- Any Snowglobe protocol code.
- Any schema change.
- Any transfer-ticket implementation.
- Any correspondence table.
- Any shared Race Week, cross-city resolver, Online wish system or SP seed traversal.

This document records direction and boundaries only.
