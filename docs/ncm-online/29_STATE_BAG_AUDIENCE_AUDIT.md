# 29 — Player state-bag audience audit

> **STATUS: PROPOSAL** - a recommendation with **no authority until ruled on**. Covers: *replication audience of NCM player state-bag mirrors*
> Authority map: [INDEX.md](INDEX.md) - classified 2026-09-24 (L125)

**2026-09-24. Read-only audit. No implementation changed.** Every correction below needs a matching client-side
read change, so none is a one-line fix and none was applied. Scope: `Open77.state.player(id)` mirrors written by
`ncm_league` and `ncm_world`.

---

## 1. The audience, from the platform's own documentation

`docs/research/open77/evidence/2026-09-19/guide-state-bags-audience-caps.md`:

| Bag | Audience |
|---|---|
| `global` | every connected player, every routing bucket |
| **`player(id)`** | **every player in that player's routing bucket, including the subject** |
| `entity(kind, id)` | exactly the players streaming that entity |

> *"Routing buckets are isolated… a bag carries gameplay secrets, so shipping it to a client that is merely
> asked not to look is an information leak with no bandwidth saving."*

**A `player(id)` bag is not private to that player.** It is bucket-wide. The platform treats the bucket as the
confidentiality boundary and says so in the language of secrets.

## 2. NCM never sets a routing bucket

Measured: NCM **reads** buckets in three places (`collection.lua` anti-spoof checks, `help.lua` diagnostics,
`ncm_weather_probe`) and **writes one nowhere**. `weather.lua` records the intent plainly — *"Event bucket
policy is deliberately a later consumer."*

> **Therefore every NCM player shares bucket 0, and every personalised `player(id)` mirror is replicated to
> every connected player.**

This is a property of the deployment, not of any one payload. It will silently apply to every future mirror.

## 3. The finding that makes the fix small

**NCM already has a private, per-player channel and already uses it for its richest data.**
`TriggerClientEvent("ncm:<x>.payload", pid, …)` is targeted at one player: `guide.payload`,
`collection.payload`, `market.payload`, `help.payload`, `guide.results.payload`, `session`, `report.result`.

So the two channels coexist today, and the *large* surfaces (Market, Machine Index, Guide) are already on the
private one. The bags are the smaller HUD-ish mirrors — and a few of them carry fields that belong on the
private channel.

**No networking redesign is required or recommended.** The correction, where needed, is to move a field from a
channel NCM already has to another channel NCM already has.

## 4. Field-by-field classification

**Class key:** `PUBLIC` intentionally visible · `PRIVATE` subject-only · `ORG` organisation/future-sensitive ·
`CACHE` harmless projection.

