# 40 — NCM ONLINE ECONOMY V1

> **STATUS: CURRENT** - authority for: *the Economy v1 build contract* - affirmed 2026-09-27 (`L168`, `L169`)
> Authority map: [INDEX.md](INDEX.md).

> **IMPLEMENTATION:** The broad v1 race-money loop, personal-first Research Exchange, existing unique-Badge
> rewards and selected Race Tag bounties are built locally under `L169`; deployment and MASTER_TEST §BJ remain
> owed. Fuel, generalized player trade, Research contracts/world-first calls and the tiered Badge reducer are not
> claimed by this implementation.

NCM's launch economy must be viable with **one human and no AI drivers**. A scheduled event with one entrant is
a time trial and pays. A contested race pays. Both charge an authored entry fee; the lowest Street rung starts
with the same nominal fee so a player is not economically punished when an expected race forms as a time trial.
Free practice remains the unlimited learning surface and never pays.

Cars and serialized Parts are the principal progression sinks. Fuel is a later, modest operating sink. Research
submissions, Badge tiers and selected Race Tag bounties add faucets for curiosity, career breadth and the way an
event was driven. Player trade redistributes existing value and is never a faucet.

This document makes that shape buildable. It replaces no asset, Market, Machine Knowledge, Badge or Race Tag
ontology. It defines when those systems may create, destroy or transfer NCM money and how the result is audited.

---

## 1. Authority and boundaries

Read this contract with the following topic authorities:

- [08_ECONOMY.md](08_ECONOMY.md) for the ledger-first intent and the refund rulings in `L84`/`L85`;
- [17_MARKET_NETWORK.md](17_MARKET_NETWORK.md) for market discovery, physical stock and atomic purchase;
- [18_PARTS_ECOSYSTEM.md](18_PARTS_ECOSYSTEM.md) and `L162` for serialized component Designs and assets;
- [28_MACHINE_KNOWLEDGE.md](28_MACHINE_KNOWLEDGE.md) and `L164` for proof-bearing, player-scoped observations;
- `L130` / `IDEA-082` for Badge entitlement, tiers and display separation; and
- [B-089-race-tags.v1.md](bricks/assignments/B-089-race-tags.v1.md) for the factual Race Tag vocabulary.

Where the older economy audit describes missing idempotency, implementation has overtaken it: migration 017
already added `ledger.idem_key` and `ux_ledger_idem`, and Market and component purchases already use them. Race
entry and settlement still write zero. Economy v1 extends the proven ledger; it does not introduce a wallet.

### Non-goals

Economy v1 does not add AI racers, cryptocurrency, exchange rates, debt, interest, gambling, speculative
commodities, a global auction house, passive income, random loot drops or level-up supercars. It does not merge
NCM eddies with OPEN//77 Freeroam money. It does not make routes, rulesets, Race Tags, Badges or observations
responsible for writing money themselves.

---

## 2. Invariants

These are implementation constraints, not tuning suggestions.

1. **Balance is derived.** A Driver's per-server balance is `SUM(ledger.amount)`. There is no second mutable
   wallet truth.
2. **Every non-zero write is idempotent.** The deterministic `idem_key` describes the economic fact. Retrying
   check-in, settlement, a Badge reducer, a research review or a trade cannot change the balance twice.
3. **Money is integer NCM eddies.** Credits are positive, sinks/debits are negative and transfers create paired
   opposite rows whose sum is zero.
4. **A single human can progress.** The renewable launch income loop cannot depend on another player arriving.
5. **Practice is free and inert.** It charges no entry fee and pays no completion, target, placement or Tag
   bounty. It may produce evidence that a player later chooses to submit to Research.
6. **Championships own default economics.** An event may override them; routes own geography and rulesets own
   sporting rules. The legacy `ruleset.prizes` zeroes are not the Economy v1 authority.
7. **Fees and payouts are independent.** A purse is not the entry-fee pot. Small fields may create money.
8. **Finishing keeps a Driver solvent; performance advances them.** A classified completion must ordinarily
   cover that event's entry fee and ordinary fuel. DNF/DNS/DSQ does not receive completion money.
9. **Ownership, access and custody stay distinct.** A loaner or rental is usable but not owned. Every Machine
   and Part transfer names the exact serialized asset and preserves provenance.
10. **Economic consumers do not corrupt source truth.** Research does not turn an observation into canonical
    model truth; Badge payment does not change entitlement; a Tag bounty does not turn a Tag into an award.
