# NCM / OPEN//77 external tooling and API audit

> **STATUS: CURRENT** — factual architecture audit as of 2026-09-24. No endpoint design or runtime change is authorised by this document.

Date: **2026-09-24**. Scope: the checked-in NCM Online resource set, schema through migration 027, the build-pinned OPEN//77 evidence already captured in this repository, and the earlier seven-part OPEN//77 assessment. This is static analysis plus prior recorded live evidence; no HTTP listener, external service, account, deployment, or multiplayer experiment was created.

## Executive finding

OPEN//77 can already host small custom inbound HTTP handlers. `Open77.http.listen(prefix, handler)` serves a resource below `/<resource>/<prefix>` on the server's **opt-in HTTP listener**; `routes()` and `unlisten()` manage that resource's routes. The server also has allow-listed outbound HTTP through `Open77.http.request` / `PerformHttpRequest` (256 KiB body maximum in the captured .78 card). The staging package is .87, but the build-pinned MCP query captured on 2026-09-23 fell back to .78, so these contracts must be re-queried against the actual deployment build before use.

NCM registers **no HTTP routes** and declares no HTTP permission today. Its external surfaces are in-game net events, bucket-replicated state bags, WebUI messages, console commands, OPEN//77 resource exports used as a consumer, server-local events between resources, SQL, and logs. None is a supported public API. The existing host could serve a narrow operator/health or read-only integration route without a companion process. A public website, cross-world identity, third-party credentials, long-lived subscriptions, strong rate limiting, privacy enforcement, TLS/edge controls, or aggregation across worlds should use a companion service or gateway. The choice is operational, not a blocker to the domain model.

The expensive future retrofits are not URL shapes. They are lost provenance, ambiguous identity, mutable rows with no change cursor, accidental publication of player-scoped data, and failure to distinguish live observations from settled history. NCM has already paid down part of this risk: durable machine assets and serial provenance, result provenance, world-scoped `server_id`, machine attribution/configuration seams, idempotent economy keys, and evidence-bearing Machine Knowledge foundations exist. The cheap work now is to preserve those distinctions and classify exposure; endpoint design should wait for a real consumer.

## 1. OPEN//77 network and HTTP surfaces

### Verified platform surfaces

| Surface | What exists | Architectural consequence |
|---|---|---|
| Inbound HTTP | Resource-scoped `Open77.http.listen`, `routes`, `unlisten`; paths live under `/<resource>/...`; listener is server opt-in | NCM does **not** require a companion merely to answer HTTP. Handler lifecycle belongs to a resource and must be removed/re-established on restart. |
| Outbound HTTP | `Open77.http.request` / `PerformHttpRequest`; absolute HTTP(S), host allow-list, bounded body and headers | A resource can call a trusted companion, but egress is deliberately constrained. Do not treat it as an unrestricted SDK. |
| Network events | Registered client/server events with platform-authenticated session `source` | Appropriate for in-game intents and targeted projections, not an internet API and not durable publication. Every client value remains untrusted. |
| State bags | Global, player, and entity replicated key/value state with audience and size/rate caps | Useful live projections, not private storage or historical query. `player(id)` means **the whole routing bucket**, not “only that player.” |
| Resource exports | Generation-bound calls between resources; 48 KiB captured export envelope | Useful internal service seam, but currently NCM mostly consumes platform exports and publishes no declared NCM export contract. |
| Platform events | Player/session, world/environment, vehicle/damage and AI lifecycle events | Useful observations. Events are not necessarily replayed and are not a durable external feed. |
| SQL | Host database access from authorised server resources | The durable source for NCM world facts. Direct external DB access would couple consumers to internal schema and bypass privacy/read-model policy. |

The opt-in listener's bind address, TLS termination, proxy trust, request limits, authentication helpers, streaming behavior, and connection concurrency are **not established by the captured API card**. Those are prerequisites for any internet-facing decision, not details to guess.

### Existing server versus companion service

Use the OPEN//77 listener when the consumer is close to the server and the route is small, bounded, and operationally disposable: health/readiness, a private webhook receiver, a bounded read-only snapshot, or a trusted companion callback. Keep database transactions and NCM authority inside the resource.

Use a companion/gateway when any of these become real requirements:

- public internet exposure, TLS/certificates, WAF, IP policy, quotas, or abuse analytics;
- OAuth, API keys for third parties, key rotation/revocation, service accounts, or scoped consent;
- cross-world/global identity, aggregation, search, long retention, or a public statistics site;
- WebSocket/SSE-style subscriptions, fan-out, caching, CDN delivery, or expensive report generation;
- privacy workflows such as export/deletion requests and operator audit across multiple worlds.

