# 08 — Money, purses, entry fees and recovery (audit, 2026-09-22)

> **STATUS: CURRENT** - authority for: *economy intent* - affirmed 2026-09-24 (L84, L85)
> Authority map: [INDEX.md](INDEX.md) - classified 2026-09-24 (L125)

> Primary-market scope is governed by [17_MARKET_NETWORK.md](17_MARKET_NETWORK.md): Base Market is one stable
> `marketId`, inventory is market-scoped authored supply, and F6 is not an omniscient global shop.

**Status:** the wider economy remains an audit/design. The first narrow non-zero slice is now built locally,
not deployed: migration 017 adds ledger idempotency/provenance, Base Market grants €$10,000 once, and one atomic
vehicle purchase debits the derived ledger balance. Fees, purses, recovery, loans and wider balance remain
unimplemented. Decisions go in `DECISION_RECORD.md`, ideas in `BACKLOG.md`; this is the reasoning behind IDEA-117
and its children.

> Finishing races keeps you alive. Performing well moves you forward. Expensive ambitions pull money back out.
> Mistakes create risk. Going broke gives you a road back, not free money.

---

## 1. Current-state findings

### The headline: the ledger already exists and settlement already writes to it

**L21 said "start money-free; build the ledger now", and that was actually done.** This is not a green field.

| Thing | Where | State |
|---|---|---|
| `ledger` table | migration 004 | **Exists.** `ncm_driver_id, server_id, kind, amount INT, currency VARCHAR DEFAULT 'eddies', ref, note, created_at` |
| A ledger write per race | `race.lua` ~line 380 | **Exists and runs today**, `kind = 'race_result'`, **`amount = 0`**, `ref = sessionId`, note carrying `P3 finished Ukulele` |
| `entry.fee INT NOT NULL DEFAULT 0` | migration 003 | **Exists**, always written as 0 |
| `issued_vehicle.cost INT` | migration 002 | **Exists**, always 0 |
| `owned_vehicle` | migration 012 (today) | **Exists** |
| `issued_vehicle.model` | migration 002 | `ENUM('issued','loaner','owned','byo')` — **`loaner` is already reserved** |
| Championship config | `packs/street.lua` | Already carries `eligibility`; economy belongs beside it |

`competition/entry.lua:43,67` and `competition/guide.lua:102` all hardcode `fee = 0` with the comment
*"L21: money-free first world"*, and `world/provisioning.lua:31` returns `cost = 0` with *"the ledger line exists
with amount zero"*. **The seams were deliberately left open.** The work is switching them on, not cutting them.

### The gap that matters most

**The ledger has no idempotency key.** `PRIMARY KEY (ledger_id)` is auto-increment and the only other index is
`KEY ix_ledger_driver (ncm_driver_id, created_at)`. Nothing stops the same row being written twice.

Today that is harmless because every amount is 0. **The moment an amount is non-zero, a settlement retry pays the
purse twice** — and this is not hypothetical: it is exactly the shape of KB-38, where `INSERT IGNORE` failed to
dedupe accomplishments because the unique key included the session id. That bug cost a wrong badge. The same bug
in the ledger costs money and is invisible until someone audits balances.

**Nothing may write a non-zero amount before this key exists.**

### A competing wallet already exists on the same server

`open77_freeroam/server/persistence.lua` keeps `players.money BIGINT NOT NULL DEFAULT 0`, keyed by **platform
identifier**, and logs it on every join (`A joined (money=0)`). It is a bare balance column, not a ledger.

NCM's economy is keyed by `ncm_driver_id` and is per-server career state (L54/L55). These are two different money
systems with two different identity models. **They must not be silently merged**, and the decision to keep them
separate should be explicit rather than accidental — otherwise someone will eventually "fix" the fact that a
player has two balances.

### Identity and persistence

`ncm_driver` (global) → `ncm_driver_binding` (per server, per platform user) → `driver_profile` (per server,
with `dimensions` and `sr` as JSON). Progression writes `driver_licence`, `driver_sr`, `driver_rating`,
`accomplishment`, all keyed `(ncm_driver_id, server_id)`.

**A balance belongs at exactly that grain**: per driver, per server. Not on `driver_profile.dimensions` JSON —
money is not a dimension (L54 lists the four and money is not among them), and a JSON blob cannot be summed,
indexed or audited.

### Registration and settlement lifecycles

