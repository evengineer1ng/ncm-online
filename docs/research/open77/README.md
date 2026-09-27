# NCM / OPEN//77 research status

Research date: **2026-09-18**. Documentation-only assessment; no production behavior changes or multiplayer experiments. Workspace is not a Git checkout, so these findings were written to disk rather than committed. Major OPEN//77 implementation awaits reconnaissance review.

## Progress

- **Completed:** all nine requested reconnaissance phases at static-analysis/document-research depth; seven requested assessment documents, adjacent-project review and root AGENTS.md.
- **Evidence:** actual NCM execution traces; 64-file/54,097-line Lua inventory with SHA-256 hashes; published NCM permissions; current official docs/devkit; actual build-pinned hosted MCP queries; public Freeroam/Race source pinned to a commit.
- **Current finding:** NCM is a mutable single-player orchestrator plus a substantial league ecosystem, not a clean domain library. Roster, calendar, standings and box scores are especially promising seams. Physical AI and statistical simulations are already distinct mechanisms.
- **Platform finding:** documented AI tasks exist but require client simulation. Empty-server physical racing is unavailable; full NCM tuning parity is not supplied by performance ceilings. Server rule authority does not equal independent physics verification.
- **Recommendation:** provisionally share useful domain/simulation rules while building a server-native race host. Decide through bounded experiments; do not maximize code reuse for its own sake.
- **Unresolved:** runtime checkpoint integrity/timing, AI fleet/handover quality, telemetry trust, native mod layering, tuning scope, access/deployment, and source/asset redistribution boundaries. No experiment is passed.
- **Next action:** review findings and P0 documentation discrepancies; then E0 build/access verification and E1 one-course conversion in an isolated prototype. E2/E3/E7 gate human racing and durable progression; E4–E6/E9 gate optional AI/tuning scope.

## Reading order

1. [NCM_ARCHITECTURE.md](NCM_ARCHITECTURE.md) — boot, state ownership, race execution, persistence and subsystem map.
2. [NCM_DOCUMENTATION_AUDIT.md](NCM_DOCUMENTATION_AUDIT.md) — prioritized user/developer documentation work aligned to the existing onboarding plan.
3. [OPEN77_RECON.md](OPEN77_RECON.md) — current APIs, contradictions, MCP, deployment and pinned Race implementation.
4. [OPEN77_NCM_MATRIX.md](OPEN77_NCM_MATRIX.md) — subsystem decisions and ownership changes.
5. [OPEN77_ARCHITECTURE_OPTIONS.md](OPEN77_ARCHITECTURE_OPTIONS.md) — three architectures, costs, rejection criteria and migration.
6. [OPEN77_EXPERIMENT_PLAN.md](OPEN77_EXPERIMENT_PLAN.md) — thirteen ordered, measurable proofs before commitment.
7. [OPEN77_VISION.md](OPEN77_VISION.md) — credible ceiling separated from speculation.

Also: [adjacent projects](LANDSCAPE.md), [evidence provenance](evidence/README.md), [future-agent instructions](../../../AGENTS.md).

Current follow-up: [external tooling and API audit](EXTERNAL_TOOLING_API_AUDIT.md) — HTTP/network surfaces,
existing NCM exposure, internal-only data, telemetry, identity/auth/privacy/rate boundaries, and cheap substrate
decisions to preserve before any endpoint design.

Current convergence research: [NCM Single Player <-> Online convergence audit](NCM_SP_ONLINE_CONVERGENCE_AUDIT.md)
— code-level archaeology of both implementations; shared definitions versus sovereign state; AI racing,
machine proxies, mod/content availability, results/trust, Machine Knowledge, framework seams, a concept matrix,
and the cheap identity/provenance decisions that preserve a future "one NCM, multiple execution contexts" model.

Current identity recovery: [Driver Identity / Nameplate recovery audit](DRIVER_IDENTITY_NAMEPLATE_RECOVERY_AUDIT.md)
— recovered three-layer Driver Card, provisional Fingerprint axes, banners/badges/profile history, present
telemetry feasibility, OPEN//77 nameplate/WebUI/state-bag readiness, missing assets and the smallest honest Phase 2.

Current content-rights register: [NCM server-mod licensing catalog](NCM_SERVER_MOD_LICENSING_CATALOG.md) - the
package-by-package distinction between server-hosted delivery, written-permission candidates and content that
is off the table today; Cohort 1 and its hard dependencies are the first audited batch.

Evidence labels: **code verified** means static execution-path inspection, not a gameplay test; **documented** means an official external source; **proposal** means engineering judgment; **unknown** is not proof of absence. External capabilities must be rechecked against a pinned preview before implementation.

## Discrepancies worth knowing immediately

- Quick Race's documented consequence-free description appears broader than its finalizer guards: money, heat and records need a targeted SP playtest.
- One bundled full circuit and one managed-driver slot were found; do not infer a large finished circuit catalogue/team-management system from the brief.
- Phone commands are active, but native quest-led onboarding remains incomplete; the disabled legacy quest probe is a different path.
- Endpoint roots and telemetry polylines are not complete authored road courses.
- Official Race currently supplies a focused Freeroam activity, with course persistence but no league/career/physical AI path found in the inspected source. Its license differs from the devkit and NCM permissions.

Verification: research Markdown links checked locally; captured Lua hashes unchanged at end of work. No gameplay tests, source refactor, public-page edits, plugin installation or server deployment were performed. The read-only MCP query helper and captured API text are research tooling/evidence, not production integration code.

## 2026-09-19 update — NCM Online orientation

Platform build still 2.31.13+op77.78 and Freeroam still d3f2a7f; docs index grew at the same build. Reconciliation of this research against today's platform, the coupling measurements of the NCM payload, and the living decision record live in [docs/ncm-online/](../../ncm-online/archive/00_ORIENTATION_BRIEF.md). New evidence captures are in [evidence/2026-09-19/](evidence/2026-09-19/README.md). Headline corrections: vehicle adoption exists since .67 (the vehicles guide paragraph saying otherwise is stale); AI is hard-capped at 55 m/s; unverified required mods are inert-only (no CET/redscript/DLL); vanilla traffic is per-client; remote cameras are documented for an unreleased build.
