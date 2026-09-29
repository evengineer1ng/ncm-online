# Oracle Kingdom as an NCM Online social simulation source

> Research assessment, 2026-09-29. Design evidence only; no NCM runtime change and no live PASS.
> Source is `D:/dev/Radio-OS/plugins/oracle_kingdom.py` and `oracle_court.py`. The requested `plugins/oracle/_kingdom.py` path does not exist in that checkout.

## What was exercised

- `tools/oracle_sim.py --seed 42 --kingdoms 2 --ticks 120 --report-interval 120`: exit 0. Eight decrees per kingdom, 2 versus 10 events, 0 versus 2 scars, and composite health 55.5 versus 51.4. This is a smoke run showing divergence, not balance validation.
- Repeating that exact command produced identical printed health lines. This checks a narrow observable, not full-state deterministic replay.
- `tools/oracle_showcase.py --seed 42 --ticks 60 --deep-field 20`: exit 0; court and kingdom serialization round-tripped. The 60-tick result had 2 decrees, no thoughts or presence requests, and one active environmental signal.
- `tools/oracle_showcase.py --seed 42 --ticks 500 --deep-field 200`: exit 0; 19 decrees, 16 thoughts, 8 presence requests, 23 environmental signals, 5 promoted/tracked kingdoms. Serialization round-tripped. Its own reported simulation time was 2.22 s, or 225 ticks/s on this machine. This does not predict server cost per player.
- `tools/oracle_court_sim.py --seed 42 --ticks 500 --stress`: exit 0; 53 decrees, 9 silences and five agents with 20-54 memories each, but zero generated presence requests and zero faction memories. The later seed sweep below identifies the zero-request result as a harness setup flaw, not evidence that the full CTA engine is silent.
- Radio-OS's `docs/ORGAN_CATALOG.md` says there is no dedicated pytest wrapper for Oracle Kingdom. The runs above are executable demonstrations with self-reported round trips, not an asserting regression suite. The old `radioenv` cannot start here because it points to missing `C:/Python313/python.exe`; these runs used the installed Python 3.14 with `PYTHONPATH=.../plugins` and bytecode writing disabled.

### Ten-seed follow-up

Seeds 1-10, 500 ticks each, completed in the full showcase with 200 background civilizations. All ten printed successful court and kingdom round trips. Final kingdom health ranged **44.2-48.2**; nine remained `STABLE` and one reached `REFORMATION`. Archetypes were six `THE_POPULIST`, one each `THE_REFORMIST`, `THE_MERCHANT`, `THE_HAWK` and `UNKNOWN`. This is some trajectory diversity, but a narrow health band and a strong archetype concentration. The run took 22.5 s in total (reported average 226 ticks/s); this remains a desktop headless result, not a multiplayer capacity result.

The same ten seeds run through the full showcase with 20 background civilizations produced **6-11 presence requests** and **15-28 environmental signals** per seed by tick 500; thoughts ranged 11-27. All court and kingdom round-trip flags were true. Average agent trust ranged 27.2-44.4. The background-field size differs from the 200-civilization performance run, so these counts are a separate content sample.

The court-only `--stress` harness produced **zero requests and zero signals on all ten seeds**, despite 40-52 decrees per seed. Source inspection explains the discrepancy: `oracle_court_sim.py` calls `SimulationEngine.advance_tick` and `CourtEngine.tick`, but never advances `OracleLifecycleEngine`. `WorldBuilder` initializes that lifecycle as `SLEEPING`, and `CourtEngine.tick` explicitly suppresses new calls to action while sleeping. The full showcase advances the lifecycle through `GeopoliticalEngine` and does produce calls. Therefore the court-only harness is not a valid request-generation test until its lifecycle is advanced. Its relationship and serialization observations remain useful.

## What to carry into NCM

The best seam is the court, not a literal kingdom per player. The court has per-agent trust, fear, admiration, resentment, agendas and three rates of memory decay; faction memory, requests, silence and spatial exposure sit above objective world facts. Its dependency direction is useful: world events inform social reactions, and social reactions affect what people offer or say. `CausalLedger`, structural scars and era classification show how consequences can remain explainable and persistent. The seeded cold simulation and presentation-only prose also fit NCM's event tape and authored Messages.