11. **No client assertion mints money.** Settlement consumes server-authoritative results, accepted evidence or
    durable progression transitions.
12. **All values are observable and provisional.** Structural invariants are locked; numbers are authored data
    to be rebalanced from source/sink and acquisition-time telemetry.

---

## 3. Flow taxonomy

| Flow | Economy role | Examples |
|---|---|---|
| Faucet | creates NCM money | classified event completion, placement, target time, research acceptance, first Badge tier, selected Tag bounty |
| Sink | destroys NCM money | entry fee, primary-market Machine/Part purchase, fuel, later service/wear, optional trade tax |
| Transfer | moves existing money/value | player-to-player Machine or Part trade, organization payment, buyback payment paired with title transfer |
| Access | neither ownership nor money creation by itself | practice, loaner, rental, test drive, sponsor-provided temporary car |

The ledger must distinguish these flows by `kind`. A dashboard that only shows net balance is insufficient: NCM
must be able to say how much money came from solo racing, contested racing, Research, Badges and bounties, and how
much left through each sink.

---

## 4. Launch event economics

### Activities

| Activity | Entry | Renewable payout | Notes |
|---|---:|---:|---|
| Free practice | €$0 | €$0 | learning, ghost use and evidence gathering only |
| Scheduled time trial | authored fee | completion + authored target/bounty lines | race kernel with a field of one |
| Contested race | authored fee | completion + placement + field/bounty lines | two or more formed-grid entrants |

A one-entrant event settles from the time-trial table. It never receives a ceremonial P1 placement payment for
beating an empty field. A two-or-more-entrant event settles from the race table.

### Provisional Street defaults

These values are the first instrumented balance, not permanent lore:

| Line | Provisional amount | Rule |
|---|---:|---|
| Entry | **-€$50** | charged once at successful scheduled-event check-in |
| Time-trial classified completion | **+€$250** | full-rate cadence is authored per route/window |
| Time target I / II / III | **+€$100 / +€$250 / +€$500** | pay the single highest newly satisfied authored band, not all three |
| Contested-race classified completion | **+€$300** | every classified finisher |
| P1 / P2 / P3 | **+€$350 / +€$150 / +€$75** | contested races only; absent places create no row |
| Field bonus | **+€$50 per formed-grid entrant, max €$250** | contested races only; amount locks when the grid forms |
| Clean Run / Clean Race bounty | **+€$50 / +€$75** | only when explicitly selected by event/sponsor policy |
| Windowed Personal Best bounty | **+€$100** | disabled unless a payout window and meaningful improvement threshold are authored |
| Total Tag bounty cap | **€$150 per Driver/session** | cap applies after the eligible mapping is resolved |

The intended net-earning bands are:

| Career band | Typical net event earning | Economic purpose |
|---|---:|---|
| Street | €$200–€$800 | recover, learn, buy early upgrades and entry Machines |
| Club / Sport | €$1,000–€$5,000 | build configurations and a broader garage |
| Elite | €$10,000–€$50,000 | pursue rare Parts and serious Machines |
| Marquee | €$50,000–€$250,000 or an asset prize | long-horizon aspiration, not routine farming |

The Machine price ladder may run from the €$2,500 MaiMai into the millions. A million-eddie Machine is therefore
a persistent-world objective assembled from higher-tier play, finite rewards, trade and asset prizes—not from
hundreds of identical beginner sprints. Exact acquisition-time targets are tuning data, but the dashboard must
measure them before the high end is released.

### Anti-farming without eliminating recovery

Time trials must remain a dependable solo road back. They therefore use controlled repeatability rather than a
hard zero after the first clear:

- each event authors a payout-window id, full-rate completion count and non-zero recovery floor;
- repeated completions of the same route/window diminish to that floor;
- target bands pay once per route revision and authored window unless a contract explicitly resets them;
- a Personal Best bounty requires both a window and a meaningful improvement threshold;
- seasonal first clears and rotating targets may renew because the authored opportunity changed;
- settlement keys the exact opportunity, so reconnecting or replaying a request cannot renew it.

The first Street pack should begin with one full-rate classified completion per route per daily window and an
authored recovery floor. The floor amount and Personal Best threshold remain balance fields to be selected and
tested in the implementation slice; absence of either field means the corresponding repeat/PB payment is off,
not unlimited.

---

## 5. Entry, lock and refund lifecycle

