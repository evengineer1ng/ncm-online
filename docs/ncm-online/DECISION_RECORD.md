# NCM Online — living decision record

> **STATUS: LEDGER** - living and append-only, current by construction. Covers: *every decision NCM has made (L-lines)* (L68)
> Authority map: [INDEX.md](INDEX.md) - classified 2026-09-24 (L125)

Maintained during the orientation/interview phase. Every entry cites its basis. Move items between sections only with the owner's answer or an experiment result. Companion: [00_ORIENTATION_BRIEF.md](archive/00_ORIENTATION_BRIEF.md).

Legend: **LOCKED** — owner-approved or forced by verified platform facts · **PROVISIONAL** — recommended, not yet approved · **OPEN** — needs the owner · **EXPERIMENT** — needs a measured result.

Last updated: 2026-09-27 - L166 rules that a ghost is a replay and never a competitor, and that ghost poses are their own versioned format. Previous entries remain authoritative.

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
| E26 | (owner, live, 2026-09-29) **Which way does `gripScale` move balance?** Owner on Online with `/ncm.setup tires 1.4` then `0.5` (tires family = grip x1.0, brake x0.45, drive x0.15 exponents): *"rear is significantly looser on 1.4, barely rotates at 0.5"*. **Above 1.0 is oversteer, below 1.0 is understeer.** The Carrier scales only the lateral force at the body, never the yaw moment, so the lever changes the car's BALANCE, not just its limit; a design that treats grip loss as "slippery" is wrong on this engine. Earlier the same night the agent had argued the opposite from the code; the owner's drive is the evidence. Governs weather/fuel/thermal mapping (`IDEA-715`-`IDEA-717`). | **ANSWERED** (feel, single driver; a yaw-rate trace would quantify it) |
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

## L131 — LOCKED — NCM owns the player-facing surface; the platform gamemode's sandbox is closed

Owner ruling, 2026-09-25: *"kill it with fire. /freeroam i mean. and of course its vehicles. in fact the /race
as well and /pvp. we can keep anim. we are handcrafting this all... we want our funnel to our experience."*

The ruling was prompted by evidence, not by preference. On 2026-09-25 at 03:22 a player took a rifle with 500
reserve rounds, a katana and an Archer Bandit out of the `freeroam` menu, five seconds before getting into the
car and crashing it — having opened NCM's Market four times, with 10,000 unspent eddies, and bought nothing.

### What is ruled

- **A player may not be given a vehicle.** This is **L102** restated against a resource rather than against a
  command: *"a player being able to spawn cars, even loaners, sinks economy."* It binds every resource loaded
  beside NCM, not only NCM's own code. Closing NCM's spawn path while a platform gamemode keeps its own open
  is not compliance with L102, it is the appearance of it.
- **`/race` and `/pvp` leave.** Not because they are bad, but because they answer the question NCM exists to
  answer, in a different voice, from a menu. Racing on this server is NCM's. PvP, when it happens, will be the
  emergent server-side system NCM already has the pieces for — not necessarily guns, and not decided yet.
- **`/anim` stays.** It is expression, it competes with nothing, and it is not freeroam's anyway:
  `open77_animations` registers the command and only the no-argument menu needs a gamemode to draw the page.
- **The persistent command-hint panel becomes NCM's** (`IDEA-417`). A standing list of what you can type is
  better than a help toast, and it should say NCM's vocabulary rather than a sandbox's.

### First-pass implementation scope — superseded by L132

The first implementation trimmed rather than evicted `freeroam`, because it owns the join spawn and the only
respawn-after-death path the server had. That was an implementation-risk judgment, not an owner ruling, and it
left `/freeroam` plus the forced join kill alive. L132 records the owner's correction and governs the current
load set.

### A standing consequence

The freeroam tree is vendor-owned, so an OPEN//77 upgrade restores everything this ruling removes. The
enforcement therefore lives in `tools/staging/close-freeroam-sandbox.py` and must be re-run after every
upgrade, beside `check-load-list.py`. A ruling kept only in prose has already failed four times in this
project (`IDEA-380`); this one is kept in a script that reports its own state.

## L132 — LOCKED — The platform freeroam resources are evicted now; missing lifecycle conveniences do not veto the boundary

Owner clarification, 2026-09-25: *"finish the job of killing the things with fire ... was the whole reason for
a reboot that got Kazami."* The intended result of L131 was removal, not merely disabling some subcommands.

- `freeroam` and `open77_freeroam` do not belong in `resources.load`, and the server is not advertised with a
  `freeroam` tag. Their vehicle/weapon menu, `/freeroam`, `/race`, `/footrace`, `/pvp`, `/dm`, join kill and
  separate persistence/wallet surface leave together.
- `open77_animations` remains loaded. The independent `/anim <profile>`, `list`, `info` and `stop` paths stay;
  the freeroam-owned no-argument picker is allowed to leave until NCM deliberately owns one.
- The known lack of an NCM respawn-after-death path is a real lifecycle gap, but it is not authority for an
  unrelated gamemode to remain loaded. Until repaired, reconnecting is the honest workaround.
- The removal remains a re-appliable vendor-tree operation and must be asserted after each OPEN//77 upgrade.
  The script keeps the earlier command/PvP edits as defence in depth against an accidental manual start, but
  absence from the load list is the authority boundary.

## L133 — LOCKED — the CEILING is the wrist protection; the rung is a unit, not a widget

Owner question, 2026-09-25: *"do you think force levels should be a slider like the rest? same min and max
but a slider?"* Yes, and the rule it replaces named the wrong thing.

`panel.html` carried this, in the stylesheet, as a standing prohibition:

> *The ladder is drawn as discrete rungs and NEVER as a slider. A continuous control would quietly undo the
> wrist protection at the last step — the rungs ARE the safety property (IDEA-395).*

**That is false, and it was false when written.** The protection is `CEILING` and the `clamp()` that enforces
it: a magnitude cannot leave the companion above its device class's cap, whatever control asked for it. A
slider bounded by the same maximum is exactly as safe as a row of buttons bounded by it. Discreteness was
never protecting anything — it protected against a danger that `clamp()` already made impossible.

What the ladder actually was is a **measuring instrument**. Walk it from the bottom and report the rung where
it becomes too strong. That is precisely how `IDEA-411` corrected four ceilings that had been reasoned about
at a desk and were all wrong, by ~60%. **The instrument did its job and the measurement is done.**

### What is ruled

- **STRENGTH is a slider whose step is one rung.** Same minimum, same maximum, same permitted values.
- **The rung survives as the shared unit**, displayed alongside the magnitude (`rung 4 / 10 (0.08)`). This is
  the part worth keeping: several testers on different hardware now compare notes — a T128, a G29, a G923 —
  and *"rung 4 was right"* travels between them in a way *"about 60%"* does not. A unit that survives being
  quoted in somebody else's message is worth more than a widget.
- **A safety claim in a comment is not a safety mechanism.** This rule sat unchallenged because it was
  written in the imperative and sounded careful. The test for whether something protects a wrist is whether
  removing it lets a larger number reach the device — and removing this one does not. Asserted now:
  `panel-render-check.js` fails if the STRENGTH control's maximum is not the ceiling rung.

### Related, from the same session

The panel render gate had 96 assertions and **drew the WHEEL/PEDALS panel with no payload at all**, which is
how a genuine ReferenceError in its not-connected branch passed review and the gate on 2026-09-25. Coverage
added; it now fails 13 assertions against that defect. A gate that does not exercise a surface is not
evidence about that surface, and the count of assertions says nothing about which surfaces they touch.

## L134 — LOCKED — Parts / Engineering knowledge, fabrication and design-promotion rulings

Owner rulings, 2026-09-25, following review of `32_PARTS_ENGINEERING_REENTRY_AUDIT.md`. **These are design
authority. Nothing in this ruling implements Parts/Engineering, changes schema/data, or proves a physical
vehicle effect.** The reconciliation and two remaining technical gates are in
`33_PARTS_ENGINEERING_FINAL_RECONCILIATION.md`.

### Knowledge and execution

- Complete process knowledge may be represented by an opaque, high-entropy, human-shareable reference. Public
  Discord/wiki cataloguing is legitimate technological diffusion, not an exploit.
- Long-term progression must not depend on permanent secrecy. **Knowing how is not being capable of doing.**
  Competency, family specialisation, Diagnostics, facilities, capacity, money, time, access, specimens,
  installation and manufacturing repeatability remain separate requirements.
- First implementation shares **complete facts only**. Partial understanding remains accumulated evidence /
  design-specific knowledge state, not token substrings and not independently tradeable fragments.
- A knowledge reference is never a PRNG seed, predictable-stat hash, exposed generator input, proximity code,
  partial hexadecimal puzzle or correctness oracle. The server-private resolver owns truth and historical
  resolved outcomes remain stored across resolver versions.
- Effect-labelled information may be shown only when Diagnostics/evidence epistemically justify it. Mystery is
  uncertainty about truth, not permanent cosmetic obscurity.

### Fabrication, costs and physical failure

- First fabrication economics are **money + elapsed time + bounded capacity**, plus legitimate source hardware,
  destructive-analysis specimens, knowledge/capability requirements and access. Costs commit before outcome;
  cancellation is not a free reroll. No general material inventory or arbitrary daily attempt cap.
- Fabrication distinguishes **functional poor/detrimental**, **functional neutral/unremarkable**, and
  **nonfunctional/junk** output. Nonfunctional means it cannot perform the intended component role; it is not a
  merely weak installable part.
- A failed project normally leaves a persistent physical asset with identity, source design, fabrication
  operation, maker, cost/time and diagnostic/provenance value. It is not installable solely because it has an
  asset row and it does not disappear behind `CRAFT FAILED`.
- Failure is governed by competency/capability, not added as punishment for copied knowledge. Mastery of a
  fully known mature process should approach reliable repeatability, without an arbitrary permanent casino tax.
- No scrap/material economy is implied. Storage, honest transfer, inspection, destructive analysis and a
  provenance-preserving terminal disposal are sufficient first lifecycle options.

### Prototype and design identity

- A one-off experimental result remains a physical asset/prototype, however extraordinary. It does not
  automatically become a component design.
- **Discovery is not understanding. Understanding is not automatically repeatable manufacturing.** A new
  immutable design is born only through an explicit Design/Manufacturing promotion operation after sufficient
  knowledge, competency, tooling/capability and evidence.
- Promotion creates design identity and ancestry; it never rewrites the prototype's realised outcome, maker,
  serial or operation. Functional reproduction never grants the historical source manufacturer's provenance.
- First implementation uses the explicit lineage -> immutable design revision -> run/project -> physical asset
  distinction, with revision labels remaining presentation rather than power.

### Costs, migration and unresolved gates

- Existing machines eventually receive canonical factory components without changing machine identity,
  ownership, paint, ordinals, odometer, result/transfer history or known provenance. Original-component exposure
  derives from existing odometer where appropriate; unknown installers/batches/timestamps remain unknown.
  Development and Online remain separate data universes. No migration is authorised yet.
- **Gate 5 remains open:** `25_MACHINE_ARCHITECTURE_PROFILE.md` is not accepted by this ruling. Report 33
  recommends accepting it with amendments.
- **Gate 6 remains an experiment:** a sole NCM performance composer is desired and high-confidence, but neither
  physical effect nor composition has a live PASS. Parts may not depend on it until the two Development proofs
  in Report 33 pass. The known carrier remains limited to top-speed ceiling, acceleration reduction and taper;
  no grip/brake/suspension/steering authority is implied.

## L135 - LOCKED INVARIANT / EXPERIMENTAL CARRIERS - mechanical truth is not today's host expression

Owner Gate 6 input-authority and required-world-mod addenda, 2026-09-25; capability result in
`34_GATE6_INPUT_AUTHORITY_REQUIRED_MOD_AUDIT.md`.

**Locked invariant:** NCM machine/component/condition truth must not be defined by today's writable host fields.
One versioned calculation may eventually project that truth through several separately proven carriers:
performance, input authority, a deeper client vehicle extension, or NCM simulation only. Each carrier has one
owner and explicit composition/removal semantics. The same mechanical fact may not be silently expressed twice.
Changing from a crude projection to a future better native carrier changes the projection adapter/version, not
component identity, realised characteristics, wear, history or provenance.

**Still experiments, not accepted Parts design:**

- the current `setPerformance` carrier and composition proofs remain owed in MASTER_TEST section AN;
- a companion-side brake/steering/throttle transform is Development-only until measured, device-independent and
  enforceable; section AO records the first brake proof;
- a common game-side final-command extension is plausible, but no exact hook/bridge/technology is selected;
- automatic world-mod delivery and runtime readiness must pass section AP before NCM depends on it; L136/KB-112
  supersede the old KB-8 causal diagnosis, while R5/§AP and L76 remain active;
- a launcher digest or client handshake is compatibility evidence, not anti-cheat, without platform-owned
  runtime attestation.

Current official documentation now explicitly permits exact-hash verified executable world packages (`.reds`,
CET Lua and native/RED4ext content) on a secured server, and unreviewed executable packages with conspicuous
consent on an unsecured server. This **qualifies the platform rationale** in L50/L71 that executable content
cannot be a world requirement. It does not silently reverse the owner's curated-fleet or no-third-party-
dependency choices, and it does not prove NCM's currently parked path works. L76 remains the operational gate.

## L136 - PROVISIONAL EVIDENCE GATE - public hosted RequiredMods need HTTPS and the real packages must pass first

Owner RequiredMods forensic-audit instruction, 2026-09-25; evidence and exact acceptance contract in
`35_REQUIREDMODS_FORENSIC_AUDIT.md`.

The historic `Unverifiable` result is no longer treated as a review/attestation verdict or a general platform
wall. Launcher `.89` and current `.100` both discard every non-loopback HTTP hosted-mod URL before resolution;
NCM advertised public HTTP, so the resolver received no URL and returned `Unverifiable` after consent but before
download. The two real NCM packages themselves pass declaration, exact-byte, archive-root and content-class
audit. Existing manual files could not cause that pre-download refusal.

Operational gate: keep Online RequiredMods parked. The first same-PC Development recovery may use
`http://127.0.0.1:11779/`, which the launcher explicitly accepts; every remote/public client path requires a valid
HTTPS resource origin. Use aligned supported builds, the existing RB15 and NCM livery hashes, and actual
ArchiveXL/TweakXL dependencies. MASTER_TEST §AP must prove both the current manual-installed client and a safely
isolated relevant-mod client, including in-game content and exact Solo/removal restoration. No dummy package
substitutes for this proof.

Until §AP passes, RequiredMods remains **unknown with an exact remaining question**, not an accepted dependency
for the proposed input/control layer. After a pass it may be accepted as an unsecured Development delivery path
only for the roots/classes exercised. Secured executable delivery and runtime readiness remain separate review
and handshake questions. This provisional gate authorises no Production endpoint, deployment or restart.

## L137 - PROVISIONAL OPERATIONAL DECISION - prove RequiredMods through the whitelisted Online world over HTTPS

Owner instruction, 2026-09-25, superseding only L136's Development-first and no-Production operational limits.
The owner explicitly selected the currently whitelisted production world for the real-package proof because
loopback HTTP would conceal the transport defect being tested, authorised the endpoint/configuration change and
restart, and retained the launcher/game checks personally.

NCM Online now terminates public TLS with Caddy on
`https://52-60-225-137.sslip.io:11779/`; OPEN//77's resource origin is loopback-only on
`http://127.0.0.1:11782`, and Warden remains loopback-only on `127.0.0.1:11780`. RequiredMods is enabled and
unsecured with the exact retained ArchiveXL 1.27.1, TweakXL 1.11.4, RB15 10.0.0 and NCM liveries 1.0.0 blobs.
The public master row, trusted certificate, external full-byte hashes, ETags and Range response passed as
MASTER_TEST §AP1. This is an interim proof origin: replace the `sslip.io` name with owner-controlled DNS before
treating it as permanent production infrastructure.

This decision proves transport/configuration only. It does not turn §AP2-§AP7 green: launcher consent,
projection, loader boot, the real in-game vehicle/liveries, reconnect, Solo isolation and byte-exact restoration
still require the owner's live checks. It does not accept RequiredMods as a future NCM control-extension path,
approve Parts/Engineering, or change Gate 6 AN/AO.

## L138 - OPEN - three owner decisions the driveability-mod avenue needs

Assessment in `36_DRIVEABILITY_MOD_CARRIER_ASSESSMENT.md`, 2026-09-25, answering the owner's question of
whether a hosted mod can give finer control over driveability than the three exposed fields and carry FFB
natively. **The assessment authorises nothing.** It found that the answer is yes to both and larger than
expected — and that every capability behind that yes is demonstrated in single-player Cyberpunk 2.31 by a
third party (`natpoh/cp2077-wheel-mod-moza`, MIT) and has never run under OPEN//77.

Three decisions are genuinely the owner's, and the first gates the other two:

1. **Does NCM become a mod-required world?** Not whether it can — it can. Whether the red `UNSECURED` badge in
   the server browser, the unsecured warning, a named-package consent gate that *"a double-click cannot skip"*
   and a 48.4 MB first download are a price worth paying for a funnel that already loses people at the connect
   wall. `KB-60` is what that wall costs today.
2. **Does NCM take ownership of native code?** A RED4ext plugin reaches the final vehicle command point, which
   would make the companion's virtual-pad layer redundant and dissolve `KB-110`, `KB-111` and Report 34 §7's
   whole bypass table. It also means **the world cannot be entered at all** when the RED4ext address database
   lags a CDPR patch, plus ABI, crash and review cost. A CET/REDscript layer is lighter and reaches the
   handling flats, but has not been shown to reach the command point.
3. **Does the companion remain the FFB device layer?** The answer decides whether the canonical `ncm-wheel`
   repository is a long-lived product or a bridge.

**Not a decision, but a scheduling fact:** all three are worth less until the spawn-cached-versus-live question
is answered, and that costs one offline single-player drive (`IDEA-455`, MASTER_TEST §AR).

## L139 - PROVISIONAL - no handling carrier is designed or built before §AR and §AP Case A

Consequence of L138 and of the L135 invariant, which already separates mechanical truth from host expression
and therefore needs no amendment.

- **No carrier beyond `{topSpeedKph, accelerationScale, taperKph}` may be designed, prototyped or implemented**
  until MASTER_TEST **§AR** says whether drive-model handling values are live, spawn-cached or restart-bound,
  and until **§AP2-§AP7** proves NCM can deliver a package at all. Either answer changes the design; guessing
  produces work that is thrown away.
- **Naming discipline is unchanged and unconditional.** Report 34 §8 governs: input mediation is
  `brake_command_authority`, never `native_brake_force`, and presenting throttle withdrawal as grip remains
  semantically dishonest whatever carrier arrives later.
- **The parts economy's integrity does not depend on any of this.** Existence, provenance, ownership,
  transfer, wear and failure are server-authoritative today and stay that way. Only *feel* is client-applied,
  and the server has no read-back for it and can construct none (`IDEA-458`).
- **One thing may proceed now:** the §AR probe itself, offline, single-player, no server, no OPEN//77, no NCM
  code, saves backed up. AGENTS.md's isolated-prototype allowance covers exactly this.
- **One thing must not be deferred behind it:** `KB-106`'s `ROAD_SCALE` measurement. A native source would make
  the units knowable, but that is a project and the measurement is one drive with instrumentation that already
  ships. A better desk is still a desk (`IDEA-411`).

## L140 - PROVISIONAL OPERATIONAL DECISION - commit before deploying; the spawn fix is committed first and alone

Schedule in `37_REPOSITORY_RECONCILIATION_SCHEDULE.md`, 2026-09-25. **Written, not executed.** No commit,
push, deploy, restart or configuration change has been made.

A read-only hash comparison found that **NCM Online is byte-identical to the uncommitted working tree and
differs from every commit**: `panel.html` `36ddb90f…`, `location.lua` `299c868b…`, `ncm_world/server/main.lua`
`b95e45fd…` all match Online and none match `HEAD`. Three facts follow, recorded as `KB-115`, `KB-116` and
`KB-117`, and they set the order:

- The exact bytes running in production exist **on one disk, in no commit, unpushed**.
- The untested FFB panel work is **already on Online**, not merely on Development, because
  `deploy-staging.ps1` does a whole-tree `rm -rf` / `mv` replace and the 15:36 UTC spawn-fix deploy carried it.
- `HEAD`'s `location.lua` is the `KB-113`-broken version, so an ordinary `git checkout --`, `stash`, `reset` or
  fresh clone would change **NCM Development instantly and live** — the resources junction has no copy step —
  and stage a silent production regression for the next deploy.

**Ruled provisionally, pending the owner's approval to execute:**

- **Commit the location/spawn fix first, alone, and push it.** After that commit exists, no ordinary git
  operation can reintroduce the regression. That is the entire mitigation and it costs one commit.
- **Commit before deploying, always.** Promotion moves a known revision (16_ENVIRONMENTS); today it would move
  a state that exists nowhere else.
- **No Online deploy, restart or configuration change until the owner's §AP2-§AP4 Case A is finished**, pass or
  fail. `KB-102` measured a 90-second window in which a stopping server still admits players.
- **§AQ is captured on the same Connect as §AP2.** The launcher proof and the `KB-113` live join observation
  need the same single join.
- **Windows dev is instrumented before any Lightsail change**, and the Development correction needs its package
  set decided as well as its URL (`IDEA-460`).
- **The two companions are not synced.** `ncm-wheel` is canonical and drives hardware; `tools/ncm-wheel.py`
  says of itself *"This drives no hardware."* Their shared contract is `ncm/core/driver/feedback.lua`, and the
  Lua is authoritative.

## L141 - LOCKED EVIDENCE - RequiredMods delivery works; the "mods cannot be installed" narrative is closed

Owner-run live Online sequence, 2026-09-25. The owner connected to NCM Online, received the OPEN//77
unsecured-world warning, received the RequiredMods review/consent UI naming all four declared packages -
TweakXL, ArchiveXL, NCM RB15 Team Liveries and RB15 F1 car only/no ERS, **each presented as "Not reviewed"** -
chose **Download and Join**, watched the launcher progress through *Preparing server mods* and *Preparing your
session*, and **entered NCM Online**. The server log corroborates: `connected: player=1 name=easporks` at
15:38:26 UTC, `ready:` at 15:38:43.

**What this proves, exactly:**

> public HTTPS -> unsecured warning -> named-package consent -> Download and Join -> preparation ->
> successful NCM session entry.

**No `Unverifiable` appeared.** `KB-112` is closed as a delivery blocker: the launcher's non-loopback HTTP URL
sanitation was the whole of the old wall, and HTTPS clears it. The four `Not reviewed` verdicts match Report
35's `safety=unknown` attestation finding exactly, so unverified inert and unverified executable packages are
both accepted after consent on an unsecured world, as documented.

**What this does NOT prove, and must not be inflated into:**

- that ArchiveXL or TweakXL initialised - no loader log was captured;
- that the RB15 record exists in game or drives;
- that any NCM livery is available;
- that projected files coexisted correctly with the pre-existing manual installation;
- that reconnect reuses cache, or that switching to Solo restores every manual byte exactly.

§AP2 is a PASS on its consent half with the collision/journal half unevidenced; §AP3 is **PARTIAL**; §AP4 and
Case B (§AP5-§AP7) remain owed. **A session-entry PASS is not an in-game content PASS.**

**Standing instruction to future sessions:** do not resurrect the "RequiredMods doesn't work" narrative. It was
false, its cause was found (Report 35), the correction was deployed, and a human has now walked the whole
funnel. Equally, do not cite this decision as proof that NCM's mod content loads.

## L142 - LOCKED OWNER RULING - NCM ceases public redistribution of RB15

Owner ruling, 2026-09-25, after revisiting the permissions.

> **NCM has not established sufficient redistribution permission for the exact RB15 package it was hosting,
> and will not continue publicly rehosting it unless and until that package is established as redistributable
> or the author grants permission.**

Earlier licensing research found the provenance is mixed: the underlying model and model-derived portions
appear to carry **CC BY 4.0** provenance, while the Cyberpunk mod author's own implementation, configuration
and the complete or modified package carry **separate redistribution restrictions requiring permission**. A
package can be partly permissively licensed and still not be NCM's to serve. Permission will be sought and the
question revisited. The earlier framing "terms not established" is superseded - the operative state is a
decision, not an open question.

**RB15 is currently NCM's only open-wheel vehicle candidate. That does not override the permissions issue, and
no substitute open-wheel mod is to be adopted now.**

Consequences:

- **The NCM liveries park with it.** NCM owns those bytes outright, but they are ArchiveXL/TweakXL content
  extending the RB15 vehicle record; projected without it they extend nothing, and they would cost every joiner
  7.8 MB for no effect.
- **Preserve, do not delete.** Blobs, declarations, hashes, the provenance manifest and all local authoring
  sources stay. This withdraws a public offer; it does not discard NCM's work.
- **It does not execute now.** Removal is a Production `server.jsonc` write, a restart, a digest mutation and a
  serving change - every one of them gated by Report 37 §6, because §AP4 and Case B evidence only exists while
  the current packages and projection are in place. Report 37 §6.2 names the exact operation the owner must
  authorise; MASTER_TEST **§AS** holds the proof rows. **The ruling is recorded and parked, not disobeyed.**
- **Two facts for the owner's decision:** RB15 is 38.5 MB of the 48.4 MB first-join download, so withdrawal
  improves the funnel by roughly 80%; and with it and the liveries gone, ArchiveXL and TweakXL have no NCM
  content left to load, so parking `requiredMods` entirely may be the honest end state (§AS4).

## L143 - LOCKED OWNER RULING - research before experiment; the single-player probe is deferred

Owner ruling, 2026-09-25, on Report 36's proposed §AR offline single-player CET probe.

> *"I have not returned to single-player. I am committed to NCM Online right now, and I do not want to flip my
> mod environment around, change installations/profiles, or create another local configuration merely to answer
> something that may already have been answered by existing Cyberpunk mods."*

**This is a workflow constraint, not a technical objection to experimentation.** The standing order it sets:

> **existing implementation research -> forensic source/repository inspection -> identify the remaining
> unknown -> only then propose an isolated experiment, and only if the unknown genuinely cannot be answered
> otherwise.**

Report 37's revision-1 note that §AR *"can happen at any point"* described a dependency, not a permission, and
has been corrected. **§AR is not scheduled. Do not ask the owner to run it.**

**Applying the order answered the question the same day, without an owner session.** Report 36 §4 now
classifies the drive model as **SPAWN-CACHED**, on three independent lines of evidence: Vehicle Physics Config
states it as an engine limitation and builds its whole resummon-based UX around it; Direct Wheel's apparently
contradicting CET module turns out to be **absent from its own `deploy.ps1` and FOMOD installer**, an unshipped
experiment; and the live `WheeledPhysics` instance is a named per-instance copy of the drive-model record.

**Where any future experiment proposal must now start.** Report 36 §11 records the single residual unknown -
whether the live `WheeledPhysics` handling fields can be *written* per-instance and have the write hold - and
states why no existing implementation answers it: nothing writes them, and the one open-source wheel-reinit
attempt is commented out in its own source. That is a code-reading and eventually an isolated native-prototype
question. **It is not an owner single-player session, and it must not be re-proposed as one.**

## L144 - LOCKED OWNER RULING - the owner does not leave NCM Online; no test may require Solo

Owner correction, 2026-09-25: *"i told you im not going to solo."*

**The correction was warranted.** L143 recorded that the owner is committed to NCM Online and will not flip mod
environments or profiles, and two messages later the next-action list still opened with *"reconnect, switch to
Solo"*. L143 was written as if it were about one experiment. It is not. It is a standing constraint on
**every** test design, and §AP4/§AP6 were drafted before it existed.

**Ruled:**

- **No MASTER_TEST row may require the owner to enter Solo, single-player, another profile, or another mod
  configuration.** A row that needs it is not "owed" - it is **unrunnable as written** and must be re-scoped or
  marked blocked by owner choice, like §AR.
- **Re-scope before asking.** The great majority of what §AP wanted was already sitting in launcher, RED4ext
  and ArchiveXL logs and in the game directory's own file metadata. That was true the whole time and nobody
  looked (`KB-121`). The standing order from L143 - research before asking - applies to **the owner's own
  machine** as much as to third-party mods.
- **What genuinely needs a human is now small and is all inside Online:** does the RB15 exist and drive, and
  are the NCM liveries visibly right. Both are in-world observations on the world the owner is already in.

**What is left of Solo.** Only one honest question needs it: *does a world-mod file leak into the Solo
profile?* That is an OPEN//77 correctness question, not an NCM one. It is recorded, unrun, and **not to be
scheduled** - the same disposition as §AR. If it ever matters, it matters to the platform.

**This does not weaken the evidence bar.** Case A still cannot prove the hosted packages supplied the content,
because the launcher explicitly kept the manual copies that were already on disk. That limitation is now
documented from the launcher's own words rather than assumed, and Case B remains the only thing that settles
it - by isolating files, which is a filesystem operation and needs no profile change.

## L145 - EXECUTED - RB15 and the liveries are gone from Production; Case B is closed as moot

Owner, 2026-09-25: *"we are removing it end of discussion. in fact, i just deleted them in warden on
production. poof. both rb15 and liveries."*

**Verified live, read-only.** The public manifest at `https://52-60-225-137.sslip.io:11779/mods/v1/manifest`
now declares **two** packages - ArchiveXL 1.27.1 and TweakXL 1.11.4 - with digest
`67ad384b2d8bcc70c2eeedd113e2abc654ce04d23b3fb8098ae81ae2937d499d`, replacing `06ab5485…`. No RB15, no
liveries. Development was parked the same day (`enabled=false`, empty-set digest) and restarted.

`L142` is therefore **executed**, not pending. MASTER_TEST §AS is satisfied by the owner's own Warden action.

### Case B is closed as moot, and the framing that kept it open was wrong

Owner: *"hosted delivery of ncms content is not unproven. we proved we can host. we didnt write the packages
we want to host yet. thats not the same thing."*

**Correct, and the earlier wording confused two different things.** What `L141` and the client-log evidence
prove is the **pipeline**: HTTPS transport, consent, executable-root acceptance, projection, loader
initialisation and archive loading all work, end to end, for real packages. Case B would only have shown
whether one specific file that already existed locally came from the host rather than from disk. That is a
custody detail about a package NCM is deleting - not a capability gap.

