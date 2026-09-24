# 26 — Document authority and lifecycle

> **STATUS: PROPOSAL** - a recommendation with **no authority until ruled on**. Covers: *this scheme - directionally accepted, executed as L125*
> Authority map: [INDEX.md](INDEX.md) - classified 2026-09-24 (L125)

**Status: PROPOSAL. Nothing moved, nothing rewritten, nothing implemented.** Answers the owner's documentation
pass, 2026-09-24: *"We have too much documentation that is equally discoverable but not equally authoritative…
Preserve the history. Curate the authority."*

---

## 1. Two proofs that the problem is real

Not hypothetical. Both found while writing this:

1. **`05_DATA_MODEL.md` says "migrations 001–007".** The schema is at **023**. A coder reading it would build
   against a world sixteen migrations out of date, and nothing in the document warns them.
2. **There are two `16_` documents and two `17_` documents** (`16_ENVIRONMENTS` / `16_MACHINE_INDEX`,
   `17_MACHINE_PROFILE` / `17_MARKET_NETWORK`). So "highest number wins" is not merely unreliable here — it is
   undefined.

And the case the owner named: `04_TESTER_WINDOW_1.md` carries the TW2 granted-equipment assumptions, sitting at
equal discoverability beside `14_TEAM_ORGANIZATIONS.md`, which L123 has just reaffirmed as current.

## 2. The insight the corpus actually suggests

**Almost every document already has a status line — and almost every one states the wrong thing.**

The existing lines describe **build state**: *"built locally, not deployed"*, *"foundation implemented locally"*,
*"migrations 001–007"*. Build state is precisely the thing that rots, because it changes every time code ships
and nobody goes back to edit prose.

What a coder needs is **authority**: *is this the current statement of intent for its topic?* That changes only
when a decision changes — which is rare, and is already recorded in `DECISION_RECORD.md`.

> **The rule that prevents the `05_DATA_MODEL` failure from recurring: document headers carry authority only.
> Build state lives in the ledgers (`BACKLOG`, `KNOWN_BUGS`, `wp/MASTER_TEST`), which are maintained anyway.**

A document saying "this is how NCM handles team ownership" stays true whether or not it is built. A document
saying "migrations 001–007 exist" is wrong within a week, forever.

## 3. Six statuses

The owner suggested four and invited something cleaner. The corpus contains six genuinely different kinds of
document, distinguished by *what a coder should do about them*:

| Status | What it means | What a coder does |
|---|---|---|
| **CURRENT** | The present statement of intent for its topic | **Build from it.** If code disagrees, the code is wrong or the doc needs a conflict raised |
| **SPEC** | Owner-authored intent, captured but not authorised | **Do not implement. Do not contradict.** Binding as direction, not as a work order |
| **PROPOSAL** | A recommendation awaiting a ruling | **Do not rely on it.** It may be rejected wholesale |
| **SUPERSEDED** | Was current; something replaced it | **Do not build from it.** Read only for history; the header names the successor |
| **HISTORICAL** | A record of a moment — an experiment, a run sheet, a point-in-time audit | **Evidence, never architecture** |
| **LEDGER** | Living append-only record, current by construction | **Read for state.** Never rewrite prior entries |

`SPEC` and `PROPOSAL` are kept apart deliberately: `18`–`20` are the owner's direction and must not be
contradicted, while `21`, `22` and `25` are mine and carry no authority until ruled on. Collapsing them would
either give my proposals weight they have not earned, or strip the owner's specs of the weight they have.

## 4. The header

One line, immediately under the H1, machine-checkable:

```markdown
> **STATUS: CURRENT** · authority for: *environments, promotion discipline* · affirmed 2026-09-24 (L121)
```
```markdown
> **STATUS: SUPERSEDED** by [14_TEAM_ORGANIZATIONS.md](14_TEAM_ORGANIZATIONS.md) · 2026-09-24 (L123) · kept for history
```