Use one shared Paddock fact tape for NPC races, results, organizations, contracts and public news. Add a **player-scoped social projection** keyed by player ID and stable NPC ID: what this NPC knows about this player, relationship axes, a bounded set of salient memories with source event IDs, obligations, current offer, last contact, and relevant district/scene. The same public result can make Billie respect one player, Rico distrust another, and Dex remain neutral. A private social response must not rewrite a shared race result or imply a physically observed encounter. Preserve simulated/physical provenance.

Translate Oracle's high-level mechanisms into NCM terms:

| Oracle mechanism | NCM social use |
|---|---|
| CourtAgent and memory entries | Per-player relationship state and a compact memory of actual races, purchases, chases, gigs and replies |
| FactionMemory | Scene reputation and introductions for authored groups; keep shared world facts separate from private standing |
| Presence requests | Contextual offers through Messages, with explicit acceptance, deadline and consequence rather than random help-menu text |
| Silence/absence | NPC reaction to a declined or ignored live offer; do not penalize ordinary offline time or flood the inbox |
| Causal ledger and scars | Event IDs and durable reputation consequences that can answer why a contact's tone or access changed |
| Court location lens | District, market, venue and in-person context shaping who has reason to contact the player |
| Importance tiers | Full simulation for the player's recurring cast; cheaper summary state for peripheral named NPCs |

Start with a vertical slice: one authored contact besides Dex/Stu/Rico, one shared Paddock event, two opposed interpretations of that event, one player choice, one later consequence and a readable causal trace. Feed it through `graph.conversation` and its existing trigger budget. A direct consequence should arrive promptly; ambient flavour should yield to gameplay. Keep Dex neutral under L176. Treat the other fifteen contacts and most of quest graph Pass 1 as SPEC until individually authorised.

## What should not be copied literally

- Oracle's kingdom variables (food, faith, legitimacy, decrees, sovereignty) describe a monarchic polity. A racing scene needs contracts, access, reputation, debt, favor, trust, rivalry, sponsor pressure and turf instead. NCM's player is a driver, not an all-powerful Oracle.
- The court's agents are hand-seeded role archetypes and many event templates are broad. The corrected full showcase produces requests, but counts alone do not show that those requests are distinct, relevant or playable. NCM needs authored cause-specific offers and coverage tests, not only more simulation axes.
- The full plugin is roughly 13,000 lines plus a separate court module, a threaded controller, JSON/SQLite saves, web/Tk surfaces and its own world clock. Porting that runtime into the server would duplicate NCM ownership, persistence and presentation. Port small pure rules into `ncm/core`, and keep server transactions and scheduling in an NCM resource.
- `CourtAgent.decay_memories` explicitly never prunes, and `CausalLedger` is append-only in memory. A per-player cast needs retention, compaction and indexed storage; permanent consequential facts can be summarized while low-salience detail expires.
- Seeded randomness and a successful serialization round trip are weaker than replay and idempotency proof. NCM needs repeatable event ingestion, identical replays after reconnect/restart, duplicate-event refusal, hidden-state projection tests, pacing tests and multi-player isolation.

## Suggested gates before a port

1. Extract a pure social reducer over a versioned NCM event contract, seeded by stable player/NPC/event IDs; prove event replay, duplicate handling and save/load equivalence.
2. Run at least 100 varied synthetic player histories, including inactive solo play. Count actionable offers, duplicate lines, unanswered leads, relationship saturation, repeated templates and unwanted offline penalties.
3. Benchmark realistic cardinality (players x relevant NPCs x memories), plus catch-up after absence. Bound storage and per-tick work before wiring it to the Online server.
4. Author distinct voice bundles through L176's vocabulary/overlap checks and the quest graph's re-entry and trigger-budget rules. Verify that every message cites an event the player could understand and never leaks hidden social numbers.
5. Add a live `MASTER_TEST` row for one real event -> private social reaction -> choice -> later consequence; built/offline-green does not satisfy L69.

The current Paddock attachment describes a shared NPC motorsport simulation and is the right source of public facts. This assessment adds a possible private social layer around those facts. No claim is made here that Oracle's mechanics are already balanced or that its existing UI should be ported.

## 2026-09-29 prototype follow-up

