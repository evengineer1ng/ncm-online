# 23 — Open design questions, from the classified ledger

> **STATUS: HISTORICAL** - the Q1-Q70 question set, answered 2026-09-24 (L123). A record of a moment, never architecture.
> Authority map: [INDEX.md](../INDEX.md) - classified 2026-09-24 (L125)

**Raised 2026-09-24**, after classifying all 177 BACKLOG rows (L122). These are the questions whose answers change
the *data model*, not the presentation. Numbering is **permanent** — answer by number, and a later session can
cross-reference `Q31` without ambiguity.

Each question carries:

- **[BLOCKING]** — an F0/F1 item cannot be built correctly until this is answered
- **[SHAPES]** — does not block a start, but changes the model enough that retrofitting is expensive
- **[LATER]** — cheap to answer now, cheap to defer; asked because it is adjacent

Where I have a view, it is marked **▸ my recommendation**, so the answer can be "agree" rather than an essay.
Where I genuinely do not have a view, I say so. **No question here is rhetorical** — I am not asking for
confirmation of things already decided (L119/L120/L121/L122 stand).

---

## §A — Identity and serialisation (the P0 cluster)

**Q1. [BLOCKING]** `IDEA-236`: confirm `asset_id` is added to `session_result` now, as the next production
migration, ahead of other work?
▸ *Yes. It is the only item in the ledger that is losing data every time the server is used.*

**Q2. [BLOCKING]** When the car raced is **not** an asset (NCX team car, league grid car), what does `asset_id`
hold? This is the real question behind Q1, because it decides whether the column can ever be trusted.
(a) nullable, meaning "no asset" and "we didn't record it" look identical forever;
(b) nullable **plus** a separate `machine_source` enum (`owned_asset` / `team_equipment` / `unrecorded_legacy`);
(c) require every raced car to be an asset, which forces `IDEA-238` to "yes".
▸ *(b) at minimum. It costs one small column and makes the 29 legacy rows explicitly legible as
`unrecorded_legacy` rather than silently indistinguishable from a team car.*

**Q3. [SHAPES]** Should the 29 existing anonymous results be stamped `unrecorded_legacy`, or left NULL?
Stamping is a one-time UPDATE on production and writes no false history — it records *that we did not record*.
▸ *Stamp them. It is the honest version of a gap.*

**Q4. [BLOCKING]** `IDEA-238`: do NCX invitational team cars become persistent assets?
If yes: who owns them — the team (`team_id`), a system/league owner, or nobody (`ncm_driver_id` nullable)?
If no: they can never accrue mileage, carry components, or wear, and that exclusion becomes permanent.

**Q5. [SHAPES]** If team cars become assets, do they draw from the **same** production ordinal sequences as
player-purchasable machines, or a separate league/equipment sequence?
▸ *Separate. "NCM #0000001" should mean a machine that entered the world's economy, not a piece of league kit.*

