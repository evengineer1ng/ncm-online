# Engineering — RPG progression, research, crafting and player manufacturing

> **STATUS: SPEC** - owner intent, captured and **NOT authorised for implementation**. Do not build from it; do not contradict it. Covers: *engineering as a career*
> Authority map: [INDEX.md](INDEX.md) - classified 2026-09-24 (L125)

**Status: SPECIFICATION CAPTURED 2026-09-23. Nothing built, nothing authorised.** Spec 2 of the owner's
batch; an addendum follows, then a final parts spec. Capture-only.

**The spec explicitly asks for a proposal back** — the five-discipline ontology, the skill families, the state
model, project state, fabrication architecture, seams, visibility, and the smallest first slice. That is
owed once the batch is closed, and is recorded as `IDEA-269` so it is not lost.

> **Engineering should be a genuine optional career, beginning very early and potentially becoming extremely
> deep, without becoming an XP grind or a prerequisite for enjoying cars and racing.**

A player must be able to ignore engineering entirely and still race, buy, trade and belong. Another must be
able to disappear into it for hundreds of hours and become *known for being good at something*.

---

## The founding rejection

Not `Level 1 → 2 → 3`. Not `0 / 10,000 XP`.

**Racing must not make you a better engineer.** Engineering makes you a better engineer — repairing develops
repair capability, fabricating develops fabrication capability, inspecting develops diagnostic capability,
installing develops integration capability. Repetition, practice, relevant work, failure, time, resources and
prior knowledge all matter. The system remembers what the player has actually *demonstrated*.

Player-facing visualisation may come later; **the authoritative state need not be levels or bars.**

## Three orthogonal axes

The owner's own closing note resolves the structural ambiguity, and it is the load-bearing decision in this
spec:

| Axis | Answers | Example |
|---|---|---|
| **Discipline** | what kind of engineering are you doing? | Diagnostics vs Fabrication vs Repair |
| **Skill within it** | what capability have you developed? | reverse engineering; process control; restoration |
| **Mechanical family** | what machinery are you experienced with? | Power Unit vs Brakes vs Suspension |

So one engineer is deep in **Diagnostics → Reverse Engineering → Power Unit**, while another is exceptional at
**Fabrication → repeatability/process → Suspension**.

**Reverse engineering is a skill under Diagnostics, not a sixth discipline.**

### The five proposed disciplines

1. **Diagnostics / Inspection** — understanding machinery: identifying components, evaluating them,
   determining compatibility, eventually condition and faults, characterising output, destructive reverse
   engineering.
2. **Maintenance / Repair** — keeping things functional and eventually restoring faults. *Explicitly distinct
   from crafting.*
3. **Installation / Integration** — removing, fitting, configuring and validating components in compatible
   vehicles. Where the compatibility architecture becomes gameplay.
4. **Fabrication / Crafting** — creating a physical asset from an **existing design**. Not inventing the design.
5. **Design / Manufacturing** — the deepest lane: one-off success → repeatable production → eventually design
   creation itself.

Proposed, not sacred. **If there is a compelling reason to restructure, report it before implementing an
alternative.**

### The resolution rule for skills

Avoid both extremes: `ENGINEERING = 74` is too shallow; `LEFT-REAR CALIPER KNOWLEDGE = 22` is spreadsheet
disease. **The broad mechanical family is the lowest specialisation level for competency.** Familiarity with
a *specific* design may exist separately as knowledge — that is not the same as a permanent skill stat per
item, and there must never be a `Makigai KX-17 Pump Skill`.

## Ceilings, and why they matter

**Every competency has a finite ceiling.** Repetition produces diminishing progression toward a meaningful
maximum. Numbers undecided.

> The first person to the summit gets a head start, **not a patent on Mount Everest.**

Mastery does not eliminate uncertainty — a master is dramatically more reliable, not mathematically perfect.
After the ceiling, differentiation comes from accumulated knowledge, accessible designs, tooling, capital,
sourcing relationships, market access, reputation, production choices and sheer history. *Richer than raising
the cap from 100 to 110 every season.*

## Time is a universal engineering resource — applied by purpose

Time constrains engineering, **but not uniformly**:

- **Research, reverse engineering, fabrication, design, manufacturing** use authoritative elapsed time as an
  economic and progression constraint. This is what stops capital from instantly consuming progression.
