# OPS — NCM Staging (AWS Lightsail, Linux)

Day-to-day recipe for the staging server. Facts: Ubuntu 24.04, 2 vCPU / 4 GB, static IP `52.60.225.137`,
OPEN//77 `2.31.13+op77.84 linux-x64`, server id `6b154fdc-d515-4903-97dd-df37cb966151`, name "NCM Staging",
unlisted. Layout `/opt/ncm/{server,resources/ncm,mods,logs}`; systemd unit `ncm-server` (`Restart=always`, so any
exit — including a Warden restart — comes straight back in 5 s). MariaDB 10.11 on the box, db `ncm`, user
`ncm@127.0.0.1`; the password lives only in `/opt/ncm/server.env` (mode 600) and is never printed.

Secrets rule: never `cat server.jsonc` (it holds the licence). Read it through `tools/o77-config-show.ps1` or the
targeted python scripts in `tools/staging/`, which print only the section they touch.

## Access
- SSH key: `C:\Users\eveng\.ssh\lightsail-ncm.pem` (the Lightsail download, copied). User `ubuntu`.
- Warden is bound to `127.0.0.1:11780` on the box and is **never** opened to the internet. Reach it through a tunnel:
  ```
  ssh -i C:\Users\eveng\.ssh\lightsail-ncm.pem -N -L 11790:127.0.0.1:11780 -o ServerAliveInterval=30 ubuntu@52.60.225.137
  ```
  then browse `http://127.0.0.1:11790`. Leave that window open while you work.

  **Easier:** double-click `tools\ncm-tunnel.cmd`. Same command with keepalives, plus it refuses to start if
  something else already holds 11790 (and names the PID), and it reconnects itself after a drop instead of
  dying silently mid-session. One window, leave it open.

  **Agent egress differs by host — check, do not assume (corrected 2026-09-22).** This previously read "no sandbox
  of Claude's has network egress to `52.60.225.137`", which is false as a general claim and cost a hand-off it did
  not need to. The observed split: the **Claude Code GUI/desktop app could not** reach the box, but **Claude in the
  VS Code extension can** — it opened SSH on port 22 directly and ran `deploy-staging.ps1` end to end on
  2026-09-22 (deploy 9). So: an agent should test reachability (`Test-NetConnection 52.60.225.137 -Port 22`) rather
  than assume either way, and this launcher is the hand-off point only when that test fails.
- Firewall is two layers: **ufw on the box** (22/tcp, 11778/udp, 11779/tcp) *and* the **Lightsail instance firewall**
  (Networking tab). Both must pass 11778/udp + 11779/tcp (KB-9). Lightsail's default only passes 22 and 80.

## Everyday commands (any terminal; `ssh` ships with Windows)
| Want | Command |
|---|---|
| Restart the server | Warden → **RESTART** (top right), or `ssh -i C:\Users\eveng\.ssh\lightsail-ncm.pem ubuntu@52.60.225.137 sudo systemctl restart ncm-server` |
| Is it up | `ssh -i C:\Users\eveng\.ssh\lightsail-ncm.pem ubuntu@52.60.225.137 systemctl is-active ncm-server` |
| Required-mods line | `ssh -i C:\Users\eveng\.ssh\lightsail-ncm.pem ubuntu@52.60.225.137 grep -i "required mods" /opt/ncm/logs/server.log` |
| Tail the log | `ssh -i C:\Users\eveng\.ssh\lightsail-ncm.pem ubuntu@52.60.225.137 tail -n 60 /opt/ncm/logs/server.log` |
| Console commands | Warden → Live console (`ncm.calendar`, `ncm.race.now <route>`, `ncm.car <pid> formula <team>`, `ncm.rc.*`, …) |

Do not restart with clients connected unless you accept the kick (KB-5).

## Connecting a test client

A directly-launched game does **not** auto-connect. E0 (2026-09-19) established that `OP77_CONNECT` and
`OP77_CONNECT_MASTER` are ignored unless the launcher performs the handoff — the plugin only dispatches a boot
connect target that way. `OP77_IDENTITY_PROFILE` and `OP77_PLAYER_NAME` **are** honoured, which is why a
directly-launched tester still keeps its own identity.