**Q6. [BLOCKING]** `IDEA-233`: do admin/progression grants carry serials? And a distinction the row does not
currently draw — **is an admin debug car the same kind of thing as a progression reward car?**
(a) both unserialised (today's behaviour);
(b) both serialised from the main sequence (a debug car burns Ferrari #14);
(c) reward cars serialised, debug cars not, distinguished by `origin`.
▸ *(c). A car awarded for an achievement is a real machine with a real birth; a car spawned to test a panel is not.*

**Q7. [SHAPES]** Is `origin` on `vehicle_asset` intended to be a **permanent, queryable classification** (so the
Machine Index can say "this is a granted car") or an internal bookkeeping field the player never sees?

**Q8. [BLOCKING, and larger than it looks]** Once components exist, "which machine raced" is no longer the whole
truth — **"which machine, in which configuration"** is. Do we capture a configuration reference on
`session_result` at settlement?
Without it, historical results can never say what the car actually was, which is the identical failure to `IDEA-236`
one level deeper — and equally impossible to backfill.
▸ *Reserve the column now even if nothing writes it until components ship. The lesson of Q1 is that "we'll add it
later" is how 29 results became anonymous.*

**Q9. [SHAPES]** Does a machine's identity survive a change of **every** component? (The ship-of-Theseus question,
which matters because `IDEA-279` says components keep their own exposure.)
▸ *Yes — the asset is the identity, components are contents. But it should be a stated invariant, not an accident.*

---

## §B — Component identity and inventory

**Q10. [BLOCKING]** `IDEA-241`: is **every** component a serialised asset with its own identity, or do some
families exist as fungible/stackable quantities (fluids, fasteners, consumables)?
▸ *Serialise anything that can wear, be installed, or be traded individually. Resist a second "quantity" concept
unless a family genuinely needs it — two ownership models is a permanent tax.*

**Q11. [SHAPES]** `IDEA-281` says some families have **no meaningful wear**. Do those families still get asset
identity (for trading and provenance), or are they authored data only?
▸ *Asset identity yes, lifecycle no. Tradability and wear are different reasons to be an object.*

**Q12. [BLOCKING]** `IDEA-246`: where do owned-but-uninstalled components live?
(a) a flat per-driver list with no location;
(b) located storage (garage / workshop / specific place), which makes "you must be where the part is" real;
(c) both, with location nullable.
▸ *(b). Location is nearly free to add now and impossible to introduce later without inventing where everything
already is. It is also what makes a workshop a place rather than a menu.*

**Q13. [SHAPES]** Is storage **capacity-limited**? (`IDEA-263` already anticipates workshop *capacity* for
projects.) A limit is an economic lever; unlimited storage is a decision too.

**Q14. [BLOCKING]** Confirm the install invariant: installing **moves** a component asset (location changes from
storage to vehicle), never mints or destroys one; removing does the reverse. Is a component ever *consumed* by
installation?
▸ *Confirm move-only, with exactly one exception already accepted: destructive reverse engineering (`IDEA-264`).*

**Q15. [SHAPES]** Can a component be installed into a vehicle owned by **someone else** — the customer-car case
that makes an engineering service business possible? If yes, who owns the part afterwards, and what records the
customer's consent?

**Q16. [BLOCKING]** When a **vehicle is sold or traded, do its installed components go with it?**
(a) always, as one indivisible bundle;
(b) never — parts must be removed first;
(c) the seller chooses per component, and the trade envelope lists exactly what is included.
▸ *(c), and this is one of the strongest arguments for designing the trade envelope (`IDEA-247`) before parts
exist rather than after. "I'm selling the car but keeping the gearbox" is a real motorsport sentence.*

**Q17. [SHAPES]** What happens to installed components when a vehicle reaches a **terminal lifecycle state**
(`IDEA-229`, currently disabled)? Released to the owner's storage, or retired with the machine?

---

## §C — The vehicle ↔ component boundary (the migration cluster)

**Q18. [BLOCKING]** `IDEA-240`: the mechanical architecture profile must be authored against the existing
catalogue. Is that **27 vehicles authored by hand now**, and who authors it — me proposing and you reviewing, or
you specifying?

**Q19. [SHAPES]** How complete must a profile be? Must every vehicle declare a slot for all twelve families, or is
a **sparse** profile legal (a vehicle simply has no entry for families it does not meaningfully have)?
▸ *Sparse. A forced full fitment invents parts nobody asked for and makes adding family #13 a rewrite.*

**Q20. [BLOCKING — the big one]** **Do the 19 existing vehicle assets get factory components retrofitted?**
Wear is component-level. If existing machines have no components, they have nothing to wear, and the first
component-bearing car is mechanically different from every car bought before it.

**Q21. [BLOCKING, follows Q20]** If yes — **what exposure do those backfilled components start with?**
(a) zero, meaning a 12,000 km machine has brand-new internals, which is a false history;
(b) the vehicle's odometer, so components inherit the distance the machine actually travelled;
(c) zero, but with an explicit `backfilled_at_odometer` marker so the gap is visible and honest.
▸ *(b) for anything whose exposure dimension is distance. It is the only option that does not make the machine lie
about itself, and it respects "do not rewrite history" by deriving from history we actually have.*

**Q22. [SHAPES]** Once components carry exposure, **does the vehicle odometer keep accruing?**
▸ *Yes, and they are different facts: the odometer is the machine's biography (`IDEA-228`, already live and
player-visible); component exposure is a wear input. Keep both, never sum them, never derive one from the other
after the initial backfill.*

**Q23. [SHAPES]** Do newly **manufactured** vehicles arrive with a full set of factory components, produced as
part of the same act? If so, those components need their own ordinals and provenance from day one.

**Q24. [LATER]** Cyberpunk/OPEN//77 have their own vehicle damage/health. `IDEA-280` says wear comes only from
distance and never from collisions. Does NCM **ignore platform vehicle damage entirely** for persistent purposes?
A visibly wrecked car with pristine components is a slight dissonance we should accept knowingly.
▸ *Ignore it. Adjudicating crash damage into persistent property is exactly the griefing/litigation surface
`IDEA-280` exists to avoid.*

