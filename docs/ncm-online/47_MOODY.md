# 47 - Moody: the volatility engine, and the seven-day week history rarely allows

> **STATUS: SPEC** - owner intent, captured 2026-10-04 (L309). **Not authorised; do not implement; do not contradict.**
> §2-§6 are coder notes: §2-§3 are evidence, and §4-§6 are PROPOSAL with no authority until ruled.
> **Supersedes doc 45 §0.5-§0.6 and amends §0.1** (owner ruling, L309 addendum; INDEX C-5 resolved). Q2, Q3 and Q5 were ruled the same day (§4).
> **§6 is authorised and BUILT (L310), governed by code** (`ncm/core/week/*`, ncm_world `week.lua`, schema 064); not deployed, no live PASS. Q6 defaulted to finales before every possible end.
> Authority map: [INDEX.md](INDEX.md). Builds on: [45_RACING_WEEK.md](45_RACING_WEEK.md) §G, §N, §O, §P. Ideas: IDEA-946 to IDEA-957.
> The spatial half (where SAFETY DRIVE puts barriers, what the proxies show at each place): [49_CITY_MEMORY.md](49_CITY_MEMORY.md) (L312, SPEC).

---

## 0. The owner's statement (verbatim, 2026-10-04)

> Yes. I think we finally have the whole machine. **Moody is not the seven-day system itself. Moody is the volatility engine that keeps every reconstruction from asking the same question under the same conditions.**
>
> The cleanest description is this:
>
> > **Racing Week was intended to last seven days. History has an enormous gravitational pull toward collapse around Day 3. Each reconstruction begins from the same historical starting point, but Moody perturbs the conditions of the experiment. The simulation, NPCs, and humans then determine what actually happens. Most worlds collapse around 72 hours. Exceptionally stable worlds push history farther. An extraordinarily rare world may complete all seven days.**
>
> That gives us four interacting layers.
>
> ### 1. The historical anchor
>
> Every reconstruction begins from the same place. Same Day 1. Same initial NPC population. Same racers and teams. Same opening championships. Same general enthusiasm. Same starting economy and institutional situation. Racing Week is officially supposed to be a **seven-day festival**. But something about this event is historically unstable. The braindance has reconstructed it over and over, and there is an enormous attractor around **72 hours**.
>
> That's the important change from our earlier conception. There isn't a supernatural rule saying: `at 72:00:00 → reset`. Instead, the historical conditions strongly tend to produce collapse there. Think of Day 3 as a valley in the probability landscape. Drop the simulation onto Day 1 and, unless something meaningfully changes its trajectory, it rolls toward that valley.
>
> Hence the familiar arc: **Day 1: admiration** -- Racing Week is incredible. **Day 2: conflict** -- The consequences become difficult to ignore. **Day 3: disgust / collapse** -- Night City has had enough. **RESET.** That's the canonical shape because that's what the system naturally produces. But it is no longer destiny.
>
> ### 2. The actual simulation
>
> This is what determines whether Racing Week deserves to follow that historical trajectory. We model the consequences of what actually happens. Not merely race results. The entire festival produces pressure. There can be underlying reservoirs for things like **safety, medical load, civic disruption, enforcement pressure, infrastructure strain, economic viability, institutional legitimacy, public sentiment, festival momentum**, and whatever else proves useful once we're actually implementing it.
>
> These are not independent health bars. They're coupled systems. A spectacular race may increase enthusiasm and legitimacy while also producing crashes. More races may strengthen the economy and festival momentum while exhausting infrastructure and increasing incident exposure. Stronger barriers may improve pedestrian safety while increasing costs and inconvenience. Aggressive enforcement may reduce some dangerous behavior while making public/racer sentiment worse. Huge payouts may keep grids full while encouraging increasingly desperate behavior.
>
> And critically, **NPCs participate in this causality without humans being present.** The server can run empty and Racing Week can still save or destroy itself. Humans are simply additional actors. Therefore: **12 humans ≠ bonus to survival.** Twelve careful racers could substantially improve the trajectory. Twelve absolute goblins could kill Racing Week by Tuesday evening. One extraordinarily consequential human could matter more than eleven others. That's exactly what we want.
>
> ## 3. Moody
>
> **Moody changes the playing field on which all of the above occurs.** Every reconstruction gets a run seed. From that seed comes a changing sequence of world conditions. At some cadence, perhaps initially every four hours, the simulation performs a ceremonial **Moody roll**. A D20 is a wonderfully legible first version. Some faces can be neutral. Some introduce a condition. Some remove or transform one. Some affect the frequency or character of subsequent rolls.
>
> Crucially, Moody isn't: **1–10 bad / 11–20 good.** Every interesting result should have consequences pointing in multiple directions. For example, imagine:
>
> > **DEVIL'S PURSE** -- Selected dangerous events receive enormous payouts.
>
> Fantastic. Racers suddenly have huge economic incentives. Grids become attractive. Racing Week gets attention. Billy's Board goes berserk. The official broadcast has a huge story. But MPCs with financial desperation now have reasons to enter races they otherwise wouldn't. Humans have the same choice. Faster/riskier behavior becomes economically rational. Moody hasn't damaged Racing Week. **Moody has changed the incentive landscape.** The simulation does the damage, or doesn't.
>
> Another roll: **SAFETY DRIVE** -- Additional barriers and pedestrian protection appear around eligible race corridors. Great for safety. But perhaps traffic disruption increases. Costs increase. Certain routes become less convenient. Civic pressure moves differently. Another: **PACKED CALENDAR** -- More races are scheduled during the next period. Great for competitors, fans, broadcast inventory and economic activity. Also more exposure hours in which something can go catastrophically wrong. Another: **QUIET HOURS** -- Race frequency falls. Bad for festival momentum. Excellent opportunity for medical/infrastructure/enforcement pressure to cool. Another: **CROWD SURGE** -- This is simultaneously fantastic news and terrifying news.
>
> And then Moody can affect **Moody itself**. **RESTLESS** -- Rolls now occur every two hours. Or perhaps: **STABLE WEATHER** -- Next Moody roll delayed. Or: **DOUBLE TROUBLE** -- Immediately roll twice. Now the volatility of the reconstruction itself is variable. That's very Gallardo Sim, very roguelite, and importantly it means **you cannot learn one optimal Racing Week strategy**.
>
> # Moody does not decide whether Racing Week survives
>
> This distinction needs to be sacred. Moody **creates conditions**. The simulation creates **outcomes**. The continuation system judges the resulting **world state**. So if Moody rolls Devil's Purse, it doesn't add `+20 collapse`. It changes payouts/incentives. Then perhaps NPCs enter dangerous races. Perhaps they drive beautifully. Perhaps there are no incidents. Perhaps a human causes a twelve-car catastrophe. Perhaps nobody takes the bait. Those actual events change the pressure model. That separation is what makes this simulation rather than disguised dice rolls.
>
> # The three-day anchor
>
> The first 72 hours remain enormously special. We should tune an unattended, average reconstruction so that **most runs die here**. Our provisional mathematical target was around: **~25% of completely unattended runs reach Day 4.** That's not sacred yet, but I like the neighborhood. It means Day 4 isn't mythical. People will know it exists. Screenshots will exist. Some players will have experienced it. But **Day 3 remains Racing Week's center of gravity**.
>
> And survival isn't simply: `pressure < 50 = continue`. The complete state generates a continuation probability. A horrible reconstruction approaching Hour 72 might have effectively a few-percent chance of surviving. A middling one might have 20–30%. A genuinely extraordinary reconstruction might have 60–70%. I'd be very reluctant to allow 100%.
>
> At noon, the tectonic event occurs. Normally the tape catches. Reality buckles. Reset. But occasionally... **12:00 becomes 12:01.** No congratulations screen. No achievement popup necessary. The race that's currently happening simply **keeps happening**. And somebody who understands NCM realizes: > Holy shit. > **It's Day 4.**
>
> # Days 4 through 7
>
> This is where the geological pressure increases. Surviving Day 3 does not mean the players solved Racing Week. They moved the fault line. The longer the festival continues, the harder maintaining it becomes. A rough initial natural progression could be: **Reach Day 4:** ~1/4; **Day 4 → Day 5:** ~1/3; **Day 5 → Day 6:** ~1/3; **Day 6 → Day 7:** ~1/4. That produces approximately **1 in 144 unattended reconstructions reaching Day 7** before we tune against real simulation data. That's rare enough to be folklore rather than Tuesday.
>
> And those probabilities are **outputs of the model**, not literal dice chances we hardcode independently. We're tuning the increasing day-pressure until an uncontrolled population produces approximately that distribution. Players and NPCs can push the distribution around. A phenomenal reconstruction might dramatically outperform baseline. A disastrous reconstruction may never realistically escape Day 3.
>
> # And reaching Day 7 isn't necessarily catching Nessie
>
> I particularly like separating: **seeing Day 7** from **completing Racing Week.** Day 7 should already feel impossible. But then you've still got to hold the entire deranged apparatus together until the scheduled conclusion. If it collapses six hours before completion? You saw the fish. You didn't land it. 🐟 Actually completing the seven-day Racing Week is **Nessie on the dock**. And because no deterministic golden path exists, it could remain legendary for a long time.
>
> # The player should not see the real equation
>
> This is where the presentation layer becomes essential. Internally, yes. Give us horrifying developer instrumentation. Graphs. Pressure reservoirs. Contributions. MPC effects. Moody modifiers. Historical trajectories. Continuation curves. Expected survival probability. Everything necessary to tune the simulation mathematically. **Publicly, absolutely not.** No: > RACING WEEK SURVIVAL: 73% -- That murders the premise.
>
> Players learn the state of Racing Week through **proxies**. The official broadcast mentions incident-free hours. News reports NCPD interventions. Race attendance changes. Billy's Board payouts become desperate. Hospitals become strained. Race calendars expand or contract. Barriers appear. Police presence changes. Sponsors disappear. NPC dialogue changes. Crowds grow. Crowds thin. Signs change. Garbage accumulates. Buildings and race sites change dressing. PA announcements change. The racing station sounds confident, then defensive, then perhaps triumphant. Talk radio becomes apoplectic. The news becomes increasingly grave. And Observer can simply **look at Night City**. That's the public instrumentation.
>
> # Which means "vibe" becomes a genuine simulation output
>
> This is probably the most important presentation concept. We shouldn't author: `DAY 1 = HAPPY` `DAY 2 = WORRIED` `DAY 3 = ANGRY`. Those are the **historically expected trajectories**, not mandatory skins. The actual world dressing should be driven by: **day + local state + global state + Moody conditions + recent events + public sentiment + enforcement + race activity**.
>
> Therefore an ordinary Day 3 looks like the Day 3 we've been imagining: police, hostility, torn banners, dwindling crowds, civic exhaustion. But an exceptional Day 3 might look completely different. The city is somehow **still having a fantastic time**. And that visual discrepancy tells an experienced player: > Something is happening.
>
> Likewise, Day 4 doesn't have one aesthetic. You could reach Day 4 because Racing Week has been extraordinarily safe and beloved. Or because huge money kept it alive despite everybody despising it. Or because enforcement effectively bubble-wrapped the city. Or because some bizarre Moody combination produced conditions nobody has previously seen. Those should be visually and auditorily distinct Day 4s.
>
> # And that makes Days 4–7 cheaper to author than they initially sound
>
> We don't necessarily need: **Day 4 content pack** **Day 5 content pack** **Day 6 content pack** **Day 7 content pack**. We need sufficiently rich **state vocabularies**. Crowd archetypes. Signs. Banners. Police configurations. Barrier configurations. PA lines. Civilian dialogue. Racer dialogue. Team dialogue. News lines. Broadcast lines. Sponsor states. VFX. SFX. World props. Gathering patterns. Then the simulation composes those according to state. The farther history gets from its usual three-day trajectory, the more procedural composition takes over. That's appropriate fictionally, too. **The reconstruction knows Days 1–3 extremely well.** Days 4–7 are increasingly strange territory.
>
> # Moody should also interact with people individually
>
> This is where the MPC system makes it considerably deeper. A Moody condition doesn't necessarily affect every racer identically. **Devil's Purse** lands. A wealthy, cautious Premier driver says: > No thanks. A financially desperate Street driver: > That's life-changing money. An aggressive racer: > Finally. A racer who witnessed a horrible crash yesterday: > Absolutely not. So the same world condition passes through **persistent personality, history, financial state, team situation, proficiency and relationships** before producing behavior. That's how Moody avoids feeling like Mario Party. The die doesn't move the pieces. **It changes what the pieces have reasons to do.**
>
> # The seven-day schedule therefore isn't really seven scripted days
>
> It's better described as: ### **Three days of historical gravity + four days of increasingly improbable alternate history.** Days 1–3 ask: > Can anything meaningfully change what happened? Days 4–6 ask: > If it can, how long can this new trajectory sustain itself? Day 7 asks: > **Can Racing Week actually become what it claimed it was going to be?** And completion answers a question the braindance has presumably been asking through reconstruction after reconstruction: > Was the collapse inevitable? Most simulations say: **yes.** Some say: **not quite.** Very few say: **apparently not.**
>
> And **Moody is why that answer never becomes a walkthrough.** You can learn the world. You can understand the pressures. You can discover that barriers matter, reckless driving matters, money matters, policing matters, crowds matter, schedules matter. But next reconstruction, the dice hit the table. **DEVIL'S PURSE.** The incentives change. Two hours later: **CROWD SURGE.** Uh-oh. Then: **RESTLESS.** The dice start rolling twice as often. Meanwhile eleven MPCs are making their own decisions, three humans are doing things you never predicted, it's raining, somebody has just put a Galena through a barrier, and the Night Market Rats are somehow producing the best racing anyone has seen all week.
>
> At that point, neither the players nor **you** can confidently say whether noon on Day 3 is going to be the end. And that's exactly the target. **Moody deals the weather of possibility. The simulation plays the hand. Night City shows you how it's feeling. And at 72 hours, history asks whether it still gets its way.** 🎲📻🏎️📼