**Entry** (`calendar.lua enterPlayer`): resolve driver → **KB-37 busy check** → **L83 eligibility check** →
`Entry.checkIn` (window + position) → DB insert/update → bag → chat/toast → publish. The `entry` table has
`UNIQUE KEY ux_entry_event_driver (event_id, ncm_driver_id)`, so **one entry per driver per event is enforced by
the database**. Interest → entry is an *upgrade of the same row*, same `entry_id` (P52/L48).

**Settlement** (`race.lua complete()`): one `UPDATE session`, then per result a `session_result` insert
(`PRIMARY KEY (session_id, ncm_driver_id)`), an `entry` state update, and the zero-amount ledger line. Then
`NcmProgression.apply` per driver. `complete()` runs once per session in memory (guarded by `s.phase`), and a
session lost to a resource restart is not restored, so there is no re-settlement path today — **but the ledger
must not depend on that remaining true.**

Notably, the ledger write is already guarded to `rec.kind == "race"`, so **practice and qualifying never write a
ledger line**. The "practice is not a faucet" requirement is already structurally true.

---

## 2. Recommended data model

### Ledger first, balance derived

```sql
ALTER TABLE ledger
  ADD COLUMN idem_key VARCHAR(190) NULL,
  ADD COLUMN event_id VARCHAR(160) NULL,
  ADD COLUMN session_id CHAR(36) NULL,
  ADD UNIQUE KEY ux_ledger_idem (idem_key);
```

Every write supplies an `idem_key` it constructs deterministically — `entry:<eventId>:<driverId>`,
`payout:<sessionId>:<driverId>`, `starter:<driverId>:<serverId>` — and uses `INSERT … ON DUPLICATE KEY UPDATE
ledger_id = ledger_id` (a no-op touch). A retry then cannot double-charge or double-pay, and the key says why.

`kind` stays the category (`starter_grant`, `event_entry`, `event_payout`, `entry_refund`, `loaner_grant`, later
`repair`, `purchase`). `ref` stays free-form; the new typed `event_id` / `session_id` columns are what telemetry
groups by without parsing strings.

**Balance is `SUM(amount)`**, cached in memory per connected driver the way `NcmOwnership` caches the garage, and
invalidated by the one module that writes. Do **not** add a `balance` column: a derived balance cannot drift from
its own history, and "why does this player have this balance" is answerable by definition.

### Economy lives on the championship, overridable per event

Beside `eligibility` on each series, because that is where sporting identity already lives and the owner is
explicit that routes own geography only:

```lua
economy = {
    entryFee    = 250,
    purse       = { P1 = 750, P2 = 500, P3 = 350 },   -- an explicit table, not a formula
    completion  = 120,                                 -- paid to every classified finisher
    dnf         = 0,                                   -- and DNF gets no completion value
    fieldBonus  = { perEntrant = 40, max = 240 },      -- capped, so population cannot inflate
    timeTrial   = { completion = 90, personalBest = 150, dailyCompletions = 1 },
}
```

**A table, not a universal formula.** The brief is right to be wary of one: a payout table is readable, showable
to the player verbatim, and tunable per championship without anyone re-deriving algebra. A formula is only worth
introducing where a table cannot express the shape (the field bonus is the one place, and it is two numbers).

Entry fee and purse are **independent knobs** — the purse is a faucet, the fee is a sink, and nothing in this
model makes the purse a function of collected fees. A three-car City Cup collecting €$750 and paying €$1,600 is
just two numbers.

---

## 3. Lifecycle: where to charge, where to pay

**Charge at check-in, not at interest.** Interest is a soft list with no reservation (L48/P52); charging there
would make browsing cost money. Check-in is the explicit committing act, it already has the busy and eligibility
guards in front of it, and `ux_entry_event_driver` gives the charge a natural idempotency anchor. `entry.fee`
already exists to record what was charged.

**Pay at settlement, inside `complete()`**, where the zero-amount line is already written — one call site, already
per-driver, already keyed by session.

Refund policy, stated as behaviour rather than code:

| Event | Fee | Reasoning |
|---|---|---|
| Withdraw before entries close | **Refunded** | They gave the slot back in time |
| Withdraw after close / DNS | **Kept** | The grid was formed around them |
| **DNF** | **Kept, no completion payout** | L83-adjacent: "bring the car home" needs teeth |
| Event cancelled by the server or an operator | **Refunded** | We failed, not them |
| Session abandoned / never went green | **Refunded** | Nothing was raced |
| Disconnect before start | **Kept** (DNS) | Otherwise disconnecting is a free option |
| Disconnect during the race | **Kept** (DNF) | Same |
| Resource restart with the event unresolved | **Refunded by sweep** | The one case the brief names explicitly: we must not eat a fee because the server failed |