---

## §D — The wear model

**Q25. [BLOCKING]** `IDEA-281`: what is the **vocabulary of exposure dimensions**? Distance is first-generation.
Do you want to name the others now (operational time, thermal/load cycles, actuation count, none), or should I
propose a closed list for review?
▸ *Let me propose a closed list. It should be small and closed — an open-ended dimension vocabulary is how this
becomes unbounded.*

**Q26. [BLOCKING]** `IDEA-283`: the lifecycle seed is established "at manufacture or another legitimate boundary".
For **backfilled** components (Q20) there is no manufacture event. Derive the seed deterministically from the
component `asset_id`?
▸ *Yes — deterministic from asset id, so it is stable, unrerollable and needs no stored event.*

**Q27. [SHAPES]** Does exposure accrue **only while installed and the vehicle is moving**? A part in storage
accrues nothing — confirm. And a part installed in a parked car accrues nothing, per KB-88's speed witness.

**Q28. [SHAPES]** When several components are installed, does each accrue the **same** distance (the vehicle's), or
is there any per-component weighting?
▸ *Same distance, weighted only by the family's own threshold profile. Per-component weighting duplicates what
thresholds already express.*

**Q29. [BLOCKING]** What is the **first visible consequence** of wear? The safest first ship is
**information only** — Diagnostics can observe condition, nothing mechanical changes — which lets wear accrue and
be proven before it has any effect.
▸ *Information-only first. It also sequences perfectly with the engineering first slice (Q41).*

**Q30. [SHAPES]** `IDEA-289` accepted graded repair relief with **diminishing returns required**. Do you want
per-service diminishing, cumulative capping, or both authored with one disabled pending play data?
▸ *Both authored, cumulative cap disabled initially.*

**Q31. [SHAPES]** Can a repair ever make a component **better than it was when new** — i.e. can `relief_m` push
the effective threshold past the original baseline? `IDEA-284` says wear is never a benefit; `IDEA-272` allows
installation workmanship a modest benefit.
▸ *No. Repair restores toward baseline and buys distance; it never exceeds the design's original potential. That
keeps the four layers (`IDEA-275`) from leaking into each other.*

**Q32. [LATER]** Do components have terminal states (unrepairable, scrapped, consumed by RE)? If so, is the
vocabulary shared with vehicle lifecycle (`IDEA-229`) or separate?

---

## §E — Engineering

**Q33. [BLOCKING]** `IDEA-259`/`IDEA-260`: the 15 skills / 5 disciplines / 12 families shape is **provisionally**
accepted (L120) pending your review of the actual ontology. Do you want to review the concrete skill list before
I model storage, or model against the shape and let the list move?
▸ *Review first. You flagged Diagnostics yourself; the list is where the next such mismatch would hide.*

**Q34. [BLOCKING]** Competency storage shape: is competency held **per skill** (15 values), **per skill × family**
(up to 180), or **per skill with family modifiers**? The proposal said "at most 27 values per engineer" — I want
that pinned before it becomes a table.

**Q35. [SHAPES]** Is engineering competency **per driver globally** or **per server**? Everything canonical today
is keyed `server_id`; cross-server identity is blocked (`IDEA-014`) but the choice is made the moment the table
exists.

**Q36. [BLOCKING]** `IDEA-262`/`IDEA-263`: do asynchronous projects advance in **real elapsed time while the
player is offline**, or only while connected?
▸ *Real elapsed time. "Survives logout" is explicit in the spec, and the `market_production_run` claim-then-verify
pattern already does exactly this and survived a live restart.*

**Q37. [SHAPES]** Is **workshop capacity** (a limit on parallel projects) in the first model, or architected and
left unbounded? `IDEA-263` says preserve the possibility.
▸ *Architected, unbounded initially — a column that exists and is not enforced.*

**Q38. [SHAPES]** `IDEA-264`: does destructive reverse engineering require **ownership** of the component, or
merely possession? Can you RE a part a friend lent you?
▸ *Ownership. Destroying something you do not own is a support ticket.*

**Q39. [SHAPES]** `IDEA-256`/`IDEA-257`: if A trades a part to B, does B automatically learn the **design**, or
must B inspect/analyse it? The invariant says owning must not grant market access — it is silent on knowledge.
▸ *Possession grants "exists" and "specification" at most; everything deeper requires Diagnostics work. That is
what makes the knowledge ladder worth climbing.*

**Q40. [LATER]** Is there a **reputation** surface distinct from competency — "known for being good at this" —
or does reputation emerge entirely from provenance (`IDEA-276`) appearing on components?
▸ *Emergent from provenance first. A reputation score is a second bounded number to balance.*

**Q41. [BLOCKING]** Confirm the first engineering slice is **Diagnostics-only against the 19 existing vehicle
assets**, needing no components (accepted at L120) — and that it ships **before** component assets exist?
This is the one place the two accepted first-slices disagree on ordering: engineering's slice needs no components,
wear's slice requires them.

---

## §F — Markets, distribution, discovery

**Q42. [BLOCKING]** `IDEA-251`: confirm market discovery is wired up **before** parts exist? The substrate
(`player_market_knowledge`, `markets.known()`) is already built and unused.
▸ *Yes. It is the cheapest foundational item in the ledger — finishing an existing half-built thing.*

**Q43. [SHAPES]** What **discovers a market**? Physical proximity, a referral from another player, a purchase, or
explicit in-world signage? `source_kind`/`source_ref` already anticipate several authorities.

**Q44. [BLOCKING]** `IDEA-254`: is a market's catalogue **authored per design**, or **derived** from
manufacturer/family/line relationships? The stated constraint is that affiliating a manufacturer must not
auto-list every future product forever — which rules out naive derivation.
▸ *Derived from relationships, but with an explicit per-design admission step, so autonomous R&D output never
appears in a storefront without something having decided it should.*

**Q45. [SHAPES]** Do **players ever sell into markets**, or is player-to-player commerce exclusively barter
(`IDEA-247`)? `IDEA-270` warns that one manufacturer must not flood every market — does that apply to players?

**Q46. [SHAPES]** Is there a **secondary market** surface (listings, asking prices, browsing what others offer),
or only direct negotiated trades? This is a large scope fork and I do not have a recommendation without knowing
how social you want the economy to feel.

**Q47. [LATER]** `IDEA-252`: does the Base Market carry the introductory component selection, or does the parts
economy start at a **different, discoverable** market so parts feel like something you go and find?

---

## §G — Trading and transactions

**Q48. [BLOCKING]** `IDEA-247`: design the **trade envelope** now, before component assets exist? The conflict is
already identified — `vehicle_asset_transfer` is per-asset with a per-asset idempotency key, and purchase is
single-asset, so multi-item atomic trade does not fit the current shape.
▸ *Now. Retrofitting atomicity onto a per-asset ledger after parts exist is the expensive version.*

**Q49. [BLOCKING]** Is a trade **synchronous** (both players present, both confirm) or an **offer that persists**
(A offers, B accepts later)? Persistent offers need escrow — the offered items must be locked so they cannot be
sold twice.
▸ *Synchronous first, but design the envelope so escrow can be added. Synchronous needs no lock; persistent
offers cannot be made safe without one.*

**Q50. [SHAPES]** Can money alone be transferred between players (a gift or payment with no goods), and is there
any record of *why*? Paying an engineer for work is exactly this.

**Q51. [SHAPES]** Does NCM support a **service contract** — "install this part, I pay on completion" — or is
payment purely a matter of trust between players?
▸ *Trust first, contracts later. But the trade envelope should not make contracts impossible to add.*

**Q52. [LATER]** Are trades **reversible** by an admin (fraud, bug), and if so, how does that interact with
append-only provenance? A reversal should be a new compensating transfer, never a deletion.

---

## §H — Economy

**Q53. [BLOCKING]** `IDEA-012`: the ledger currently runs on a €$10,000 starter and three authored prices. Parts
need a price model. Do you want an **economy design pass before parts pricing**, or should parts be priced against
the current starter economy and re-tuned later?

**Q54. [SHAPES]** What are the intended **money sinks**? Today there is effectively one (buying a car).
Repairs, parts, storage, entry fees and RE material cost are all candidates. Without sinks, any income source
inflates the currency permanently.

**Q55. [SHAPES]** Is there **income** beyond the starter grant yet — race purses, prize money? `IDEA-012` says the
ledger runs at zero. Parts and repairs are sinks; if there is no tap, the economy drains to zero and stops.

**Q56. [LATER]** Should component **prices be authored or derived** (from family, rarity, manufacturer, quality
vector)? Derived pricing scales to procedural R&D output; authored does not.
▸ *Derived, with authored overrides — R&D can mint designs faster than anyone can price them by hand.*

---

## §I — Behaviour, rulesets, telemetry

**Q57. [SHAPES, and time-sensitive in the same way as Q1]** `IDEA-069` behavioural history: races are happening
now and incidents are already classified. **Do we start recording behavioural facts before the chrome systems
that will read them exist?** Anything not recorded now is not reconstructible later.
▸ *Start recording. It is the same lesson as `IDEA-236`, and the recording is cheap while the consequences are
still undesigned.*

**Q58. [BLOCKING for chrome, cheap now]** `IDEA-068`: the row argues permitted-capability sets on rulesets are the
cheapest part of the whole chrome concept and should be built first, because they make everything else safe to add.
Confirm building that now, ahead of any chrome mechanic?

**Q59. [BLOCKING]** `IDEA-054`: telemetry retention tiers must be decided **before** the table grows.
`telemetry_chunk` accrues ~raceSeconds/10 rows per driver per session. Confirm the three tiers (session-hot days,
derived-warm season, permanent records), and name the actual retention for hot — 7 days? 30?

**Q60. [SHAPES]** Confirm the derivation to warm runs **at settlement**, not on read, so deleting hot data can
never damage warm or permanent?
▸ *Yes — this is the whole reason the tiering works.*

**Q61. [LATER]** Does telemetry retention differ between a **sanctioned championship** round and a casual street
race? Keeping everything for the former is defensible; for the latter it is the table that eats the disk.

---

## §J — Sequencing and gates

**Q62. [BLOCKING]** `IDEA-249` (engine-capability audit) gates all component **effects**. Confirm the split:
component identity, inventory, trading, wear accrual and provenance can all be built **before** the audit, because
none of them touch vehicle behaviour — only effects wait.

**Q63. [BLOCKING]** `IDEA-287`: §AG5/§AG6 odometer QA must pass before distance carries economic weight. Confirm
those now run on the **development box** (they are destructive/console-driven), and that passing there is
sufficient, or whether you want them re-proven on production.

**Q64. [BLOCKING]** Given Q41's ordering tension, confirm the intended build order. My proposal:
1. `IDEA-236` + Q2 columns (stop the bleeding)
2. `IDEA-251` market discovery (finish the half-built thing)
3. `IDEA-068` permitted-capability sets (cheap, makes later work safe)
4. Engineering Diagnostics slice (no components needed)
5. `IDEA-247` trade envelope design
6. Component assets + `IDEA-240` architecture profiles + backfill (Q20/Q21)
7. Exposure accrual, information-only (Q29)
8. Effects, after `IDEA-249`

**Q65. [SHAPES]** Do the remaining **GATE** rows (`IDEA-004` empty-server run, `IDEA-031` settlement replay,
`IDEA-032` "no 20 anywhere", `IDEA-033` adversarial gates) get scheduled now that a dev box can run them without
touching the world? `IDEA-031` in particular — double settlement is "silently fine for months and then eats a
championship" — and the economy is about to get much larger.

---

## §K — Process

**Q66. [SHAPES]** Do F0 schema changes now go to production **individually as they are ready**, or batched into a
deliberate promotion? L121 says promote known revisions; it does not say how big a revision should be.
▸ *Individually for F0. A schema gap that is losing data should not wait for company.*

**Q67. [SHAPES]** Do you want a **schema freeze checkpoint** — a point where the F0 set is declared final and
reviewed as a whole — before parts work starts writing new tables?
▸ *Yes. It is the concrete version of "parked at the door", and it is cheap while the tables do not exist.*

**Q68. [LATER]** Should the **INV rows become an explicit invariant register** — a short document of rules the
model must obey, testable where possible — rather than 14 backlog rows that are easy to lose track of during
implementation?
▸ *Yes, and several are mechanically testable (wear monotonic, exposure never decreases, install conserves assets,
repair never exceeds baseline). Invariants with tests are worth ten times invariants in prose.*

**Q69. [LATER]** `IDEA-242` R&D: how large should the **authored seed catalogue** be before procedural generation
is allowed to add to it? A generator with nothing to imitate produces noise.

**Q70. [LATER]** `IDEA-244`: do you want to **review generated component names** before they become permanent
identity, at least for the first generation? Names are provenance once they are issued.

---

## How to answer

Answer by number in one pass. `"Q14 agree"` is a complete answer where I have made a recommendation.
Anything left unanswered stays open and I will not infer it — an unanswered structural question is a better
outcome than a guessed one.
