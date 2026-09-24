# NCM Online — living decision record

> **STATUS: LEDGER** - living and append-only, current by construction. Covers: *every decision NCM has made (L-lines)* (L68)
> Authority map: [INDEX.md](INDEX.md) - classified 2026-09-24 (L125)

Maintained during the orientation/interview phase. Every entry cites its basis. Move items between sections only with the owner's answer or an experiment result. Companion: [00_ORIENTATION_BRIEF.md](archive/00_ORIENTATION_BRIEF.md).

Legend: **LOCKED** — owner-approved or forced by verified platform facts · **PROVISIONAL** — recommended, not yet approved · **OPEN** — needs the owner · **EXPERIMENT** — needs a measured result.

Last updated: 2026-09-24 — L130 records the Driver Card and Fingerprint owner rulings. Previous entries remain authoritative.

## Guiding principle (owner, 2026-09-19)

**Configurable by architecture. Opinionated by default.** — *Framework, not server. Opinionated defaults.*

## LOCKED

| ID | Decision | Basis |
|---|---|---|
| L1 | NCM Online's runtime is an OPEN//77 **resource set** (server + client + shared Lua, WebUI), not the CET mod running inside an OPEN//77 session. | Client Lua has no engine RTTI; CET mods are not network-aware. Trust cap: on a *secured* server unverified required mods are inert-only; an *unsecured* server may require executable content with player consent (server-mods guide, corrected 2026-09-19). |
| L2 | Single-player NCM stays a shipping product on its own roadmap; online work never blocks or regresses it. SP itself will be redesigned as part of the broader NCM work (owner, Q3). | Owner's principle; AGENTS.md. |
| L3 | One NCM: a shared, engine-free **ncm-core** (rules + data) consumed by an SP host and an online host. Online host is OPEN//77-native. | Owner's principle; yesterday's option B; coupling measurements in the brief §2. |
| L4 | OPEN//77 owns identity, networking, replication, vehicle canon/authority, instancing, persistence plumbing, content delivery, operator ACL. NCM does not reimplement these. | Brief §3. |
| L5 | No code is derived from Open2077/freeroam Race (PolyForm-NC). Ideas only. | Licence; yesterday's recon. |
| L6 | Every result carries per-entrant **provenance** (`physical/simulated/estimated/dnf/disconnected`) and every sporting record carries its **context** (SP vs online, server, session kind, sanctioned/ranked category). A human's physical finish is never replaced by a projection. | Owner Q3; yesterday's matrix; SP finish-resolver semantics. |
| L7 | Result settlement is idempotent and transactional (SQL); side effects keyed by a settlement key. | E7 design; SP finalizer's multiple-writes debt. |
| L8 | Physical AI above 55 m/s is unavailable on build .78. This is treated as a **current platform limitation to pursue with the OPEN//77 developers**, not an NCM design constraint. The architecture must not assume Formula-speed physical AI will never exist. | `Open77.vehicles.ai.setSpeed` card; owner Q4. |
| L9 | Vanilla traffic is per-client and cannot be a shared, fair race obstacle. Shared obstacles must be server-spawned. | `Open77.vehicles.adopt` card ("traffic is spawned per client"); vehicles guide. |
| **L10** | **NCM Online is a persistent motorsport world, not an event launcher.** Joining means entering a persistent Night City where motorsport is part of the world: ambient racing activity, driving around, meeting players, going places, racing with friends or AI, organized events. Organized races and isolated instances occur *within* the world; they are not the product. What exists between races is an **active, expansive design area** and must not be reduced prematurely to a lobby/paddock. | Owner Q1. |
| **L11** | **One NCM Driver identity.** A person has one NCM driver across SP and online, with provenance-aware sporting histories (SP / online / which server / simulated / championship / future sanctioned categories all distinguishable). The *current* SP career does not carry into online. Schema must allow eventual portability between servers: no single OPEN//77 server is the conceptual permanent owner of a driver's identity; global identity infrastructure is deferred. | Owner Q3. |
| **L12** | **Fictional sporting identities persist regardless of physical simulation.** In championships such as NCX, fictional AI drivers exist and score as competitors even when the platform cannot physically simulate them at pace. Missing physical AI never removes an identity from a league. How physical AI, simulated/off-screen competitors and humans combine in a given session stays open for design and experiment. | Owner Q4. |
| **L13** | **Multiple vehicle-ownership models, selected per discipline/event/ruleset.** Server- or team-issued homologated cars (spec/series, e.g. NCX); persistent personally owned cars and garages where ownership/tuning/identity matter; rentals/loaners; bring-your-own street vehicles where it fits the event's character. Eligibility, homologation, balancing, ownership and economy are properties of rulesets, never a global assumption. | Owner Q5. |
| **L14** | **Framework, not server.** NCM Online is a reusable motorsport framework/capability for OPEN//77 servers, validated first through one canonical, opinionated NCM reference world. Server policy is separable from core motorsport logic; nothing is hard-coded around one personal server. Third-party operator polish is *not* a day-one gate: expose policy through configuration, tunables, content packs and documented extension surfaces as systems stabilise. Different servers should eventually express very different NCMs (underground street world, NCX-only Formula server, broad multi-discipline world). | Owner Q6. |
| **L15** | **World topology is a ruleset/event property with three policies, and in-world racing is a first-class mode, never a lesser "casual" mode.** `open_world` — the race occurs in the persistent world; whatever Night City is doing is part of the event (today including client-local traffic — measure divergence in E15 before judging acceptability). `controlled_world` — physically in the world, but NCM controls population around the event and may introduce shared server-owned obstacles/traffic where viable. `isolated` — dedicated bucket with deliberate population/weather/time policy (NCX, serious circuit competition, tightly controlled championships). **Ranked/unranked is independent of topology**: an open-world championship whose premise is surviving Night City may be sanctioned. | Owner Q7. |
| **L16** | **Four event origination sources exist**: server calendar, ambient NCM-generated activity, spontaneous player-created races, organized registered events. Permissions vary by event class, not one universal creator. | Owner Q8. |
| **L17** | **Ambient motorsport is simulated at scale and physically materialized on demand (online promotion).** The server may simulate far more motorsport than clients physically see; when an event becomes relevant to nearby humans and is technically suitable, NCM promotes it into physical existence (cars appear, competitors gather, spectate/enter possible); when no longer needed physically, the event continues abstractly. Not every simulated race physically exists. | Owner Q8. |
| **L18** | **Driver ≠ Seat ≠ Entry ≠ Team.** The human is always their own NCM Driver; a seat is a team/series position they occupy ("signed for Kimiko, #77" — the career history says so). A fictional roster driver displaced by a human keeps an explicit sporting state (reserve, benched, unsigned, moved, competing elsewhere) and never evaporates. Other series may use different seat models when justified; player-created teams, independents, signed drivers and custom teams belong in the framework outside NCX-style corporate championships. | Owner Q9. |
| **L19** | **Automated race control with human override from the start.** NCM runs events without a volunteer director; authorized humans have race-control powers (delay/start, abort, red flag, inspect incidents, apply/modify penalties, correct classifications). **Spectators (non-entrants) are admitted to instances** from the beginning; physical presence matters before broadcast cameras exist. The ruleset decides how much ceremony a format wants; silly formats need none. | Owner Q10. |
| **L20** | **Consequences are ruleset-expressed; entrant continuity is modeled now.** ncm-core can express SR consequences, sporting penalties, championship penalties, economy consequences, grid penalties, DSQ/DNF; rulesets choose which apply. Entrant lifecycle includes **`suspended`** and **`substituted`** states from day one. Disconnect ≠ automatic death: entry/vehicle/session state is preserved for a configurable grace period and reconnection is allowed where the format permits; some formats may prohibit rejoining. **The entry is larger than its current driver**: vehicle-exchange and endurance entries survive a driver drop via reserve/substitute drivers; "disconnect = team DNF" is never hard-coded. | Owner Q11. |
| **L21** | **Start money-free; build the ledger now.** The first tester world issues/grants/rents cars at zero cost and charges no fees. Every result/reward operation still runs through settlement IDs and ledger discipline so that money can be switched on later without rebuilding race settlement. A persistent economy (ownership, payouts, fees, repairs, rentals, team resources, prize money) is an intended later layer. **AMENDED 2026-09-22 by L84:** that later layer is now specified. This decision was right and is why the amendment is cheap — the `ledger` table, `entry.fee`, `issued_vehicle.cost` and the zero-amount settlement line all exist already. | Owner Q12a. |
| **L22** | **Do not extract the SP prestige ladder (Gonk→Edgerunner/REP) as online policy.** Preserve it as an NCM idea for the SP redesign; extract only reusable concepts/mechanics. Online progression is multi-dimensional (reputation/prestige, discipline licences/grades, Safety Rating, championship/team standing, records/accomplishments, perhaps experience) and remains OPEN in design. | Owner Q12b. |
| **L23** | **Events/rounds are first-class scheduling objects; sessions belong to them.** A calendar entry is an Event that contains Practice, Qualifying, Race, Sprint, Feature, endurance stints, vehicle-exchange legs, etc., sharing an entry list. Qualifying supports both shared-track and solo/time-trial structures. The canonical NCX round format is a **content decision made later**, once the championship is tangible. | Owner Q13. |
| **L24** | **Absence, substitution and provenance-counting are ruleset decisions.** The championship engine never bakes in "absent human = simulated result" or "= zero points". One standings table can accept physical-human, physical-AI, simulated-AI and (later) externally verified human results with provenance on every row; whether they count equally is per ruleset (NCX may say yes; a human-only series may reject simulated/external provenance). Admin corrections, ties and mid-season rule revisions are race-control decisions with an audit trail. | Owner Q14. |
| **L25** | **Content-scoped mod requirements; assists are not prerequisites; validate sporting equivalence, not purity.** RB15 + NCX liveries are required only where NCX content is run; Manual Transmission and IWN/racing-line are input/assist options, never NCM Online prerequisites (pursue OPEN//77 verification for MT opportunistically; an NCM-native racing line is a later goal). Policy: NCM controls/validates everything that affects sporting equivalence for a sanctioned event; personal cosmetic/non-competitive mods do not matter unless OPEN//77 requires otherwise. RB15 + NCX assets are requirements of **NCX capability/content**, not of entering NCM Online. Whether OPEN//77 can practically scope/install content requirements below whole-server join is determined in M0/E13; if the platform requires the complete mod world at launch, that is recorded as a platform constraint and the reference-server/profile options come back for decision. No second server profile is created pre-emptively. | Owner Q15 + review amendment; server-mods guide. |
| **L26** | **Online leads with fixture parity; bounded SP re-adoption.** Online pulls core extraction forward; frozen fixtures generated from current SP behaviour preserve semantics; SP adopts each slice in a bounded pass. **An extracted core slice is not finished until both hosts consume it.** | Owner Q17. |
| **L27** | **First tester-facing world = a motorsport world with street racing as content pack #1 and NCX arriving very early as content pack #2.** A tester enters Night City, exists in the world with a persistent driver identity, drives somewhere, encounters/accesses racing and runs a proper NCM street event; NCX then demonstrates the same driver/world/platform issuing a #77 Kimiko Formula car for an organized round. Street classes validate OPEN//77 physical AI while the AI speed cap is pursued for NCX. | Owner Q18. |
| **L28** | **Vehicle is not structurally fused to Entry.** An entry's vehicle assignment is a separate, time/phase-scoped relation (`vehicle_assignment`: entry × session × leg/phase → vehicle); vehicle-exchange and endurance formats change assignments across legs/stints without changing the entry. | Review amendment. |
| **L29** | **Five online resources — world / session / league / sim / hud.** Not subdivided further without demonstrated need. | Review amendment. |
| **L30** | **Night City itself is the world.** `ncm_world` may support places, hubs and activities, but the persistent experience is never modelled as movement between fixed NCM hubs; driving through the city remains first-class and the between-races world stays open (L10). | Review amendment. |
| **L31** | **NCX is not architecturally circuit-only.** Content pack #2 introduces NCX Formula — cars, teams, liveries, canonical weekend content. Formula entries may participate in circuits, point-to-point routes and other NCM event types where their rulesets permit. | Review amendment. |
| **L32** | **Tester window 1 must be one continuous player journey**: join → world → discover/enter → race → result → return to world, feeling like one product rather than separate technical demonstrations. Scope: join, drive/exist in the world, impromptu race, scheduled street round, spectate. M2 precedes M3 (identity/existence is foundational, never retrofitted). | Review amendment. |
| **L33** | **Architecture (01) and roadmap (02) approved with the amendments above; M0 approved to begin** (2026-09-19). Each work package is announced with completion criteria before substantial implementation. | Owner review. |
| **L34** | **Scheduled start times are the grammar of NCM Online.** Races are posted with a time and a start place in Night City; you drive there; you are on the grid or you are not — "be here or be square". Entering is an explicit act at the venue (L35), never a lobby. Practice is free and needs no session. Racing with friends stays possible as a *short-notice scheduled* event (P17), never as an instant lobby. This is a deliberate departure from SP's sandbox "confirm and race now": the schedule creates anticipation and constraint. | Owner, 2026-09-19. |
| **L35** | **Entry is a prompted, explicit act at the start venue.** Arriving in the start zone offers "Pay entry fee and enter?"; the yes enters you (fee amount zero until the economy exists, L21). Being in the zone alone never enters anyone (spectators, passers-by). Missing the window means not entered; consequences for registered no-shows are ruleset-defined (L20). | Owner, 2026-09-19. |
| **L36** | **Thin fields are backfilled with AI drivers.** A posted slot always runs; missing seats are filled from the fictional roster through the ruleset's allowed backends (physical AI where measured, simulated otherwise, with provenance). Human-only rulesets may instead set a minimum-entrant policy. | Owner Q26. |
| **L37** | **Cadence tiers, iRacing-style:** small, low-consequence races are frequent (every 15–30 minutes across the street calendar); bigger events (championship rounds, specials) are rare and posted well ahead. Content packs declare series cadence; the scheduler posts slots ahead of time. | Owner Q27. |
| **L38** | **One posted event may split into several grids by rating/SR** when the field is large (event → N sessions with a shared entry list and a split policy). Designed into the schema now; splitting logic and any rating ladder come later (Q19). | Owner Q28. |
| **L39** | **Racing stays in the background until the player brings it forward.** The persistent "next race" card is a prototype (M3), not the product UX. There is no single "next server race"; many independent events coexist, including simultaneous ones. A player who has expressed no interest sees no countdown occupying the HUD. (Owner, 2026-09-20.) |
| **L40** | **The Race Guide — a motorsport TV guide for Night City — is how racing is discovered.** Opened on demand; lists upcoming events with series, start time/countdown, venue, vehicle/class requirements, grid capacity where applicable, and an Interested count. **Interest is digital, entry is physical:** marking Interested is a soft signal that makes the event the player's tracked event (countdown/distance HUD, waypoint to the venue, T−pings) and counts toward "8 interested / 20 max"; it never reserves a grid slot. Only physical entry at the venue (L35) reserves a limited position, and an Interested player never blocks a physically present one. Lifecycle sketch, not prescribed: uninterested → interested/tracked → arrived → entered → staged → racing → finished. (Owner, 2026-09-20.) |
| **L41** | **Simultaneous events are a supported concept.** Multiple races may run around Night City at once; players choose what they care about. Route-conflict detection is a later concern and overlapping events are not assumed forbidden — occasional intentional interaction may be desirable. (Owner, 2026-09-20.) |
| **L42** | **External testers come in only when NCM Online is a coherent experience, not a set of primitives.** Tester window 1 is no longer pinned "immediately after M4"; it is gated by an experience checklist (roadmap) and currently expected after M5. Internal one-PC/two-client testing continues throughout. Amends the placement in the roadmap; L32's continuous-journey criterion stands. (Owner, 2026-09-20.) |
| **L43** | *(2026-09-21: this destination is now **TW2** — L59/L60; TW1 is the QA/capture session.)* **Tester Window 1 is the inaugural NCX vertical slice: one real multiplayer NCX race, up to 20 human drivers.** Readiness is the chain CONNECT → OFFER → ACCEPT → PICKUP → ARRIVAL → GRID REVEAL → ASSIGNED CAR → STAGING/LIGHTS → RACE → RESULT running end to end in an internal rehearsal, not a milestone number. Still an alpha; testers are told so. The field scales 1..20 (6 join → 6 race); 20 is aspirational, never a prerequisite. Analysis and placement in [04_TESTER_WINDOW_1.md](archive/04_TESTER_WINDOW_1.md). Supersedes the "expected after M5" placement in L42; L42's principle (coherent experience before outsiders) stands. (Owner, 2026-09-20.) |
| **L44** | **NCX eligibility is a broad earned status; a grid seat is a per-race position.** NCX is never "20 permanent drivers". The mature qualification system is a later design (M9/M10). TW1 is deliberately exceptional: the alpha cohort is granted NCX assignments directly. (Owner, 2026-09-20.) |
| **L45** | **TW1 team assignment is programmatic and in-game — a sorting hat, not a Discord choice.** Ten NCX team identities (Rayfield, Herrera, Borton, Archer, Miyutsaki, Yorinobu, Kimiko, Raven, Spunky Monkey, Quadra; liveries exist for the RB15), two seats each. Variety first: one driver per team, then second seats; players do not choose, the unexpected offer is part of the presentation. Exact randomisation designed later. (Owner, 2026-09-20.) |
| **L46** | **NCX venues are a real NCM concept: NCX temporarily transforms parts of Night City into sanctioned motorsport venues** (barriers/course furniture, controlled intersections, grid/start-finish infrastructure, spectator areas, crowds, audio/PA zones, dressing), built before an event and torn down after, preferably in the shared world so nonparticipants can discover and watch, with streaming keeping the cost local. The inaugural onboarding is one-time theatre; the venue is not. (Owner, 2026-09-20; platform verdicts and E19–E22 in [04_TESTER_WINDOW_1.md](archive/04_TESTER_WINDOW_1.md).) |
| **L47** | **TW1 presentation classes:** A blockers = race core (incident penalties, corrected time, readable position/progress, unmistakable gates, reliable GPS, missed-gate handling, start/grid/finish/classification, 20-car stability), venue/course readability (grid + start-finish infrastructure, barriers wherever the course could be misread or exited), enough presentation for the reveal. B strong targets = crowd audio, substantial authored crowds (benchmark-gated), extensive barriers, music states, polished arrival/grid environment, convergence/holding, shared-world discoverability. C quality-gated = PA/announcer (good → in, robotic → out). D future = crowd AI, dynamic commentary, generalised chauffeur, editor tooling beyond the drafting loop. (Owner, 2026-09-20.) |
| **L48** | **The inaugural opening is compact and diegetic:** CONNECT → NCM Driver Profile questionnaire (reads as ordinary onboarding) → profile complete → short NCM orientation (normal NCM only) → back to the world → the assigned team's message arrives → accept → pickup → arrival → grid → reveal. Assignment is never stated by the UI ("your team is X" / scores) — the team contacts the driver; Discord does the rest. Assignments stay private until the team's message. (Owner, 2026-09-20.) |
| **L49** | **Inaugural course direction: Pacifica Stadium as the major venue (grid/start most likely) and the pre-race Route Plan as the format's strategy layer.** Some sectors have several legal, barrier-dressed routes; drivers declare a route per Route Sector before lights out; navigation guides each driver down their declared branch; branches reconverge at Universal Gates where the pack reforms; used once, at most twice, per course. Not a triathlon: the race stays "who wins in the NCX Formula car". Geometry, timing and balance are decided by scouting, not now. (Owner, 2026-09-20.) |
| **L50** | **NCM is two products sharing one brand, one driver identity and one lore — not one mod list.** *NCM Collection* (SP, Vortex/Wabbajack) is breadth: dealers, shops, physics stacks, wheels, traffic, 100+ cars — the modder's research matrix is its backlog. *NCM Online* (OPEN//77) is the league and the spectacle: calendar, teams, ceremony, identity, records, with a **curated, inert‑only fleet** (`.archive`/`.xl`/TweakXL only; no CET, redscript or plugins beyond the loaders) and **one handling truth per car** declared by the server. What cannot be inert cannot be Online; that is the platform's secured‑server design, not a taste. | Stocktake 2026-09-20 after E13/E4; KB-8; docs "Required mods" (inert cap, handling-divergence warning). |
| **L51** | **Online fleet policy: catalogue unbounded, active set bounded.** NCM's Online library may grow without limit (inert cars, QA'd one handling pass each, redistribution cleared or player‑fetched). A server declares only the cars the upcoming programme uses — a *season card* of ~10–25 cars, ≤ ~1 GB per first join — and rotates it between rounds (digest change; players fetch the delta; the content‑addressed cache means returning players fetch nothing). Disciplines may be split across worlds when a card grows. Until hosted delivery works (KB-8) the active set is what testers install by hand (P34): TW1 = RB15 + vanilla. | L50; docs bandwidth arithmetic ("you are the host"); launcher blob cache. |
| **L52** | **Tuning online is layered, and only the server touches physics.** Base car = the inert TweakXL record (identical on every client). Class ceiling (BoP) = `setPerformance` per instance at issue time. Setup = the driver's named choice inside the ruleset's window, realised as `setPerformance` values + pre‑baked record variants (gearing/aero variants are separate inert records). Parts progression changes eligibility and the setup window, never physics, until a per‑instance handling primitive exists (P4 stands). No client‑side handling mods in competition. | P4; `setPerformance` card; docs handling‑divergence warning. |
| **L53** | **An event is discipline × format × class × venue × ruleset.** Discipline = sporting vocabulary (course adapter + classifier): street sprint, Formula/NCX, **oval**, drag, knockout, endurance, time attack, kart, quad/Badlands, rally stage, drift (judged, later). Format = the round's session shape (sprint; weekend practice→quali→race; two‑race reversed‑grid; heats; stints) — event templates per L23. Class = eligible records + BoP ceilings (P38). Packs declare series by these ids; nothing is implied by the pack name. | L23, L31, P38 |
| **L54** | **Driver dimensions are independent and never gate the first world.** `licence` per discipline (earned by completed clean sessions, not results), `safetyRating` (badge, from server‑observed incidents; the only dimension that may ever gate entry, and only into series that opt in), `rating` per class (seeding only), `accomplishments` (record only). SP `reputation` is displayed as legacy, not a mechanic. NCX eligibility (L44) = licence + SR floor + invitation. | L22, L44, Q19 |
| **L55** | **Garage and economy are ledger‑driven from zero.** `owned_vehicle` rows per driver (P3 `owned`), acquired through a ledger transaction even at zero cost; prize/fee schedules live on rulesets (all zero in TW1) — **SUPERSEDED 2026-09-22 by L84(c): default economics belong to the CHAMPIONSHIP, not the ruleset; a scheduled event may override**; team resources are the same ledger, team‑scoped. Money switches on per server without a migration. | L21, P3, Q20 |
| **L56** | **Incidents are scored by the server and expressed twice: in the result and in the badge.** Every contact — with a car, an object, a person — is an incident with a severity band (1x/2x/4x‑style, tuned per discipline) scored from server‑observed telemetry (delta‑v, damage channels, NPC hits on server‑owned NPCs). The *corrected time* (finish time + incident seconds + sporting penalties) decides the result, so the first car home can lose to a cleaner slower one; the same incidents feed `safetyRating`. Cars being tanks in 2077 is desirable; the penalty is what restores the cost of contact. Official NCM servers run this universally; framework operators choose their own ruleset. | Owner brief 2026-09-20; L19, L20, L47 (corrected time); E8 |
| **L57** | **Telemetry is a first‑class stream.** Clients sample their own car (position, speed, gear, throttle/brake/steer, on‑ground) at a fixed rate and the server keeps per‑session, per‑driver samples; the server adds what it observes itself (vehicle snapshots, gate crossings). Consumers: the live race graph, incident scoring, sector/records, ghosts and replays later, SR. Client samples are trusted under P11's relaxed threat model and cross‑checked against server snapshots where they overlap. | Owner brief; NCM SP telemetry; P11 |
| **L58** | **Two tiers, both first‑class, and everyone starts in the street.** Street tier = open‑world racing with live traffic, chaos welcome, luck part of the game; sanctioned tier = NCX‑style events with barricades, spectators, controlled population and fame. Neither is the lesser mode (L15): some drivers will prefer street chaos forever, others high‑society racing. New drivers start in street racing; TW1's cohort is the exception (they get every discipline as controlled runs, L59; TW2's cohort gets the NCX event, L60). Progression between tiers is by dimensions (L54), never a paywall. | Owner brief 2026-09-20; L15, L46, L54 |
| **L59** | **TW1 is a controlled multiplayer QA + capture session, not the first polished event.** 3–5 outside OPEN//77 alpha testers (run it with whoever turns up); participants know they are testing NCM Online and that promo/demo footage is being recorded. The host may stop, restart, reposition cars, repeat starts, stage side-by-side runs and deliberate incidents. Objectives, in order: validate NCX with several real remote clients; find sync / race-state / checkpoint / incident / join-leave / UI / vehicle / session-management problems before TW2; rehearse hosting real humans; exercise several disciplines (GT/road, Badlands, drift, drag, oval, Formula) as short controlled runs; capture genuine multiplayer footage; seed a first tester group before TW2 recruitment. Testing outranks footage; footage is evidence the systems work. | Owner update 2026-09-21 (revised TW1/TW2 plan) | supersedes L43's "inaugural race" for TW1; L43's chain and L45's sorting hat move to TW2 |
| **L60** | **TW2 is the first showcase event and inherits the big-race expectations:** recruitment/sign-ups, a scheduled event, pre-race/warm-up, paddock/grid procedures, Formula cars + team liveries, rolling/start procedures as applicable, NCX race management, incidents/penalties, results, post-race. Ambition 20 cars; **must degrade gracefully below 20** — nothing may assume exactly 20 competitors. | Owner update 2026-09-21 | audit every "20": seats, hold percentages, grid columns, team-car pairs, HUD layouts |
| **L61** | **Formula stays unannounced until TW2 recruitment.** TW1 participants get a private brief once they are in ("we are preparing a larger Formula event; please do not share the details/liveries before we announce"); a small amount of Formula footage may be captured. No public teasing, no mystery posts; the promo may hold a very short Formula glimpse without explaining it. | Owner update 2026-09-21 | tester brief text for TW1 |
| **L62** | **The NCM Online promo is a fast montage of real multiplayer footage** — several forms of Night City motorsport, actual multi-player racing, NCX/race-system behaviour, possibly a brief Formula shot — cut for the OPEN//77 Discord, YouTube, TW2 recruitment and outside discovery. CTA: *NCM ONLINE / TESTERS-RACERS WANTED / BUILT ON OPEN//77* → join the OPEN//77 Discord, answer the NCM recruitment post. Single-player NCM footage only sparingly, for cinematic material not yet capturable online, and never presented as NCM Online functionality; anything implying multiplayer comes from the OPEN//77 server. | Owner update 2026-09-21 | shot list from the TW1 run sheet |
| **L63** | **Development priority is TW1 operability, not event polish:** quick create/restart of sessions; moving between disciplines/routes in seconds; a small variable field; clear race/session state; reliable starts and checkpoints; useful logging/debug; join/leave/disconnect resilience; deliberate incident/penalty testing; recovering a broken session without a server restart; repeating a scenario on demand; spotting what differs with remote clients. Architectural correctness is not traded for footage. Progression: **local/internal QA → TW1 controlled multiplayer QA/capture → fixes/regression → TW2 showcase readiness → TW2 Formula event.** OPEN//77 remains the only target. **Build breadth before validating:** be as close to beta as possible before TW1 so the hour with real humans tests breadth and no emergency TW1.5 is needed; the Race Guide is core, not TW2 polish. | Owner update 2026-09-21 (two messages) | **Batch 2 built and on staging 2026-09-21** (Race Guide, host kit `scenario.lua`, authored routes, stream gates, rolling start, fix pass); next = the master test pass (wp/MASTER_TEST.md), then TW1 (TW1_RUN_SHEET.md) |