1. Interest/browsing is free and reserves nothing.
2. Successful check-in runs busy and eligibility checks, reads the advertised fee, proves sufficient balance,
   inserts the entry and debit atomically, then records the paid amount on `entry.fee`.
3. The grid locks the event form and exact field bonus. At the Street rung the race and time-trial fee are the
   same, so a grid collapse needs no adjustment.
4. If a later championship authors a lower time-trial fee, check-in charges no more than the advertised race
   fee and grid collapse refunds the difference. Forming a small field may never create a surprise debit.
5. Settlement writes the result and all monetary lines in one recoverable operation. A result visible without
   its payout, or a payout visible without its result, is a defect.

| Outcome | Fee | Payout |
|---|---|---|
| Classified finish | kept | completion plus any eligible performance lines |
| DNF / DNS / DSQ | kept | no completion; separate policy may later author a non-performance recovery grant |
| Voluntary withdrawal after paid check-in | kept | none |
| Server/admin cancellation | fully refunded | none |
| Session never goes green or is abandoned by NCM | fully refunded | none |
| Resource restart leaves a paid event unresolved | refunded by an idempotent recovery sweep | none |

DNF and DSQ remain different sporting facts even while their launch amounts match. The policy can later diverge
without rewriting history.

---

## 6. Vehicle acquisition beyond Market purchase and player trade

Every route below creates or transfers an exact Machine asset. None silently creates an abstract unlock.

1. **Prize Machines.** Authored championship, seasonal or special-event prizes. Prefer a car over a giant cash
   purse when the object itself is the story. One prize allocation can be claimed once.
2. **Earn-to-own contracts.** A Driver receives time-limited access to a named Machine and earns title by meeting
   authored use, result, research or payment milestones. Until the final transfer it remains a loan.
3. **Restoration projects.** The player acquires a documented chassis/project asset and supplies money, Parts or
   research to return it to service. Restoration changes condition/configuration, not identity.
4. **Commissioned manufacture.** A Driver funds an authored manufacturer/Foundry production order. Payment,
   production run, exact Design revision and delivered serial remain linked.
5. **Organization or sponsor awards.** A team, manufacturer or sponsor may transfer an existing Machine or fund
   a new one under an explicit contract. Sponsorship is not a random drop.
6. **Exceptional community grants.** Tournaments, moderation recovery or authored community contributions may
   grant an asset. The exceptional source is permanently visible in provenance and is not a routine faucet.

Loaners, rentals and test drives expand access but do not grant ownership. Random post-race car drops and
automatic level-up supercars are excluded: they destroy price legibility and serialized provenance.

---

## 7. Research Exchange

Research rewards curiosity only when the Driver deliberately submits evidence. Automatic observation alone does
not pay.

### Eligible submission shapes

- a newly and physically discovered Machine identity;
- a physically discovered specialist Market;
- the first accepted observation characteristic or meaningful capability band for an eligible subject;
- evidence requested by an active research contract; and
- later, a scanned configuration, unusual Part or documented anomaly.

Base Market catalogue exposure normally pays nothing. The Market is intentionally universal; opening it is not
research.

### Reward classes

| Class | Renewal | Purpose |
|---|---|---|
| Personal first | once per Driver/subject/evidence class | small finite reward for first legitimate discovery or accepted characteristic |
| Research contract | as explicitly authored | renewable because the world requested new evidence, not because the same sample was resubmitted |
| World first | once per program/evidence identity | larger limited reward; may include a smaller authored participation payment for valid non-winning submissions |

An accepted submission references the existing proof-bearing evidence. It retains source Machine, basis, time,
coordinates and configuration provenance. Repeated refitting cannot mint a new claim merely because a
configuration revision changed, and tiny incremental maxima are not separately payable. Programs define
meaningful bands or requested facts rather than rewarding every numeric improvement.

### Privacy and truth

Evidence remains private unless the submission explicitly grants the program the required use/publication
permission. A submission creates a contribution record; it never transforms one Driver's asset observation into
canonical model documentation. Rejection does not delete or downgrade the underlying private evidence.

The minimum durable claim records program/version, Driver/server, evidence type and immutable evidence reference,
normalized evidence identity, submission time, consent scope, review state/reason, accepted amount and ledger
row. World-first selection and its payment must share one transaction/unique constraint.

Deterministic key:

```text
research:<programVersion>:<driverId>:<evidenceIdentity>
```

---

## 8. Badge rewards

Badge money is a finite career faucet. Payment occurs when a tier is first earned, never when a Badge is shown,
hidden or selected for the Driver Card.