## 1. Invariants (SPEC, restated from §0; do not contradict)

1. **Four layers, kept apart:** the historical anchor, the simulation, Moody, and the continuation judgement.
2. **Moody creates conditions, never outcomes.** No face adds or subtracts collapse. It changes rules, incentives
   or Moody's own cadence. *Sacred.*
3. **The continuation judgement reads world state** and produces a probability below 100 %. It is not a threshold.
4. **History pulls toward 72 hours.** About 25 % of unattended runs should reach Day 4, and about 1 in 144 should
   reach Day 7, with completing Day 7 rarer still. These are **tuning targets for model outputs**, never hard-coded
   odds.
5. **NPCs are causal without humans.** An empty server can save or destroy a run. Humans are more actors, not a
   bonus.
6. **No public meter.** Players read the run through proxies: broadcast, news, crowds, police, barriers, Billie,
   dialogue, dressing and Observer. Developers get every graph.
7. **Vibe is an output.** Day 1/2/3 moods are the expected trajectory, not skins. Dressing is composed from
   state vocabularies, so an extraordinary Day 3 or Day 4 looks and sounds different.
8. **A condition passes through each person** (personality, history, money, team, proficiency, relationships)
   before it changes behaviour.
9. **Survival is silent.** 12:00 becomes 12:01 and the race keeps happening, with no congratulations screen.