That last row is the only one needing new machinery: a boot-time sweep for `event_entry` lines whose event never
produced a settlement, refunding them with `idem_key = refund:<eventId>:<driverId>`. Idempotent by construction,
so running it twice is free.

---

## 4. Transparency and when the purse locks

The Race Guide payload (`ncmGuide` slim rows in `guide.lua`) is already the place, and already carries per-event
facts. Add `entryFee`, `purse` and `payout` rows to it and the guide can show:

```
ENTRY €$250 · PURSE €$1,600
P1 €$750 · P2 €$500 · P3 €$350
```

**Recommendation: the purse is locked when the grid forms, not when entries open.** The field bonus depends on
entrant count, which is not final until then, and inventing a number earlier means correcting it later. Before
lock, show the base table plus "+€$40 per entrant, up to €$240" — an honest statement of a rule, not a guess. The
venue option list (IDEA-095) already has a natural place for the committed number at the moment of entry.

---

## 5. Time trials and farming

A time trial is a race with a field of one (L67), so it settles through the same path and needs no separate
economy. The exploit the brief names — repeat a short route forever — is real: **B-line is a drag sprint and the
shortest thing on the calendar.**

The seam, without locking the policy: the ledger itself is the anti-farming record. A query of the form *"has
this driver been paid `event_payout` for this route in the current window?"* is answerable from
`(ncm_driver_id, kind, event_id, created_at)` without new tables. So:

- first qualifying completion per route per window pays completion value;
- subsequent ones pay 0 completion but still pay a genuine personal-best bonus;
- practice stays free and unlimited, and **already writes no ledger line at all**.

`dailyCompletions` in the economy block is the tuning knob; the enforcement reads the ledger.

---

## 6. Concurrency

Already handled by the shape the code is in. Economic state is per event and per session: `entry.fee` is per
entry, payouts key on `session_id`, and `sessions`/`byEvent`/`plans` are all keyed maps (IDEA-112 removed the last
global). **There is no "current purse" anywhere and there must never be one.**

One restriction worth adopting: a driver may hold entries in several *future* events, but KB-37 already forbids
being in two live sessions. Since the fee is charged at check-in and check-in requires being at the venue, a
driver cannot be committed to two events at once in practice.

---

## 7. Telemetry from day one

All of it falls out of the ledger with no extra writes, provided the typed columns exist:

- money created: `SUM(amount) WHERE amount > 0 GROUP BY kind` — starter grants vs payouts, separable;
- money destroyed: the same for `amount < 0`;
- per-championship economics: `GROUP BY` the series id parsed from `event_id`, or store `series_id` too;
- net result per event, per driver: `SUM(amount) … WHERE event_id = ?`;
- balance distribution: `SUM(amount) GROUP BY ncm_driver_id`;
- bankruptcy frequency: balances at or near zero;
- farming patterns: repeated `event_payout` on one route by one driver in a window.

**Recommendation: add `series_id` to the ledger as well.** Parsing it out of `event_id` works (ids are
`seriesId@startsAt`) but it is the same "a parsed id is not a catalogue" mistake that bit us in IDEA-113.

The one thing that does *not* fall out for free is the brief's §13 denominator — earnings per racing hour. Worth
recording `session.completed_at - session.green_at` alongside payouts, which `session` already has.

---

## 8. The two future seams

**Vehicle repair/recovery.** Already safe. Ownership (`owned_vehicle`) is separate from the spawned entity
(`issued_vehicle.vehicle_id`) and there is no condition concept anywhere — so adding `owned_vehicle.condition`
later touches nothing economic. The only rule to hold now: **never delete an `owned_vehicle` row on destruction**.

**The MaiMines.** The seam exists and is one word: `issued_vehicle.model` is already
`ENUM('issued','loaner','owned','byo')`. A loaner is a vehicle a driver may use but does not own — which is
exactly an `issued_vehicle` row with `model = 'loaner'` and no `owned_vehicle` row. Nothing needs designing now
beyond **not conflating the two tables**: `NcmOwnership.owns` must keep meaning *owns*, and eligibility must
eventually ask "owns or has on loan", not "owns". That is a one-line change later precisely because the tables
are separate.