| Tier | Provisional one-time reward |
|---|---:|
| Bronze | €$100 |
| Silver | €$300 |
| Gold | €$1,000 |
| Diamond | €$3,000 |
| Purple | €$10,000 |

Across roughly forty five-tier Badges the theoretical maximum is €$576,000 per Driver: meaningful career wealth,
but still below the million-eddie upper Machine tier. Balance the catalogue as a total liability, not forty
isolated reward decisions. Unique non-tiered Badges such as First Win or an event souvenir may carry one authored
flat amount.

Badge entitlement, current tier, display selection and payment are separate durable facts. A tier never revokes,
and settlement corrections do not claw back an already earned Badge under the existing Badge direction.

Deterministic key:

```text
badge:<driverId>:<badgeId>:<tierId>:<serverId>
```

---

## 9. Race Tag bounties

Race Tags remain ephemeral factual descriptions—"labels on the tape." The Tag evaluator is pure and writes no
money. Economy v1 separately allows a championship, event or rotating sponsor contract to map selected factual
Tag ids to bounties.

```lua
tagBounties = {
    clean_run    = 50,
    clean_race   = 75,
    personal_best = 100,
}
maxTagBounty = 150
```

The settlement consumer uses the evaluator's **uncapped qualified fact set**, not the 2–4 Tags selected for
presentation. UI priority must never decide money. The factual set and displayed selection come from the same
inputs and logic version and are recorded with settlement diagnostics.

### Initially eligible

- `clean_run`;
- `clean_race`;
- windowed `personal_best` with an authored meaningful-improvement threshold; and
- later, `route_record`, only after route geometry is versioned and the record is server-corroborated.

### Initially ineligible

- all negative/contact/penalty Tags, including `heavy_contact`, `tough_one`, `jump_start`, `penalised`,
  `lost_positions` and `did_not_finish`;
- `close_finish`, because two Drivers can manufacture it;
- `gained_positions` and `good_start`, because grid position can be manipulated;
- `clear_win` and `led_every_gate`, because placement already pays; and
- unrestricted incremental `personal_best`, because sandbagging would mint money.

A rotating sponsor bounty—"Makigai pays €$100 for a Clean Run in tonight's street events"—is a new authored
opportunity with an explicit window and budget. It is preferable to attaching a permanent universal price to
every descriptor.

Deterministic key:

```text
tag_bonus:<sessionId>:<driverId>:<tagId>:<bountyVersion>
```

---

## 10. Procedural Parts economics

Procedural generation must produce legible engineering value, not a slot-machine price.

### Primary price at Design birth

```text
primaryPrice = round(
    familyBase
  × nonlinearCapabilityMultiplier
  × engineeringComplexityMultiplier
  × interfaceClassMultiplier
)
```

The inputs and resolved price are frozen on the immutable component Design revision. Reproduction of that
revision uses the same primary price unless an authored economic release changes the offering; rerunning the
generator does not reprice already existing assets.

Capability pricing evaluates the whole effect vector, including losses and trade-offs. Most Parts should be
sidegrades for a purpose, not universal upgrades. Fitment breadth and distribution are disclosed to the buyer
but do not masquerade as performance. Scarcity controls how many physical assets exist and may affect negotiated
secondary prices; it does not rewrite engineering truth.

The current full-kit reference points—roughly €$6,800 Street, €$19,300 Sport and €$23,800 premium mix—are useful
calibration, not caps. Compare kit acquisition time to event earnings before changing individual prices.

Because Parts are durable, their purchase is mostly a one-time sink. Repeating operating sinks belong to fuel
and later service/wear, not arbitrary Part deletion. A Market buyback pays below the asset's current primary
offer value, transfers that exact serialized Part back into supply and preserves its custody history. Buy and
buyback values must never permit risk-free arbitrage.

---

## 11. Fuel and energy — post-settlement slice

Fuel is approved as a design direction, not as the first economy implementation. It enters only after paid
events are live and measured, because an operating sink without a proven faucet can strand the first players.

Target fuel cost is approximately **5–10% of ordinary gross event earnings**, and entry plus ordinary fuel should
normally remain below roughly **20% of a classified finish payout**. Fuel creates route planning and operating
texture; it is not expected to control inflation.

NCM owns the state because OPEN//77 exposes no authoritative reusable `fuelLevel` for this economy. The first
approximation uses authored capacity and integer/fixed-point energy units:

```text
burn = idleRate × elapsed
     + distanceRate × authoritativeDistance
     + speedLoad × distanceAtSpeed
     + accelerationLoad × positiveAccelerationWork
```

Coefficients are Machine/energy-carrier tuning data. Consumption is bounded, deterministic at the authoritative
sampling resolution and independent of frame rate. Refuelling debits money and increases stored energy in one
transaction; a retry cannot buy twice or fill twice.

Every Driver retains a bankruptcy road back: emergency splash, tow, a free practice surface and/or an eligible
loaner must allow them to reach a paying event. The exact recovery presentation and carrier vocabulary are open
for the fuel work package.

---

## 12. Player trade and Market buyback

A trade surface consumes an accepted offer containing exact asset ids, buyer, seller, amount, expiry and request
key. In one transaction it:

1. rechecks custody, transfer eligibility and buyer balance;
2. debits the buyer and credits the seller with paired rows;
3. transfers every named Machine/Part and appends custody history; and
4. marks the offer accepted so retry returns the original result.

Trade mints no money. A future listing or transaction tax may be a sink, but no tax is assumed in v1. Private
trade does not reveal undiscovered Markets or publish private Machine knowledge.

Buyback is a Market transaction, not deletion: the exact asset returns to authored supply. Buyback amount,
Market, asset and custody transfer must commit together.

---

## 13. Ledger contract and atomicity

Economy v1 adds a single money service in the league host. Market, components, race settlement, Research, Badges,
fuel and trade call it rather than embedding new balance queries and `INSERT` statements independently.

Minimum operations:

```text
balanceOf(principal, server)
credit(principal, amount, kind, idemKey, refs)
debitIfAffordable(principal, amount, kind, idemKey, refs)
transfer(from, to, amount, kind, idemKey, refs)
```

Zero and negative credit amounts, negative debit amounts, missing idempotency keys and currency mismatches are
refused. Duplicate keys return the original economic result, not a second mutation.

Before paid racing, add nullable typed `event_id`, `session_id` and `series_id` ledger references. `ref` and
`note` remain human aids, never fields analytics must parse.

| Economic fact | `kind` | Idempotency shape |
|---|---|---|
| check-in fee | `event_entry` | `entry:<eventId>:<driverId>` |
| cancellation/recovery refund | `entry_refund` | `refund:<eventId>:<driverId>:<reason>` |
| classified completion | `event_completion` | `payout:<sessionId>:<driverId>:completion` |
| placement | `event_placement` | `payout:<sessionId>:<driverId>:placement` |
| target band | `event_target` | `target:<opportunityId>:<driverId>:<bandId>` |
| field bonus | `event_field_bonus` | `payout:<sessionId>:<driverId>:field` |
| Tag bounty | `tag_bonus` | `tag_bonus:<sessionId>:<driverId>:<tagId>:<version>` |
| Badge tier | `badge_reward` | `badge:<driverId>:<badgeId>:<tierId>:<serverId>` |
| Research acceptance | `research_reward` | `research:<programVersion>:<driverId>:<evidenceIdentity>` |
| fuel purchase | `fuel_purchase` | `fuel:<stationId>:<driverId>:<assetId>:<requestId>` |
| player trade | `player_trade` | `trade:<tradeId>:<side>` |
| asset buyback | `asset_buyback` | `buyback:<marketId>:<assetId>:<requestId>` |

One session may legitimately create several payout rows. The receipt groups them; idempotency protects each
fact. Settlement must be recoverable as a unit: either use one database transaction for result + lines, or write
a durable settlement envelope whose incomplete state is safely resumed. A loop of unrelated best-effort inserts
is not acceptable for non-zero money.

---

## 14. Player-facing statements

The Race Guide shows the entry fee, base completion, placement table, field rule, target opportunities, repeat
policy and active sponsor bounties before check-in. Before grid lock it displays the rule; after lock it displays
the exact contested field amount.

Every settled event produces an itemized statement:

```text
TIME TRIAL COMPLETE

Completion          +€$250
Clean Run            +€$50
Badge: Bronze       +€$100
Entry                -€$50
Fuel                 -€$18
NET                  +€$332
```

Lines that did not apply are omitted. A capped or declined bounty may appear in an expandable explanation, but
never as an unexplained missing payment. The statement identifies the settled session and survives reconnect so
a correct database transaction cannot look like theft.

Research acceptance/rejection, Badge earnings, Market purchases, buybacks and trades receive the same standard:
name the object/fact, amount, new balance and where the asset went.

---

## 15. Telemetry and balance review