The owner directed an in-repo, standalone development fork before an NCM port (`L216`). The copied source, active racing model, run commands, tuning history and limits are in [prototypes/oracle_racing/README.md](../../../prototypes/oracle_racing/README.md). The first 100-seed social fixture has much wider average NPC respect (-56.7 to +98.2 after 32 events) while recording every state delta against a source event. This is a social reducer over synthetic, explicitly simulated facts; it is not the Paddock race sim and has no live PASS.

## 2026-09-29 ForkUniverse and Neikos comparison

The owner asked that `D:/dev/Radio-OS/forkuniverse` and `D:/dev/Radio-OS/plugins/neikos.py` also be assessed for reusable ideas. This was a static source review only; no tests or simulations were run. Radio-OS's `D:/dev/Radio-OS/docs/ORGAN_CATALOG.md` reports prior test counts, but those are catalog claims, not verification in this review. The deeper four-sim, long-term PvE treatment is [NCM PvE world vision and sim review](NCM_PVE_WORLD_VISION_AND_SIM_REVIEW.md).

### ForkUniverse: deterministic causal world engine

The engine's `UniverseState` has an atomic `advance_tick`, an epoch loop defined as repeated single ticks, an absence/catch-up seam, and a distinct operator-input seam. Its `CausalLedger` stores factual events, while its hot-layer `TruthDelta` exports changes for presentation. RNG streams are keyed by canonical seed, namespace and tick. The query layer constrains requests with strict schemas and supports a query-driven execution model. These are strong design references for making the racing prototype reproducible and making every NPC reaction explainable.

For Oracle Racing, the useful adaptation is a versioned player/NPC/event seed envelope and event-scoped deterministic variation, plus equivalence between stepwise replay and batched catch-up. Its factual ledger / interpretive view split matches NCM's requirement that social reactions never become race facts. Typed deltas can later let Messages, Scanner and radio consume the same settled social facts without inventing them. Prediction-and-settlement could support a contact's wager or expectation, provided it is explicitly a character belief and cannot change an authoritative race outcome.

Do not adopt ForkUniverse's wall-clock catch-up or world-scale tick loop automatically. The NCM social layer should advance from accepted, deduplicated Paddock events and player choices; offline elapsed time should only settle authored deadlines or decay that has an explicit design purpose. The current prototype's one-shot tape generation is not equivalent to per-event namespaced RNG, so that is a concrete improvement before any NCM adapter.

### Neikos: player-driven play and macro-state

Neikos is a command-driven island game with topology, encounters, factions, a normalized `IslandLedger`, a `PlayerTrajectory`, gates and cross-run echoes. Its controller explicitly avoids simulation drift from wall-clock polling: mutating player actions advance the sim. The ledger separates raw axes from baseline-normalized values and derives stability, civilization and tension indices. The trajectory gives individual actions a durable profile, while prior-run signatures can seed place-specific memory echoes.

For NCM, the transferable shape is a private driver trajectory derived from consequential play, combined with a slower scene ledger that can influence which contacts have standing, which offers appear, and how districts respond. Repeated track choices, clean/dirty finishes, build specialization, chases, favors and accepted/declined jobs can shape this trajectory. A returning player could receive restrained callbacks to earlier consequences. Keep this as social framing and offer selection; it must not silently tune race physics or infer intent from a single event.

Neikos's code also illustrates limits to avoid: many hand-tuned axes and archetype thresholds are difficult to author or explain; hidden aggregate indices can classify the same history opaquely; its large monolith couples domain rules, UI and controller. The shared world ledger in Neikos should not be copied as a shared player-affecting NCM state. Preserve one shared public Paddock fact stream and a separate private per-player social projection. Any shared district pressure needs an explicit owner ruling and server authority.

### Combined recommendation

Build on the existing Oracle Racing reducer, not either project's runtime. First make event application keyed/idempotent and replayable by stable event ID, then add a compact driver trajectory and a small, evidence-backed district/scene pressure model. Use player choices and observed/simulated events as the only causal inputs; represent NPC beliefs as beliefs; derive authored offers from traceable prerequisites. Broaden outcomes through distinct histories and motivations, not random mood drift or dozens of ungrounded axes. Keep presentation adapters downstream of settled facts. No source was copied from ForkUniverse or Neikos, and no NCM runtime was changed.
