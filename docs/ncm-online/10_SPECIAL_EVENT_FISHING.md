# NCM Fishing — automotive special event

> **STATUS: SPEC** - owner intent, captured and **NOT authorised for implementation**. Do not build from it; do not contradict it. Covers: *the fishing special event*
> Authority map: [INDEX.md](INDEX.md) - classified 2026-09-24 (L125)

**Status:** shaped concept. Not scheduled, built, validated, assigned to a milestone, or part of the initial six
championships. This document preserves product intent; it is not an implementation specification.

## Definition

**Fishing means literal F-I-S-H-I-N-G, performed with a car.** It is an intentionally absurd but mechanically real
NCM automotive competition:

```text
DRIVE CAR → LAUNCH CAR OFF RAMP → FLY OVER WATER → PASS THROUGH FISH TARGET → SPLASH
```

There are no rods, casting controls, conventional fish-catching interactions, on-foot fishing systems, hacking,
Chrome, messages, scams or phishing. The vehicle is effectively the fishing implement. Success remains recognizably
NCM: vehicle choice, approach speed, position, timing and airborne trajectory determine the catch.

Fishing is not a checkpoint race decorated with fish. It is evidence that the eventual competition framework must
support automotive contests whose scoring primitive is not `start → checkpoints → finish → position`.

## Venue and attempt loop

A Fishing venue contains:

- a defined driving approach;
- a launch ramp or equivalent terrain feature;
- a body of water;
- one or more spatial fish targets over that water;
- authoritative detection of a qualifying vehicle intersecting a target;
- scoring/results based on valid catches;
- practical shoreline or water exits and a reasonable return path.

The competitor accelerates, launches over the water and tries to cross a fish target. A valid crossing catches that
fish. Missing every valid target is **NO CATCH · 0 PTS**.

Rings or volumes are the current conceptual visualization, not a locked art direction. A fish may later look like a
fish or receive stronger event dressing. The required primitive is a clearly understandable three-dimensional catch
volume; implementation must not be coupled prematurely to literal visible rings.

**Fish targets should generally move.** The driver is solving:

```text
vehicle + speed + approach + launch timing + trajectory + predicted fish position
```

Fishing should not collapse into memorizing one perfect ramp speed for one stationary coordinate. Movement must be
observable enough that skillful anticipation matters: *where will that fish be when my car reaches it?* Catch
validation remains deterministic against the fish volume's actual position at intersection; movement must not become
a concealed server coin toss after launch.

## The non-negotiable catch rule

A catch is valid only when all of these are true at the instant of target intersection:

```text
target intersection
+ registered entrant
+ qualifying registered vehicle
+ entrant still occupying that vehicle's driver seat
= valid catch
```

- An empty vehicle cannot catch a fish.
- A driver cannot accelerate toward the ramp, bail out, and receive credit when the empty car crosses the target.
- A passenger receives no catch merely because the vehicle crosses a target.
- If an unexpected vehicle legitimately reaches the target under the event rules, the catch counts.

Once the valid intersection occurs, the fish is caught. Splashdown, vehicle condition, exiting the car or the return
to shore cannot retroactively invalidate it.

This driver-seat rule is sporting logic, not flavour or presentation.

## Splashdown and return

Entering the water is expected. The default loop is deliberately **not** an immediate automatic teleport:

> You fish, you go fish.

The driver launches with the vehicle, lands in the water, exits and swims back to shore. The physical consequence is
part of Fishing's identity and comedy. A more ambitious catch may naturally mean a longer swim.

Venue authoring must keep that consequence playable rather than exhausting: usable shoreline, viable water exits and
a reasonable path back toward the competition area are requirements. Exceptional recovery may eventually handle
physics bugs, trapped players, inaccessible shoreline, inability to exit, or other broken states. Such recovery is a
failsafe, never the normal optimal loop.

Vehicle recovery is unresolved. Fishing must eventually consume NCM's shared ownership, condition, recovery and
repair architecture rather than inventing a private version of those systems.

