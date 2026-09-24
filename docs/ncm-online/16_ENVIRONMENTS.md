# NCM environments — the world and the workshop

**Status:** architecture agreed (L112). **NCM Development is standing as of 2026-09-24 (L121).**
NCM Online is **unchanged**: still `serverId = ncm-dev`, unrenamed, and `deploy-staging.ps1` still defaults to
`-Target online`. Cutover steps 1-2 are done; **steps 3-6 remain the operator's call** and are still gated on
the ordinary-player spine below. Standing up the workshop never required touching the world.

> **NCM Online is the world. NCM Development is the workshop.**

---

## Why

The single Lightsail server is doing two jobs that have stopped being compatible. It is the environment we
deploy to constantly, restart, migrate and deliberately break — and it is the server unsolicited players have
been joining and treating as a real NCM world. On 2026-09-23 a visitor stayed an hour; the same evening the
server was restarted nine times.

Every release since has added durable world state — vehicle assets, ownership, money, markets, discoveries,
race history, seasons, Help reports, QA evidence, saved locations. The cost of confusing the two is now a
canonical world, not a lost test.

## What already supports this (verified, not assumed)

| Capability | State |
|---|---|
| Windows dedicated server | **exists** — `tools/o77-server.ps1` runs OPEN//77 from `tools/open77/server`, with DPAPI-held licence/DB credentials |
| Local resource loading | **exists and is better than production's** — a directory junction `tools/open77/server/resources/ncm -> ncm/online/resources`, so local edits are live with no copy step |
| Local database | **exists** — `tools/db-setup.ps1` installs MariaDB and creates the `ncm` database/user idempotently |
| Per-world data scoping | **exists** — every canonical table is keyed `server_id`; two worlds cannot silently merge |
| Forward-only migrations | **exists** — `NcmSchema` + `server/migrations.lua`, one transaction per version, replay-safe |
| Environment-specific settings | **exists** — `Open77.tunables.declare`, `apply = "live"`, edited in Warden. No second config file is needed |
| Deployment targeting | **added 2026-09-23** — `deploy-staging.ps1 -Target online|dev`, with a banner naming the world |
| Version control | **added 2026-09-24** — private repo `github.com/evengineer1ng/ncm-online`; the promotion unit is now a named revision rather than "whatever is on the disk" (L121) |
| Platform upgrades on Windows | **added 2026-09-24** — `tools/o77-upgrade.ps1`, the counterpart of `upgrade-open77.sh`: verifies the package against its own manifest, preserves operator state, runs the KB-51 load-list guard **before** the swap, keeps a rollback tree |
| Database version pinning | **added 2026-09-24** — `tools/db-pin-1011.ps1` pins the dev engine to production's exact version |

The two-environment model is roughly 80% built already. What was missing was identity, not machinery.

## The critical fact about identity

**Every canonical row in the live world is keyed `server_id = 'ncm-dev'`.**

```
vehicle_asset ncm-dev x3 · ledger ncm-dev x15 · event ncm-dev x384
vehicle_discovery ncm-dev x14 · player_report ncm-dev x1 · qa_observation ncm-dev x3
```

So:

> **`serverId` is an opaque identity, not a statement about environment. It must never change on the live
> world.** Renaming to NCM Online is a display and access change. Changing `serverId` would not rename the
> history; it would orphan it — 384 events and the first persistent player-owned asset would become
> unreachable rows belonging to a world that no longer exists.

The role a server plays is carried by a **separate** `environment` tunable (`development` | `online`), which
defaults to `development` so a fresh or misconfigured server is never mistaken for the world.

This means **cutover needs no data migration at all.**

## Architecture

| | NCM Online | NCM Development |
|---|---|---|
| Host | Lightsail / Linux | developer's Windows PC |
| Identity | `serverId = ncm-dev` (historical, permanent) | its own `serverId`, e.g. `ncm-devbox` |
| `environment` | `online` | `development` (default) |
| Database | canonical, backed up, forward-migrated only | local MariaDB, disposable |
| Access | whitelist removed when deliberately opened | private to the developer |
| Deployment | promoted releases only | live via the resources junction |
| Restarts | announced (KB-5 / L90) | freely |
| QA instrumentation | passive, field evidence | plus destructive and console-driven QA |

## Promotion, not copying

```
DEVELOP → gates → controlled QA → release candidate → PROMOTE → NCM ONLINE → field evidence → next cycle
```

A finished coding task does not mean production changes. A **known revision** is promoted.

### The procedure, using the tooling that exists

1. Develop on Windows. The junction means edits are live; `o77-server.ps1` restarts freely.
2. `tools/ncm-test.ps1` — core tests on both interpreters, host harnesses, `luac -p`, `node --check`, panel
   render checks. This is the gate; it must be green.
3. Controlled QA on Development: the console-driven and destructive items of `wp/OFFLINE_TEST_QUEUE.md` that
   passive observation can never reach.
4. Identify the revision being promoted and read `NcmMigrations.status()` — know which migrations will run
   against the canonical world **before** they run.
5. Back up the production database (`/opt/ncm/backups/...`, as the access release already did).
6. `tools/deploy-staging.ps1 -Target online -NoRestart`, then restart and poll for `is-active`.
7. Smoke check: boot lines, `migration NNN applied`, zero script errors, `ncm.qa` for new FAILs.
8. Leave it running. Development continues separately.