**NCM has no unproven delivery capability. NCM has unwritten packages.** Those are a build task, and the
pipeline is warm and waiting for the first one.

Consequences, so nobody re-opens this:

- **§AP is complete for its purpose.** §AP5/§AP6 are retired as moot; §AP3's two remaining in-world looks -
  does the RB15 drive, do the liveries render - are retired with their subject. **Do not ask anyone to drive
  an RB15.**
- **The two loaders stay staged deliberately.** They currently deliver no NCM content, which is the
  `§AS4`/`IDEA-461` cost - an unsecured badge and a consent gate for two DLLs that load nothing. Keeping them
  means the pipeline is already correct the day NCM's first real package exists. Revisit only if the join
  funnel is being measured. The `requiredMods.note` still reads *"NCM RB15, liveries, and exact hosted loader
  dependencies"* and is now stale; correct it on the next config touch, not with a restart of its own.
- **The next package proves itself.** Whatever NCM ships first carries its own §AP-style receipt, and by then
  the whole pipeline is a known quantity rather than a question.

## L146 - LOCKED OWNER RULING - NCM owns native code; the carrier is one mod and the companion retires

Owner, 2026-09-25: *"plan the wheel package, but more than a wheel package, make it be the ncm mod which
carries the ability for us to have part effects, chrome effects, weather driving effects like rain, whatever
else we have planned in that vein. they all touch a similar cord. then lets actually build it and we will
debug the issues of the final product, not every step along the way."*

Asked directly, the owner chose the **full native plugin** and chose to **move force feedback into it now**.

**This answers `L138`, open since Report 36.** (1) NCM becomes a mod-required world - it already is one, for
two third-party loaders; now it requires one of NCM's own. (2) **NCM takes ownership of native code.**
(3) The companion does **not** remain the FFB device layer; it is superseded by the carrier.

### Why native, and why this is not merely the strongest option taken by default

`IDEA-443` warns against choosing the most powerful layer by reflex, so the reasoning is recorded rather
than assumed. There is a real gap and only one thing crosses it: **OPEN//77 resources have no TweakDB and no
engine RTTI, and CET mods are not network-aware** (`L1`). Neither side can reach the other. A CET carrier
would need the companion to relay for it, which means every NCM player - wheel or not - runs an executable
the delivery pipeline can neither install nor start. A RED4ext plugin is the only component that is both
network-capable and started automatically by the loader chain NCM already requires.

It also satisfies Report 36 section 6.7's threshold rather than dodging it: the end state has **no separate
GitHub download at all**, which is the condition the owner set for the migration being worth doing.

### What is amended

- **`L50` and `L1` described a SECURED server.** NCM runs unsecured with consented executable loaders and
  has since section AP. The inert-only rule stands for *content*; it never governed NCM's own runtime.
  Stated here so the contradiction is recorded rather than discovered later.
- **`L139` is DISCHARGED, not ignored.** Its two conditions are met: section AR was answered by research
  (`L143`, spawn-cached) and AP1-AP4 passed. Its naming discipline is **not** discharged and is carried into
  the code: the command surface is `brake_command_authority`, never `native_brake_force`.
- **Report 36 remains a capability assessment and its findings stand.** What changes is that the three
  decisions it raised are now made. It is not promoted to a design document; this entry is the decision.
- **`KB-117` closes by retirement.** Two divergent companions stop being a problem when neither is required.
  Both stay on disk as the reference the port was made from - do not delete our work.

### What is NOT decided here

Production. The carrier is a Development artifact until it has launched the game on the owner's own machine
and passed section AT. **A plugin that fails to load stops Cyberpunk launching entirely** - the one failure
mode that reaches every player simultaneously - so it is found by us, once, by hand (`IDEA-478`).

## L147 - EXECUTED OWNER RULING - use whitelisted Production for the carrier proof; protect world data, accept code divergence

Owner, 2026-09-25: the morning's two-server reconciliation was turbulent; code loss or temporary divergence is
acceptable at this stage, but **the database rows representing the actual world and game state are not**. The
immediate priority is getting the exact `dist/ncm-carrier-0.1.0.zip` into the whitelisted, unlisted NCM Online
world so its real launcher delivery path can be tested. The owner will perform the final launcher/game checks.

**Executed with the database as a hard boundary.** Before any Production mutation, a verified logical database
dump and operator-state archive were created at
`/opt/ncm/backups/pre-carrier-prod-20260925T195327Z`. The dump is gzip-valid, contains 63 tables, and has SHA-256
`af60470a4958775cf13f21003cdf64e68c70d710125cf865eb370ceb02f7353e`; the operator archive lists cleanly and
has SHA-256 `eccaff6a40cde90fa6cc40b9e5ab01a5029b90e342d1e4d8250b445a42fd4536`. No database migration was added or
applied: Production booted with schema 001-030 and `0 applied; pending=[]`.

**The environment choice is evidence-driven, not ceremonial.** Loopback HTTP is valid transport, but a raw-address
join carries no master catalogue row and therefore no required-mod digest (`KB-126`). Production already has the
routable master identity and trusted HTTPS path that section AP proved. The current resource tree was staged to
Production, the carrier became its sole required package, and one controlled restart activated it. The public
manifest and the master now agree on digest `78c37893896a5e93691019fd47ed051653bda256d53d8d59c0ba1a90da683583`,
package `ncm-carrier` 0.1.0, executable classification, 868,069 bytes, and SHA-256
`7febfa6e794ca0748d6f03c325de8053d20beba403840e0883aa97fdea619286`. NCM started without boot errors and
published 11 machine projection records.

The owner's first join receipt then exposed an independent platform-version gate: client protocol 1.40 versus
Production `.87` protocol 1.35 (`invalid_server_packet:unsupported_version`). Production was upgraded to the
same `2.31.13+op77.102` already exercised on Development. The 711-file Linux package verified before swap; the
freeroam boundary and 41-resource load graph passed against the candidate before shutdown; the old platform tree
is retained at `/opt/ncm/backups/server-20260925T200746Z`. Post-upgrade the master advertises protocol 1.40,
the carrier declaration is unchanged, migrations remain `0 applied; pending=[]`, and NCM again publishes 11
machine records.

The first true cold launch then separated delivery from runtime. The launcher accepted the unsecured package,
projected exactly its three files and started Cyberpunk with the declared digest; RED4ext explicitly loaded
`NCM Carrier 0.1.0`. It then terminated during native script validation (`KB-132`). This is not evidence that
`.102` alone rejects the game: the same `.102` client validated the same 1,288-reference script set with Open77
alone earlier that afternoon. Carrier 0.1.0 did, however, violate RED4ext's documented lifecycle by touching SDL,
threads, TweakDB and RTTI from `Main(Load)`, before game memory is ready. The smallest correction is Carrier 0.1.1:
`Main(Load)` is registration-only; startup/teardown move to Running `OnEnter`/`OnExit`; and the malformed logger
path is fixed (`KB-133`). This is a supported-boundary correction, not a declaration that causality is proven.

Production now serves 0.1.1 as its sole package: 868,295 bytes, SHA-256
`6966a75d228cb70105f6201aaff4a2ab60ca6681ba78d65ad40acad4d2306301`, manifest digest
`e0ad7ec9091c2b23f69067addb318c3d9fe319fc5111eb0ff76c47949b1bbde2`. The public full download and Range
response passed, the 41-resource dependency guard passed before restart, and the post-restart world again has
`0 applied; pending=[]`, five series, race control and 11 machine projections. The next evidence is one owner cold
launch; it either closes the lifecycle diagnosis or falsifies it without risking database state.

The owner cold-launched at 20:25 UTC and **the lifecycle correction passed**. Launcher digest
`e0ad7ec9...bbde2` was present, RED4ext loaded NCM Carrier 0.1.1, the game survived validation, Open77 reached
active, Production recorded connected then ready, and the carrier's corrected local log recorded bridge startup
and NCM connection. This closes the native delivery/startup question, not the feature question. Source/live
reconciliation immediately found three honest next gaps: no device/health reply (`KB-134`), no actual input
detour behind the “installed” log (`KB-135`), and no receipt for the 11 published record projections (`KB-136`).
No performance or input effect is claimed until those channels produce their own receipts.

**Reconciliation rule:** Production and Development code may diverge during this urgent proof and may later be
made identical by replacing Development's code/resources with the chosen Production revision. That authority does
not include copying, replacing, resetting, or otherwise reconciling either database. World rows remain canonical
to their own environment. A later cleanup must choose and name a code revision; it may not treat a filesystem
overwrite as permission to move game-state data.

## L148 - EXECUTED - the carrier may write live vehicle physics, under five properties that make it safe

**Decided 2026-09-26, owner approval given explicitly before the first write shipped.**

Until 0.1.9 the carrier was read-only by policy. It now writes one thing: the component of a horizontal
force entry perpendicular to the direction of travel, multiplied by `gripScale`. The along-travel component
is passed through untouched, so a value below 1.0 is a wet road and not a slow car.

The approval is not for "the carrier may write physics" in general. It is for writes that hold **all five**
of these, each a property of the design rather than a promise:

1. **Stateless.** Recomputed from the game's own value on every call. Nothing accumulates, so a missed call
   or an unseen thread costs nothing. This is what makes it safe across the twelve threads that were found
   to drive one body's physics.
2. **Exactly reversible.** At 1.0 the reconstruction is the original vector identically, because there is no
   stored original to drift from: `long*dir + lat*perp` **is** the decomposition of what was already there.
   Confirmed live -- `gripScale 0.30 -> 1.00 (inert, no writes)`, and the owner felt default physics return.
3. **Inert by default,** and the default is what ships.
4. **Bounded.** Clamped to [0.3, 1.5]. A typo cannot put a car on ice at 200 km/h, and the clamp is logged.
5. **Scoped and guarded.** The latched player vehicle only -- never traffic, never another player's car --
   and every memory access runs under SEH, with one fault disabling writes for the session and saying so.

**What this does not authorise.** Input-command authority remains refused (`KB-135`): writing a vehicle's
throttle, brake or steer is a different surface with different failure modes and is not covered here.
Neither is writing the per-wheel normal loads, which hold the car up -- scaling those makes a car sag into
its suspension rather than slide, and that mistake was caught by measurement rather than by review
(`IDEA-499`).

**Basis.** Live-proven on Production across Carrier 0.1.2-0.1.9: the interception point verified against the
build's own address table, the force field decoded and its units established, the four corners identified by
three independent manoeuvres, and the classifier validated by arithmetic (60 gravity and 240 wheel calls per
second at 60 fps, every run complete, across twelve threads). MASTER_TEST §AU.

## L149 - EXECUTED - discovery of the physics surface closes here; Parts is the first consumer

**Decided 2026-09-26 on the owner's sequencing instruction:** *three tests tonight then building real
effects, parts will be first consumer*. All three ran (§AV). Two returned negatives. This line records that
the negatives are accepted as answers rather than as reasons to keep digging.

**What closes.**

1. **Zero-sum axle load redistribution is withdrawn as an actuator** (§AV2). The write is safe and
   arithmetically correct -- §AV1 proved it holds vertical equilibrium -- and it does nothing. It is not to be
   revived, extended, or built on. `L148`'s note that writing the per-wheel normal loads makes a car sag was
   the *first* objection to this channel; §AV2 is the second and the decisive one.
2. **Body-frame telemetry is not offered** (§AV3). No sideslip, no g-g diagram, no body-frame accelerations,
   until an orientation source is found outside the searched range.
3. **`insert1` is bookmarked, not scheduled** (`IDEA-503`). It is the only surviving route to per-corner grip
   and it is a project, not an evening. The right time to attempt it is once Parts has said which fields it
   actually needs, so the search has a specification rather than a hope.

**What this authorises next.** Parts, built on the capability §AU proved and nothing more: vehicle-level
lateral grip, live and reversible (`L148`), plus NCM's own server-authoritative simulation (`IDEA-458`). Every
Part declares which of the three channels its felt effect terminates in (`IDEA-505`), and the composer refuses
to promise a felt effect on a channel that does not exist.

**Why stop discovering here rather than after one more test.** Both remaining unknowns were answered in one
sitting and both said no, so the expected value of the next experiment fell sharply -- what is left is
`insert1`, which is expensive and currently unspecified. Against that, the proven capability has no consumer
at all: `gripScale` still comes from a JSON file a human edits (`IDEA-502`). **The binding constraint moved
from *what can the carrier do* to *what is the carrier connected to*,** and `KB-136` sits directly across
that. Continuing to widen a capability nothing consumes would be the more expensive mistake.

**Basis.** MASTER_TEST §AV, three settings driven on Production by the owner on Carrier 0.1.13. Note that the
first reading of §AV2 was a false positive caused by comparing maxima across unequal windows (`KB-143`); the
negative is from duration-controlled percentiles and the correction is recorded rather than quietly applied.

## L150 - EXECUTED - Parts implementation is authorised, bounded to the spec's own first instruction

**Decided 2026-09-26 on the owner's instruction** to move into Parts after the ledger pass. This line exists
because [18_PARTS_ECOSYSTEM.md](18_PARTS_ECOSYSTEM.md) carries **STATUS: SPEC** and says in terms *"Nothing
built, nothing authorised... Do not build from it"*. Building from it without recording an authorisation
would be precisely the silent authority decay `L125` and the docs gate exist to prevent.

**What is authorised: the spec's own opening instruction and nothing past it.**

> *Do not make the parts yet. Build the periodic table, the grammar, and the factory that can eventually
> make them.*

So: the mechanical ontology, the architecture profile, and the compatibility resolver. **Not** authorised by
this line: R&D generation, manufacturing, supply, inventory, the secondary market, barter, procedural naming,
or any individual part. Those stay SPEC and need their own authorisation when they are reached. The document
keeps its SPEC banner for that reason -- the majority of it is still unauthorised owner intent.

**Why now rather than after `KB-136`.** `L149` closed discovery on the grounds that the binding constraint
had moved from what the carrier can do to what it is connected to. Parts is the consumer that specifies the
connection, and the ontology layer needs no transport at all -- it is pure server-side vocabulary. The
transport work (`KB-136`) becomes scheduled by a consumer rather than argued for in the abstract.

**One condition the spec attached, now satisfied.** 18_PARTS_ECOSYSTEM ruled performance effects out of its
first pass with a specific gate: *"Effects come only after a separate audit of what Cyberpunk / OPEN//77 /
NCM can actually manipulate. Do not speculate them into the schema."* **MASTER_TEST SS-AU and SS-AV are that
audit**, and `IDEA-505` is its result expressed as a schema rule. Effects themselves remain out of scope;
what the ontology now carries is not an effect but an honest statement of *whether one is reachable at all*.

**Basis.** `parts.ontology` reuses `engineering.competency.FAMILIES` rather than declaring a second list of
twelve, derives the record channel from `machine.flats` rather than restating it, and refuses at load if
either authority disagrees. Seventeen tests, green under Lua 5.4 and LuaJIT.

## L151 - EXECUTED - the force channel is general, and the write widens from one lever to four

**Decided 2026-09-26, on the owner's direct challenge:** *"why did we get the grip through c++ fields if we
weren't going to actually use that methodology for more?"* The challenge was correct and this line records
why, because the reasoning it corrected was mine.

**What was wrong.** After `§AV`, NCM's capability was summarised as *one* live lever -- vehicle-level lateral
grip -- and a list of things that "cannot" be done. That list conflated **one mechanism tried and refuted**
with **never attempted**. Only one item on it was actually proven: scaling the existing per-corner
normal-load entries does not change lateral capability (`§AV2`). Everything else was untested. In particular
*"two drivers in the same car model cannot feel different"* is true of the **record** channel and has never
been true of the **instance** channel -- which is the one `L148` opened.

**The correction, stated plainly.** `gripScale` was never "the lateral lever". It was the smallest possible
demonstration of a general mechanism: **intercept the force the solver is about to apply, decompose it,
scale a component, write it back.** The along-travel component sat untouched in the same expression from the
first day. So:

| lever | acts on | expresses |
|---|---|---|
| `gripScale` | across-travel component | tyre grip (already proven, `§AU5`) |
| `driveScale` | along-travel, when pushing | power delivery |
| `brakeScale` | along-travel, when retarding | braking |
| `rollBias` | left/right normal load, zero-sum | roll stiffness, anti-roll feel |

Drive and brake are separate multipliers because they are separate Part families; one number could not
express a car that gains power without gaining stopping ability.

**`rollBias` is the axis `§AV2` never tested.** That experiment moved load front-to-rear and found no change
in *grip*, which is why load redistribution is dead as a grip lever. It says nothing about left/right and
nothing about **attitude** -- and `§AU3` separately observed that scaling these entries makes a car sag into
its suspension, so they demonstrably do move the body. Roll is what an anti-roll bar is for. Expect a change
in how the car leans and, on `§AV2`'s evidence, expect no change in how much grip it has. Those are
different claims and the build is instrumented to tell them apart rather than to hope.

**The authorisation.** `L148`'s five properties are unchanged and every new lever holds all five: stateless
and recomputed from the game's own value each call; exactly reversible at the inert value because the
reconstruction *is* the decomposition; inert by default and the default ships; bounded and clamped, with the
clamp logged; scoped to the latched player vehicle under SEH, one fault disabling writes for the session.
`L148` authorised the lateral component specifically, so this line extends that authorisation to the three
new levers **under the same five properties and no others**.

**Still not authorised, and not by this line.** Input-command authority (`KB-135`) -- throttle, brake and
steer remain the driver's. And calling engine functions rather than writing fields: `ApplyForceAtPosition`
(`611586815`), `ApplyTorqueAtPosition` (`3303544265`), `ApplyAirResistance` (`3489929719`) and
`ApplyLowSpeedResistances` (`1695226878`) are all confirmed present in this build's address table, and they
are the route to true per-corner forces and direct yaw authority -- but **their signatures are not
established**, LTBF's headers expose only getters, and calling a function with hand-built arguments is not
reversible the way writing a float back is. That needs its own recon step and its own decision line.

**Basis.** The same interception point, classifier and SEH harness proven across Carrier 0.1.2-0.1.14 and
live on Production. Shipped in 0.1.15.

## L152 - EXECUTED - Parts reach a car, and the channel that carries them is the per-player one

**Decided and built 2026-09-26**, on the owner's instruction not to stop at a bookmark: *"we said we were
doing parts... we are not stopping until parts are in place, affecting cars."*

**What was missing, precisely.** Three force levers were proven live on Production (`§AU5` grip, `§AW1`
drive, `§AW2` brake) and Parts existed as an ontology, an architecture profile and a compatibility
resolver. **Nothing connected them.** The levers were readable only from `ncm_carrier.json`, a file on the
player's own disk, so the whole proven capability was reachable by one person with a text editor and by
nobody else. There was no path from a fitted component to a force.

**What this line authorises: that path, end to end.**

```
fitted parts -> parts.handling.compose -> player state bag -> client -> WebSocket -> applyHandling -> force
```

| piece | where | what it does |
|---|---|---|
| `parts.handling` | `ncm/core/parts/handling.lua` | pure; composes fitted parts into three clamped scales |
| `NcmHandling` | `ncm_world/server/handling.lua` | per-player compose and publish to `ncmHandling` |
| push loop | `ncm_world/client/carrier_bridge.lua` | reads its OWN bag (`KB-41`), pushes on change |
| `cmd: handling` | `bridge/server.{hpp,cpp}` | a second message on the socket projections already use |
| `applyHandling` | `vehicle/physics_probe.cpp` | clamps again, stores, logs every move |

**Why the INSTANCE channel and not the record channel, stated as the answer to the owner's question**
(*"do we care about machine flats if it affects every car in the server?"*). The record channel writes
TweakDB flats keyed by RECORD: one client cannot hold two setups for one model. The instance channel scales
the force the solver is about to apply to ONE BODY -- the latched player vehicle -- so it is **per-player by
construction rather than by convention**. Two drivers in the same Galena with different engines feel
different. That is the property Parts needed and the record channel cannot supply at any price.

**Three families, and the other nine are refused rather than approximated.** `tires`, `power_unit` and
`brakes` have proven quantities; suspension, steering, aerodynamics and mass have none, because anti-roll
and yaw balance are **moments** and `§AW3` refuted the per-corner load entries with a mechanism. A part
naming an inexpressible family gets a named refusal and the whole compose fails -- it is not silently
dropped, because a driver paying for a component that does nothing, and nobody finding out for a month, is
the failure `IDEA-505` exists to prevent. `parts.ontology.INSTANCE_QUANTITIES` was corrected from one family
to three in the same change, and `parts.handling` now **asserts at load** that the two tables agree, so the
ontology cannot quietly lie to a designer again.

**Balance is not decided here and no number in the path is a design judgement.** 18_PARTS_ECOSYSTEM puts
component balance, rarity and loot tiers explicitly out of scope, so each part states its own effect and the
module's job is validation, combination, clamping and reporting. Combination is multiplicative within a
lever -- which is the correct arithmetic for independent multipliers on one quantity and, more importantly,
is **commutative**, so a composed setup cannot depend on the order a Lua table happens to iterate in.

**Safety, as properties rather than promises.** Every one of `L148`'s five holds unchanged; this line adds
three that are specific to taking orders from a socket:

- **Clamped twice.** The server clamps while composing so it can tell a player their setup was capped; the
  carrier clamps again because it does not trust the wire and should not.
- **One owner per value.** A composed setup takes ownership of the three levers on arrival and
  `ncm_carrier.json` stops driving them, saying so once in the log. Two writers on one value is not a
  design -- the file's 1 Hz loop would otherwise erase a fitted engine a second after it arrived.
- **Losing the server restores inert.** `clearHandling()` runs on bridge disconnect, so a driver keeps
  neither a stale advantage nor a stale penalty from parts the world can no longer vouch for.

**What does not exist, said plainly rather than implied.** There is **no parts inventory**: ownership,
acquisition, fitting, wear and the garage UI are Parts layer 4 and are not authorised. `server/handling.lua`
holds an in-memory table and exposes `NcmHandling.setParts` for whatever eventually owns that truth. Nothing
persists across a restart, and a persistence schema written before the inventory it stores would be a guess.
`/ncm.setup` drives the real mechanism -- the same call the inventory will make -- so a PASS is a PASS of the
path and not of a shortcut around it.

**One failure this nearly shipped with, kept because it is the instructive kind.** The WebUI relay page
whitelists every event name it forwards. `ncm:machine.handling` was not in it, so the server would have
composed correctly, the client would have pushed correctly, and the carrier would have heard nothing --
every symptom pointing away from the one file at fault. Caught by reading the transport before deploying
rather than by driving. It is the same shape as `KB-136` and the comment in that file now says so.