The recovery trigger — balance at zero **and** no eligible car — is answerable from the ledger plus the garage,
both of which will exist after the first slice.

---

## 9. Conflicts with existing decisions

- **L21 ("start money-free")** must be amended, not deleted. It explicitly anticipated this: *"money can be
  switched on later without rebuilding race settlement."* It was right, and the ledger it demanded is why this
  audit is short.
- **L55** says *"prize/fee schedules live on rulesets"*. The owner now says championship/event. Rulesets today
  carry sporting rules (incidents, start type, hold) and nothing economic, so this is a live contradiction that
  needs one sentence in the decision record. **Recommend the championship**, to match where `eligibility` went.
- **L54** lists the four driver dimensions; money is not one. Keep it that way — a balance is not a dimension.

---

## 10. Smallest useful first slice

In dependency order. Steps 1 and 2 are the ones that must not be skipped or reordered.

1. **Add the ledger's idempotency key and typed columns** (migration 013). *Before any non-zero amount exists.*
2. **A ledger module** — `credit` / `debit` / `balanceOf`, every write taking an `idem_key`, with the same
   cache-and-invalidate shape as `NcmOwnership`. Amounts still zero; nothing behaves differently yet.
3. **Starter grant**, idempotent by `starter:<driverId>:<serverId>`, granted at profile creation.
4. **`economy` block on each championship**, entry fee charged at check-in, recorded in `entry.fee`.
5. **Payout at settlement**, replacing the existing zero-amount line rather than adding a second one.
6. **Race Guide exposure** — fee and payout table in the guide payload.
7. **The refund sweep** at boot for unresolved events.

Deferred: MaiMines, repair economics, anti-farming enforcement (the *seam* is in step 5; the policy can wait for
observed behaviour), and every §18 anti-goal.

### Tests worth writing

Core (pure, offline): payout table resolution including ties and short fields; field bonus capping; time-trial
payout with a field of one; DNF paying no completion; refund policy as a table of (situation → fee outcome).

Host: **the idempotency tests are the ones that matter** — charge twice, assert one row and one balance change;
settle twice, assert one payout; restart mid-event, assert the sweep refunds exactly once. Those three are worth
more than every balancing test combined, because a balance bug is silent and permanent.

---

## 11. Decisions taken (owner, 2026-09-22) — recorded as L84 / L85

The audit was accepted and every open question in this document is now answered. Full wording in
`DECISION_RECORD.md`; the short form:

| Question | Decision |
|---|---|
| Starter amount and scope | **€$10,000, once per driver per server/career.** Provisional balancing data. |
| NCM money vs freeroam money | **Never meet.** No sync, mirror, convert, import, export or inference. |
| L55's ruleset-vs-championship | **Championship** owns default economics; ruleset owns sporting rules; event may override; route owns geography only. |
| Charge point | **Successful check-in**, after the busy and eligibility guards. Interest stays free and reserves nothing. |
| Withdrawal refund | Before a debit, nothing to refund. After a paid check-in, voluntary withdrawal **forfeits**. |
| Server/admin cancellation | **Full refund**, with an explicit reason. |
| DNF | Entry spent, no completion payout. |
| DSQ | Same amounts initially, but **kept distinguishable from DNF** so the policies can diverge. |
| Purse lock | **At grid formation.** Before: base payout + the field-bonus rule and cap. After: the exact table. |
| Balance | **Derived from the ledger.** Never a second mutable truth. |
| Loaners | `model='loaner'` and `owned_vehicle` stay distinct. **A loan is never ownership.** |

### Two hard holds (L85)

1. **The `idem_key` migration lands before any amount is non-zero.** Duplicate charge, duplicate settlement and
   restart/retry are **gate tests**, not nice-to-haves.
2. **The economy implementation does not begin until Deploy 11 is validated** — 39 unrun checks across §K–§O.
   Starting on top of that would deepen the built-but-unvalidated stack until a failure is hard to attribute.

### Slice order, confirmed

`idempotency/schema → ledger API at zero → starter grant → championship economy config + check-in debit →
settlement payout → Race Guide exposure → boot refund recovery.`

All monetary values stay **provisional and observable**. Economic truth and instrumentation first; balancing from
observed behaviour afterwards.