### Hotfix

Same path, narrower change. The point of the boundary is not ceremony: it is that the fix is *tested somewhere
first*. A genuine production blocker goes dev → gate → promote, skipping only the unrelated work in flight —
not skipping the gate.

## Database safeguards

- **Promotion moves code, resources, config and migrations. It never moves data.** `deploy-staging.ps1` syncs
  `ncm/online/resources` and touches `server.jsonc`; it has no path that writes to the production database.
- **Production schema changes are forward migrations only**, against the existing canonical world. Migration
  015 deliberately left `owned_vehicle` in place rather than renaming it, and 019 used
  `ADD COLUMN IF NOT EXISTS`, precisely so a replay cannot wedge the runner.
- **Development data never reaches production**, because it lives in a different database on a different
  machine under a different `serverId`. There is no copy step that could carry it.
- **Provenance is preserved by not touching identity.** The first persistent player-owned asset
  (`10000000-…0001`, a Makigai MaiMai bought for €$2,500) stays exactly as it is.

## QA evidence across environments

`qa_observation` rows already carry `server_id`, and now carry the environment in `build`
(`world 0.5.0 · league 0.3.0 · online`). A FAIL seen on the developer's box and a FAIL seen on the official
world are different facts and will not be confused. The two environments share no state and neither depends on
the other.

## Windows / Linux parity — real risks found in this codebase

| Risk | Reality |
|---|---|
| Deployment scripts | `deploy-staging.ps1` is PowerShell + `ssh`/`scp`/`tar`; it is a *promotion* tool and only ever runs on the developer's machine. Not a parity risk. |
| Path separators | Lua `require`/`dofile` paths in the repo use `/`; the manifest uses `/`. `ncm-build.ps1` normalises. Low risk. |
| **Filesystem case sensitivity** | **The real one.** Windows is case-insensitive, Linux is not. A resource file referenced as `Server/Main.lua` would work on the dev box and fail on Lightsail. The `luac -p` gate walks actual files, so a *missing* file is caught, but a *case-mismatched reference* is only caught on Linux. |
| Line endings | Already bitten us: a CR-insensitive diff was needed to compare local and deployed files. Cosmetic, but it makes verification harder. |
| **MariaDB version** | **This row used to read "same engine both sides". It was false.** On 2026-09-24 the box had **13.0** (winget has no 10.11 build at all) against production's **10.11.14**. The danger is directional: a newer engine ACCEPTS syntax an older one rejects, so the dev box goes green and production still breaks -- false greens flow downhill into the canonical world. Now pinned to 10.11.14 from the official archive, checksum-verified (`tools/db-pin-1011.ps1`). `ADD COLUMN IF NOT EXISTS` remains verified against the live 10.11. **Re-check this row whenever either side is upgraded.** |
| Schema charset | Every one of the 23 migrations declares `CHARSET`/`COLLATE` explicitly, so a 13.0 dump restored into 10.11 with no collation rewrite. MariaDB changed its default collation in 11.5; without that discipline the version gap would have been a silent divergence. |
| **Resource load list** | **The one that has actually bitten (KB-51).** `resources.load` is an explicit allow-list, not a directory scan, so a platform upgrade that adds a resource and makes a loaded one depend on it aborts the WHOLE automatic start set -- while the server still listens and registers, looking healthy with NCM absent. Reproduced on the Windows box during the `.87` upgrade and stopped before the swap. `tools/staging/check-load-list.py` now takes a server root argument and runs on both sides; `tools/o77-upgrade.ps1` runs it against the candidate tree before swapping. |
| Native/platform | The OPEN//77 server is the same product on both; `o77-server.ps1` already runs it on Windows. |

**Cross-VM references (not a parity risk, but the same family):** `ncm_world` and `ncm_league` are separate
Lua VMs and a global from one is `nil` in the other. This bit three times on 2026-09-23 and is now enforced by
`tools/test-cross-scope.lua` in the gate (L113).

**Mitigation that costs nothing:** the promotion smoke check reads the boot lines. A case-mismatch or missing
resource shows up immediately as a resource that failed to start, which is exactly what step 7 looks for.

## Cutover — the exact steps, when the operator decides

**Not now.** The gate is the ordinary-player spine, still unproven:

> join → Help → Guide/Market → buy a legitimate vehicle → persistent ownership → Machine Index/CALL →
> interest → GPS → venue registration → race start → race completion → history/settlement

That is MASTER_TEST §AC11 and the surrounding §S/§U/§Y items. When the operator judges it proven:

1. Stand up NCM Development on Windows: `db-setup.ps1`, `o77-server.ps1`, confirm the junction, set its own
   `serverId` (e.g. `ncm-devbox`) and leave `environment = development`.
2. Confirm the two databases are genuinely separate (different host, different credentials).
3. On Lightsail, set the Warden tunable `environment = online`. **Leave `serverId` alone.**
4. Rename the *display* identity (server name/branding) to NCM Online. Not `serverId`.
5. Flip `deploy-staging.ps1`'s default `-Target` from `online` to `dev`.
6. Remove the player whitelist when, and only when, the build is judged ready for open access.
7. From then on: develop on Windows, promote deliberately.

Steps 3–6 are configuration and one default. **No data migration, no renumbering, no reset.**