**Basis.** `L135` (the server composes, the carrier applies, neither decides the other's business), `L148`
and `L151`. Shipped in Carrier **0.1.20** and `ncm_world`, live on Production 2026-09-26.

## L153 - LOCKED OWNER DIRECTION - Foundry is vehicle R&D over existing geometry

**Owner direction, 2026-09-26. Architecture representation remains under review and no implementation is
authorised by this line.** The prior AI/generative-geometry Foundry branch is abandoned. Foundry does not use
AI-generated vehicle geometry, text/image-to-3D, procedural mesh synthesis, diffusion models, an AI Foreman,
training-data provenance work or a GPU/model pipeline.

### The three processes remain distinct

1. **Parts R&D creates technology:** immutable component Design revisions inside the bounded Parts grammar.
2. **Vehicle R&D / Foundry creates reproducible automobile Designs:** it selects from compatible component
   Designs which legitimately existed and were accessible at that historical world time, on a previously
   validated vehicle lineage/substrate.
3. **Manufacturing creates physical assets:** it instantiates an already-released factory specification through
   bounded batch/cadence/shelf-cap production. It does not design and does not reroll a BOM per Machine.

Parts R&D is not reopened or replaced by this direction. Foundry consumes it.

### The three content resources remain distinct

- **Validated geometry/substrate breadth** establishes lineages. A new usable mesh is a rare new family tree and
  is introduced deliberately, not exhausted on day one.
- **Human-authored, runtime-valid appearance treatments** provide finite visual depth within each lineage. They
  are reserved and allocated across derivative Designs, and low remaining runway must be observable.
- **Procedurally evolving component technology** provides engineering depth over world history.

Paint does not create an engineering Design. A Design may allow several factory appearances; each manufactured
Machine receives one actual renderable factory treatment from that palette.

### Historical and physical invariants

- A released Vehicle Design revision freezes one factory BOM/specification, lineage, manufacturer,
  collaborators, allowed factory palette and R&D provenance. A later change is a new Design revision, never an
  edit of the old one.
- Every stock Machine manufactured from that Design begins from the same engineering specification. Permitted
  batch variation is only on dimensions explicitly allowed by the Design, such as factory appearance.
- The Machine's later installed physical Parts, wear, repair, repaint, owner and history do not rewrite the
  factory Design.
- Lineage, Vehicle Design revision, production run, permanent physical `assetId`, current configuration and live
  runtime entity are separate identities. The existing physical-asset model is preserved.
- Vehicle R&D is deterministic/auditable and may produce nothing. Completing R&D, promoting a Design, releasing
  it to an economy and repeating its manufacture are separate events.
- Unreleased validated substrates are controlled content inventory. A game/internet vehicle count is not a
  usable-NCM count; the installed game must be inventoried and candidates validated before admission.

### What this line does not decide

It does not name tables, repurpose `vehicleKey`, alter the current runtime-record uniqueness invariant, author a
generation-zero BOM, approve a catalogue expansion, start a migration or authorise Foundry implementation.
Those questions are reviewed in
[38_FOUNDRY_VEHICLE_LINEAGE_ARCHITECTURE.md](38_FOUNDRY_VEHICLE_LINEAGE_ARCHITECTURE.md), which remains a
**PROPOSAL** until the owner rules on it.

## L154 - EXECUTED - approximation is allowed; claiming a mechanism you do not have is not

**Decided 2026-09-26, hours after `L152`, on the owner's challenge:** *"why cant we approximate. strip
pureness from 100% to 05%"*.

> **Numbered L154, not L153.** A concurrent session claimed `L153` for the Foundry scope ruling while this
> was being written. `IDEA-380` predicted exactly this -- `Next free ID` and the decision counter are
> read-modify-writes on shared files with no lock -- and it has now happened for a decision line rather
> than a backlog row. Renumbered before commit, so no duplicate reached the repository. **This is the sixth
> time a rule kept only in prose has failed, and the fix is still an assertion, not more care.**

**The challenge was right and the error was mine.** `L152` refused nine of the twelve families outright.
Correcting it matters more than the code, because the mistake was a *category* one and it will recur in
other forms.

**What I conflated.** Two rules, one worth keeping and one invented:

- **Worth keeping (`IDEA-505`, 18_PARTS_ECOSYSTEM 8.1):** *do not promise a felt effect a channel cannot
  carry.* That is about honesty.
- **What I actually enforced:** *do not express a family at all unless a lever literally IS its quantity.*
  That is about exactness, it is far stricter, and it defends nothing.

A stiffer suspension genuinely raises usable mechanical grip. A wing genuinely adds grip and genuinely
costs straight-line speed. A lighter shell genuinely accelerates, stops and turns better. Expressing those
through `gripScale` and `driveScale` is a **coarse model of a real effect**, not a fabrication. The
fabrication would be calling a suspension part *roll balance* -- a MOMENT, refuted for this channel by
`§AW3` with a mechanism.

**So fidelity became a property of an expression rather than a gate on one.**

| | families | meaning |
|---|---|---|
| `direct` | 3 | the lever IS the quantity: tyres, power unit, brakes (`§AU5`, `§AW1`, `§AW2`) |
| `approximated` | 8 | a real effect, coarsely modelled onto levers it does not literally own |
| refused | 1 | `steering`, and for a mechanism -- see below |

**Where the honesty went: `losses`.** Every expression, including the three direct ones, must enumerate
what it provably cannot do, and the module asserts at load that none is empty. That list is what a panel or
a component description must read before promising anything. Examples, chosen because each is the thing a
player would most reasonably expect and will not get: aerodynamics cannot express **speed dependence**
(real downforce scales with v²; this is constant); cooling cannot express **time dependence**, which is
the entire point of cooling; chassis cannot change **actual mass** (`total_mass` at `+0x1BC` is verified
and deliberately unwritten); transmission has **no discrete gears**; every moment-shaped effect --
anti-roll, brake bias, differential lock, torque split -- is named as a loss wherever it is adjacent.

**The mechanism: `effect ^ weight`.** A family declares terms, each a lever and an exponent, and a part's
effect is raised to it. Weight `1.0` is full coupling; `0.5` is partial (a 1.44 gearbox delivers 1.20 to
the road); **`-0.25` is an inverse coupling**, which is how one number on a wing adds grip and costs drive
force at once. Exponents rather than blend factors for a reason that is not aesthetic: `a^w * b^w =
(a*b)^w`, so composition stays commutative and a car cannot depend on the order a Lua table iterates in.

**The topology is physics; the weights are a first pass.** Which lever a family touches, and in which
direction, is not a taste question -- drag opposes drive whatever anyone prefers. The exponents are honest
starting values awaiting play data, in the same spirit as `machine.projection`'s `WET`, and no test pins
one, because a test that did would turn tuning into a failure.

**The one refusal, and why it is not squeamishness.** `steering` changes RESPONSE -- rack ratio, geometry,
assistance -- not the magnitude of any force the interception reaches. The only honest expression would be
input authority, and `KB-135` reserves throttle, brake and steer to the driver; `L148` did not authorise it
and `L151` explicitly declined to. A part that says *sharper turn-in* and delivers *more grip* is
describing a mechanism it does not have, which is the exact thing this line permits everywhere else
because everywhere else the mechanism is real.

**An unplanned result worth recording.** Four families have no drive-model flat at all (cooling,
transmission, electrical, chassis) and every one of them now reaches `driveScale`. Steering, the one family
the instance channel cannot carry, turns out to **have** a flat. The two channels therefore cover the
periodic table between them with no family left at simulation-only -- down from four. Nobody designed that;
it falls out of two independent tables, so `test_parts` now asserts it, because a coincidence that useful
would otherwise break silently.

**What did not change, and deliberately.** The carrier is untouched: still three levers, still the same
clamps, still clamping again because it does not trust the wire. Approximation is entirely a server-side
composition concern, which is `L135` working as intended -- the server composes, the carrier applies, and
widening what NCM can say cost the plugin nothing.

**Basis.** `L152`, and the owner's correction of it. Live on Production 2026-09-26 with Carrier 0.1.20
unchanged; `ncm_world` reports `3 direct, 8 approximated, 1 refused`.

## L155 - LOCKED OWNER RULING - Machine-keyed Parts and bounded derivative performance

**Approved 2026-09-26 as a ten-point package, including immediate `assetId` keying and `KB-146` work.**

1. Permanent Machine `assetId`, not player ID, is the authoritative key for fitted Parts and the resulting
   current Machine configuration. Player identity is only the delivery/authority context for the Machine the
   player currently controls.
2. `KB-146` is a prerequisite defect: an active setup must positively bind `assetId -> current runtime vehicle
   entity -> exact physics body`. Missing, stale or mismatched evidence restores inert. The Carrier must never
   choose the fastest vehicle-shaped body as a fallback.
3. Runtime record flats normally describe the shared substrate baseline. They are not the per-Machine channel
   and cannot safely distinguish concurrent derivatives which share that substrate.
4. A rare Design-level record clone is permitted when a released derivative genuinely requires record-channel
   separation. This is an exceptional, scheduled content release rather than the default way to manufacture
   descendants.
5. A clone-backed release requires a distinct vehicle record **and** a distinct referenced drive-model record;
   cloning only the vehicle record would leave the handling flats shared. Exact record names remain runtime
   adapter/provenance detail, not semantic Vehicle Design identity.
6. A derivative need not always produce a new felt runtime behaviour. Engineering, eligibility, economy,
   collectability and history may distinguish it. Any simulated-only difference must be labelled honestly and
   must not claim a physical effect the runtime does not express.
7. Concurrent use is never forbidden merely because two Machines share a record or mesh. Instance-safe channels
   carry current Machine effects; a required record-only distinction either earns a validated clone-backed
   release or is not offered as a concurrent physical distinction.
8. OPEN//77's per-instance `setPerformance(id)` surface is added to the experiment register. It is not adopted
   until NCM proves authority, replication, ownership transfer, reset/reconnect and same-record concurrency on
   the pinned build.
9. Clone-backed Designs have operational weight: they require catalogue admission, build provenance, packaging,
   restart/deployment and live validation. Treat them as deliberate content drops, not ordinary repeat mints.
10. This line authorises the immediate Machine-keyed Parts/live-binding prerequisite only. It does not authorise
    Foundry schema migration, record-clone production, catalogue expansion or economy release.

**Basis.** Owner approval of the coordination package following the performance-channel review; `L153`, `L154`,
`KB-146`, Proposal 38, and the existing permanent `vehicle_asset.asset_id` identity model.


## L156 - LOCKED - Three levers is a SPACE: families are directions, and the levers constrain each other

**Decision.** The instance channel expresses a component family as a **direction in the three-lever space**,
not as an allocation of one lever, and after composition the levers **cap each other**.

1. A family declares terms across any of `gripScale` / `driveScale` / `brakeScale`, with signed exponents.
   Its `fidelity` describes its FIRST term -- its own quantity. Every other term is a coupling and is
   modelled, whatever the primary fidelity says.
2. **No two families may share a normalised direction.** Two families differing only in magnitude are one
   part wearing two names. `parts.handling.directionKey` makes this checkable and the suite asserts it over
   every expressed family.
3. Two couplings are adopted, both applied once after composition and both **downward only**:
   `traction_ceiling` caps `driveScale` at `0.50 + 0.80 * gripScale`, and `brake_grip_limit` caps
   `brakeScale` at `0.40 + 0.80 * gripScale`. A rule that could RAISE a lever would invent force no part
   paid for, so ceilings reduce and never add.
4. A coupling ceiling is reported separately from a clamp, in the log and in chat, because "your engine is
   worth 1.25 of the 2.00 you asked for" and "the carrier's hard bound cut you to 2.00" are different facts
   about a car. Both name the rule that fired and what to do about it.
5. A ceiling may never fall below the capped lever's own floor; asserted at load against the source lever's
   minimum.
6. `losses` continues to carry what a family provably cannot express. Two entries now recur across the
   whole table and are the honest ceiling of this channel: **no speed dependence** and **no time
   dependence**, because a lever is a constant.

**What this corrects.** `L154` allowed approximation and then, in the same table, gave `transmission`,
`drivetrain`, `cooling` and `electrical` the identical direction -- `driveScale` alone at 0.5, 0.5, 0.3 and
0.3. Eleven families, eight distinguishable behaviours at best. The word "approximated" was carrying weight
the arithmetic was not, and a player fitting one of those four could not have told it from another. Two
ordinary couplings had also simply been missed: braking force is grip-limited (`tires` did not touch
`brakeScale` at all, which is wrong rather than simple) and drag shortens a stop as well as costing top end.

**What it deliberately does NOT do.** It does not touch the carrier, the wire, or the three-float payload;
a client on Carrier 0.1.24 gets all of it from a resource restart. It does not make a lever a function of
speed, load or time, which is what `cooling` and `electrical` actually need -- `IDEA-532` holds that design
and this line is explicitly not a substitute for it.

**Coefficients are a first pass.** The topology is physics -- drag opposes drive whatever anyone prefers --
but the exponents and the two ceiling lines are starting values awaiting play data, in the same spirit as
`machine.projection`'s `WET` table. 18_PARTS_ECOSYSTEM puts component balance out of scope and no number
here is a design judgement.

**Basis.** Owner ruling, 2026-09-26, on reviewing the `L154` expression table: *"most of these are just
drive scale"*. The `derive custom formulas from our interactions between the 3 broader scales` framing is
the owner's and is the substance of points 1 and 3. Live verification is MASTER_TEST §AY as amended.


## L157 - LOCKED - Top speed is a DECLARED NUMBER per Machine, delivered by the governor

**Decision.** Top speed is not an emergent physical quantity on this platform and NCM stops treating it as
one. It is an authored number per car, scaled by parts, and delivered by the `ceiling` carrier --
`Open77.vehicles.setPerformance(vehicleId, profile)` -- and never by the force write.

1. The baseline is **authored**, in `data.vehicle_catalogue.TOP_SPEED_KPH`, populated once from
   `Open77.vehicles.ratedTopSpeed` (a gearing rating, which is a SPECIFICATION) via the client-side
   `/ncm.ratedtopspeed` dump. **An absent entry means NO CEILING, never a guessed one.**
2. `parts.handling` composes a `topSpeedScale` from four families, clamped to **[0.80, 1.25]**. Two of the
   four exponents are NEGATIVE: `aerodynamics` and `transmission` are both fitted to go faster and both
   cost top speed, to drag and to gearing respectively.
3. A **class ruleset always wins** when it is lower. Most-restrictive-wins, as `machine.projection`
   already applies it. A part may not buy past a ruleset.
4. **`accelerationScale` is never written.** The platform's rule -- and `machine.projection`'s
   `MAX_ACCELERATION_SCALE = 1.0` -- is that the governor withholds and never adds. Raising a top speed
   here lifts a ceiling NCM itself imposed; it does not add force. **This is what makes L157 need no new
   authority to add power.**
5. An observation may never become the baseline (`IDEA-328`, `IDEA-331`).

**The state of the evidence, stated plainly.** When this was written **nothing in NCM had ever
successfully capped a top speed.** `setPerformanceClass` is called by `client/main.lua` but its data
source `GlobalState.ncmCeilings` has never reached a client (`server/state_probe.lua`: *"class ceilings, a
shipped feature, have never applied"*), its only producer was the RB15 class disabled by `KB-144`, and its
last live run was 154 attempts with zero applied. The 355 km/h figure in `class.lua` is a measured cliff
written into a table and was never enforced. The per-instance server call was present in the deployed
binary, permitted, and had **zero call sites**.

So `/ncm.topspeed` (MASTER_TEST section BA) is a capability spike that proves or kills the mechanism, and
this line is provisional on it. **If BA fails, top speed is not reachable on this platform** and that
becomes the answer rather than a quietly reshaped design.

**Basis.** Owner ruling, 2026-09-26: *"isnt top speed relatively arbitrary per car??? its not a physics
problem"*, and the follow-up demand to trace the capability rather than cite a table row.


## L158 - LOCKED - One mechanical fact, one carrier, enforced statically

**Decision.** `machine.expression` holds a static map from mechanical fact to the single carrier that
expresses it. Both composers assert against it at load. It is the cross-composer half of the rule
`machine.projection` has always stated and could never fully enforce.

1. `claim()` stays, and is not sufficient. It is **per-draft**: `projection.compose` and
   `handling.compose` build separate drafts in separate modules, so neither guard can see the other. And
   `applyWeather` never called it at all.
2. **Wet grip and wet braking MAGNITUDE move to the instance carrier.** `slip_progression` and
   `turn_friction` stay on the record, because a scalar force multiplier provably cannot express the shape
   of a curve. Each carrier keeps the half it can actually carry.
3. `parts.handling` gains named contributors on the same layer vocabulary the record carrier already uses
   -- `parts, wear, weather, thermal, chrome, ruleset`. **`chrome` is therefore a named socket from day
   one**, which is the chrome-hack onramp at no cost.
4. Contributions are quantised to 0.01 before reaching a lever, because `signature()` formats at `%.4f`
   and an unquantised drifting term would republish the state bag twice a second per driver.
5. **An inert contributor is TRACED, never omitted.** A layer returning exactly 1.0 must be
   distinguishable from a layer nobody wired up -- the `IDEA-516` failure class.

**Why this is not hypothetical.** `KB-145` found seven dead flats, and two are `M.WET`'s largest entries:
`lateral_grip` -> `.frictionMulLateral` (0.18) and `brake_friction` -> `.brakingFriction` (0.15). More than
half of wet weather was already a silent no-op. **`IDEA-508` exists specifically to make those two resolve
again**, and on that day wet grip would have been applied on both carriers at once, with nothing able to
catch it.

**A second defect found and fixed on the way.** `NcmMachine.setWeather` had exactly one caller and it was
a console command; `ncm_world` never read `Open77.environment` at all, so `wetness` was permanently zero
in production. That is upstream of `KB-136` -- fixing the transport would have delivered a correct payload
saying "dry" forever. Now wired, with `world.environment` added to `ncm_world` and the read reporting its
own outcome once, because a missing permission and a missing API are indistinguishable otherwise.

**Basis.** Owner direction to build the systems end to end, 2026-09-26; `KB-145`, `IDEA-502`, `IDEA-508`,
`IDEA-516`, Report 36 section 4.


## L159 - LOCKED - Tyre temperature is a server-side per-Machine model; the window is a PENALTY

**Decision.** Tyre temperature is modelled server-side, keyed to `assetId`, and expressed as a
downward-only multiplier on `gripScale` and `brakeScale`.

1. **One temperature for the whole car.** `parts.ontology` declares the `per_corner` channel does not
   exist and names "per-corner tyre temperature" specifically; MASTER_TEST AV2 returned a clean negative;
   `SERIALISATION_UNIT = { tires = SET }` already records the consequence. This is the only ontologically
   legal shape, not the cheap one.
2. **The multiplier never exceeds 1.00.** It is 1.00 in the window and 0.85 at both extremes. Being in the
   window is the absence of a penalty, not a reward -- the owner's rule, and what lets this inherit `L156`
   point 3 rather than needing authority to add force.
3. **It touches grip AND brake directly.** An earlier draft assumed a reduced `gripScale` would propagate
   through the `L156` couplings. **It does not**: at grip 0.85 the ceilings are 1.18 and 1.08, and a stock
   car sits at 1.00 on both, so neither bites. The couplings are correct; they were never the propagation
   mechanism.
4. **Heat is WORK, not momentum.** `integral F dt` is kg m/s; heating is `integral F.v dt`. Without the
   speed term a 30 km/h hairpin heats a tyre as much as a 200 km/h sweeper.
5. **State lives with the Machine and keeps cooling in real time**, hosted by `odometer.lua` -- which
   already polls every vehicle at 1 Hz, already resolves speed with an availability check, and is already
   keyed by `assetId`. Long absences settle in closed form, so a car parked for ten minutes is cold rather
   than five seconds cooler.
6. Not carrier-side: the Carrier holds one bound body and has no per-entity map. Not client-side: snapshot
   fields are `client_attested` and a client number feeding grip is forgeable for 15 percent of a car.
7. **Day and night get no lever.** `secondsOfDay` feeds AMBIENT temperature, so a cold night makes tyres
   harder to warm -- the real mechanism -- rather than applying a flat penalty for driving after dark.
   Weather feeds the same term.
8. The HUD gauge shows a POSITION in the window, not degrees, and draws **no needle at all** when the
   temperature is unknown (`IDEA-361`).

**Basis.** Owner direction, 2026-09-26: *"lets also try a method of tracking and modeling active tire
warmth or coolness + a window ... not pure accel for being in the window like an arbitrary stat boost, but
inferred grip and braking differences, our best guess."* Owner-selected parameters: ~60 s to the window,
15 percent at the extremes, temperature keeps cooling while parked.


## L160 - LOCKED - The ROAD and the TYRE are two bodies, and neither is the other's proxy

**Decision.** Track temperature is modelled as a body distinct from air temperature, and the road gets a
grip layer of its own beside the tyre's.

1. **Three temperatures, named separately.** `airTemperature` is the sky's number. `trackTemperature` is
   air plus solar gain by day, minus clear-sky radiative loss by night, minus the heat standing water
   carries away. `ambient` -- what the tyre exchanges heat with -- is an alias for the TRACK, because a
   tyre is pressed against asphalt and not against the air above it.
2. **Rain scales the radiative terms to zero rather than reducing them.** A wet road is neither sunlit nor
   radiating to a clear sky; it is under cloud, wet, and pinned near the air. This is what makes "a warm
   track" a state that weather can destroy outright.
3. **`surface` is a new named layer** in `parts.handling.LAYERS`, between `weather` and `thermal`. That
   order is the causal order: the sky decides what the road is, the road decides what the tyre is working
   against, the tyre decides what the contact patch delivers.
4. **`surfaceMultiplier` must not read wetness, and that is load-bearing.** Rain is already charged
   directly by `weatherContributor`. If the road also charged for being wet, one weather state would be
   billed three times and the model would collapse into "rain is everything". What the road charges for is
   TEMPERATURE, which a dry winter morning has too. Asserted by a test whose name says so.
5. **Asymmetric, and never a boost.** Cold asphalt costs 0.10 at the extreme, greasy hot asphalt 0.04.
   1.00 at the optimum. "A warm track is grippier" and "a warm track is where you stop being charged" are
   the same statement under `L156` point 3, and only the second is a ceiling NCM may write.
6. **Absent rather than defaulted.** With no clock the surface layer does not appear at all, and
   `trackTemperature({})` returns `AMBIENT_DEFAULT` with no daily term. A plausible guessed default would
   read exactly like a working feature -- which is precisely how `KB-151` hid for as long as it did.
7. `LOSSES` gives up "track temperature as distinct from air temperature", which is now modelled, and
   gains the road's THERMAL INERTIA (here the asphalt responds to rain and to the clock instantly, where
   real asphalt stays warm through a short shower) and the absence of shade, tunnels and bridge decks.

**What it produces.** Brisk cornering, sustained, across the day:

| condition | air | track | surface | tyre | position |
|---|---|---|---|---|---|
| 03:00 rain | 8 | **0** | 0.900 | 67 | -0.51 cold |
| 09:00 dry | 20 | 20 | 0.986 | 87 | +0.06 window |
| 15:00 rain | 24 | 16 | 0.975 | 83 | -0.05 window |
| 15:00 dry | 28 | **44** | 0.993 | 111 | +0.75 hot |

Compounded across all three environmental layers, grip runs 0.910 on a dry afternoon to 0.709 in
pre-dawn rain. **An emergent result worth naming: rain on a hot afternoon puts tyres perfectly in the
window and charges 18 percent for the water.** That was not designed; it fell out of two independent
bodies, and it is the kind of trade the model exists to produce.

**Basis.** Owner ruling, 2026-09-26: *"hot weather daytime sun should make tire warmer, while hot weather
dqytime sun in it itself carries its own modifier for grip, so in essence, warm track is its own thing,
while the tire model itself is its own. so a tire may be cold technically on a warm track, but then warms
up quicker than a cold tire on a cold track."* This supersedes `L159` point 7's "day and night get no
lever" in one respect only: day and night still get no lever **on the tyre**, and now get one on the
**road**, which is a different body.


## L161 - PROVISIONAL - Nothing NCM writes as a FORCE can raise a top speed

**Decision.** Recorded as a finding, not a design. The instance carrier cannot raise top speed, and the
evidence is the owner's own drag runs.

**The trace.** Galena drag, 2026-09-26: stock 38.4 s, `power_unit 3.0` 36.7 s, `+ tires 1.5` 35.5 s.
`L156`'s couplings capped the effective drive at 1.217 and then 1.575. Acceleration moved on every run.
**Top speed did not move at all** -- the owner's report, and the correction that produced this line.

**Why that is evidence and not merely a null result.** If the plateau were a DRAG EQUILIBRIUM, terminal
velocity would go as the square root of drive force: 1.575x force is `sqrt(1.575) = 1.25`, a 25 percent
higher top speed, which nobody could miss on a drag strip. An **identical** plateau under 1.575x force is
not a force balance at all. It is a hard cap, enforced somewhere NCM's force write does not reach.

**Consequences, stated plainly:**

1. `driveScale` is an ACCELERATION lever and is not a top-speed lever. A previous session's claim that the
   drag runs were "a proven top-speed mechanism" was wrong; they prove the opposite.
2. **Top speed control can therefore only ever be DOWNWARD from a native cap**, by any mechanism available
   to us. That is not a limitation of the implementation; it is the shape of the platform, and it happens
   to agree with `L156` point 3 and `MAX_ACCELERATION_SCALE = 1.0`.
3. `Open77.vehicles.setPerformance` is the only candidate for moving the cap itself, which makes the
   `MASTER_TEST` BA spike more load-bearing rather than less. It currently returns ACCEPTED for
   `topSpeedKph = 40` and does not slow the car; the `getPerformance` read-back is deployed and unrun.
4. The reachable fallback, if BA fails, is **withholding drive near a target speed** -- a taper on
   `driveScale` toward zero. That is a DIFFERENT operation from what the drag runs tested and is not
   refuted by them, but it is also not yet proven. The carrier already computes `speedSq` per frame at the
   write site (`vehicle/physics_probe.cpp`), so the input exists with no new read and no wire change.
   Evaluating it per frame in the carrier would reopen the coefficient-evaluation question `IDEA-532`
   raises, which is the honest cost and is recorded rather than hidden.
5. **A measured cap may not become the authored baseline** (`IDEA-328`, `IDEA-331`). It may validate one.

**Provisional** because point 3 is unrun. If BA passes, this line keeps points 1, 2 and 5 and drops 4.

**Basis.** Owner correction, 2026-09-26: *"those three timed runs you quoted accelerated faster but all
had same top speed."*


## L162 - EXECUTED IN CODE / LIVE-GATED - Parts becomes a conserved economy of physical assets

**Decision.** The owner authorised Parts economy/UI v1 after the seven OPEN//77 assessments were reviewed.
The implementation may create immutable component Designs, discrete manufacturing runs and serialized
physical component assets; expose a 25-Design Base Market catalogue; persist Machine configurations; and let
an owner purchase and fit compatible Parts through the existing `NcmHandling.setParts(assetId, parts)` seam.
It remains **production-disabled by default** until migration, conservation, restart and live handling evidence
is recorded in §BF. Building it is not a live PASS (`L69`).

The v1 boundaries are locked:

1. **One asset, one custody.** A component is on a market shelf, in owned storage, installed, consumed or
   disposed. Market quantity is an aggregate view over physical assets, never an abstract counter. FIFO
   purchase claims one exact asset and all purchase/fitting work is idempotent and transactional.
2. **Fitment is authored server truth.** Nineteen stable positions describe the supported interfaces. A
   full-system kit may occupy several positions atomically but contributes its effect once. Unresolved
   compatibility cannot enter Base Market; clients receive only decisive public results and reasons.
3. **A configuration is immutable history.** Fitting creates a new Machine configuration revision and moves
   every displaced component to ordinary Parts Inventory. Required positions cannot be empty. The target must
   be owned and either dematerialized or authoritatively stationary and unoccupied; unreadable runtime state
   fails closed.
4. **Factory history is not invented.** Existing MaiMai, Galena and Hella assets receive deterministic factory
   components and revision 1 without changing vehicle identity/history. Existing odometer distance becomes
   original-component exposure; unrecoverable historical serial/run/installer/time remains unknown. Future
   manufacture commits the Machine and its eleven factory components/configuration in the same transaction.
5. **R&D cannot expand the physics grammar.** Manufacturer evaluations are deterministic, versioned and
   restart-stable, may legitimately yield `no_design`, and can only vary bounded effect/fitment/trade-offs in
   already supported families. Private seeds/personality inputs never reach clients. Only decisive Base-line
   outcomes with broad starter compatibility enter Base Market supply; specialists remain undistributed.
6. **UI warns; it does not forbid planning.** The Market keeps every car visible and overlays text/icon plus
   green/red fitment. Buying for an unowned or incompatible future Machine remains the same 900 ms hold action.
   Machine Index gains Parts Inventory and the equivalent keyboard/controller/touch selection path.
7. **No invented performance ratings.** The six buyer metrics have permanent UI positions but display
   `Not rated` until authoritative evidence or an accepted derivation exists. Relative component projections
   carry DIRECT/MODELLED fidelity and limitations; they do not fabricate absolute car performance.
8. Player R&D, secondary trading/barter, repair, wear consequences and steering Parts are outside v1. Exposure
   is recorded now so wear can be introduced later without reconstructing use.

**Implementation.** Forward migrations 031-032; `parts.catalogue` and `parts.rnd`; typed component services in
`ncm_league` and `ncm_world`; Market payload v2 with separate vehicle/component streams; Machine Index Parts
Inventory; world-side install-state authority; odometer-coupled exposure; resource hydration and reconciliation.
`ncm_league.partsEnabled` defaults false and is republished live to the world/UI.

**Evidence at decision time.** Catalogue/R&D pure tests pass under both supported Lua interpreters; the panel
render harness covers the split stock panes, mixed fitment overlay, serial provenance, future-planning warning,
factory-original inventory and eligible hold-to-fit. No database migration, concurrency, restart or physical
handling claim is marked live until §BF records it.

**Basis.** Owner plan, 2026-09-26: *"the first parts are acquirable in base market and equippable to your car"*,
followed by the explicit Parts Economy and UI v1 implementation instruction.


## L163 - EXECUTED OWNER RULING - Online is the current development surface; deploy Parts there enabled

**Decision.** There is no second active environment in the present pipeline. NCM Online is unlisted,
whitelisted to the owner/test identities, and is the place where this feature is developed and proved. Do not
delay Parts behind a hypothetical separate Development deployment or split the pipeline further. Deploy the
tested resource set to Online with `ncm_league.partsEnabled=true` by default; retain the live tunable as an
emergency park, not as the normal shipped state.

This changes **where §BF runs**, not what constitutes evidence. Deployment and successful boot are not live
gameplay PASSes (`L69`). Migration/backfill/conservation checks and purchase, fitting, restart and felt handling
rows still receive evidence individually on Online. Production promotion language in `L162` is superseded for
the current private pipeline; its safety and transaction gates remain binding.

**Basis.** Owner correction, 2026-09-26: *"development is not our pipeline right now ... online is essentially
development only accessible to me ... deploy"*.

## L164 - EXECUTED OWNER RULING - the first observation vocabulary is accepted; the estimator is not

**Decision.** The owner ruled on `31_CAPABILITY_AUDIT.md` on 2026-09-26, after the machine-discovery /
market-discovery / scanning / machine-knowledge threads were read end to end against the code.

**Section 9 of the audit is accepted as authority.** NCM may define its first typed observation vocabulary
from the six characteristics that audit found safe -- observed speed, lateral acceleration, yaw rate and
stability, slip angle, speed retention and gradient -- because every input is present, server-side and
authoritative. The provenance work the audit's section 10 put ahead of it is built in the same pass.

**The estimator is NOT accepted and is not built.** `30` section 6 and `31` section 10 both say the envelope
mathematics get their own reviewed proposal, and its anti-midpoint (`IDEA-337`) and determinism
(`IDEA-338`) invariants deserve that pass. Evidence accumulates first; inference is a later decision.

### What this ruling makes true

1. **Every characteristic is a demonstrated-capability floor.** `28` section 29: *"A lower bound on
   demonstrated capability is not an upper bound on maximum."* This is what allows one reducer to serve all
   six without any of them lying, and it is why `observed_speed_floor` keeps its existing name instead of
   becoming `observed_speed_max`.
2. **Two of six are wired; four are declared and refused.** The odometer's 1 Hz server loop already reads
   speed and already derives cornering load, so those two have a real producer. The other four need
   `velocity`/`angularVelocity` fields that loop does not read yet (`IDEA-544`). **A vocabulary entry with
   an invented producer is worse than one with none**, and a core test asserts that exactly two are wired so
   the gap cannot be closed by accident.
3. **An empirical claim owes more than an identity reveal.** An observation kind must name its basis and
   must attest a live physics owner, or core refuses it. Section 7's hazard -- an unowned car reads a
   confident `0` because nothing is simulating it -- is now a refusal at the boundary rather than a caution
   in a comment.
4. **`ai_driven` is a tri-state.** Migration 033 adds it NULL-able and nothing defaults it. An NPC at the
   wheel is not a driver's achievement, and a build that does not report the flag must leave the row saying
   *unknown* rather than claiming a human drove.
5. **No client-attested path.** The drivetrain half exists only client-side and is structurally an
   attestation (`31` section 3). That basis stays declared and unused until there is a design for believing
   an observer about somebody else's car.

### `IDEA-359` is retired as an enforcement and preserved as a finding

`machine_knowledge.configurationRef()` refused **every** value with `configuration_substrate_absent`, because
the audit's section 6 proved build 2.31 has no component object -- no mod slots, no wheel types, no RTTI --
for `configuration_ref` to name. **Migration 031 built the record that section predicted**, so the refusal
has done its job and becomes a shape rule.

The finding is unchanged and is now the *justification*: because there are no engine components, this column
can only ever reference something NCM authored itself. Both reserved columns are filled -- `session_result`
(024) and `vehicle_knowledge_evidence` (028).

**A race result carries the configuration latched at GREEN, never the head at settlement.** `machine_configuration`
is an append-only chain and its head moves the moment a part is fitted; reading it late would attribute a lap
time to what the car became afterwards.

### Correction recorded, because the owner made it

An earlier report in this session framed Parts v1 as shipping *omniscient*, contradicting the knowledge
design. **That was wrong.** Components are gated by needing to discover the market they are in, and Base
Market is universally known, so every player seeing its parts is correct by design.

The real defect was narrower and structural: the component query named `base_market` as a SQL literal while
the vehicle half of the same payload resolved through the driver's known-market set, which is precisely what
`17_MARKET_NETWORK.md` forbids (*"must never call a singleton theShop"*). Fixed in `IDEA-545`, with no
behaviour change while one market exists.

**Basis.** Owner, 2026-09-26: *"lets fill in the gaps with code where necessary and start building on this"*,
plus the explicit ruling to build provenance and the first vocabulary while leaving the estimator alone, and
the correction *"where is the contradiction?"*.

## L165 - LOCKED OWNER DIRECTION / BALANCE OPEN - the launch economy works for one human and no AI grid

**Direction.** NCM Online's burgeoning-world economy does not depend on AI drivers or immediate population.
No AI-driver implementation is in the launch economy: an otherwise empty scheduled race runs for its human
entrant and is classified as a time trial under `L67`. This parks `L36`'s AI-backfill default and the recent
`IDEA-548` feasibility thread unless the owner deliberately reopens them; the research remains evidence, not
scope.

Both scheduled solo time trials and contested races are recurring money faucets. Ordinary races charge an
entry fee. Whether the lowest-rung time trial charges an entry fee remains **OPEN**, with the owner's present
lean being yes; free practice remains available and pays nothing. Championship/event economics continue to
own the exact fee and payout tables under `L84`, and race purses do not have to equal collected fees.

Cars and serialized Parts are the major durable sinks. Vehicle prices are intended to span an unusually wide
persistent-world ladder, from the provisional €$2,500 MaiMai floor to highest-end Machines in the millions;
the exact catalogue values and payout ratios remain balancing data. Fuel/refuelling and approximate
NCM-authored fuel behaviour are an active design investigation, not authorised implementation.

The already-specified generalized player trade surface remains the transfer authority for money, Machines and
component assets in any combination. It redistributes value and preserves custody/provenance; it is not counted
as a currency faucet and therefore cannot solve sparse-launch liquidity by itself.

**Basis.** Owner economy review, 2026-09-27: time trials and races must pay; races have entry fees; lowest-rung
time-trial fee undecided but leaning yes; no AI-driver implementation; fuel/refuelling under investigation;
persistent-world vehicle ladder from a €$2,500 MaiMai to million-eddie high-end Machines; player trade already
specified.

## L166 - EXECUTED IN CODE / LIVE-GATED - a ghost is a replay, not a competitor

**Decision.** NCM stores laps that real players drove and replays them as **ghosts**: a non-colliding car,
local to one client, moving along a stored pose stream. A ghost is **never an entrant and never evidence**.

### What this ruling makes true

1. **A ghost cannot affect anything that is scored.** Not timing, not collision, not standings, not ratings,
   not results, not settlement. It has no position, it is not counted in the field, and it is drawn outside
   the standings table. Giving a ghost a `P` number would tell a driver there was a competitor who did not
   exist, and is refused at the HUD by an offline assertion rather than by convention.
2. **A ghost wears the car its lap was set in.** `vehicle_asset.record` is the model, and the machine is
   latched when the **start line** is crossed. This supersedes the practice behaviour in which attribution
   was read when the session *closed* -- a driver who left practice, refitted and came back had their lap
   credited to the wrong machine. `session.quali` now latches at the start gate and returns the latch, the
   run's interval and its incident time in the finish result.
3. **Ghost poses are their own versioned format, separate from the telemetry sample.** `replay.pose.FORMAT`
   is stored beside every lap and a reader that meets a format it does not know refuses it by name.
   `telemetry.SAMPLE_FIELDS` is **not** extended: it is the incident/progress stream, it is sampled from the
   driver's body rather than the car, it carries no heading, and its persisted form has no version column --
   so changing it would have altered a stored format nobody can identify retrospectively, in three vendored
   copies, to serve a consumer with different needs.
4. **The poses are the client's; every number attached to them is the server's.** Only the client can see its
   own car's heading, so the client sends the line. The time, the interval, the route and the machine all come
   from the claim the race host writes when the server saw the lap finish. A client cannot upload poses for a
   lap the server did not time, and its own claimed figures are used only to check that the poses plausibly
   belong to that lap.
5. **A stored ghost is immutable.** `ghost_lap` rows are inserted and never updated; a faster lap is a new
   row and "my best" is a query. This is deliberate and load-bearing: it is what allows telemetry retention
   to be introduced later without a cleanup silently deleting the laps a leaderboard rests on.
6. **A ghost trace never touches a state bag.** A lap is roughly 45 KB against a measured ~4 KB ceiling
   (`IDEA-509`). Both directions use `vocabulary.chunks`, and every push logs its encoded size.
7. **Practice, qualifying and time trials get a ghost; a contested race does not.** A **time trial is a race
   with a field of one** (`L67`, `IDEA-001`, `driver.progression.isTimeTrial`), so it arrives on the race
   kernel with the race phases rather than as its own session kind -- and it is the same solo activity
   practice is, so the same rule reaches it. In a contested race a ghost would be clutter among real
   competitors and could be read as another entrant, so it is excluded deliberately rather than by omission.
   The race kernel's result now carries the finish **instant**, not only the duration; `totalSec` folds in the
   penalty, so the moment a lap ended was not recoverable by subtraction.
8. **`PERSONAL BEST` is the only tier authorised.** `SESSION BEST` and `ROUTE RECORD` hand one driver's
   racing line to another driver, which is a claim about a third party; both remain refused by
   `replay.lap.eligible` until the server corroborates the line from its own observation **and** the driver
   has opted in. Publishing a route record is opt-in because it exposes how someone drives.

### What this ruling does not settle

Route geometry is still unversioned -- `roots.register` replaces a route in place -- so a stored ghost can
silently belong to different geometry than the one it replays against (`IDEA-562`). That is tolerable for a
driver's own best and is a blocker for `ROUTE RECORD`. Presentation is also unsettled: props carry no opacity
field and only a yaw, so this ghost is solid and does not bank or pitch (`IDEA-561`).

**Basis.** Owner, 2026-09-27, on scope: *"Player lap ghosts are a much better near-term feature than AI
racers"*; on the car: *"its not gonna be the players car model? it should be"*; on sequencing: *"stop with
cheapest possible test bullshit, we are building it"*. Built and offline-green the same day; **no live PASS
yet** -- `wp/MASTER_TEST.md §BI` (`L69`).

## L167 - LOCKED OWNER DIRECTION / TAG ECONOMICS OPEN - evidence and accomplishments become faucets

**Research exchange.** Players may voluntarily turn in legitimate discoveries and proof-bearing observations
for NCM money. Payment attaches to an accepted, idempotent research submission, not to every automatic sample
or every incremental best-value update. The evidence keeps its source Machine, basis, time, coordinates and
configuration provenance. Turning it in does not rewrite an asset observation as model truth, and player-scoped
knowledge is not silently published merely because it became economically useful. Exact contracts, eligible
discovery sources, publication/consent policy and amounts remain open.

**Badge rewards.** The scoped Badge ladder may award a fixed amount once per tier crossing. Badge entitlement,
tier, display selection and money remain separate facts: hiding or displaying a Badge never pays, and a retry
never pays twice. Unique non-tiered Badges may carry one authored flat reward. Exact tier values remain balance
data; the Badge implementation itself is still unbuilt.

**Race Tag bonuses remain a proposal, not a blanket rule.** The owner proposed extra money for Tags achieved in
a race or time trial. `B-089-race-tags` currently defines Tags as ephemeral factual descriptors and includes
negative or abusable outcomes as well as desirable ones. If adopted, the safe boundary is a separate
championship/event or sponsor mapping from selected Tag ids to fixed bonuses plus a per-session cap. The pure Tag
evaluator never writes money, and neither "one tag = one universal amount" nor payment for every Tag is authorised.

**Basis.** Owner economy follow-up, 2026-09-27: research turn-ins for observations/discoveries, fixed Badge-tier
money, and possible per-race/time-trial Race Tag bonuses.

## L168 - LOCKED OWNER RULING - Economy v1 is the build contract, including selected Race Tag bounties

The owner accepted the combined economy direction and instructed that it be written as the specification before
implementation. [40_ECONOMY_V1.md](40_ECONOMY_V1.md) is therefore **CURRENT** and build-authorised. It governs
the Economy v1 implementation while `08_ECONOMY.md` remains the ledger/refund audit and the asset, evidence,
Badge and Race Tag documents retain authority over their own source facts.

**Launch must work for one Driver.** Free practice remains free and pays nothing. Scheduled time trials and
contested races both charge an authored fee and pay from separate tables; the provisional Street fee is €$50 for
either form, so a lonely grid does not punish the player. A field of one receives time-trial completion/target
money and never a ceremonial P1 payout. Exact values are balancing data and must be instrumented.

**The additional faucets are accepted with boundaries.** Research pays only an explicit accepted submission of
proof-bearing evidence; Badge money pays each earned tier once; a championship, event or sponsor may pay only an
allow-listed factual Race Tag through a separate capped bounty mapping. The Race Tag evaluator remains pure and
negative/contact/penalty or initially manipulable Tags do not pay. This resolves `L167`'s open Tag-economics
branch without making Tags themselves rewards.

**Cars and Parts remain the principal progression sinks.** Vehicle acquisition may also occur through exact
prize assets, earn-to-own contracts, restoration projects, commissioned manufacture, organisation/sponsor awards
and exceptional provenanced grants. Loaners/rentals are access, never ownership. Procedural Part primary prices
are fixed at immutable Design birth from authored family, capability, complexity and interface factors; scarcity
changes availability and secondary negotiation rather than engineering truth.

**Fuel follows paid settlement, not vice versa.** Its intended cost is modest, approximately 5–10% of gross
ordinary earnings, with a bankruptcy road back. Player trade is a value transfer, not a faucet. The shared
idempotent ledger, atomic settlement and itemised statement are mandatory foundations for every non-zero path.

**Basis.** Owner, 2026-09-27: *"These are strong additions"* and *"write the spec doc from your last two
answers and then we build."* The provisional tables and unresolved tuning fields are recorded in document 40;
authority to build does not make those first numbers permanent.

## L169 - EXECUTED IN CODE / LIVE-GATED - Economy v1 creates a real solo income loop

The owner rejected a narrow staged slice and authorised a broad learning implementation: *"time to implement,
not a narrow provable slice which gets us nowhere quickly, we move fast and break things thats how we learn."*
Economy v1 therefore lands as one connected local vertical rather than a resolver with no playable money loop.

Migration 035 freezes authored event economics and adds typed ledger references, one settlement receipt per
session/Driver and accepted Research contributions. A shared server economy service now owns the starter grant,
balance, atomic paid check-in, idempotent result settlement, itemised statements, abort/restart refunds and
generic one-time rewards. Solo scheduled events pay the time-trial table and never P1; contested events pay the
race table. Qualification records a result but mints nothing. Street, GT, Hypercar and sponsor-funded NCX scales
are authored data surfaced in the Guide.

The dormant Race Tag vocabulary is integrated as a pure evaluator. Its complete `qualified` fact set is kept
separate from the capped display set; settlement pays only explicitly mapped Tags and enforces a session cap.
The launch maps pay clean driving, not negative/contact/penalty or position-manipulation outcomes.

The Research Exchange has an explicit `/ncm.research` list/submit path for finite personal-first physical Machine
discoveries and server-measured capability observations. Catalogue exposure does not pay, evidence remains
provenanced, and a physical Machine/characteristic cannot mint money again through an incremental maximum or
configuration revision. Existing unique accomplishments pay once after progression persists: first finish,
first time trial and first win. This does **not** claim the tiered Badge reducer, authored research contracts or
limited world-first calls.

Fuel/refuelling and generalized player trade are not smuggled into this pass. Fuel follows measured paid-event
economics; trade must preserve the already specified asset/custody and value-transfer boundaries. The complete
offline gate is green. Migration/deployment, exact balances, duplicate/retry/restart behavior and receipts now
owe live proof in MASTER_TEST §BJ before any row becomes validated.

**Basis.** Owner implementation direction, 2026-09-27; `40_ECONOMY_V1.md`; `IDEA-564`-`IDEA-567`.


## L170 — OPEN — three questions the character / PvE reconnaissance cannot answer for itself

Raised 2026-09-27 by [../research/open77/CHARACTER_ARCHAEOLOGY_AND_PVE_SUBSTRATE.md](../research/open77/CHARACTER_ARCHAEOLOGY_AND_PVE_SUBSTRATE.md).
That pass was read-only and **changed no production behaviour**. It found three decisions that are the owner's,
not an agent's, and they block real work rather than being philosophical. Nothing was resolved silently.

### G1 — the `???` market roster contradicts a CURRENT authority document

> **RESOLVED 2026-09-27 by `L171`: option A. The roster is approved and supersedes document 17's
> clause, which is amended in place.** The analysis below is retained as the basis of that ruling.

The owner's addendum asks the Market surface to show a working total of **17 markets**: one Base Market plus
sixteen `???` silhouettes, so the interface itself says *there is more out there*.

`17_MARKET_NETWORK.md` is **STATUS: CURRENT** and is the named authority for *markets and market discovery*. It
forbids exactly that, twice and by name:

> *"Unknown markets are absent. There is no total market count, completion percentage, locked `???` market roster
> or canonical market catalogue disclosed to the client."*

> **DO NOT BUILD YET** — *"...market completion, undiscovered-market slots, global omniscient inventory..."*

and keeps it as an architectural test: *"Unknown markets are absent and no total count is exposed."* The stated
reason is leakage — hidden-market information escaping through ids, sort order, tooltips, payload shape or
inventory calls.

**The request splits, and only half of it conflicts.** The addendum's middle **LEAD** state (heard of, cannot yet
use) is *compatible*: it matches the document's own `access_policy` seam (*"knowledge and access may diverge"*),
its `player_market_knowledge.source_kind`/`source_ref` columns, and Machine Knowledge's precedent of independent
accumulating channels rather than a tier ladder. The **sixteen silhouettes** are not compatible: sixteen
silhouettes *is* a disclosed total count.