**`affirmed` is not `modified`.** Fixing a typo does not re-affirm a document; a decision does, and it cites the
`L` that did it. This is what makes "do not assume the newest date wins" enforceable rather than aspirational —
the date in the header is the date someone last *stood behind* the content.

## 5. Five rules

1. **Authority is per topic, not per document.** The question is never "which doc is newest" but "what is the
   authority on *team ownership*". Two CURRENT documents covering different topics is normal; two claiming the
   same topic is a conflict.
2. **Headers carry authority; ledgers carry build state.** (§2)
3. **Number and date confer nothing.** `16_MACHINE_INDEX` is not superseded by `17_MARKET_NETWORK`.
4. **Code is the authority for code-shaped facts.** Schema authority is
   `ncm/online/resources/ncm_league/server/schema/` — not any document. A doc may *explain* the schema; it may
   not *define* it. This is the specific fix for `05_DATA_MODEL`.
5. **Surface conflicts; never silently choose.** If two CURRENT documents disagree on one topic, add it to the
   index's conflict list and ask. A wrong silent resolution is worse than an open question.

## 6. The entry point

**`INDEX.md`** — the map a new coder reads first, and the only file that has to be kept accurate.

```markdown
## Authority by topic
| Topic | Authority | Status | Affirmed |
|---|---|---|---|
| Team ownership, organisations, governance | 14_TEAM_ORGANIZATIONS.md | CURRENT | 2026-09-24 (L123) |
| Environments, promotion | 16_ENVIRONMENTS.md | CURRENT | 2026-09-24 (L121) |
| Database schema | ncm/…/server/schema/ (CODE) | CURRENT | — |
| Foundational sequencing | 24_FOUNDATION_RECONCILIATION.md | CURRENT | 2026-09-24 (L123) |

## Known conflicts (unresolved — do not silently pick)
- 01_ARCHITECTURE.md describes five resources / nine core packages; the disk has three resources
  and a different core layout (IDEA-029). Authority for the live layout is the code.

## Everything else, by status
…
```

`AGENTS.md` currently points a newcomer at `00_ORIENTATION_BRIEF.md`; it would point at `INDEX.md` instead.
One line changed.

## 7. Archiving

Move `SUPERSEDED` and `HISTORICAL` documents to **`docs/ncm-online/archive/`**, preserving them intact with their
new headers. They stay in git, stay readable, stay linked from the index — they simply stop appearing beside
current material when someone lists the directory or greps the folder.

**No stub files left behind.** A stub would recreate exactly the equal-discoverability problem it was meant to
solve. The index records where everything went.

**Cost measured, not guessed:** 62 cross-links exist across the whole folder, 2–5 inbound per archive candidate.
Link fixes are mechanical and a gate check can verify none dangle.

## 8. Enforcement, so it does not decay

Four assertions added to `tools/ncm-test.ps1`, which already gates every session:

1. every `.md` under `docs/ncm-online/` (excluding `archive/`) has a parseable STATUS line;
2. every `SUPERSEDED` header names a successor file that exists;
3. every topic in `INDEX.md` resolves to exactly one `CURRENT` document;
4. no two `CURRENT` documents claim the same topic.

Without this the scheme survives about three sessions. With it, the next coder cannot quietly reintroduce the
problem — which is the actual goal.

## 9. Proposed classification — the one-time pass

**Proposed, not applied.** `→ archive` marks a physical move.