- **Ordinary repair and servicing compress aggressively.** A player standing beside another's broken car must
  not be told *"repair completes in 2 h 47 min"* — that destroys the social interaction. Enough friction to
  feel like an engineering act; not realistic wall-clock duration.

> **Do not apply one universal timer formula to every engineering activity.**

## Asynchronous projects

Some work is a persistent **project**: legitimate start → authoritative inputs/state/seed committed → time
passes → the player races, trades, logs out → the project becomes ready to resolve.

**Not mobile-game timer hell.** Timers exist because industrial throughput needs a real constraint, not to
make people watch clocks.

Investigate whether one project abstraction serves reverse engineering, fabrication, research, design and
manufacturing **without dragging repair into the same slow model**.

Preserve the possibility of **workshop capacity** — a beginner must not be able to launch 900 analyses
because they can afford 900 components. No slot mechanics committed; just avoid an architecture that
accidentally assumes unlimited parallelism.

## Destructive reverse engineering

Acquire a component → choose destructive analysis → the physical asset is **irreversibly consumed** → an
analysis project begins → time passes → **knowledge** is gained.

> **The economic output is KNOWLEDGE. This is not salvage, not recycling.**
> Never `destroy pump → receive metal + electronics`.

Sophistication of the studied component drives difficulty and duration; the analyst's competency drives what
they extract and how efficiently. A novice studying an extraordinary component must not understand everything
merely because they could afford one.

**It must be a real item sink.** The asset is gone: it does not return to market inventory, does not create
replacement supply, does not duplicate, and yields no generic materials. **Preserve provenance of the
destruction.**

Useful consequence: players may compete for one scarce component because one wants to install it, one to
collect it, one to resell it, and one to study and destroy it. Engineering can permanently reduce circulating
supply through legitimate behaviour.

### Money buys opportunity, never mastery

```
€$ → access to research material
research material + capability + time + process → knowledge
```

Three costs: **capital** (acquiring it), **opportunity** (permanently removing a tradable asset from
circulation), **time** (analysis is not instant). Possibly capacity later.

Buy 500 components and you have purchased a very expensive research backlog — not a rank.

## Knowledge is not one thing

Do not collapse to `KNOWLEDGE +5`. Distinguish: a design exists · its published specification · having
inspected it · practical familiarity · having destructively analysed it · deeper design/manufacturing
understanding · able to fabricate it · able to produce it reliably.

Different authoritative facts, not necessarily different UI bars. **None of them automatically means
"player may now manufacture this."**

## Fabrication: bounded uncertainty, separated from learning

Not `recipe + materials = identical perfect part`. A deterministic seeded process — the metaphor is a
high-resolution roll, *not* a literal D100 presentation. Competency shifts the **distribution**.

**Not pass/fail.** Poor fabrication still produces a poor but legitimate physical component, with identity,
provenance and history. Beginners should be able to make terrible parts, and making them is still practice.

> **OUTCOME MAY BE STOCHASTIC. LEARNING MUST NOT BE PURELY STOCHASTIC.**

A bad roll does not mean nothing was learned. One miraculous roll does not make a beginner a master.

### Fabrication quality ≠ design quality

Excellent fabrication of a mediocre design does not create the world's best component. Poor fabrication of an
excellent design produces a disappointing instance. **A lucky beginner produces an unusually good example of
the design they were actually attempting** — they do not accidentally invent god-tier technology.

**Never retroactively improve previously manufactured assets because their maker later became skilled.** The
part remains exactly what it was born as.

### Skill improves reliability, not just peak

Progression improves **expected outcome and control/variance**. This is the distinction between
*"I got lucky and made one good part"* and *"people come to me because I reliably make good parts."* The
second is the endgame.

> **Fabrication asks: can you make one? Manufacturing asks: can you make them repeatedly and predictably?**

### Component individuality

Two assets from one design need not be identical. Architect for an eventual **bounded outcome vector**, not
`QUALITY = 87` — drawn from a validated finite mechanical vocabulary, possibly correlated rather than
independent casino rolls per characteristic. Effects still deferred pending the engine audit.

## Player manufacturing, markets, and no aristocracy

The horizon: manufacture for self → for others → trade → sell → become known → a workshop identity → supply
one or more markets. **Player supply obeys the same conservation rules as any other physical supply.**

