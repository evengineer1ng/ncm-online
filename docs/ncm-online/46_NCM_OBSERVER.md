# 46 - NCM Observer: the ghost that watches the race

> **STATUS: SPEC** - owner intent, captured 2026-10-04 (L307); O-1 and O-4 ruled in the L307 addendum. **§5 slices 1-2 are authorised and BUILT (L308) and are governed by code** (`ncm/online/resources/ncm_observer/`, core `observer.director`); the rest stays SPEC. **Not authorised; do not implement; do not contradict.**
> §2-§5 are coder notes: §2-§3 are evidence, and §4-§5 are PROPOSAL with no authority until ruled.
> Authority map: [INDEX.md](INDEX.md). Governing decision: L307. Ideas: IDEA-928 to IDEA-945.
> Analysis Observer (heatmaps, incident markers, interventions) is captured in [49_CITY_MEMORY.md](49_CITY_MEMORY.md) (L312, SPEC).

NCM Observer is a specialised OPEN//77 client that exists to witness Night City Motorsports without taking part in
it. It is a ghost camera operator, race reporter, streaming bubble and broadcast source in one client.

---

## 0. The owner's statement (verbatim, 2026-10-04)

> At this point, I think **NCM Observer is a specialized OPEN//77 client whose entire existence is to witness Night City Motorsports without participating in it.**
>
> It's basically a **ghost camera operator, race reporter, streaming bubble, and broadcast source wrapped into one client.**
>
> From start to finish:
>
> 1. **It begins as NCM Tester 2.** Instead of treating that second local client as a failed attempt at local multiplayer, we give its account/client a privileged `observer` role. It connects to OPEN//77 normally enough that the server recognizes it as a client, but NCM explicitly excludes it from gameplay. It has no meaningful player progression, money, garage, championship eligibility, race entries, damage, police consequences, economy, standings, etc. It should not count as a human racer or affect ordinary player statistics. Ideally its physical avatar is suppressed entirely. It's a presence without a person.
> 2. **Its location exists primarily to make the world physical.** This is one of the clever parts. OPEN//77/NCM already has races that can be simulated remotely and become physically represented around clients. Observer exploits that. If you're racing Corpo Circle while another event is happening in Westbrook, Observer can move its client presence to Westbrook. Its streaming bubble causes that part of the simulation to become observable/physical, subject to however our current physical↔simulated transition actually works. So Observer doesn't merely query a remote race. **It goes there and watches it happen.**
> 3. **It can target any active racer or race.** NCM's race state already knows who's racing, where, in what event, what position they're in, and so forth. Observer gets a target-selection/director layer. It can be told: `Watch Westbrook Short Ring`, `Watch P6`, `Watch Chang`, `Watch the closest battle`, `Watch leader`, `Watch this incident`. Initially that's probably admin/debug control. Eventually it can be automatic.
> 4. **Once there, it becomes a camera rather than a character.** It gets several **racer-relative camera modes** that require essentially no track authoring: passenger-seat/onboard, close chase, far chase, overhead drone/helicopter, orbit, side/rear angles where feasible. Passenger is particularly important for MPC development because we can literally ride with the driver and hear/watch their manual gearbox behavior.
> 5. **It also gains Night City's world-relative camera network.** This is the bonkers second half. We already have roughly **30,000 lane geometries from WolvenKit** because we've been doing things such as programmatic speed limits. Each lane gives us position and road direction, which means we can generate candidate roadside broadcast-camera poses automatically. Offset from road, choose height, aim along/across the lane, look ahead. No need to hand-place cameras one by one.
> 6. **We curate those generated cameras instead of authoring them.** Observer becomes the review tool. Snap to candidate camera #1: yes/no. Camera #2: yes/no. Camera #3: garbage, no. Camera #4: beautiful, yes. We could eventually approve thousands or tens of thousands. Each approved camera remains associated with the road/lane rather than a particular race. So any future race using that road inherits television coverage automatically. A newly constructed race could instantly know which approved cameras lie along its route.
> 7. **During a race, Observer becomes a live television camera operator.** It can jump between those two camera families. Roadside shot as the field approaches. Cut to overhead drone through an intersection. Cut to far chase for a battle. Cut into P6's passenger seat. Cut to another roadside camera ahead. Because NCM knows the route and racer positions, it can anticipate rather than merely react. It knows that the P4/P5 battle is 180 metres from an approved camera and can cut there *before the cars arrive*.
> 8. **Eventually a deterministic director chooses what Observer watches.** NCM already generates the signals needed to determine what's interesting: small gaps, position changes, side-by-side running, attacks, defensive moves, incidents, penalties, leader approaching traffic, final laps, finishes, perhaps even unusual MPC gearbox behavior. Those become shot-selection inputs. It isn't computer vision trying to understand pixels. **The simulation tells the camera where the story is.**
> 9. **Observer simultaneously becomes Radio OS's reporter.** This is important: Radio OS's live race commentary attaches to **Observer, not your player character**. Your player remains just a participant. Observer has an eyewitness perspective. It can say, effectively, "We're riding with Chang," because it actually is. It knows what is happening around the camera and can maintain short-term broadcast memory: Chang has tried the outside twice; these two have fought for four laps; this driver held fourth here last lap but shifted to fifth this time.
> 10. **The reporter gets two kinds of truth.** Eyewitness truth comes from Observer's physical context: cars nearby, passes, lines, speed, gears, shifts, crashes, traffic. Broadcast-desk truth comes from NCM's official data: timing, gaps, classification, penalties, standings, championship history, weather, race identity. Hidden MPC variables can guide attention, but they shouldn't be spoken as supernatural knowledge. If an NPC's aggression variable spikes, Radio OS reports the resulting late braking or attack, not "aggression is now 0.78."
> 11. **OBS turns that output into Race Week television.** Observer's rendered client is the video source. Game audio supplies engines and environmental sound. Radio OS/TTS supplies commentary. NCM telemetry can drive browser-source broadcast graphics: timing tower, event title, lap/gate information, lower thirds, championship positions, penalties, unofficial/official classification. OBS composites everything into one live program.
> 12. **That program is streamed outward.** Assuming the OPEN//77 TV mod accepts the appropriate live-stream source, OBS feeds the stream to whatever service/protocol it can consume. OPEN//77 televisions then play that feed.
>
> And that's where the snake eats its tail:
>
> **Night City runs the race. Observer travels to the race. Observer physically watches the race. Radio OS reports what Observer witnesses. NCM supplies official timing and graphics. OBS packages the whole thing. The feed goes back into OPEN//77. Players standing elsewhere in Night City watch that race on televisions.**
>
> You could be sitting at the drive-in watching Westbrook live. Then get in your Galena and drive toward Westbrook while the same race continues.
>
> And this isn't merely presentation technology. **Observer becomes one of our primary development instruments.** When we give MPCs manual transmissions, gearbox familiarity, learned shift timing, ratio proficiency, line decisions, defending and attacking behavior, we don't have to infer whether it's convincing from a table of numbers.
>
> We put the ghost in their passenger seat. We listen. We watch. Then, once it works, **we put that same ghost on television.**

