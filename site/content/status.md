---
title: Status Labels
description: What LIVE, EXPERIMENTAL, IN DEVELOPMENT, PLANNED, HISTORICAL and DEVELOPER mean on this site.
---

# Status Labels

NCM moves quickly, and its documents come from many stages of the project. Every system on this site carries one of
these labels. The label describes the **public NCM Online server**, not the repository.

| Label | Meaning |
|---|---|
| {{status:live}} | Available on the public NCM Online server. You can use it now. |
| {{status:experimental}} | Implemented and testable, but unstable or incomplete. It may change, break or be withdrawn. |
| {{status:in-development}} | Being built. Not necessarily available to players. |
| {{status:planned}} | Designed or intended, but not implemented. Not a promise. |
| {{status:historical}} | An earlier design or implementation, kept for the project's history. |
| {{status:dev}} | Developer infrastructure: tools, tests and build systems, not a player feature. |

**How a label is decided.** The order of evidence is: current code, current tests, current configuration, recent
authoritative decisions in the
[decision record](https://github.com/evengineer1ng/ncm-online/blob/main/docs/ncm-online/DECISION_RECORD.md), git
history, and only then older design documents. A design document alone never makes something LIVE.

Inside the repository, `docs/ncm-online/` documents carry their own banners (CURRENT / SPEC / PROPOSAL / SUPERSEDED
/ HISTORICAL / LEDGER) for *document authority*. Those describe documents, not features. See
[`docs/ncm-online/INDEX.md`](https://github.com/evengineer1ng/ncm-online/blob/main/docs/ncm-online/INDEX.md).
