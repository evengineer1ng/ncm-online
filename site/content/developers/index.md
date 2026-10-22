---
title: Developers
description: Developer documentation for NCM Online: what the codebase is, how it is organised, and how to build on it.
status: dev
---

# Developers

NCM Online is the complete source of a real, running OPEN//77 server: Lua resources, native RED4ext plugins,
redscript, tooling, tests and the full design record. It is released under the
[MIT License](https://github.com/evengineer1ng/ncm-online/blob/main/LICENSE).

**Be realistic about what it is.** This is an actively developed server codebase, not a polished framework. It has
project-specific assumptions, experimental branches, dated design documents and one developer's conventions. It is
also full of working answers to hard questions: authoritative racing on a platform not built for it, an NPC league
that runs with nobody online, a conserved economy, serialized machines, native physics bridges and rig input.
Study it, fork it, take what is useful.

## Where to start

| If you want to... | Read |
|---|---|
| understand the shape of the system | [Architecture](architecture.md) |
| find your way around ~6,000 tracked files | [Repository Map](repo-map.md) |
| run a server locally | [Running NCM](running.md) |
| run the tests | [Testing](testing.md) |
| add a system, a resource or a native mod | [Extending NCM](extending.md) |
| keep these docs honest | [Maintaining These Docs](docs.md) |
| contribute | [CONTRIBUTING.md](https://github.com/evengineer1ng/ncm-online/blob/main/CONTRIBUTING.md) |

## Reading the design record

NCM keeps its decisions in public, and the volume is large:

- **[`docs/ncm-online/INDEX.md`](https://github.com/evengineer1ng/ncm-online/blob/main/docs/ncm-online/INDEX.md)** is
  the authority map. It says which document governs which topic and lists known conflicts. Every document carries a
  status banner (CURRENT / SPEC / PROPOSAL / SUPERSEDED / HISTORICAL / LEDGER). **A document's number or date confers
  no authority.**
- **`DECISION_RECORD.md`** holds every ruling (L1 to L371 and counting). When a design document and a later ruling
  disagree, the ruling wins. When a ruling and the code disagree, read the code.
- **`BACKLOG.md`** is the append-only idea ledger. **`KNOWN_BUGS.md`** is the defect ledger. **`NOW.md`** is where
  the project is today. **`wp/MASTER_TEST.md`** is the live test register: nothing counts as done until a live PASS
  sits beside it.

## Using AI assistants on this repository

The repository is large enough that reading it all is not an option, for a person or a model. Point the assistant at
[Architecture](architecture.md), [Repository Map](repo-map.md) and `docs/ncm-online/INDEX.md` first. The root
`AGENTS.md` holds the working rules the project's own sessions follow.