## Physical difficulty and fish value

Fish may differ in position, difficulty and eventual value. Difficulty can emerge from combinations of:

- distance from launch;
- lateral offset;
- target size;
- target movement;
- approach or trajectory demands;
- vehicle performance;
- future condition, tuning, Machine progression or environmental effects.

The governing principle is **physics/capability gating, not arbitrary UI eligibility**. A distant target should not
say `REQUIRES NCX`; it should be physically difficult enough that exceptional speed and trajectory are necessary.
If another legitimate vehicle or build can reach it, the catch stands. Fishing-specific performance hacks must not
be added merely to manufacture this outcome.

Movement generally escalates with difficulty, without becoming a single rigid ladder:

- **Common/easy fish:** slow, relatively large and predictable; understandable to a new player and reachable with
  ordinary machinery.
- **Intermediate fish:** meaningful movement with varied speeds and patterns, distances, sizes and values; prediction
  and launch timing become central.
- **Rare/high-value fish:** fast and/or difficult movement, potentially smaller volumes, awkward placement, limited
  opportunity windows, and machinery/setup demands created by physics.
- **Nessie:** the extreme, distant, highly mobile and deliberately elusive case.

Distance alone never defines quality. A nearer, small, fast, rare target may be harder and more valuable than a
farther predictable one.

## A rich middle, not a five-rung ladder

Fishing progression must not reduce to `Bronze Fish → Silver Fish → Gold Fish → Diamond Fish → Nessie`. The middle
needs a varied, somewhat unpredictable ecosystem. A future target catalogue/pool may describe:

- name/species or target identity;
- rarity and typical catch value;
- movement characteristics;
- catch-volume characteristics;
- possible distance/range;
- spawn weighting or availability;
- distinctive presentation.

No species taxonomy is canonized by this note. The invariant is variety: a distance does not guarantee a particular
fish, and similar areas or attempts can present different opportunities. A player should sometimes see an unusually
valuable target and decide, *that's worth going for.* Target selection is part of the activity.

Effective difficulty/value may emerge from distance, movement speed and pattern, volume size, rarity, trajectory,
time window and the machinery plausibly required. This creates meaningful choices among reliable lower-value fish,
moderately difficult profitable targets, risky high-value fish, and exceptional legendary catches.

## Nessie

**NESSIE** is the working nickname for an extreme legendary target extraordinarily far from the launch. Ordinary
cars are intended to be physically incapable of reaching it under normal conditions; something approaching NCX
performance may be the obvious candidate.

**Nessie is the stealth bomber of all our fish.** It moves more aggressively and less predictably than ordinary
targets and must remain elusive even after a player solves the raw distance requirement. Owning an NCX car, finding
the perfect approach, or timing Power Surge may put the driver in Nessie's general operating area; it does not turn
the catch into a deterministic vending machine. Nessie can still say nope and move.

Its motion may eventually use very rapid travel, enormous relocations that feel almost like teleportation,
disappearance/reappearance, intermittent windows, randomized relocation, or a combination. None is locked. Nessie
may contain substantial uncertainty, but it must not feel as though the server secretly decided after launch whether
the attempt wins. There must remain an observable target and a legitimate prediction/commitment problem.

Nessie is never hard-gated to NCX. A surprising legitimate vehicle/build/setup that reaches the target while its
registered entrant is still driving has caught Nessie. The feat should emerge from the simulation, not menu
permission.

Nessie may eventually become an exceptional persistent fact in the driver's NCM history. Its exact distance, score,
reward, presentation and persistence are unresolved and must not be fabricated from this note.

## Format and scoring boundary

The shaped mechanic is:

> A registered entrant catches a fish when their registered vehicle intersects its catch volume while that entrant
> still occupies the driver seat.

The event format and balance are not designed. Possibilities discussed, without commitment:

- different point values by fish;
- harder or farther fish worth more;
- multiple launches or “casts” per entrant;
- best total score or another settlement method;
- exceptional recognition for rare/legendary catches;
- roughly three launches per entrant.

