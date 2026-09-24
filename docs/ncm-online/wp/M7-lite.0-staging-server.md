# WP M7-lite.0 — Staging server on AWS Lightsail

Milestone: M7-lite (first package). Status: **planned 2026-09-20**. Depends on: nothing in code; M4-lite complete. Decisions: Q16 (server on this machine for development), TW1 doc §G3 (residential uplink is unmeasured), L43 (TW1 needs a public server), Q24 (secured/inert first).

## Why now
- The hosted-mods pipeline (E13) can only be proven with a **routable public endpoint**: the master refuses to publish a catalogue row for loopback/private addresses (Warden: "IP must be routable for public listing"), so the launcher never sees required mods from a home LAN server. Remote testers need this box regardless.
- The dev loop stays on this PC (hot restarts, direct log access, two local clients). Lightsail is **staging/production**, fed by a one-command deploy.

## Facts that shape it
- The OPEN//77 dedicated server is a self-contained **.NET 10 win-x64** build (`Open77.Server.exe`, GameNetworkingSockets.dll, native `Open77.Platform`); no Linux runtime ships and the docs mention none → **Windows Server instance**. Owner action: ask the OPEN//77 devs whether a Linux build exists or is planned (halves the cost).
- Ports: **UDP 11778** (game), **TCP 11779** (resources + mod blobs), Warden **11780** and the DB bridge **11781** stay bound to 127.0.0.1 and are reached through an SSH/RDP tunnel only.
- MariaDB runs on the instance (`db-setup.ps1` pattern), DPAPI secrets re-created there (`ncm-secret.ps1`), `OP77_LICENSE_KEY` injected by the launcher script as today. The owner's second license/server identity: the master registered this server as `1f841694-…`; a new box gets a new registration.
- KB-5: resource restarts kick connected clients on chunk-cache mismatch — deploys go out between sessions, not during.

## Deliverables
1. **Instance:** Lightsail Windows Server 2022, 2 vCPU / 8 GB (floor for 8–20 clients; measure), static IP, firewall: 11778/UDP + 11779/TCP open to all, 3389 (RDP) + 5986 (WinRM-HTTPS) restricted to the owner's IP; Windows Firewall rules for `Open77.Server.exe`.
2. **Bootstrap script** `tools/staging/bootstrap.ps1` (run once on the box): .NET runtime not needed (self-contained), MariaDB 13 install + `ncm` db/user, folder layout `C:\ncm\{server,resources,mods}`, scheduled task or NSSM service to run `o77-server.ps1` at boot, log rotation.
3. **Deploy script** `tools/deploy-staging.ps1` (run from this PC): rsync-equivalent over WinRM/SSH of `ncm/online/resources/**`, `tools/open77/server/server.jsonc` (with staging overrides: `publicEndpoint = <static IP>:11778`, `publicBaseUrl = http://<static IP>:11779/`, `visibility = unlisted`), and `%LOCALAPPDATA%\NCM\mods\*.zip` → remote Warden import is manual the first time (hash-stored blobs are portable: `server/.open77/mods/*` can be synced directly); then a remote restart. Prints the remote `Required mods: N declared, digest=…` line.
4. **Ops notes** in `docs/ncm-online/OPS_STAGING.md`: how to RDP/tunnel to Warden, restart, read logs, roll back a deploy, rotate the license key.

## Completion criteria
1. Launcher **catalogue row** exists: the server appears in the launcher (visibility `listed` for the test, then `unlisted`), and the deep link `open77://connect?server=<id>&endpoint=<ip>:11778` resolves to it.
2. **E13 passes:** a fresh join through the launcher shows the consent screen listing `RB15 F1 (car only, no ERS)` and `NCM RB15 team liveries`, both badged unverified/inert; the client downloads them from `http://<ip>:11779/mods/v1/blobs/<sha>`; join succeeds; the launcher log shows the world layer projecting 10 files.
3. Both local clients (owner + tester profile) join staging; a street race runs end to end there (M3.3 flow) with acceptable ping.
4. `deploy-staging.ps1` round-trips a resource change (edit → deploy → remote restart → visible in game) in under two minutes.
5. Measured: instance CPU/RAM and tick time with two clients racing; the numbers go into the TW1 doc §G3 as the first capacity data point.

## Out of scope
The RB15 in the world (M7-lite proper), team cars, migration 006, any Linux port, HTTPS for the resource transport (optional per the platform; revisit if the launcher warns), autoscaling.

## Result (2026-09-20)
Built on **Linux** (Ubuntu 24.04, Lightsail 2 vCPU/4 GB, op77.84 linux-x64), not Windows as first written. `tools/staging/bootstrap.sh` + `tools/deploy-staging.ps1` (base64 argv remote commands; the Windows tar) are the reproducible path; `OPS_STAGING.md` has the day-to-day recipe.

| # | Criterion | Outcome |
|---|---|---|
| 1 | Catalogue row + deep link | **Met.** Row appears with icon/banner/tags once the endpoint is routable (KB-7) *and* the Lightsail firewall passes 11778/udp + 11779/tcp (KB-9). |
| 2 | E13 consent screen + download | **Blocked upstream (KB-8).** Launcher refuses every hosted hash as `Unverifiable` before download; unsecured mode does not lift it; indexed loaders `NotInIndex`. Reviews queued. |
| 3 | Two clients race on staging | Not yet run (owner chose to push mod delivery first). |
| 4 | deploy round-trip < 2 min | **Met** (~50 s incl. restart). |
| 5 | CPU/RAM/tick with two clients | Not yet measured; idle: ~700 MB RSS, tick 0.3–0.4 ms. |

Unplanned win: the **RB15 renders and drives on staging** with the client's own files (Formula class, exact record spawn) — the first NCM mod car in multiplayer, via the manual path P34.