The stable boundary should be a sanitized NCM read/command service, whether its first adapter is an OPEN//77 route or a companion. Do not make SQL tables the API and do not let a companion decide race results, title, money, knowledge, or settlement.

## 2. What NCM exposes today

### Intentional player and operator surfaces

- In-game commands and WebUI actions cover calendar/Guide, interest/withdraw/entry, race gates/forfeit, market view/inspect/purchase, collection, vehicle call, onboarding, help/reporting, inbox, and operator race control.
- Targeted server-to-client payloads project sessions, Guide/results, Market, collection, vehicle outcomes, and help/report outcomes.
- Console-only commands expose migrations, reports, scenario/race control, telemetry summaries, provenance/odometer diagnostics, grants/mints and operational inspection. These are operator interfaces, not authenticated remote APIs.
- Public driver identity is deliberately projected through the `ncm` player-bag value: durable driver UUID, display, number, reputation, and SR.
- Global calendar/world identity and selected live session projections are deliberately replicated for gameplay.
- Player problem reports are bounded, idempotent by client-generated UUID, enriched with server-known context, and stored in SQL. They are explicitly not a ticketing API.

### Internal seams that are not contracts

- Lua globals such as `NcmCalendar`, `NcmRace`, `NcmMarket`, `NcmTelemetry`, `NcmOwnership`, and `NcmProvenance` expose many functions inside their own VM. Separate resources cannot see them.
- Server-local events (`ncm:gridCars`, `ncm:odometer.track`, `ncm:machine.seated`, `ncm:race.completed`, QA events, venue/pickup lifecycle) are cross-resource implementation plumbing. Their payloads are neither versioned nor authenticated as third-party extension contracts.
- Shared `ncm-core` modules are a promising engine-free domain boundary, but their Lua interfaces are internal and copied into resource build output. They are not a wire protocol.
- SQL migrations and tables are authoritative storage, not a supported query surface. Several rows use JSON precisely as forensic evidence, not as indexed public fields.
- Logs contain useful operational facts, including player IDs, driver IDs, asset IDs, positions, reports and incident candidates. Log scraping would create an accidental, unstable and privacy-poor API.

### Accidental or over-broad exposure risks

The platform's `player(id)` state bag is visible to **every player in that player's routing bucket**. NCM correctly treats `ncm` as public, but also mirrors personalized `ncmGuide`, `ncmEntry`, `ncmHistory`, `ncmPractice`, `ncmVenue`, and onboarding state into player bags. Some are harmless public sporting context; others include personal participation or history. Their current use must not be read as a privacy decision. Classify every bag key as public-to-bucket, subject-only (use a targeted event/read response), entity-viewer, operator-only, or durable-private.

Net-event names are discoverable by clients and several read actions have no general request throttle. Authority checks are generally server-side and mutations revalidate identity/ownership/state, which is the important security boundary, but availability protection is uneven: vehicle call has a cooldown and reports have a courtesy throttle; telemetry bounds batch shape; many read payloads rely only on natural UI cadence. This is acceptable for the current private developmental world, not a reusable external API policy.

## 3. Data location and present reachability

| Domain | Durable/internal truth today | Existing projection/event | Missing external/read-model seam |
|---|---|---|---|
| Machine assets | `vehicle_asset`, transfer history, factory appearance, lifecycle, odometer, three ordinal sequences, owner principal | Collection/Market/odometer panels; vehicle registration and seated-machine local events | Sanitized asset biography; title/custody distinction; revision/change cursor; configurable public/private fields |
| Race results | `session`, `session_result`, incidents, telemetry chunks, ledger/progression; machine attribution now has `asset_id`, basis/rule, reserved `configuration_ref` | Live `ncm:session`; on-demand personal past results; local `ncm:race.completed` | Stable settled-result envelope, correction/supersession history, publication cursor/outbox, public versus private projections |
| Schedules | `event`, entries, packs and in-memory calendar | Global/player bags, Guide payloads, notifications | Revisioned schedule read model; cancellation/correction semantics; incremental cursor rather than full rebroadcast |
| Markets | Market definitions, inventory, assets, transfers, ledger, production runs, current supply plan and forensic signals | Player-specific Market payload; inspect/purchase events | Explicit public stock versus entitled stock versus private knowledge; timestamps/revisions; avoid exposing manufacturer internal signals by default |
| Machine Knowledge | Discovery summary plus append-only `vehicle_knowledge_evidence` keyed to driver/world/model/optional asset | Collection payload and market inspection/discovery | No complete observation store or API; spec says knowledge is multidimensional and evidence-backed, not the simulation's omniscient truth |
| World identity | Opaque permanent `server_id` is already the world ID; environment is separate | Published world identity/tunables | Fail-loud agreement between resources; optional future `runtime_id` only for process/session operations; cross-world driver binding remains deferred |
| Authentication | OPEN//77 installation identity -> verified platform user ID -> per-world NCM driver binding | Authenticated network-event `source`; operator console ACL | No HTTP principal, service account, API key, scopes, consent or revocation model |
| Telemetry | 5 Hz client samples in bounded in-memory rings and ~10 s SQL chunks; 1 Hz server position fallback; incidents/results derived from both | `ncm:telemetry`, server vehicle/damage events, live session views, operator summary | Field dictionary/trust class, retention, consent, downsampled historical products, stable live subscription semantics |
| QA/support | `qa_observation`, `player_report`, logs | In-game report acknowledgement; operator console reads | Operator-only export with redaction/retention; never a public player-data feed |