| Mirror | Fields | Class | Audience correct? |
|---|---|---|---|
| **`ncmInbox`** (`organized.lua`) | `items` (message/seat-offer bodies), `unread` | **ORG / PRIVATE** | **NO — broadest gap.** A driver's messages and team-seat offers are replicated to everyone in the bucket. |
| **`ncmOdo`** (`odometer.lua`) | **`assetId`**, `m` (lifetime metres), `name`, **`ord`** (serial) | **PRIVATE** | **NO — and see §5.** Which serialised machine a player occupies, its identity and its lifetime distance, handed to every client continuously. |
| **`ncmGuide`** (`guide.lua`) | races list; **`carRefusal`**; **`iOwn`** (count of eligible machines owned); `mine` (subject's entry) | mixed: list `PUBLIC`, rest **PRIVATE** | **NO.** `iOwn` and `carRefusal` describe the subject's garage composition and eligibility. |
| **`ncmHistory`** (`guide.lua`) | **`mine`** (subject's results), **`myBestMs`**, `board`, `routeId` | `mine`/`myBestMs` **PRIVATE**; `board` `PUBLIC` | **PARTLY.** The leaderboard is public by design; the subject's own runs and personal best are not. |
| **`ncmVenue`** (`guide.lua`) | `eventId`, `series`, `route`, `venue`, `startsAt`, **`options`** | `options` **PRIVATE**, rest `PUBLIC` | **PARTLY.** `options` is the subject's available actions, which encodes entry/eligibility state. |
| **`ncmEntry`** (4 writers) | `eventId`, `state`, `routeName`, `startsAt`, `venue` | `PUBLIC`-ish | **Acceptable.** Who has entered a race is legitimately public in a sporting world; the venue is already shared. |
| **`ncmResult`** (`race.lua`) | position, times, gap, incidents | `PUBLIC` | **Acceptable.** Results are published. |
| **`ncmPractice`** (`guide.lua`) | `board`, `open`, `formsAt`, copy strings | `PUBLIC` / `CACHE` | **Acceptable.** |
| **`ncmOnboarding`** (`identity.lua`, `main.lua`) | `pending`, `version`, `complete` | `CACHE` | **Acceptable** — no answers, only completion state. |
| **`ncmHelp`** (`main.lua`) | `seq`, `at` | `CACHE` | **Acceptable.** |

## 5. The pattern the owner asked about — and it has already started

The question was whether Machine Knowledge, discovery, ownership, market access, engineering or trade could
inherit this. **One already has: `ncmOdo`.**

`28_MACHINE_KNOWLEDGE.md` (captured 2026-09-24) says knowledge must be *earned*: discovery establishes identity,
observation is empirical and asset-provenanced, and estimates narrow only with legitimate familiarity. But today
every connected client is continuously handed **the serialised identity and lifetime odometer of the machine
every other player is sitting in** — the exact facts that spec intends players to work for.

It is not currently exploited (NCM's own client reads only its own keys) and it is not a live incident. It is a
**substrate mismatch**: the data is on the wire, so any future surface following the `ncmOdo` precedent inherits
bucket-wide replication by default.

**The guard, stated once, is cheap and needs no new machinery:**

> A `player(id)` bag may carry only what is true for **everyone in the bucket**. Anything specific to the
> subject goes on the targeted event NCM already uses.

That single rule covers discovery, market access, engineering competency, trade offers, component inventory and
knowledge ladders before any of them are built.

## 6. Recommended corrections — smallest, in priority order

**None applied.** Each needs the matching client read changed from a bag subscription to an event handler, so
each is a small paired change rather than a one-liner, and that is the owner's call.

1. **`ncmInbox` → targeted event.** The clearest confidentiality gap: messages and seat offers. Smallest
   correction: publish via `TriggerClientEvent("ncm:inbox.payload", pid, …)`, matching the existing
   `*.payload` convention; drop the bag.
2. **`ncmOdo` → targeted event.** Same shape. Also the one with forward consequences (§5).
3. **`ncmGuide`: move `iOwn` and `carRefusal` only.** The races list can stay on the bag; the two
   subject-specific fields move to the existing `ncm:guide.payload`, which already goes to that player.
4. **`ncmHistory`: split.** `board` stays public; `mine` and `myBestMs` move to the private channel.
5. **`ncmVenue`: move `options` only.** Event/venue facts stay.

**Explicitly not recommended:** routing-bucket changes, entity-bag migration, encryption, ACLs, new endpoints,
or any change to how OPEN//77 replication works. Buckets exist for world isolation, and repurposing them for
per-player privacy would be a much larger change than moving five fields onto a channel that already exists.

## 7. What this audit does not claim

- **No evidence of exploitation.** The stock NCM client reads only its own keys.
- **Not a live incident.** Online currently has one player. The finding is about substrate, not damage.
- **Not a platform defect.** OPEN//77 documents this audience precisely and offers the targeted event as the
  private alternative. NCM simply used the broadcast channel for a few fields that wanted the private one.
- **Caps were not audited.** The 4 KiB per-value and 20k writes/sec limits are separate concerns; nothing here
  suggests NCM is near them.
