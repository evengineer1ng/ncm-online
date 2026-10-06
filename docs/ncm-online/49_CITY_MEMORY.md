# 49 - City memory and civil engineering: the Campaign Scar Ledger, the Infrastructure Knowledge Ledger, and making the city survive the machine

> **STATUS: SPEC** - owner intent, captured 2026-10-04 (L312; civil engineering L313). **Not authorised; do not implement; do not contradict.**
> **Q1-Q4 RULED (L312 addendum, §6):** scar *clusters* keyed by segment + configurable radius + context, with accumulated burden; v0 is physical incidents only; scars end with the campaign and distil into knowledge; the first cycles are a hand-run experiment, with no automation until an intervention is shown to work. Q5 stays OPEN. **Civil engineering (§0.2, §7) is SPEC. C1-C4 RULED (L313 addendum, §8):** it joins the Engineering Architecture pass; anyone builds and anyone dismantles (on site, per component), modestly priced. **New SPEC (§8.2-§8.3):** the end-of-cycle Night City seed map (infrastructure + danger heatmap incl. free-roam incidents + pins), loaded at rollover by operator choice or random known/blank, announced in chat; infrastructure awareness believed in proportion to evidence.
> §2-§5, §7 and §8.4-§8.5 are coder notes: §2-§3, §7.1 and §8.4 are evidence; §4, §5, §7.2-§7.3 and §8.5 are PROPOSAL with no authority until ruled.
> Authority map: [INDEX.md](INDEX.md). Builds on: L46 (NCX venues), L47 (barriers), L307 ([46_NCM_OBSERVER.md](46_NCM_OBSERVER.md)), L309/L310 ([47_MOODY.md](47_MOODY.md): the 72-hour attractor, SAFETY DRIVE, the SAFETY reservoir, proxies), [45_RACING_WEEK.md](45_RACING_WEEK.md) §P (collapse as a namespace archive). Ideas: IDEA-973 to IDEA-1008. Shares its engineering grammar with [48_ENGINEERING_ENVELOPE.md](48_ENGINEERING_ENVELOPE.md).

## **NCM does not author what Day 3 looks like. NCM authors Day 1, records what happens, and lets Day 3 become the evidence.**

Doc 47 already rules *that* a week can outlive Day 3, *that* barriers can appear (SAFETY DRIVE), and *that* players read
the run through what the city looks like. This document is the spatial half that doc 47 leaves open: **where** the
damage happened, **what** the city shows because of it, and **where** the barriers belong next time. It adds no new
end rule. Collapse is still doc 47's.

---

## 0. The owner's statement (verbatim, 2026-10-04)