### Live is not historical

NCM currently has three distinct temporal products and should preserve them:

1. **Live ephemeral state** — session phase, positions, standings, current schedule projection, current Market availability. State bags/events may drop, coalesce, expire, or be replayed as snapshots.
2. **Settled history** — completed results, transfers, production runs, ledger entries, evidence and incidents. SQL is authoritative; corrections must be additive/auditable rather than silent replacement.
3. **Current derived views** — standings, balances, availability, Machine Index cards, supply plan. These can be rebuilt and may change when rules or knowledge change.

An eventual API must label `asOf`, source/provenance, world, revision, and settlement/correction state. A live projection must never be archived as if it were the settled record, and a settled record must not be repeatedly shipped through live replication.

## 4. Event and telemetry surfaces

NCM has a real telemetry pipeline, not merely logging: client samples at 5 Hz, batches of at most 10, validation for shape/clock/jumps, a 60-sample ring per driver/session, course projection, drift comparison to server position, gate crossing, rolling-start checks, incident inference, and optional SQL chunks. When the client stream is absent, the server's 1 Hz authoritative position read provides a lower-resolution fallback. Canonical `onVehicleDamageChanged` adds damage evidence, but cannot name the struck world object.

Trust is field-specific. Client drivetrain/motion samples are useful observations and diagnostics; canonical player/vehicle snapshots, accepted gates and server clock govern sporting decisions. Physical motion itself is still client-simulated under OPEN//77 authority leases. Telemetry chunks currently embed compact positional arrays and are keyed by session/driver, with no explicit retention or consent policy. They should remain internal until a field dictionary, trust classification, retention window, access class and downsampling rule exist.

The local event bus is synchronous and non-durable. Platform and resource events may be missed across restart and are not a historical subscription. If external tools eventually need reliable notifications, emit them **after the SQL commit** through a small durable publication/outbox record keyed by the canonical object/version. Do not promise exactly-once delivery; promise idempotent effects and resumable cursors.

## 5. Authentication, privacy, and rate limiting

### Authentication

In-game authentication is inherited from OPEN//77: the connection has a persistent verified installation/user identifier, and NCM binds that platform user to a per-world NCM driver. That proves who sent a network event in this world. It does not authenticate an HTTP caller and it does not yet prove one global NCM Driver across servers.

Do not mint a public token format now. When a real external consumer exists, define principals and scopes first: player, operator, world service, and possibly read-only public. An OPEN//77 route may validate a narrow shared secret or gateway signature as an adapter, but long-lived third-party credentials, consent and revocation belong in the companion/gateway tier.

### Privacy

Adopt exposure classes before adding routes: **public**, **bucket-visible**, **subject-private**, **team/organization**, **operator**, and **internal/forensic**. Default unknown fields to internal. Specific cautions:

- platform user IDs and bindings are authentication data, not public Driver identity;
- location, raw telemetry, support reports, QA context, Market access/knowledge and inbox/narrative state are not public by default;
- Machine Knowledge belongs to the knowing principal; the server's hidden canonical values are not automatically knowable;
- an observation can expose another machine's serial, time and coordinates even if the observing driver's identity is omitted;
- public results can name sporting identities while private ledger, bets, account identifiers and detailed telemetry stay separate;
- logs and forensic JSON need retention/redaction rules even if no HTTP route exists.

### Rate and size control

OPEN//77 supplies state-bag safety caps (including request/write rates) and transport envelopes, but those are platform protection, not product quotas. NCM has local bounds and a few cooldowns, yet no shared per-principal request budget. Before any HTTP exposure, use one small adapter-level limiter keyed by authenticated principal plus route class, hard response/page limits, query timeouts, and concurrency caps. Expensive aggregation should never run synchronously inside a race tick. Preserve the existing lesson from the Guide: full broadcast payloads already fail somewhere between roughly 17.9 and 22.5 KiB in the current path, even when individual mechanisms claim larger theoretical envelopes.

