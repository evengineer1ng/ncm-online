# OPS — NCM Staging (AWS Lightsail, Linux)

> **STATUS: CURRENT** - authority for: *day-to-day operation of NCM Online* - affirmed 2026-09-24
> Authority map: [INDEX.md](INDEX.md) - classified 2026-09-24 (L125)

Day-to-day recipe for the staging server. Facts: Ubuntu 24.04, 2 vCPU / 4 GB, static IP `52.60.225.137`,
OPEN//77 `2.31.21+op77.124 linux-x64` (platform-only upgrade 2026-10-02, L290), server id `6b154fdc-d515-4903-97dd-df37cb966151`, name "NCM Online",
unlisted. Layout `/opt/ncm/{server,resources/ncm,mods,logs}`; systemd unit `ncm-server` (`Restart=always`, so any
exit — including a Warden restart — comes straight back in 5 s). MariaDB 10.11 on the box, db `ncm`, user
`ncm@127.0.0.1`; the password lives only in `/opt/ncm/server.env` (mode 600) and is never printed.

Required-mod resources are public through Caddy 2.11.4 at
`https://52-60-225-137.sslip.io:11779/` (interim proof hostname). Caddy terminates TLS on public 11779 and proxies
to OPEN//77 at `127.0.0.1:11782`; its ACME HTTP-01 listener uses public TCP 80. Warden remains private at
`127.0.0.1:11780` and Caddy's admin socket remains private at `127.0.0.1:2019`.

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
- Firewall is two layers: **ufw on the box** (22/tcp, 80/tcp for ACME, 11778/udp, 11779/tcp) *and* the
  **Lightsail instance firewall** (Networking tab). Both must pass 11778/udp + 11779/tcp; TCP 80 must remain
  reachable for certificate issuance/renewal (KB-9). Lightsail's default passes 22 and 80.

## Everyday commands (any terminal; `ssh` ships with Windows)
| Want | Command |
|---|---|
| Restart the server | Warden → **RESTART** (top right), or `ssh -i C:\Users\eveng\.ssh\lightsail-ncm.pem ubuntu@52.60.225.137 sudo systemctl restart ncm-server` |
| Is it up | `ssh -i C:\Users\eveng\.ssh\lightsail-ncm.pem ubuntu@52.60.225.137 systemctl is-active ncm-server` |
| Required-mods line | `ssh -i C:\Users\eveng\.ssh\lightsail-ncm.pem ubuntu@52.60.225.137 grep -i "required mods" /opt/ncm/logs/server.log` |
| Tail the log | `ssh -i C:\Users\eveng\.ssh\lightsail-ncm.pem ubuntu@52.60.225.137 tail -n 60 /opt/ncm/logs/server.log` |
| Console commands | Warden → Live console (`ncm.calendar`, `ncm.race.now <route>`, `ncm.car <pid> formula <team>`, `ncm.rc.*`, …) |

Do not restart with clients connected unless you accept the kick (KB-5).

### After every OPEN//77 upgrade, run BOTH guards

The platform's resource tree is vendor-owned and an upgrade rewrites it, so two things have to be re-asserted
before the restart -- neither is optional and neither announces itself when it is missing:

```
scp -i C:\Users\eveng\.ssh\lightsail-ncm.pem tools\staging\check-load-list.py         ubuntu@52.60.225.137:/tmp/
scp -i C:\Users\eveng\.ssh\lightsail-ncm.pem tools\staging\close-freeroam-sandbox.py  ubuntu@52.60.225.137:/tmp/
ssh -i C:\Users\eveng\.ssh\lightsail-ncm.pem ubuntu@52.60.225.137 'sudo python3 /tmp/check-load-list.py && sudo python3 /tmp/close-freeroam-sandbox.py'
```

`check-load-list.py` catches a new dependency missing from `resources.load`, which aborts the whole automatic
start set and leaves a healthy-looking server with no NCM (KB-51). `close-freeroam-sandbox.py` evicts
`freeroam` and `open77_freeroam` from the load set, removes the discovery tag, retains `open77_animations`, and
keeps the earlier script/config edits as defence in depth (L131/L132). An upgrade restores the vendor tree and
may restore the config template, so read the script's state report: both freeroam resources must say `no`,
animations must say `yes`, and the dependency guard must still pass.

The eviction deliberately removes the forced join death. It also removes freeroam's respawn-after-death and
the no-argument animation picker. Until NCM owns those paths, reconnect is the respawn workaround and
`/anim <profile>`, `/anim list`, `/anim info` and `/anim stop` are the supported animation surface.

### The access list is upgrade-fragile — check it every time (KB-52, KB-137)