At minimum, observe per day and per active Driver:

- faucet totals by kind and championship;
- sink totals by kind and price band;
- transfer volume separately from creation/destruction;
- net earning per classified racing hour;
- completion, DNF, DNS and DSQ rates;
- balance distribution and zero-balance frequency;
- repeat-route concentration and payout-window exhaustion;
- median time to first purchased Machine, first full Part kit and each vehicle price band;
- Research acceptance/rejection and world-first contention;
- Badge liability paid versus remaining catalogue maximum;
- Tag bounty frequency, cap hits and suspicious pair/session patterns; and
- fuel share of gross earnings once fuel exists.

Balance changes answer observed acquisition time and behaviour. They do not rewrite ledger history or procedural
Design prices in place.

---

## 16. Build order

The order is part of the contract because each later faucet depends on an earlier source of truth.

### Slice A — paid scheduled events

1. Pure core resolver: event form, classified state, completion, placement, field, target, repeat policy and Tag
   bounty cap produce deterministic line items without database access.
2. Shared host money service over the existing idempotent ledger, plus typed event/session/series references.
3. Championship/event Economy v1 data with the provisional Street table.
4. Atomic check-in debit and insufficient-balance refusal.
5. Atomic/resumable settlement, cancellation/restart refund and itemized receipt.
6. Race Guide disclosure and source/sink telemetry.

### Slice B — Research Exchange

Build the program catalogue, explicit submission/review record, privacy grant, first/world-first concurrency and
payment. Begin with physical discovery and the two already wired observation characteristics; do not invent
producers for the other four.

### Slice C — Badge rewards

Define the Badge catalogue and reducer first. Pay tier crossings from durable transitions. The schema/service
seam may be prepared earlier, but there is no payment without a real Badge entitlement fact.

### Slice D — Race Tag bounties

Integrate `B-089` as a pure evaluator, preserve its descriptive presentation, expose its uncapped fact set to
settlement and enable only the initial allow-list/cap. Race Tag integration is a dependency, not permission to
reimplement Tags inside the economy module.

### Slice E — operating and exchange sinks

Add fuel/refuelling after paid events have measured income, then Market buyback and the already specified player
trade surface. Service/wear follows its own authority and is not smuggled into fuel.

---

## 17. Gate tests

Nothing is economically done until live PASS evidence sits in `wp/MASTER_TEST.md` (`L69`).

### Pure/offline

- field one resolves as a time trial and never earns P1;
- fields two and greater resolve as contested races;
- completion, placement, field cap, highest-only target and Tag cap resolve exactly;
- DNF/DNS/DSQ earn no completion;
- repeat windows diminish but retain an authored recovery floor;
- absent PB threshold/window means no PB money;
- negative and non-allow-listed Tags can never become line items;
- Badge theoretical liability and once-per-tier transition are deterministic; and
- procedural price resolution is deterministic for the same immutable Design revision.

### Host/database

- duplicate check-in changes balance once and creates one fee row;
- insufficient funds creates neither entry nor debit;
- duplicate settlement changes balance once per legitimate line;
- result and receipt cannot survive without their payout set, or vice versa;
- cancellation and restart recovery refund exactly once;
- two simultaneous world-first submissions award the limited reward once;
- duplicate Badge, Research, fuel, trade and buyback requests are inert;
- a trade's money and every exact asset transfer commit together; and
- balance always equals the ledger sum after restart.

### Live

- a solo Driver can enter, finish, read the statement and repeat without another human online;
- a contested race uses the race table and the locked field amount;
- the Guide agrees with the resulting statement;
- a DNF keeps the entry fee and receives no completion line;
- an admin-cancelled event returns the fee visibly;
- a Market purchase, race payout and later fuel debit all reconcile to one displayed balance; and
- no client retry, reconnect or resource restart creates a duplicate cent.

---

## 18. Deliberately open balancing data

The contract is build-authorised without pretending these numbers are final:

- championship tables above Street and exact high-tier Machine acquisition-time targets;
- Street repeat-floor amount, payout-window duration and PB improvement threshold;
- exact Research programs, eligibility bands, budgets and consent wording;
- final Badge catalogue and unique-Badge flat amounts;
- sponsor bounty rotations and budgets;
- fuel capacities, coefficients, carrier prices and emergency recovery ceremony;
- Market buyback percentage; and
- whether later player trades carry a listing/transaction tax.

Each has an explicit configuration or later work-package seam. None justifies delaying Slice A.
