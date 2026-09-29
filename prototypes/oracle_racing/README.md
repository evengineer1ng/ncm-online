# Oracle Racing - standalone social simulation prototype

This is an isolated development copy of Oracle Kingdom for NCM Online's PvE research. It does not load into NCM, OPEN//77 or Radio-OS, and it changes no game behavior or save. The original Radio-OS source remains unchanged at `D:/dev/Radio-OS/`.

## Provenance and layout

The following files were copied verbatim from Radio-OS on 2026-09-29:

- `oracle_kingdom.py`, SHA-256 `B163BA7BAFECCCDD15ED0BB7B6F4EB7B17A6101D505CFDC5E67A4DA2A544272F`
- `oracle_court.py`, SHA-256 `AD12B3FF4C8DDC6A8DE9E4229FB98C96B29CF4E35918060699ED0589A18B79A2`
- `tools/oracle_sim.py`, `oracle_showcase.py`, `oracle_court_sim.py`, `oracle_geosim.py` (headless source tools)
- `reference_ui/oracle_kingdom_tk.py`, `oracle_court_feed.py` and `oracle_kingdom_web/` (the original presentation/feed source, retained but not wired into this prototype)

`racing_world.py`, `test_racing_world.py` and `tools/racing_showcase.py` are the new racing fork. The copied `oracle_kingdom.py` is the source of `SeededRNG` and `CausalLedger` for now; its food/faith/kingdom mechanics are reference code and do not drive the racing prototype. `oracle_court.py` is retained for later selective extraction of memory, disposition and presence rules. This keeps the first conversion honest: the racing vocabulary is a new domain model, not string replacement over unrelated kingdom equations.

## Current racing model

An immutable `RacingEvent` has a stable event ID, tick, kind, district, stake, provenance and optional named subject. The event kinds describe race results, turf records, weather mastery, deliveries, police escape, market purchases, favors and betrayal. A `RacingWorld` is private to one player. It tracks six example NPCs with different roles and stable hidden preferences; each interprets the same result through a role lens and local exposure. Player standing in each district is derived from the event tape. Contacts build trust, respect, grievance and bounded salient memories. Thresholds open offers with a cause event ID.

Every actual state delta and offer opening is written to Oracle's causal ledger. An offer can be accepted or declined once; a later event may cite an accepted response, giving a traceable event -> offer -> choice -> outcome path. A decline closes that offer without a trust penalty. Event IDs are idempotent; reusing one with different facts fails. Snapshots round-trip through JSON and continue deterministically. Generated seasons are **fixtures**, not races witnessed in the game, and all their events are labelled `simulated`. A future server adapter must validate any `observed` event before it reaches this reducer.

Variation comes from the event sequence, stable NPC preferences, role values, district exposure, stakes and direct player choices. There is no per-tick random mood change. Early tuning showed two bad attractors: almost every contact at maximum respect, then nearly every contact in a feud. Both were corrected by balancing success/failure events, making grievance about personal harms, and reducing peripheral exposure. A 100-seed, 32-event sweep now gives average contact respect **-56.7 to +98.2**; 36 of 600 individual respect values reach ±99, 11 of 100 seasons open no offer, and all six social tags occur. These are probe numbers, not approved balance targets.

## Run

From this repo root with a Python 3.10+ interpreter:

```powershell
$env:PYTHONDONTWRITEBYTECODE='1'
& 'C:\Users\eveng\.local\bin\python3.14.exe' prototypes/oracle_racing/tools/racing_showcase.py --seed 42 --events 32 --sweep 100
$env:PYTHONPATH='C:\Users\eveng\Documents\cyberpunk2077\prototypes\oracle_racing'
& 'C:\Users\eveng\.local\bin\python3.14.exe' -m unittest -v prototypes/oracle_racing/test_racing_world.py
```

The copied Oracle tools run with the same `PYTHONPATH`. For example:

```powershell
& 'C:\Users\eveng\.local\bin\python3.14.exe' prototypes/oracle_racing/tools/oracle_sim.py --seed 42 --kingdoms 2 --ticks 120 --report-interval 120
```

## Current limits and next step

- NPC names, role lenses, offer thresholds and event weights are illustrative. They are not NCM contact authoring, Night City canon or Paddock balance.
- The fixture draws events independently from a seeded style distribution. It is not a race simulator, and it does not establish a causal explanation for why a particular race was won. The **social consequences** of supplied facts are traceable.
- Offer generation and accept/decline are mechanical. There is no authored conversation, deadline, reward, re-entry route or message budget yet. No unauthored NCM contact has been made speakable.
- Memories are bounded to 32 per contact, but the prototype's event tape and causal ledger are not compacted. NCM would need retention and replay policy before server use.
- The original web, Tk and feed source is copied under `reference_ui/` for provenance. It is not runnable as a standalone NCM interface; the headless prototype is the development surface.

## Lessons from ForkUniverse and Neikos

A static review of `D:/dev/Radio-OS/forkuniverse` and `D:/dev/Radio-OS/plugins/neikos.py` is recorded in [the PvE social assessment](../../docs/research/open77/ORACLE_KINGDOM_PVE_ASSESSMENT.md#2026-09-29-forkuniverse-and-neikos-comparison). Neither source was copied into this prototype.

The [long-term PvE world vision and four-sim review](../../docs/research/open77/NCM_PVE_WORLD_VISION_AND_SIM_REVIEW.md) captures the owner's direction for further research: each player has a distinct adventure over a shared Paddock/city simulation, with named physical NPC conversations, four primary intents and deeper evidence-backed options. Its architecture remains a proposal, not an NCM runtime change.

- **ForkUniverse:** adopt stable event/tick-namespaced randomness, strict versioned event envelopes, stepwise-versus-batched replay equivalence, and a clean boundary between factual event history and presentation deltas. This prototype currently creates a seeded season tape up front; moving variation to stable event identities would make partial replay and reconnect recovery safer.
- **Neikos:** derive a compact player trajectory from meaningful choices and let a small scene-pressure summary shape access and offers. Keep action-driven progression; avoid passive mood drift. Cross-run callbacks are promising only when they point to a real prior event or saved summary.
- **Together:** one immutable public racing fact stream can feed private per-player NPC interpretations. NPC beliefs remain interpretations; they cannot alter an observed or simulated race result. Any district-level shared state needs an explicit NCM authority decision.
- **Do not lift wholesale:** either project's runtime loop, broad hidden stat arrays, or UI/controller coupling. The prototype should remain a small, replayable social reducer with evidence-backed causes.

The next development slice is an authored racing-social arc using a real Paddock event shape and two differently motivated NPC reactions. The prototype now proves the mechanical event -> offer -> response -> later consequence causal path; it needs scene-specific copy, a second contact and playable pacing. After that, calibrate seed diversity against offer quality, not only numeric spread.