Attempt count, point values, field structure, target reset/consumption, simultaneous running, tie-breaking, payouts,
penalties and settlement remain explicitly open.

Fishing is intended eventually to pay money. Conceptually, a fish carries a bounty/catch value rather than
necessarily using a conventional race purse. Possible presentation:

```text
FISH CAUGHT
<species>
CATCH VALUE: €$X
```

Amounts and formulas are wholly unresolved. Value should broadly reflect difficulty/rarity without becoming a
deterministic metres-from-shore equation. Catch revenue is not guaranteed profit: recovery, deductible, uncovered
damage and repair may make a sporting success a financial disaster.

Nessie should be extraordinarily valuable—closer to buried treasure than an ordinary payout—but never an infinite
currency printer once someone learns the challenge. First-catch/discovery bounty, smaller repeats, replenishment,
diminishing returns and other anti-farming methods remain open. Efficient ordinary fish need the same farming audit.

## Persistent Fishing history and badges

Fishing feeds NCM's telemetry-first badge/prestige system through **two distinct badge families**. They answer
different questions and must never be collapsed.

### Fishing Experience

**How much successful Fishing has this driver done?** It uses the normal
`Bronze → Silver → Gold → Diamond → Purple` prestige ladder. Thresholds and the final metric are unresolved, but it
must measure meaningful successful participation—valid catches, successful outings, cumulative catches, or another
durable fact—not merely launches or repeated misses. This is mastery through successful repetition.

### Best Catch

**What is the greatest fish this driver has ever caught?** It uses the same five visual tiers, driven by the quality
or tier of the best recorded catch rather than repetition.

**PURPLE BEST CATCH = NESSIE.** A valid Nessie catch upgrades Best Catch to Purple.

The distinction is intentional:

- Purple Fishing Experience + Diamond Best Catch: lifelong fisher who has never caught Nessie.
- Bronze Fishing Experience + Purple Best Catch: inexperienced fisher who somehow caught Nessie.

Fishing telemetry should preserve factual history independently where practical: valid catch, species/target ID,
rarity/tier, Nessie, and the minimum event/value metadata future interpretation needs. Badges interpret history; the
mechanic never depends on owning or equipping them. Badge permanence and curated Driver Card presentation follow the
existing NCM badge philosophy.

## Relationship to vehicles and economy

Fishing deliberately puts vehicles into water. It therefore intersects with the emerging shared vehicle philosophy:

- persistent ownership is distinct from a spawned physical entity;
- persistent condition is distinct from ownership;
- destruction should not normally delete ownership;
- “totaled” may eventually mean unusable until recovery/repair;
- recovery and repair may become economic sinks.

Fishing must consume those shared systems later, not solve them locally. Insurance, recovery, repair cost, condition
damage and consequences are unresolved.

The intended economic result eventually resembles:

```text
catch value
− participation/entry cost, if any
− recovery cost
− insurance deductible
− uncovered damage
− repair and other shared vehicle-economy consequences
= actual financial result
```

A valuable catch can be a sporting triumph and a financial disaster. Conversely, suitable machinery, coverage and
skill may make a class of fish consistently profitable without Fishing-specific cars or stat bonuses.

## Future insurance relationship

Fishing makes a future shared vehicle-insurance system materially meaningful, but does not own or implement it.
The architectural boundary is:

> Fishing determines what happened. Vehicle condition/recovery determines what the car needs. Insurance determines
> who pays.

Policies may have visible coverage types, exclusions, deductibles, ceilings and clauses. A standard policy might
cover sanctioned collision or ordinary towing while stating, plainly, **FISHING: NOT COVERED** for intentional
aquatic entry. A more expensive specialist product/add-on might cover Fishing recovery, submersion and water damage,
subject to its deductible and terms. Product names and exact coverage are not locked.

This must never be an unreadable-fine-print gotcha. Terms are visible before purchase. A driver who never fishes need
not buy aquatic coverage; a serious fisher may regard it as essential. “You want to fish? Go fish.” is the cultural
promise of the specialist coverage, not a finalized product name.