| **L64** | **TW1 is not booked until NCM Online is a feature-complete beta.** We are in alpha. TW1 exists to validate breadth with real humans, so it may not be spent discovering what a solo session would have found; TW2 must not need an emergency "TW1.5" ahead of it. No calendar pressure on either window: readiness sets the date, not the reverse. | Owner, 2026-09-21. SP 1.0 shipped before it was ready; that is the mistake being deliberately not repeated. |
| **L65** | **NCM single-player is on indefinite back burner.** `NCM_MASTER_PLAN.md` (P1.4 onward) is paused, not cancelled; the shipped 1.84/2.0 payload stays unregressed and untouched. L2's principle stands, but **L26 is suspended**: a core slice is done when the *online* host consumes it and its tests pass. SP re-adoption passes R1–R4 are deferred until after TW2, and the fixture-parity harness with them. | Owner, 2026-09-21. Recorded explicitly because the plan and the work had silently diverged: no `core_loader.lua` exists in the SP payload and no R-pass has run. |
| **L66** | **TW2 is followed by a soft launch, not a teardown.** The server stays up after the showcase so anyone the event interested can come back and find something to do. That makes a *self-sustaining playable loop* a TW2-readiness requirement, not a later nicety. | Owner, 2026-09-21. |
| **L67** | **The calendar/guide loop must work for exactly one person.** A driver alone on the server can always (a) enter a posted event and run it, (b) practise that event's route, or (c) decline and wait for more players — no human arrangement is required to race. **A solo entry is classified as a time trial: it never grants a win, a podium or championship points.** | Owner, 2026-09-21. Scheduled races that need nobody to organise them are the spine of the loop (L34). Implementation gap logged as IDEA-001: a session forms correctly at one entrant, but `first_win` is still granted at `position == 1`. |
| **L68** | **Ideas are captured before they are scheduled.** Every idea, feature, concern or fix goes into `BACKLOG.md` with a permanent ID the moment it is spoken, in state `raw`, whether or not it will ever be built. Rows change state; they are never deleted. Dropping something means recording *why*. Plans may be inconsistent during alpha — the ledger may not be lossy. | Owner, 2026-09-21: "my biggest fear is losing ideas we have come up with and being unable to remember them… that does not mean we action them right away." One human plus one agent means no shared memory unless it is written down. |
| **L69** | **Testing is a gate, not a phase.** No milestone, batch item or feature is *done* because it is built and offline-proven; it is done when a live PASS is logged beside it in `wp/MASTER_TEST.md`. Building may run ahead of validation within a batch, but a new batch does not start while the previous pass is unfilled. | Owner, 2026-09-21. The Batch 1 → Batch 2 sequence deployed twice without a validation pass; recorded so the pattern is visible rather than repeated. |

| **L70** | **Never force the player's map open.** The KB-1 workaround (client opens and closes the native map to kick the route calculation after `setWaypoint`) is removed everywhere, including at grid forming and `/ncm.gps`. The flicker is jarring, it fires during driving, and it is unreliable anyway. NCM keeps setting the waypoint — that part works — and accepts that the minimap may not paint the road line until the player opens the map themselves. The router behaviour is reported upstream as a platform issue. | Owner, 2026-09-21, after the first full weekend run: "I would prefer we remove any instance of forcibly opening the map on the player even though its just a flicker, its annoying and jarring." Presentation that fights the player is worse than a missing convenience. |
| **L71** | **Third-party client mods are never a dependency of NCM Online; their *ideas* can become NCM features.** A mod that computes and draws something in-world is executable content, so it cannot be a required mod on a secured server, cannot be delivered while KB-8 stands, and — decisively — a CET/redscript mod is not network-aware: it cannot see NCM routes, sessions or gates through the `Open77.*` boundary. Where such a mod demonstrates something worth having (e.g. braking-zone markers along a racing line), NCM reimplements it natively from its own route data and telemetry rather than depending on it. | Owner question, 2026-09-21 (in-world navigation mod modified to paint red braking zones). Brief §8.3 trust cap; client Lua has no engine RTTI. |

| **L72** | **NCM visual identity canon.** The **light-background and small/icon logo variants are canonical**; the chrome 3D render is presentation art only, never a UI asset (it cannot survive 24 px, cannot be `currentColor`-tinted, cannot be an SVG glyph). Founding year is **EST. 2077** everywhere. NCM's lane is "a motorsport network operating inside Night City" — pit-wall software, not vanilla Cyberpunk UI and not a generic website floating over the game. NCM must coexist with, not fight, the native surfaces it cannot restyle: toasts, chat, world markers, the vanilla map and the native hacking bar — which is why a **typographic short-code grammar** (NCM / NCX / RC / team codes) is systemic: it is the only vocabulary shared by native and WebUI surfaces. | Owner + concept art pass, 2026-09-21. Asset contract in BACKLOG IDEA-080. |
| **L73** | **Driver number is the player's preferred racing number**, chosen once on first launch, stored in `driver_profile.number`, and shown on the Driver Card as identity. It is **not a guarantee of exclusivity**: a sanctioned event may assign a different display number when two entrants clash (by seniority or entry order, per ordinary motorsport practice). Identity is preserved without promising uniqueness. | Owner, 2026-09-21. |
| **L74** | **Badge system invariants.** (a) **The tier frame is never baked into badge art** — one SVG per badge, five frames applied as an overlay; baking would turn ~40 files into ~200 and destroy the system's economics. (b) **Prestige counters are durable aggregates incremented at settlement, never recomputed from raw telemetry** — otherwise the unresolved retention decision (IDEA-054) would silently delete people's careers when old samples are pruned. (c) **Badges never revoke**; counters follow settled results, so a later race-control correction does not take an earned badge away. (d) **Reveals are queued and played on the menu layer at a safe moment**, never over the race HUD — unlocks fire at settlement, when the player may still be driving. (e) Tier names are i18n keys, not literals. | Owner's badge/prestige design + agent review, 2026-09-21. Full system in BACKLOG IDEA-082. |

| **L75** | **Alpha progression data is disposable; alpha *ideas* are not.** Rows already written to the staging database — accomplishments, SR, licences, ratings, results — carry no obligation. When a settlement bug is fixed, the wrong rows it wrote are deleted outright rather than repaired, migrated or reasoned about: no dedupe that tries to preserve the earliest "true" row, no field-size forensics. L74c (badges never revoke, counters are durable) governs from beta onward and does **not** apply retroactively to alpha data. The ledger obligation in L68 is about ideas and decisions, not about driver history. | Owner, 2026-09-21, on the KB-38 duplicate accomplishments: "if youre saying its about already acquired data its fine we are in alpha." Recorded because the opposite assumption — that any written row is permanent under L74c — was about to cost a repair migration and an owner decision per defect. |

| **L76** | **NCM adds no new client mod dependencies until the platform hosts required mods.** The required-content footprint stays at what NCM uses today. TW1 is covered by confirming by hand that every participant has the mods (P34). This is a **hosting workaround, not a content budget** — when KB-8 lifts and hosted required mods work, the constraint re-opens rather than hardening into taste. It does **not** close the detection question: a server anyone can reach (L66 soft launch) meets people who were never told, so refusing or warning at entry is still owed, scoped to soft launch rather than TW1. | Owner, 2026-09-21, on KB-40. |
| **L77** | **A Formula class ceiling of ≤ 355 km/h is an acceptable permanent answer, not a stopgap.** The RB15's deterministic collapse at ~360 km/h (KB-30) is an engine limit NCM does not expect to be fixed, and a car capped below the cliff is a good racing product. The ceiling is applied through the IDEA-079 ceiling authority, never a direct `setPerformance` call, because LIMITER / POWER SURGE / wet all write the same slot. The exact number is set from one in-game measurement of the real cliff; 355 is the agreed upper bound. | Owner, 2026-09-21: "as long as we establish ceiling as 355 kph or lower we are fine." Converts KB-30 from a blocker into a tuning task and gives IDEA-079 its first committed number. |

| **L78** | **Building and validating run in parallel; validation debt is written down at the moment the fix is made.** L69 stands — nothing is *done* until a live PASS sits beside it — but it is not a stop-the-world barrier: fixing and building continue while a validation pass is outstanding, and an unvalidated pile is acceptable **provided every item in it has an appended, specific live-QA line**. The obligation is on the *writer of the fix*, at the time of the fix, not on a later reader reconstructing what to check. The queue is `wp/OFFLINE_TEST_QUEUE.md` (solo, per deploy) and the `wp/MASTER_TEST.md` Results table (the formal gate); a fix that lands without a validation line is the defect, not the pile. | Owner, 2026-09-21: "as long as we have our validation needs appended routinely and not forgotten about i am not worried about the pile growing. qa will happen building and fixing also needs to happen." Corrects a reading of L69 that would have serialised the two and stalled the fix work behind a live session the owner has to be present for. |
| **L79** | **Joker laps are the signature mechanic for NCM Online oval racing.** Oval events are scheduled, human-only, multi-lap races on authored closed loops throughout Night City and the Badlands, including compact roundabouts rather than only traditional oval venues. The first implementation uses rolling starts, ordered loop progress instead of GPS-route standings, and a required authored joker branch whose completion is shown and enforced before classification. Solo entry remains a time trial under L67. Cautions and a safety car are deliberately out of v1: race control is normally unattended and the cars' durability makes stoppages more burden than value. | Owner, 2026-09-21: "lock in joker laps," after scoping short-track oval intent. Full shaped item: IDEA-098. |
| **L80** | **Build the Race Guide once for the world it is becoming.** The Guide's architecture includes regional channels, concurrent lanes, My Races, Past Races, reminders and route previews now, even where a capability initially has no data. Missing capabilities are represented by explicit server flags and honest disabled/empty states—not fake weather, invented route maps, or buttons that imply an action exists. Region comes from the authored route's start node; the shared SP-derived node/root catalogue is the authority. | Owner, 2026-09-22: future Guide capabilities “will be built,” so the current visual rebuild must anticipate them. Implemented first slice: IDEA-100. |
| **L81** | **B-line and Hold Your Breath are drag courses.** They do not belong in the ordinary Street Sprint rotation and both carry `recommendedMode = "drag"` in the shared route catalogue. A dedicated drag event series will schedule them later. | Owner correction, 2026-09-22. B-line removed from the current Street Sprint pack; Hold Your Breath metadata corrected. |