**No permanent first-mover monopoly.** A real temporary advantage is fine; a lockout is not. Someone starting
six months later reaches the same ceilings. One manufacturer must not flood every market — production takes
time, inputs matter, capacity may matter, market rules apply, others compete.

**OEM stays relevant.** `PLAYER CRAFTED > OEM` must not be implied. NPC manufacturers have mature processes
and highly consistent output. Player manufacturing occupies *different niches* — personal, inexpensive,
unusual, specialist, exceptional one-offs, eventually repeatable premium — and **joins** the industrial
ecosystem rather than superseding it.

## Determinism and anti-exploit

Seeded, bounded, server-side. **No client randomness.** No rerolling by disconnecting, reopening a menu,
restarting a project or manipulating timing: a project commits identity, inputs and seed at start so its
result cannot be save-scummed.

**Practice must be legitimate** — no mastery from repeatedly starting and cancelling a zero-cost action.
`meaningful attempt + committed resources + time/work + completion = practice`, rather than *only perfect
success progresses*. And do not punish bad output; bad parts are real practice.

## Visible vs hidden

Authoritative truth stays separate from presentation; **no UI assumptions baked into mechanics.**

*May expose:* disciplines, expertise areas, demonstrated competencies, current capabilities, nearby
opportunities, completed research, known designs, current projects, completion times.

*Deliberately hidden:* probability distributions, mastery formulas, process parameters, thresholds, hidden
internal modifiers, some deeper requirements.

> A player should understand *"I have become very good at suspension fabrication"* — not
> `Suspension Fabrication = 93.772 / 100, success = 87.318%`.
>
> **Understandable, but not trivially solvable.**

> ⚠️ **AMENDED by the addendum below (2026-09-23).** "Hide the rolls" is now too strong. The **possible
> outcome range** may be shown before an operation and the **resolved result** shown landing inside it —
> deliberate ceremony. What stays hidden is the formula and the internal modifiers, not the fact that a roll
> happened. See *Roll ceremony* below.

---

## What exists today (checked, not assumed)

The spec's first question is what progression primitives already exist. Answer: **a good precedent, and
nothing else.**

| Concern | State |
|---|---|
| Driver progression | **exists, racing-only**: `driver.progression` holds licence levels (rookie/licensed/pro), safety rating, and an Elo-style rating. Tables `driver_licence`, `driver_sr`, `driver_rating`, `driver_profile`. |
| Core/host split | **already the right shape.** `M.apply(state, result, ctx)` is a pure reducer in core; `NcmProgression.load/apply` does persistence in the host. Engineering competency should follow this exactly. |
| Engineering / crafting / fabrication / workshop | **nothing whatsoever.** Every grep hit was a false positive. |
| Project / timer infrastructure | **none.** The closest analogue is `market_production_run` — an asynchronous unit of work claimed by index with a holder nonce so it cannot double-execute. That claim pattern is directly reusable for engineering projects. |
| Seeded RNG contract | **exists and is enforced.** `ids.uuid4(rng)` refuses without an injected rng (`rng_required`); core modules never use ambient randomness. This is exactly the philosophy the spec asks to preserve. |
| Knowledge ladder precedent | **exists.** `competition.machine_knowledge` already separates source, epistemic status (observed vs published), model identity and asset identity — deliberately, so an adapter cannot collapse them. The engineering knowledge ladder is the same idea extended, not a new invention. |

## Seams and risks noted while capturing

1. **Competency is a reducer; do not make it a schema.** The racing precedent shows the shape: a small pure
   `apply` over demonstrated work, persisted as compact state. Three axes × five disciplines × twelve families
   is a *derivation*, not 180 columns.
2. **The project claim already has a proven pattern.** `market_production_run`'s claim-then-verify-nonce is
   the anti-double-execution mechanism, and it survived a live restart test. An engineering project wants the
   same shape plus committed inputs and seed.
3. **Destructive analysis is the first true item sink in NCM.** Every existing flow conserves assets —
   production creates, purchase transfers, reclaim removes a *runtime* vehicle but never the asset. Consuming
   a serialised asset permanently is new, and it must be provenance-preserving (a `destroyed` lifecycle or a
   transfer kind, never a `DELETE`), consistent with "terminal does not mean deleted" (L119).