## 2. What already exists (evidence)

| Spec layer | In the tree today | Where |
|---|---|---|
| Historical anchor | One historical seed and genesis: the same cast and the same Day 1 every run. | `racing_week_genesis` (schema 062); L303; doc 45 §P |
| Historical gravity | `week.curve` CARRIER: tolerance 0.95 → 0 over 72 h by keyframes. | `ncm/core/week/curve.lua`; doc 45 §N |
| The simulation (one reservoir) | The live signal: a deviation pushed by facts from every resource, human or NPC alike, measured against an *expected* cost (0.5 crash DNFs per race on dev). It leaks back to the carrier at 8 % per hour. An NPC-only week tracks history. | `ncm:week:fact`; `week.curve.IMPULSE`; L302 |
| Institutions | Four latched announcement steps, fired early by a bad week. Police discretion is continuous from tolerance. | `week.curve.STEPS`; L302 |
| Money | The craze money carrier (×1.6 → ×0.95), moved by the live signal. | L303 |
| Proto-Moody | Seeded, auditable condition rolls with reset semantics: two slots a Day, a PK so a re-roll is a no-op. **Designed, not built.** | doc 45 §G |
| No public meter | `GlobalState.ncmWeek` publishes chapter, step, limit, rule, cap and `endsIn`, never the tolerance. | L302 |
| Per-person filtering | Paddock personality axes (FTB2), money (`npc_money`), team budgets, trajectory and voices. | doc 44; L240; L305 |
| Proxies | Speed-limit signs by Day, PA steps, police caps, money craze purses, voice topics. Not yet curve-driven: the crowd palettes and PA tone (doc 45 §N "not built"). | L301-L303 |
| Collapse | A dry-run archive into `<server>#R<n>` and the ending beat (countdown, freeze, KIMIKO). | doc 45 §P |