| **L82** | **Chat is the wrong *display* surface, not a forbidden one.** Structured things — lists of actions, leaderboards, run histories, anything with rows — belong in NCM's own UI. Short conversational confirmations are fine in chat and do not need removing. The real defect is that every `[NCM]` line renders under the client's **Global** tag when almost all of them are private to one player (KB-42): a private line presented as a broadcast is worse than the same line in the right place. Judge chat by *whether the right person sees it*, not by how little of it there is. | Owner, 2026-09-22, live QA I12: "The point isn't so much to avoid using chat for anything, moreso avoid it for most things. some things are fine… bigger issue is all chats tagged as global when most should be personal to the player." Corrects an over-reading of KB-31 that was heading toward stripping chat entirely. |

| **L83** | **Drivers bring their own car, earned through progression, and an entry that does not comply is REFUSED rather than substituted.** Eligibility is therefore load-bearing at entry, not decorative: a championship declares what may race, the driver must **own** a car that qualifies, and if they do not they are told so and not entered. NCM does not quietly hand them a compliant car instead — a substituted entry would make the eligibility rule meaningless and the earned car worthless. **Two distinct checks, two distinct refusals:** *eligible* (is this model allowed in this championship) and *owned* (does this driver own one). They fail for different reasons and must say so differently. **Testing exception, explicitly temporary:** while NCM spawns cars for QA, that path must be marked as a loaner and must never be the thing that satisfies the ownership check by accident. | Owner, 2026-09-22: "end goal is players bring their own car which they earn thru progression. it should be a refusal if they dont own what is required. however for testing we will be spawning our own for now." Answers the open question in [07_NODE_NETWORK.md](07_NODE_NETWORK.md) §C6 that gated the eligibility work. |

| **L84** | **Economy invariants.** **(a) Starter grant:** provisionally **€$10,000, once per NCM driver per server/career** — idempotent, so reconnects, profile-recreation bugs and resource restarts never re-award it. The amount is balancing data, not a constant. **(b) Wallet boundary:** NCM currency and `open77_freeroam`'s `players.money` **never meet**. Different identity domains (`ncm_driver_id` vs platform identifier), different economies, deliberately. Do not synchronise, mirror, convert, import, export or infer one from the other. **(c) Ownership of economics:** default fee/purse economics belong to the **championship**. A **ruleset** owns sporting permissions and rules; a **championship** owns the sporting product and its default economics; a **scheduled event** may deliberately override them. A **route owns geography and never economics**. **(d) Charge point:** at successful check-in, *after* the busy (KB-37) and eligibility (L83) validation. Interest and browsing stay free and create **no financial reservation**. **(e) Refunds:** before a debit there is nothing to refund. After a paid check-in, voluntary withdrawal normally **forfeits** the entry. Server/admin cancellation, or any failure attributable to NCM, **refunds fully**. Every case carries an explicit transaction reason. **(f) DNF:** entry spent, no normal completion payout — "bring the car home" needs teeth. **(g) DSQ:** entry spent, no normal completion payout initially, but kept **semantically and economically distinguishable from DNF** even while the amounts are identical, so the policies can diverge later. **(h) Purse locking:** a field-dependent purse locks at **grid formation**. Before lock the UI shows the base payout plus the field-bonus rule and its cap; after lock it shows the exact table. **(i) Ledger authority:** balance is **derived** (`SUM(amount)`) and there is never a second mutable balance truth. **(j) Loaners:** `issued_vehicle.model = 'loaner'` and an `owned_vehicle` row stay distinct. **A loaner never implies ownership.** Eligibility may later accept owned-or-valid-loan; it must never be taught that a loan is a purchase. | Owner, 2026-09-22, accepting the audit in [08_ECONOMY.md](08_ECONOMY.md). Amends **L21** ("start money-free"), which anticipated exactly this: *"money can be switched on later without rebuilding race settlement."* Resolves **L55**'s "prize/fee schedules live on rulesets" in favour of the championship. Money remains outside **L54**'s four driver dimensions. |
| **L85** | **A deterministic unique `idem_key` and typed references must land before any transaction amount becomes non-zero, and the economy implementation does not begin until Deploy 11 is validated.** Two separate holds, both hard. The first is structural: the `ledger` table has no uniqueness beyond an auto-increment id, so a settlement retry would pay a purse twice — KB-38's exact failure mode, except silent and denominated in money. **Duplicate charge, duplicate settlement, and restart/retry are economy GATE tests**, not nice-to-haves. The second is process: Deploy 11 carries 39 unrun QA checks (§K–§O), and starting the economy on top would deepen a built-but-unvalidated stack to the point where a failure becomes hard to attribute. | Owner, 2026-09-22. The second hold is L69/L78 applied deliberately rather than drifted into: building may run ahead of validation, but not indefinitely, and not across a layer as unforgiving as money. |
| **L86** | **OPEN//77 owns worn presentation; NCM owns apparel entitlement.** NCM never duplicates or directly mutates the platform presentation tables. Issued, earned, purchased, found and sponsored gear converge on one future idempotent entitlement grant; equipping delegates to the platform. Apparel begins as identity/access/provenance, not driving-performance stats. Paid apparel remains under L85. | Owner, 2026-09-22: clothe characters now while deliberately preparing earning, buying, finding, upgrades/effects and modded racing gear. Full boundary: `09_APPAREL.md`. |

| **L87** | **OPEN//77 canonical environment is the validated synchronization substrate; NCM Weather Service owns policy and forecast.** Weather is world state. NCM generates and persists the slower deterministic plan, exposes a confidence-aware forecast and records event provenance; the platform adapter applies/reconciles that plan. Event buckets may override it explicitly. No geographic weather/radar is implied, and downstream performance or Fishing interpretation remains outside the Weather Service. | Owner weather brief + two-client op77.87 live PASS, [E26](archive/experiments/E26_2026-09-22_weather-sync.md). Detailed boundary: [11_WEATHER.md](11_WEATHER.md). |
| **L88** | **The eventual NCM vehicle canon is broad, curated and literally shared.** Racing has priority, but cheap cars, tuners, classics, bikes, utility machinery and joyful oddballs are legitimate persistent-world content. Every client sees the actual admitted vehicle—no proxy. Tens of GB may be justified; indiscriminate hundreds are not. Preserve future expansion room. The Matrix is not an install list, and local success or Nexus listing proves neither distribution rights nor online readiness. | Owner, 2026-09-22. [12_CANONICAL_VEHICLE_ROSTER.md](12_CANONICAL_VEHICLE_ROSTER.md). |
| **L89** | **Vehicle Library, Collection, Garage and Active Vehicle are distinct.** Library defines NCM's canon; Collection records a Driver's discoveries; Garage owns physical assets; Active identifies current access/use. Durable identity is an NCM-owned `vehicleKey`, not a TweakDB record or live entity id. Discovery represents legitimate in-world encounter, not asset installation, Guide text or secrecy from the human player. Catalogue growth never erases historical completion. | Owner, 2026-09-22. [13_VEHICLE_COLLECTION.md](13_VEHICLE_COLLECTION.md). |
| **L90** | **A server reset is announced and counted down. Players are never dropped without warning.** Any restart while anyone is connected is preceded by a broadcast and a **1:00 countdown**, with reminders at 60, 30, 10 and 5 seconds. KB-5 still stands — prefer restarting with nobody on — but when a restart must happen anyway, silence is not an option: dropping someone mid-race costs a race that cannot be re-run, and it is the worst thing a host can do to a session. | Owner, 2026-09-22, after a stranger walked into a live test session: *"if we ever reset server we do it with a broadcast message and a 1:00 countdown."* Also settles the access posture that prompted it — **strangers seeing the server mid-work is acceptable** (*"if they see plumbing, they see plumbing"*), so KB-36 is a courtesy problem, not a security one. |
| **L91** | **Tester Window 2 is dropped as a concept. NCM Online opens its doors instead of staging an authored showcase.** The opening experience is not a hand-held 30-minute Formula race with an invited audience; it is an open server whose systems explain themselves. The advertisement becomes *"the doors are open"* rather than *"we need twenty testers at a specific time"*. Cracks will show early and that is accepted — OPEN//77 is itself experimental. **What replaces TW2 as the thing worth showing:** the Vehicle Collection, vehicle trading (spec 1), vehicle supply and manufacture (spec 2), team structure and the parts economy (spec 3), plus the dormant banners/badges work. `04_TESTER_WINDOW_1.md` and the TW1 run sheet are unaffected. | Owner, 2026-09-22: TW2 *"is too on rails, driven by me and has too many failure points… we shouldn't design our opening experience around authored content."* The design briefs *"place a heavy emphasis on emergent content and systems."* **Corroborated by our own records:** KB-50 is the platform's stress-test finding that vehicle sync degrades when many vehicles concentrate in a small area, and a 20-car standing formula grid is the densest configuration NCM can produce — TW2 would have aimed an invited audience at the platform's one known weak spot, on a schedule. |
| **L92** | **The NCX ten are organizations on the ordinary NCM substrate, not a parallel team implementation.** A player may become the Owner of Yorinobu or Spunky Monkey — motorsport ownership of the racing organization, **not** ownership of the wider Cyberpunk corporation or brand. NCM/NCX is its own motorsport world. The founding ten are the **founding NCX grid, not the permanent complete grid**; NCX may admit further organizations later. NCX is then a highly governed, prestigious *use* of the same substrate, with championship rules layered above it. | Owner, 2026-09-22, answering doc 14 §8 Q1: *"NCX10 teams absolutely should become NCM organizations… not immutable authored constructors sitting outside the player organization system."* **This reverses the assessment's recommendation** to leave `team` alone, and exposes a concrete coupling: `core/competition/teams.lua` deliberately sets `teamId == livery` key *"so the two never drift"*. Under a governed rebrand the livery can change while the organization must not, so identity has to be decoupled from livery — livery becomes dated branding, not identity. |
| **L93** | **A championship grid slot is a sporting charter held by governance, not property of the organization occupying it.** An NCX organization **cannot destroy a grid slot by folding**. If an Owner fails, leaves, becomes insolvent or the organization collapses, NCX governance can facilitate transfer, sale or reallocation and ultimately find another Owner/operator. There is an NCM/NCX governing-body authority, initially administered by the server operator and moderation side, capable of enforcing championship standards and preserving continuity. | Owner, 2026-09-22. Architecturally this separates three things the assessment had as two: the **organization** (persistent entity, transferable), the **charter/grid slot** (a sporting entitlement governance allocates and reclaims), and the **ownership relationship** (dated). Ownership transfer therefore needs a governance-initiated path, not only an owner-initiated one. Comparable to a Formula One entry surviving the constructor that held it. |
| **L94** | **NCX identity is soft-preserved: rebranding is possible but governed, and history survives it.** An Owner may eventually rename or rebrand an NCX team — name, livery, logos, identity — subject to formal governance review and meaningful standards. **A rebrand must be a real rebrand, not a lazy text-field edit**; changing a name may require an accompanying approved livery/branding package. The founding identities should be culturally significant and somewhat sacrilegious to replace, without being hard-coded forever. Continuity of history is preserved across any approved rebrand. | Owner, 2026-09-22. Architectural consequence: **branding is a dated record carrying an approval reference, not mutable columns on the organization** — the same discipline as dated ownership (L90-era reasoning and doc 14 §3). The organization id stays stable and opaque; name, short, colour and livery become effective-dated branding versions, so "Yorinobu, 2027–2031" remains a true statement after a rebrand. **Do not build the governance/review/rebranding system in this pass** — only avoid modelling that would prevent it. |
| **L95** | **OWNER, MANAGER and TEAM DRIVER are mutually exclusive active roles for one identity. An Owner must appoint another human as Manager and cannot appoint themselves.** The existing rule stands: an Owner cannot occupy a Team Driver seat, and may still privateer where series rules permit. This is intentional human dependency, not an implementation inconvenience. | Owner, 2026-09-22, answering doc 14 §8 Q2. **Costs nothing to enforce:** role is a column on the single active affiliation row, and the One-Team Rule's unique index (IDEA-159) already permits exactly one active affiliation per identity — so an Owner structurally cannot also hold a Manager or Driver affiliation, in their own organization or anywhere else. The rule the owner wanted and the constraint already proposed turn out to be the same constraint. |
| **L96** | **When an organization folds, active affiliations end and the people go free; nothing historical is deleted.** Drivers and the Manager become unaffiliated and may go elsewhere. The former Owner remains an ordinary player who may simply have suffered the financial consequences of a failed organization — **no penalty state**. Historical affiliations, results and organizational history all persist. An orderly disposition process for a failed organization and its assets should eventually exist — sale of the organization, sale or auction of remaining vehicles and assets, liquidation, or acquisition by another Owner — but **exact bankruptcy and liquidation mechanics are not designed and must not be invented now**. For NCX, folding additionally respects championship continuity per L93. | Owner, 2026-09-22, answering doc 14 §8 Q3. Ending an affiliation means setting `effective_to`, never deleting the row, which keeps the unique-active-affiliation index satisfied while preserving the record that the person was there. |
| **L97** | **Privateer eligibility is a series rule, never organization discretion.** The championship decides whether its entry model is team-only, privateer-only, mixed, or a future equivalent. An organization **cannot veto** otherwise-eligible privateers from a mixed series, and **cannot admit** a privateer into a team-only series. Organizations control their own permitted team entries, Driver assignments, reserves and vehicle assignments; the series controls which categories of entrant are legal. | Owner, 2026-09-22, answering doc 14 §8 Q4. **The config already has the right home:** a championship in `packs/street.lua` declares cadence, route pool, discipline, format, class, eligibility, tier, capacity and entry window, with `tier` declared per championship precisely *because it cannot be derived*. `entryModel` belongs beside it for the same reason. Today's two paths already occupy two of the values — street championships are effectively privateer-only, organized NCX events are team-only (seat-based). |
| **L98** | **A watchdog is driven by a periodic sweep over authoritative platform state, never by an event from the subsystem it is watching.** An event cannot report the absence of itself. Corollary: the test for whether a player can *play* is not the test for whether they have a *position* — those are different questions and NCM had been asking the easy one. Second corollary: a watchdog ships with a console command that fires it deliberately, because a watchdog nobody has seen run is not evidence of anything. | Agent, 2026-09-23, root-causing KB-60. The KB-39 limbo watchdog was started from `onPlayerReady`, which is exactly what never fires when appearance restore fails — so for the one visitor it existed for, it never started. It had also been passing `p.fresh and p.position`, which that player satisfied for eleven minutes while being unable to do anything. **The decision costs almost nothing and is already paid for:** the rule now lives in `core/world/readiness.lua`, pure and offline-tested, and the host does one 5 s sweep for the whole server instead of a thread per player. Audit trail: IDEA-184 (other watchdogs with the same shape — `separateWhenReady` is one), IDEA-185 (fire-on-purpose commands). |
| **L99** | **An asset id names a physical example; a vehicleKey names the machine; a TweakDB record names the runtime thing to spawn. Ownership is keyed on the first, and the three are never collapsed.** A driver may hold several examples of one machine. Eligibility and the Collection therefore ask different questions of the same garage — "which models can I enter?" (distinct records) and "which machines have I got?" (distinct keys) — and neither is the row count. | Agent, 2026-09-23, implementing IDEA-157. `owned_vehicle` was keyed `(driver, server, record)`, so a second example of a car was not merely unsupported, it **overwrote the first** through the ON DUPLICATE KEY path. Migration 015 moves ownership to `vehicle_asset`, keyed on `asset_id`. **`vehicle_key` is stored on the row rather than derived from the record on every read**, which is the whole point: 13_VEHICLE_COLLECTION.md warns that a mod update can rename a TweakDB record without changing the conceptual vehicle, and a stored key is the only thing that still knows what the machine was afterwards. **A defect this would otherwise have introduced, caught in the core tests:** `Eligibility.eligibleOwned` counts the ids it is handed, so a spare Caliburn would have read as a second eligible option — hence `NcmOwnership.records()` (distinct) for eligibility and `.keys()` (distinct) for the Collection, with `.list()` remaining one row per example. |
| **L100** | **The global NCM season is a UTC calendar quarter with stable identity `YYYY-Sn`; a season is a bounded competitive/historical period, never a world reset.** S1/S2/S3/S4 begin Jan 1/Apr 1/Jul 1/Oct 1 at 00:00:00 UTC and use half-open bounds. `seriesId` is the enduring championship; its edition in a season is a separate historical object and may cover only part of the quarter. Closure finalizes once and preserves its facts; the next season receives fresh aggregation while ownership, economy, organizations, progression, discoveries, all-time statistics and other world state continue. | Owner specification, 2026-09-22. Existing architecture standardizes Unix/UTC occurrence fields, provenance and idempotent settlement (L6/L7); `competition.seasons` now supplies pure identity/bounds. The current SP eight-race player-driven “season” remains a distinct legacy concept. Future closure is keyed once per series + season + finalization version and recovered after downtime; it does not depend on a midnight callback. |
| **L101** | **The persistent Race Guide toast is NCM's walk-in orientation anchor and must visibly name `/ncm help`.** Transient onboarding is allowed only when it points back to a repeatable player-controlled help surface. `/ncm help` gives the smallest useful map of the world—get/return a car, F6 Race Guide, `/ncm gps`, F10 Vehicle Collection—and `/ncm lost`/`/ncm docs` are aliases. Do not flood every join with repeated toasts or turn chat help into the future welcome-panel redesign. | Owner, 2026-09-22: the help command is useless if the persistent card does not advertise it. Six or seven unplanned visitors in two days established that walk-ins are already a real product path and have found bugs authored testing missed. Builds on L91's open-door posture and IDEA-083's later persistent Help/About panel. |
| **L102** | **No player may spawn or acquire a vehicle by any command. Vehicles come from the Market or are earned; nothing a player can type creates a car, a loaner, or an asset.** Enforced at `NcmGarage.command`, the single choke point, because there are **two** player-reachable routes into it — the `/ncm` chat dispatcher and the `ncm:cmd` NET EVENT, which any client can trigger. Two callers are authorized and neither is a player request: the operator console (`ncm.car`, `source == 0`) and `reissueLast`, which restores a dropped racer's car on reconnect and is fired by `race.lua` through a server-side `AddEventHandler` no client can reach. | Owner, 2026-09-23, giving three reasons that are all supply-integrity, not UX: *"what if they spawn into a wall and create weird physics? spawn over and over? never buy a car because loaners exist?"* **The third is decisive** — a free loaner is a permanent substitute for a purchase, so the Market would open with nothing to sell. **This row was twice rewritten as the reasoning sharpened:** first read as discoverability (which would have permitted a dormant faucet), then as asset creation only (which would have permitted free loaners). The rule is about vehicles reaching players at all. **Removing the command was not sufficient:** four player-facing strings advertised `/ncm car`, including the first-join welcome and `/ncm help` (L101), and advertising a removed command is worse than keeping it — all four now point at the Market and at asking a host. |
| **L103** | **The Machine Index is personal accumulated automotive knowledge, not ownership and not an omniscient catalogue.** Keep `vehicle_discovery` as the first-identity projection; preserve richer evidence separately with model/optional asset scope, source, epistemic state, time and retry identity. Market reveals only real stock and never grants human discovery credit. Unknown is valid data; owned-now and owned-ever are distinct. | Owner Machine Index specification, 2026-09-23; IDEA-196/197; `16_MACHINE_INDEX.md`. |
| **L104** | **Base Market is one stable, universally known member of a future Market Network—not a universal shop.** Inventory/allocation is scoped to opaque `marketId`; player market knowledge and access are separate from vehicle knowledge, product eligibility and affordability. Unknown markets are absent and have no exposed total. Discovery/access creates no stock; F6 remembers legitimate commercial knowledge and renders only actual visible supply. | Owner Market Network specification, 2026-09-23; IDEA-198; `17_MARKET_NETWORK.md`. |
| **L105** | **The server is the support channel. `/ncm help` opens a WebUI surface, not a chat dump, and a player reports a gameplay problem from inside NCM with the diagnostic context attached automatically.** Help takes **no keybind** — the command is the route — and lives as a panel mode beside Guide/Market/Collection so the F6 shell absorbs it with no rework. Reports persist as rows keyed on a **client-generated `reportId`**, so a retry is idempotent and nothing is acknowledged as received until the row exists. | Owner, 2026-09-23. **Authored content is optional by design:** the owner's warning was *"authorship sounds small until it isnt"*, so known-issues and recent-changes sections render **nothing at all** when empty — no heading, no placeholder, no standing obligation, and nothing that can go stale. `KNOWN_BUGS.md` is never rendered to players; it holds migrations, internal architecture and operator-only defects. **Controls are DERIVED** from one catalogue in `player.help`, so the §14 failure mode — code says one thing, Help says another — has no second list to drift from; a surface the host has not loaded is absent rather than advertised, which is why the Market row appears only when the Market is running. **Context is facts, never conclusions:** `eligibility.reason` is recorded, not "ownership bug caused race rejection". |
| **L106** | **Acquisition and access are separate concerns.** Owning a machine and having one in the world are different facts: no free issuance, no checkout creation, no garage system, no delivery AI, no replacement minting, and physical possession never implies ownership. | Market/access workstream, 2026-09-23 (IDEA-199). Recorded here from that session's own standing-boundary statement in `NOW.md`, because code in `server/vehicle_access.lua` and `client/vehicle_access.lua` cited L106 before this record contained it. **A corollary that another session had been treating as L106** is now stated separately as **L109**.|
| **L107** | **There is exactly one definition of "the driver's race", and every player-facing surface resolves through it.** `driverEvent(driverId)` returns the soonest race the driver still has a live entry in. The venue ring, the persistent card, the waypoint, `/ncm.gps` and the venue option list all read it. No surface may re-derive "next race" from the global calendar. | Agent + owner QA, 2026-09-23. **Three surfaces answered this question three different ways in one hour** (KB-75), and each looked locally reasonable: last-clicked, `cal.next[1]`, and `nextEvent()`. The failure mode is identical to the Help controls catalogue (L105) and the shell tab list — **two lists that drift** — and it is now the third time today the same shape has appeared. The rule is therefore general: **when a question has one answer, it gets one function**, and surfaces call it rather than reimplementing it. `cal.next[1]` remains correct for "what is on at this server", which is a different question. |
| **L108** | **A venue option is never absent. Every option is always shown, greyed when inapplicable, with the reason stated.** This REVERSES the earlier rule that an inapplicable option should be omitted rather than disabled. Pressing a greyed option explains itself and does nothing; the tap-cycle skips them; the host still re-checks on action. | Owner, 2026-09-23, standing on a start line offered nothing but HISTORY: *"enter race and whatever other options exist otherwise should never be absent, they should be greyed out if inapplicable."* **The argument that settles it:** a card showing only HISTORY is **indistinguishable from a broken one** — and on that occasion it WAS broken (KB-75). The old rule optimised for not offering a dead end; it cost the ability to tell a system that had decided from a system that had failed. An absent control also teaches a player nothing, whereas *"Entries not open yet"* or *"You have no eligible car"* tells them what to do next. Internal reason slugs are unchanged for the host log; a separate map supplies the player-facing wording. |
| **L109** | **A client physics probe is placement EVIDENCE, never authority.** The client may propose where a vehicle could go; the server independently re-checks ownership, distance, routing bucket, nearby players and nearby vehicles before anything is created, and a client that proposes nothing may still be served by a server-side fallback. | Agent, 2026-09-23. Originally written as L106 to close a dangling code citation, then renumbered when the Market workstream's own L106 turned out to mean something broader (acquisition vs access). The rule stands on its own and is what the access code actually enforces: `server/vehicle_access.lua` and `client/vehicle_access.lua` both cite "L106" for this rule, but no L106 existed in this record. The text here is a faithful statement of what that code actually enforces, recorded so the citation resolves. **If the Market workstream intended something broader by L106, amend this row rather than adding another.** Consequence already relied upon: widening the client's search (KB-74) changes where a car may be OFFERED, never what may be created. |
| **L110** | **Where you log out is where you log in. Position persistence is a property of the WORLD, not of racing.** Freeroam and races alike: leave in Pacifica, return in Pacifica. Restoring a player into a live race session is explicitly **not** the goal and is not desirable — a rejoining driver is placed back in the world, not dropped onto a grid they may no longer want to be on. | Owner, 2026-09-23: *"its not so much about races but about freeroam + races, the whole ordeal... i actually dont love restoring a disconnected player to a working race. if you are in pacifica when you log out, should be at pacifica when you log in."* **This does not touch L20.** The 180 s reconnect grace is a SPORTING rule with tests behind it — a dropped entrant keeps their progress, then DNFs — and it stays exactly as it is. What changes is PLACEMENT: rejoining restores world position, and continuing a race within grace is something the driver chooses, never something done to them. **The validation gate is the work, not the storage.** Restoring into geometry, water, a closed interior, mid-air or onto a despawned vehicle is worse than the default spawn, so a restore is validated before use (ground check, KB-58 separation), **falls back to default spawn on any doubt**, never restores into a vehicle seat, and expires — a three-day-old position is not where the player thinks they are. A refused restore must say why: a silently stranded player looks identical to a working one (the KB-72/KB-76 lesson). |
| **L111** | **Vehicle colour is deterministic and supply-constrained. It is decided when the machine is manufactured, stored on the asset, and never re-rolled.** Choice exists only as *"pick one of the machines that exist"*, never as a colour picker: what is available is whatever the manufacture/supply model actually produced. | Owner, 2026-09-23: *"colours should be deterministic, only chosen through what is deterministically available as per our manufacture supply model."* Today the engine picks a paint variant per spawn, so the same owned MaiMai was brown one session and blue the next — the machine had no identity of its own. **It belongs on the asset** (`vehicle_asset`, keyed on `assetId` precisely so an individual example carries its own history, L99), assigned at mint/allocation alongside the rest of its configuration, and applied on **every** spawn path — CALL, `/ncm car` loaners, grid cars, race spawns — or a machine is one colour when called and another on a grid. **The mechanism is real, not assumed:** `Open77.vehicles.setPaint(vehicleId, { primary = {r,g,b}, secondary = {r,g,b} })`. This is also the seam the parts system lands on: colour, plate, livery, trim and fitted parts all describe THIS example, not the model — so allocation, not the player, is the author of a machine's appearance. |
| **L112** | **NCM Online is the world; NCM Development is the workshop. The Lightsail server becomes something we RELEASE to, not something we develop on — and `serverId` is an opaque identity that never changes.** Development moves to a Windows-hosted server with its own database. Promotion moves code, resources, config and forward migrations; it never moves data. A finished task does not mean production changes: a known revision is promoted. | Owner, 2026-09-23. **The finding that shapes the whole cutover:** every canonical row in the live world is keyed `server_id = 'ncm-dev'` — 384 events, 15 ledger rows, 14 discoveries, the first persistent player-owned asset. Renaming that identity would not rename the history, it would **orphan** it. So the rename to NCM Online is a display and access change, and the role a server plays is carried by a separate `environment` tunable (`development` | `online`, defaulting to `development` so a fresh server is never mistaken for the world). **Cutover therefore needs no data migration at all.** Architecture, procedure, parity risks and the exact steps are in [16_ENVIRONMENTS.md](16_ENVIRONMENTS.md). **Not active:** there is still one server, nothing renamed or opened, and the gate remains the ordinary-player spine (MASTER_TEST §AC11). |
| **L113** | **A global from another Lua VM is always nil, and `if ThatGlobal and ...` is silently false forever. Cross-scope global references are forbidden and the gate enforces it.** `ncm_world` and `ncm_league` are separate resources with separate VMs; within a resource, client and server are separate again. Fix such a dependency by REMOVING it — shared core, the database, or `GlobalState` — never by bridging it. | Agent + owner, 2026-09-23, after the same defect landed **three times in one day**, each found by a player rather than a test: **KB-66** (`ncm_world` asked `ncm_league` to grant ownership — the grant never happened), **L110** (`ncm_world` reached for `NcmCalendar.serverId()` and fell back to a literal, keying `driver_location` under `"ncm"` while the world used `"ncm-dev"`), and **L111** (`ncm_world` reached for `NcmOwnership.paintFor` — a called machine was never painted once, which is why an owned MaiMai came back green and then red). **The idiom is what makes it invisible:** the defensive `and` guard that looks careful is exactly what swallows the failure. `tools/test-cross-scope.lua` now fails the gate on any such reference, verified by a negative control that reintroduces the real bug; `cross-scope-ok` on a line is the documented escape hatch for a deliberate, guarded case. |
| **L114** | **Practice is an explicit player action. Interest, registration, venue proximity and merely opening the venue surface never create or join a practice session.** The PRACTICE button starts/joins practice; practice then has an equally explicit leave/retire path. Interest remains a soft signal only, registration remains the formal race commitment, and neither silently changes the driver's live-session state. | Owner, 2026-09-23: *“why have a practice button if it just hijacks a session on its own due to proximity rules?”* Live evidence exposed the contradiction: `NcmGuide.interest()` called `NcmRace.practiceJoin()` unconditionally, while the separate PRACTICE option called `interest()` again. That hidden practice session blocked ENTER RACE as `in_live_session`, published `other_event=nil`, and left the actual City Cup roster at zero (KB-77 / MASTER_TEST 2.18 §AC11 FAIL). |