Three ways forward, stated neutrally:

- **A. Amend the document.** The `???` grid is a deliberate psychological device and the owner may simply want it.
  Cost: a decision superseding that clause, plus taking on the leak discipline the clause was protecting.
- **B. Keep the prohibition and get the same feeling another way.** The Machine Index already produces "there is
  more than you know" **without a count**, because a catalogue of encountered machines is visibly partial. Markets
  can do the same: known markets, plus *leads* as named-but-inaccessible rows. Sixteen anonymous slots say
  "sixteen"; two named leads say "there is a world out there", and are better fiction.
- **C. Split the difference.** Disclose a bounded, non-numeric shape ("NCM knows of other suppliers in this
  district"), which is a count of nothing. Needs care not to become a count by another route.

**Recommendation: B, plus one addition** — give a brand-new player **one lead immediately**, from NCM Dispatch, so
the second market is a name they cannot yet use rather than an empty slot. That is the invitation the addendum
wants, it satisfies the document, and it is the first authored thread, all in one message row.

**Blocks:** `IDEA-608` (the world graph), the market half of `IDEA-609` (trade provenance as a lead), and any
authoring of the market network.

### G2 — where may a multi-step race constructor live?

> **RESOLVED 2026-09-27 by `L179`. The answer is "in an integer", and single player had it all along.**
> The premise below is wrong in one specific place: *"a six-step wizard is a tree"*. Foreman's is not.
> `race_commands.lua` keeps the entire constructor state in one quest fact (`ncm_foreman_builder_step`) and
> `MTEJournalHandler.reds` renders each step as a FLAT LIST OF FINAL ACTS filtered by that integer -- choosing
> "sprint" writes one field and increments a counter, and opens nothing. So the `venue_options` ruling is
> satisfied rather than scoped away, no CEF surface was spent (the card is drawn on `venue.html`, which is
> already always attached), and the F6-only alternative below was not needed. Retained unedited as the record
> of what the question looked like before the source was read.

`competition.venue_options` carries an owner ruling (2026-09-21, amended 2026-09-23):

> *"at most four options, each one a FINAL ACT and never a branch, no sub-menus and no tree. An option that cannot
> apply right now is ABSENT, not greyed out — a disabled row is a dead end the player has to read and reject,
> which is the failure KB-32 describes from the other side."*

SP's Foreman constructor is a **six-step wizard** (type → field → launch → pressure → district → confirm), and the
owner's brief asks for spontaneous race creation at a lighter, more world-adjacent surface. Those two cannot both
be satisfied: a six-step wizard is a tree, and a tree cannot live at a venue prompt under that ruling.

Either **the constructor is F6-only** — and the world prompt offers `Race Here` as a single final act that accepts
defaults, which is also exactly what `IDEA-602` proposes — **or the ruling is scoped to venues specifically** and
some other world surface may branch.

There is a hard budget on the F6 side either way: eight CEF surfaces per resource and `ncm_world` already holds
seven (`IDEA-570`), so a constructor must be a *mode of `panel.html`*, as the Landing panel was, not a new page.

**Blocks:** the surface design of `IDEA-602` and `IDEA-603`.

### G3 — is a market in *other humans* ever acceptable?

> **RESOLVED 2026-09-27 by `L172`: no. Self-paper only.** The analysis below is retained as the basis
> of that ruling.

SP's Billie sells winner slips on **any runner**, priced by a softmax book over the field. In single player the
runners are machines and the economy is private, so that is safe. In a persistent multiplayer economy it is a
prediction market on a small population of real people, and it is the collusion surface: two players can shape a
result, repeated head-to-head pairings can print money, and pricing a player's own probability from their own
record makes **deliberately losing profitable**.

The reconnaissance recommends **self-paper only, indefinitely** — the player raises their own exposure on their own
finish, opponent strength enters as a *risk-model input* rather than as odds on a person, and no product ever
quotes a price on another human. That preserves the whole conceptual loop (*"I am confident, so I increase my
financial exposure"*) and removes the market in people.

This is a product decision with a permanent economic character, not a tuning choice, which is why it is here
rather than in the backlog.

**Blocks:** `IDEA-610`.

**Basis.** Owner brief plus addendum, 2026-09-27; the reconnaissance document above; `17_MARKET_NETWORK.md`;
`competition.venue_options`; `betting.lua`. No implementation was authorised and none was performed.


## L171 — LOCKED — the undiscovered-market roster is approved and supersedes document 17's prohibition

**Decision (owner, 2026-09-27).** The Market surface **may** present a fixed roster of undiscovered market slots
against a working target of **17 markets** — one Base Market plus sixteen unknown — so that the interface itself
tells a new player a larger network exists. This is `L170` G1 **option A**, taken over the recommended option B.

**What this supersedes.** `17_MARKET_NETWORK.md` (STATUS: CURRENT, authority for markets and market discovery)
forbade exactly this in three places, and all three are amended in place rather than silently overridden:

- the knowledge-model paragraph — *"There is no total market count, completion percentage, locked `???` market
  roster or canonical market catalogue disclosed to the client"* — struck and replaced, with the original text
  preserved struck-through;
- the **DO NOT BUILD YET** list — `undiscovered-market slots` struck from it;
- the architectural test *"Unknown markets are absent and no total count is exposed"* — rewritten.

`17_MARKET_NETWORK.md` remains the authority for markets. It is amended, not demoted.

**The condition attached to the ruling, and it is not optional.** The reason document 17 wrote the ban was
**leakage**, and that hazard is entirely unchanged by the decision. The count is now deliberately disclosed;
**nothing else about an undiscovered market may be.** No name, operator, district, inventory, specialization or
manufacturer may reach the client through slot ids, slot ordering, sort keys, tooltips, payload shape, row counts
within a filter, or any inventory call. Slot order must not be inventory order, and a slot id must not be
derivable from a `marketId`. A slot discloses that something exists there, and that is all.

**What did not change.** *Market completion* stays on the DO NOT BUILD list: a roster of unknown slots is not a
completion metric and must not acquire percentages, counters or "12 / 17 discovered" framing. The canonical
market catalogue is still never disclosed. Knowledge, access, stock, eligibility and affordability remain
separate questions with separate refusal reasons.

**17 is a working scale, not a locked number.** The owner stated it as a useful target; nothing here fixes it,
and the UI must not hard-code it.

**Still recommended, and unaffected by the ruling:** the **LEAD** state — a market you have heard of but cannot
yet use — which was compatible with document 17 and is compatible with the roster. It is what `IDEA-609` (trade
provenance creates leads) resolves into, and it is the difference between a slot that flips straight to usable
and one that becomes a name first. Giving a new player one lead at session zero is now additive to the roster
rather than a substitute for it.

**Basis.** Owner ruling, 2026-09-27, answering `L170` G1; the addendum's section 5/7; the analysis in
[../research/open77/CHARACTER_ARCHAEOLOGY_AND_PVE_SUBSTRATE.md](../research/open77/CHARACTER_ARCHAEOLOGY_AND_PVE_SUBSTRATE.md)
section VII.3. Affects `IDEA-607`-adjacent market work, `IDEA-608` and `IDEA-609`; unblocks market authoring.

## L172 — LOCKED — NCM never sells a wager on another player

**Decision (owner, 2026-09-27).** Answering `L170` G3: **no.** If BookQueen Billie comes to NCM Online she sells
**self-paper only**. The player may raise their own financial exposure on their **own** finish, and on their own
streak legs. NCM will **not** quote odds on another human being.

**What this means mechanically.**

- Light / standard / heavy contracts on the player's own finish: **port**, with stake derived from progression
  (`maxStake(tier) * ratio`) rather than chosen, as SP did.
- Streak tickets on the player's own legs: **port**, filtered to settlement-authoritative races.
- The SP **winner board** — `buildWinnerBoard`, the softmax over `driverThreatScore`, the 8% overround, and the
  `Back the favorite` / `Back the value` choices — **does not port.** It stays in the archaeology as a record of
  what single player did.
- Opponent strength still matters, but enters as a **risk-model input** to the player's own multiplier, exactly
  as SP used average field threat. A stronger field raises what your own paper pays. It never becomes a price on
  a person.

**Why.** The conceptual loop worth keeping is *"I am confident in my upcoming performance, so I increase my
exposure"* — a money sink with a conditional faucet, which is what the economy wants (`IDEA-554`, `IDEA-558`).
A market in other players is a different product: a prediction market over a small, non-anonymous population,
where two people can shape a result and repeated pairings can print money.

**What this disposes of, by construction rather than by rule.** Exploit **E7** (collusive odds shaping) cannot
occur if no product prices another player, and IV.5's "revisit at >= 6 humans" clause is withdrawn. The exploits
that remain are the self-wager ones and they are still live design work: solo exclusion, manufactured weak
fields, head-to-head repetition, disconnect abandonment, abort farming, field collapse, and **record shaping** —
which is the sharpest, because pricing a player's own probability from their own record makes losing on purpose
profitable. `L172` does not solve those; it removes a different and larger class.

**Basis.** Owner ruling, 2026-09-27, answering `L170` G3; Part IV of the reconnaissance document. Scopes
`IDEA-610`.


## L173 — LOCKED — NCM counts overtakes

**Decision (owner, 2026-09-27).** Add overtakes. The quest graph's reaction library depends on them
(`41_QUEST_GRAPH_PASS1.md` §7.2 — *"P8. Seven passes. P1."*), and single player had them while Online does not.

**It needs no new telemetry.** `session.race` already persists `r.crossings[gateIndex] = now` for every entrant at
every gate. Running order at a gate is that gate's crossing times sorted ascending; an overtake between gate *N*
and *N+1* is a pair whose relative rank inverted across that segment. The derivation is a pure function over data
the session already holds, so it is `ncm/core` work with no host, schema or network change.

**Rules taken with the decision:**

- A pass counts only where **both** drivers crossed **both** gates of the segment. A driver who retires is not
  passed by everyone behind them.
- Passes are counted per segment, so one pair swapping repeatedly counts each time it actually happens.
- A pass is **contested** when the same pair has a contact incident in that segment's time window, and **clean**
  otherwise. Contact data is passed in rather than imported, so the module stays pure.
- Overtakes are **a count, not a Race Tag.** `gained_positions` and `came_through` already exist and answer a
  different question (net start-to-finish movement, not passes made).
- Lapping is out of scope for v1 and must not be silently counted as a pass.

**Basis.** Owner ruling, 2026-09-27, answering `IDEA-621`.

## L174 — LOCKED — the Scanner is authorised, superseding two documents that deferred it

**Decision (owner, 2026-09-27).** Build the Scanner.

**What this supersedes.** Two authority documents deferred it explicitly, and both are amended in place:

- `28_MACHINE_KNOWLEDGE.md`: *"Do not promise scanner telemetry before engine capability is validated"* and
  *"This is not authorisation to build the scanner, component recognition, configuration history or engineering
  knowledge."*
- `16_MACHINE_INDEX.md`: build `2.31.13+op77.87` provides *"enough for a bounded Scanner experiment, not enough
  to promise the final UX."*

The deferral is lifted. The **engineering caution inside it is not**, because it was about capability rather than
permission: what the Scanner may *claim* is still governed by `competition.machine_knowledge`'s evidence
vocabulary. A scan may establish `identity_reveal` and `observed_configuration`; it may not invent capability it
did not measure, and an observation remains a floor rather than a maximum (`28_MACHINE_KNOWLEDGE.md` §7 stands).

**Sequencing this implies.** The Scanner has two halves and they are not equally ready. The *knowledge* half —
what a scan writes, how it enters the Machine Index, what provenance it carries — is buildable now against
`machine_knowledge` and migration 033. The *interaction* half — aiming at a machine and scanning it — depends on
client capability that has never been measured, and `Open77.character.aimedEntity` is the likely input. Build the
knowledge half first; prove the interaction half with an experiment rather than a promise.

**Unblocks.** `Flashbulb` (`41_QUEST_GRAPH_PASS1.md` §11), whose entire trigger is scanning behaviour, and the
Scanner/Research channel of Machine Knowledge's five parallel channels.

**Basis.** Owner ruling, 2026-09-27, answering `IDEA-622`.

## L175 — LOCKED — Leads are a first-class object

**Decision (owner, 2026-09-27).** Build Leads.

A **Lead** is knowledge of something the player cannot yet use: a market heard of but not accessible, a part
whose origin is unknown, a person mentioned but not met, a place named but not found. It is the middle state
between *unknown* and *accessible* that `17_MARKET_NETWORK.md` anticipated when it separated knowledge from
access (*"knowledge and access may diverge"*), and that `28_MACHINE_KNOWLEDGE.md` already models for machines as
independent accumulating channels rather than a tier ladder.

**What this unblocks, and it is most of the graph:**

- `Glass` cannot trigger at all without Leads — his eligibility *is* "multiple unresolved Leads".
- Trade provenance creating a lead instead of an unlock (`IDEA-609`), which is the coupling that makes the player
  economy generate PvE rather than bypass it.
- The `???` market roster's middle state (`L171`), so a slot can become a *name* before it becomes a shop.
- Dex's context shelf (`41_QUEST_GRAPH_PASS1.md` §2.4), which is a list of unresolved things by another name.

**Rules taken with the decision:**

- A Lead names a **subject** (market, machine, part design, person, place, event) and carries **why the player
  knows it** — `source_kind` and `source_ref` — because the provenance is what later characters react to.
- A Lead is **not a quest**. It has no steps and no objective text. It resolves when the thing becomes known or
  accessible through any route, including routes nobody authored.
- Leads must not become a checklist. No count, no percentage, no "3 / 8 leads followed".
- A Lead may expire only if the authored fiction requires it; the default is that knowledge is permanent.

**Basis.** Owner ruling, 2026-09-27, answering `IDEA-608` and the Glass gap in `41_QUEST_GRAPH_PASS1.md`.

## L176 — LOCKED — the voice harness keeps its vocabulary and overlap tests and loses its word ceilings

**Decision (owner, 2026-09-27).** The single-player voice harness's **per-character word and sentence ceilings are
struck down.** They were built against the WolvenKit phone in single player, which was a highly restrictive
display surface, and they encode that constraint rather than a design intent. NCM Online's Messages surface has no
such limit.

**The owner's reason is the important part, and it inverts the usual argument:** enforcing a small envelope on
every character risks making them *all sound the same*. A 22-word ceiling does not make Dex characterful; it makes
Dex clipped, and a cast that is uniformly clipped has lost exactly the variety the harness existed to protect.

**What survives, because it serves that same goal better than the ceilings did.** `voice_harness.lua` had four
mechanisms and only one of them was a UI artifact:

| Mechanism | Status |
|---|---|
| per-character word / sentence ceilings | **struck** (`L176`) |
| `requiredAny` — domain vocabulary a character must use | **kept** |
| `forbiddenAny` — vocabulary that belongs to another character | **kept** |
| pairwise token-overlap failure at >= 0.55 across all character pairs | **kept, and it is the load-bearing one** |

The overlap test is the direct mechanical expression of *"no two contacts sound the same"*. Scenario ownership
(who answers which player question, and who deflects) is kept for the same reason.

**Dex is recharacterised.** The archaeology described Dex's voice as *terseness*; the owner's correction is that
it is **neutral guidance**. Dex is the contact who routes without colouring, not the contact who is short. That
distinction matters for authoring: a long Dex message is fine, an *opinionated* one is not. `forbiddenAny` for
Dex (odds, chassis, podium, favorite, chalk, heater) already encodes this correctly — it forbids other
characters' domains, not length.

Consequently the violation flagged against `41_QUEST_GRAPH_PASS1.md` §2.2 (Dex's ~75-word opening message) is
**withdrawn**. It is in voice.

**Basis.** Owner ruling, 2026-09-27, on the harness analysis in
[../research/open77/CHARACTER_ARCHAEOLOGY_AND_PVE_SUBSTRATE.md](../research/open77/CHARACTER_ARCHAEOLOGY_AND_PVE_SUBSTRATE.md)
section I.9. Scopes `IDEA-601`: port the validator without the ceilings.

## L177 — PROVISIONAL — ambient population is built in two layers, and only one of them can be cleared by radius

**Decision, 2026-09-27.** NCM Online gets an **ambient population service** (`ncm_world/server/ambient.lua`,
core `world.ambient`). It exists because an empty city is not a taste problem: a street with nobody on it
removes the only scale reference a driver has, and it is the first thing every tester has said about the world.

**The reconnaissance record was half right and it was read the wrong way round.** The 2026-09-19 finding that
*"vanilla traffic is per-client"* is **true** and is confirmed here from the platform's own embedded Lua prelude
at `2.31.13+op77.102`. What was inferred from it — that traffic is therefore not server-side — is **false**.
Both of these are true at once:

| | Vanilla population | Our own ambient layer |
|---|---|---|
| Density / enable switch | **server-owned and replicated** — `Open77.world.setPopulation(bucket, { crowd, traffic, police })`, needs `world.population`; the client half is read-only | n/a |
| Granularity | `crowd` is a real multiplier; `traffic` and `police` are **binary** on 2.31, and `getPopulation` says so itself (`trafficGranularity = "binary"`) | per entity |
| Scope of the switch | **the whole routing bucket**, never a radius | any radius, any shape |
| Entities | spawned **per client**; nothing on the server can name, move or remove one of them; two players on one corner are not looking at the same cars | canonical, shared, removable by id |

**So the ask — clear traffic out of a race corridor — is the SERVER-OWNED layer's job, and only it can do the
job by radius.** That is the whole reason the layer exists.

**The vanilla switch is not used in the shared world at all, and the arithmetic is why (`KB-165`).** Amended the
same day, after the owner asked the obvious question I had not: *there is always a race — don't you see a
conflict?* There is. The five shipped street series run 20/30/60/180-minute cadences at staggered offsets — **21
starts in any three-hour window** — and per-slot corridor holds merge into **one continuous interval, 100% of the
clock**. A bucket-wide switch in a world with a race every twenty minutes is a **permanent** switch, so the first
version of this decision would have emptied Night City for good: this service's own purpose, inverted, by the
service itself.

The guard is therefore **structural, not an operator setting** (`world.ambient.maySuppress`): the shared bucket is
never suppressed for a corridor, because the switch has no radius and the corridor does. A bucket a race has to
itself still is — there the only players it can reach are the ones racing, which is exactly `IDEA-638`'s case and
the reason to want it. `ambientVanillaSuppressShared` is the explicit escape hatch for a private server where
everyone present is at the race, and it is off.

**A corridor is also only held for a race that is really going to happen.** A scheduled slot with no entrants
holds nothing, and a scheduled row stops holding 120 seconds past its own start — long enough for the T-60 session
to form and take over — rather than guessing a length for a race that may never have begun. Without this, empty
slots on a 20-minute cadence would have stripped every published route of ambient life as well.

**Three rules the service holds.**

1. **These are not AI racers.** Nothing the service spawns enters a session, is scored, or appears in a result.
   The goal is that the courier on the corner is in the *same place* for two players — which is the one thing
   per-client traffic can never be — not that NCM has a field of bots.
2. **Nothing is removed that somebody can see.** A corridor despawn needs *two* signals to agree: the host's
   projection read (`Open77.npcs.owner(id).readyClients`, which is exact — zero means no client is drawing it)
   **and** a distance rule past every player's streaming radius. An unknown projection state counts as watched.
   An entity that fails the test is **deferred and reported**, not dropped: a corridor that is not clear yet
   looks exactly like a corridor that failed, and saying which is the point.
3. **The corridor is the whole lap, not the grid box.** It is a capsule around the route polyline — start,
   authored intermediates, finish — so the calendar publication now carries the finish's **coordinates** and the
   intermediate list, not just a name. Once a session is **live** the corridor is rebuilt from that session's own
   published **gates**, which are the line race control actually laid out for it; a reversed grid or a shortened
   route would otherwise be cleared along a road it is not using.

**Provisional, not locked, because nothing here has a live PASS yet.** The offline evidence is the full gate,
52 core director tests, a 40-assertion host harness against platform doubles, and an `ncm-stub` scenario that
drives the real `ncm_league` publication into the real `ncm_world` service across two Lua VMs. **None of it caught
`KB-165`, and that is worth naming:** every test looked at a single race, and the defect only exists when you
multiply one race by the calendar. What is owed is `wp/MASTER_TEST.md` §BL — and in particular the two things no double can answer: whether `joinTraffic` actually
puts our cars on the authored lanes on a live client, and what budget the world carries without hurting frame
time during a race. Scopes `IDEA-635` through `IDEA-639`.

## L178 — EXECUTED IN CODE / LIVE-GATED — component Wear & Tear is active; tyre compounds remain deferred

**Owner ruling, 2026-09-27.** The owner accepts the authoritative odometer as trustworthy and directs the Wear
& Tear system to be implemented now; Hard / Medium / Soft tyre compounds are explicitly later work. This lifts
`L120` point 7 as an implementation blocker. It does not convert an offline build into a live PASS (`L69`):
deployment, migration 038 and the end-to-end checks in `MASTER_TEST` §BM remain owed.

The implemented boundary is deliberately narrower than proposal 42's eventual stress-aware model:

1. **Distance is the first-generation clock.** `component_asset.exposure_m` remains immutable, additive factual
   distance. No collision, incident, race flag, client-reported aggression or compound-specific thermal history
   contributes to ordinary wear.
2. **Wear is pure and component-local.** Core `parts.wear` derives stable per-asset thresholds from asset identity,
   the versioned family profile, exposure and append-only service relief. Condition and severity are never stored.
3. **Eight families wear in v1.** Tyres, brakes, suspension, cooling, drivetrain, transmission, power unit and
   electrical have one named first condition each. Aerodynamics, structure and chassis have no routine mileage
   consequence until an honest stress model exists.
4. **Consequences only withhold.** Active conditions contribute downward-only grip, drive and brake multipliers
   through the existing named `wear` layer and sole `parts.handling` composer. Wear never improves a Machine and
   never invents a new physics channel.
5. **Service advances a threshold.** Migration 038 adds append-only `component_service`; the first provider is a
   deterministic network service with an authored price and fixed workmanship record. It adds bounded `relief_m`,
   never reduces exposure, never resets identity/history and cannot make a component immortal.
6. **No health percentage is exposed.** Parts Inventory shows normal / attention / critical, the named condition,
   service count and a priced hold action. The driving HUD receives targeted system lamps only; critical changes
   fill/silhouette as well as colour.
7. **`KB-163` is fixed before consequence.** A fit or installed-part service first settles the Machine's pending
   odometer interval against the outgoing configuration. A failed checkpoint retains the accumulator and refuses
   the operation instead of silently moving history.
8. **Compounds are not smuggled in.** All tyre Designs still use the existing thermal profile. `IDEA-628` and the
   component-keyed swap semantics in `IDEA-630` remain later work.

**Pacing values are first-pass gameplay tuning, not real-world claims.** They are centralized under wear profile
version 1 and may move after §BM/live kilometre and economy evidence. Scope: `IDEA-631`-`IDEA-634`, migration 038,
core `parts.wear`, Parts Inventory service and the race warning strip.

## L179 — EXECUTED IN CODE / LIVE-GATED — players call their own races, and `G2` is answered by single player

> **ITS INTERACTION SHAPE IS SUPERSEDED BY `L181` (same day). The event plumbing below still stands.**
> What `L181` replaced: the six-step machine, the five-option ceiling, the four-route list, and the
> discipline question. What survives unchanged: `impromptu` as an event class, `NcmCalendar.adopt` as the
> non-cadence route, entry at the mark, the announcement, no purse, and both cadence guards. The reading of
> single player below is still accurate and is still why `G2` is closed — the step machine was a faithful
> port, and a faithful port of the wrong product. Read `L181` for the shape that shipped.

**Decision (owner, 2026-09-27).** *"Before continuing the PvE, we need the ability for players to set up races
themselves as outlined by Quickie and Foreman to be implemented."* Built this session.

**`G2` is resolved, and not by a judgement call.** `G2` asked where a multi-step race constructor may live, given
the owner's `venue_options` ruling — *at most five options, each a FINAL ACT, never a branch, no sub-menus, no
trees*. That ruling reads like a prohibition on a constructor. It is not, and single player proves it: Foreman's
builder in `race_commands.lua` is a **six-step machine whose entire state is one integer**
(`CUSTOM_RACE_BUILDER_STEP`, published as the quest fact `ncm_foreman_builder_step`), and
`MTEJournalHandler.reds` renders each step as a flat list of final acts filtered by that integer. Choosing
"sprint" opens no sub-menu; it writes one field and advances the counter. **A step machine is not a tree.** Each
step is its own short flat list, so the ruling is satisfied rather than bent. The constructor lives in an integer.

**Quickie and Foreman are two different products and both are recovered.** Quinn hands over a race already built
— one offer, one yes (`createQuickRacePhoneOffer`). Foreman builds one to order. This session implements
Foreman's half, because Quinn's half is a *pre-filled draft* and therefore a small consequence of it once the
generator exists.

**Two single-player steps are deliberately dropped, and the module says so in code (`M.OMITTED`).**

| SP step | Fate online | Why |
|---|---|---|
| RACE TYPE | kept as **discipline** | street sprint / drag / time attack / drift |
| FIELD SIZE | **dropped** | SP spawns 3–9 AI rivals. Online fields are human and the field is whoever turns up, so a chosen size is a promise nothing can keep |
| START TYPE | kept as **launch** | grid / rolling / side-by-side; drag skips it, exactly as SP does |
| DIFFICULTY | **replaced by class** | street/serious/elite sets AI driver tier and prestige bands. With a human field there is no dial to set; what cars are admitted is the real lever |
| LOCATION | kept as **route**, with a new meaning | SP picks a district to search in. `P12`/`P17` make position the whole point of an impromptu event, so this is the nearest suitable starts to the creator, closest first |
| SUMMARY | kept | confirm or scrap, same words |

**`impromptu` was authorised on day one and never built.** `P12` granted it (*"any driver, from wherever they
stand; lightweight rules"*), `P17` said it posts through the scheduler, and `impromptu` has sat in the
`EventClass` enum and the `event.class` column ever since with **zero code on either side of it**.
`NcmCalendar.adopt` is the non-cadence escape hatch `organized` already proves, so no new scheduling concept was
needed — which is also the answer to the standing objection that the calendar is cadence-derived and cannot
represent an ad-hoc race. It cannot *materialise* one; it can adopt one.

**Three things a player-called race deliberately is not.**

1. **Not invitational.** It is announced server-wide and entered at the start line like a calendar event (`L35`:
   you must be on your mark, `venueRadiusM = 60`). Seats and offers are what `organized` is for.
2. **Not paid.** `economy` is left nil, so settlement finds no purse. Two friends alternating wins would
   otherwise be a money printer, and the economy is younger than this feature.
3. **Not free of cadence.** `KB-165` is a standing trap: a per-race permission is a permanent cadence. Hence
   `impromptuCooldownSec` (900) bounding one driver **and** `impromptuMaxOpen` (2) bounding the board — the
   second is not redundant, because five drivers each obeying the first would still fill it.

**The draft and the option list are server-side.** The client draws the published bag and sends back an id; the
server re-derives the step and refuses anything it did not offer, exactly as `ncm:venue.option` already does. A
stale card therefore cannot create an event.

**Shipped.** `competition.race_builder` (pure, 25 tests), `ncm_league/server/impromptu.lua`,
`ncm_world/client/race_builder.lua`, the `#build` card in `web/venue.html`, two tunables in
`NcmCalendar.settings`. No migration: the `impromptu` enum value already existed.

**Basis.** Owner instruction, 2026-09-27. Recovered from `ncm-localized/.../modules/race_commands.lua` lines
1051–1360 and 3470–3590, and `r6/scripts/MT_Ecosystem/MTEJournalHandler.reds` lines 60–92, 365–395, 697–755.
Scopes `IDEA-641`–`IDEA-645`. Resolves `G2`, left OPEN by `L170`.

## L180 — EXECUTED IN CODE / LIVE-GATED — NCM's in-world cards live on the right, never the centre of the view

**Decision (owner, 2026-09-27).** Three placements corrected in one ruling, because they are one rule:

1. **The Street Call builder must not be in the F6 panel shell**, must not take the middle of the screen or the
   whole screen, must be scrollable if its options need more room, and must be **no bigger than the panel used to
   enter a race at a ring**. It is also **hotkey-opened, not always present**.
2. **The race-entry panel at a ring** overlaid the middle of the player's view while they were standing on their
   mark. Moved to the right.
3. **The live race graph** stood on the left during a race. Moved to the right.

**The rule these share:** while a player is in the world — on their mark, or driving — the centre of the screen is
the road. NCM may annotate the edges of that view and may not occupy its middle.

**Consequences worth recording, because each one is a constraint the implementation obeyed rather than a
preference.**

* The builder is drawn on `web/venue.html`, the page that already holds the ring entry panel. That is not
  convenience: it makes "no bigger than the race-entry panel" **structurally true** rather than a number someone
  has to maintain, and it costs **zero** of this resource's eight WebUI surfaces — `panel.html` would have spent
  the last free one.
* The race graph is **mirrored, not merely shifted**. Its dot labels are `white-space: nowrap` and overflow the
  152px box on purpose; a graph moved to the right with labels still reading rightward would push driver names
  off the edge of the screen. Line, dots and labels all flip.
* `#panel`'s `max-width` drops 980px → 860px so that a full-width panel anchored right still stops short of the
  screen centre (1920 − 44 − 860 = 1016px) instead of reaching back across it.
* The builder takes the **E key** while it is up, and `client/calendar.lua` yields both the venue option list and
  that key via `NcmClientBuildActive` — the same idiom `NcmClientRaceActive` already uses. Two surfaces cannot
  own one key.

**The hotkey is F5, and this is the weakest part of the change.** `KB-62` records that three of NCM's four
function keys collide with something, that the collisions keep moving, and that a static audit has a short shelf
life. F5 was chosen against KB-62's occupied list (F2 wardrobe, F6 POV, F7 camera, F9/F10 PolyZone, F8 already
ours) and that reasoning may expire the same way the last one did. `/ncm.build` and `/ncm.call` are the durable
routes.

**Basis.** Owner instruction, 2026-09-27. Scopes `IDEA-646`.

## L181 — EXECUTED IN CODE / LIVE-GATED — a called race is ONE FORM, it starts where you are standing, and it is never asked what kind of race it is

**Decision (owner, 2026-09-27), correcting `L179` the same day it shipped.** `L179` recovered single player's
Foreman constructor faithfully — a six-step machine, each step a flat list of at most five final acts — and that
was an accurate port of the wrong product. Four things were wrong and only one of them was the page count.

**1. "Here" is the sane default, and it was not even available.** *"Someone starting a race here and now is not
'ok lets drive 2 km to race start together'."* The `L179` builder could only start a race at an authored node,
which made the entire premise of an impromptu race — *race, here, now* — the one thing it could not express. The
start now defaults to the driver's own position, and that position **becomes a temporary node**.

**2. Do not hide the rest.** Offering four nearest routes, *"of which none are guaranteed near"*, is restrictive
in both directions at once: it withheld 31 of 35 places AND could not guarantee the four it offered were close.
The **whole node list** is exposed, for the start, the finish and every checkpoint. Nearest-first ordering is
kept as a courtesy; nothing is truncated.

**3. Do not ask what kind of race.** *"How do we enforce a drag race?"* — we cannot. There are no staged lanes,
no launch procedure, no lap counting on an open route and no judging. A discipline picker asked the driver to
choose something the server would then quietly not honour. Every player-called race is a point-to-point street
sprint, **derived and never asked** (`race_builder.M.DISCIPLINE`), because that is the only discipline whose
rules this server can actually enforce.

**4. One form, not six pages.** *"Should be all one form potentially with drop downs not a 6 page click through
thats hardly quick."* A click-through is fatal for a feature whose whole premise is immediacy.

**And one thing added: checkpoints chain.** *"If someone wants to chain nodes as checkpoints they should be
allowed."* Up to eight, in order, each becoming a real gate.

### The `venue_options` ceiling does not apply here

`L179` inherited *at most five options, each a final act, never a branch* by analogy and **the analogy was
wrong**. That ruling governs the prompt a driver gets standing at a venue — an interruption they did not ask
for, in the middle of the road. This is a form opened deliberately from a hotkey. It may carry a 35-row dropdown
and a submit button. The owner's correction is what establishes the boundary; the ruling itself is untouched.

### What this cost, and it is a real cost

**The last free WebUI surface.** A form with dropdowns needs the mouse and the keyboard. `venue.html`, where
`L180` put the card, is `pointer-events: none` and deliberately never takes focus — that is precisely what makes
it safe to leave attached during a race (`KB-67` is the bug from when it was not). Making it focusable would put
an input-capturing page permanently on screen. So the form is its own page, `web/build.html`, created only while
open and destroyed on close. `ncm_world` now holds eight of eight (`IDEA-570`); **nothing else may take one
without a decision** (`IDEA-647`).

Focus therefore follows `panel.html`'s `KB-61` discipline exactly: the page is shown unfocused, replies
`build:drawn`, and only then is input captured. A page that never replies loses the player's input back to the
game after 2500 ms. Nothing about *releasing* focus may depend on the page being healthy — a soft-lock in a
driving game costs a reconnect.

> **SUPERSEDED, 2026-09-28 (`L193`, `KB-178`). This whole subsection is no longer how the form works, and the
> cost it accepted has been refunded.** `web/build.html` is **deleted**; the form is a block on `venue.html`,
> shared through `NcmVenueSurface`, and `ncm_world` is back to **seven of eight**. Two reasons. First, the
> surface was not merely scarce: at 8 of 8, with three transport pages created and destroyed during a session,
> `WebUI.create` for the form could be **refused outright depending on timing**. Second and decisive, the form
> **had never once rendered**, for an unrelated reason in the same area (`KB-178` — the client-to-page hop), and
> the fix for that removed the need for a focusable page at all.
>
> The reasoning above is sound on its own terms and the conclusion still followed from it — *a form with
> dropdowns does need focus*. What changed is the premise: **the form does not need dropdowns.** Input is read
> in Lua with `Open77.input.isDown` (arrows, Enter, Backspace, Delete, PageUp/PageDown, and the pad), which are
> physical reads that need no focus, so the page stays `pointer-events: none` and is never focused.
>
> That inverts the paragraph above rather than weakening it: the `KB-61` handshake is not improved here, it is
> **unnecessary** — there is no focus to hold, so there is nothing to soft-lock. `build:drawn` survives only as
> a render confirmation. `L181`'s interaction shape — one form, every field visible, submitted once — is
> untouched; only the surface and the input path changed.

### A route is a list of points, so nothing new was needed to hold one

The host kit has authored routes from arbitrary points since Batch 2: `/ncm.ar start / gate / finish` records a
point list and `scenario.lua::registerCustom` turns it into nodes plus a root. A Street Call route is the same
shape with two deliberate differences, which is why `impromptu.lua` has its own registrar rather than reusing
that one:

| | Authored route (`/ncm.ar`) | Street Call route |
|---|---|---|
| Lifetime | permanent reference data | one race |
| Storage | `custom_route` row | runtime only, in `data.roots` / `data.nodes` |
| Cleanup | never | swept by `releaseRoute` once the event is closed, cancelled, gone, or an hour past its start |

`data.nodes` gained an `unregister` for this. `data.roots` has had one since the host kit; nodes did not, because
authored routes never needed it — and without it every called race would leave a start line on the map and a row
in the builder's own node list for the lifetime of the process.

**Temporary nodes are excluded from the form by construction, not by bookkeeping.** The node list filters on the
authored `raceLegal` flag, which runtime nodes do not carry — so yesterday's improvised start lines cannot appear
as today's destinations even between sweeps.

### What the form asks, and what it works out

| Field | Behaviour |
|---|---|
| **Start** | `Here` by default, or any of 35 race-legal nodes |
| **Checkpoints** | 0–8, ordered, any node, chained; each becomes a gate |
| **Finish** | any node. **No "here"** — the owner's ruling: the end *"doesnt need a here node"* |
| **Laps** | shown only when start and finish are the same node, because laps are meaningless on a point-to-point |
| **Open to** | the enabled street classes |
| **Green flag** | 2 / 5 / 10 / 20 minutes |
| ~~Type~~ | **not asked** — derived as `street_sprint` (point 3 above) |
| ~~Field size~~ | **not asked** — the field is whoever turns up (carried over from `L179`) |

**"Here" is an intent, not a coordinate.** The form stores the sentinel and the server resolves it against a
fresh position at submit time, so a form left open for five minutes starts the race where the driver is when they
post it — not where they were when they opened it. The client's live-position tick keeps the length preview
honest while they choose.

**The form previews, the server decides.** Node coordinates ride along in the schema so the page can show a
running route length as points are chained without a round trip per change. The server recomputes it and refuses
anything under 250 m regardless of what the client displayed. An unmeasurable preview reads *"length unknown"* —
never `0 m`, which would look like a refusal nobody made.

### What carries over from `L179` unchanged

The event plumbing, which was right: `impromptu` as an event class, `NcmCalendar.adopt` as the non-cadence route,
entry at the mark with `venueRadiusM = 60` (`L35`), the server-wide announcement, no purse, and both cadence
guards (`impromptuCooldownSec` 900 per driver, `impromptuMaxOpen` 2 for the board — `KB-165`). No migration.

**Basis.** Owner instruction, 2026-09-27, superseding `L179`'s interaction shape and nothing else. Scopes
`IDEA-647`, `IDEA-648`; resolves `IDEA-644`, which asked for exactly the un-capping this ruling orders.

## L182 — LOCKED / EXECUTED IN CODE / RESTART-GATED — wear onset uses very wide overlapping envelopes

**Decision (owner, 2026-09-28), from the first Online observation.** A 157.527 km Galena lit five HUD marks:
the SRV master plus critical tyre/brake and attention suspension/cooling. The odometer and exposure accounting
were correct; the pacing was not. Profile v1 put each family in a narrow ±12% band around a fixed distance, so
every Machine was effectively guaranteed the same maintenance staircase and this Galena's suspension and cooling
thresholds landed only 10 m apart.

Profile v2 replaces the staircase with broad, overlapping deterministic envelopes: tyres 750–7,500 km, brakes
1,000–12,000 km, cooling 1,500–25,000 km, suspension 2,000–30,000 km, electrical 2,500–60,000 km, drivetrain
3,000–45,000 km, transmission 4,000–55,000 km and power unit 6,000–80,000 km. Physical asset identity chooses a
stable point inside the family envelope. The attention-to-full-effect span is another 100% of that asset's own
onset distance, and service interval/cap scale from the same threshold. Families deliberately overlap, so neither
the order nor the relative distance of service is guaranteed across Machines.

At 150 km every mileage-wearing family is necessarily fresh. The observed Galena's first two onsets become
1,201.718 km (tyres) and 1,732.516 km (brakes); its next is cooling at 3,133.305 km. Existing exposure and service
history are untouched: condition is a pure projection and simply re-derives under profile version 2.

**Operational state:** full offline gate green. The two vendored `parts.wear` files are staged on Online with
rollback `/opt/ncm/backups/wear-v2-20260928T004557Z`, but the running resources deliberately remain on v1 until
the connected client leaves and an announced/empty restart is available.

**Basis.** Owner live observation and ruling, 2026-09-28. Refines `L178` and `IDEA-633`; records `KB-166`.

## L183 — LOCKED / EXECUTED IN CODE / LIVE-GATED — the quest graph's first slice is built, and Messages becomes a conversation

**Decision (owner, 2026-09-28).** Build the quest graph, starting with **Dex, Setup Stu and Rico**, then the
others. Move Messages off its own hotkey into the **F6 shell, immediately left of HELP**, and rebuild it: pick a
conversation from a sidebar, have it in the main pane, and make it feel diegetic.

This authorises Appendix A.8 of [41_QUEST_GRAPH_PASS1.md](41_QUEST_GRAPH_PASS1.md) and nothing beyond it. The
other fifteen contacts in that document remain SPEC.

### What was built

| Layer | What |
|---|---|
| `ncm/core/graph/contacts.lua` | All **eighteen** declared contacts, three authored. Discovery grammar, domains (§0.4) and the surviving voice fields. Each unauthored contact records **why** it is blocked, so the appendix is not re-derived next session |
| `ncm/core/graph/conversation.lua` | The engine: state projection (§0.3), script validation, the `L176` voice audit, the §20 trigger budget, and §0.2's re-entry rules |
| `ncm/core/graph/opening.lua` | The authored scripts, **copy preserved word for word**, plus the push conditions and their `TUNE` first numbers |
| migration **039** | `message.from_kind` widened (`IDEA-599` — the one schema blocker), nullable `thread_id` (`IDEA-614`), `player_contact`, `player_behaviour_counter`, `player_graph_budget` |
| `ncm_league/server/graph.lua` | The adapter: transcript rows, projection at read time, lead writes, the budget, the heartbeat |
| `panel.html` / `client/panel.lua` | MESSAGES as a shell tab; sidebar of conversations, one transcript, replies as a composer |
| `tools/test-quest-graph.lua` | 93 host assertions. `test_conversation` + `test_opening` add 70 offline |

### Five rulings inside the build

**1. A conversation is not a quest, and nothing stores one.** `player_contact.node` is where a conversation
*rests*, not how far it has *got*: no step, no objective, no ordering, no completion column (`L175`, §0.3).
Choices are **projected from state at read time and never persisted**, and `pick` re-projects server-side, so a
stale panel cannot force a branch it should no longer be offering.

**2. Hearing a name grants a LEAD, never a contact.** Dex, Stu and Rico all mention people who are not authored
— Quinn, Foreman, Billie, Needle, Mara, Zero, Dr. Vale. Each mention writes a `lead` row (`player.leads`,
`L175`) instead of opening a contact who could not answer. This is `IDEA-625`'s first producer: character
reveals. `Contacts.speakable` refuses to open anything unauthored, so the rule is enforced rather than remembered.

**3. A SOLICITED introduction is never rationed.** §20's budget exists to stop the *world* crowding the player.
It must not stop the player opening a door they just asked to open: a driver who picks *"Put me through"* and
then waits out a thirty-minute cooldown has been ignored, not paced. So an introduction caused by a picked choice,
or named by a message already delivered (§3.1's guaranteed Stu handoff), bypasses the cap and the cooldown. It
still *counts*, so an unsolicited introduction cannot pile on top of one in progress. **This was a live defect
until `tools/test-quest-graph.lua` caught it** — see `KB-167`.

**4. A world-initiated beat is pushed exactly once.** Re-entry comes from a player action (§0.2), never from the
clock, so the host records each pushed node and never pushes it again. The alternative — one bookkeeping flag per
offer — is the same omission waiting to recur with every beat Pass 2 adds. Also `KB-167`.

**5. The vocabulary rule holds, and its one exception is written down.** `L176` kept `forbiddenAny`, and the
first thing it caught was a trespass in the owner's own authored copy: §3.3's Stu line says *"instead of waiting
on the **board**"*, and `board` is on Stu's recovered forbidden list because board *state* belongs to Foreman and
Dex. Neither silently editing owner copy nor silently deleting a recovered rule is acceptable. The third option
is a **per-node exemption carrying a mandatory reason** — scoped to one node, greppable, and refused by
`validate` if the reason is blank. That line points *away* from the board to contrast it with a race the player
builds; it does not read board state.

### Messages

The surface it replaced was one reverse-ordered pile of notices with no notion of who was talking, which stops
working the moment characters exist — a Dex thread and a seat offer were the same kind of object. Now: a rail of
conversations, the player's own lines right and the contact's left, oldest at the top, scrolled to the bottom on
open, and replies as a composer at the foot of the pane. §2.4's context shelf renders **above** the generic
categories, as questions about people rather than as objectives.

**The leak discipline is asserted, not promised.** §3.4's hardware-curiosity score lives in its own table away
from every player-facing payload and is stripped from projected replies; `openCount` never leaves the server. The
render harness and the host harness both walk the whole payload and fail on anything progress-shaped — a count,
a fraction, a percentage, a score (`L171`, `L175`). Unread counts stay, because that is a fact about an inbox.

**F9 is released.** `KB-62` records that three of NCM's four function keys collide with something and that the
collisions keep moving; a surface that can live in the shell should not spend one. Messages had F9, and F7 before
it, which collided with the camera toggle in owner QA. Nothing claims the key now. Four stale *"press F9"* lines
in `ncm_world/server/main.lua` were pointing at the questionnaire, which never had that key at all; they now say
what is true.

**Operational state: DEPLOYED ONLINE 2026-09-28 03:05 UTC.** Offline gate green — 713 core tests, 95
quest-graph host assertions, 201 panel render assertions, docs authority clean. **Migration 039 applied and
verified** on the canonical database (`§BQ1`, `§BQ2` PASS): `from_kind` carries all ten values, `thread_id` and
the three new tables exist, `schema entries 39`, `quest graph ready: 3 authored contact(s), 8 push(es)`, both
resources `started generation=1` with no script error.

**The deploy immediately paid for itself by exposing `KB-168`,** which the offline gate could not see: a nil SQL
parameter is a *hole* to OPEN//77's bridge, not NULL, so four of this feature's statements were refused outright
and nothing persisted across a restart. Two older instances surfaced in the same log — `player_message_exposure`
had been failing since migration 036, and the `ledger` payout line had been raising an **uncaught** error that
aborted settlement transactions, so placement money and bounties were never paid. All three are fixed and
redeployed. The harness that missed mine now models the bridge.

**No player-facing PASS exists yet** (`L69`): every step of `wp/MASTER_TEST.md` **§BQ** from `§BQ3` down is owed,
and `§BQ32` is the `KB-168` regression check.

**Basis.** Owner instruction, 2026-09-28, authorising Appendix A.8 of `41_QUEST_GRAPH_PASS1.md` and specifying
the Messages surface. Depends on `L175` (leads) and `L176` (the voice model). Constrained by `L171` (Dex recites
no market count) and `L172` (Rico never prices a human). Scopes `IDEA-599`, `IDEA-600`, `IDEA-613`, `IDEA-614`,
`IDEA-625`, `IDEA-649`–`IDEA-654`; records `KB-167`.

---

## L184 — LOCKED / EXECUTED IN CODE / LIVE-GATED — other drivers appear on the map and minimap, the city tier only

**Decision (owner, 2026-09-27).** Build player presence on the player's own map and minimap as the **city tier
only**: slow positional pins for every driver in the viewer's routing bucket, a player toggle, and the layer
stood down while the viewer is in a live session.

**The field tier is refused, and the refusal is the decision.** Pins attached to a streamed rival's body
(`Open77.blips.attachToEntity`) were the other buildable half and the better-looking one — smooth, free of
update cost, correct at any speed. They also hand a driver a rival's exact position through a building, which
no mirror gives them. A refusal that exists only as a missing feature gets built by accident later, so it is
written here instead.

**What the platform actually provides**, checked against the build-pinned API index before anything was
written (`open77_namespace Open77.blips` / `Open77.players`, `open77_guide blips`, `open77_api
GetPlayersPositions`):

- `Open77.players.positions()` answers `{ [playerId] = { x, y, z, bucket } }` for every player with a snapshot
  **younger than two seconds**, with no permission checked in its handler. It is the only source that knows
  about a driver five kilometres away, which is why this tier is server-driven at all.
- `Open77.blips` draws to HUD, minimap and world map **together**. There is no per-surface visibility: `range`
  gates all three and `shortRange` is refused by name. "Everyone on the map, only rivals on the minimap" was
  never available and must not be promised.
- `ui.vanilla.map` was already declared for `/ncm.gps`, so **no new permission and no new WebUI surface**.
  Blips are a quota of 128 per resource, which `client/landmarks.lua` already spends per waypointable node, so
  pins are moved and never recreated.
- `CPO_RemotePlayerVariant` (`remote_player`) is the obvious sprite and comes from a **dormant multiplayer
  HUD** the guide says must be checked visually. The default is therefore `vehicle`, with `/ncm.playersprite`
  to look at the other one on a live client. `setColor` is unreleased at the index pin (op77.78) while Online
  runs op77.102, so no colour distinction is depended on.

**Cadence needed a ruling of its own.** The data is already up to 2 s old, so the tick is not a responsiveness
dial: five seconds by default, tunable. `KB-165` applies directly — a per-tick rule is a permanent rule, and
1 Hz would be 3600 sends per client per hour to answer a question that does not change in five seconds.

**Operational state:** built and offline-green — 19 new `test_presence` assertions, whole gate green, `luac -p`
clean over the resources. **Nothing is deployed and no live PASS exists** (`L69`): `wp/MASTER_TEST.md` **§BR**
is owed. No migration, no schema change, no new dependency.

**Basis.** Owner question and same-day ruling, 2026-09-27. Scopes `IDEA-650`–`IDEA-654`, opens `IDEA-660`,
records `KB-168`. Constrained by `IDEA-595` (bounded payloads) and `KB-165` (cadence). It reads the same bucket
convention as `L177` and changes nothing about it.

## L185 - LOCKED OWNER DIRECTION - rig integration becomes a dedicated mod; Carrier is not reopened

**Decision.** The abandoned wheel, pedals, button-rim and force-feedback subgoal will not be resumed inside
`ncm_carrier`. It becomes a separate **NCM Rig Bridge** RED4ext mod, and implementation waits for the bounded
device-access proof in `43_RIG_BRIDGE_ASSESSMENT.md`.

This narrows `L146` without undoing the part that worked. Carrier remains the machine-effects mod: server bridge,
record projection, per-Machine physics binding, handling, gearing and restoration. Rig Bridge owns the local
hardware product end to end: discovery, mapping, calibration, direct vehicle command, buttons, native force
output, safety, configuration and diagnostics. Carrier is not modified as a prerequisite and its inert input/FFB
scaffold is not silently treated as an implementation.

**The server is control plane, never input transport.** Steering, throttle, brake and FFB remain local and
high-rate. OPEN//77/WebUI may carry health, settings, race context and capabilities. The existing companion/FFB
hidden surface can be reused while Carrier keeps its existing machine surface; distinct port ranges and protocol
identities prevent bind order from deciding which peer is which (`KB-147`-`KB-149`, `IDEA-647`).

**The first authorised scope is research/prototype P0 only, not a product build:** while Cyberpunk is running,
prove that an in-process provider can read the owner's G29, Thrustmaster pedals and ESP32 rim concurrently.
Start from the source-verified DirectInput and Windows.Gaming.Input precedents; test the Logitech SDK adapter for
the G29; retain `WM_INPUT` Raw Input as an additional provider if an exact endpoint needs it. None is assumed to
solve every force-output backend, for which DirectInput exclusivity or a vendor SDK may be needed.
If neither first provider passes, that P0 iteration stops and records the exact boundary. Per `L186`, that result
falsifies only those implementations; it does not establish that an out-of-process hardware service is necessary.

**Nothing is built, packaged, deployed or live-passed by this ruling.** The external companion remains the only
proved rig path until the ordered P0-P5 contract has live evidence. A new required executable package is a later
promotion decision, not implied here.

**Basis.** Owner direction, 2026-09-27: prefer a new dedicated rig bridge rather than modifying Carrier, after
understanding what failed. Source trace recorded as `KB-169`; scope `IDEA-661`-`IDEA-664`; assessment document 43.

## L186 - LOCKED EVIDENCE RULE - a failed rig prototype does not refute in-process integration

**Decision.** Negative rig evidence is scoped to the exact implementation tested: API/backend, access mode,
device set, initialization point, window/thread context and build. If a provider prototype fails,
the conclusion is that the prototype failed under those conditions. It is not evidence that a fully in-process
Rig Bridge is impossible, nor that an external process is technically required.

P0 is therefore a provider experiment, not a binary referendum on the architecture. A negative result must retain
the error and lifecycle evidence, investigate the actual boundary, and select the next smallest discriminating
experiment. An architecture fallback may be chosen later for measured cost or reliability, but not smuggled in as
an impossibility claim. The external companion remains the currently proved fallback only.

This corrects one inference in `L185` and document 43; it does not change the locked product boundary. Carrier
stays closed and the proposed Rig Bridge stays separate.

**Basis.** Owner correction, 2026-09-27. The first assessment repeated the earlier HTTP/HTTPS category error:
our implementation failure was presented as a failure of the idea. Recorded as `KB-170`; scopes `IDEA-665`.

## L187 - LOCKED - Safety Rating is kept and rebalanced; car contact is the signal, scenery is discounted

**Decision.** The Safety Rating badge is **not removed**. It is rebalanced so that clean racing is worth
something, a single incident is a cost rather than a catastrophe, and no one session can crater the badge.

Removal was the owner's stated alternative and it was rejected on cost, not on preference: SR is load-bearing in
four locked decisions. `L54` makes it the **only** dimension that may ever gate entry; `L44` defines NCX
eligibility as licence + SR floor + invitation; `L38` splits an oversized field by rating/SR; and `P39` hands
griefing to the SR badge and eligibility floors precisely so that incident scoring can stay zero-fault and
blame-free. Deleting SR would reopen all four. The defect was never the existence of the badge, it was its
arithmetic (`KB-171`).

**Four rules now govern SR movement.**

1. **Exposure earns the badge.** A clean session pays `cleanGain` 0.05 plus `perKmGain` 0.03 per kilometre
   actually raced, capped at `maxGain` 0.30. Distance is the session's built course length with laps included,
   falling back to the event route; a host that reports no distance still pays the base credit. Turning up is
   worth little, driving a long race clean is worth a lot.
2. **SR measures who is safe to race ALONGSIDE.** Car-to-car contact costs `perBand` 0.06 per severity band.
   Scenery and self-inflicted contact cost `objectFactor` 0.35 of that, and the first band of it per session is
   free -- it spends the clean credit but moves nothing. Wall damage is car control and belongs on the
   Fingerprint (`IDEA-069`/`IDEA-070`), not on a rating about racing near people. This settles `IDEA-090`.
3. **No craters.** One session may cost at most `maxLoss` 0.50, however many incidents it contained. The
   observed -0.80 and -0.90 races become -0.147 each under the new weighting, recovered by one clean 6 km race.
4. **Unknown contact is never cheap.** A host that supplies an incident *count* with no records is charged as
   car contact. A gap in the detector must not read as good behaviour -- which is the shape of `KB-34`.

**What this does not change.** Incident detection, bands, escalation, dedupe and the *corrected time* are
untouched; `L56` still expresses incidents twice and the seconds added to a result are unaffected. The severity
index SR reads stays linear in the band (1/2/3) while incident seconds keep the `1x/2x/4x` multiplier -- two
curves for one event, left as it was rather than changed silently. Nothing gates entry in the first world
(`L54`). Lifetime `distanceM` is still unwritten in `driver_sr`; the gain needs only the session's distance, so
no schema migration was taken.

**Alpha SR rows are not migrated.** Under `L75` the numbers already written carry no obligation, and every
driver's SR simply moves under the new rules from wherever it now sits.

**Basis.** Owner, 2026-09-27: *"safety rating in ncm online is a sham right now, no upside. a race or time trial
with no incidents gets you maybe a fraction of the gains as one incident. multiple incidents leaves a crater.
remove it or balance it"* -- the diagnosis was arithmetically exact. `P39` already anticipated tuning thresholds
in rehearsal (E8), and `IDEA-093` had already judged this a core edit with a fixture rather than a brick.
Recorded as `KB-171`; residual tuning questions as `IDEA-666`. **Not done until `MASTER_TEST` §BS passes live
(`L69`).**

## L188 - LOCKED OWNER REQUIREMENT - Rig Bridge is multi-vendor and multi-device by construction

**Decision.** The dedicated NCM Rig Bridge may not be a Logitech-only product with other brands deferred behind
its core assumptions. Its normalized input model, saved profiles, diagnostics and game injection are hardware
neutral. A rig may compose steering, pedals, clutch, shifter, handbrake and actions from any number of physical
devices, and each role/control binds independently to a stable device identity plus an axis/button/switch.

The provider boundary is explicit. Windows.Gaming.Input `RawGameController` and generic DirectInput are the first
input providers because working MIT Cyberpunk mods prove both in-process patterns. `WM_INPUT` Raw Input remains
available for an endpoint those providers cannot read. Logitech and any later Thrustmaster/Fanatec/Moza SDKs are
optional capability adapters, never the definition of a supported input device. Force output is bound separately:
a wheel can have generic input without an FFB backend, and lacking FFB must not disable its steering.

The first exact-rig proof is the owner's split rig: G29 steering/output, separate Thrustmaster pedals and ESP32
rim buttons, all sampled concurrently inside the Cyberpunk process. It must preserve stable assignments across
restart and hotplug. Product-name substrings and enumeration indices seen in the reference mods are useful demos,
not sufficient identity for NCM.

**Source basis.** Source trace, 2026-09-27: clevergrant's `cp2077-wheel-mod` supplies the working SDK/pump/detour
pattern; natpoh's `cp2077-wheel-mod-moza` supplies DirectInput enumeration, independent wheel/pedal handles and
DirectInput FFB; jackhumbert's `custom_game_controller` supplies multiple arbitrary Windows.Gaming.Input devices
and shipped Fanatec/Thrustmaster mappings. All three repositories are MIT; reused code still requires preserved
notices and vendor SDK redistribution remains a separate check. Owner requirement: more than Logitech wheels.
Scopes `IDEA-667`; amends the research basis of document 43 without authorising implementation.

## L189 - LOCKED - a server-to-client payload carrying a list goes over `NcmStream`, never a state bag

**Decision.** `ncm_league/server/stream.lua` is the transport for any payload that carries a list, and the
player state bag is not an alternative to it. A state bag may hold a small, **bounded, measured** value; the
moment a payload contains a list whose length is data rather than a constant, it is a stream. The receiving
half is `ncm_world/client/stream_rx.lua` (`NcmStreamRx`), which is shared rather than per-surface.

**Why now.** `KB-172`: Street Call published its form as an 11,515-byte player bag against a 4,032-byte ceiling
(`IDEA-509`). It never worked once, on any press, for any player, and it shipped and deployed that way because
nothing in the offline gate can see a size ceiling and nothing at runtime said a word. This is the **fifth**
instance of the same bug -- `KB-59`, `KB-86`, `KB-153`, `KB-160` -- and the first that a player met. The
transport to prevent it already existed, was already written up in its own header as a structural rule rather
than a per-payload fix, and a new feature simply did not use it. A rule that only applies to the payloads that
already broke is not a rule.

**What this obliges.**
- A publisher measures. `NcmStream.send` returns the encoded size, the head size and the packet count, and the
  caller logs them. An unmeasured payload is an unexploded one.
- **A head is bounded by construction, or it is not a head.** `NcmStream` cannot split a head. `KB-86` is the
  instance where twenty rows of history sat in one, and `stream.lua`'s header already warns about it.
- **Never discard a write's return value.** `KB-172` was silent because the `:set` call sat inside a `pcall`
  that threw away the result, so a refusal that reports rather than raises read exactly like success. Compare
  `ncm_world/server/handling.lua:68`, which returns the status.
- **Say when nothing arrived.** Both sides of `KB-172` logged something reasonable and neither logged the
  fault. A client that waits for a payload names the two possibilities when it times out.

**What this does not say.** It does not ban the state bag. `ncmEntry`, `ncmVenue`, `ncmHandling` and the
onboarding flags are small fixed-shape values and stay where they are. It also does not make a stream free: it
is a net event per packet, so a payload that could simply be *smaller* should be smaller first. Street Call was
both -- it sent the same 35-node list twice, and `competition.race_builder` now puts it on the wire once and
rebuilds the page's `start`/`finish` lists on the client (`M.wire` / `M.schemaFromWire`).

> **CORRECTION, 2026-09-28 (`L193`, `KB-178`). The last sentence above described the defect, not the fix.**
> Rebuilding `start`/`finish` on the client restored the full 11,515 bytes **immediately before the
> client-to-page hop**, and that hop drops large messages silently (`KB-63`). So this decision fixed the
> server-to-client half and left the other half broken, and the form still never drew once. **This decision is
> otherwise sound and stands** -- the stream is the right transport and `KB-172` is genuinely closed. What it
> got wrong was scope: it counted one hop where there are two. `L193` extends the rule to the second hop and
> is where the Street Call form's transport now lives. `M.schemaFromWire` remains core's tested inverse of
> `M.wire`; nothing on the client path calls it any more.

**Consequence accepted.** `client/panel.lua` keeps its own private copy of the receiver for now (`IDEA-668`);
it is the busiest surface in NCM and carries live PASSes, so converging it is its own change. Until then the
rule is upheld by two receivers, which is the part of this decision with a shelf life.

**Live proof owed:** `§BN1`-`§BN4`. Nothing here is PASSED until the card opens on a real client.

## L190 - LOCKED - Messages is a messenger: a notice is a thread, and an incoming line arrives

**Decision.** The Messages surface has exactly one place where messages are read: a thread. There is no second
pane of recent messages, no tray, and no list of notices beside the conversation. Two rules follow, and they are
rules rather than styling:

- **A notice is mail from a sender.** A seat offer belongs to the team that sent it, in that team's thread, with
  its subject line intact and its `accept` / `decline` in the composer where every other answer lives. It appears
  in the rail with an unread badge and it does **not** take the pane the player is reading.
- **An incoming line arrives.** A line appended to a transcript that is already on screen is revealed on its own,
  behind a typing indicator, and the composer stays empty until the contact has finished. Opening a thread,
  switching threads or reopening the panel draws history **at once** -- pacing scrollback would be a claim that
  old lines are being said now.

Time is part of the surface: a stamp where the clock jumped more than fifteen minutes, a clock on the newest
bubble and nowhere else, and a `NEW` rule where unread begins. None of these is countable progress (`L171`,
`L175`); an unread badge counts messages, which is a fact about an inbox.

**Why now.** Two owner complaints, 2026-09-27, about the same panel: the bottom tray was *"terrible and
intrusive, not how a real messaging app works"*, and the messaging was *"instantaneous right now and i cant
always tell what the newest message is"*. The first had a defect underneath it (`KB-173`): the tray was fed by a
query with no thread filter, so it showed the twenty newest rows in `message` regardless of thread -- the open
conversation duplicated below itself, mixed with everybody else's lines. The second was structural: a reply wrote
the player's line and spoke the whole next node in the same frame, so a three-line exchange and its replies all
appeared together and there was nothing to read as a conversation.

**Consequence accepted.** The surface now holds state the server does not know about: which notice thread is
open, and which lines have already been revealed. That is presentation and it is deliberately not persisted --
a panel reopen redraws history at once, which is also the honest thing to do after a reconnect. The pacing is
page-local, so a line is durable the moment the server writes it; nothing about arrival can lose a message.

**What this does not say.** It does not merge the two payloads. `ncm:inbox` and `ncm:graph.threads` stay separate
on the wire, because a notice has a deadline and an answer and a conversation has neither; the page folds them
into one rail. It also does not make every notice a conversation the player can talk into -- an offer is
answered, not discussed.

**Live proof owed:** `§BT`. Nothing here is PASSED until an offer is accepted from a thread on a real client.

## L192 - LOCKED - the Machine channel outranks force feedback for the Carrier's single socket

**Owner report.** *"something broke our top speed ceiling and probably physics application on cars, maimai back
to stock 103kph"*, with the note that it had been working until the last two or three deploys.

**The constraint.** The Carrier's bridge is a serial accept loop. `serveWebSocket` in `bridge/server.cpp` blocks
until that one socket closes, so **a Carrier port is a lock, not a channel**, and exactly one of the client's two
hidden surfaces can ever hold it. Something has to yield. The only question is which.

**The ruling.** The **Machine channel yields to nothing.** Parts, gearing, the governor and every projection are
the product; force feedback is a peripheral preference that needs a process NCM does not ship. The machine walk
therefore sweeps `38480-38483` with no skip and no exception, and the FFB walk is the one that steps aside --
searching the Rig Bridge's own `38520-38523` first and entering the legacy companion range only after the Carrier
has been located, then skipping the port it is on.

**What this reverses.** The previous rule pointed the same skip the other way, to stop the machine surface
displacing a wheel companion mid-corner. That protected the optional half of the product at the cost of all of
it, and it hid the cost for weeks: the companion happened to hold `38480`, so the Carrier fell to `38481` where
the machine walk could still reach it. **The feature was never robust, only lucky.** `KB-177` has the evidence --
same plugin build, Carrier on 38481 applies 42 gear chains, Carrier on 38480 applies zero.

**The generalisation, and it is the part worth keeping.** A scan that declines a port emits no fault, because
declining is its normal behaviour. Two channels contending for one lock must therefore have a **written
precedence**, and the lower-priority one must be the one that yields -- otherwise the failure is silent,
indistinguishable from an absent peer, and discovered by a driver rather than by a log line.

**Live gate.** `§BV1`. Offline-green is not a pass.


## L191 - EXECUTED IN CODE; LIVE-GATED - Rig Bridge is a full dedicated mod, not a probe and not Carrier

**Owner ruling.** *"nice build it end to end, no probe"*. Build the complete dedicated Rig Bridge product now.
Do not reopen Carrier's abandoned input scaffold. The bridge is multi-vendor and multi-device by construction;
Logitech is one compatible device family, not the architecture.

**Executed boundary.** `ncm/rig_bridge/` is a separate RED4ext DLL and package. It owns a 250 Hz DirectInput
provider, stable instance-GUID bindings, independently assignable steering/throttle/brake/clutch endpoints,
button-to-game actions, hot-plug re-enumeration, exact local-player mount scoping, direct native vehicle-command
injection, DirectInput condition/constant FFB, explicit arming, bounded strength and a telemetry watchdog. It
serves its own loopback/WebUI range (`38520-38523`) and reuses the existing FFB surface. Carrier keeps
`38480-38483` and the Machine surface; no Carrier source or package changed.

**Why DirectInput first.** The positive source precedent is cross-vendor (`cp2077-wheel-mod-moza`), supports a
separate wheel and pedals, and exposes both input and FFB without redistributing a vendor SDK. The product does
not contain a Logitech-only path. Windows.Gaming.Input and Raw Input remain additional providers if a measured
endpoint cannot expose what it needs through DirectInput; they are not prerequisites invented in advance.

**Done still means live PASS.** The DLL builds warning-free, exports the three RED4ext entry points, depends only
on Windows system DLLs, packages with config/redscript/notices, and its pure mapping test passes. That is offline
evidence, not wheel support. `MASTER_TEST §BU` must still prove enumeration of the owner's exact G29 + separate
Thrustmaster pedals + ESP32 rim, exact-car control, reconnect, panel control, FFB arm/watchdog and coexistence
with Carrier. The external companion is not retired before those live input and output halves pass.

**Amendment, 2026-09-28 — verification pass. "Bounded strength" is now true in code, and one advertised
channel is scenery.** Independently rebuilding and re-gating the L191 work confirmed the offline evidence above:
the Release build is clean, the DLL exports `Query`/`Supports`/`Main`, its imports are Windows system DLLs only
(`DINPUT8`, `IPHLPAPI`, `KERNEL32`, `USER32`, `WS2_32`, `ole32` — no vendor SDK, no redistributable), the mapping
test passes, and the package assembles. Two corrections follow, and neither changes the boundary this entry sets.

**First, the force ceiling was a document and a panel convention, not an enforced invariant** (`KB-174`). The
setter and the config loader clamped to `[0, 1]` and the built-in default was 0.35, above the 0.18 top rung that
`§BU9` says unknown hardware must never exceed. The ceiling now lives in `config.hpp` as `kFfbRungs` /
`kFfbStrengthCeiling`, and the setter, the loader, the panel's rung table and the rung the bridge *reports* all
read it, so the surface can no longer disagree with the device. **The rule this makes explicit: a safety envelope
stated in an acceptance item must be enforced at the narrowest point in code, not assumed from the values the UI
happens to offer.** Nothing was armed, so nothing was at risk — that is luck, not design.

**Second, "DirectInput condition/constant FFB" overstates what is driven** (`KB-175`, `IDEA-673`). The condition
effects (spring, damper) are genuinely fed, from RTTI vehicle speed through the detour. The constant-force effect
is computed from `feedback.collision`, which nothing ever raises above zero, and `feedback.road` is filled from
telemetry and read by nothing. Outside a TEST PULSE the constant force is always 0, while the panel still
advertises road and texture tune values. The claim for this build is therefore **speed-scaled centring and
damping**, which is what `§BU9` already asks for; road and collision feel are unbuilt, and the owner chooses
between feeding them and deleting the plumbing.

**The gate was red when this entry was written** (`KB-176`). `tools/ncm-test.ps1` failed on two documentation
invariants — document 43's `CURRENT` banner named no topic, and `BACKLOG.md`'s next-free-ID line had already
been consumed. Both are fixed and `ncm-test` is green. A build is not offline-green while the gate that asserts
it is failing, however narrow the failure; the reported state and the gate's verdict have to be the same fact.

## L193 - LOCKED - a payload crossing the client-to-WebUI bridge is bounded BY CONSTRUCTION, not by batching

**Decision.** `L189` bounded the server-to-client hop. There are **two** hops, and this is the other one. A
value handed to a WebUI page with `page:send` must be bounded by what it *contains*, not rescued after the fact
by splitting it: the page receives **what is on screen**, and the catalogue it is chosen from stays in Lua.

Concretely, for the Street Call form: `client/race_builder.lua` holds the node list, the form, the cursor and
the picker. `web/venue.html` receives at most fourteen form rows or a nine-row picker window, as display
strings. No message's size depends on how many nodes exist, so there is no size at which the feature can
silently stop drawing.

**Why now.** `KB-178`. The form had never rendered, on any press, for any player. `L189`'s fix was real but
half-scoped: the client received the streamed node list correctly and then called `Builder.schemaFromWire`,
which re-expands it into **both** `start` (HERE + 35 rows) and `finish` (35 rows) — restoring the full 11,515
bytes — and handed that to the page in one `page:send`. `KB-63` says exactly what happens next: no error, no
return value, no log line, and the page never receives it. The card then failed its own 2500 ms draw watchdog
and closed. The schema was reassembled at the last possible moment before the one hop that could not carry it.

**The owner is the reason this was found, and the previous account was wrong twice.** It claimed the form had
never rendered *because* of payload size and that the earlier six-page version had never worked either. The
owner said the six-page version rendered. It did — each of its steps sent at most five options, a few hundred
bytes, comfortably under the threshold. **The page count was never the fault**, and a per-payload size story
that contradicts an observation is a story, not a diagnosis. `L181`'s one-form shape is kept in full.

**What this obliges.**
- **Batching is the fallback, not the rule.** `client/panel.lua::sendBig` is correct and stays — it serves
  screens that genuinely must show a long list. But where a surface can be handed only the visible window, it
  is, because a split payload still grows and a windowed one cannot.
- **A page that shows a long list receives a window and a position, never the list.** "17 of 35" is a string.
- **Geometry stays server- or Lua-side.** The node coordinates existed in the payload only so the page could
  preview a route length. Lua computes the readout and sends the sentence, so coordinates never cross at all.
- **Every page gets a guard and a harness.** `venue.html` had neither while carrying three tenants, which is
  why this was invisible. `tools/venue-render-check.js` is in the gate: 53 assertions, and it asserts the
  page holds no schema and computes no distances, so the payload cannot grow back.

**What this cost, and what it bought.** The form is no longer driven by dropdowns and a mouse, because
`venue.html` is `pointer-events: none` and is never focused — which is exactly what makes it safe to leave
attached during a race (`KB-67`). Input is read in Lua with `Open77.input.isDown` (arrow keys, Enter,
Backspace, Delete, PageUp/PageDown, and the pad), which are **physical reads that need no focus**. The
keyboard vocabulary was read out of the deployed `Open77.dll` rather than guessed, per the presentation
audit's own advice; ESC is deliberately not a close key, because it opens the pause menu.

What that bought is worth more than the dropdowns: **`KB-61` cannot happen here at all.** There is no focus to
hold, so there is nothing to soft-lock. That is a stronger guarantee than the confirm-then-focus handshake it
replaces, and the `build:drawn` reply is kept only as a render confirmation.

**And it gave back a WebUI surface.** `kMaximumWebSurfaces` is 8 per resource; `ncm_world` was at **8 of 8**
with `web/build.html` (`IDEA-570`), while `carrier_bridge.lua` and `race.lua`'s bridge probe create pages
transiently — so `WebUI.create` for the form could be refused outright depending on timing, a second and
independent failure mode. The form is now a block on `venue.html`, shared through `NcmVenueSurface`, and
`web/build.html` is deleted. Back to **7 of 8**. Owner direction, 2026-09-28: *"use venue.html i dont care just
make it work without adding a second page."*

**Live proof owed:** `§BN1`, `§BN33`-`§BN41`. Offline-green is not rendered; nothing here is PASSED until an owner presses
F5 on a real client and the card draws.

## L194 - LOCKED / EXECUTED IN CODE / LIVE-GATED - Player Exchange is a first-class F6 system, not a backend slice

**Owner direction.** *"Implement today"* and *"the exchange panel [must be] built in F6 — don't hack around
this with a narrow vertical slice."* `IDEA-247` therefore ships as one coherent synchronous product: invitation,
exact offer construction, bilateral consent, settlement, receipts, refusal paths and a first-class **EXCHANGE**
tab in the existing F6 shell. Commands are recovery twins; they are not the primary product.

**The offer is genuinely heterogeneous.** Either Driver may contribute exact owned Machines and exact stored
Parts; one side may additionally contribute whole-eddie cash. Both sides must contribute value, money-for-money
and gifts are refused, and NCM never judges whether the bargain is fair. A selected Machine includes every exact
component asset fitted to it at confirmation time. That installed set is visible to both Drivers and moves with
the Machine; a seller who wants to keep a component refits or removes it before offering the Machine.

**Consent binds to facts, not a button press.** Each edit creates a new monotonically increasing revision and
clears both confirmations. Confirmation covers sorted Machine ids, component ids, their custody and containing
Machine, cash, parties and revision. Before either confirmation and again before commit, the host rechecks title,
stored/installed custody, funds, race commitment and whether a Machine is materially present in the world. A
 called Machine must be stored; a checked-in/racing Machine cannot move. Selecting a stored Machine reserves it
 against a concurrent CALL until it leaves the offer or the Exchange closes.

**One accepted revision is one transaction.** Migration 040 adds the durable `trade_envelope`, exact asset and
money legs, provenance links from both transfer histories and a balance-lock row. The transaction serializes all
NCM debits for both Drivers, inserts the accepted envelope only while every SQL precondition is true, transfers
title and component custody, appends ordinary transfer histories, writes one paired `player_trade` debit/credit,
and marks the envelope settled. There is no partial success and no mint. Existing Market, Part-market and entry
debits now take the same balance lock, closing the concurrent double-spend window rather than making Exchange
atomic only in isolation. Machine identity, ordinals, distance, wear and service history stay on the same assets.

**Boundary.** This first system is direct and synchronous: both Drivers are online, drafts live in memory, and a
decline, disconnect, expiry or resource restart releases them without moving anything. The accepted settlement
is durable and replay-safe. Persistent listings are later because an offline offer requires escrow and expiry
recovery; that is a second product, not missing UI in this one. Private Exchange reveals acquired Machine identity
to its new owner but never grants Market access or publishes either Driver's private knowledge.

**Live proof owed:** `MASTER_TEST §BW`. Offline proof covers 747 core tests under Lua 5.4/LuaJIT, a deterministic
18-assertion host lifecycle/transaction harness, the real F6 panel render harness and syntax over the resource
tree. No Exchange is DONE until two real clients pass the exact-asset, refusal, retry and restart rows in §BW.

## L195 - EXECUTED IN CODE / LIVE-GATED - the NCM quick menu is a NATIVE radial, drawn by its own required mod

**Owner direction (2026-09-28).** Keep every hotkey, and put F6 (now named **Hub**), F5 (call a race), `/ncm.gps`,
the map and the other player-facing hotkeys on one radial wheel. Hold **Start** on a controller (Start is free in
OPEN//77; Back opens the pause menu), or a dedicated non-F key on keyboard; both mappable. Leave slots open for
features still coming. **Not WebUI** ("dig harder at a real radial"), and **do not appropriate Carrier or Rig
Bridge; make a new one if needed.** No key audit: the owner picks the keys.

**What was found before building.** `open77_uikit` (the platform's radial) is still absent from op77.102 on both the
dev box and staging, so it was not an option. `open77_contextmenu` is a hold-ALT entity picker, not a radial. The
`radial*` strings in `Open77.dll` are a list of vanilla UI states, not a scripting API. The vanilla
`RadialWheelController` is a full-screen, centred HUD module that exists on foot and in vehicles and already owns
blur and sounds. OPEN//77 claims the weapon wheel, so that host otherwise sits idle for the whole session.
`r6/scripts` is a permitted required-mod root (`Open77.Server.Core.dll`), and Rig Bridge already ships redscript
that way.

**Shape: three owners, one job each.**
- `ncm_radial` (new resource, client only) **decides everything**: it reads Start/keyboard holds physically
  (`isDown(keyFor(...))`, the idiom the platform's own hold-to-open context menu uses), aims from either stick,
  WASD/arrows or an accumulated mouse flick, highlights one of eight FIXED slots, and on release asks `ncm_world`
  to run it. It is a separate resource only because its hidden loopback transport needs a WebUI surface and
  `ncm_world` is at 8 of 8 (`IDEA-570`). That surface is transport and is never visible.
- `ncm_radial.dll` + `ncm_radial.reds` (new required mod `ncm-radial`, `ncm/radial/`) **only draw**: the DLL serves
  the transport page on 127.0.0.1:38560-38563 (its own range) and exposes two string natives, and the script draws
  the wheel inside `RadialWheelController`, hiding the vanilla children while NCM's wheel is up and restoring
  exactly the ones it hid. It shares no code, state, port or package with Carrier or Rig Bridge.
- `ncm_world` **runs** the action through `quickAction`, over the very function each hotkey calls
  (`NcmQuickActions`), plus `Open77.map.open()` for Map, so the wheel can never do what the hotkey would not.

**Slots (clockwise from top):** Hub (F6), Race graph (F8), Call a race (F5), *open*, Map (M), *open*, GPS
(`/ncm.gps`), *open*. Machine Index, Help and Status are deliberately not on the wheel (owner). Defaults: keyboard
**B**, controller **Start**, both `RegisterKeyMapping`s so both appear in the pause menu's key-bindings tab.
`/ncm.radial pad <control>` is the fallback if the platform refuses a pad control as a mapping default.

**Safety rules, by construction.** A dropped socket closes the wheel; no frame for 1.5 s closes the wheel; only
this game's process tree may connect; a focused surface (the F6 hub) closes the wheel and runs nothing; on-foot
Movement and Attack are blocked while it is up and released on close. Driving is not blocked, on purpose.

**Offline proof:** the DLL builds clean at /W4; the state tests pass (wire format, separator injection, selection
bounds, drop-close, stale-close, garbage refusal); the redscript compiles against the vanilla bundle AND the
installed OPEN//77 scripts in a scratch cache (`tools/build-radial.ps1` refuses to package otherwise); `ncm-test`
is green. **Unverified, owed live:** that the host constructs in an OPEN//77 session, that `DelayCallbackNextFrame`
ticks it, the ink layout at real resolution, whether `mouseDeltaX/Y` are per-frame or cumulative, what
`setActionBlocked` accepts, and whether a pad control is accepted as a mapping default.
**Live proof owed:** `MASTER_TEST §BX`.

## L196 - EXECUTED IN CODE / LIVE-GATED - the Scanner's look is the REAL vanilla render, shipped by its own redscript-only required mod

**Owner direction (2026-09-28).** The green filter and reticle of the vanilla scanner, *"without time dilation
slowing down"*, for Machine discovery. Offered a WebUI imitation (tier 1) and the real render (tier 2): *"tier 1
sucks, tier 2 please."* Then: *"do not modify an existing mod, create a new one, disrupting performance of carrier
or rig bridge is a nonstarter."*

**What was found (evidence: `docs/research/open77/evidence/2026-09-28/scanner-vision-look.md`).** OPEN//77 refuses
`PlayerVisionModeController` for the whole session, and no claim can release it. It refuses the focus-mode time
dilation *separately*. Vanilla activation is three independent calls, and only one of them is the green render:
`VisionModeSystem.EnterMode(player, gameVisionModeType.Focus)`. The platform does not intercept that system. The
controller deactivates only when its own `m_active` flips, and under OPEN//77 it never activates, so it cannot cancel
a render we start. `VisionHold` (Tab) and `VisionToggle` (Caps Lock) are in both the on-foot and driving input
contexts.

**Shape.** A new required mod `ncm-vision` (`ncm/vision/`, `dist/ncm-vision-0.1.0.zip`): **one redscript file and
no DLL.** A `ScriptableSystem` registers two input listeners on the local player at attach. Hold Tab for green
while held, tap Caps Lock to toggle. It makes the render call alone. There is no scanning controller, so no scan
HUD, and no `FocusModeLocomotion`, so no walk-only restriction. It shares no code, state, port or package with the
Carrier, the Rig Bridge or the radial. It has no per-frame work and never consumes the key.

**Rules kept by construction.** Vanilla symbols only, so an OPEN//77 or NCM rename can never break the compile. A
redscript compile error disables every script mod a player has, which is why `tools/build-vision.ps1` refuses to
package unless the file compiles against the vanilla bundle plus every installed script in a scratch cache. A
release of the hold also clears the toggle, so one press and release recovers from a key-up lost to alt-tab.
Detach and re-attach return the render to Default before unregistering.

**Not decided here, deliberately.** (a) Whether the filter is refused while a player is entered in a live session.
Redscript cannot see NCM's race state without either an OPEN//77 symbol (compile risk) or a transport. Record
§BY's visibility finding first. (b) NCM's own tint: Preem Scanner shows the LUT, vignette and scanlines are inert
depot content, so a restyle can ship later as an `.archive` without touching this script. (c) The *knowledge*
half: aiming at a Machine and writing `identity_reveal` stays with `IDEA-624` and the server.

**Offline proof:** the script compiles alone against vanilla and together with OPEN//77, rig bridge and radial
scripts. The package holds exactly `r6/scripts/ncm_vision/NcmVision.reds` + `README.md`. **Unverified, owed live:**
that the render appears in an OPEN//77 session, time scale stays 1.0, movement stays free, it works while driving,
nothing else resets it to Default, and what vanilla highlight noise comes with it.
**Live proof owed:** `MASTER_TEST §BY`.

## L197 - LOCKED / EXECUTED IN CODE / LIVE-GATED - a new Machine enters the Index through the SCANNER, not through proximity

**Owner decision (2026-09-28).** *"since we added ai traffic ... we are going to be in proximity of discoverable
cars constantly and machine index will fill rather quickly ... my decision is to gate discovery of new cars to
machine index behind using the scanner, not simply proximity. we need the reticle for discovery purposes. also,
the scanner is where chrome hacks will be available to use against other drivers."* Rulings on the four open
points, same day: the reticle and transport grow the existing `ncm-vision` package; **vanilla per-client traffic
is discoverable as `client_attested`**; proximity becomes **sighting-only**; a scan is **a ~1.5 s hold within ~60 m**.

**What the code established first.** NCM's ambient traffic (`L177`) is not vanilla traffic. It is server-owned
network vehicles (`Open77.vehicles.create` + an NPC driver on `joinTraffic`). It had never triggered discovery only
because nothing registered it with the collection. Those cars are therefore server-verifiable scan targets.
Vanilla per-client cars cannot be seen by the server at all, and `aimedEntity()` does not give their record.
Redscript can (`VehicleObject.GetRecordID()`).

**Shape: three owners, one job each (the `L195` pattern).**
- **`ncm-vision` 0.2.0** (required mod, `ncm/vision/`) **sees and draws.** The green render (`L196`), unchanged. A
  20 Hz look-at report that runs only while vision is on: the engine's look-at target, falling back to the object
  nearest the crosshair within 6°, never the player's own car. It carries the EntityID hash, the record **key**,
  the kind and the distance. A native reticle is drawn in the vanilla crosshair container, which is full-screen,
  present on foot and in vehicles, and not managed by OPEN//77. `ncm_vision.dll` is a loopback transport on
  **38600-38603**, its own range. It answers every Lua message with the latest report, so the socket has a single
  writer. It shares no code, state, port or package with the Carrier, the Rig Bridge or the Radial.
- **`ncm_scanner`** (new client resource, separate because `ncm_world` is at 8 of 8 surfaces) **decides the lock.**
  It uses `competition.scanner.step`, the same function the core tests cover. It names a target as `networked`
  (by `vehicleId`, when `aimedEntity` agrees with redscript by entity or within 3 m) or as `vanilla` (by record
  key). It asks the server, and it tells the reticle what to say.
- **`ncm_league/server/collection.lua`** **decides knowledge.** `ncm:scanner.query` answers only "indexable?" and
  "known?", and a name only for a machine already known, so fog of war holds on the wire. `ncm:scanner.scan` is
  the only write, through `revealIdentity(source = "scanner")`. A networked target's record, bucket and distance
  are re-derived from the server's own snapshots; the report is not trusted. A vanilla target's record key is
  mapped back to a catalogue record **server-side** (`competition.scanner.recordIndex`, CRC32 + length, the
  TweakDBID identity layout), so the catalogue never crosses the wire (`L193`) and a client cannot name a record
  the server did not derive. Vanilla reveals are `client_attested`, at most one per 20 s and 30 per hour.

**Consequences, all in code.** `scanner` is a knowledge source, and it may credit a human, as the dwell did.
Proximity (`recordEncounter`) now records an encounter only for a machine the Driver already knows. Ambient cars
register with the collection as `context = "ambient"`, with no source Driver, and unregister when removed or
lost. Market, trade and ownership reveals are unchanged (`28_MACHINE_KNOWLEDGE.md` §3: many sources, no universal
mechanic). What changed is that physical encounter now means a deliberate scan.

**Chrome hacks (`IDEA-076`/`IDEA-077`, now `IDEA-681`).** The Scanner is the targeting surface they will use. The
target model is already the one `Open77.hacking` needs, a network vehicle by id with server revalidation. The
reticle's state vocabulary and the transport are where a hack list will attach. Nothing hack-specific is built.

**Offline proof:** 8 new core tests (lock, range, retarget, admission for both kinds, rate limits, record keys
against the CRC32 check value) pass under Lua 5.4 and LuaJIT. The DLL builds clean at /W4 and its state tests
pass (wire format, clamping, stale and disconnect clearing, key masking). The scripts compile against vanilla
**plus every installed script**; that check caught a real `Uint32`/`Uint64` error a standalone compile missed.
`ncm-test` is green. **Unverified, owed live:** the look-at target from a driver's seat; whether
`aimedEntity.engineEntity` equals the EntityID hash; the reticle's layout at real resolution; whether the
crosshair container stays visible in every vehicle camera.
**Live proof owed:** `MASTER_TEST §BZ`.

## L198 - LOCKED / EXECUTED IN CODE / LIVE-GATED - an unpaid event DECLARES itself; a missing economy anywhere else is a refusal

**Why this needed saying (`KB-186`).** Two earlier decisions were each right, and together they refused every
Street Call. `impromptu.lua` made a player-called race unpaid on purpose by leaving `economy` nil, so there would be
no money printer between two friends (`KB-165`'s cadence logic). Economy v1 then made every check-in validate the
event's economy and refuse when there was none, so a paid series that lost its block could not start racing free.

**Ruling.** "No economy" has exactly two meanings, and the event must say which one applies:
- **Declared unpaid** (`unpaid = true`, or class `impromptu`): check-in at fee 0, no ledger line, and settlement
  returns nothing to pay. `NcmEconomy.isUnpaid(e)` is the one test, and both check-in and settlement read it.
- **Anything else** with no economy is misconfigured, and still refuses with `economy_required`. A missing block
  must never quietly become a free race.

A future unpaid format (e.g. a meet-up or exhibition) sets `unpaid = true`. It does not delete its economy and hope.
Covered by stub scenario `entrybag`, which asserts both halves. Live: `MASTER_TEST §CB5`.

## L199 - LOCKED OWNER DIRECTION / EXECUTED IN CODE / LIVE-GATED - restore FFB in the product; do not ship a logging probe first

**Owner direction (2026-09-28).** *"dont want a probe, want a fix that restores ffb."* The accepted response is
Rig Bridge 0.1.2, not a diagnostics-only DLL. This does not waive live proof: it changes what earns the next drive.
The build must correct known invalid output behavior before asking the owner to spend a session collecting it.

**Correction to the prior record.** `KB-184`'s main inference is withdrawn. In 0.1.1 the panel setters changed live
atomics, while `persist()` serialized a separate startup `Config`; `strength 0.020` / `armed false` in the file did
not establish the force used by the running device. The keyboard slider bug was real and remains fixed, but it is
not the explanation for absent rumble. The owner raised FORCE and still had SPRING/DAMPER without SINE/CONSTANT.

**0.1.2 behavior.** SINE has one fixed 125 Hz carrier; car state changes magnitude, not a playing effect's period.
Magnitude writes are capped at 50 Hz, so a driver that must restart still emits complete cycles. Both dynamic
effects let DirectInput preserve playback or perform its required compatibility restart, retry once after
reacquisition, and update their sent-value cache only after success. The watchdog is checked before effects start,
removing the armed-but-parked 250 Hz start/stop loop. FORCE, device class and tuning update the persisted config.
ARM deliberately remains session-only: every fresh process starts disarmed.

**Evidence boundary.** The DLL builds warning-free; native mapping and feel tests pass; package 0.1.2 exists. No
hardware claim is made until `MASTER_TEST §CC` passes on the G29. The external companion remains the fallback until
SINE and CONSTANT both pass. Tracked by `KB-187` / `IDEA-686`.

## L200 - LOCKED OWNER DIRECTION / EXECUTED IN CODE / LIVE-GATED - Chrome hacks adapt OPEN//77's hacking framework, and affect vehicles only

**Owner direction (2026-09-28).** Implement Chrome now, the whole roster, allowed everywhere, with players and AI
traffic as targets, usable only while scanning (`L197`), Online first, and a full build rather than a probe.
Chrome affects vehicles only. The framework NCM adapts is `Open77.hacking`, as recorded in
`docs/research/open77/CAPABILITY_PALETTE.md` §1-§3 and `IDEA-067`.

**Shape.** One deck definition (`ncm.chrome`) whose grades are the roster, every grade `cosmetic`, `nonlethal`
and `damage = 0`, plus Self-ICE and purge implants, all equipped on join. A driven car goes through
`Open77.hacking.start`, with the platform's range, warning, line-of-sight, ICE and purge, and the native bars are
driven by `present()`. A car nobody human is driving goes through an NCM-timed upload with a lock heartbeat.
On `impact` NCM applies the vehicle consequence:
- LIMITER, LIMP, POWER SURGE and OVERCLOCK go through the `chrome` handling layer and the Carrier governor. Caps
  are fractions of the authored baseline; SURGE and OVERCLOCK raise drive and top speed into the gear headroom.
- ENGINE CUT, TIRE SABOTAGE, BLACKOUT, LIMP health and TOTAL FAILURE use `Open77.vehicles` natives.

A per-bucket PvP scope admits hacks, and a damage arbiter keeps weapon PvP off. Every outcome is written to
`chrome_event` (migration 041), so the skull and fingerprint history (`IDEA-078`) is a query over those rows.
Code: `ncm/core/competition/chrome.lua`, `ncm_world/server/chrome.lua`, `ncm_scanner/client/scanner.lua`.
Offline: core and host harness green under both interpreters. **Live proof owed.**

## L201 - LOCKED (ownership) / PROVISIONAL (DD numbers) / EXECUTED IN CODE / LIVE-PASSED ON THE G29 - the Rig Bridge alone owns wheel force feedback

**Ownership, LOCKED.** Exclusive DirectInput force feedback has exactly one owner per device, and the Carrier and
Rig Bridge were both taking it (`KB-188`). Under `L188` the Rig Bridge is the rig/FFB product and the Carrier is
the machine-effects mod, so **when the Rig Bridge is installed the Carrier never opens haptics** (Carrier 0.1.29).
The Carrier still reads devices. Anything else that takes the wheel (SimHub, a vendor tool, another mod) is
named in the Rig Bridge panel rather than failing silently.

**Output architecture, LOCKED.** Force output is a self-contained module with its own device instance, its own
message-only window and a lifetime independent of input rescans. Effects are created and started once, then only
updated; silence is magnitude zero. Every DirectInput result is visible in the panel's FFB OUTPUT row, because
testers report from the panel, not from a console (`KB-189`).

**Direct-drive limits, PROVISIONAL.** Gear and belt keep their measured fractions. Direct drive is a newton-metre
budget (3 Nm at full FORCE) over rated torque, and an unknown DD base is assumed 32 Nm (`IDEA-687`). Unmeasured:
revisit on the first report from a DD owner.

**Evidence.** Deployed to Online 2026-09-28 21:44 UTC (Carrier 0.1.29, Rig Bridge 0.1.4). Owner, same evening:
*"ffb is back"* (`MASTER_TEST §CD1`). ARM gates TEST PULSE again in 0.1.5 (`KB-190`), built and not deployed. The
engine frequency conflict is settled by the owner in favour of `IDEA-422` (rpm-linked): `L199`'s fixed carrier now
holds for SLIP and ROAD only, and the engine has its own effect (`KB-191`, `IDEA-689`, 0.1.5).

## L202 - LOCKED (owner rulings) / EXECUTED IN CODE / NOT DEPLOYED - a race ring belongs to its place; interest is a bookmark; one entry at a time

**Why.** Race-entry fixes kept landing one at a time (`KB-27`, `KB-75`, `KB-77`, `KB-82`, `KB-185`), and each patched
one of several independent answers to "which race is this ring/card for?". Every one of those answers was based on
time or on who the driver was, and never on where they stood. The owner answered targeted questions on 2026-09-28,
and those answers replace the model rather than patch it again (`KB-195`-`KB-199`).

**Rulings, LOCKED (owner, 2026-09-28).**
1. **Rings.** Every race inside its window has its own ring at its own venue. The window stays at 20 minutes. Rings
   are visible from far enough away to spot one and head over (`IDEA-694`).
2. **The card belongs to the ring you stand in**, never to "your soonest race".
3. **Interest is a bookmark**: GPS, reminders and a place in the Guide. It is never required to enter, and it never
   takes a ring or card.
4. **One entry at a time**, and a team seat counts. Entering B while entered in A is a **two-press switch**. The
   first press says what it will cost, and the second withdraws from A and enters B. A's fee follows the ordinary
   withdrawal rule, which is forfeit.
5. **A team seat is withdrawable at the venue**, and withdrawing gives the seat back.
6. **Street Calls are public races with their own ring** and never take another race's ring.
7. **Entry reach is the drawn ring**, and the server uses the same number.

**Executed.** Core: `competition.entry` (`RING_*`, `HELD`/`RELEASABLE`, `heldEntry`, `entered_elsewhere` on
`checkIn`/`register`) and `competition.venue_options` (seat = entry, `switch_entry`/`confirm_switch` in the ENTER slot).
Host: `NcmGuide.driverEvent` (entry first, then bookmark), `ncm:venue.at` and location-owned `venueOptions`,
`ncm:venue.option` carries its ring, the switch in `enterPlayer` (B is written and paid before A is released, so a
refused B never costs A), a single `ncmEntry` writer, and `NcmOrganized.releaseSeat`. Client: one ring per race,
visible to 500 m. Publication: every race inside the lead.

**Evidence.** Offline only. Core 765/765 under Lua 5.4 and LuaJIT. The full `ncm-test.ps1` gate is green. New stub
scenario `ringcard`. `guide`, `guide2`, `entrybag`, `weekend`, `gridcars`, `hostkit`, `rolling` and `progression` pass.
The six scenarios recorded red in `IDEA-685` fail at the same points, before or outside this code. **Live proof owed:
`MASTER_TEST §CE`.**

**Open around it.** `IDEA-691` (ring colour, platform), `IDEA-692` (re-seating), `IDEA-693` (practice elsewhere).

## L203 - LOCKED OWNER DIRECTION / DESIGN DETAILS OPEN - the motoring network begins in physical places and persists in the Hub

The owner set the product boundary on 2026-09-28. **Every Autofixer terminal is one distinct Market.** It is
unmarked and unknown until the Driver deliberately interacts with it; proximity is explicitly insufficient.
After that interaction the Market is permanently known, sits beside Base Market and the Driver's other discovered
Markets in F6, and may be browsed and purchased from there.

**Test drives exist only at the physical terminal and never in F6.** A test-drive Machine is timed, geofenced,
must return to the same terminal and may not enter a race. Time expiry, leaving the geofence and attempting race
entry are the three violation sources for one shared strike sequence: the first two violations are soft, pleading
messages (*"pleeeeeease return the car?"*, then *"you're making me feel bad"*); strike three is **Hellfire**, a
five-star police chase. **Returning the Machine after Hellfire clears NCM's test-drive penalty and fugitive state,
but it does not clear the active wanted level:** the Driver broke the rules and must escape the five-star chase
normally. A living Driver who keeps the Machine remains a fugitive even after escaping; police seeing them
retriggers Hellfire. **Death automatically returns the test-drive Machine and clears Hellfire and the fugitive
state. Disconnect also returns the Machine and clears the fugitive state.** Exact duration, radius and police
detection remain open. This preserves the Market
Network's distinction between learning/access and stock, and keeps test drives as temporary access rather than
ownership or a free vehicle faucet.

NCM will also examine physical garage and fuel-station locations for an NCM-owned motoring-place registry. **Every
garage and fuel station is visible on the map from the beginning**, with distinct authored SVG blips; unlike an
Autofixer Market, neither infrastructure type requires discovery. **Bought Parts may be held and
inspected remotely, but fitting moves to a physical garage and costs a percentage of the fitted Part's value.**
The percentage is authored economy balance; the debit and configuration change must be one transaction. That is
the entire first garage /
Engineering slice. Engineering is intentionally a much larger future lane, including an earned do-it-yourself
path, but that future is not smuggled into the first work package. The linked GarageCore, YARRG, CMS location
packs, Immersive Odometer/Fuel and public maps are reconnaissance sources, not permission to redistribute their
files, assets or coordinates without verification. Open implementation details are tracked by `IDEA-695`-
`IDEA-701`.

## L204 - PROVISIONAL / EXECUTED LOCALLY - fuel is persistent Machine state and distance is its authority

The first fuel slice is built locally and offline-green, not deployed. Fuel belongs to the persistent Machine,
not the current session or Driver. It is consumed only from the server odometer's accepted distance segments;
teleports and rejected jumps therefore consume nothing. The alpha profile is deliberately tunable: **60 L capacity,
350 ml/km (35 L/100 km), and €$2/L**. The HUD extends the odometer cluster with the authoritative percentage.

At zero fuel the server persists zero, stops the engine, and sends both toast and chat: **`Stuck? Type
/ncm.nofuel for help.`** `/ncm.refuel` is accepted only while seated in the active NCM Machine within 18 m of an
authored fuel station; it buys a full fill, and balance ledger plus fuel state settle under the economy lock before
the engine restarts. `/ncm.nofuel` chooses and routes the nearest station. The intended recovery presentation is a
jerry can in hand, but no server-safe handheld-equipment method or redistributable asset is yet verified. The built
fallback dismounts the Driver, stores/tows the Machine to that station, then asks them to call it from F6 and refuel.

Fuel stations are visible from the beginning with an NCM-authored SVG. Owner-supplied Immersive Odometer and Fuel
System 5.4a data provides 81 factual in-game pump coordinates. NCM copies no third-party names, code, icons, assets,
prices or interaction logic: it groups pumps within 50 m into **53 anonymous physical sites**, uses all 81 pump
points for refuelling proximity, and uses one representative pump per site for its map/recovery target. Every site
remains unaccepted truth until `MASTER_TEST §CF7` passes in-engine. This is an executed experiment pending live proof.

## L205 - LOCKED OWNER DIRECTION / EXECUTED IN CODE / LIVE-GATED - the Rig Bridge's gamepad layer is JoyMoCo, ported

**Owner direction (2026-09-28).** *"make wheel/pedals tab be called devices ... gamepad tab should allow me to
record pure button presses from my esp32 wheel ... also allow variants for that same button ... from other
devices ... controllers with gyro axes should be allowed to be mapped for driving x. We also need rumble presets
we can assign per button just like joymoco."* Answers to the four questions: (1) port the engine to C++ inside the
Rig Bridge -- Cyberpunk and this server now, possibly shared later as a mod; import the owner's rim buttons as the
default profile; JoyMoCo is read-only and untouched; other Cyberpunk control schemes are wanted; (2) each variant
carries a context dropdown: driving, on foot, or both; (3) build the full stack first and test backwards; (4) save
and load a local JSON, nothing more for now.

**Design that follows, LOCKED.** JoyMoCo's profile format v1 is the spec, with three additions documented in
`ncm/rig_bridge/GAMEPAD_PROFILE.md` (device-keyed sources, `context`, the XInput slot). The virtual pad reaches
the game by a detour on `XInputGetState`/`XInputSetState` in the game's own XInput modules, not ViGEm: the binary
imports XINPUT9_1_0 and names xinput1_4/1_3, and imports no Windows.Gaming.Input (measured from the import table).
Buttons OR with the physical pad, sticks and triggers take the larger deflection, JoyMoCo's rule. The Xbox pad is
never a source, because it already reaches the game. The panel talks to a separate loopback API guarded to the
game's process tree, because a whole profile through `page:send` would be dropped silently (`KB-63`).

**Ownership, extending `L201`.** The Rig Bridge owns every rig device, not only force feedback. It runs SDL3
in-process for Joy-Cons and SDL-only devices (the rim, `KB-201`), and Windows gives one process one raw-input
target, so Carrier 0.1.30 starts no SDL at all when the Rig Bridge is installed.

**PROVISIONAL.** The shipped Joy-Con stick mappings use `"stick": "auto"` because how SDL reports a solo
Joy-Con's stick varies. Recording windows are JoyMoCo's: 3 s countdown and 4 s capture for motion, first press
within 8 s for a button. Revisit on test.

**Evidence boundary.** Built and offline-green: the pure engine and the XInput merge under `tests/pad_tests.cpp`,
the full build warning-free, the panel harness green including the new section assertion. Nothing has run in
the game. `MASTER_TEST §CG` is the contract. Tracked by `IDEA-705`; gaps `IDEA-706`; sharing deferred `IDEA-707`.

## L206 - LOCKED OWNER DIRECTION / EXECUTED IN CODE / LIVE-GATED - physical Autofixers are specialized Market sources

**Owner direction (2026-09-29).** The supplied 20 coordinates are 20 distinct Markets. Permanent specialties are
allowed. A Market's 1–3 cars means 1–3 distinct models, while serialized examples may replenish. Every physical
Market must receive newly authored Parts supply rather than reusing Base Market stock; breadth and uniqueness are
the goal. Leave future Market identities unallocated for PvE discovery.

**Locked behavior.** The Market begins unknown and unmarked. Only an explicit terminal interaction may record
`physical_terminal` discovery; the league host then rechecks a fresh authoritative player position within 6 m.
Once learned, the Market persists in F6 beside Base Market and the Driver's other learned Markets, and buying from
F6 is allowed. Proximity never discovers it. The 20 launch terminals each carry 1–3 models and two Market-scoped
component Design families; a Base Market Design is never listed at an Autofixer.

**Catalogue evidence boundary.** The 18 added model families have `_player` records in the official OPEN//77 game
2.31 vehicle catalogue (the build-pinned endpoint served the newest indexed build at or below the requested live
build). This verifies identifiers, not successful Online spawning, handling quality, DLC entitlement behavior or
terminal Z/mesh alignment. Those remain live-gated. Tracked by `IDEA-709`–`IDEA-712`.

## L207 - LOCKED OWNER DIRECTION / EXECUTED IN CODE / LIVE-GATED - the Session Landing panel is what's new, nothing else

**Owner direction (2026-09-29).** *"our session landing page is quite ugly and dense, needs to be constrained."*
Asked what it is for: **what's new** (and "status dashboard"; see the open point below). The capability list is
"rapidly outdated" and goes; **the changelog stays visible**; **the progression-reset notice is scrapped**; nothing
new is added; it still opens on **every join and is closable**.

**Executed.** `panel.html` draws a centred column at most 760 px wide: eyebrow, "What's new" with the newest
release's title/date/build, that release's items, the collapsible changelog (newest open), and CONTINUE. The
contract block, the capability grid and the hero slot are gone from the markup. `core/player/landing.lua` still
validates and sends `contract` and `capabilities` (unchanged data contract, other readers untouched); the page simply
no longer draws them. The render check now asserts their absence. A 2026-09-29 release entry was authored so the
panel's first line is current.

**Open.** "Status dashboard" was chosen alongside what's new while "nothing new" was chosen for additions; whether a
status strip (balance, Machine, fuel, next race) belongs here is unasked. Tracked by `IDEA-714`.

## L208 - LOCKED OWNER DIRECTION / EXECUTED IN CODE / LIVE-GATED - weather, tyre heat and fuel load act on BALANCE, not only on the limit

**Owner direction (2026-09-29).** *"we shouldnt simply use minus grip everywhere, thats understeer. more grip can be
equally bad and just as relevant, possibly in tire warmth model as well."* Live evidence `E26`: on this engine
`gripScale` above 1.0 loosens the rear (oversteer) and below 1.0 pushes (understeer). Every condition below is
therefore authored as a balance choice.

**Weather (graded, drying road).** Road wetness climbs toward the weather's target while it rains (~2 min to full)
and dries after it stops (~6 min), so the laps after rain stay greasy. At full wet: grip x0.80 and brake x0.82
(owner: "noticeable"), drive x0.90. **Push on entry, loose on power:** while braking or turning in the wet car
pushes (grip below 1.0); under heavy throttle it briefly goes loose (grip above 1.0). Sandstorm: grip x0.95, drag
x1.05. Fog, pollution and cloud stay neutral.

**Tyre temperature.** Cold pushes (x0.85 rising to 1.0; live today). In the window: 1.0. **Overheated goes loose
with weak brakes:** grip up to ~x1.12, brake down to ~x0.88. Road temperature: cold road ~x0.95, hot road ~x1.03
and faster tyre heating.

**Fuel load (doubled on owner choice).** Scaled by fuel mass (~0.75 kg/L, 60 L = ~45 kg) over the Machine's mass;
on a 1,500 kg car a full tank costs ~8% drive and braking, ~3% grip (a slight push) and ~1% top speed. Fuel load
also heats tyres faster (short term) and adds long-term tyre wear exposure (owner: "faster wear longterm and hotter
tyres short term").

**Executed (2026-09-29).** `parts.thermal.levers`/`surfaceLevers` (cold pushes, overheated loose with weak
brakes, hot road livelier); `parts.handling` gains a `fuel` layer (`fuelContributor`, nominal 1,600 kg until
per-car mass reaches the server), wet drive loss, sandstorm, and `wetPowerGrip` (throttle 0.70 to 1.0 lifts wet
grip by up to x1.33); `ncm_world/server/machine.lua` moves `roadWetness` toward the weather's target in 0.05 steps;
`server/handling.lua` composes road wetness, weather id and fuel, and puts `wetPower` on the handling wire;
`client/carrier_bridge.lua` applies the lift from live throttle and re-sends every 100 ms while the road is wet;
`server/odometer.lua` scales tyre heating by `economy.fuel.heatFactor` and charges extra tyre-only exposure by
`tyreWearFactor`. `gripMultiplier` keeps its symmetric <= 1.0 meaning for the gauge; the earlier "the window is a
penalty, never a boost" rule is superseded for what the car receives.

**Open.** Every constant is a first pass to tune on the wheel (live tests `§HB1`-`§HB5`). Tracked by
`IDEA-715`-`IDEA-717`.

## L209 - LOCKED OWNER DIRECTION / EXECUTED IN CODE / LIVE-GATED - every weather is a road of its own, combined with time of day

**Owner direction (2026-09-29).** *"lets make all weather conditions have their uniquely tuned logical properties,
should combine nicely with time of day."* Before this only rain changed the road; every other weather heated the
track exactly like a sunny day.

**Executed.** `parts.thermal.WEATHER` gives each of the eight states a profile: `sun` (share of daytime solar gain),
`sky` (share of night radiative loss), `airC` (air offset), `wet` (road wetness target) and optional surface
`grip`/`drag`. Time of day multiplies through `sun`/`sky`, so sunny is the hottest afternoon and the coldest night,
heavy cloud keeps both mild, fog is cool with a damp film (wet 0.15), pollution traps heat and leaves grime
(grip x0.97), sandstorm is hot and gritty (grip x0.95, drag x1.05), rain soaks the road. Track temperature reaches
the tyre (heating) and the `surface` layer (cold pushes, hot livelier, `L208`). An unknown weather is the previous
model exactly. First-pass values; live test `§HB6`. Tracked by `IDEA-718`.

## L215 - OWNER DIRECTION / DESIGN OPEN - Oracle Kingdom informs the per-player PvE social layer

**Owner direction (2026-09-29).** Explore bringing the Radio-OS Oracle Kingdom socio-political simulation into NCM Online's expanded PvE, specifically for social interaction with NPCs per player. It may influence racing indirectly; it does not replace the Paddock's motorsport simulation. The attached Paddock plan contains proposed L210-L214 numbers, reserved here to avoid collision until that plan is reconciled into the living record.

**Boundary.** This is a research and design direction, not authorisation to port the Python plugin or deploy a new runtime. The event contract, social variables, shared versus private facts, persistence, pacing, authoring and test thresholds remain open. The static and headless assessment is [ORACLE_KINGDOM_PVE_ASSESSMENT.md](../research/open77/ORACLE_KINGDOM_PVE_ASSESSMENT.md); IDEA-719 tracks the work. Existing L176 voice rules, L183's authored-contact boundary, the Messages trigger budget and L69's live PASS rule continue to govern.

## L216 - LOCKED OWNER DIRECTION / PROTOTYPE BUILT - develop Oracle Kingdom in racing language before an NCM port

**Owner direction (2026-09-29).** Copy Oracle Kingdom into this repository and develop it here before porting anything to NCM Online. Recast its vocabulary as racing and allow substantially wider outcomes while preserving causal explanation.

**Executed in an isolated prototype.** `prototypes/oracle_racing/` contains an unchanged reference copy of the Oracle Kingdom and court source, headless tools and UI source, plus a new pure racing-social model. It takes stable racing/social event facts and produces private per-player NPC relationships, district standing, salient memories and cause-linked offers. Accept/decline and a later result can form a traceable event -> offer -> choice -> outcome path. It reuses Oracle's seeded RNG and indexed causal ledger. The 100-seed fixture sweep spans -56.7 to +98.2 average NPC respect after 32 events, with 36/600 individual values at the +/-99 cap. Replay, idempotency, provenance, shared-cast/private-history divergence, causal conservation and offer-choice-outcome tests pass. Those metrics show variance, not yet good pacing or writing.

**Boundary.** This is a standalone prototype, not an NCM resource, live system, or approval of particular contact scripts. Public Paddock events, results and provenance remain authoritative in their own domain. A later port must use the build-pinned NCM event contract and pass live MASTER_TEST cases. The current copy's realm, faith and decree systems remain reference code; the active racing model does not mislabel those equations as motorsport.

## L217 - OWNER REQUEST / RESEARCH RECORDED - assess ForkUniverse and Neikos as additional references

**Owner request (2026-09-29).** Also examine `D:/dev/Radio-OS/forkuniverse` and `D:/dev/Radio-OS/plugins/neikos.py` for lessons and port candidates. Static review only; no code copied from either source, no tests run, and no NCM runtime changed.

**Finding.** ForkUniverse contributes patterns for stable tick/event-namespaced randomness, replayable catch-up, strict event schemas and separating factual events from presentation deltas. Neikos contributes action-driven progression, a normalized macro-ledger, player trajectory and restrained cross-run memory echoes. For the racing prototype, combine replay/provenance discipline with compact choice-derived trajectory and a small scene-pressure summary. Keep public Paddock facts separate from private NPC interpretations; any shared district mutation requires a later ruling. Details and limits are in [the comparative assessment](../research/open77/ORACLE_KINGDOM_PVE_ASSESSMENT.md#2026-09-29-forkuniverse-and-neikos-comparison), tracked by IDEA-721.

## L218 - OWNER DIRECTION / PVE VISION - shared Night City career and social world

**Owner answers (2026-09-29).** A solo player's first 10–20 hours should **blend a racing career with city ties**. Their repeatable PvE play should mix **driving jobs, turf challenges and racing**. Recurring NPCs should appear through **Messages and place-based encounters**. Consequential conversations use **authored choices with reactive dialogue**. The world is **one shared evolving world**; the most visible changes are **people, access and opportunities**, with longer-term shifts in **access and alliances**. The first arc should **mix the existing contact web with new NPCs**. Use recognizable Night City **places**, while inventing most groups.

**Meaning.** Public events and shared access changes need server authority and source history; personal relationships can differ by player. These answers supersede L217's open question about whether shared district state is wanted. The precise magnitude, duration and conflict policy for shared changes are still open. The owner requested a deep four-simulator review and defined vision for the next coder; the [PvE world vision and sim review](../research/open77/NCM_PVE_WORLD_VISION_AND_SIM_REVIEW.md) records source strengths, limits, a proposed architecture and a concrete handoff. Its architecture is PROPOSAL, not a production implementation ruling. The Paddock attachment remains a plan in this checkout; no `44_THE_PADDOCK.md` or Paddock runtime exists here at review time.

## L219 - OWNER CORRECTION / LONG-TERM PVE VISION - personal adventures over shared simulation and physical dialogue

**Owner correction (2026-09-29).** L218's “one shared evolving world” must not be read as one shared questline. Each player has **their own PvE adventure**, while an underlying shared simulation runs for everyone; the NPC Paddock is the starting model for that substrate. The owner explicitly rejected framing this as an “ideal first version”: this is **long-term vision**. The player may choose a driver path, an NPC-team management path, or both as the design allows; no one role is assumed as the sole PvE route.

**Physical meetings.** The intended interaction is a named, physical NPC and a Fallout 4-like **text dialogue** between player and NPC, with **four primary intents leading to deeper choices**. Authored choices and reactive replies can often depend on evidence and relationship history, with the reason grounded in fiction. No voice acting or mocap is planned. Messages and physical conversations should read the same character/story state. The [vision review](../research/open77/NCM_PVE_WORLD_VISION_AND_SIM_REVIEW.md#physical-dialogue-long-term-interaction-contract) gives an illustrative shared-event/two-player example; it is still a proposal for implementation, not a built interface or a platform capability claim.

## L220 - OWNER DIRECTION / PVE ARCHITECTURE - simulation-led, performed by Night City through every capability tier

**Owner direction (2026-09-29).** The PvE layer leans **simulation-based**, built from the owner's multiple earlier Python sim engines (FTB1 through the Paddock plan, Oracle Kingdom/Court, ForkUniverse, Neikos, FTB2). It leverages what CDPR gave us: a rich Night City and the engine beneath it for NPCs, traffic, crowds, police, weather and native UI. **Owner correction, same session:** do not treat OPEN//77 as the extent of NCM's capability; NCM already ships its own redscript and RED4ext required mods (Carrier, Rig Bridge, ncm-vision/Scanner, Radial) and single-player NCM drove the native phone, journal, quest nav and mappins.

**Meaning.** The sims decide and Night City performs: sim state is server authority, engine bodies and UI are projections that never write back, and only server-corroborated observations flow upward. Persistent identity lives in the sim, not the entity. Each engine owns one job and they meet only through the fact tape. Capability is reached through three tiers (OPEN//77 server API; NCM's own native mods; vanilla systems those mods drive). The tiers differ in authority, not reach: client natives act locally, so shared state stays server-decided and corroborated. New natives ship as new packages under `requiredMods`, never inside Carrier or Rig Bridge. The [restructured vision](../research/open77/NCM_PVE_WORLD_VISION_AND_SIM_REVIEW.md) records the five-layer stack, the capability inventory and two first probes (native dialogue choices fed by the server; Online Messages in the native phone). Architecture remains PROPOSAL; no runtime changed; `IDEA-726`-`IDEA-728`.

## L221 - OWNER RULINGS / PVE - native dialogue yes, native phone deferred, real-time clock, per-system control, reuse by reimplementation

**Owner rulings (2026-09-29), answering the L220 vision's open questions.**

1. **Native dialogue: yes.** IDEA-727 is approved as the first PvE probe: a new isolated required mod drives CDPR's own choice UI from server-supplied choices, with a WebUI fallback.
2. **Native phone: deferred.** Building the single-player phone through WolvenKit was brutal and repeatedly lagged the whole game. The final SP phone works, except that Foreman, the richest thread, lags every time (`KB-212`). It would be a good feature but needs a deeper audit first. Online Messages is adequate for now. IDEA-728 is deferred.
3. **Sim control over vanilla systems is decided per enumerated system**, not by one blanket rule. The vision's [per-system table](../research/open77/NCM_PVE_WORLD_VISION_AND_SIM_REVIEW.md#per-system-control-decided-one-system-at-a-time) lists fourteen systems with proposed defaults. Only rows 1 (clock) and 14 (native dialogue) are ruled; the rest await the owner.
4. **The in-game clock follows real time in US Eastern** on a 24-hour day (11:00 PM ET = 11:00 PM in game), because day versus night matters to NPC schedules and to roleplay. The platform clock (`open77_weather`: `setTime`, `setTimeRate` 0–120, default 8× from noon on every restart) makes this rate 1.0 plus an Eastern anchor. Daylight saving, per-bucket event time, and players who always see the same hour are open (IDEA-729).
5. **Reuse proven code by principle, tested first, and make it work in Cyberpunk, not Python.** Tens of thousands of lines of the owner's engines are available. Mechanisms are reimplemented as pure `ncm/core` Lua, with the Python originals as test oracles where they can be run. No Python process runs beside the game.

**Boundary.** Research and direction only; no runtime changed. The clock service and the dialogue probe each need MASTER_TEST cases and a live PASS (L69).

## L222 - OWNER RULINGS / PVE - a Night City life sim: every vanilla system ruled, physical facts may write back

**Owner rulings (2026-09-29), answering the L221 questions.**

- **The model is a life sim.** Abstract *inZOI* or *The Sims 4*, set in Night City and flavoured by motorsport, but not so rigid that it is only racing. The owner's Python engines are the seed of a proper life-sim engine; CDPR and OPEN//77 supplied the hard part, Night City and a hostable multiplayer REDengine server. **There is no "first arc"**: the world is an ongoing snow globe players reside in.
- **Clock.** `America/New_York` with daylight saving. A player who always plays at the same hour always sees the same part of the day, and that is accepted as the cost of doing business. Events never pin their own time: a midnight race at noon makes no sense.
- **Per-system rulings** (the full table and wording are in the [vision](../research/open77/NCM_PVE_WORLD_VISION_AND_SIM_REVIEW.md#per-system-control-decided-one-system-at-a-time)):
  - Weather: ACCEPT, with expansion. World state, not a story knob; everything reacts to it.
  - NCPD: CHANGE. Legitimate NCPD interactions for players **and simulated actors** when their actions warrant it; never a wanted level manufactured for drama.
  - Ambient crowds and traffic: ACCEPT.
  - Vanilla traffic: CHANGE. Normally untouched, but an authoritative activity may control it where technically necessary, with explicit scope and restoration.
  - Named NPC bodies: ACCEPT AND EXPAND, including physical experience.
  - AI vehicles: CHANGE substantially. They may represent persistent actors and activities.
  - Map pins: ACCEPT, and the absence of a pin keeps discovery meaningful.
  - Markets: ACCEPT, deepen later. Named causes only; simulated NPCs buy parts and move the modelled R&D and supply chain.
  - Handling: ACCEPT the boundary. Narrative has zero direct handling authority; only physical and mechanical systems change it.
  - Hacks and cyberware: CHANGE. They are genuine sim verbs where target, capability and consequence are authoritative; no scripted effects masquerading as hacks.
  - Slow motion: ACCEPT. No sim authority.
  - Screens, radio and billboards: ACCEPT AND EXPAND. Sourced projection surfaces.
- **Write-back amended.** The Paddock plan's blanket "physical outcomes never write back" becomes provenance-gated. An activity running in explicit physical-authoritative mode whose outcome NCM corroborates writes `physical` facts back; everything else is a projection and cannot manufacture truth. Provenance is `physical`, `simulated` or `reported`, and one never pretends to be another.
- **People.** The 18 quest-graph contacts become physical people too. Canon gangs and groups may be used. NPCs may address the player by driver name, an earned handle, or both. Solo incident frequency is not locked; test and iterate.
- **Work order.** The Paddock lands first, then the social sim. The Python originals may be run as test oracles freely. Dialogue is a mix of owner-authored and drafted lines, informed by Night City's own dialogue.

**Boundary.** Direction, not implementation. The vision stays PROPOSAL architecture; each system's first use still needs MASTER_TEST cases and a live PASS (L69). New ideas are `IDEA-730`-`IDEA-734`.

## L223 - LOCKED OWNER DIRECTION / OPS - NCM Online is frozen at Baseline 1; all work moves to the development server

**Owner direction (2026-09-29).** NCM Online is sound as it stands: someone can join with a wheel and play just by joining the server, a Thrustmaster tester has been contacted and two more testers are planned. Iterating on Online risks hiccups for them. **The current Online deployment is Baseline 1, frozen exactly as it is. Nothing is pushed to Online until the big expansion is ready on dev.** All PvE and sim work happens on the development server exclusively.

**Why this ruling.** Iterating on both servers once produced a split that had to be reconciled. From then on only Online was pushed, so dev fell days behind. Dev now catches up to Baseline 1 and becomes the only workshop.

**What Baseline 1 is (verified 2026-09-29).** Platform `2.31.13+op77.102` (client `op77.101`), identical on both servers. All 374 files in Online's `resources/ncm` are byte-identical to the working tree at the Baseline 1 commit (git tag `online-baseline-1`). Required mods are `ncm-carrier` 0.1.30 (`d4431422...`), `ncm-rig-bridge` 0.1.7 (`eea1aba6...`) and `ncm-vision` 0.3.0 (`e44ecafa...`), plus ArchiveXL 1.27.1 and TweakXL 1.11.4 in the mod store. Online's `resources.load` also carries `open-voice`.

**Enforced, not only written.** `tools/deploy-staging.ps1` now refuses to change Online without `-ThawOnline`; `-Logs` still works. Reading Online's logs and state remains fine. A thaw is an owner ruling recorded here, never a session's judgement.

**Dev data (owner, 2026-09-29).** The development database keeps its own data and is never seeded from Online. Its population is the owner's account and `ncmtester2`, and that is a deliberate design constraint: if the sim delivers a good experience for one player plus one test account, it has done something good.

## L224 - OWNER RULINGS / PADDOCK - the Paddock plan's decisions confirmed and amended for a life sim

**Owner rulings (2026-09-29).** These answer the questions raised before the Paddock is built on dev (L223). They confirm and amend the attached Paddock plan, whose proposed L210–L214 are reserved by L215. That plan is still not reconciled into `44_THE_PADDOCK.md`, which does not exist yet.

1. **The parallel circuit stays.** NPC organizations and series never share a grid, standing or result with humans. This will be reconsidered only once there is good NPC racing data *and* human data to compare.
2. **Full scale**: 4 tiers, about 60 organizations and about 150 drivers.
3. **A daily rhythm replaces flat cadence.** Series race on the real-time clock (L221/L222): **street racing at night, sanctioned racing during the day.** This replaces the plan's flat "every 20–30 min per series, staggered".
4. **Billie takes bets on NPC races, confirmed.** This amends L172 as the plan proposed: never on a human, never on a human-managed org's drivers, and managers are barred from their own series.
5. **Build order agreed.** First a sim-only season (results, standings, WIRE); then display-only sightings in the city; then physical-authoritative races that write back when corroborated (L222).
6. **Paddock people get physical bodies**, whenever it makes sense in the build. **Garages are shared, rented workplaces, not homes.** Teams rent garages for car work; one garage serves several teams at different times of day, with some natural overlap, and double or triple stacking where garage density requires it. Night City's publicly accessible points of interest (about 1,000, including many garages) and the map are going to be a major part of the sim.
7. **The owner's own code and data may be reused verbatim**, including the FTB name and sponsor generators. The owner holds the copyright in the Radio-OS and oracle-radio engines and grants NCM that use, which settles the rights question for owner-authored sources. Third-party material in those repositories is not covered.
8. **Managers and street work.** A manager may not manage a second team (the One-Team Rule). Street activity stays free for everyone, managers included.
9. **No hardcoded cap on shared impact.** How much one player can change should be learned from the sim's behaviour, not guessed as rules in advance. Design the shared transactions so a limit can be added once evidence shows one is needed.

**Boundary.** Direction for the Paddock build on dev. Implementation, schema numbers and live PASS criteria belong in `44_THE_PADDOCK.md` and MASTER_TEST once written. New ideas are `IDEA-735`–`IDEA-737`.

## L225 - ADOPTED - `44_THE_PADDOCK.md` is the authority for the NPC motorsport world; L210–L214 released

**Owner request (2026-09-29): "paddock design doc please".** The attached Paddock plan, amended by L222 and L224 and re-verified against Baseline 1, becomes [44_THE_PADDOCK.md](44_THE_PADDOCK.md) (CURRENT; the Pace DLL section is SPEC-level). The decision numbers the plan proposed, L210–L214, were reserved by L215 and never written; they are **released unused**, and their substance lives in L224. Numbering is not reused (L68).

**What the doc adds beyond the rulings, as first numbers and tunables, not locked balance:**
- A daily schedule of 45 races: Street 20:00–04:00 ET, Regional 12:00–20:00, Pro 10:00–18:00, and a Premier feature at 15:00.
- Pure-core Eastern-time conversion, so the Paddock does not depend on the in-game clock service.
- A declared seeded calibration baseline that works at two humans.
- Salience-ranked WIRE with a small daily push budget.
- Billie's authoring as a phase-2 dependency.
- Five build phases, and MASTER_TEST §CH.

**Boundary.** Nothing is built. All work is on the development server (L223), and done means a §CH PASS (L69).

## L226 - OWNER RULINGS + BUILT / PADDOCK - doc 44 §17 closed; phases 1-2 built on dev, awaiting §CH

**Owner rulings (2026-09-29), closing doc 44 §17 before the build:**
1. **Series names are generated**, every tier, by the ported FTB league generator (no hand-authored Premier/Pro names).
2. **NPCs race the same routes humans race** (the eight city sprint roots). This is what makes PACE and calibration mean something.
3. **Head-to-head slips pair two drivers in the same race only.** No cross-series head-to-heads.
4. **Push budget: 3 unsolicited Paddock messages per player per Eastern day**; solicited items (your own slip, your own team) are exempt.
5. **Build scope today: phases 1-2** (the season runs; Billie and the manager). Sightings, bodies and the Pace DLL wait.

**What was built** (offline-green, `tools/ncm-test.ps1` ALL GREEN; nothing live yet):
- Pure core (`ncm/core`): `vocabulary.hash` (LuaJIT-safe FNV-1a + Park-Miller streams), `world.clock` (Eastern DST), `world.conditions`,
  `paddock.{names_data,names,attributes,car,season,world,sim,calibration,tape,news,tags,projection,pricing,finance,contracts,progression,principal,manager,spotlight}`,
  `competition.affiliation`. `names_data` is GENERATED by `tools/paddock-names-port.py` from the owner's FTB source (L224.7); `--check` detects drift.
- Migrations 043-050 in `ncm_league` (043 stamps human results with conditions via `NcmWeather.stamp`, a separate guarded UPDATE after each write).
- A new server-only resource `ncm_paddock` (kill switch `paddockEnabled`), and a PADDOCK tab in F6 (WIRE, STANDINGS, RESULTS, PACE, DIRECTORY, BILLIE'S BOARD, MY ORG).
- **Billie is authored** (`graph.contacts` `authored = true`, a script in `graph.opening`). Rico's "Put me in touch" now opens her (`open:billie`) instead of granting a lead. Placing a slip requires having met her.

**Findings the build forced, recorded rather than silently absorbed:**
- **FTB1's race engine is too processional for one-lap sprints.** Its 0.35 s overtake margin (built for 50-lap races) let a clearly faster car finish where it started. The sprint port uses a 0.02-0.08 s margin, 0.12 s grid spacing and lighter dirty air. With equal cars pole still wins about 48%, so the grid matters; that is why every tier grids by a qualifying sim rather than the reverse grids the earlier plan proposed.
- **FTB1's crash rate (about 3.6% per lap at stat 50) is replaced by a per-race DNF target of 2.5%** (measured 1.5-3.5% over 2,000 races).
- **The OPEN//77 instruction quota (KB-211) is now measured, not guessed.** `tools/test-paddock-host.lua` meters VM instructions between yields. The first cut of the daily tick ran about 589k instructions in one slice, because the store JSON-encoded 420 rows before yielding. Now the worst slice anywhere is Billie's pricing at about 178k (400 sims, 2 per yield), and the canary fails above 400k.
- `vocabulary.json` keeps 4 decimals. That is fine for hidden attributes (daily growth steps are about 0.01), and it is the reason the store round-trip test compares within a tolerance.

**Boundary.** Built, not live. Done means `§CH1`-`§CH16` PASS on the dev server (L69, L223); Online stays frozen. New ideas are `IDEA-738`-`IDEA-744`.

## L227 - OWNER RULINGS + BUILT / PADDOCK - skip sightings; phases 4-5 built and running on dev; MASTER_TEST is the 1.0 bar

**Owner rulings (2026-09-29):**
1. **Phase 3 (sightings) is skipped**, except the parts phases 4 and 5 need. "No point in phase 3 if phase 5 exists and that's the one I'm looking for." The display-only sighting pass is not built; what it would have supplied to phase 5 (a road line from human ghosts within the 64-point `followRoute` limit, the 55 m/s platform cap, spawn/despawn discipline) is built into phase 5 itself.
2. **MASTER_TEST is a loose expectation for the 1.0 full release, not a gate on dev-server work.** "This is dev server stuff today so not relevant." L69 still defines *release* status; it no longer orders the dev build queue. NOW's next action is no longer "run §CH first".
3. **Build phases 4 and 5 now.**

**What was built** (commits `edc6b8c`, `dbeebf4`; `tools/ncm-test.ps1` ALL GREEN; running on dev):
- **Phase 4, bodies and garages (doc 44 §11).** `tools/paddock-garages-port.py` carries 83 garage/workshop/parking sites from the game's own map pins into `paddock.garages_data` as derived facts only (position, kind, district); Autofixers stay out (they are L206 terminals). `paddock.garages` rents every org a site on a shift persisted on the org row (schema 051): a day team pairs with a night team, never more than three deep; on dev 60 orgs share 36 sites. Bodies exist only where a player is within 120 m of a garage whose tenant is on shift (senior first, drivers away around their own races, a global cap of 18). Each body carries an `open77_interactions` **Talk** prompt; the server re-checks distance and answers with `paddock.talk`, one line from public facts only, spoken through a notification until native dialogue (IDEA-727) passes. Meetings are recorded so a return visit hears something new. A site can be marked good/bad from play (`ncm.paddock.garage`), and a bad site's tenants move.
- **Phase 5, physical-authoritative races (doc 44 §12, §15).** A player declares an upcoming NPC race live from F6 RESULTS → NEXT UP (hold) and goes to the start line. At T-75 s the grid spawns there, pole first. At the window's opening the sim runs sealed as always, then the cars drive a human ghost's line at a ceiling taken from **each car's own sim splits**. The **server times every gate itself** from canonical positions. A clean run (at least half the field and two cars finishing every gate in order) **replaces the sealed sim result with provenance `physical`** before the close; anything less is `fallback`, the sim result stands, and the reason is kept. The race's close waits for the verdict, and Billie settles after it, so nothing is settled twice. One live race at a time; a declarer who is not at the start, or who leaves, calls it off.
- **Two backends.** `platform`: OPEN//77's `vehicles.ai.followRoute` with an NPC driver, per-leg ceilings set on each `waypointReached`, capped at 55 m/s. `pace`: **NCM Pace** (`ncm/pace`, package `ncm-pace` 0.1.0, loopback 127.0.0.1:38640-38643), a new RED4ext/redscript package that issues the same native `AIVehicleDriveToPointAutonomousCommand` OPEN//77 uses, uncapped, on the declarer's client, and reports gate times at the game's tick rate. Pace times are evidence: a `physical` verdict on the Pace backend also requires them to agree with the server's within 1.5 s. `liveBackend = auto` uses Pace when the declarer's client reports it. NCM Pace is published to dev's `requiredMods` (the IDEA-478 procedure as corrected by the owner; `publish-carrier.py --id ncm-pace --remove` undoes it).
- Schema 051 (`paddock_live`, `paddock_live_crossing`, `paddock_meeting`, `paddock_garage_check`, org garage/shift).

**Findings the build forced:**
- **P-PACE-1 is mostly answered by existing evidence.** The Scanner already proved that a client vehicle snapshot's `engineEntity` equals redscript's `EntityID.GetHash`; the Pace plugin maps OPEN//77 vehicle ids to engine entities that way. Server-created cars confirm on the first live race.
- **OPEN//77's own `followRoute` issues the same native command** (`Open77VehicleDriving.reds`), so the platform backend and Pace differ in the speed cap and gate-timing rate, not in the driving model. P-PACE-2 (does the platform leave a native command alone on a car with no platform job) stays open until the first Pace race.
- **The first boot after schema 051 died on the instruction quota** (`KB-214`): the rental sort hashed site ids inside its comparator, in the same slice as the world and race loads. The harness now meters a from-scratch rental.

**Boundary.** Running on dev, untested with a player in the city. Online stays frozen (L223). New ideas are `IDEA-745`-`IDEA-751`.

## L228 - OWNER RULINGS / PADDOCK - live races run on schedule by themselves; racers persevere

**First live race (owner, 2026-09-29, 20:40 street race from North Tunnel):** the grid spawned and raced, piled up at the start; most cars that crashed stopped and stayed; a few escaped, some hit traffic; one recovered late and hit a second pileup; the race was called "didn't finish". "Race neutralization was WAY too trigger happy, but overall this was a good proof."

**Rulings:**
1. **Nobody declares a live race.** "I don't want to ever have to hold to make live race happen. It should just happen on schedule as intended." The RUN IT LIVE button and the declaration flow are removed.
2. **Racers must persevere:** "try much harder to persevere through a race desperately trying to win."
3. **Proof order:** first a race that starts and finishes; then a player sitting halfway along a route sees the field pass.
4. **The dev server is build .102**, and the platform docs index (op77.78) is stale for it. Platform facts about AI simulation are measured on .102, not taken from the .78 cards.

**Built:**
- `liveMode` = `watched` (default: a player within `liveWatchRadiusM` 600 m of the route's line or start at staging) / `always` / `off`. At most `liveMaxConcurrent` (2) at once.
- **A wider grid** (rows 15 m apart, columns 6.8 m) and a **rolling start** (one row every `liveStartGapMs` 900 ms).
- **Perseverance:** no progress for `liveRecoverSec` (8 s) re-sends the car from where it is on the line; for `liveResetSec` (20 s) puts it back on the road just behind where it stopped (`vehicles.setTransform`) and sends it on; only `liveRetireSec` (180 s) retires it. A failed or cancelled AI task is re-sent at once. Progress is distance from where the car last made way, so a slow car is never called stuck.
- **The finish:** once the winner is home, everyone still running gets `liveFinishGraceSec` (90 s) or half the winner's time; cars still out then are `not_classified`. The hard deadline is 4x the sim winner's time + 2 min.
- **A probe** (`ncm.paddock.probe`, and once 90 s after boot): one AI car far from every player, driven for 30 s; the answer goes to `paddock_live` as `probe-<t>`. If cars move with nobody near, `liveMode = always` is safe.

## L229 - MEASURED / PADDOCK - what moves an AI car on build .102 (probe v1)

`ncm.paddock.probe` on dev (build .102), one player online, five cars on a distance ladder, three legs of 25 s each:

| Distance | A: unasked | B: `requestAuthority` to the player | C: remote-camera interest lease + request |
|---|---|---|---|
| 186 m | picked up by the player's client (`physicsOwner` 1, steward) but the drive **failed**: it spawned on a garage pin, not a road | failed | failed |
| 573 m, 840 m, 1.6 km, 3.6 km | `waiting_for_simulator`, `physicsOwner` 0 | **refused `ai_driven`** | lease granted; still `waiting_for_simulator` |

**Findings, stated no wider than the evidence:**
1. A client picks an AI car up by itself somewhere **between 186 m and 573 m**. Beyond that nothing drives it. (An earlier single-car run, with nobody online and then with the player 3.6 km away, agreed.)
2. **`requestAuthority` is refused for an AI-driven car**, by name. The live-race "ask the nearest watcher" change did nothing for platform AI and is removed.
3. **A remote-camera interest lease alone** (no picture) did not make the client simulate. A camera actually rendering the car (`openView`) and a driverless car with a request (for Pace or kinematic playback) are **untested**: probe v2 legs D and E.

**Consequence for the design (L228 all-of-the-above):** the continuous race model owns every car everywhere; physical cars exist only inside a bubble of a few hundred metres around a player (first numbers 250 m in / 400 m out, tuned by probe v2). Probe v2 narrows the ladder to 150-550 m on road points only.

## L230 - BUILT + PROVISIONAL RULE / PADDOCK - the continuous race and the physical bubble

**Built (dev, offline-green):**
- `paddock.racestate`: every running race has a continuous model from its window's opening, watched or not. Each car's line position at every millisecond comes from its own sim splits. With no physical stretch the model reproduces the sim exactly (tested).
- **Anchors** write the street back: a physical car's real (distance, time) re-anchors it, and it continues at its own sim pace from there, so what it lost or gained carries to the flag.
- **The physical bubble** (`ncm_paddock/server/bubble.lua`): a model car within `bubbleInM` (250 m) of a player is spawned where the model says, facing along the line, and driven physically with the street race's perseverance; beyond `bubbleOutM` (400 m) of every player it is anchored back into the model and removed. First numbers from probe v1 (a client picks AI up between 186 m and 573 m).
- **F6 PADDOCK -> LIVE**: every race on track, a route strip with every car and a timing tower; street and bubble cars at their real positions.
- Schema 052 adds `mixed` to `paddock_race.provenance`.

**PROVISIONAL, awaiting the owner:** when any car of a race drove physically in a bubble, the result is the model's classification with every anchor applied. It is `physical` when every car drove at least 95% of its line physically, else `mixed`, and `detail_json.live.physicalPct` names each car's share. A whole street race (grid at the start) is unchanged: `physical` or `fallback`.

## L231 - BUILT / WORLD - Night City on US Eastern real time (KB-217, IDEA-729)

The owner saw bright sun at 21:30 Eastern. The server alone cannot fix it: OPEN//77's weather guide says the engine always runs at 8x and every clock correction is a world time-jump, so any other server rate means a jump about every 15 s. The owner pointed at Nexus mods for the native route, and two of them (Custom Timescale 7955, the 2:1 Gametime tweak 19244 after Game Time Tweaks 870) each ship one 8 kB archive that replaces `base\gameplay\game_time.curveset`.

**Measured:** that resource holds one curve, `time_of_the_day_to_timescale`, a multiplier on the engine's 8x base by hour of day (about 1.0, dipping to about 0.72 at dawn and dusk to stretch them).

**Built:**
- **NCM Clock** (`tools/build-clock.ps1`, package `ncm-clock` 0.1.0): the curve flattened to 0.125, so the engine runs at exactly 8 x 0.125 = 1x. It is regenerated from the local game at every build (one named file extracted), so nothing of CDPR's is committed. Published to dev `requiredMods` and hand-installed on the owner's game (KB-215).
- **The clock service** (`ncm_paddock/server/clock.lua`): rate 1.0 and Eastern time at boot; every 10 minutes it re-reads the clock and writes only past a 120 s drift. `clockMode = eastern | off`.

**Caveat:** every client needs NCM Clock; one without it still runs 8x and is jumped back about every 15 s. Quests that set their own time still do.