4. **Repair's fast path and research's slow path must not share a timer.** Stated in the spec; worth holding
   as an invariant because one generic project table will otherwise quietly swallow repair.
5. **Workshop capacity interacts with barter and markets** (IDEA-247, IDEA-254). A workshop that can hold
   parts is an inventory; an inventory that can hold parts is tradable. Worth designing once.


---

# Addendum — every engineering intervention has an outcome roll

Captured 2026-09-23. Same status: **nothing built, nothing authorised.**

> **Bounded, competency-influenced outcome uncertainty is not unique to fabrication.** It is a common grammar
> across the disciplines wherever a player's workmanship can meaningfully affect a physical machine or
> component. Fabrication is simply the easiest example.

**Engineering competency affects the quality of engineering work, and that workmanship can become part of the
persistent mechanical state of the affected component or vehicle.**

## What each discipline actually produces

The shared grammar resolves *whatever that action legitimately produces* — it does **not** mean every
discipline modifies vehicle performance.

| Discipline | The roll produces | Bound |
|---|---|---|
| **Fabrication** | a physical component | — |
| **Installation / Integration** | installed state / workmanship | poor may slightly impair; competent achieves expected; exceptional extracts a modest benefit **within the legitimate range the component, design and vehicle mechanics support** |
| **Maintenance / Repair** | condition / service state | weak restores function with some disadvantage left; excellent restores very effectively; skilled work may earn small bounded advantages |
| **Diagnostics / Inspection** | **information quality, not a vehicle buff** | poor gives coarse information; stronger gives precision, extra facts, more confidence |
| **Reverse engineering** | depth/quality of knowledge extracted | resolved after its required analysis time |
| **Design** | the potential embodied by a design | — |
| **Manufacturing** | how consistently instances realise that potential | — |

> **Installation workmanship must NEVER invent capabilities outside the validated mechanical vocabulary, or
> turn an ordinary component into an arbitrarily powerful one.**

## Repair outcome and component condition are separate

Repair is not "broken → click REPAIR → factory perfect".

> **A worn component repaired beautifully is still a component with its own physical history.**
> Do not erase provenance, accumulated exposure or service history because a repair succeeded.

## Four layers that must never merge

```
design potential  ≠  manufacturing realization  ≠  installation workmanship  ≠  current condition
```

Keeping them apart is what lets one physical component accumulate a genuine **engineering biography**:

```
designed by X
  → manufactured by Y   with manufacturing outcome A
  → installed by Z      with installation outcome B
  → accumulated use / wear
  → repaired by Q       with repair outcome C
```

> **Each operation changes only the state it legitimately owns.**

This is also the mechanism behind spec 2's endgame — *"their name appears in provenance"*. It means component
assets need an **attributed operation history**: who did what, when, and with what outcome. Player identity
therefore enters component provenance, which is new — today only manufacture and ownership transfer are
recorded, and neither attributes workmanship.

## Roll ceremony — this revises the earlier visibility stance

The previous spec said to hide the rolls. That is now too strong.

**May be shown:** the legitimate possible outcome range *before* committing, and the resolved result landing
inside it. Where several real statistics are affected, resolution may occur **per affected statistic** rather
than collapsing into one universal QUALITY roll.

Illustrative shape only — these dimensions do not exist and must not be created before the mechanical-effect
audit:

```
Acceleration:     possible  -X <-> +Y
Taper behaviour:  possible  -A <-> +B
        [ resolution ceremony ]
Result:           +...
```

**Still hidden:** the formula, hidden internal modifiers, distributions, thresholds.

The ceremony should communicate *"my engineering capability created this opportunity, and this particular
piece of work landed here"* — without revealing enough for progression to become a solved optimisation
problem.

Unchanged: the authoritative outcome is **server-owned, seeded, deterministic and resistant to rerolling**
through cancellation, reconnection or restart.

## One grammar, not one mechanic

Worth investigating whether all five disciplines share one abstract model:

```
capability determines opportunity/range
  → legitimate engineering action commits
  → seeded bounded uncertainty resolves workmanship
  → domain-specific result is persisted
```

> **But do NOT force every discipline through an identical formula merely for architectural neatness.**
>
> They share a language of competency and uncertainty without becoming the same mechanic wearing different
> hats.
