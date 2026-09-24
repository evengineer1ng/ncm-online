# A credible OPEN//77 edition of Night City Motorsports

Assessment date: 2026-09-18. The ceiling is a reusable motorsport and league framework for server owners, while single-player NCM remains a first-class product. Human entrants do not need to replace fictional competitors. The strongest opportunity is combining observed races with a persistent racing world whose identity survives between events.

This is a product hypothesis grounded in [NCM code](NCM_ARCHITECTURE.md) and [current platform evidence](OPEN77_RECON.md), not a promise that all features can ship on this preview.

## Meaning of confidence labels

- **CURRENTLY POSSIBLE:** relevant primitives or reference implementation are documented/source-verified now. This does not mean an NCM online feature has been built or tested.
- **LIKELY POSSIBLE WITH ENGINEERING:** a credible construction from verified primitives and NCM domain behavior; implementation, performance and usability remain work.
- **REQUIRES OPEN//77 CHANGES:** a necessary capability is absent or explicitly restricted in the inspected surface; request and verify it rather than invent an API.
- **SPECULATIVE:** depends on unproved behavior, major scale, infrastructure or product adoption beyond the evidence.

## Capability ceiling

| Opportunity | Confidence | Grounded scope / condition |
|---|---|---|
| Human-only sprint/circuit events | CURRENTLY POSSIBLE | Reference Race demonstrates queue, grid, cars, checkpoints, timing and results. Harden observations and lifecycle for NCM competition |
| Better course presentation | CURRENTLY POSSIBLE | Native next-gate anchors, WebUI, map cues and props exist; visibility, matching geometry and cleanup need course-specific QA |
| Reusable NCM race executor/format framework | LIKELY POSSIBLE WITH ENGINEERING | Explicit heat instances, validated format contracts and results API; avoid exposing mutable internals as the extension API |
| Casual standalone events | LIKELY POSSIBLE WITH ENGINEERING | Short-lived heats with clearly declared record/reward policy; no need for every server to enable career systems |
| Community seasons/leagues | LIKELY POSSIBLE WITH ENGINEERING | SQL persistence plus NCM schedule/standings concepts; requires eligibility, disconnect, correction and season rollover policy |
| Persistent personal career | LIKELY POSSIBLE WITH ENGINEERING | Account-scoped progress/unlocks/messages, separated from shared season state and from the user's SP save |
| Server-generated calendar | LIKELY POSSIBLE WITH ENGINEERING | NCM scheduling and bounded simulation adapted to server time, live promotion and once-only event claims |
| Off-screen fictional races | LIKELY POSSIBLE WITH ENGINEERING | Statistical simulation needs no physical cars or connected viewers; results remain explicitly simulated |
| Persistent fictional and human competitors | LIKELY POSSIBLE WITH ENGINEERING | Stable competitor IDs with human/account or fictional/seed provenance; rules must specify which events/counts affect each ledger |
| AI-only physically observed events | LIKELY POSSIBLE WITH ENGINEERING, experiment-dependent | Platform AI exists with a ready nearby client; course quality, pace and fleet stability remain E4/E5 questions |
| Mixed human + physical AI grids | LIKELY POSSIBLE WITH ENGINEERING, experiment-dependent | Shared race acceptance is plausible; task handover, contact physics and fair speed/classes are unproved |
| Physical AI races on an empty dedicated server | REQUIRES OPEN//77 CHANGES | Current physics is client-simulated. Statistical continuation is a different feature and can ship without this |
| Team/faction seasons and management | LIKELY POSSIBLE WITH ENGINEERING | Shared memberships/standings and account-owned contracts; current SP management has one slot, not a finished online team manager |
| Economy/betting | LIKELY POSSIBLE WITH ENGINEERING | Optional server policy after idempotent settlement, trusted results and abuse tests. Not an initial dependency for a useful league |
| Parts/build progression | LIKELY POSSIBLE WITH ENGINEERING | Inventory/eligibility/cosmetics and simulated build effects are plausible. Advertised physical effects must match verified controls |
| Full SP per-vehicle tuning parity | REQUIRES OPEN//77 CHANGES or a separately proven lower-level extension | Documented caps cannot express arbitrary NCM handling/power modifications; uniform mod packs do not establish per-instance parity |
| Route packs and author tools | LIKELY POSSIBLE WITH ENGINEERING | Transform explicit data, preserve IDs/revisions and validate road geometry; endpoint roots need additional authoring |
| Rich box scores, news and rival stories | LIKELY POSSIBLE WITH ENGINEERING | Strong NCM seam; build paged public read models from settled events, keep private contact state separate |
| Spectator standings/results | LIKELY POSSIBLE WITH ENGINEERING | Public read models and views; physical camera-follow/streaming behavior needs a separate test before promising broadcast tools |
| Public statistics website | LIKELY POSSIBLE WITH ENGINEERING | Export sanitized settled results through an explicit service; account/privacy/access controls and hosting are additional systems, not an assumed OPEN//77 leaderboard API |
| Trusted high-resolution driving analytics | SPECULATIVE in full form | Basic motion/time analytics are plausible; detailed authoritative pedals/tires/fault attribution are not established by current server snapshots |
| Large always-active racing city | SPECULATIVE | Simulated activity can scale differently from physical cars; no evidence here establishes hundreds of synchronized racers/AI |
| Cross-server global career/market | SPECULATIVE | Requires identity federation, governance, integrity policy and external infrastructure; outside the current server-owned scope |
| Near-human high-speed racing AI everywhere | SPECULATIVE | Destination AI is not an authored racing controller. Better paths/overtaking/high-speed APIs may require platform changes, but deficiencies must first be measured |

## A coherent first online product

A strong initial edition could offer a small set of validated courses, human races, persistent season standings, fictional rivals, scheduled off-screen events and attractive box scores. Players would see a league that continues between their sessions without claiming that every event physically occurred. Add physical AI only on the routes/classes where experiments show it works.

For example, a server calendar could publish a fictional support event, settle it statistically, update rival form and show its box score. A later human championship round uses the physical executor and the same public result schema with different provenance. A contact can discuss both events, while only the eligible physical round contributes to a competitive route record. This joins the systems without falsifying what happened.

The first online tuning system could be spec cars or conservative class caps. Progression might initially unlock series, liveries, access or management choices rather than claim unsupported physical upgrades. If better tuning primitives arrive, the inventory/build contract can gain verified effects without rewriting seasons.

## Server-owner experience

Offer selectable policies rather than one mandatory career: casual meet/race server, structured league, or persistent fictional racing world. Proposed extension surfaces are course packs, race-format rules, season scoring, competitor providers, build eligibility, economy adapters and presentation themes. Version them and document ownership/error/reload behavior. A format proposes rules; the host still owns identity, acceptance and settlement.

Operators need reproducible deployment, schema migrations/backups, course validation, private/public data rules, moderation/corrections, interrupted-event recovery and useful diagnostics. A downloadable resource with many features but uncertain recovery behavior is not yet a serious framework.

## What would justify expanding ambition

E2/E3/E7 establish reliable human racing and durable results. E11 demonstrates a league that feels active without physical simulation. E4–E6 establish mixed grids at a measured fleet size. E9 determines honest build/tuning scope. E10 demonstrates that newcomers can use the depth. E12 identifies the maintainable implementation boundary.

NCM's mature concepts earn their place through useful behavior and evidence. OPEN//77 earns responsibility for entity/network/world primitives where its contracts are better suited. Neither age nor novelty decides which implementation survives.

Status: grounded product ceiling recorded. The immediate decision is which experiments to run after review; the long-term vision does not authorize an unreviewed major port.