## 1. Invariants (SPEC, restated from §0; do not contradict)

1. **A presence without a person.** The observer role has no progression, money, garage, entries, eligibility, damage,
   police, economy, standings or statistics, and is never counted as a human racer.
2. **It is still a client, so it still makes the world physical.** Removing Observer from gameplay must never
   remove it from the systems that materialise simulated races around clients.
3. **It goes to the race and watches.** It is not a remote query.
4. **Two camera families:** racer-relative (needs no authoring) and world-relative (generated from lanes, curated, owned
   by the road rather than by a race).
5. **The simulation tells the camera where the story is.** The director is deterministic and fed by NCM's signals,
   not by computer vision.
6. **Radio OS reports from Observer, not from the player.** It uses two kinds of truth (eyewitness and broadcast
   desk). Hidden variables can steer attention, but they are never spoken.
7. **It is a development instrument first** (ride along with MPCs), and television second.

## 2. What already exists (evidence; file and decision cited)

| Spec stage | What is in the tree today | Where |
|---|---|---|
| 1 Tester 2 | `ncmtester2` is a real identity (`d82ed6cf-c5cb-4dd8-8473-3a1d0057d3b7`). A second local client runs its Lua normally. | KB-52; KB-4 |
| 2 Physical bubble | Any connected client counts: the bubble reads `Open77.players.positions` and materialises a model car within `bubbleInM` **100 m** of any player, handing it back past **150 m** (L247). With `liveMode = watched` (L228), a player within 600 m of a route lets a live race start. *(Corrected at L308: the bubble is `bubbleInM` **250 m** / `bubbleOutM` **300 m** today, restored after L247's diagnostic 100/150.)* | `ncm_paddock/server/bubble.lua`; L228-L230, L247 |
| 2 Bubble driving | The client has to run NCM Pace at the street or oval minimum for the bubble to drive cars in its game. | `bubble.lua` `paceAtLeast` |
| 2 Moving it | `ncm.tp <playerId> <toPlayerId\|venue>` and the `ncm:warp` event (`Open77.players.teleport`). | `ncm_world/server/main.lua:803` |
| 3 Race state | Every running race has a continuous model: each car's line position at every ms, anchors from physical driving, and the timing tower in F6 → LIVE. Racer pins every 2 s (L304). | `paddock.racestate`; L230, L304 |
| 4 Cameras | OPEN//77 scripted cameras replace the player's view. `Open77.camera.project` and `screenRaycast` exist (IDEA-573). | platform guide `cameras.md` |
| 5 Lanes | **19,432 vehicle lanes** in the speed-limit index (L301, `tools/gen-lane-limits.py`, now `ncm_speed`). Pace's traffic graph: 279,906 road points and 51,338 continuous edges. The "~30,000" in §0 should be reconciled with these counts. | L301, KB-327; L241; `../research/open77/PACE_ROAD_PATH_PROBE.md` |
| 7/8 Signals | Gaps and positions (racestate), the flag (L305), crash facts (IDEA-918) and speeding incidents (L301). | L301, L305 |
| 9/10 Provenance | Observer-attested facts are already distinct from server-measured ones (`BASIS`, `observation_basis`, migration 029). Eyewitness truth maps onto `attested`, desk truth onto `server`. | IDEA-362; L164 |
| 11 Overlays | Native NPC nameplates (`ncm_broadcast` 0.1.3), a timing tower, and the race graph surface. | IDEA-839; L235 |
| 12 World TVs | `open77_media`: a 38-record screen catalogue up to `cinema.150ft`; the page is CEF, **http/https only**; a client materialises 6 screens within 90 m. | IDEA-574 |
| Remote cameras | `Open77.remoteCamera` + `open77_remote_camera`, **experimental** from op77.82 (dev is .102). The server distributes camera definitions, **not video frames**, so each viewer renders on its own client. | `evidence/2026-09-19/guide-remote-camera-excerpt.md` |

## 3. What §0 assumes that nobody has measured yet (evidence gaps)

Each gap is paired with the cheapest experiment that closes it. None of these experiments has run.

| # | Assumption | Why it is open | Cheapest test |
|---|---|---|---|
| G1 | A second client on this PC can be the observer. | KB-4: a script-launched second client loses its WebHost; launcher launches render. KB-147: the Carrier port. **Observer may need neither WebUI nor Carrier**, which would sidestep both. GPU load from two clients plus an OBS encode is unmeasured. | Launch `ncmtester2` through the launcher with the full dev stack; record fps on both clients with OBS capturing client 2. |
| G2 | Moving Observer to a distant race makes it physical. | Expected from the code (§2), but never observed with the observer as the only nearby client. | `ncm.tp` the observer beside a running Paddock race while the owner is more than 600 m away; look for `bubble ... spawning` lines and see the cars on screen. |
| G3 | Observer's avatar can be suppressed and non-colliding. | Paddock cars are driven around it; an invisible body standing on the road is still an obstacle. `players.setModel` existed only on `main` at .78. Collision and visibility controls are unverified. | Read the .102 API cards for player visibility, collision and ghosting before designing. |
| G4 | The camera can sit 300 m down the road and watch the field approach. | **The bubble materialises cars at `bubbleInM` (250 m today) from the observer's position**, so they can pop in at the edge of a long shot. The owner has moved this number before (L247 100 m, later restored to 250 m), so it is not Observer's to widen. | Measure pop-in from a roadside pose. Then decide whether camera candidates need a look-distance cap (≤ ~90 m) or whether the observer's body may lead its camera. |
| G5 | "Passenger seat" can ride in an MPC's car. | Seating a client in an AI-driven car may move physics ownership (`requestAuthority` is refused for AI cars, L229) or disturb the AI task. A seat-offset camera attached to the car, with the body nearby, avoids the question. | Try the attached camera first; seat the observer only as a separate experiment. |
| G6 | The OPEN//77 TV plays a live stream. | `open77_media` loads an http(s) page in CEF. Live video then depends on that page's player and on **codecs: stock CEF builds commonly lack H.264/AAC**, so a VP8/VP9/AV1 path (WebRTC or WebM) may be required. Unverified. | Point one screen at an http page playing (a) a VP9 test clip and (b) an H.264 clip; then try a low-latency live source. |
| G7 | A remote camera can stand in for physical presence. | L229: an interest lease alone did not make a client simulate. Whether a camera actually *rendering* a car does is probe v2 **leg D, never run**. It does not change §0's design, but it would decide whether TVs near a race can skip OBS. | Run leg D. |
| G8 | Lane poses make usable shots. | Night City is vertical: overpasses, buildings and signage occlude. Lanes give position and heading but not line of sight. | Generate candidates offline, then auto-reject occluded ones with raycasts from the observer client before any human review. |

## 4. Rulings and open questions

- **O-1 RULED (L307 addendum): deterministic commentary, no LLM, no Python required.** Radio OS is a loose guide.
  Lines are generated from facts by seeded templates, in the `life.voice` pattern (`ncm/core/life/voice.lua`):
  the same facts and the same seed give the same line. There is an **optional bridge out** that hands finished lines
  to a higher-end voice playback engine. Observer, captions and stock playback work without it. L221.5 stands.
- **O-2 (coder recommendation, awaiting the owner): one predicate, attached to a mode rather than an identity.**
  - The server holds `observer[pid] = { owner = <driver binding key>, since = t }`. Each consumer asks
    `NcmObserver.is(pid)`.
  - Every exclusion in §1.1 is enforced at its consumer. The bubble and `watched` deliberately say yes.
  - **Why a mode, not a role on an account:** ruling O-4 makes Observer something any player may run on demand.
    An account flag would also make "accidentally an observer" a persistent state, which is exactly what O-4 forbids.
  - **Why linked to the owner's binding:** an Observer can then never earn, enter or count anything. Its existence is
    still attributable, and per-player limits (one Observer each) have something to count against.
- **O-3 OPEN (owner undecided).** For the decision: in-game TVs need a reachable http(s) stream, **not** a public
  platform. A self-hosted relay (OBS → a small media server → an http page) keeps the loop private. Publishing to
  Twitch or YouTube is a separate, later choice.
- **O-4 RULED: Observer is a client mode.**
  - **Never accidental:** entering it is an explicit act. A connection is never an observer by default, by
    reconnect or by identity.
  - **On demand:** it runs only when its owner asks.
  - **Eventually everyone's:** each player may have their own. The owner's is the Racing Week broadcast and the
    tool that builds Observer.
  - Packaging stays separate per the standing rule.
  - Still unmeasured: whether one account can hold two connections at once (player + Observer) or whether Observer
    needs a linked second identity, as `ncmtester2` is today.
- **O-5 IDEA-023** is stale: `remoteCamera` shipped experimentally at .82. This document absorbs it.

## 5. The build order (slices 1-2 BUILT at L308, not deployed; 3-5 not built)

This slice uses the instrument before the television, in the same order as §0's closing lines.

1. **BUILT (L308), live test §OB2/§OB4.** **G1 + G2 on dev:** connect `ncmtester2` through the launcher, `ncm.tp` it to a running race far
   from the owner, and confirm that the cars materialise and race around it.
2. **BUILT (L308).** **The mode predicate (O-2), explicit entry/exit, plus a debug director:** `ncm.observe <race|racer|leader|battle>` moves the observer and
   attaches a chase or seat-offset camera.
3. **Ride-along for MPC gearbox work** (L306 S6 / IDEA-927): the first real use.
4. **Offline lane-camera candidates** with the occlusion pre-filter (G8), plus a yes/no review loop that stores
   approvals keyed by lane ID.
5. Only then: the director, deterministic commentary with the optional voice bridge, OBS overlays from NCM HTTP routes, and the TV loop (after G6).