## 6. Expensive retrofits to avoid

1. **Changing identity meaning.** Keep `server_id` as opaque permanent world identity; keep environment separate. Assert both NCM resources agree. Add `runtime_id` later only where a process instance matters.
2. **Results without the machine/configuration at the time.** Migration 024/026 is the right early correction. Preserve `asset_id`, attribution basis/rule, entry machine and `configuration_ref`; never reconstruct truth from current ownership.
3. **Flattening provenance.** Physical, simulated, estimated, DNF/disconnected, recorded/derived/unknown, documented/observed/researched/owned must survive into storage and read models.
4. **Publishing mutable internals.** SQL columns, Lua tables, local events and state-bag payloads will change. External consumers should receive versioned semantic projections only after a second consumer proves the boundary.
5. **No correction history.** Sporting classifications, schedules, title and markets will need operator corrections. Silent UPDATE-only history makes public caches and audits irreconcilable.
6. **No incremental publication key.** Polling whole schedules/results/markets becomes expensive. Canonical objects need stable IDs, meaningful `updated_at`/revision or an append-only publication cursor before external synchronization begins.
7. **Mixing privacy with transport.** A player bag is not subject-private; a targeted event is not durable; HTTP is not authenticated merely because it runs inside the server.
8. **Treating telemetry as one trust level.** Source, sample time/age, authority epoch, units, missingness and derivation must remain available wherever data can affect competition or public claims.
9. **Cross-world identity by accident.** The single conceptual NCM Driver is locked, but federation is deferred. Do not expose a per-world binding as though it were a globally portable credential.
10. **Market leakage.** Public inventory, access entitlement, personal discovery, live supply plan and forensic manufacturer signals are different products. One broad “market JSON” would erase that boundary.

## 7. Cheap substrate decisions recommended now

These are recommendations, not endpoint designs or implementation authorization.

1. **Classify existing projections by audience.** Record each state-bag key and targeted payload as public/bucket/subject/team/operator/internal. Move nothing in this audit; fix only confirmed mismatches in later scoped work.
2. **Name the world boundary once.** Affirm `server_id == world identity`, keep `environment` separate, and add the already-proposed boot-time cross-resource agreement assertion. Defer `runtime_id` until multiple processes or operational correlation require it.
3. **Preserve source and time on facts.** New durable observations/results should carry world, canonical object ID, occurred/observed time, source/provenance, and schema/rules revision. Machine observations also need asset serial identity and coordinates per the current spec.
4. **Separate live, settled, and derived read models.** Keep state bags/events for bounded live projections; SQL for settled history; explicitly rebuildable views for current summaries. Do not design URLs yet.
5. **Require additive correction semantics for public facts.** Before exposing results, schedules, transfers or Market history externally, choose revision/supersession rather than destructive rewrite. The exact table/endpoint can wait.
6. **Add a publication cursor only with the first external consumer.** Prefer a small commit-after outbox/change ledger over triggers, log scraping or direct table polling. Do not build it speculatively, but do not ship an external integration without it.
7. **Keep HTTP as an adapter.** A future `ncm_api` resource may host bounded routes; a companion may consume the same semantic service. Neither owns sporting/economic authority. Re-query the actual .87+ API cards before choosing.
8. **Define retention before exporting telemetry or observations.** Raw traces, downsampled analytics, incidents and player-visible observations need separate retention/access rules. Until then they remain internal.
9. **Do not create public auth yet.** The first non-game consumer must bring a concrete threat model and principal/scope requirement. A public-read surface and an operator mutation surface must never share an implicit trust mode.

## 8. Deferred deliberately

Endpoint paths, JSON field names, REST versus RPC, pagination syntax, webhooks, WebSockets, API version numbers, public-site hosting, OAuth provider choice, cross-server federation and global Market design are all deferred. They are cheap to decide after one consumer exists and expensive to guess now.

## Evidence and confidence

- Platform HTTP: captured [Open77.http API card](evidence/2026-09-19/Open77.http.txt), build .78 fallback noted in [access evidence](evidence/2026-09-23-access/README.md).
- State-bag audience/caps: captured [state-bag guide](evidence/2026-09-19/guide-state-bags-audience-caps.md).
- Identity: captured [identity guide](evidence/2026-09-19/guide-identity.md) and current `ncm_world/server/identity.lua`.
- NCM surfaces/data: current manifests, server/client Lua, and schema migrations 001–027.
- Architectural context: the seven assessment documents linked from this folder's [README](README.md).

**Confidence labels:** HTTP existence and current NCM registrations are code/document verified; internet-facing listener behavior not named in the API card is unknown; companion-service recommendations are architecture judgment. No runtime HTTP probe was performed.
