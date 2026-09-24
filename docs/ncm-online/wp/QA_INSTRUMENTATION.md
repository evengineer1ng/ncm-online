# QA → instrumentation mapping

> **STATUS: CURRENT** - authority for: *mapping the QA corpus to instrumentation* - affirmed 2026-09-24
> Authority map: [INDEX.md](../INDEX.md) - classified 2026-09-24 (L125)

**What this is.** A durable mapping from the existing QA corpus to what NCM can observe about itself during
ordinary play. It does **not** replace, summarise or supersede the QA documents; it hangs off their stable
identifiers and points back at them.

**The QA corpus is two documents sharing one letter namespace.**

| Document | Role |
|---|---|
| `wp/OFFLINE_TEST_QUEUE.md` | **defines** the items: `### <ID> · <title>` with **Do / Pass / Result / Notes**. Categories A–T, 133 numbered items. |
| `wp/MASTER_TEST.md` | **records** live results: §R–§AD plus the numbered 2.x sections. |

They are the same corpus, not two corpora: OFFLINE `S1 · Authored route descriptions appear` is MASTER `§S1`,
item for item. Neither document alone is "the" QA document, and a new letter must be checked against **both**
(see `NOW.md`'s claim registry). §R was claimed twice for this reason and the newer claim moved to §AD.

**The number that frames this work:**

```
NOT RUN: 102     PASS: 21     FAIL: 3     PARTIAL: 2        (133 items, 2026-09-23)
```

**77% of the corpus has never been run.** Not failing — unrun. The bottleneck was never observability; it is
that 133 manual items need an operator present, and there is one operator. So the goal of instrumentation is
not "measure everything", it is **move items out of NOT RUN while nobody is awake**.

---

## Classification

Every item falls in exactly one bucket. The buckets are about *how evidence can legitimately be produced*, not
about importance.

| Bucket | Meaning | Share |
|---|---|---|
| **AUTO** | A passive observer can produce a machine-verifiable PASS or FAIL from authoritative transitions during ordinary play. | ~49 items |
| **REVIEW** | Ordinary play produces *evidence*, but the verdict needs a human. Absence is often the signal. | ~20 items |
| **MANUAL** | Subjective, visual or perceptual. No instrument can honestly answer it. | ~26 items |
| **CONTROLLED** | Needs an operator console command, a deliberate destructive/concurrent condition, or a deploy/restart boundary. | ~32 items |

Counts overlap slightly where an item has both an observable invariant and a manual half.

**These are deliberately not 100%.** Roughly a quarter of the corpus is driven by operator console commands —
`ncm.grant 1 Sport`, `ncm.scenario`, `ncm.incident` — which ordinary players never invoke. Claiming coverage
there would mean inventing proxies, and a proxy that cannot fail is not evidence.

---

## Per-category mapping

Legend for **Verdict**: what the observer may conclude on its own.
`PASS` = invariant held on a real transition · `FAIL` = invariant violated · `REVIEW` = recorded, human decides.

### G. The eight settlement fixes — **the strongest category**

Every item is a stated invariant over a race that a player runs normally.

| Item | Question | Observable | Verdict rule |
|---|---|---|---|
| G1 | Is race time real, or quantised? | race completion, `elapsedMs` | **FAIL** if the time is an exact multiple of 100 ms |
| G2 | Is green dated from `startsAt`? | session green event | **FAIL** if `greenAt` ≠ scheduled start |
| G4 | Are once-only accomplishments granted once? | accomplishment write | **FAIL** on a second `first_finish`/`first_win` for one driver |
| G6 | Does the readiness watchdog fire? | already instrumented (KB-60 sweep) | PASS/FAIL already live |
| G7 | Is entry refused while already racing? | entry refusal reason | **PASS** on `reason=in_live_session`; **FAIL** if an entry is accepted while a session is live |
| G8 | Phantom DNS? | event close with held-back entrants | **FAIL** if a driver in a live session is classified DNS elsewhere |

G3, G5 are presentation/log-format → REVIEW.

### P. Guide blocker and unsolicited calendar presentation

| Item | Observable | Verdict |
|---|---|---|
| P1 | guide publish `rows=N` + the panel telemetry already shipped (KB-65) | **FAIL** if a publish with `N>0` is followed by a panel that never drew |
| P2 | interest → republish to an open panel | **PASS** on republish within a bound |
| P3 | persistent card contents while no entry exists | **FAIL** if a named race/ring/waypoint exists with no live entry |
| P4 | ring/card/waypoint target vs `driverEvent()` | **FAIL** if they disagree — this is exactly KB-75 / **L107** |

P4 is the single most valuable instrument in the corpus: it is an invariant that was violated in three separate
places on 2026-09-23 and nothing noticed.

### T. Vehicle Collection and discovery provenance

| Item | Observable | Verdict |
|---|---|---|
| T1 | `DISCOVERED` write | PASS |
| T2 | `source_driver_id` / `source_holding` present | **FAIL** if a discovery lands with a source that is not the holder |
| T3 | repeat encounter | **FAIL** if `source_driver_id` changes after first write (anti-farm, IDEA-137) |
| T4 | self-credit | **FAIL** if `source_driver_id == ncm_driver_id` |

### B / N / O / K / A / S — auto invariants worth having

- **B3** upgrade at the line keeps the **same entry id** → FAIL on a second entry row for one driver/event.
- **B5** interest never forms a grid → FAIL if an `interested` driver is gridded without checking in.
- **N1/N2** eligibility at a venue → PASS when an entry is offered and accepted for a driver who owns a legal
  car; **FAIL** if an entry is *accepted* for a driver the eligibility rule refuses.
- **N7** the list and the server agree → **FAIL** if entry succeeds when the option list said it would not.
  Reuses `competition.venue_options` and `NcmCompetition.carRefusal` rather than restating the rule.
- **O2/O3/O4/O8** cadence, concurrency, route sharing, drag confinement → derivable from the published calendar
  at boot and over time. Cheap, no per-player cost.
- **K4/K6** a drag race actually completes; every route driven at least once → accumulate route coverage.
- **A2** no phantom win → FAIL if `first_win` increments on a single-entrant session (IDEA-001).
- **A6** counter honesty → FAIL if `entrants` counts people who are only on the list.
- **S5/S6** weather rides once, ordinal confidence → payload-shape invariants; **FAIL** on a full forecast copied
  per row, or on any numeric probability (11_WEATHER.md defers calibration).

### D. Never tested at all

- **D5** leave/rejoin mid-race → the `SUSPENDED → RESUMED` transition is authoritative and already exists. AUTO.
- **D6** the round number → duplicate of G1. AUTO.
- **D1/D2/D3/D4** console/scenario → CONTROLLED. **D7** RB15 cliff → MANUAL (a human reads a number off a HUD).

### H. Two clients

**H1/H2/H3** incident attribution are invariants, and they become observable **whenever two drivers happen to
race together** — which passive observation is uniquely good at catching, because it does not require anyone to
arrange it. `kind=car` with `other=nil` is a **FAIL** (that was KB-34). H4 CONTROLLED, H5 MANUAL.

### M. The ownership ledger

Mostly CONTROLLED (`ncm.grant`, `ncm.garage`, `ncm.revoke`). Two exceptions worth taking:

- **M1** migration applied → AUTO at boot.
- **M7** ownership survives a restart → AUTO: asset count per driver across a restart boundary.
- **M4** idempotence → REVIEW: the *invariant* (a repeat grant does not double) can be watched on any grant path,
  including the Market's, even though the item's own `Do` is a console command.

### I. The venue option list

- **I5** ENTER RACE still enters → AUTO.
- **I1, I2, I3, I4, I6, I7, I8, I10** → MANUAL. Whether a ring is *perceptible*, whether a tap feels distinct
  from a hold, whether an empty state reads as a sentence — none of these are machine-answerable.
- **I9 · "Options are absent, not greyed"** is **SUPERSEDED by L108**, which reverses that rule: options are now
  always present and greyed with a reason. **The item is left in place and marked, not deleted** — it is a true
  record of what was once required and why it changed.

### C, R — CONTROLLED

`C1–C8` are Warden scenario commands. `R1–R5` are upgrade/boot checks, including R1 which is a standing step
for every future upgrade. Passive play cannot touch either, and should not pretend to.

### J, F, Q — MANUAL

`J1–J7` (Guide layout, clipping at 1920×1080), `F1–F6` (glyph legibility in motion and daylight), `Q2–Q5`
(clothing appearance, two-client visual agreement). These are presentation-quality questions. An instrument
could confirm a payload field exists; it cannot confirm a glyph is *legible*.

### E. Free-driving observations — **MANUAL, permanently**

E has no numbered items at all. Its whole content is:

> *"anything that made you hesitate about what to do next — that last one is the most valuable note in the file."*

No instrument will ever produce that sentence. It is listed here so that nobody later mistakes E's absence from
the instrumentation surface for an oversight.

---

## Rules the instrumentation must follow

1. **Facts, never conclusions.** Record `calls=3, then help_opened`. Never `PLAYER_CONFUSED=true`.
2. **Observe, do not re-implement.** Where an invariant already has an authoritative implementation
   (`competition.venue_options`, `NcmCompetition.carRefusal`, `competition.eligibility`), the observer asks that
   code rather than restating the rule — otherwise a second "telemetry truth" drifts away from domain truth.
3. **The flag gates the writing, not the observing.** Domain code emits the events it already emits; one
   observer subscribes. Disabling unsubscribes. No `if qaEnabled` inside domain logic.
4. **Missing transitions are evidence.** A venue reached with no registration interaction offered is worth a
   REVIEW row. So is a guide published with rows that never drew.
5. **Bounded and deduplicated.** One row per transition, not per tick. A repeated identical observation updates
   a count; it does not add a row.
6. **Instrumentation failure is never a gameplay failure.** Every observation is wrapped; a throw is swallowed
   and logged.

## Explicitly out of scope

Progression, achievements, engagement metrics, behavioural profiles, funnels, scoring, or any analytics that
would change what the game rewards. This pass makes the existing QA corpus observable. It does not invent
gameplay, and it does not change gameplay semantics to make something easier to measure.

## Status

| Phase | State |
|---|---|
| Corpus read, classified | **done** — this document |
| §R collision resolved | **done** — the KB-60 items moved to §AD |
| Observer, flag, storage, inspection command | **done, deployed 2026-09-23 16:51 UTC** |
| Live evidence accumulating | **started** — M1 and M7 recorded at boot with nobody connected |

## What is wired, and what is not

**Wired now (12 rules, 12 QA items):** `A2 G1 G4 M1 M7 N7 O1 P1 P4 T2 T3 T4`.

| Where the fact comes from | Items |
|---|---|
| boot, no player needed | M1 (migrations settled), M7 (ownership survives a restart), O1 (championships started) |
| race completion (`ncm:race.completed`) | G1/D6 quantised time, A2 phantom win, G4 once-only accomplishments |
| venue card publish | P4 — the L107 invariant violated three times in one hour |
| guide publish + panel telemetry | P1 — published rows that never drew |
| discovery write | T2/T4 provenance and self-credit |
| entry decision | N7 — list and server must agree |

**T3 is deliberately not claimed** from the discovery path: that code does not load the previously stored
source, so the rule cannot judge it there. The anti-farm property is enforced structurally anyway (source is
written on INSERT only, never in the `ON DUPLICATE KEY UPDATE` clause). Claiming a PASS we cannot observe would
be exactly the fake-proxy trap.

**Not yet wired, and honest about why:** the remaining AUTO candidates (B3, B5, N1/N2, O2/O3/O4/O8, K4/K6,
A6, S5/S6, H1/H2/H3, D5) each need a fact announced from a system this pass did not touch. They are cheap to
add one at a time once the pattern has proven itself live; adding twelve more emits before any of them has
produced real evidence would be speculative.

## Runtime cost

Event-driven throughout. Every instrument sits on a transition that already happens — a race completing, a
card publishing, a discovery being written — so the marginal cost is one table lookup and, for a genuinely new
(item, verdict) pair, one INSERT. Repeats are a counter bump. **No new polling loop was added**; the two
sweeps that already exist (readiness 5 s, location 20 s) were not extended.

The storage is bounded by construction: at most `items x verdicts x servers` rows, a few hundred forever,
regardless of player count or uptime. Nothing here scales with population, so no instrument needs sampling,
deferral or a population-size caveat.