> Yes. I would **write this one down as an NCM design pillar**, because it connects Observer, Race Week, infrastructure, simulated MPC races, world dressing, safety, campaign duration, and eventually player organization. And critically, it gives you a cheap way of producing enormous visual change without authoring "Day 2 Night City."
>
> ## NCM Race Week: the city as a persistent accident ledger
>
> The central idea is: **We author the beginning. The simulation authors the aftermath.**
>
> NCM does **not** need three handcrafted versions of every race location. There isn't a pristine Day 1 map, a slightly damaged Day 2 map, and a Mad Max Day 3 map. There is one initial race-week intervention layered onto ordinary Night City.
>
> At the beginning of a campaign, perhaps almost nothing has been learned yet. NCM establishes races through the existing 35 nodes and their possible passages. Some important locations get race dressing: banners, temporary fencing, spectators, lighting, grid markings, barriers, marshal positions, whatever we're capable of placing. But coverage can initially be terrible. That's okay. In fact, **terrible coverage is useful information.**
>
> The first campaign could deliberately be close to naked Night City. Nobody knows yet that this particular intersection kills people. Nobody knows racers regularly overshoot this particular braking zone. Nobody knows MPCs arrive at this blind crossing at 170 km/h. We don't sit down with a map and try to predict all of that. **We run the city.**
>
> ### Observer becomes our motorsport laboratory
>
> This makes NCM Observer much more important than merely being a cool spectator client. You can run the dev server, put Observer into autonomous mode and simply **watch NCM happen**. Observer follows Race 14. Cuts to Race 27. Tracks a particular driver. Watches an intersection. Maybe you join one of the races yourself. Maybe you don't. The important thing is that the simulation does not require its creator to participate. You're effectively sitting in race control watching your little motorsport snow globe.
>
> And Observer should simultaneously be recording a spatial event stream:
>
> ```text
> CAMPAIGN 017
> DAY 1
> 14:37:22
>
> Race: R_204
> Passage: P_0813
> Vehicle: MPC_447
> Position: x/y/z
> Speed before impact: 163 km/h
> Impact severity: 0.74
> Impact type: environment
> Nearby protection: none
> Outcome:
>   vehicle disabled
>   civilian exposure: high
>   simulated casualties: 2
> ```
>
> We don't necessarily need all those fields immediately. The fundamental thing is: **what happened + where + when + how serious.** You already have reason to know where simulated cars are because they have to intersect the live world coherently. So collision location becomes another piece of provenance rather than an entirely separate simulation.
>
> ### Then we create the Campaign Scar Ledger
>
> This is the thing I would explicitly name and document. **NCM Campaign Scar Ledger.** It is authoritative server-side state describing meaningful physical consequences of the current Race Week. It should be **sparse**. Do not save the exact state of every object in Night City. Do not replicate the entire city. Do not attempt to preserve every piece of physics debris exactly where REDengine happened to throw it. Instead, meaningful incidents create or modify **scar records**. Something conceptually like:
>
> ```text
> SCAR
>   id
>   campaign_id
>   position
>   radius
>   category
>   severity
>   created_at
>   last_modified
>   related_race
>   related_passage
>   related_barrier
>   casualties
>   presentation_seed
> ```
>
> And nearby incidents can aggregate. If twelve cars hit approximately the same concrete wall, we don't necessarily need twelve separate permanent objects. That location becomes increasingly scarred.
>
> **Severity 0** Normal. **Severity 1** Scrapes, small debris, light barrier damage. **Severity 2** Visible impact damage, damaged fencing, larger debris. **Severity 3** Destroyed/displaced protection, heavy marks, wreckage. **Severity 4** Catastrophic location. Burned wreck, severe environmental dressing, emergency aftermath, memorialization where appropriate.
>
> Now Race Week has **physical memory**.
>
> ### The client doesn't need the entire ledger
>
> This is why I don't think the concept itself needs to be terribly heavy. The server holds the authoritative facts. When a client approaches a region, NCM asks: *What campaign scars are relevant around this player?* Perhaps there are 17. Those 17 are sent/materialized. The client renders the appropriate native assets, decals, particles, damaged barriers, debris, wrecks, etc. Leave the region and those visual representations can stream out. **The fact that they exist remains server-side.**
>
> That's very compatible conceptually with how Cyberpunk's world is already organized. Its world consists of nodes representing meshes, collision, lights, effects, sounds and other elements grouped into streaming sectors; current modding tooling can add custom sectors and many kinds of nodes. [Red Modding Wiki](https://wiki.redmodding.org/cyberpunk-2077-modding/modding-guides/world-editing?utm_source=chatgpt.com) And the available world-editing vocabulary is already tantalizingly close to what we'd want: static and dynamic meshes, decals, particles, effects, sounds, collision shapes, lights, entity records and other node types. [Red Modding Wiki](https://wiki.redmodding.org/cyberpunk-2077-modding/modding-guides/world-editing/object-spawner/supported-nodes?utm_source=chatgpt.com) So there is a plausible implementation path to investigate rather than this merely being design fiction.
>
> ### Day 1 → Day 2 happens automatically
>
> This is the gorgeous shortcut. Imagine the very first serious NCM campaign. **Hour 0** Night City looks normal except for whatever race infrastructure we've authored. Fresh barriers. Fresh banners. Clean concrete. No wreckage. No burn marks. No history. **Hour 6** Somebody has stuffed a Galena into the same barrier three times. That barrier looks battered. There's debris beside it. **Hour 14** Another collision happens there. The barrier is now heavily damaged. A wall behind it has a major impact scar. **Hour 22** A serious MPC accident occurs somewhere we didn't protect at all. Now there's a wreck there. **Hour 31** You return. You recognize the place immediately. But **it isn't the place you left.** And nobody authored `DAY2_NODE_14`. Race Week authored it.
>
> ### Debris is particularly valuable
>
> I'd be generous with persistent-looking debris because it's cheap visual storytelling. You don't need every fragment to be physically simulated indefinitely. The incident produces an aftermath composition. Broken barrier segment. Bumper. Glass/debris texture. Traffic cone knocked over. Tire. Burn mark. Maybe eventually some vehicle bodywork identifiable with the kind of car involved. Those can be deterministic dressing generated from the scar's category, severity and presentation seed. So when clients return, they don't necessarily see the *literal rigid bodies* generated by the original crash. They see a deterministic reconstruction of its aftermath. That's an important technical shortcut. **Persist meaning, regenerate presentation.**
>
> ### Native Night City becomes the art department
>
> And this is where your larger "decorate the simulation" problem suddenly gets cheaper. You're not creating thousands of custom destroyed-city assets. Cyberpunk already has a massive visual vocabulary. Current world tooling can place decals onto nearby surfaces and spawn particle/effect nodes, lights, sounds and meshes. [Red Modding Wiki](https://wiki.redmodding.org/cyberpunk-2077-modding/modding-guides/world-editing/object-spawner/supported-nodes?utm_source=chatgpt.com) So the challenge becomes: **Find the native vocabulary that communicates each scar class.** That's a finite art-direction task. Maybe we eventually build a library: `impact_light_01...08`, `impact_heavy_01...12`, `barrier_damaged`, `barrier_destroyed`, `debris_vehicle_light`, `debris_vehicle_catastrophic`, `burn_aftermath`, `emergency_aftermath`, `fatality_aftermath`, `crowd_incident`. Then the simulation composes those. That's miles cheaper than manually dressing hundreds of possible race passages.
>
> ### But the really important thing is that damage becomes data
>
> Because now we have answered: *Where should we put the barriers?* We don't know. **Race.** After Campaign 1, make a heatmap. There were 119 significant environmental impacts. Thirty-one happened around one particular turn. Twelve involved civilian exposure. Nine happened at one crossing. Four resulted in simulated fatalities. Well. There's your fucking level-design meeting. 😂 You and Observer look at that intersection and say: *Maybe we should put something here.* So Campaign 2 begins with additional barriers. Not because an omniscient game designer decided where barriers should go. **Night City taught us where they were needed.**
>
> ### That creates a second ledger
>
> And this one persists beyond individual campaigns. I would distinguish: **Campaign Scar Ledger** - Temporary physical history of **this** Race Week. Reset/decay substantially when the campaign ends. **Infrastructure Knowledge Ledger** - Long-term knowledge learned from **all** Race Weeks. This might contain:
>
> ```text
> PASSAGE P_0813
>
> campaign exposures: 9
> total races: 481
>
> impact clusters:
>   apex_outer: severe
>   braking_entry: moderate
>   pedestrian_crossing: catastrophic
>
> known interventions:
>   barrier_layout_01:
>     civilian incidents -62%
>     racer secondary impacts +11%
>
>   barrier_layout_02:
>     civilian incidents -91%
>     racer secondary impacts -4%
> ```
>
> Now NCM is learning how to operate motorsport in Night City.
>
> ### Which gives us the actual path to Day 7
>
> This is where your earlier "Day 7" idea stops being a joke about somehow surviving long enough. The natural state of Race Week is: **anarchy without organization.** Race. Crash. Kill people. Block roads. Destroy infrastructure. Generate police pressure. Piss everybody off. Eventually Night City says: *Enough.* Campaign ends around Day 3.
>
> But after repeated campaigns, players and MPCs develop **organization**. They learn dangerous locations. They erect barriers. They move spectators. They improve recovery. They change schedules. They stop sending traffic through particular crossings. They develop marshal systems. They perhaps eventually gain access to proper temporary road closures. So the exact same volume of racing causes **less external damage**. Now the city can tolerate another day.
>
> **Day 4 isn't unlocked. Day 4 becomes possible.** That's much better. And perhaps the first Day 4 happens almost accidentally. Observer reaches hour 72. The normal campaign-end conditions aren't met. Nothing happens. Clock keeps going. **DAY 4** Holy shit. Then eventually somebody gets Day 5. And years down the road, with mature infrastructure, organization and generations of learned race-safety design: **somebody keeps Night City racing for seven days.** That becomes a genuine civilization-level achievement.
>
> ### And barriers themselves can have history
>
> There's another layer I really like. Don't necessarily replace every damaged barrier magically. Let it accumulate. Day 1: **fresh concrete barrier**. Day 2: **three impact scars**. Day 3: **badly chipped, blackened, slightly displaced**. Maybe organizers repair it. Now: **old battered barrier + ugly replacement section**. That communicates organization too. A pristine city says nothing has happened. A destroyed city says chaos happened. A damaged-but-repaired city says: **People are trying to keep this thing alive.** That third state is where Days 4–7 should increasingly live.
>
> ### Observer therefore needs two modes
>
> I think your idea implies a really useful distinction. **Broadcast Observer** - The fun thing you watch. Cinematic cameras. Follow races. Switch cars. Watch battles. Maybe autonomous director logic eventually decides what's interesting. This is where you sit back and watch your weird city race itself. **Analysis Observer** - The development and organizational instrument. Collision heatmaps. Incident markers. Civilian exposures. Barrier interventions. DNFs. Congestion. Race-route density. Infrastructure failures. Maybe click a collision marker and jump directly to its location or replay its captured telemetry.
>
> So you're watching the broadcast and something awful happens: **WHAM.** You mark it. Later you open analysis: *Jesus Christ, everybody dies here.* And now that becomes engineering work for the *city*. That's a lovely parallel to the vehicle engineering system we were just discussing. **Car engineering:** make the machine survive and go faster. **Race engineering:** make the city survive the machine.
>
> ### And MPCs eventually participate
>
> This shouldn't forever require you personally to review a heatmap and place barriers. That's merely the earliest implementation. Eventually MPC organizers can consume the Infrastructure Knowledge Ledger. One MPC is competent. It recognizes: *P0813 has severe outside-apex exposure.* It orders barriers. Another is cheap. Doesn't. Another places inadequate barriers. Another has excellent safety engineering but spends a fortune doing it. Now organizations have styles. And players can participate in the exact same system. Somebody can literally become the person who makes Race Week safer. Not through a "+12 Safety" skill. By **putting the fucking barrier in the correct place.**
>
> ### Then your five-minute videos become incredibly powerful
>
> Because now you can actually document development *and* emergent history. Imagine the same camera location across several campaigns. **Campaign 1, Day 1** Normal intersection. No protection. Cars screaming through. Cut. **Campaign 1, Day 3** Wreck. Scorch marks. Debris. Destroyed street furniture. Cut. **Campaign 2, Day 1** Two concrete barriers have appeared. Cut. **Campaign 2, Day 3** One barrier badly battered. But no wreck behind it. Cut. **Campaign 5** Proper barrier line. Spectator area behind fencing. Race screaming past. Cut. **Day 4.**
>
> That communicates what NCM is without explaining a single equation. And you could keep doing this as a development diary. Not: *"Version 0.38 added persistent safety infrastructure."* Instead: **Watch this corner learn how not to kill people.** That's a video.
>
> ### It also connects directly back to the gearbox
>
> Which sounds bizarre until you follow the causal chain. You're still building the manual gearbox. Great. Eventually MPCs have manual-transmission proficiency. Different gearbox architectures affect acceleration, driver errors, shift behavior and car performance. That affects racing. Racing affects crashes. Crashes affect Race Week's physical environment. The environment affects subsequent races. Those races create engineering problems. Engineers modify cars. New cars create different accident patterns. Race organizers adapt infrastructure. And Observer watches the entire feedback loop.
>
> So these aren't actually two unrelated projects called **Manual Transmission** and **Day 3 Decoration**. They're different ends of the same simulation: **Machines create consequences. The world remembers consequences. People adapt.** That's NCM's procedural principle.
>
> And I would write one sentence in enormous letters at the top of whatever design document eventually captures this: **NCM does not author what Day 3 looks like. NCM authors Day 1, records what happens, and lets Day 3 become the evidence.**
>
> That is the shortcut. It gives you visual storytelling, temporal progression, safety gameplay, campaign difficulty, infrastructure evolution, Observer utility, development telemetry, MPC organization, player agency and a plausible route from chaotic three-day Race Weeks toward the mythical seven-day campaign from **one underlying system: remember where the cars hit things.** For a solo project, that's exactly the kind of system you want: one piece of machinery throwing shadows across half the game. 🌃🏎️💥📍

## 0.2 The owner's statement on civil engineering (verbatim, 2026-10-04, L313)

> Yes. **Call it civil engineering.** I actually think that solves a conceptual problem rather than creating another lane. You already have engineering. This is the same profession pointed outward. Vehicle engineering asks: *How do I arrange physical things so the car survives the race?* Civil engineering asks: *How do I arrange physical things so **Night City survives the race?***
>
> And I would resist turning it into a construction game with 600 decorative pieces. The Tears of the Kingdom lesson isn't "give people every possible object." It's **give people a tiny physical vocabulary with combinatorial consequences.**
>
> ### The civil-engineering kit could be shockingly small
>
> You might initially need only something like:
> - **Barrier**: heavy, stops/redirects cars, expensive and potentially dangerous if positioned badly.
> - **Fence**: catches debris/protects crowds, poor against direct vehicle impacts.
> - **Post/anchor**: structural connection point.
> - **Panel/gate**: closes an opening, can control traffic or pedestrian access.
> - **Deck/ramp**: spans gaps or redirects motion, with obvious potential for disastrous creativity.
> - **Cable/net**: connects anchors and catches things that barriers cannot.
>
> That's it. Those objects have **snap points**. Barrier to barrier. Fence onto barrier. Post onto barrier. Net between posts. Deck between supports. Rotate, extend, duplicate, snap. Now you've accidentally created a little structural language. A player can make:
>
> **wall**
> ```text
> ████████████████████
> ```
> **protected spectator area**
> ```text
> ROAD      █████████
>           │       │
>           │ CROWD │
>           │       │
> ```
> **chicane**
> ```text
> ──────────██────────
> ────██──────────────
> ```
> **catch fence**
> ```text
>        │~~~~~~~~│
> ███████│        │███████
> ```
> Or eventually your absurd Night City racing tube:
> ```text
>        ~~~~~~~~~~~~~~~
>      /                 \
> ████/                   \████
>     |       ROAD        |
> ████\                   /████
>      \_________________/
> ```
>
> You didn't author a "safety tunnel." **Someone invented one.** That's the part worth stealing from Tears of the Kingdom.
>
> ### But NCM should not know whether someone's construction is "good"
>
> This is where your existing simulation saves you from having to create a bullshit building-score system. Don't assign: *Barrier placement: +17 Safety*. Let the race answer. You already have vehicles with trajectories, collisions, incidents, casualties, DNFs, speeds and locations. So run them. If somebody builds a barrier arrangement and twenty races go through it with fewer civilian incursions: **it works.** If it prevents civilian casualties but causes cars to ricochet into oncoming racers: It solved one problem and created another. If someone builds an elaborate tunnel and cars survive inside it but the structure funnels a catastrophic wreck into a narrow corridor where recovery takes 45 minutes: That's data too. If someone puts a concrete barrier across the racing line: Cars hit it. No need for NCM to decide that the player is incompetent. **Physics files the complaint.** That's extremely important because it preserves the same philosophy you're discovering with car engineering.
>
> ### Civil engineering should use the same underlying engineering grammar
>
> This is where I wouldn't make it Lane Six. The same concepts recur: **geometry**, **mass**, **material**, **connections**, **load**, **damage**, **cost**, **availability**, **durability**. A gearbox has geometry and mounting points. A barrier has geometry and connection points. A gearbox receives torque. A barrier receives impact load. A gearbox overheats. A barrier degrades. A gearbox can be brilliantly or stupidly installed. **So can a barrier.** Eventually an engineering character could legitimately specialize: *Vehicle Engineering → Transmission* or *Civil Engineering → Race Infrastructure* without NCM needing two unrelated RPG systems.
>
> ### And don't make everyone a civil engineer
>
> This is where the multiplayer gets fascinating. You don't want every human to spawn with an infinite concrete-barrier gun. The ability can emerge naturally through access, experience, reputation, equipment, contracts, whatever engineering system you eventually settle on. But crucially, I wouldn't require the person to click: **Choose Class: Civil Engineer**. Someone should be able to discover it. They see a wreck. They acquire permission/access to infrastructure placement. They drag two barriers over. Next race doesn't kill anyone there. Observer notices. They do it again. Eventually the system has substantial evidence that this person builds useful infrastructure. **Congratulations. Apparently you're a civil engineer now.** That's much more NCM. Your profession emerges from what you actually do.
>
> ### Community construction changes the entire Day 4 question
>
> This is the really exciting multiplayer implication. With one human and hundreds of MPC race activities, the default trajectory might be awful. You can't attend everything. You can't fix everything. Race Week burns hot and dies young. Three days. Then five humans join. One mostly races. One loves engineering cars. One trades. One watches Observer. And one person becomes completely obsessed with the fact that **Westbrook Intersection #whatever keeps eating Galenas.** That person spends two hours building protection. Another human joins them. Suddenly a tiny public-works department has spontaneously formed inside your racing game. Nobody assigned them. And because their work actually reduces campaign externalities: **the entire server benefits.** That means Day 4 becomes a genuinely collective achievement.
>
> ### And 100 humans produces a completely different organism
>
> This is why I wouldn't balance campaign duration around player count with a simple multiplier. Let the population itself be part of the experiment. 100 humans could make Race Week dramatically worse. Everyone races. More crashes. More traffic disruption. More payouts pursued. Nobody maintains anything. **Night City melts. Day 2 ending.** Or 100 humans could become terrifyingly organized. Twenty people race. Ten engineer cars. Five organize recovery. Eight work infrastructure. People coordinate route schedules. Someone watches Observer and identifies dangerous areas. Others construct fixes. Human drivers might actually be safer than MPCs. Now they displace MPC entries from grids, reducing MPC chaos. Same 100 humans. Completely different outcome. That is *way* more interesting than: `campaign_health += player_count * 0.003`
>
> ### And yes, you've accidentally created a social deduction layer
>
> But I wouldn't formalize it. No "saboteur role." No Among Us UI. Let ambiguity exist. Someone builds:
> ```text
> ████
>    █
>    █████
> ```
> Cars keep dying. Was the builder: 1. incompetent? 2. experimenting? 3. working from bad Observer data? 4. protecting spectators at the expense of racers? 5. deliberately sabotaging Race Week? Nobody knows. And because infrastructure has attribution/provenance, people can investigate. *Who built this?* **EVEN_RACING, 14:22** *Why the fuck did you put that there?* 😂 That becomes governance. Maybe players dismantle it. Maybe engineering organizations establish standards. Maybe trusted builders gain broader construction permissions. Maybe servers eventually have an infrastructure approval process. You don't need to author a politics game. **Shared consequences create politics for free.**
>
> ### The most important limitation: construction should be expensive in friction, not UI misery
>
> I wouldn't make barriers infinitely available. Not necessarily because of money alone. Physical logistics can constrain them. A barrier has to come from somewhere. Maybe early NCM abstracts delivery. Later: **inventory → supplier → delivery → staging → installation**. A giant concrete barrier can't magically live in your pocket. Likewise, building the Night City Safety Tube should be theoretically possible but **civilizationally difficult**. Thousands of components. Huge expense. Massive logistics. Road access implications. Recovery implications. Maybe police/public response. And perhaps it works. That's the important thing. Don't say: *Maximum 20 barriers per player.* Say: *Sure. Build your tube.* Then let them discover why constructing 14 kilometers of motorsport-grade containment infrastructure in Night City is an absolutely psychotic undertaking. And if 100 humans somehow pull it off? **They earned whatever happens next.**
>
> ### Snapping is the killer UX feature
>
> This is probably the actual first technical prototype I'd want after basic placement. Not fancy construction. **Snap points.** Every infrastructure object exposes standardized connection sockets. Something roughly like:
> ```text
> BARRIER
>
> ●================●
> ↑                ↑
> A                B
> ```
> Bring another compatible object close enough:
> ```text
> ●================● ●================●
>                   ↓
>                SNAP
> ```
> Then:
> ```text
> ●================●================●
> ```
> Rotate around the joint. Stack compatible objects vertically. Connect fence to barrier-top socket. Connect post to barrier. Connect net between posts. With six primitives and standardized sockets, players get hundreds of structures. That is the procedural shortcut.
>
> ### Observer then becomes the civil engineer's primary instrument
>
> This gives Observer another fantastic reason to exist. Not merely: **watch races.** But: **understand the city.** Give the civil engineer layers. Collision heatmap. Speed heatmap. Civilian casualty heatmap. Debris trajectories. Barrier impacts. Traffic incursions. Spectator exposure. Recovery time. Maybe eventually predicted racing lines based on historical trajectories. Now someone can literally study a corner. They see:
> ```text
>              X X X X
>           X X
> ROAD ────────────────→
>              \
>               \ X
>                \ X X
> ```
> "Everyone leaves the road here." Then they go there physically. Walk around. Look at the architecture. Place infrastructure. Wait. Watch the next ten races. Come back to Observer. Did it work? **That's gameplay.** Not a management-menu minigame. Actual empirical civil engineering inside Night City.
>
> ### And your first campaign should probably be terrible
>
> I think your instinct here is exactly right. Don't solve Night City before anyone has raced it. Campaign Zero or Campaign One could have almost no protection beyond obvious grids/nodes. Let the MPCs loose. Let them be lunatics. Watch. Record. Your first civil-engineering dataset is produced. And the first footage becomes extraordinary because later you can revisit it: *Here's what NCM looked like before anyone understood how dangerous this corner was.* Then Campaign 2 has barriers. Campaign 8 has a proper protected section. Campaign 30 might have some community-designed monstrosity that nobody on Earth would have predicted. And perhaps eventually somebody realizes: *We don't actually need a giant tube. Three barriers, one catch fence and moving the grid by 18 meters solves 94% of this.* That's genuine design evolution.
>
> Which brings the whole thing back to your moral observation. You played NCM and realized: **We are absolutely fucking destroying Night City.** You could ignore that because it's a racing mod. Or you could script Night City to pretend racing is harmless. Instead you're saying: **No. That's actually happening.** So the simulation records it. The world visibly deteriorates. Race Week becomes increasingly untenable. Then you hand players some concrete, fencing, anchors, nets and Observer data and say: **Okay. What are you going to do about it?** That's civil engineering.
>
> And now the mythical seven-day Race Week isn't merely the championship's hardest difficulty. It's proof that a community managed to take an inherently irresponsible activity and construct enough organization around it that **Night City tolerated them for an entire week.** That's a hell of a communal victory condition.

---

## 1. The invariants (SPEC, distilled from §0)

1. **Author Day 1, not Day 2 or Day 3.** The only hand-authored layer is the opening race dressing. Every later state of a place is composed from what happened there.
2. **Sparse, not a replica.** The ledger holds meaningful places, not objects. Nearby incidents aggregate into one scar whose severity rises (0-4). No REDengine debris is persisted.
3. **Persist meaning, regenerate presentation.** A scar stores category, severity and a `presentation_seed`. Its aftermath is a deterministic composition, identical for every client and every visit.
4. **The server is authoritative; clients get only what is near them.** A client asks for the scars around it, materialises them, and drops them when it leaves. The fact stays on the server.
5. **Two ledgers, two lifetimes.** The **Campaign Scar Ledger** belongs to one run, with explicit reset or decay at its end (doc 45 invariant 11). The **Infrastructure Knowledge Ledger** persists across runs: where the impacts cluster, and which interventions measurably changed them.
6. **Damage is data, and it never decides the outcome.** Scars feed doc 47's SAFETY reservoir and its proxies. Moody creates conditions, the simulation creates outcomes, and the continuation verdict judges the state (doc 47). A scar is evidence, not a modifier.
7. **Provenance is preserved.** A scar from an observed (physical) incident and one from a simulated race are distinct classes (AGENTS.md).
8. **Organisation is visible.** Pristine, destroyed, and damaged-but-repaired are three readable city states. The third is where Days 4-7 live.
9. **Safety is placement, not a stat.** Organisers (MPC or human) improve the week by putting the barrier in the right place. There is no "+12 Safety".
10. **Observer has two modes:** Broadcast (watch it) and Analysis (heatmaps, incident markers, interventions, jump to the place).

---

## 2. What the tree already has (evidence)

| Pillar concept | Already in the tree | Where |
|---|---|---|
| The 72 h attractor; Day 4 possible, not unlocked; Day 7 rare | Ruled and built (timeline, verdicts, Moody) | doc 47 §0, §6; `ncm/core/week/*` (L310) |
| Barriers appear as a world response | The SAFETY DRIVE face; "barriers appear" as a proxy; "state vocabularies, not Day packs" | doc 47 §0 (lines 47, 77, 89) |
| A safety pressure fed by crashes | The SAFETY reservoir, fed by `race_crash`, `wreck`, `civilian_contact`, `chrome_impact`, `clean_race`. **Counts only, no position** | `ncm/core/week/curve.lua:28`, `:85-92` |
| Spatial incident records | Zero-fault incidents from x/y/z samples: delta-v bands ×1/×2/×4, object hit vs car contact vs person, one episode per crash within 15 m / 3 s | `ncm/core/competition/incidents.lua:12-29` |
| Incident → session event | The incident record carries x/y/z. **The session drops it**: neither the stored `r.incidents` entry nor the emitted `incident` event keeps a position. The race's gate progress (`r.progress`) is known here | `ncm/core/competition/incidents.lua:92`, `:115`, `:146` (records); `ncm/core/session/race.lua:328`, `:331`; `ncm/core/session/quali.lua:116` |
| Session event → week fact | `civilian_contact` for a person, `wreck` for a band-3 car contact. By this hop there is no position left to forward | `ncm/online/resources/ncm_league/server/race.lua:833-834` |
| Simulated-race crashes | `crash_out` at segment `s`, with no coordinates | `ncm/core/paddock/sim.lua:151`, `:183` |
| Placing barriers in the world | Server props from the platform's curated alias table (`barrier.road.jersey`, `barrier.concrete`, `barrier.roadblock.concrete`, `barrier.tire_blocker` …), stored in `venue_point` and re-spawned at start | `ncm/online/resources/ncm_world/server/venue.lua:14-17`, `:258`, `:289` |
| Venues as temporary city transformation | NCX venues: barriers, controlled intersections, spectators, dressing | DECISION_RECORD L46, L47 |
| Run-scoped state with an archive | Collapse switches namespace to `<server>#R<n>`, with a dry-run mode | doc 45 §P; doc 47 §2 |
| Observer as an instrument | The director takes incidents as an input; Observer as the primary development instrument | doc 46 §0.8, §0 close; `ncm/core/observer/director.lua` (L308) |

**A naming collision.** `life.climate` already "scars the baseline" when a district leaves a crisis (DECISION_RECORD
L240, `life.climate`). That is a district-axis scar. This document's term is always **campaign scar**.

---

## 3. Gaps (evidence)

1. **No position reaches the week, and it is lost in two hops.** The incident record is spatial. The core session drops x/y/z when it stores and emits the incident (`session/race.lua:328`, `:331`; `quali.lua:116`), and the league host then sends a bare count (`race.lua:833-834`). Both hops must carry it. *(Corrected 2026-10-04: the first capture named only the league hop.)*
2. **Simulated crashes have no coordinates.** They have a segment index on a route. A position means mapping `s` onto that route's geometry. Until then, a simulated scar can be placed only at segment resolution and must say so.
3. **There is no ledger store.** No table, no aggregation, no region query, no archive at collapse.
4. **Materialisation is barrier-only today.** The curated alias table has barriers, arrows, checkpoints and lamps. Decals, particles, scorch marks and wreck meshes are not in it. **The Red Modding wiki claims in §0 are unverified third-party claims.** They describe single-player world editing (ArchiveXL sectors, the object spawner). They say nothing about what OPEN//77 lets a server spawn per client. Check them against the build-pinned official API cards before relying on them (AGENTS.md).
5. **Prop scale is untested.** E19 (N barriers along a course; stream-in at speed; which aliases block a car) has never run. A scarred city multiplies that load.
6. **"Damaged barrier" is not a prop state.** A barrier is spawned or not spawned. Battered, displaced and repaired states must be composed (offset, rotation, a second alias, debris beside it) or found as distinct assets.
7. **No Analysis view.** Observer's director is in the tree; heatmaps and incident markers are not.
8. **Knowledge across runs has no home.** Doc 45 §P keeps anchored cars and knowledge. Nothing records place-knowledge.

---

## 4. A minimal ladder (PROPOSAL, no authority; amended to the L312 rulings)

Each rung is useful alone and logs before it changes anything. The rulings in §6 constrain every rung.

- **S1 - carry the place through both hops.** Keep x/y/z, the gate interval (`r.progress` → `r.progress + 1`), kind, band, delta-v and `provenance = "physical"` on the stored incident and the emitted event (`session/race.lua:328`, `:331`; `quali.lua:116`). Forward them on the week fact (`ncm_league/server/race.lua:833`). Log only. No behaviour change.
- **S2 - scar clusters (physical only).** A pure core module with tests, following `competition.incidents`. Same course segment + within a configurable radius (start 8-12 m) + compatible context (kind; a z tolerance so stacked decks never merge) = same cluster. `burden += incident severity × consequence modifiers`; configurable thresholds turn burden into levels 1-4. Stored under the run namespace.
- **S3 - Analysis Observer, offline first.** Render the clusters and the S1 log over the map, as an HTML page or an image, before any in-game view.
- **S4 - Campaign A.** Little or no intervention. Record. Watch. Inspect the heatmap.
- **S5 - Campaign B.** The owner places a few barriers by hand (`/ncm.au dress`), recorded as interventions. Run again and compare the same clusters. The question: did the bad outcome materially fall?
- **S6 - collapse distils.** Archive the run's clusters with the run (doc 45 §P). Fold them into the Infrastructure Knowledge Ledger: traversals, significant impacts, civilian exposures, severe incidents, protection present. The next campaign starts visually fresh.
- **S7 - materialise with what exists.** Cluster levels shown with the current barrier and fence aliases only, region-scoped through the venue spawn path. Gated on an E19-style scale check.
- **S8 - the native aftermath vocabulary.** After a platform spike on what a server can place per client: the `impact_*` / `debris_*` / `burn_*` library from §0.
- **S9 - automation.** SAFETY DRIVE and MPC organisers read the knowledge ledger, **only after** S5 has shown that an arrangement reduces the bad outcome (§6 ruling 4).
- **S10 - simulated scars.** Once route geometry can place a simulated incident on a plausible point along its segment, with `provenance = "simulated"` (§6 ruling 2).

---

## 5. Open questions (for the owner)

- ~~**Q1 - aggregation and severity.** What radius makes "the same wall"? How do incident bands (×1/×2/×4, wreck, person) climb the 0-4 scale? Is severity 4 reachable only by a person contact or a wreck?~~ **RULED, §6.1-6.2.**
- ~~**Q2 - simulated scars.** Do scars from off-screen simulated races materialise physically, or only feed data (heatmap, SAFETY) until a segment→position mapping exists?~~ **RULED, §6.3.**
- ~~**Q3 - the end of a run.** Full reset of the scar ledger at collapse, or decay? What exactly passes into the knowledge ledger? This is the same question doc 48 IDEA-968 left open for engineering, and doc 45 §P answered for cars.~~ **RULED, §6.4.**
- ~~**Q4 - who places barriers first.** The owner by hand (`/ncm.au dress`), the SAFETY DRIVE face reading the knowledge ledger, or MPC organisers? The paste suggests that order over time.~~ **RULED, §6.5.**
- **Q5 - fatalities and memorials (OPEN).** Are simulated casualties and memorialisation (severity 4) in scope, and in what tone? §6.4 fixes one part: a surviving memorial or famous crash site would be an explicit later rule, never accidental persistence.

---

## 6. Owner rulings on Q1-Q4 (L312 addendum, 2026-10-04)

### 6.0 The owner's words (verbatim)

> I'd make a campaign scar cluster, not nearest crash within 10 m. The eventual correct unit is probably road-relative, because two crashes 6 m apart but on opposite decks of an interchange absolutely aren't the same place, while crashes 20 m apart along the same outside wall might be one hazard. Real crash-hotspot research runs into exactly this problem, and network-based clustering tends to be more meaningful than naïve Euclidean proximity. [Sage Journals](https://journals.sagepub.com/doi/10.1177/0361198118796071?utm_source=chatgpt.com)
>
> But v0 does not need fancy DBSCAN. Use something deliberately crude: **same passage/segment + nearby position + compatible impact context = same scar cluster.** I'd start around perhaps 8–12 m as an experimental radius, but make it configuration, not doctrine. Observer is precisely how you'll discover whether that's visually ridiculous.
>
> And I wouldn't map one crash severity directly to scar level 0–4. Make scar severity accumulative. A severe crash can immediately produce a severe scar, but repeated moderate crashes should also build one: `scar burden += incident severity × consequence modifiers`. Then thresholds turn burden into presentation levels 1–4. That matters because ten cars hammering the same barrier is visually different from one minor tap. Severity-weighted crash clustering is also a well-established way to distinguish genuinely important hotspots from mere crash counts. [PubMed](https://pubmed.ncbi.nlm.nih.gov/34612168/?utm_source=chatgpt.com)
>
> But not in the first implementation. You've just discovered the reason. Live incidents already have XYZ. Simulated incidents only know the route segment. Don't contaminate the beautifully simple first test by inventing approximate positions. **City Memory v0 should be physical/live incidents only.** Later, once route geometry can map a simulated incident onto a plausible point along its segment, simulated races absolutely should participate. Otherwise Observer will eventually watch a city in which off-screen MPCs supposedly killed six people at an intersection that remains mysteriously pristine. And importantly, provenance survives: **physical**, **simulated**. Same philosophy you've already been using elsewhere.
>
> I feel quite strongly about this one. **At collapse/reset, the Scar Ledger ends with the campaign.** Don't carry the burned Galena into Race Week 12 just because Race Week 11 ended with it there. That eventually makes Night City look permanently post-apocalyptic. Instead, archive the campaign ledger as history. Then distill it into the Infrastructure Knowledge Ledger: 18 races traversed this location. 7 significant impacts. 3 civilian exposures. 2 severe incidents. No protection present. Next campaign begins visually fresh... …but somebody has learned: put a fucking barrier there. That's your mixture of permanence and impermanence again. **The scar is temporary. The reason the barrier exists is permanent.** That's vastly more meaningful. You could eventually allow a tiny number of exceptional scars to survive for narrative reasons, memorials, famous crash sites, whatever, but that should be an explicit later rule rather than accidental database persistence.
>
> Absolutely. **Don't automate away the experiment before you've watched it.** The first cycle should be almost scientific: Campaign A: little/no intervention. Observer records incidents. You watch. Heatmap appears. You inspect it. Campaign B: you make a few interventions. Run again. Did they work? That's important because this isn't just developing NCM. You're going to learn what the rules of NCM safety engineering actually are. Only after you've demonstrated: *crashes happen here → this barrier arrangement materially reduces the bad outcome* should SAFETY DRIVE or NPC organizers begin making those decisions themselves. Otherwise we're teaching NPCs a system whose semantics we haven't established.

### 6.1-6.5 The rulings, distilled

1. **Q1a RULED - clusters, not nearest-crash.** v0 key: same course segment + within a radius + compatible impact context. The radius is configuration (start 8-12 m), not doctrine. Observer judges it visually. A road-relative (network) unit is the eventual target. v0 is not DBSCAN. *Coder note:* NCM has no `passage` object in code. The live race's segment is its gate interval (`r.progress`). Stacked decks need a z tolerance in "compatible context".
2. **Q1b RULED - severity accumulates.** `burden += incident severity × consequence modifiers`. Thresholds turn burden into levels 1-4. One severe crash can reach a high level at once, and repeated moderate ones climb there too. Both the thresholds and the modifiers are configuration.
3. **Q2 RULED - v0 is physical (live) incidents only.** No invented positions for simulated crashes. They join once route geometry maps a segment to a plausible point. Provenance stays `physical` | `simulated`.
4. **Q3 RULED - the scar ledger ends with the campaign.** It is archived with the run as history and distilled into the Infrastructure Knowledge Ledger. The next campaign starts visually fresh. *The scar is temporary; the reason the barrier exists is permanent.* Any surviving scar (memorial, famous crash site) is an explicit later rule, never accidental persistence.
5. **Q4 RULED - the experiment is run by hand first.** Campaign A has little or no intervention: record, watch, inspect the heatmap. Campaign B has a few owner interventions: run again and compare. SAFETY DRIVE and NPC organisers may decide placement **only after** an arrangement has been shown to materially reduce the bad outcome.

---

## 7. Civil engineering (L313; coder notes)

The owner names the profession behind §0's barriers: **civil engineering, the same engineering pointed outward.** Car
engineering makes the machine survive the race; civil engineering makes Night City survive it. §0.2 is SPEC.
Distilled:

- **A tiny kit with combinatorial consequences:** barrier, fence, post/anchor, panel/gate, deck/ramp, cable/net. Not 600 pieces.
- **Snap sockets** are the first prototype after basic placement.
- **The race is the judge.** No placement score. Physics files the complaint.
- **One engineering grammar** shared with doc 48 (geometry, mass, material, connections, load, damage, cost, availability, durability). Not a sixth lane.
- **The profession emerges from evidence.** No class pick. Access comes through permission, experience, contracts or equipment.
- **The population is part of the experiment.** No player-count multiplier. Day 4 becomes a collective achievement.
- **Attribution, not a saboteur role.** Every structure says who built it and when. Governance emerges from shared consequences.
- **Friction, not caps.** Logistics (supplier → delivery → staging → installation) constrain building, not a per-player limit. "Sure. Build your tube."
- **Observer layers for the engineer:** collision, speed, casualty, debris, barrier impacts, incursions, spectator exposure, recovery time.

### 7.1 What the tree already has (evidence)

| Concept | In the tree | Where |
|---|---|---|
| Placing a structure | Owner-only admin command `/ncm.au dress <alias> [yaw] [radius]`, with undo, clear and up/down | `ncm/online/resources/ncm_world/server/venue.lua:14-20` |
| Persisting it | `venue_point` (server, venue, kind, key, x/y/z, heading, `meta_json`). **No author or placed-at column.** Attribution would live in `meta_json` or a new column | `ncm/online/resources/ncm_league/server/schema/007_venue_authoring.lua:9-21` |
| The platform's prop vocabulary | In a 2026-09-25 server backup: `barrier.concrete`, `.road`, `.road.jersey`, `.roadblock.concrete`, `.tire_blocker`, `.hesco`, `.pedestrian`, `.gate.swinging`, `.blockade.*`; `fence.railing*`, `fence.wire.reinforcement`; `street.electrical_pole`. **No deck, ramp, net or cable**, and no sockets. That snapshot is not the build-pinned API card | `tools/open77/backups/server-20260925T190102Z/resources/system/open77_admin/shared/config.lua:287-297` |
| Does a placed prop stop a car? | **Unknown.** E19 ("which `barrier.*` aliases block a car") has never run | DECISION_RECORD E19 |
| A shared engineering grammar | Doc 48's envelope (mass, packaging, connections, load), SPEC; Engineering Architecture pass queued after the manual | doc 48; L311 Q5 |
| Judging by outcome | Scar clusters and the knowledge ledger (§6) are exactly the "did it work" measurement | §4 S1-S6 |

### 7.2 A first civil-engineering rung (PROPOSAL, no authority)

It slots into §4 at S5, the hand-run Campaign B, and changes nothing before it:

- **CE0 - run E19.** Place each `barrier.*` / `fence.*` alias on a test road and drive into it. Record which ones collide, what they do to the car, and whether they survive. Everything else depends on the answer.
- **CE1 - attribution on what exists.** Write the author and placement time into `meta_json` when `/ncm.au dress` places something. Record each as an intervention against the nearest scar cluster.
- **CE2 - snapping as pure placement math.** A core module that snaps a new prop's end socket to a neighbour's (per-alias socket offsets, measured in CE0). Owner-only, still through `dress`.
- **CE3 - the kit's missing pieces** (post, deck/ramp, net): a platform spike, the same family as §4 S8.
- Player access, logistics and the emergent profession wait for the Engineering Architecture pass (doc 48 §5) so that one grammar serves both.

### 7.3 Open questions (for the owner)

- ~~**C1 - sequencing.** Does civil engineering enter the Engineering Architecture pass (doc 48 §5) as its second domain, or wait until City Memory v0 has produced a heatmap?~~ **RULED, §8.1.1.**
- ~~**C2 - who may build first.** Owner-only through `dress` for Campaigns A/B, as Q4 implies? When do testers get access, and through what (permission, contract, reputation)?~~ **RULED, §8.1.2.**
- ~~**C3 - removal and governance.** Can anyone dismantle a structure in v0, or only its builder and the owner?~~ **RULED, §8.1.3.**
- ~~**C4 - cost.** Are barriers free while the experiment runs, or priced in the NCM economy from the start?~~ **RULED, §8.1.4.**

---

## 8. Owner rulings on C1-C4, and the Night City seed map (L313 addendum, 2026-10-04)

### 8.0 The owner's words (verbatim)

> 1. civil emgineering joins engineering architecture pass 2. should be anyone can build , costs in game money though. we need to keep a rich enough sim and understanding of where people have placed down barriers and such around night city, and how their contributions are affecting races. at the end of race week cycle, export the seed map of the night city that resulted, so it could be dressed up again with same placed infrastructure as a day one start in the cycle. the server operator can load the preferred seed (people in chat should see what seed loads/loaded) or a random mechanism that selects between known seed or blank slate, randomly, also visible publicly at rollover. the seed map should retain understanding of how safe night city was kept with a heat map of danger aka documented incidents (track player general driving incidents , not just racing) and an overlay of infrastructure pins, showing at a glance how frequently dangerous a place is and how much infrastructure exists around it. race sim system needs to draw awareness of infrastructure from observed racing, which ncm observer and player actively playing will handle over time, more evidence is more concretely believed, not swayed by initoal projections based on little data, mord wild west at the start. 3. dangerous, but say anyone who can afford to and has the time to go to every infrastructure component itself and disassemble it. xommunity will decide their fate , maybe they are leondardo da vinci taking things down to design the safest racing intersection ever seen  or theyre sabotaging the campaign 4. priced but modsestly

### 8.1 The rulings, distilled

1. **C1 RULED: civil engineering joins the Engineering Architecture pass** (doc 48 §5) as its second domain. One grammar serves cars and city.
2. **C2 RULED: anyone can build, for in-game money.** NCM keeps a rich record of who placed what, where and when, and of **how each contribution affects races**. *This widens Q4 (§6.5):* Campaign B's interventions are no longer owner-only. Any player's placement is an intervention to measure. The rule against **automated** placement before evidence still stands.
3. **C3 RULED: anyone can dismantle, if they can afford it and spend the time.** They must physically go to **each** component and take it apart, one by one, with no remote or bulk removal. The community decides a structure's fate. NCM does not judge Leonardo from saboteur; the record and the races do.
4. **C4 RULED: priced, but modestly.** Placement and dismantling both cost money. Friction comes from cost, travel and time, not from caps.

### 8.2 New: the Night City seed map (SPEC)

**At the end of every Racing Week cycle, NCM exports the resulting city as a seed map.** It is the infrastructure players built, captured so a later cycle can start Day 1 dressed with it.

- **Contents.**
  - Every placed infrastructure component (kind, position, heading, builder, placed-at).
  - A **danger heatmap** of documented incidents. **This includes general player driving incidents, not only racing.**
  - An **overlay of infrastructure pins.** One glance shows how dangerous a place was and how much protection sits around it.
- **Loading at rollover.**
  - The server operator loads a **preferred seed**.
  - Or the operator enables a **random mechanism** that picks between the known seeds and a **blank slate**.
  - Either way, **the choice is public**: chat shows which seed is loading, then which seed loaded.
- **What it is not.**
  - Scars do not carry over. Q3 stands, and the visual aftermath still ends with the campaign.
  - What carries over is the *built* city plus its danger record.
  - The seed is an explicit, operator-visible reset choice (doc 45 invariant 11), not accidental persistence.

### 8.3 New: infrastructure awareness from evidence (SPEC)

**The race simulation learns how infrastructure changes outcomes only from what was observed.**
- Observer and actively playing players produce that evidence over time.
- **More evidence is believed more firmly.** Small samples move belief only a little. No initial projections are seeded from thin data.
- Early cycles are **the wild west**: the simulation acts as if it knows nothing about barriers until the races teach it.
- This governs how simulated races account for infrastructure. It does not let anything place infrastructure (§8.1 ruling 2).

### 8.4 What the tree already has (evidence)

| Need | In the tree | Where |
|---|---|---|
| General driving incidents (not racing) | Free-roam position/speed samples already reach the server (`ncm:speed:sample`: position, speed, heading, time). They feed `speeding` facts only. **No crash detection runs on them.** The incident detector is a pure module already shared by three hosts | `ncm/online/resources/ncm_speed/server/speed.lua:5`, `:74`; `ncm_league/server/competition.lua:10`, `telemetry.lua:12`, `ncm_paddock/server/bubble.lua:26` |
| A public rollover moment | The rewind already sends a notification and a chat line to every player (KIMIKO) | `ncm/online/resources/ncm_world/server/week.lua:225-248` |
| Run boundaries | Collapse re-keys run-local state to `<server>#R<run>` | `ncm/core/week/collapse.lua:4-5`, `:20` |
| Placed infrastructure as data | `venue_point` rows re-spawned at start. They are per venue, with no author column | schema 007; `venue.lua` |
| Simulated crash risk | A per-segment hazard from driver stats and weather. **Infrastructure plays no part** | `ncm/core/paddock/sim.lua:9-10`, `:151` |

### 8.5 Consequences for the ladder (PROPOSAL, no authority)

- **S1 widens:** run the incident detector on free-roam samples too, with `context = "freeroam"` beside `race`, and provenance `physical`.
- **CE1 becomes player placement:** a paid placement and a per-component, on-site, paid dismantle, both attributed and logged as interventions.
- **S6 grows the export:** at collapse or completion, write the seed map (components, heatmap, pins) as its own record outside the run namespace, so it survives the rewind.
- **New, at rollover:** an operator setting `seed = <id> | blank | random(known + blank)`, with the result announced in chat before and after loading.
- **New, the evidence model:** per cluster and arrangement, outcome rates with a confidence that grows with the number of observed traversals (for example a shrinkage estimate toward "no effect"). The simulation's hazard reads it once confidence is meaningful.