The whitelist and ban list live in `/opt/ncm/server/access.json`, at the root of the vendor-owned tree, written
by the server at runtime and **absent from the package manifest**. An upgrade that does not carry it forward
takes the whitelist down silently: the server is `active`, Warden loads, nothing logs a complaint, and the world
sits open until someone notices. It has now happened twice.

Two things must hold after any upgrade, and `upgrade-open77.sh` asserts both:

```
ssh -i C:\Users\eveng\.ssh\lightsail-ncm.pem ubuntu@52.60.225.137 \
  'ls -l /opt/ncm/server/access.json; stat -c "%A %U:%G %n" /opt/ncm/server'
```

- **`access.json` exists.** If it does not, the previous copy is in the upgrade backup
  (`/opt/ncm/backups/server-<stamp>/access.json`) — restore that rather than retyping identities.
- **The tree root is owned by the systemd service user** (`ubuntu`), not `root`. The server saves the access
  list by writing `access.json.tmp` beside it and renaming, so a `root:root` working directory makes every
  Warden access change fail with *"access list could not be saved; identity was not added"* — while the Warden
  API still returns `200` and only the audit log records `ok:false`. A tree becomes root-owned by running the
  upgrade under `sudo`; the script now repairs this before the swap.

**Order matters when rebuilding a whitelist by hand:** add the identities first, enable the whitelist second.
Enabling with an empty list disconnects and refuses everyone, the owner included. The owner's identity is
`ae3e440b-1384-4337-ba01-3bcc0a369d95` (easporks); the second test client, ncmtester2, is
`d82ed6cf-c5cb-4dd8-8473-3a1d0057d3b7`.

**A player can join after an empty-server check while systemd is already stopping the old process (KB-102).**
Re-check immediately before every restart, but do not call that a drain lock. A supported maintenance/admission
gate remains `IDEA-419`; do not improvise a permanent firewall rule as routine procedure.

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

## Required mods (state as of 2026-10-03 08:12 UTC) -- ONLINE BASELINE 2 (L299)