### CURRENT (13)
| Doc | Authority for |
|---|---|
| `01_ARCHITECTURE.md` | overall system shape — **but see conflict C-1** |
| `02_ROADMAP.md` | milestone vocabulary (M0–M12) only; **not** current sequencing — that is `24` |
| `07_NODE_NETWORK.md` | nodes, routes, chains |
| `08_ECONOMY.md` | economy intent |
| `11_WEATHER.md` | weather |
| `13_VEHICLE_COLLECTION.md` | discovery and collection |
| `14_TEAM_ORGANIZATIONS.md` | **organisations, team ownership, governance** — reaffirmed by L123 |
| `15_GENERATION_1_VEHICLE_ARTWORK_MANIFEST.md` | vehicle artwork |
| `16_ENVIRONMENTS.md` | environments, promotion |
| `16_MACHINE_INDEX.md` | player-scoped machine knowledge |
| `17_MARKET_NETWORK.md` | markets, discovery |
| `24_FOUNDATION_RECONCILIATION.md` | foundational primitives and sequencing |
| `OPS_STAGING.md` | day-to-day operations |

### SPEC — owner intent, not authorised (7)
`06_CHROME_ROSTER.md` · `09_APPAREL.md` · `10_SPECIAL_EVENT_FISHING.md` · `12_CANONICAL_VEHICLE_ROSTER.md` ·
`17_MACHINE_PROFILE.md` · `18_PARTS_ECOSYSTEM.md` · `19_ENGINEERING.md` · `20_WEAR_LIFECYCLE.md`

### PROPOSAL — mine, awaiting or partly ruled (3)
`21_ENGINEERING_PROPOSAL.md` and `22_WEAR_PROPOSAL.md` — *accepted 2026-09-23; the decisions themselves live in
L120, these remain the reasoning* · `25_MACHINE_ARCHITECTURE_PROFILE.md` — awaiting Q18/Q19 · `26` (this doc)

### SUPERSEDED → archive (4)
| Doc | Superseded by | Why |
|---|---|---|
| `00_ORIENTATION_BRIEF.md` | `INDEX.md` + `NOW.md` | AGENTS.md already says NOW + BACKLOG *is* the catch-up brief |
| `03_PACKAGING_AND_COLLECTION.md` | `12` + `13` | provisional (P16), never ruled on, overtaken |
| `04_TESTER_WINDOW_1.md` | `14_TEAM_ORGANIZATIONS.md` + L123 | **the granted-equipment model the owner named** |
| `05_DATA_MODEL.md` | the schema directory (code) | **claims migrations 001–007; actual is 023** |

### HISTORICAL → archive (3 + directories)
`23_OPEN_QUESTIONS.md` (answered 2026-09-24 → L123) · `TW1_RUN_SHEET.md` · `experiments/` (4 files, historical by
nature) · completed work packages in `wp/` — **except `wp/MASTER_TEST.md` and `wp/OFFLINE_TEST_QUEUE.md`, which
are LEDGER and stay**

### LEDGER (5)
`BACKLOG.md` · `DECISION_RECORD.md` · `KNOWN_BUGS.md` · `NOW.md` · `wp/MASTER_TEST.md`

### Needs a look before classifying (1)
`bricks/` (5 files) — the component-gate pipeline. I have not read these closely enough to classify honestly and
would rather say so than guess.

## 10. Conflicts found during this pass

- **C-1 — `01_ARCHITECTURE.md` vs the code.** Describes five resources and nine core packages; the disk has three
  resources and a different core layout (`IDEA-029`, raised 2026-09-21, still open). It is otherwise the best
  statement of system shape, so I propose keeping it CURRENT *and* listing this conflict, rather than demoting a
  document that is 90% right.
- **C-2 — duplicate document numbers.** Two `16_`, two `17_`. Renaming breaks links and git history for no
  functional gain once the index exists. ▸ *Leave them; let the index carry authority.*
- **C-3 — `02_ROADMAP.md` sequencing vs `24` §9.** Resolved by per-topic authority: `02` owns milestone
  vocabulary, `24` owns what happens next.

## 11. Cost

Roughly: 33 headers written, 4 + ~8 files moved, ~15 links repaired, one `INDEX.md` authored, four gate
assertions added, one line changed in `AGENTS.md`. The archaeology this reconciliation already paid for is what
makes it cheap — the classification above is the output of that work, not a new investigation.