General vehicle insurance warrants its own future shared design surface; no parent currently exists in the catalog.
Fishing-specific exclusions and claims remain here until that parent is shaped, then cross-reference rather than
duplicate the rules.

A player may eventually risk an extremely valuable privately owned NCX car because its performance makes Nessie
reachable. Prestige alone must not forbid that. The distinction between privately owned NCX machinery and
team-supplied/recruited-driver machinery may create restrictions or consequences for abusing team property, but that
system is not designed. Preserve it as an open question.

The cultural contrast is deliberate: a privateer may say **MY NCX. MY FISH.** A recruited driver launching team-owned
NCX machinery into the ocean may face different permission, insurance, recovery or team consequences. None are
designed here; the future ownership/team/insurance architecture must merely be capable of expressing them.

Where a Fishing ruleset permits self-enhancement, a system such as Power Surge may legitimately change launch
performance. A car + setup + approach + correctly timed enhancement may reach a fish the stock vehicle cannot.
Nessie does not validate the expected solution; Nessie validates the legitimate catch.

The intended decision is:

```text
What fish do I see? What is it worth?
Can my machine reach it? Can I predict where it will be?
Can Chrome bridge the gap?
What happens to this car when I land?
Does my insurance cover what I am about to do?
Is this catch worth the risk?

SEND IT.
```

## Product position and tone

Fishing is a future **Special Event, novelty championship, or reusable alternative competition format**. It is not a
foundational championship, not required for TW1, and must not distort the current championship implementation.

NCM treats Fishing with straight-faced sporting legitimacy. The premise supplies the joke; the rules and scoring
should be consistent. Presentation can be restrained:

- `FISH CAUGHT`
- `NO CATCH · 0 PTS`

An understated miss sting or “womp womp” may be explored, but nonstop joke copy is not the direction. The world acts
as though launching automobiles through fish targets into the ocean is a perfectly reasonable motorsport discipline.

Fishing is distinct from **the MaiMines**. MaiMines is the cultural nickname around the accessible one-make MaiMai
Cup and potential economic recovery rung (“Mining” / “go dig”). Fishing is a separate automotive competition. Their
resemblance to MMO professions is a running cultural joke, not shared mechanics or progression.

## Anti-goals

Do not reinterpret Fishing as:

- conventional rod fishing or casting;
- an on-foot or generic Cyberpunk fishing minigame;
- phishing, cybersecurity, scams, messages, Chrome or hacking;
- a checkpoint race with fish decoration;
- an NCX-exclusive event or explicit `REQUIRES NCX` gate;
- a reason for Fishing-specific tuning/performance cheats;
- a distance-only progression ladder or deterministic solved launch recipe;
- arbitrary hidden RNG that decides catches after launch;
- a single badge that conflates lifetime experience with greatest catch;
- an insurance implementation or private claims system;
- a reason to implement permanent vehicle deletion;
- a private vehicle-condition, repair or recovery subsystem;
- part of TW1 or the initial six-championship architecture;
- the MaiMines or an extension of MaiMai progression.

## Explicitly unresolved

- first venue and launch geometry;
- target art and feedback beyond the catch-volume primitive;
- movement algorithms/patterns, target observability and relocation limits;
- species/target catalogue, rarity model, spawn weighting and availability;
- attempts per entrant and target reset rules;
- scoring, ties, field structure and settlement;
- catch bounties, farming controls and actual profit balance;
- Fishing Experience metric and all badge thresholds;
- Best Catch tier mapping below Purple;
- Nessie's exact placement, movement implementation, value, reward and persistence;
- normal vehicle recovery after splashdown;
- exceptional player/vehicle recovery conditions and UX;
- condition, repair and economic consequences;
- general insurance architecture, policy products, terms, claims and aquatic coverage pricing;
- weather/environment participation;
- private versus team-supplied vehicle permissions;
- whether Fishing is one special event, a novelty championship, or a reusable format with several venues.