The Baseline 1 freeze is over (L299). Online runs dev's code at `fb23f35` (tag `online-baseline-2`) and dev's mod stack:
**8 required**, digest `7b070f256f80234de8565ec5f9b2f2b6949b7eb06ee5ee7e6f7710ddc578d833` (identical to dev's):
ncm-carrier 0.1.30, ncm-rig-bridge 0.1.7, ncm-vision 0.4.0, ncm-clock 0.1.0, ncm-broadcast 0.1.0, ncm-pace 0.9.2,
archivexl 1.27.1, tweakxl 1.11.4. The four NCM packages were imported with `publish-carrier.py /opt/ncm/server --zip
/tmp/<zip> --id <id> --import-blob --enable`; ArchiveXL and TweakXL were declared from the blobs already in the store
(copied to `/tmp/<id>-<ver>.zip`). All eight downloaded back over the public HTTPS endpoint with matching hashes. The
consent note names all eight. New resources `ncm_paddock`, `ncm_broadcast` (`check-load-list.py`: 44 resources OK).
Migrations 043-058 applied on boot. The Paddock ran GENESIS (170 orgs, 1544 people, 252 sponsors, 15 series): Online's
world is its own, not dev's. First boot: no ERR, production minting (`minted=2/2`, KB-311 proved live), NPC cars
minting, 24 races scheduled. Instance at boot: 2 vCPU, 3.8 GB (2.8 GB free), Open77.Server ~26 % CPU while minting.

**Pre-change backup:** `/opt/ncm/backups/pre-carrier-prod-20261003T080827Z` (`ncm.sql.gz` 92 tables,
`operator-state.tar.gz`, `resources-ncm.tar.gz`). **Rollback:** stop `ncm-server`; restore `resources-ncm.tar.gz` into
`/opt/ncm/resources/`; restore the database from `ncm.sql.gz` (migrations 043-058 add tables/columns -- the dump is the
only clean way back); restore `server.jsonc` from `operator-state.tar.gz` (the 3-mod declaration); start.

## Required mods (state as of 2026-09-29 15:45 UTC)

**Declared on Online:** `ncm-carrier` 0.1.30, `ncm-rig-bridge` 0.1.7, **`ncm-vision` 0.3.0** (sha256
`e44ecafa7de0da94b217fcaeb2aa73ffdac7249690f8774a75076d755b4d50c9`, 253,778 bytes: the QUICKHACKS and SCAN DATA
panels, and the looked-at point in the report, `KB-211`); manifest digest
`879af3286c16ed2ecd971024a8febbbe81ead75744576f4d4280f73a9fb82c99`. `ncm-radial` is not declared (pulled,
`KB-182`, radial row). The consent note names all three versions. Same deploy: `ncm_league` collection (record
index off the request path, network vehicle by position) and `ncm_scanner`/`ncm_world` chrome. Backup
`/opt/ncm/backups/pre-carrier-prod-20260929T154321Z`. Blob downloaded back over HTTPS with a matching hash.

### 2026-09-28 17:34 UTC

**`ncm-vision` is 0.2.1** (sha256 `73ce73ae831faccf5847fcb9291719be9341a6a208f6d682b8f86ca7436dda15`), manifest digest `46cfc0588afe325a3cff98a2b4475e967a2296973285bcd53bf38442769c13a9`. Everything else is as in the 17:29 entry below. 0.2.0 stopped the game from starting (`KB-182`) and was live about 5 minutes. 0.2.1 was published with the same tool, and the consent note names it. After the restart every NCM resource started and the blob downloaded over HTTPS with a matching hash.

### 2026-09-28 17:29 UTC

**Declared on Online:** `ncm-carrier` 0.1.28, `ncm-rig-bridge` 0.1.0, **`ncm-radial` 0.1.1** (sha256
`3114e10329fef9ac34f4ca867c897b35524440b897fe702b4566afeda2238e2e`, 245,870 bytes) and **`ncm-vision` 0.2.0**,
display name *NCM Scanner* (DLL + two scripts, `L197`; sha256
`0904d8708c05efd53752667bbbe907f33baef3539bb0e39406c8d46629e19208`, 243,998 bytes). `enabled=true,
unsecured=true`; manifest digest `531c022a5e6e28a432718551e7ddbd8936a9894796b0bc376ce0bc008b037a3f`. Both new
blobs were imported with `publish-carrier.py --id <id> --import-blob --enable` and downloaded back through the
public HTTPS endpoint with matching hashes. The consent note was rewritten to name the new versions.

Same deploy: the full resource tree, including the new `ncm_scanner` resource (loaded by the `ncm/*` wildcard;
`check-load-list.py` passed with 43 resources), the scan handlers and sighting-only proximity in
`ncm_league/server/collection.lua`, and ambient-car registration in `ncm_world/server/ambient.lua`. No
migrations. Boot: every NCM resource `started generation=1`, `collection ready`, `scheduler started: 5 series`,
no ERR. Pre-change backup: `/opt/ncm/backups/pre-carrier-prod-20260928T172655Z` (`ncm.sql.gz`,
`operator-state.tar.gz`, `resources-ncm.tar.gz`). Rollback for a package: `publish-carrier.py /opt/ncm/server
--id ncm-vision --remove` (or re-publish 0.1.0 from `/opt/ncm/mods`), then restart. **Not live-proven:**
`MASTER_TEST §BX` (radial) and `§BZ` (scanner) are owed.

### Earlier state (2026-09-28 16:41 UTC)

#### Required mods (state as of 2026-09-28 16:41 UTC)

**Declared on Online:** `ncm-carrier` 0.1.28, `ncm-rig-bridge` 0.1.0, `ncm-radial` 0.1.0 (DLL + redscript, quick
menu, `L195`) and `ncm-vision` 0.1.0 (redscript only, `L196`); `enabled=true, unsecured=true`; manifest digest
`258ec4cbe0bfa0b404f4b856389de06c6bf9e5af62d0fda95db83c5235fbe541`. Radial sha256
`0a07f1ee075c547fe11318da8c7ff67c784d6d88e680908474b8f46f7b35a30b` (244,205 bytes); Vision sha256
`5406fa60dff914e20f88d254892ff602dd66a6e138fd058d93a5b48252812d50` (2,931 bytes). Both were imported with
`publish-carrier.py --id <id> --import-blob --enable`, survived the restart in `.open77/mods`, and were downloaded
back through the public HTTPS endpoint with matching hashes. The consent note names all four packages.

Same deploy: the full resource tree (Exchange `L194`, health regen, the `ncm_radial` resource, F6 renamed Hub)
and migration 040 (`player_trade`, applied in 8 statements, preconditions checked on the live schema first).
Pre-change backup: `/opt/ncm/backups/pre-carrier-prod-20260928T163834Z` (`ncm.sql.gz`, `operator-state.tar.gz`
with the pre-change `server.jsonc`, and `resources-ncm.tar.gz`, the previously deployed resource tree).
Rollback for either new package: `publish-carrier.py /opt/ncm/server --id ncm-radial --remove` (or `ncm-vision`),
restart. **Not live-proven:** `MASTER_TEST §BT-§BY` are all still owed.

### Earlier state (2026-09-25)

## Required mods (state as of 2026-09-25 20:24 UTC)

The canonical Carrier build/publish/verify/rollback procedure is
[CARRIER_NEXT_STEPS_AND_UPGRADE.md](CARRIER_NEXT_STEPS_AND_UPGRADE.md). Use it for every in-place Carrier
replacement; do not manually copy the DLL or use a warm reconnect as acceptance.

**Enabled on the whitelisted Online world:** `requiredMods.enabled=true, unsecured=true`; sole declared package
`ncm-carrier` 0.1.1 (executable), 868,295 bytes, SHA-256
`6966a75d228cb70105f6201aaff4a2ab60ca6681ba78d65ad40acad4d2306301`; digest
`e0ad7ec9091c2b23f69067addb318c3d9fe319fc5111eb0ff76c47949b1bbde2`. RB15, NCM liveries, ArchiveXL and
TweakXL are not declared. The owner authorised this Production proof under `L147` and owns the remaining
launcher/game checks in MASTER_TEST section AT.

Caddy owns public TCP 11779 with a trusted certificate for `52-60-225-137.sslip.io`; OPEN//77 listens only on
`127.0.0.1:11782`. The master row relays the carrier HTTPS blob URL and executable classification. An external
full download matched the release ZIP's declared size/SHA-256; Range returned 206 with the hash ETag.
Warden stayed on loopback. `sslip.io` is an interim proof hostname, not permanent owned infrastructure
(`IDEA-452`). Certificate observed: Let's Encrypt, TLS 1.3, expires 2026-12-24; Caddy renews automatically.

Flag scripts (upload with `scp -i <key> tools\staging\<name>.py ubuntu@52.60.225.137:/tmp/`, run with
`ssh -i <key> ubuntu@52.60.225.137 "python3 /tmp/<name>.py && sudo systemctl restart ncm-server"`):
- `set-unsecured.py` — `enabled=true, unsecured=true`, drops indexed loader entries. **Run it after any Warden
  import**: an import rewrites the `requiredMods` block and silently drops `unsecured`.
- `set-mods-off.py` — `enabled=false, unsecured=false` (emergency/manual park; not the current state).
Warden's Mods page has no unsecured toggle and no review button; the review API works from the browser console:
`fetch('/api/mods/<id>/request-review', {method:'POST'})` on the Warden tab.

**2026-09-25 forensic correction and production transport deployment:** KB-112 / Report 35 recovered the exact
failure. Launchers `.89` and current `.100` discard every non-loopback HTTP hosted-mod URL, then call the missing
URL `Unverifiable`; unsecured consent and review were not the blocker. L137 authorised the whitelisted Online
proof. The HTTPS endpoint and MASTER_TEST §AP1 are live-green. Do not retry indexed loader IDs unless the signed
index actually contains them. Do not call the delivery path accepted until the owner completes §AP2-§AP7.

Deployment artifacts and rollback:

- checked-in Caddy config: `tools/staging/Caddyfile.required-mods`;
- checked-in idempotent dry-run/apply guard: `tools/staging/configure-required-mods-https.py`;
- pre-carrier database/operator backup: `/opt/ncm/backups/pre-carrier-prod-20260925T195327Z`;
- pre-`.102` platform tree: `/opt/ncm/backups/server-20260925T200746Z`;
- server config backup: `/opt/ncm/backups/required-mods-https-20260925T145252Z/server.jsonc`;
- prior Caddyfile backup: `/opt/ncm/backups/required-mods-https-prestage-20260925T145252Z/Caddyfile`;
- health: `systemctl is-active caddy ncm-server`, then independently GET the public manifest and one Range;
- park with `set-mods-off.py` if launcher acceptance finds a package/projection fault. Restoring the old
  public-HTTP endpoint does not make hosted delivery usable and is not an acceptable steady-state rollback.

## Rebuild from nothing
1. Lightsail: Ubuntu 24.04, 2 vCPU/4 GB, static IP, firewall rules above, SSH key downloaded.
2. `scp` the server tar and `tools/staging/bootstrap.sh`; on the box `bash bootstrap.sh /tmp/open77-server.tar.gz /tmp/ncm-db-pass`
   (write the DB password to that file first; the script shreds it). Create `/opt/ncm/server.env` with
   `OP77_DATABASE_CONNECTION=…` and `OP77_WARDEN_SETUP_LISTEN=http://127.0.0.1:11780`, mode 600.
3. `sudo systemctl start ncm-server`, open the tunnel, finish Warden onboarding at `http://127.0.0.1:11790`
   (game port 11778, public endpoint `52.60.225.137:11778`, unlisted, licence key from the DPAPI store).
4. `tools\deploy-staging.ps1` — applies `database.enabled=true` and `"ncm/*"` to `resources.load`, syncs, restarts.
5. Publish the current NCM-owned package set from release artifacts; do not restore deleted RB15/livery or
   obsolete loader declarations from historical backups.