## PROVISIONAL

| ID | Decision | Rationale | Depends on |
|---|---|---|---|
| **P11** | **Integrity tier: secure foundations, relaxed present-day threat model.** Sporting truth is server-authoritative wherever reasonably practical; important claims are validated; foundations never assume permanently trusted clients, so integrity can be tightened later without rebuilding. Competitive anti-cheat is not a product gate now; fun, experimentation, friends and deliberately silly formats (vehicle-exchange triathlons) come first. | Owner Q2 (PROVISIONAL by owner's designation). | Revisit if NCM becomes competitive. |
| P1 (revised ×2) | Server topology: one persistent NCM world server. World bucket(s) are a first-class product surface. Each session declares a topology policy per L15; `isolated` sessions allocate from a reserved bucket range; `controlled_world` sessions run in the world bucket with `world.setPopulation`/`clearArea` around the event and optional server-owned obstacle vehicles; `open_world` sessions touch nothing. | L10, L15; per-bucket environment APIs; Deathmatch precedent. | E15 |
| P2 (revised) | **NCM Driver ID** is minted by NCM (stable UUID, created wherever the driver first exists — SP profile or online enrolment), never derived from a server. Each OPEN//77 server records a binding `userId ↔ ncmDriverId` plus its own per-server ledgers (career, wallet, garage). Sporting history rows carry `context = {origin: sp|online, serverId?, sessionKind, sanctioned?}`. Portability later = moving/merging bindings and histories, not re-keying. | L11; identity guide (`userId` durable per installation). | — |
| P3 (revised) | Vehicle provisioning is a **ruleset capability**: `issued` (server/team canonical vehicles), `owned` (persistent garage via `getProperties` round-trip), `loaner`, `byo` (adoption of the player's vanilla car or an owned canonical car). Eligibility/homologation is evaluated by ncm-core against the vehicle's record/class/build; provisioning is executed by the online host. | L13; platform primitives. | Economy (OPEN Q12) |
| P4 | Tuning online = class rules + `setPerformance` ceilings + optional uniform handling INI; parts progression is eligibility/cosmetic/simulation-only until a per-instance handling primitive exists. | E9; yesterday's matrix. | E9 |
| P5 | Liveries ship as inert ArchiveXL patch archives (required mod, hosted by us); RB15 base archive via player-fetch unless the author licenses redistribution. | server-mods guide; RB15 livery research. | U13 |
| P6 | Presentation online = WebUI HUD + `open77_worldui` gates + blips + package audio; native ink/CET UI stays SP-only. | Client Lua boundary. | E10 |
| P7 | Off-screen league (ambient scheduler, roster simulation, box scores) runs server-side as a service consuming ncm-core; independent of physical AI. | E11; L12. | — |
| P8 | Checkpoints are server-validated oriented-box gates (`Open77.zones`) with ordered progress, direction, swept-crossing and grace rules from NCM; "held for N ticks" evaluation. | zones guide; gamemode-kernel contract; P11. | E2 |
| P9 (revised) | **Entrant backends are an abstraction from the first milestone**: `human`, `physicalAI` (platform AI, leased simulation), `simulatedAI` (statistical, off-screen or "on the timing screen but not on track"). A session declares which backends its seats may use; a fictional identity can switch backend between sessions without changing its sporting identity. Physical AI is enabled per class/route by measured capability, not by architecture. | L8, L12; vehicle-ai guide. | E4/E5/E6 |
| **P12** | **Event classes with distinct permissions**: `calendar` (server/operator), `ambient` (NCM scheduler; promotable per L17), `impromptu` (any driver, from wherever they stand; lightweight rules), `organized` (registration/entries; creators = race control/team leads/operators per tunables). Promotion relevance = nearby humans + technical suitability (route validated, AI backend available, budget). | L16, L17. | E4/E5/E11 |
| **P13** | **Sporting identity model**: `Driver` (NCM Driver ID), `Team` (content-defined or player-created; membership with time ranges), `Seat` (series × team × number; occupant = driver, with `reserve` list), `Entry` (session × seat-or-independent; may have a driver *roster* for exchange/endurance; states incl. `registered/gridded/racing/suspended/substituted/finished/dnf/dsq/withdrawn`), `Result` (per entry, per stint, with provenance); `VehicleAssignment` (entry × session × leg → vehicle, L28). Displaced fictional drivers get states `reserve/benched/unsigned/transferred`. | L18, L20, L28. | E12 |
| **P14** | **Race control is a service with an automated director and an ACL-gated human override**: commands `delay/start/abort/redflag/penalty/correct` write to an audited decision log; the session state machine consumes them. Spectator admission = bucket entry as non-entrant with a spectator HUD mode. | L19; `command.*` ACL; bucket APIs. | E14 |
| **P15** (verified) | **Solo test capability, verified 2026-09-19:** two in-world clients on this PC (RTX 5060 Ti 16 GB) under distinct identities — the launcher for client 1, `tools/o77-client.ps1` + dev-console `open77:shell:autoconnect` for client 2 (identity profiles enrol on the alpha master without sign-in). Three-plus-client tests wait for Discord testers. Save folder backed up before multi-client sessions. Browsing servers quarantines the Solo-profile (SP NCM) mods until "Play your own game" restores them. | E0 part A record. | — |
| **P17** | **Impromptu = short-notice scheduled.** "Race my friends to the Trench" posts a calendar event at T+N minutes starting at the creator's position; same scheduler, countdown, pings, venue prompt and settlement as any posted race. No instant-start path exists anywhere. | L34; one code path. | — |
| **P18** | **Practice overlay, no session.** Client-side route preview on the native map, waypoints/next-gate rings along a chosen course, a local unofficial timer with personal practice bests; never a sporting record (context `practice` is excluded from standings/records). Weekend *practice sessions* (L23) remain separate, server-run sessions. | L34, L25. | E10 |
| **P19** | **Pings and the next-race heartbeat.** Server notifications at T−15 / T−5 / T−1 for events a driver is eligible for or registered in; a persistent HUD element with countdown and distance to the start venue; a calendar browser. Free-roam always has a "next thing". | L34, L37; `open77_notifications`. | — |
| **P20** | **Recurring slots in content packs.** Series declare cadence (`every 30m at :00/:30`, `weekly Sat 20:00`), venues, ruleset and backfill policy; the scheduler materialises slots ahead (e.g. next 2 hours of small races, next 2 weeks of big events) and posts them to the calendar and activity feed. | L36, L37. | M3 |
| **P21** | **Entry lifecycle gains `checked_in`** (after `registered`, before `provisioned`): the state produced by the venue prompt's yes. Advance registration reserves (championship seats); the prompt confirms. Start times are wall-clock; a session sets its bucket's game time/weather (isolated) or inherits the world's. | L35, P13. | — |
| **P16** | **Packaging: one NCM Content Catalog, two delivery channels.** A versioned catalog (mod, file version, archive hash, components, redistribution, eligibility `sp-only / online-inert / online-unsecured`) drives both the Nexus Collection tiers (NCM Core / Driving / World) for SP and the online packs' required-mod declarations. The Collection is the recommended SP install; the standalone mod page stays canonical/manual. NCM Online never depends on the Collection; the two share pinned hashes so Collection players pre-satisfy online player-fetch. See [03_PACKAGING_AND_COLLECTION.md](archive/03_PACKAGING_AND_COLLECTION.md). | Launcher profile model (Solo vs Stack+World); content-addressed store; owner's Collection research. | E13, OPEN Q24/Q25 |
| P10 | Operator policy lives in `Open77.tunables` + versioned content packs + a server profile; ncm-core ships opinionated defaults; operators cannot alter competitive rules mid-session (round-boundary promotion). Generic exposure grows as choices become apparent. | L14; tunables API. | — |
| **P22** | **A player is an OPEN//77 identity, never a machine.** NCM keys everything (driver binding, entries, sessions, reconnect grace, ledger, records) on the platform's `userId`/player id and holds no concept of installation, IP, hardware or "primary client". Two instances on one PC connecting as two identities are, to NCM, two remote players; local display/input/process management is a setup concern outside NCM (owner, 2026-09-20). Guardrails: no per-IP or hardware-keyed logic ever (incl. M13 anti-abuse — key on identity); client scripts keep no machine-global state; pad polling stays a fallback behind the platform's own interaction binding because `Open77.input` reads physical devices, not per-instance bindings. Known practical limits on this PC are platform/hardware, not design: KB-4 (second instance renders no chat/notification WebUI and gets no key input at prompts), VRAM, and the Steam single-instance workaround. | Keeps future local-online play free. | Revisit if OPEN//77 adds per-instance input/device binding. |
| **P23** | **NCM Messages will be OPEN//77-native.** Port the valuable parts of SP messaging — content, conversation trees, response options, state-machine concepts, conditions/consequences (`contact_events.lua` archetypes/offers, `phone_bridge.lua` responses) — never the WovenKit/vanilla-phone implementation. TW1 needs only v0: one authored team offer with Accept/Decline; per-team voices later. | L43, L45. | Inspect SP content when M7.5 starts. |
| **P24** | **Pickup/transport uses platform vehicle AI with the player as passenger; no bespoke transport tech.** Primitives exist (server vehicle, `ai.attachDriver`/`driveTo`, passenger boarding with reserved driver seat, `warpIntoVehicle`) but routing reliability and fleet scale are unmeasured (no headless physics; E4/E5 unrun). Build as a one-car experiment; keep the fade-teleport fallback (car pulls up → board → fade → arrive near venue) wired from day one; Delamain/shared transport acceptable. | L43. | Decide autonomous vs fallback per tester after the rehearsal. |
| **P25** | **TW1 sequencing:** M3 → M4-lite (organized/invitation events, teams/seats, race-control abort/DSQ) → M7-lite (E13 required-mod pipeline with unsecured consent, RB15 + liveries, 20 canonical liveried RB15s on a grid) → M7.5 TW1 slice (Messages v0, sorting hat, pickup/convergence/reveal, dispersed spawn, ops kit) → rehearsal (≥6) → TW1. M1-debt, the rest of M4 (Race Guide, spectators, standings), M5, M6 and the rest of M7 follow. Not built before TW1: NCX qualification/careers, the full Messages port, overflow/spectator systems, AI backfill, physical AI fleets, route-conflict detection, economy. | L43, L42. | Revisit after the rehearsal measurements. |
| **P26** | **Venue substrate = VenueDefinition (data) + loader/teardown (server) + drafting loop (shipped `prop.*` admin commands → `ncm.venue.export`) + client audio crossfader.** Runtime representation is the platform's server-owned props/NPCs/package audio, streamed per player. No generalised editor before TW1; CyberTrials is an authoring reference only. | L46. | Revisit after E19/E20. |
| **P27** | **Crowds are audio-first.** Visual crowd = passive silent NPCs holding authored zones, facing the course, idle/watch clips; no individual intelligence for TW1. Density authored (very high at grid/start-finish/hairpins/braking zones, medium at corners/overlooks, low on fast sections) and capped by E20 measurements, never guessed. Vanilla `setPopulation` crowd is an unshaped ambient layer. | L46, L47. | — |
| **P28** | **Shared world vs controlled bucket for NCX races is decided by E22**, not assumed: population and traffic are per bucket, so a shared-world circuit relies on `clearArea` sweeps + lowered bucket traffic + barriers; a controlled bucket needs the venue and admitted spectators (M4) inside it. | L46, L15. | Owner decision after E22. |
| **P29** | **NCM Driver Profile personality = onboarding metadata, not an RPG system.** Questionnaire answers produce a weighted team-affinity vector stored on the profile (migration 006, `onboarding_json`); no XP, stats or gameplay effects; never displayed. First consumer: the inaugural sorting hat. | L48. | — |
| **P30** | **NCM Messages are persisted data from the first offer.** `message` table (to driver, from team/system, kind, subject/body, actions, state unread/read/accepted/declined/expired, ref) lands in migration 006; the seat offer is a message from then on, delivered by toast+chat until the Messages panel (M7.5). Port SP content/state, never the WovenKit implementation (P23). | L48, P23. | — |
| **P31** | **Sorting hat = variety first, affinity within the rule** (core `Teams.assignSeat` with `opts.affinity`, built 2026-09-20): drivers 1–10 fill distinct teams by best fit, 11–20 second seats; the second Rayfield fan lands on their next-best team. Cohort-level matching only if greedy-in-arrival-order proves unfair in rehearsal. | L45, L48. | Revisit after rehearsal. |
| **P32** | **Courses are ordered stage lists; a stage is one gate or a choice group of alternative gates** (branches with id/label/colour/icon/nominal length); progress stays a stage index; a per-entry Route Plan (`stage → branch`) lives in session state; rulesets choose `routeChoice = declared|live` and a `deviation = accept|penalty|reject` policy (NCX: declared + time penalty; street: live + accept). No invisible walls. Progress within a stage is normalised by branch length for corrected position. Implemented in M7.5 with the first authored course; until then, no new code assumes a flat gate list. | L49, L47, P26. | — |
| **P33** | **Pre-race route briefing is one short screen → select per sector → LOCK ROUTE PLAN; after lock, aggregate branch counts are visible to all** (identities = owner decision); no branch capacities for the inaugural; unlocked entries get a branch by a default policy (proposal: least-declared). | L49. | Owner: identities visible per branch? default policy? |
| **P34** | **TW1 mod delivery is manual, not baked in.** Until the platform attests hosted hashes (KB-8), testers install the RB15 + NCM liveries by hand (inert files only, no ERS/CET), restore those groups in the launcher's *Your own game* list and allow the ArchiveXL/TweakXL plugins; the server keeps the packages declared but `requiredMods.enabled=false`. The native path (verified packages, consent gate) stays the target; flipping `enabled` re-enables it with no other change. Livery yaml is named `zzzz_ncm_rb15_liveries.yaml` so TweakXL reads it after the RB15 base record. | E13; KB-8; L48 ("entry is physical") | revisit when either review lands or the devs answer on `Unverifiable` |
| **P35** | **The ride pulls up; the passenger never sees a spawn.** Final product: the transport is born out of sight on a road and drives to the player. For TW1 every tester has an **authored spawn point** with a paired **pickup node** (on-road, inside the passenger's streaming range — KB-10 — and with a clear drive to the spawn); the pickup spawns at the node and pulls up. Kerb-side spawning (2026-09-20) is a dev/test expedient only, because the server's default spawn is a random spot with no paired node. The autonomous drive itself is proven (staging, 2026-09-20: pull-up 17 s, boarded 25 s, drive along a road); failure handling stays on the road (re-issue ×2, then the passenger takes the wheel), never a teleport. | L43, P24, KB-10 | author spawn/pickup node pairs with the venue work (M7.5); measure per-pair reliability in rehearsal |
| **P36** | **Rides follow authored routes.** Per spawn-point→venue pair, NCM authors a `followRoute` point list (≤64 points, ~150–250 m apart, on known-good roads, avoiding the intersections E4 found), tested once in rehearsal; a single far `driveTo` is only the dev/test path. Failure handling unchanged (lane-find, re-issue, hand the wheel over). | E4 (2026-09-20), P35 | author with the M7.5 venue/spawn work; keep the bad-intersection list in KNOWN_BUGS |
| **P37** | **M7.5 order by tester‑visible value per hour:** questionnaire + secret team offer (Messages v0) → grid reveal ceremony → Pacifica venue dressing (props/NPCs/audio, E19–E21) → chauffeur polish on the authoring kit (M7.5.1). Dispersed spawn is done. Chauffeur, hosted delivery and loaders are dev‑ask dependent and never on TW1's critical path (emergency teleport covers arrival). | Stocktake 2026-09-20; E4; KB-8/10/11 | revisit when either dev ask lands |
| **P38** | **Online class design starts from inert + lore‑native**, not the hypercar list: Formula (RB15), Street (vanilla pool, proven), one lore‑native derivative class (Quadra Turbo‑Z, Galena GT Widebody, Riptide‑Phoenix‑style cars once verified inert), one novelty class (Cyber Kart). Real‑world exotics join the Collection first and Online only when inert and QA'd. | L50, L51 | class packs land with M8 |
| **P39 (revised 2026-09-20)** | **Incidents are zero‑fault: incident = incident, no blame.** Both cars in a contact carry it; objects/people are always yours; light contact under a delta‑v threshold is 0x; repeat incidents by the same driver escalate (a count, not a judgment). Attribution ("the approaching car pays") was considered and rejected: assigning blame is administrative hell and creates ambiguity; griefing is handled culturally by the community, by the SR badge and eligibility floors, and by race control's existing DSQ/abort powers for the egregious case (L19). Framework operators may choose otherwise in their ruleset. | Owner decision; iRacing precedent | tune thresholds per discipline in rehearsal (E8) |
| **P40** | **Live race graph: one line, one dot per driver, corrected progress.** Progress = distance along the course polyline; a penalty moves the dot back by the distance the driver would cover in that time at their recent average speed, so the graph shows who is *actually* winning under corrected time. Toggleable, on by default; part of the race HUD page. | L56, L57 | build with the incident engine |
| **P41** | **Ovals are a discipline from the start.** Course with start = finish, N laps, 2–4 gates around the ring, lap counting by repeating the stage list; candidate venues are large roundabouts (owner scouting). Ovals need sanctioned traffic control (E22) more than any other discipline because per‑client traffic (L9) makes a live roundabout unfair; they are also the natural showcase for the incident system (contact‑heavy, tank cars). | L53, L15, L46 | first oval after the Pacifica venue work |
| **P42** | **Data model growth is three migrations, designed now:** 008 competition vocabulary (discipline, format, class, class_vehicle, ruleset; event/session gain their ids and kinds), 009 driver dimensions + incidents + telemetry (driver_licence, driver_rating, driver_sr, incident, accomplishment, telemetry_sample), 010 garage (owned_vehicle, vehicle_setup, vehicle_assignment, team‑scoped ledger). See 05_DATA_MODEL.md. | L52–L57 | build 008 with M8, 009 with M9, 010 with M10 |
| **P43** | **Detection reality check:** the server only sees what it owns. Car↔car contact is server‑observable (snapshots, delta‑v); car↔object partly (damage channels); car↔pedestrian only for server‑owned NPCs — vanilla crowds are per‑client (L9), so scoring pedestrian hits in the open world depends on client reports. Sanctioned venues (L46, E22) with server‑spawned population are where incident scoring is authoritative; open‑world street racing scores car↔car and self‑reported hits under P11. | L9, L46, P11 | E8 measures detection quality |
| **P44** | **Drag rules.** (1) Straightness: deviation from the lane line is penalised (corrected time), porting NCM SP's unfinished straightness scoring. (2) Lanes from qualifying, weighted to the winner but subject to traffic luck: P1 = fast lane, traffic‑side (with the flow); P2 = slow lane, traffic‑side; P3 = slow lane, oncoming side; P4 = fast lane, oncoming side. Only meaningful where traffic runs (street tier); with per‑client traffic (L9) the luck is per client, which the street tier accepts as intrigue. | Owner brief; L9, L53 | drag adapter in M8 |
| **P45** | **Ovals have two lives.** Street‑tier ovals run in live roundabouts *with* traffic — weaving is the fun, variance is the point. High‑tier ovals get the NCX treatment: barricades, spectators, controlled population (L46/E22), tight incident bands. Same discipline, two rulesets. | Owner brief; L53, P41 | first street oval after Pacifica; sanctioned oval with M7.5 venue tooling |
| **P46** | **Client surfaces: several WebUI pages per resource are fine; interactive pages sit on `layer="menu"` and take focus only while open.** Verified in the shipped freeroam/polyzone resources (multi-page, `page:setFocus(open, open)`, `RegisterKeyMapping`, never `visible=false` at create). NCM runs two pages: `race.html` (HUD, never focused) and `panel.html` (questionnaire + inbox, focused while open). Every interactive action keeps a chat/console twin (`/ncm.q`, `/ncm.inbox`, `/ncm.read`, `/ncm.accept`) for KB-4 clients and for the day a page cannot take input. Permissions used: `world.props`, `world.npcs`, `vehicles.read` (names verified in freeroam's manifest). | Batch 1 exploration 2026-09-20 | confirm focus/click live (Batch 1 §1) |
| **P47** | **The Race Guide is the spine; sessions hang off it.** Build the organizational layer before hardening more session transitions: an event exists in the Race Guide → a driver browses and signals interest → the system waypoints them to the venue → the staging ring is already there → optional practice → qualifying at its time → an explicit route to the race grid → the race on schedule. Special presentations (TW1's chauffeur, bespoke seat offer, team-car delivery, narrative) layer on top of that foundation; none of them is generic race-weekend infrastructure. | Owner QA batch 2, 2026-09-21 (`ncm_race_weekend_qa_batch_2.md`) | **built 2026-09-21 (Batch 2):** F6 Guide page + chat twins, interest = soft entry (`entry.state interested`, upgrades at the venue under the same id), map route on interest; ordinary events never invite/spawn cars |
| **P48** | **Practice is on demand, not a scheduled window.** Keep the practice-run machinery (runs, best time, practice leaderboard with P1/P2…) but no countdown, no synchronized window, no "practice opens in": a driver who has shown interest in a listed event can practice the route whenever practice is available, alone, as often as the ruleset allows, then wait or leave until qualifying. This removes the practice → qualifying transition. | Owner QA batch 2 | **built 2026-09-21 (Batch 2):** `session.practice` on the quali run engine, one per event from posting until the first session forms, joined on interest, unlimited runs, `practice_run` rows, per-event leaderboard (`/ncm.practice`), published beside the live session (`GlobalState.ncmPractice`) |
| **P49** | **Qualifying is one run, its window is sized to the route, incidents count, and the window closes when every run is in.** `format.weekend` quali `maxRuns = 1`; a second start is refused; the window is `format.windowFor(lengthM)` — a careful-pace run estimate (54 km/h) doubled plus a minute, rounded up to whole minutes (to fives above ten), floored at the format's number: Troll Pass 4 min, 2 km 6 min, Tip-to-Trench 20 min — never a fixed 4 minutes; incidents during a qualifying run are recorded and add to the run (already the core rule) — sporting consequences per ruleset. | Owner QA batch 2; built in Batch 1 fix pass (core test `quali_one_run_closes_when_every_run_is_in`) | confirm |
| **P50** | **Qualifying → race is explicit and geography-aware.** On the qualifying result: "P<n>. Proceed to the race grid" and the grid waypoint at once; the gap between the last qualifying finish and grid close is computed from the route (finish → grid travel at a sane speed, floored), never one universal 90 s. The grid still closes deterministically: at the deadline those on the grid start, absentees are DNS (hold ≤ 60 s past the scheduled start, as built), a countdown that reaches zero changes state immediately. | Owner QA batch 2 | built 2026-09-21: `format.gapFor(travelM)` = finish→next-start distance at 54 km/h + 60 s, whole minutes, floor `sessionGapSec` (Troll Pass 2 min, Tip-to-Trench 9 min); HUD routes to the next start on the result; grid closes deterministically — confirm the pace |
| **P51** | **Results overlays are brief.** A P1/P2 board shows for ~15 s, then the HUD strip carries the result; no session result obstructs the view through a transition. | Owner QA batch 2 | built (client `BOARD_SEC`) — confirm the duration |
| **P52** | **No seat-offer ceremony or spawned team car for ordinary events.** The invite → accept → team car flow is TW1/NCX presentation. Ordinary events: interest in the Race Guide is the entry; the driver brings their own car (garage, L55). The chauffeur is never attached to an ordinary event. | Owner QA batch 2; L50, L58 | chauffeur gated 2026-09-21: rides only in TW1 mode (`/ncm.au tw1 on` → `GlobalState.ncmVenue.tw1`); the invite/team-car flow stays on the NCX invitational only; ordinary events enter through the Race Guide (Batch 2) |
| **P53** | **Batch 2 build defaults, accepted by the owner ("your assumptions are good", 2026-09-21):** the Guide is one list with a street/sanctioned tag (not tabs); practice is open from an event's posting until its first session forms; practice leaderboards are per event now and per route later (IDEA-035); the rolling-start pace reference is the pole car (a server pace car later); interest is a soft list with no reservation; ordinary scenario events use the `street_sprint_v0` ruleset; `formation` defaults to 300 m and `pace` to 80 km/h; formation faults are band 1 / 2 s; ovals roll by default (P41). | Batch 2 build 2026-09-21 | revisit any of these from the master test or TW1 findings |
| P54 | **External component manufacturing goes through the ncm-core gate, not a new plugin API.** A brick is one ncm-core module (Rule / Reducer / Catalogue) delivered as a runnable mini core root with read-only copies of its dependencies, queued at `ncm/bricks/<B-id>/`, admitted by moving the file into `ncm/core` and adding one `MANIFEST.lua` line. Host adapters, WebUI, schema and orchestration are never bricks. Contract and templates: `bricks/COMPONENT_GATE.md`, `_ASSIGNMENT_`, `_MANIFEST_`, `_INTEGRATION_REVIEW_TEMPLATE.md`. Ledger states added for this: `specified`, `candidate (B-nnn vN)`, `revision (Rk)`. | The gate already existed (COMPAT.md + `NcmCore.define` + dual-interpreter runner + `ncm-test.ps1 -CoreRoot`); inventing a parallel plugin system would create a second architectural authority. A brick must be removable without archaeology: one file, one MANIFEST line, one host call site. Code existing never advances an idea past `candidate` (L69). | IDEA-093; revisit after the first pilot (IDEA-089) round-trips once. |

## OPEN (for the owner)

Answered in batch 1: Q1 → L10 · Q2 → P11 · Q3 → L11/P2 · Q4 → L8/L12/P9 · Q5 → L13/P3 · Q6 → L14/P10.
Answered in batch 2: Q7 → L15/P1 · Q8 → L16/L17/P12 · Q9 → L18/P13 · Q10 → L19/P14 · Q11 → L20/P13 · Q16 → P15.
Answered in batch 3: Q12 → L21/L22 · Q13 → L23 · Q14 → L24 · Q15 → L25 · Q17 → L26 · Q18 → L27.
Scheduling tenet (2026-09-19): Q26 → L36 · Q27 → L37 · Q28 → L38.

| ID | Question | Why it matters architecturally |
|---|---|---|

| Q19 | *(answered by L54, 2026-09-20)* **Online progression model** (dimensions, how licences/grades are earned, how SR gates series). *Default assumption for the plan:* driver profile stores independent dimensions (`reputation`, per-discipline `grade`, `safetyRating`, accomplishments); no dimension gates entry in the first world. | Driver profile schema; eligibility rules. |
| Q20 | *(shape answered by L55; amounts still open)* **Economy design** (prices, starting money, acquisition, loss, repairs, team resources). *Default:* ledger exists, all amounts zero, no fees; money switched on per server later. | Ledger activation; garage acquisition. |
| Q21 | **Canonical NCX round format** (practice/quali/race, sprint weekends, multi-race). *Default:* content pack #2 ships a configurable weekend template; the reference format is chosen when NCX is tangible. | NCX content pack. |
| Q22 | **What exists between races** (venues, garages as places, meets, shops, ambient spectacle, world state such as district heat). Owner: active, expansive design area. *Default:* the world layer exposes hooks (places, presence, activity feed, promotion) so features can be added without re-architecting. | World layer scope. |
| Q24 | **Reference-world trust posture and the RB15 online.** Secured (inert-only: RB15 without ERS runtime/native plugin) vs unsecured for tester windows (MT, RB15 ERS possible with consent) vs pursue verification. *Default for the plan:* unsecured for tester windows 1–2, secured as the framework target. | Pack #2 physics identity; required-mod set; framework posture. |
| Q25 | **Shared inert handling baseline.** Should the Collection's *NCM Core* tier and the online world pin the same inert handling configuration (tweaks/INI) so SP and online driving converge, with executable handling stacks (MT/NCGT/etc.) optional and SP-only? *Default:* yes. | Catalog eligibility; E9. |
| Q23 | **Driver/contract market** for seats (transfers, signing, reserves rotation). *Default:* seats are content-defined with manual/admin occupancy changes; market rules later. | Seat occupancy service. |

## EXPERIMENTS (required before commitment)

Numbering follows [OPEN77_EXPERIMENT_PLAN.md](../research/open77/OPEN77_EXPERIMENT_PLAN.md); additions are suffixed.

| ID | Question | Status |
|---|---|---|
| E0 | Access, build pin, event-bus semantics, permission enforcement, restart | **passed 2026-09-19** ([record](archive/experiments/E0_2026-09-19.md)): two clients/identities; DB + idempotent migrations; `TriggerEvent` host-wide/queued (guide stale); tunables promote as documented; `state.save` survives reload not restart; readiness holds consistent (retest with long hold in M2); **open:** read natives may be ungated (`vehicles.all()` without permission returned `{}`) — retest in M2 with a vehicle present |
| E1 | Course conversion (one circuit, one endpoint root) with authored gates | not run |
| E2 | Two humans, server gate acceptance, adversarial cases, tie policy | not run |
| E3 | Grid/readiness/countdown/cleanup with canonical vehicles | not run |
| E3b | 20-car canonical spec grid with per-entry `appearance` (RB15 liveries) on two clients | not run |
| E4/E5/E6 | Platform AI on NCM course; fleet/handover; mixed timing | not run |
| E7 | Durable settlement | not run |
| E8 | Telemetry availability incl. whether server Lua can read drivetrain fields | not run |
| E9 | Performance ceilings and uniform handling INI | not run |
| E10 | WebUI HUD, worldui gates on stacked roads, private narrative | not run |
| E11 | Off-screen league at NCM roster scale | not run |
| E12 | Bounded ncm-core extraction (standings/box-score slice) | not run |
| E13 | Required-mod pipeline: NCM inert archives + livery archive hosted; RB15 via player-fetch; verify which Collection components are refused; whether requirements can be scoped below whole-server join; whether the launcher recognises a Vortex/Nexus-downloaded archive by hash; unsecured-mode join with one executable package; inert-only RB15 (no ERS) behaviour on a secured dev server | **run 2026-09-20, blocked upstream (KB-8).** Catalogue row + package list reach the launcher from the routable staging server (KB-7/KB-9 cleared), but every hosted hash is refused `Unverifiable` before download, in secured *and* unsecured mode (the launcher logs the cap lifted, then refuses); indexed loaders are `NotInIndex`. Warden: inert repack accepted (INERT), original RB15 zip refused (top-level folder, `.reds`); loader zips accepted only unsecured. Reviews queued for both NCM packages. **Inert RB15 works in multiplayer** once the client has the files: server spawns `Vehicle.v_sport1_rb15_f1` (Formula class, exact record, no `_player` variant) and the car renders and drives on staging. TW1 = manual install + launcher per-group restore + ArchiveXL/TweakXL plugin allow (P34). Player-fetch, Collections, scoping: not testable until verdicts work. |
| E14 | Spectator as non-entrant in an instance; race-control commands via ACL | not run |
| E15 | In-world (bucket 0) race with population on: measure per-client traffic divergence between two drivers on the same route; server-spawned obstacle fleet feasibility | not run |
| E16 | Platform request: AI speed cap raise/removal — owner to raise in OPEN//77 Discord; record the developers' answer and any build it lands in | owner action |
| E17 | Resource-driven GPS route: `blips.create{routable}`+`track` gives a pin but the engine computes the road path only after tracking is cleared and re-set (map open does the same); `clearWaypoint`→`setWaypoint` from a hand-set waypoint re-routed at once, but a fresh `/ncm.gps` still needs one map open/close to draw (KNOWN_BUGS KB-1). Same session: `open77_interactions` keys are keyboard-only (pad = polled `input.isDown("padX")`, permission `input.actions`); prompt show distance ≤ 250 m; bag writes need `state.write`; `open77_uikit` not shipped in .82 (missing dependency stops every resource) | **passed 2026-09-19** |
| E18 | Platform question (owner to raise in OPEN//77 Discord): **identity portability.** Docs say "each installation has a persistent cryptographic identity" and "the private key never leaves the Windows identity store"; the only multi-identity mechanism is per-installation profiles (`OP77_IDENTITY_PROFILE`). No documented sign-in / export / recovery / "use my identity on a friend's PC" flow as of 2.31.13+op77.78 docs. Ask: is a temporary sign-in on another machine planned, and what happens to a `userId` after a reinstall (recovery)? NCM stays on `userId` only (never fingerprint/public key/endpoint) and plans an operator-level driver rebind (M11) for lost identities. | owner action |
| E19 | Prop/venue scale: server prop quota, N barriers along a 3–4 km course, client FPS/stream-in at speed, which `barrier.*` aliases block a car, `race.checkpoint` host usability | not run |
| E20 | Crowd scale: passive NPCs at 50/150/300/500 in authored zones — client FPS near the grid, lease cost, snapshot cost, stream-in at approach speed; vanilla crowd density as ambient layer | not run |
| E21 | Package audio: zoned 3D crowd beds + PA emitters + client music crossfade across event phases; audibility on approach; balance against engine audio | not run |
| E22 | Sanctioned venue in the shared world: `clearArea` + bucket traffic reduction vs controlled bucket with admitted spectators; per-client traffic divergence on the circuit; NCPD off | not run |
| E23 | Orientation media in the client WebUI: bundled VP9/Opus WebM (~15–25 MB, `web_files`) in a modal page with skip/done bridge vs unlisted YouTube embed; download time on a fresh join; audio balance; fallback when neither plays | not run |
| E24 | Navigation for route plans: does `setWaypoint` re-route without a map open once a route exists (KB-1 at speed is unacceptable); worldui/prop gate visual language (branch rings vs universal cylinder/`race.checkpoint`); does branch-gate placement make the engine's road route follow the intended branch | not run |
| E25 | (observation, unplanned) Is an `unlisted` server private? Two strangers walked into staging 2026-09-21 23:27–23:41 UTC while it was `Visibility=Unlisted, masterListing=enabled` | **observed 2026-09-21** ([record](archive/experiments/E25_2026-09-21_walk-in.md)): not private in practice; cause unknown (staff view vs. ordinary discovery); reported to devs; KB-36/41/42, IDEA-091/092 |
| E0-note | A dedicated-server package **2.31.13+op77.82** exists locally (Downloads, 2026-09-18) while the hosted MCP index tops out at .78 ("no index published for .82"). E0 must record the actual server/client build; API cards are a lower bound until the index catches up. | recorded 2026-09-19 |

## 2026-09-23 — L106: owned-asset access after purchase (LOCKED contract)

Purchase transfers persistent title and never creates a runtime vehicle at checkout. Machine Index reuses the
Collection's discovery wall and presents the owner's separate assetIds. CALL operates on one existing asset,
not a model or generic replacement. Server identity and fresh SQL title authorize access; runtime possession
never establishes ownership. Calling writes no asset, ledger, market-stock or purchase rows. Existing runtime
representations are reused/refused rather than duplicated. No garage or delivery AI is in this slice.

The F6 shell order is RACE GUIDE | MARKET | MACHINE INDEX | HELP. SHELL_TABS/renderNav in panel.html is the one
navigation definition; Help is always final and future gameplay surfaces go to its left. F10 remains a direct
Machine Index shortcut. Guide content scrolls inside the area above the stationary navigation.

PROVISIONAL implementation: ncm_world/server/vehicle_access.lua reads title but does not mutate league-owned
persistence. Its client adapter probes four nearby candidates with static/dynamic support and clearance rays.
Server rechecks owner, request lifetime, movement, bucket and nearby shared entities before exact-record creation.
The first envelope admits only the three Base Market records; other models refuse honestly. Probe failure leaves
ownership untouched. Client geometry is evidence, not server-verifiable collision authority. Thin geometry,
traffic races and platform streaming require live QA; no native road-arrival or volumetric sweep is claimed.

This explicitly supersedes KB-68's earlier proposed kerbside creation at checkout. L102 continues to forbid free
player-invokable issuance/minting; calling an already-owned asset is access, not acquisition. No deployment or live
CALL test occurred in this session. Evidence and pending gates: QA 2.17 / §AB; research evidence/2026-09-23-access.

2026-09-23 14:40 UTC deployment update: IDEA-199/L106 shipped to staging at the user's request. Clean boot and storage restart verified; live CALL/UI/geometry QA remains pending (MASTER_TEST 2.17).

## L115 — LOCKED — Navigation is one owner, changes intent at entry, and uses the platform's routing recipe

`ncm_world/client/nav.lua` is the only thing in NCM allowed to set the player's GPS destination.
`calendar.routeTo` and `race.gpsTo` are now spellings of it. Two independent waypoint setters that could not
see each other is what produced KB-81.

**Navigation intent changes on a successful ENTER RACE, not at lights-out.** Once a driver is standing at the
venue and entered, the venue route has served its purpose and the useful destination is the course. Doing it
at entry also gives them the entire pre-start window to notice a route that has not drawn and refresh it
themselves, which is the whole mitigation for the item below.

**The map open/close workaround was never a REDengine limitation, and IDEA-052 is superseded.** The shipped
OPEN//77 race gamemode (`gamemodes/freeroam/race/client/main.lua`) states it plainly: a bare waypoint only
moves the pin, `Open77.blips.create{routable=true}` uses Cyberpunk's custom-waypoint definition "which is what
wakes the native GPS pathfinder and its vehicle line effect", `Open77.blips.track(id)` selects it and must be
re-issued after an update, and — the sentence that explains every symptom we had — *"the vanilla GPS
controller snapshots pedestrian/vehicle context when tracking starts; selecting the point before the car
materializes can leave a valid manually-tracked id with no minimap road route for the whole heat."* NCM set
its waypoints on foot at a venue. So NCM now re-tracks whenever the seat context crosses, and verifies
periodically, exactly as the platform's own code does. `setWaypoint` is retained as a fallback for a build
without routable blips.

L70 is unchanged and unweakened: **NCM never opens the player's map for them.** The map-refresh workaround is
documented for the player in Help rather than automated, and `/ncm.gps` is a recovery tool, never a step in
racing.

## L116 — LOCKED — Withdrawn and forfeited are different facts about different objects

> **WITHDRAWN = entered but did not start. FORFEIT/DNF = started but did not finish.**

A withdrawal edits an entry row before the race exists. A forfeit is a sporting fact about a session, and the
kernel already models it (`session.race.leave`: DNS before green, DNF after). The previous rule — "a check-in
is a commitment, only interest may be withdrawn" — was not wrong so much as misplaced: what cannot be taken
back is a race you have *started*. Applying it to a check-in made the venue panel's WITHDRAW refuse the only
state it is ever offered in (KB-82).

Consequences that are now load-bearing:

- A check-in that has not started is withdrawable, and the driver may enter again while entries are open.
- A driver held by a live session is refused, and the refusal **names the forfeit command** rather than
  leaving them stuck.
- A classified entry (`finished`/`dnf`/`dns`/`dsq`) is refused as `already_raced`. Under L74c a result is
  history; withdrawing one would rewrite it.
- A forfeit never destroys the session for other entrants. Whether the race then ends is the kernel's
  ordinary decision, identical to any other retirement.

## L117 — LOCKED — An offering is not an asset, and primary supply is produced toward a ceiling

> **FINITE SUPPLY DOES NOT MEAN FINITE FOREVER.**
> **BASE MARKET IS A MARKET, NOT THE MARKET.**

**Offering vs asset.** A model OFFERING is a persistent shelf position in a market. An ASSET is one
individually identified physical vehicle standing on it. The Market payload was a list of assets, so buying
the only MaiMai did not sell the MaiMai out -- it removed the MaiMai from NCM (KB-85). Offerings are now
authored and permanent; stock is a state of the offering, and `0 / 8` is a thing a market says, not a thing
that makes a market disappear.

**Production.** Each offering authors a `ceiling`, a `batch` and a `cadence`, and every tick mints
`min(batch, max(0, ceiling - available))` real assets. Ceiling-**seeking**, not ceiling-checking: a skipped,
partial or lost tick is corrected by the next one, and no sequence of ticks can put the shelf above its
ceiling.

- **Cadence and batch are never collapsed into a rate.** "1 every 30 min" and "2 every 60 min" share a
  long-run average and are different supply chains. Averaging them away would delete the only thing that can
  later make one manufacturer feel unlike another.
- **The ceiling governs unsold primary inventory, not world population.** Purchased cars leave the shelf and
  exist forever; the vacated capacity refills. A model with a ceiling of 4 will produce far more than 4.
- **A ceiling lowered below current stock pauses production. It never destroys assets.** `plan` floors
  capacity at zero and has no concept of removal.
- **Every produced unit is a real asset** with its own `assetId`, resolved `vehicleKey`, class and
  deterministic factory finish (L111), through `NcmOwnership.manufacture`. There is no abstract count that
  later becomes a car, and no parallel vehicle identity.

**Idempotency is derived, not remembered.** Tick `n` is `epoch + n * cadence`, so a restart, a redeploy, a
retry and a second scheduler all compute the same answer. The host claims a tick by writing
`market_production_run` (PK: server, market, model, tick index) **before** minting, and verifies the claim by
reading its own nonce back rather than trusting an affected-rows count -- whether a driver reports `INSERT
IGNORE` as 0, an insert id, or nothing is not something vehicle manufacture may rest on. Restarting NCM is
not a vehicle-printing exploit, and was proven not to be against the live world.

**Stock is derived, never counted.** Availability is a query over unsold, unowned, listed assets. The Market
cannot say 8 when 7 purchasable rows exist.

**There is no one-per-player rule, and there never was one.** The "one machine per listing" wording was
inherited description of a three-asset bootstrap. Ordinary human economic behaviour -- buying several,
holding, later reselling -- is not prohibited by the substrate. Hoarding, cornering and secondary-market
power are future governance questions and will not be pre-solved by falsifying ownership or supply.

**Discovery follows player-facing exposure.** Selecting an offering and looking at it is a legitimate
encounter with that model and may credit a Machine Index discovery, at any stock level including zero.
Canonical catalogue membership alone discovers nothing, and building the Market payload is not exposure.

## L118 — LOCKED — A manufacturer may change how fast it refills the shelf, and nothing else

> THE MANUFACTURER MAY CHANGE HOW QUICKLY IT REFILLS THE SHELF.
> IT MAY NOT MOVE THE SHELF, CHANGE THE PRICE, JUDGE THE BUYER, OR BREAK OWNERSHIP.

L117 stands; this narrows what is allowed to move inside it. Ongoing cadence and batch are no longer fixed
forever. Everything else an owner could care about is.

**The authority boundary is two numbers.** `economy.supply_profiles` returns a next batch quantity and a next
interval, clamped into an authored envelope. It has no path to price, shelf capacity, identity, ownership,
provenance or an existing asset. It cannot confiscate, cannot destroy, and cannot decide somebody owns too
many.

**It reacts to demand, never to a buyer.** The fact bundle it consumes contains counts, ratios and durations
and **has no field capable of carrying an identity** — so ten sales to one player and ten sales to ten players
are literally the same input. That is a structural guarantee, not a rule someone has to remember, and a test
asserts the bundle's shape. There is no hoarder, scalper, whale or manipulator anywhere in this system.

**One mechanism, parameterised.** Pressure from bounded signals → gates (cold start, dead zone, persistence,
cooldown) → a bounded integer step along a ladder of legal (batch, interval) rungs. Three personalities today
(`steady_hand`, `volume_responsive`, `scarcity_keeper`) differ only in numbers, so a hundred future models
scale through data rather than a hundred formulas.

**The ladder is how discrete production survives a continuous calculation.** A response naturally implies a
fractional rate, and there is no such thing as 1.8 Hellas. The envelope is expanded into every legal discrete
pair, ordered slowest to fastest; a decision is "move at most N rungs". Integer production, envelope clamping
and bounded adjustment become one fact. Equal-rate rungs are kept, never merged — 1-per-30-min and
2-per-60-min remain different market behaviour.

**Signals, and one the simulations forced us to reject.** The engine reads supply/demand *imbalance* over a
rolling window, plus sold-out and glut streaks. The first design used raw sales velocity and was wrong in the
most important case: a market in perfect equilibrium sells exactly what it produces, which velocity reads as
maximum demand and answers by raising production forever. Imbalance is also weighted by how material the flow
was, because a ratio is most sensitive when the numbers are smallest — without that, one car sold against none
produced reads as infinite demand and a single purchase could move a schedule.

**A committed schedule is a commitment.** An evaluation always runs *after* its event has fired and decides
only the event after it. A player watching "2 vehicles in 47 minutes" gets that event; what changes is what
comes next. Nothing revises a countdown already on screen.

**Determinism, not randomness.** No RNG anywhere. Unpredictability comes from real players creating changing
inputs against different profiles, which is reproducible, QA-able and forensically explainable. A clever
player reading the market correctly is not an exploit; a deterministic interaction that can be mechanically
repeated for unlimited advantage is, and the gates exist for that and not for punishing insight.

**Restarting is not a lever.** The committed plan and the profile memory persist. A restart resumes; it does
not re-roll, reset to default cadence, duplicate a batch or skip one.

**Players are told THAT schedules move, never how.** The Market states current stock, capacity, next event,
next batch and current cadence, plus one sentence: manufacturers set their own production and schedules
respond to market conditions. Profile ids, parameters, thresholds, weights and lookbacks are server-side, and
a render assertion forbids them reaching the panel.

## L119 — LOCKED — A machine has a birth certificate, an odometer, and one day a death certificate

Production stopped being an inventory count the day it started making individual persistent machines (L117).
So each machine can now answer: what number NCM vehicle was I, what number from my manufacturer, what number
example of my model, how far have I actually travelled, and am I still an active machine.

**Five identities, never collapsed.** `vehicleKey` is the conceptual model, `record` a TweakDB runtime
configuration, `vehicleId` an ephemeral live entity, `assetId` this specific persistent machine, and the
ordinals are immutable provenance attached to that assetId. A new `vehicleId` after a CALL is not a new car.
A new owner is not a new car. New paint is not a new car.

**Ordinals are history, not array indices.** Three independent append-only sequences — global, manufacturer,
model — because they are three different facts. The first Ferrari need not be global #1 to be Ferrari #1.
Once assigned, a number is never changed, reused, compacted, renumbered around a deleted record or derived
from `COUNT(*)`; a retired car keeps its place forever. **Unique, immutable and auditable beats cosmetically
gapless**, so a failed transaction that has already reserved a number leaves a gap and that is correct.

**Concurrency.** A batch reserves one contiguous range per sequence in one optimistic claim — move the
counter only if it is still where we saw it, stamp a nonce, read the nonce back — and three unique indexes
make a duplicate physically impossible even if the allocator is ever wrong.

**Manufacturer identity is authored, not parsed.** `MAKER_KEY` maps a display name to a permanent key, so a
rename edits the mapping and never forks a manufacturer's history. Deriving it from the vehicleKey prefix
would have been wrong: `ncx_rb15` is Red Bull Racing.

**Only manufacture consumes ordinals.** Admin and progression cars are `origin = grant` with no serial: a
debugging session must not burn Ferrari #14.

**Mileage belongs to the assetId.** Measured server-side from the vehicle's own position at 1 Hz *while
occupied* — not from the client (which could edit a figure that may one day cost someone their property), and
not from the driver's position (which would count them walking around their own parked car). An empty vehicle
being shoved or towed is not travelling. Reconstruction never invents kilometres: a changed asset, a gap, or
an impossible speed are all rejected by one filter, which is how CALL materialisation, teleports, restarts,
streaming reloads and administrative relocation are all handled without four special cases. Checkpointed at
250 m or 60 s, so a crash costs at most that much — bounded and stated.

**Terminal does not mean deleted, and nothing dies yet.** `TERMINAL_FAILURE_ENABLED = false` and `canRetire()`
refuses every request. The state exists so that future retirement never requires a `DELETE`: a retired machine
keeps its assetId, all three ordinals, its provenance, its owner, its final mileage and its race history. It
stops being drivable; it does not stop existing.

**Two rules that constrain the future feature before it is written.** A bug is not a death — a missing runtime
entity, a failed materialisation, a refused CALL or a migration fault must never be read as mechanical
failure, so retirement will always require one explicit authoritative transition. And **cars must never be
destroyed to control economic supply**: manufacturer production governs the faucet (L118), vehicle lifecycle
may one day govern a use-driven drain, and mortality is never coupled to world vehicle population. If a
hundred dormant players return with their cars, demand falls and the supply profiles adapt — nobody's
property is deleted to restore scarcity.

## L119 — AMENDED 2026-09-23 — the mileage-to-mortality link is struck

The owner struck it: *"previous odometer = eventual car death clock is struck from the record, replaced by
systems below."*

**What is withdrawn:** the intended future in which authoritative mileage approaches a hidden deterministic
per-vehicle lifespan and the machine suffers irreversible terminal mechanical failure. The survival-curve
design, the hidden threshold and the "cars eventually die of their own use" direction are all withdrawn
(IDEA-235 struck).

**What replaces it:** vehicle use will predispose installed **components** toward mechanical conditions, and
components are serviceable, replaceable and tradable. A machine therefore degrades and is repaired rather
than reaching a private expiry date. See `18_PARTS_ECOSYSTEM.md`.

**What survives unchanged, and why:**

- The **odometer** itself. It was never only a death clock — it is provenance, it is what makes a
  212,000 km survivor a different object from a 14,000 km one, and it will now calibrate component exposure
  instead.
- The **lifecycle state and its disabled flag**. `retired_terminal_failure` remains representable and
  `TERMINAL_FAILURE_ENABLED` remains `false`. A permanently retired machine must still be expressible
  without a `DELETE`, whatever eventually causes retirement — and now nothing is scheduled to.
- **"Terminal does not mean deleted"**, and **"a bug is not a death"**. Both are about how retirement must
  work if it ever happens, not about what triggers it.
- **"Cars must never be destroyed to control economic supply."** Unchanged and arguably more important now:
  with parts entering circulation, the temptation to drain vehicle population will only grow.

## L120 — LOCKED — the engineering and lifecycle substrate, as accepted

Accepted by the owner on 2026-09-23 from `21_ENGINEERING_PROPOSAL.md` and `22_WEAR_PROPOSAL.md`. These are
architecture decisions; **nothing is implemented and no tuning value is chosen.**

### Accepted outright

1. **Time regimes belong to the OPERATION, not the discipline.** Every engineering operation declares
   `bench` (synchronous, social, immediate) or `project` (asynchronous, committed, survives logout). The
   split cannot follow discipline lines because Diagnostics holds both the fastest operation in the system
   and one of the slowest.
2. **Bounded competency vs unbounded design knowledge is the fundamental storage distinction.** Competency is
   what you can *do* — at most 27 values per engineer, forever, with ceilings. Knowledge is what you know
   about a *design* — one row per driver x design, growing without limit, a ladder rather than a level. They
   are separate tables because one is bounded and one is not. Capability requires **both**.
3. **Inspection is the first engineering vertical slice.** It needs no component assets to exist, it is not
   blocked on the mechanical-effect audit, and it still exercises the whole substrate.
4. **Wear is derived, never rolled**: from a stable authored profile, a per-component seed, accumulated
   exposure and service history. No periodic random rolls, anywhere.
5. **Immutable exposure, derived condition** is the fundamental lifecycle architecture. Exposure is additive
   only and never reduced; condition and severity are never stored at all.
6. **Component assets and exposure accrual ship together**, in the same release. A kilometre not recorded is
   a kilometre that never happened, and unlike a derived condition it cannot be reconstructed later.
7. **The AG5/AG6 + soak gate precedes economic consequences.** Exposure may accrue before conditions exist,
   but no condition may carry mechanical or economic weight until odometer integrity is proven. Once distance
   is economic data, a measurement artifact stops being cosmetic and becomes an exploit.

### Provisionally accepted, pending review of the ontology itself

**15 skills across 5 disciplines, plus 12 mechanical families.** Accepted as a shape, not as a list.

The owner's condition is explicit and is now honoured in the proposal: *"we should not force Diagnostics into
workmanship semantics merely to preserve symmetry."* Diagnostics produces information, not workmanship, so
its three skills are **breadth / precision / depth** — deliberately not the floor/spread/ceiling reading used
for the workmanship disciplines. The symmetry is allowed to break where it does not describe reality.

### The reconciliation — where the two systems touch mathematically

The owner identified that the first draft's derivation subtracted serviced conditions as a **set**, which
would have made a botched repair and a master's repair identical. That contradicts the engineering
addendum's *"a weak repair may restore functionality while leaving some disadvantage"*, and it is precisely
the seam between the two proposals.

**Resolved: a repair does not clear a condition. It advances that condition's threshold, by an amount its
workmanship earned.**

```
effectiveThreshold(c) = baseThreshold(profile, seed, c) + sum of relief from services on c
overshoot(c)          = exposure - effectiveThreshold(c)
active(c)             <=> overshoot(c) >= 0
severity(c)           = g(overshoot(c))
```

Consequences that are now structural rather than remembered rules:

- A **botched** repair grants ~0 relief: work happened, nothing was fixed.
- A **weak** repair grants less relief than the overshoot: the condition persists at reduced severity —
  exactly "restored functionality, left some disadvantage".
- An **excellent** repair clears it and buys real distance before it is due again.
- **Exposure is never reduced.** The threshold moves, the odometer does not. An 18,000 km component stays an
  18,000 km component whose gearbox condition is simply not due again until 23,000.
- **Relief must have diminishing returns**, or paying a master repeatedly would hold a component in permanent
  adolescence and break "wear is monotonic pressure". Bound per-service and/or cumulatively; author both and
  disable one until play data arrives.

**The interface between the two systems is one number.** A repair operation emits `relief_m`, persisted on
the service record and never recomputed. That is the *only* value engineering hands the wear derivation.
Workmanship moves a threshold; it never cancels exposure, and the two are never summed.

This is also what makes an engineer's reputation mechanically real rather than decorative: two engineers
service the same gearbox, and the difference shows up in how long it stays fixed.

## L121 — LOCKED — version control, and the workshop is standing

Owner direction, 2026-09-24: *"we need to turn the windows server back on, port our lightsail work there... maybe
first order of business is actually a private github repo with our code, and in fact this would help us port to
server 2 in general... any lightsail updates in the future will have been instrumented on windows first."*

### 1. The repository is the transport, not just the backup

The repo was made first because it solves both problems at once. Until 2026-09-24 the only defence against
losing this work was a hash inventory (M0.1 criterion 8) and the idempotence of the deploy scripts. There was no
history, no branch, and no copy off this machine of the entire NCM Online implementation, the published
single-player payload, and ~470 KB of design record.

`github.com/evengineer1ng/ncm-online`, private (verified: unauthenticated API returns 404). 644 files, ~11 MB.

**What is tracked is what we wrote.** The workspace is not one package -- it is authored source, downloaded
runtimes, release snapshots and recovered game assets sharing a folder. ~1.9 GB is excluded, and `.gitignore`
states which of three reasons applies to each path: re-downloadable binary, content we may not redistribute, or
machine-local state. The RB15 livery artwork is excluded on the second and first grounds together and therefore
**still has no backup** (`IDEA-293`) -- recorded rather than quietly dropped.

**No secret has ever been in the tracked set.** Credentials are DPAPI-encrypted outside the workspace and
`server.jsonc` is ignored; verified by scan before the first commit. That discipline, established long before
there was a repo, is the only reason this could be a same-day decision.

### 2. NCM Development is running; NCM Online is untouched

L112 described this split and said "not now", gated on the ordinary-player spine. That gate still stands, and
**nothing about the live world changed**: `serverId` is still `ncm-dev`, it is not renamed, and
`deploy-staging.ps1` still defaults to `-Target online`. Those are cutover steps 3-6 and they remain the
owner's call.

What was done is steps 1-2 only, because standing up the workshop never required touching the world:

| | before | now |
|---|---|---|
| OPEN//77 | `.82` | `.87` — 704 files verified against the package manifest |
| load list | 35 entries, `.82`-era | mirrored from production's **actual** 39 |
| database | MariaDB **13.0**, at migration 005 | MariaDB **10.11.14**, at 023 |
| identity | would have defaulted to `ncm-dev` | `serverId = ncm-devbox`, `environment = development` |

### 3. Version parity is not pedantry, and the direction of error is the whole argument

`16_ENVIRONMENTS.md` claimed "MariaDB: same engine both sides." That was **false** by 2026-09-24: the box had
13.0 (winget's only build; it has no 10.11 at all), production runs 10.11.14.

A newer engine **accepts** syntax an older one rejects. So the failure mode is not symmetric: the dev box would
go green and production would still break. **False greens flow downhill into the canonical world; false reds do
not.** An environment whose job is to catch problems before production cannot be the more permissive of the two.
Pinned to 10.11.14 from the official archive, checksum-verified, via `tools/db-pin-1011.ps1`.

The existing migration discipline paid for itself here: every one of 23 migrations declares `CHARSET`/`COLLATE`
explicitly, so the 13.0 dump restored into 10.11 without a single collation rewrite. The default collation
changed in MariaDB 11.5, and that would otherwise have been a silent, tedious divergence.

### 4. The box earned its keep before it finished booting

Three defects in the first hour, all of which production hides:

- **KB-51 reproduced, and stopped.** `.87` makes `freeroam` depend on `open77_cyberware_lab`; the local load
  list did not have it. That aborts the *entire* automatic start set while the server still listens and
  registers with the master -- healthy-looking, NCM absent. It cost an hour of production downtime once. The
  guard caught it on the candidate tree **before the swap and before any start**. `check-load-list.py` now takes
  the server root as a parameter, because a guard that only runs in production runs too late.
- **KB-93**, a duplicated schema entry in the manifest, harmless only because the loader de-duplicated the path.
- **KB-92**, a `SQL 1146` that only fires when the schema is behind the code -- i.e. on every fresh install,
  and never in production.

**This is the argument for the whole exercise, made by the exercise.** All three are invisible on a
long-running, already-migrated server.

### 5. Standing rule

**Lightsail changes are instrumented on Windows first.** Not ceremony: the point is that a change is *tested
somewhere* before it reaches a world with durable player property in it. The promotion procedure is the one
already written in `16_ENVIRONMENTS.md`; it now has a real environment behind it.

### L121 addendum — the legacy dev rows were relabelled, not deleted (2026-09-24)

The development database still held 110 rows keyed `ncm-dev` — the live world's identity — from the
2026-09-19/20 sessions. Owner: *"whats your take on the rows? relabel? whatever is safest."*

**Relabelled to `ncm-devbox-legacy`.** The label is not a fiction invented for tidiness: those rows were
always written by *this box*, during the period when it happened to share the serverId production had also
chosen. `ncm-devbox-legacy` states what is true — this machine, earlier. The old label's collision with
production was the inaccuracy, not the fix.

Checked before deciding, because "safest" turns on what the rows can actually reach:

- **They were already inert.** The money guard (`market.lua:455`) filters `l.server_id=?` inside the
  purchase transaction, and the identity binding (`identity.lua:77`) filters `b.server_id = ?` and joins
  `p.server_id = b.server_id`. A legacy balance could not have funded a purchase and a legacy binding could
  not have resurfaced as an identity.
- **Deletion was the more dangerous operation, not the safer one.** 69 child rows — `entry` 21, `seat` 20,
  `session` 13, `session_result` 15 — hang off those 57 events, and **none of those tables carry
  `server_id`**; they are scoped transitively through `event_id`. Deleting therefore meant cascading 179
  rows across 10 tables in foreign-key order, and the FKs would have failed a naive attempt partway. The
  relabel touches no foreign key, collides with nothing (checked against every unique index on the six
  tables — `driver_profile` and `ncm_driver_binding` and `team` all key on `server_id`, and the target value
  did not exist), and leaves every child correctly attached because `event_id` never changes.

Targeted restorable backup taken first: `ncm-devbox-legacy-rows-<stamp>.sql` under the NCM backups folder,
`--complete-insert`, restorable against the current 023 schema rather than the older pre-migration full dump.

Result: **zero rows anywhere on the development box now wear production's identity**, in the database or in
any dump taken from it. The running server did not notice — same single boot error, scheduler unaffected.

**The general rule this establishes:** when a `server_id` relabel is on the table, check for child tables
that lack the column. Scoping by transitive join is invisible to a `WHERE server_id=` survey, and it is what
decides whether relabel or delete is the smaller operation.

## L122 — LOCKED — the ledger is classified by cost-of-being-wrong, and one foundation is already leaking

Owner direction, 2026-09-24: *"organize it and classify what has been started, finished… and of things that
havent been started or finished, tag the ones that are high priority foundational, data, schema, etc type of work
that the server / future server ambitions hinge on… we cant slip up on things like serialized cars… those
serializations need to exist in their relative final form before touching production anymore… id rather be parked
at the door for design work later than find out after building on weak foundation."*

### The organising axis

`State` already said how far along a row is. What was missing was **what kind of thing it is**, because that is
what decides how expensive it is to get wrong. Every one of the 177 rows now carries a `Class`:
**F0 / F1 / INV / GATE / SYS / UI / OPS / UP / DSN**, with `·LIVE` marking a shape production already stores.

Nothing was pruned (L68 holds). 177 IDs in, 177 out; no ID lost, invented or duplicated; every row's original
content byte-identical apart from the added column. The 14 **done** rows moved to a `## Completed` section at the
bottom under their original headings — a row is not done because it is built, only when a live PASS sits beside it
(L69), so *built, pending live validation* stays above.

### The split is real, not a feeling

Of 163 open rows: **35 are data-model or schema** (F0/F1), **14 are invariants** that constrain that model, **6 are
gates**, and **28 are UI that can wait indefinitely**. The owner's suspicion that "there's a decent amount of this"
was an understatement.

### The finding that justifies the whole exercise

**`IDEA-236` is not a future risk. It is a present loss, measured against production on 2026-09-24.**

Production holds **29 completed race results, none attributable to a machine — and not reconstructible.** The whole
chain was checked rather than the one table: `session_result` has no `asset_id`, and neither does `entry`, nor
`seat`. The car actually fielded is recorded **nowhere**. It cannot be inferred from ownership afterwards, because
a driver may own several machines and NCX team cars are not assets at all (`IDEA-238`).

So every race run between now and that column existing is a permanently anonymous result. It is forward-only and
cheap to add, and impossible to backfill — the exact shape of mistake the owner was describing, already happening.

This also sharpens *why* the serialisation work (`IDEA-226`/`227`, live-verified) matters: ordinals give a machine
an identity, but without `IDEA-236` that identity has no competition history to attach to. The Machine Profile
(`IDEA-237`) is blocked on it, and wear and engineering both need to know **which machine** did the distance.

### The rule this sets

**Before production takes more data of a given shape, the F0 items for that shape must be settled.** Presentation
is explicitly exempt — the model does not need the UI, the UI needs the model. Standing at the door for design work
is cheaper than discovering the foundation after building on it.

Corollary, learned twice now: **the "next free ID" line has been stale twice** (left at IDEA-127 while the ledger
ran to 183, then at 205 while it ran to 294). It is the only guard against reusing a permanent ID. Checking it
against the last row is now part of appending.

## L123 — LOCKED — the Q1–Q70 answer pass, and the ten governing principles

Owner answered all seventy questions of `23_OPEN_QUESTIONS.md` on 2026-09-24. Reconciliation against the
repository is `24_FOUNDATION_RECONCILIATION.md`. **Nothing implemented; stopped for review as instructed.**

### The governing principle the pass established

> **Do not preserve exceptions created by obsolete prototypes as permanent ontology.**

A car is a machine asset. A component is a component asset. "Team car", "grid car", "street car" describe use,
custody, ownership or history — not species. TW2-era grants, temporary NCX equipment behaviour and alpha/debug
conveniences are implementation artifacts, and must not become architecture merely because they still exist in
documentation. The purpose of the pass is **preparedness**: where a modest decision now prevents a painful
retrofit later, prefer being prepared.

### The ten cross-cutting decisions

Identity for persistent physical things · history is append-oriented · unknown history stays unknown · world
identity is distinct from runtime identity · property is conserved (destructive reverse engineering is the one
defined exception) · prepare seams without simulating them · record irrecoverable facts early · Development
proves and Online confirms · alpha scaffolding is not ontology · prefer shared primitives over isolated fixes.

### What the reconciliation found

**Most of this is already designed and blocked on one missing primitive.** The answers to Q4, Q6, Q15, Q45, Q46,
Q48, Q50 describe a world `14_TEAM_ORGANIZATIONS.md` (L92/L93) and `IDEA-139/142/157/162/168` already specify.
They are blocked on the same thing: **NCM has no principal that can hold title, money or custody — everything is
keyed to a driver.** Migration 015 named `owner_principal_kind/id` in writing as "a cheap later ALTER"; the
foresight was recorded and never spent. So `14_TEAM_ORGANIZATIONS.md` is **reaffirmed, not superseded**, and
becomes the specification for that work.

**Ten primitives satisfy most of the seventy answers**, four carrying the weight: **owner principal**, **physical
asset** (shared supertype of machine and component), **custody** (which makes install/remove/store/list/trade one
operation shape), and the **transfer envelope** (atomic multi-item settlement, replacing a per-asset idempotency
key that cannot express "car + part + cash ↔ car + cash").

**A constraint found that the effects audit must be given, not left to discover:** `setPerformance` is one profile
per vehicle, does not stack, and class homologation ceilings already claim it (`IDEA-079`/`IDEA-102`). The real
question for `IDEA-249` is therefore narrower and harder than "what can we manipulate".

### Corrections recorded against my own prior work

- **L122's counts were drawn from 57% of the ledger.** A row-matcher skipped 119 rows whose IDs were bolded.
  Corrected: F1 58 · F0 24 · INV 38 · GATE 10 — 82 foundational rows plus 38 invariants, not 35.
- **`IDEA-239`/`IDEA-240` are duplicate IDs, and mine** — a second instance of the `IDEA-190` collision, both
  pairs appended while the header's "next free ID" still read IDEA-205. Annotated, not renumbered: L68 makes IDs
  permanent and the remedy is the owner's call (`IDEA-296`).
- **Q57 was overstated by me.** Having checked, the behavioural substrate largely exists — `incident` already
  records session, both drivers and a severity band. What is missing is machine attribution on those rows. Q57 is
  real, but it is not bleeding the way Q1 is. What *is* bleeding, measured: 29 unattributable results, 9
  driver-only incident rows, and `player_market_knowledge` with 0 rows since migration 017.

### Open

Five answers are needed before Stage 1 can be designed rather than guessed: **A1** `origin` semantics (it does two
unrelated jobs today and Q6 abolishes one of them), **A2** whether team machines draw from the same serial
sequences, **A4** whether "owned exactly one asset at the time" counts as authoritative attribution for the 29
legacy results, **A5** whether a player-visible condition with no mechanical effect is acceptable in the interim,
and the Q18/Q19 architecture-profile representation the owner asked to see first.

## L124 — the A-series rulings: A2 and A5 locked, A1 and A4 explained and awaiting judgement

Owner review response, 2026-09-24. **Stop remains in effect; nothing implemented.**

### A2 — LOCKED. Team machines use the same serial sequences.

> *"A team machine is a machine… The exclusivity belongs upstream in access and distribution, not in the identity
> of the resulting asset."*

An NCX machine consumes the same global/maker/model ordinals as any other machine from that manufacturer. There
is no NCX serial universe and no NCX asset exception. The owner path is:

```
qualify / control organization → gain market + distribution access → organization purchases →
manufacturer supply consumed → ordinary machine asset minted → organization principal owns it
```

**Consequence, and it is a real one: exclusivity now has to be carried by market access**, because it is no
longer carried by identity. That makes restricted/qualified market access a *requirement* rather than a
flavour feature, and it lands on `IDEA-254` (distribution scopes) and `IDEA-251` (discovery). Filed as
`IDEA-298`. Encouragingly, `player_market_knowledge` already carries an unused `access_state` column — the seam
was cut in migration 017 and never used.

### A5 — LOCKED. Interim visible conditions are acceptable; the interim must not become the model.

A condition may be determined, persisted and surfaced through supported presentation (glyph, warning state,
diagnostic readout) **before** its mechanical consequence is enabled. The distinction that matters is
**authoritative condition state** vs **downstream mechanical/presentation effects of that state**.

Two guards the owner attached, both recorded as binding: **do not invent fake effects** to make an interim
condition feel complete, and **do not let information-only become the permanent product model** — the intended
mechanical consequence stays explicitly represented as gated and unimplemented. This amends the softer reading in
`24_FOUNDATION_RECONCILIATION.md` §9 stage 11: conditions are not "information-only", they are
*consequence-pending*.

### A1 — explained, not ruled. The field is emptier than either of us assumed.

Measured, not inferred:

- `origin` holds `production` or `grant`, added by migration 023 with **`NOT NULL DEFAULT 'production'`**.
- **Production contains 19 assets, all `origin = 'production'`. `grant` has never been used in the live world.**
- **Nothing in the codebase branches on `origin`.** Its only reads are one `SELECT` and one log line in
  `provenance.lua`. It is effectively write-only.
- `Identity.consumesOrdinals()` exists to express the serialisation gate and **is never called outside tests**.
  The real gate is `local origin = ord and PRODUCTION or GRANT` — origin is *derived from* whether an ordinal was
  allocated, not the thing that decides it.

**So my "two unrelated jobs" framing in `24` was wrong and is corrected here.** `origin` does not gate
serialisation. It is a **redundant, write-only restatement of a decision already recorded by the presence or
absence of `production_ordinal`**. Meanwhile `acquired_via ENUM('grant','progression','prize','purchase','seed')`
already carries the "how did this driver come by it" meaning a player-visible provenance field would want.

Ruling deferred to the owner with the full explanation in the session record.

### A4 — evidence gathered; attribution is strong but not airtight. Recommendation: do not backfill.

Authoritative facts from production:

1. **Exactly one ownership transfer has ever occurred** — `primary_purchase`, the MaiMai, 2026-09-23 14:02:12.
   No grants, no trades, ever. No driver other than `baremetaleven` has ever owned an asset.
2. Driver **A**'s two results (2026-09-22) **predate all ownership** — definitively unattributable.
3. Of `baremetaleven`'s 27 results, **8 fall after the purchase, and all 8 were non-team entries.**
4. Entry requires owning an eligible machine (`competition.eligibility.check` → `no_eligible_car`), and L83
   forbids substitution.
5. **The MaiMai is the only asset in the world with any odometer distance at all** — 26,606 m — last checkpoint
   2026-09-24 00:53:46,about 3.5 minutes after the final race.

**The gap:** NCM never stored the eligible record on the entry, and **never verifies at the grid which vehicle the
driver is actually in.** A driver could be made eligible by an owned machine and physically drive a `/ncm car`
loaner. Nothing recorded would contradict that.

So attribution to asset `10000000-…-0001` for those 8 results is **strong inference, not record**. Under the
owner's own rule — *"do not manufacture certainty to eliminate NULLs"* — the recommendation is to **leave them
unknown**, and instead record *why* they are unknown. A middle path is offered (`IDEA-300`): an explicit
`attribution_basis` of `recorded` / `derived` / `unknown`, so a derived attribution could be stored while being
permanently legible as derived. That remains the owner's call.

### Also delivered for review

`25_MACHINE_ARCHITECTURE_PROFILE.md` (Q18/Q19 representation) and `26_DOCUMENT_AUTHORITY.md` (documentation
authority/lifecycle system plus a one-time classification pass). Both are PROPOSAL status; nothing moved,
nothing rewritten.

## L125 — LOCKED — documentation authority: preserve history, curate authority

Executed 2026-09-24 on the owner's direction, following `26_DOCUMENT_AUTHORITY.md`. **This was the whole of the
session's work; no foundation or gameplay code was touched.**

### What the scheme is

Every document under `docs/ncm-online/` carries one banner directly under its H1:

```
> **STATUS: CURRENT** - authority for: *topic* - affirmed <date> (<L-line>)
> Authority map: [INDEX.md](INDEX.md) - classified <date> (L125)
```

Six statuses, each distinguished by **what a coder should do about the document**: **CURRENT** (build from it) ·
**SPEC** (owner intent, do not implement, do not contradict) · **PROPOSAL** (a coder recommendation, no authority
until ruled) · **SUPERSEDED** (read for history only; the banner names the successor) · **HISTORICAL** (evidence
of a moment, never architecture) · **LEDGER** (living, append-only, current by construction).

`SPEC` and `PROPOSAL` are deliberately separate so owner-approved intent and coder recommendations never borrow
authority from one another.

**`INDEX.md` is the entry point**, and `AGENTS.md` now points there instead of at the orientation brief. Authority
is **per topic**, not per document. Conflicts are listed, not resolved.

### The principle that makes it survive

> **Headers carry authority. Build state lives in the ledgers.**

Almost every document already had a status line, and almost every one stated *build state* — "built locally, not
deployed", "migrations 001-007". Build state rots on every deploy; nobody goes back to edit prose. Authority
changes only when a decision changes, and that is already recorded here. `05_DATA_MODEL.md` sat in the corpus
claiming **migrations 001-007 while the schema was at 023** — that is the failure this inversion prevents.

### Owner rulings applied

- **Move and repair all links, including the four inside this ledger.** A path repair preserves an entry's
  meaning exactly; it is not a rewrite of substance. No entry's wording changed.
- **All 60 files**, not the top-level 33 — a half-classified corpus reintroduces the ambiguity being fixed.
- **Race Tags:** the repository is correct that it is not integrated or tested, **and it should be integrated
  eventually**. So `bricks/assignments/B-089-race-tags.v1.md` is **SPEC** (wanted, unbuilt) while the brick
  methodology itself is **HISTORICAL** (a closed experiment). Recorded as conflict C-4 in `INDEX.md`.

### What the verification found, before anything moved

- **The corpus is 60 markdown files, not 33.** `26` §11 counted only the top level and understated the work.
- **22 of the 60 had no status line at all**, including `MASTER_TEST.md` and every brick document.
- **Only 9 real markdown links pointed at archive candidates**; the other ~50 references were prose mentions,
  which do not break when a file moves. The archiving cost was far lower than the raw reference count suggested.
- **But `DECISION_RECORD.md` — append-only — held 4 of those 9.** That is the conflict that required the owner's
  ruling above, and it is exactly why §5 said to verify before moving.

### Result

27 documents moved to `docs/ncm-online/archive/` with `git mv`, history intact, **no stub files left behind** — a
stub would recreate the equal-discoverability problem it was meant to solve. 61 links rewritten. **Zero dangling
links inside `docs/ncm-online/`.** Full gate green, now including a new assertion.

### The assertion, because three manual lapses are enough

`tools/check-docs-authority.py`, wired into `tools/ncm-test.ps1`, asserts: exactly one banner per document
(ignoring fenced code blocks, since `26` legitimately shows example banners); a known status; a named successor
on every SUPERSEDED; presence in `INDEX.md`; no dangling relative link; and no two CURRENT documents claiming the
same topic. The `next free ID` line in `NOW.md` went stale three times and caused a duplicate-ID collision — the
lesson taken is that a manual step repeated by humans and agents needs a machine behind it, not more care.

### Three of my own errors, caught during the pass

1. The banner writer skipped an existing banner when a blank line preceded it, leaving one document with two.
2. The link repairer double-applied to banners already written for their future location, so every archived
   document pointed one directory too deep.
3. The link repairer **mangled verbatim captured evidence** — it rewrote an upstream absolute URL
   (`/docs/server-resources`) inside an OPEN//77 documentation capture into a relative path. Reverted. A link
   fixer must treat `/`-absolute targets as external and leave captured third-party material alone.

All three were found by the dangling-link check and a diff review, not by inspection of intent.

## L126 — LOCKED — team machines ARE assets. Recording a ruling the owner already gave.

The owner asked on 2026-09-24 whether "team cars name no machine" was a legacy assumption creeping in.
**It was, and the reason it survived is that I never recorded their own answer.**

### The ruling, from the Q1–Q70 pass (Q4)

> *"Yes, absolutely. They are persistent machine assets. They are owned by the **team**."*

Plus the future-facing half, which matters for L92/L93: NCX teams must themselves become player-owned and
managed while retaining league-level governance. Spunky Monkey, Rayfield and Herrera are not permanently
protected NPC institutions.

**L123 failed to capture this.** The only mention of team cars anywhere near it reads *"NCX team cars are not
assets at all (`IDEA-238`)"* — which describes the state of the data as a supporting fact, and reads exactly like
an open question. `IDEA-238`'s ledger row was left at `raw (owner decision)` for the same reason.

So a coder — including me, four days later — would have found a settled decision presented as undecided. That is
precisely the failure L125's authority pass exists to prevent, reappearing one level down: **not a stale
document, but a stale row and an unrecorded decision.**

### What is therefore true

- A team machine is an **ordinary machine asset** (L123: *"do not preserve exceptions created by obsolete
  prototypes as permanent ontology"*), drawing the same serial sequences (L124 A2).
- Its owner is an **organization principal** — which migration 025 made expressible three hours before this was
  written, and which `IDEA-168` specified long before that: *"assignment grants access, not title."*
- `team_car` and `issued_vehicle` are the **migration source**, not a permanent species. Converting them is M6
  in `24_FOUNDATION_RECONCILIATION.md` §9, still unbuilt.

### The latent bug this exposes

`NcmCompetition.enterMachine` resolves an entry's machine from `NcmOwnership.list(driverId)` — **what the driver
OWNS**. A team car will be owned by the organization, so a team driver will not find their seat machine in that
list, and will be refused an entry they are entitled to make.

**Owning and being-entitled-to-field are different questions**, and `IDEA-168` named the distinction before the
code existed. Filed as `IDEA-314`. It is latent today only because team cars are not yet assets; **M6 turns it
into a live defect the moment it lands**, which is the worst possible time to discover it.

### Corrected in code

`enforceEnteredMachine`'s comment said a team entry *"names no machine and is untouched"*, framing a temporary
gap as a permanent carve-out. Rewritten to say what is actually true: it names no machine **until M6**, and the
rule needs no change when it does.

## L127 — LOCKED — a machine is never classified by who uses it

Owner, 2026-09-24, catching me up after drift:

> *"Team cars are simply cars, owned by a team. Not a special category of car… a team car is simply a car
> serialized like any other from a manufacturer, even NCX cars or any CAR. The design is team and more
> competitive cars will be produced in external more exclusive markets, not base market. So people will have
> genuine connections to markets that newer players won't."*

### The rule

**One species.** A team car, an NCX car, a street car and a show car are the same kind of object. What differs
is **ownership, custody, configuration and history** — never the object's category. No schema, enum or
vocabulary may classify a machine by who uses it.

**Exclusivity lives in the channel, not the car.** Competitive machines are produced into external, restricted
markets rather than the Base Market, so **market access becomes real progression**: an established player knows
where to source what a newcomer cannot reach. That is *why* the serial space can stay uniform (L124 A2) — the
scarcity was never supposed to be in the object.

### What I broke, the day after L123 banned it

Q2 offered three answers and I recommended (b), a `machine_source` enum carrying `team_equipment`. **The owner
chose (c): "require every car to be an asset."** I then built (b) anyway, in migration 024 and in
`ncm/core/vocabulary/provenance.lua`.

So a superseded recommendation of mine became a schema column and a core enum, and the value it carried was
precisely the species distinction L123 had forbidden **one day earlier**. Prose in a decision record did not
prevent it.

Migration 027 drops the column; the vocabulary and both write sites are corrected. What remains says only true
things: **`asset_id` is WHICH machine, `attribution_basis` is HOW WELL WE KNOW IT, and there is no third fact.**
"This was a team car" is `asset_id` pointing at a machine whose owner principal is an organization — which
migration 025 already made expressible.

### The guard

`IDEA-315`: no enum under `ncm/core/vocabulary/` may contain a value naming a **use** rather than a **fact** —
`team_equipment`, `loaner`, `grid_car`, `league_car`. Mechanically checkable, and the third time this session
that a rule kept in prose failed where a gate assertion would have held (see also L125 §8, `IDEA-313`).

---

## L128 — LOCKED — a gate goes in front of the transaction only when the fact it reads cannot change

Built with `IDEA-251`, 2026-09-24.

### The rule

**Durable per-Driver facts are checked before the transaction. Contested world facts are checked inside it.**

`NcmMarket.purchase` settles stock, money, title and the transfer record in **one** MySQL transaction, and that
is not tidiness — it is what makes "visible, available, affordable" unraceable. Reading any of those out in
front, deciding on them, and then acting is a time-of-check/time-of-use race with real money and a unique
serialised machine on the other side of it.

Market **knowledge and access** are different in kind: they are durable per-Driver rows that no concurrent
buyer can move. So they are asked in front, where a clear refusal (`market_unknown`, `market_inaccessible`)
can be returned before anything is attempted.

### The consequence that must not be "tidied up" later

`economy.markets.purchaseDecision` validates six facts and has **never been called** since it was written. It
looks like an oversight and it is not. Wiring it would mean hoisting the balance and stock reads back out in
front of the transaction purely to populate its arguments — **reintroducing precisely the race the transaction
exists to remove**, in exchange for the appearance of using a helper.

The purchase gate therefore reuses `purchaseDecision`'s **refusal strings** and not its control flow. That is
recorded here, and in `IDEA-357`, so the next reader finds a decision rather than dead code.

### Related

Extends L127's lesson one step. L127 says a vocabulary value with no producer is a guess with a schema behind
it; this says a validator with no safe caller is a guess with a function behind it. In both cases the honest
move is to leave the seam visible and say why.

---

## L129 — PROVISIONAL — the companion hosts the page; NCM owns the data; the seam is a same-origin socket

Proven 2026-09-24 (`IDEA-387`, `IDEA-392`, MASTER_TEST §AJ). **PROVISIONAL**: the owner drove the
investigation and approved the probe, but has not ruled on the architecture that came out of it.

### The rule

**A bundled NCM WebUI page has no outbound network at all** — not a scheme policy, no network. Its origin is
a private scheme (`https://r-NN-g-1.cym-ui`), and `ws`, `wss`, `http` and `https` alike fail in ~0ms without
opening a socket.

**So the direction is inverted.** When NCM needs to reach a process on the player's machine, the *companion*
serves an HTML page and NCM creates a surface whose `entry` is that URL. The page's origin is then a real
`http://127.0.0.1:<port>`, a socket back to it is same-origin, and — the fact that makes it useful —
**`Open77.webui.create` still injects the Lua bridge into the configured top-level entry origin**, so client
Lua talks to it with the ordinary `page:send` / event bridge.

No TLS, no certificate, no trust-store change: loopback is a secure context over plain HTTP.

### The constraint that comes with it

**The race HUD stays bundled** (`IDEA-393`). Once remote entries work it is tempting to serve the HUD that way
and get hot reload for free. That would make core race presentation fail whenever an optional peripheral
process is closed, on a machine NCM does not control. Only the bridge surface is remote, and its failure mode
is that it does not appear.

And per `IDEA-388`, the bridge carries **the local player's own occupied vehicle and nothing else**, by
construction rather than by policy — otherwise it reopens the leak `IDEA-341` was filed to close.

### Why this is recorded as a decision rather than a note

Two sessions and an outside researcher each read the same documentation and each concluded the bundled page
should be able to dial out. It cannot. **The documentation is not wrong — the sentence about fetch and WS
applies to pages that have a network stack, and the bundled virtual origin does not.** That distinction is
invisible in the docs and cost three probe rounds to establish, so it belongs somewhere a reader will find it
before spending the same three rounds.

---

## L130 — LOCKED — Driver Card expression and Fingerprint authority stay separate

Owner ruling, 2026-09-24. This is new design authority following the historical recovery audit; it does not
rewrite that audit as though these details had been recovered.

### The compact in-world Driver Card

- A card displays the platform-verified current presentation name, one selected/default banner, **zero to
  three displayed badges**, and one fixed standardized high-contrast Fingerprint region.
- Earned badge collection, entitlement and displayed selection are separate facts. Selecting or hiding a
  badge changes no accomplishment. The first slice may bridge only the existing `first_finish`, `first_win`
  and `first_time_trial` accomplishments plus an explicitly Development-only preview fixture.
- The Fingerprint region is not player-curated. Banner artwork may style the card around it but may not
  camouflage, replace, distort or make it illegible.
- The first card says **Fingerprint unavailable / insufficient data**. Unknown is never six zeroes and no
  polygon is fabricated.
- The bucket-public player bag carries only the bounded public card projection. It is not a Driver Profile,
  global directory or permission to publish earned collections, history, telemetry, machines, Machine
  Knowledge, market or engineering knowledge, onboarding, biography, eligibility or other private state.

### Modern Fingerprint direction — not a calculation definition

The six current dimension names are **Competition, Street, Engineering, Commerce, Culture and Intensity**.
They describe what a Driver tends to do in that NCM world. They are behavioral/activity dimensions, not XP,
skill, competence, quality, morality, wealth, reputation, player-selected personality or an admin rating.

The intended future pipeline is authoritative activity evidence → independently defined dimension measure →
eligible world-population distribution → percentile → displayed vertex. A percentile is a derived,
versioned presentation and may move when the surrounding population moves; the authoritative evidence and
aggregates remain historical truth. Competition means sanctioned participation rather than success; Street
means open-world automotive participation; Engineering, Commerce and Culture mean legitimate participation
in their respective ecosystems; Intensity may combine legitimately measured dangerous, combative,
disruptive or incident-rich participation but never asserts fault, intent or “bad driving.”

**Fingerprint = tendency. Badges = accomplishments. Competency = capability. History/provenance = what
happened. Reputation = what other people think.** They must not be collapsed.

Fingerprint V1 remains separately gated. No values ship until evidence inputs, eligible population,
independent measures, minimum sample, window, cadence, anti-farming implications and definition version are
deliberately ruled. The public contract reserves the version and unavailable state now; it does not invent
formulas.