## 3. What the spec changes in code that exists (evidence)

1. **Run boundaries are calendar arithmetic today.** `week.clock` has `DAYS = 3`, and `runIndex = floor(dayNumber / 3) + 1`
   tiles time into fixed three-day runs from noon. A run that ends at 72, 96 ... 168 h needs its **start and end
   recorded as state** (`racing_week_run` already persists run state), with `hours` counted from the run's own opening.
2. **The carrier hits 0 at hour 72**, which *is* the deterministic `at 72:00:00 → reset` that §0 retires. The anchor becomes
   a pull: a landscape over 168 h whose valley sits at 72, and through which the judgement reads a probability.
3. **One number becomes coupled reservoirs.** Tolerance is a single deviation. The spec names nine reservoirs that
   interact. Doc 45 §G's rule "not backed by any system yet, so not proposed" still applies: a reservoir needs
   facts that feed it.
4. **Championships, finales and the ending count back from a known end** (finales from −165 min, the crown at hour
   72, the countdown in the last two minutes). With an uncertain end, each of these needs a rule (§4 Q2-Q3).
5. **The collapse is already a namespace switch with a dry-run mode.** That survives unchanged. Only *when* it fires
   changes.
6. **The continuation draw must stay auditable** (doc 45 §0.11): seeded from the run seed and the boundary,
   recorded with the probability and the state that produced it, INSERT IGNORE like §G's rolls.

