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

Current presentation research: [presentation capability audit](PRESENTATION_CAPABILITY_AUDIT.md) — the visual,
spatial, motion and audio vocabulary actually available to NCM Online: shipped OPEN//77 presentation services, the
eight-CEF-surface ceiling, native/WebUI hybrid projection, world-space mechanisms (markers, props, world televisions,
camera surfaces), the base-asset catalogues with their support levels, a screen-space and z-index map with two latent
collisions, five visual directions, and a token/component proposal. Companion to a separate player-visibility audit,
which owns *what* to communicate; this one owns *with what*. Prototypes in [prototypes/](prototypes/).
Addendums A-C (2026-09-27) answer three owner design questions against the same evidence: **market presentation
identity** as a scoped token override block rather than a per-market interface; **Player Banners**, which already
exist in embryo in `driver.presentation` and lack only an earning path; and the **communication register** the
repository already writes in, specified as rules rather than a mood.

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

> **Build skew warning, added 2026-09-27 (`KB-162`).** The hosted devkit MCP that `query_open77.ps1` targets is
> pinned well behind staging - it answered `2.31.13+op77.78` while staging ran `.102` - and it says so in every
> reply. **An absent card means the index does not know, never that the platform cannot.** A BLOCKED verdict on
> platform capability needs a positive source: a card that says no, or a guide that states the limit. When the
> index lags, check the release channel and devblog first. **Grepping the installed `Open77.dll` is worth doing but is NOT an oracle**: binding names are not
> stored as literals, so a grep MISS proves nothing (`joinTraffic`, `attachDriver`, `driveTo` and `npcs.speak`
> appear in no server binary yet all are documented and shipping). Prefer listing the resources actually running
> on the deployed server, and when nothing settles it, **run the call**. This warning exists because a
> reconnaissance pass declared shared AI traffic BLOCKED three days after OPEN//77 shipped it.

## 2026-09-27 (late) - ambient population is server-side, and the correction is narrower than it looks

> **`KB-164`, decided in `L177`.** Two lines on this page - the 2026-09-19 headline *"vanilla traffic is
> per-client"* and the 2026-09-27 note that *"corroborates"* it and adds that `traffic` is a binary switch with
> no density control - are **true about the entities and silent about the control**. Read together with the
> capability matrix's `BLOCKED` row they were taken to mean traffic is not server-side. It is.
>
> The oracle is the shipped server itself: `Open77.Server.Scripting.dll` embeds the documented Lua prelude as
> strings, so the installed build answers questions the hosted devkit index (pinned behind staging, `KB-162`)
> cannot. At `2.31.13+op77.102` it says, in its own comments:
>
> * `Open77.world.setPopulation(bucket, { crowd, traffic, police })` is **"Server-owned and replicated to every
>   client in that bucket; the client half is read-only"**, gated on `world.population`. `crowd` is a genuine
>   multiplier on vanilla pedestrian density; `traffic` and `police` are binary on 2.31 and `getPopulation`
>   reports `trafficGranularity = "binary"` rather than pretending otherwise.
> * `Open77.world.clearArea(position, radius, options)` removes what the **calling resource owns** and counts
>   everything else as `refused`. Its `population = true` option **requires a bucket** and says so by name
>   (`bucket_required_for_population`), because the suppression that follows is bucket-wide: *"there is no
>   radius-scoped vanilla-population control on 2.31 and inventing one here would only move the surprise."*
>
> **What stays true:** vanilla population entities are spawned per client, carry no canonical id, and cannot be
> named, moved or removed from the server. Radius-scoped clearing is possible only for entities a resource
> created itself. That is why NCM builds its own ambient layer rather than trying to curate the vanilla one -
> see `L177` and `docs/ncm-online/wp/MASTER_TEST.md` §BL.
>
> **The method lesson is `KB-162`'s, repeated.** A grep, an index and a prose summary are all sources that can
> be *incomplete* rather than *negative*, and a capability nobody wrote down is indistinguishable from one that
> was ruled out. When nothing settles it, read the shipped build or run the call.

## 2026-09-27 follow-up - character / message archaeology and the lightweight PvE substrate

[CHARACTER_ARCHAEOLOGY_AND_PVE_SUBSTRATE.md](CHARACTER_ARCHAEOLOGY_AND_PVE_SUBSTRATE.md) - the NCM **single-player**
character/message system recovered from its shipped implementation (seven contacts, the WolvenKit journal and
localization resources, the quest-fact bridge, the state-projected choice sets, the authored prose and the voice
validator), plus the **Dynamic Contact Event System** that was not in the brief and is the closest thing NCM has to
an authored PvE substrate; then portability, spontaneous racing, Book Queen Billie, Messages, a world graph, and a
creative expansion. Read-only; **no production behaviour changed and nothing measured in-engine.** Three owner
decisions are `L170`. Note it **corroborates this README's 2026-09-19 finding that vanilla traffic is per-client**,
from the platform's own vehicles guide, and adds that `traffic` is a binary switch with no density control in 2.31.