So the client starts at the main menu and connects itself. Press `` ` `` for the dev console and enter:

```
resource.emit open77:shell:autoconnect 52.60.225.137:11778 alpha
```

`alpha` is the **master**, and it is a required positional argument, not a flag you can drop. Use `127.0.0.1:11778`
against a local server.

Do **not** call `Open77.network.connect(...)` from the console instead: that is the internal API the shell calls
*after* its own bootstrap reset, so invoking it directly skips the setup the shell would have done first.

Launching the second client under its own identity:

```
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\o77-client.ps1 -Profile ncm-tester2 -Name ncmtester2
```

~4.2 GiB VRAM per in-world client, so two is the practical ceiling on this PC. All instances share the save
folder — run `tools\o77-backup-saves.ps1` first. Expect 60–150 s before the window appears, and cross the
"press any key" screen by hand.

**If a client joins on top of another player** and both puppets stick: `ncm.unstick <playerId>` from Warden's
Live Console steps them off. NCM also does this automatically on join, on a racer's resume teleport and after
`ncm.tp` (KB-58) — but the automatic guard only exists from deploy 14 onward.

Restart timing (observed 2026-09-21): `Open77.Server` does not exit on SIGTERM; systemd waits its 90-s stop timeout,
SIGKILLs it, then starts the new process — a restart is ~100 s end to end, not 5 s. An interrupted `deploy-staging.ps1`
has usually already issued the restart; check `journalctl -u ncm-server` before assuming nothing happened.

## Deploying NCM code
From the repo, in PowerShell (only needed when `ncm/online/resources/**` or `ncm/core/**` changed):
```
powershell -NoProfile -ExecutionPolicy Bypass -File tools\deploy-staging.ps1          # build core → sync → config touches → restart → grep log
powershell -NoProfile -ExecutionPolicy Bypass -File tools\deploy-staging.ps1 -Logs    # just tail the remote log
powershell -NoProfile -ExecutionPolicy Bypass -File tools\deploy-staging.ps1 -Mods    # also upload %LOCALAPPDATA%\NCM\mods\*.zip to /opt/ncm/mods
```
Round trip is ~50 s. The script sends remote commands base64-encoded in argv (PowerShell 5.1 + ssh.exe mangle
quotes and prepend a BOM on stdin — don't "simplify" it back). Expect in the tail: `migrations: … pending=[]`,
`scheduler started`, `race control started`, `teams seeded: 10`.

## Upgrading the OPEN//77 server (KB-51)

`tools/staging/upgrade-open77.sh` verifies the package against its embedded manifest, keeps operator state, and
backs the old tree up to `/opt/ncm/backups/server-<UTC>` with automatic rollback on a failed start.

**After upgrading, before restarting, ALWAYS run the load-list guard:**

```
scp -i <key> tools\staging\check-load-list.py ubuntu@52.60.225.137:/tmp/
ssh -i <key> ubuntu@52.60.225.137 "python3 /tmp/check-load-list.py"
```

Exit 0 = every dependency of every loaded resource is itself in `resources.load`. Non-zero = **the server will
abort its entire automatic start set and NCM will not run**, while still listening and registering with the
master so it looks healthy. This is not hypothetical: .84 -> .87 added `open77_cyberware_lab`, made the shipped
`freeroam` depend on it, and took NCM offline for an hour (KB-51).

To fix, add the named resource to `resources.load` **after its own dependencies** — see
`tools/staging/add-cyberware-lab.py` for the shape. Do **not** edit a package-shipped `open77.lua` to remove the
dependency: it works, and it silently conflicts on every future upgrade.

Post-upgrade health, in one line each: `migrations: N applied` → `ownership ledger ready` →
`ncm_world started v…` → `class ceilings published` → `scheduler started: 5 series`. If the series line is
missing, NCM did not start.

## Required mods (state as of 2026-09-20)
Imported in Warden and on disk: `rb15-f1-inert-v10` 10.0.0, `ncm-rb15-liveries` 1.0.0 (both INERT),
`archivexl` 1.27.1, `tweakxl` 1.11.4 (executable). **Parked**: `requiredMods.enabled=false, unsecured=false`
because the launcher refuses every hosted hash (`Unverifiable`, KB-8). Testers install by hand (P34).

Flag scripts (upload with `scp -i <key> tools\staging\<name>.py ubuntu@52.60.225.137:/tmp/`, run with
`ssh -i <key> ubuntu@52.60.225.137 "python3 /tmp/<name>.py && sudo systemctl restart ncm-server"`):
- `set-unsecured.py` — `enabled=true, unsecured=true`, drops indexed loader entries. **Run it after any Warden
  import**: an import rewrites the `requiredMods` block and silently drops `unsecured`.
- `set-mods-off.py` — `enabled=false, unsecured=false` (current parked state).
Warden's Mods page has no unsecured toggle and no review button; the review API works from the browser console:
`fetch('/api/mods/<id>/request-review', {method:'POST'})` on the Warden tab.

## Rebuild from nothing
1. Lightsail: Ubuntu 24.04, 2 vCPU/4 GB, static IP, firewall rules above, SSH key downloaded.
2. `scp` the server tar and `tools/staging/bootstrap.sh`; on the box `bash bootstrap.sh /tmp/open77-server.tar.gz /tmp/ncm-db-pass`
   (write the DB password to that file first; the script shreds it). Create `/opt/ncm/server.env` with
   `OP77_DATABASE_CONNECTION=…` and `OP77_WARDEN_SETUP_LISTEN=http://127.0.0.1:11780`, mode 600.
3. `sudo systemctl start ncm-server`, open the tunnel, finish Warden onboarding at `http://127.0.0.1:11790`
   (game port 11778, public endpoint `52.60.225.137:11778`, unlisted, licence key from the DPAPI store).
4. `tools\deploy-staging.ps1` — applies `database.enabled=true` and `"ncm/*"` to `resources.load`, syncs, restarts.
5. Re-import the four mod zips in Warden if hosted delivery is being tested again.