## 4. Conflicts and questions (PROPOSAL; not resolved here)

- **C-5 RESOLVED (L309 addendum): supersede.** Was: **doc 45 §0 invariants 5 and 6** ("ends after Day 3"; "there is never a playable Day 4") are
  contradicted by §0 here. **Invariant 1** ("Day 1/2/3 emotional identities are fixed") is softened to "the expected
  trajectory". Invariant 2 ("random conditions modify play, never the Day's identity") is compatible. Q1 asks the owner
  to confirm that this document supersedes 5 and 6 and amends 1.
- **Q2 RULED: crowned at every collapse** (whatever the standings say when history catches; a completed run crowns at its scheduled end). Was: **Q2 Championships.** L303 crowns every series at hour 72, "a name to remember at shut down". If the official schedule
  is seven days, almost no run would ever crown.
  - *Recommendation:* keep the **hour-72 crown** as the scheduled Day 3 finale, the one most runs reach.
  - Days 4-7 run a second, rarer title crowned only at completion.
- **Q3 RULED: a countdown before every possible end; survival is silent.** Was: **Q3 The final minutes.** The current ending counts down the last two minutes. *Recommendation:* keep the countdown at
  every possible end (noon of Day 3 through Day 7), because it is suspense, not a verdict.
  - If the run survives, nothing happens at 12:00: no toast, no screen, as §0 asks.
- **Q4 Cadence.** §0's D20 every four hours, with self-modifying faces, supersedes doc 45 §G's two fixed slots a Day.
  §G's reset semantics and provenance carry over unchanged.
- **Q5 RULED: as recommended.** Was: **Q5 First reservoirs.** *Recommendation:* split today's tolerance into reservoirs that real facts already feed,
  and add the rest only when a system feeds them:
  - **safety** (crashes, civilian contact);
  - **enforcement** (speeding, wanted);
  - **momentum / economy** (races run, purses, grid fill);
  - **sentiment**, derived from the three above.
- **Q6 OPEN, defaulted at L310 to "before every possible end"** (it falls out of the provider; one rule changes it). **The double-points finales.** L303 schedules them back from hour 72 (street at -165 min,
  the Hypercar finale at -50). With the crown at an uncertain end, should they run before every possible end, before
  the historical end only, or be dropped?

## 5. Tuning (PROPOSAL)

§0's targets are distributions over unattended runs, so they need an **offline harness**: run the pure `week.*` model
plus `paddock.sim` facts for thousands of seeded empty-server runs, and tune the day-pressure until the histogram reads
about 25 % / 1/3 / 1/3 / 1/4. Each later rule change is re-checked against the same histogram, which joins the gate.
The Python engines stay a test oracle only (L221.5).

## 6. The build order (BUILT at L310 except where noted; not deployed)

1. Variable-length runs: start and end as state; `week.clock` counts from the run's opening. Default behaviour unchanged.
2. The continuation judgement at each noon boundary from hour 72 on: seeded, recorded, `dryrun` like the collapse.
3. The harness, then the carrier reshaped from "0 at 72" into a pull, tuned to the histogram.
4. Moody v1: the D20, the face table with reset semantics (§G's), provenance rows, self-modifying faces, and the
   developer view.
5. Faces that act through existing systems first: purse (money carrier), calendar density (Paddock scheduling),
   weather, police posture, fees. Per-NPC response through `paddock.attributes` and money.
6. Reservoirs (Q5), then state-composed dressing and voices (crowd palettes, PA, signs). Observer is the camera on all of it.
   *L310: reservoirs and the racing radio (`week.vibe`) are built; crowds, signs, PA tone and dressing are not.*
