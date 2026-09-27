# NCM Carrier - next execution prompt and in-place Production upgrade

> **STATUS: CURRENT** - authority for: *the bounded Carrier follow-up and the in-place NCM Online Carrier-package upgrade* - affirmed 2026-09-25 (L146-L147).
> Product decisions remain in `DECISION_RECORD.md`; live truth remains
> in `wp/MASTER_TEST.md`.
> Authority map: [INDEX.md](INDEX.md) - added 2026-09-25 after Carrier 0.1.1's first successful cold launch.

This document is deliberately both a prompt and a runbook. Give the first section to the coder. The operator
section is the exact path used successfully for 0.1.1. Do not replace it with a manual DLL copy or a broad
resource deployment.

## Copy-paste execution prompt

You are continuing the existing NCM Carrier work in
`C:\Users\eveng\Documents\cyberpunk2077`. This is not a greenfield design and it is not permission to build
Parts. Work from repository evidence, preserve unrelated dirty changes, and complete the bounded proof below.

### Read first

Read these completely before editing:

1. `AGENTS.md`
2. `docs/ncm-online/NOW.md`
3. `docs/ncm-online/INDEX.md`
4. `docs/ncm-online/DECISION_RECORD.md`, especially L146-L147
5. `docs/ncm-online/KNOWN_BUGS.md`, especially KB-132-KB-136
6. `docs/ncm-online/wp/MASTER_TEST.md`, section AT
7. `docs/ncm-online/OPS_STAGING.md`, Required mods
8. `ncm/carrier/src/main.cpp`
9. `ncm/carrier/src/bridge/server.hpp` and `server.cpp`
10. `ncm/carrier/src/vehicle/hook.hpp` and `hook.cpp`
11. `ncm/online/resources/ncm_world/client/carrier_bridge.lua`
12. `ncm/online/resources/ncm_world/server/machine.lua`
13. `ncm/online/resources/ncm_world/shared/core/machine/projection.lua`
14. `tools/build-carrier.ps1`
15. `tools/staging/publish-carrier.py`, `check-load-list.py`, and `backup-production-state.sh`

### Established facts - do not rediscover or weaken them

- Production is `52.60.225.137`, server id `6b154fdc-d515-4903-97dd-df37cb966151`, whitelisted and unlisted.
- Production runs OPEN//77 `2.31.13+op77.102`, protocol 1.40.
- Carrier 0.1.1 is the sole required package. Current manifest digest:
  `e0ad7ec9091c2b23f69067addb318c3d9fe319fc5111eb0ff76c47949b1bbde2`.
- Current package: 868,295 bytes, SHA-256
  `6966a75d228cb70105f6201aaff4a2ab60ca6681ba78d65ad40acad4d2306301`.
- 0.1.0 was hosted, projected and loaded, then RED4ext script validation failed because runtime work happened
  in `Main(Load)`. Carrier 0.1.1 moved it to Running-state callbacks and live-passed a cold launch. KB-132 is
  closed. This also falsifies `.102` file/piracy verification as the direct cause.
- 0.1.1 cold-launch evidence: launcher digest present; RED4ext loaded the DLL; validation passed; Open77 reached
  active; Production recorded connected and NCM ready; `ncm_carrier.log` recorded bridge startup and NCM
  connection. AT1 is PASS.
- The server publishes 11 `GlobalState.ncmProjections` records, but the successful client produced no native
  `projection v1` receipt. That is KB-136 and remains open.
- `Server::sendDevice()` exists but has no caller, and no health sender exists. The client therefore sees only
  legacy `companion connected`, not `carrier 0.1.1 | hook=...`. That is KB-134.
- `installHook()` does not install a hook. It resolves or guesses offsets, sets a Boolean and logs “installed”;
  nothing calls `onVehicleTick()`. On the live `.102` build RTTI named none of the three fields, so all three
  hard-coded fallbacks were accepted. That is KB-135. Do not claim input authority.
- Development direct-IP joins do not receive a required-mod digest. Do not use loopback Development as the
  final hosted-package acceptance environment unless that platform limitation has independently changed.
- Database rows are a hard boundary. Code may temporarily diverge; no environment's database may be copied,
  replaced, reset or reconciled into the other.

### Objective

Produce the smallest next Carrier build, expected version 0.1.2, that makes the record-projection chain
observable and completes the typed Carrier handshake. Then replace the hosted Carrier package in place and run
the smallest empirical record-performance proof. Do not implement Parts, wear, Chrome gameplay, fabrication,
or real input authority in this build.

The chain under test is:

`server machine.projection -> GlobalState.ncmProjections -> client carrier_bridge.lua -> embedded bridge page`
`-> loopback WebSocket -> native Server::dispatch -> TweakStore::apply -> native receipt -> fresh vehicle`

Every arrow needs a receipt. Silence is not success.

### Required code work

#### 1. Complete the typed handshake - KB-134

- Add a native connection callback or retained outbound snapshot so every new WebSocket connection receives:
  - a `device` object describing the actually detected device and haptic availability;
  - a `health` object with Carrier version, honest input-hook state, applied-flat count and affected-record count.
- Emit the snapshot after the WebSocket handshake, not during `Main(Load)` and not before a client exists.
- Refresh health after every projection apply/restore and after relevant capability changes.
- Do not invent a wheel class or haptic capability. The first live run detected `Xbox 360 Controller`, class
  `unknown`, with no haptic effect available.
- Update `carrier_bridge.lua` wording only after the peer identifies itself. Before identity, “bridge connected”
  is accurate; “Carrier healthy” is not.
- Add focused tests for message shape if the carrier test harness supports them. At minimum, compile-time and
  deterministic serialization checks must cover both objects.

Acceptance receipt:

`[ncm_world/client/ffb] carrier 0.1.2 | hook=false | N flat(s) on M record(s)`

The exact hook value remains false in this build unless a real detour exists and has ticked. Do not fake it.

#### 2. Instrument and close the projection transport gap - KB-136

Add bounded, change-only diagnostics at these boundaries:

- server publication: record count, version, and a stable signature; the existing 11-record line may be extended;
- client read: distinguish absent `GlobalState.ncmProjections`, malformed state, and readable record count;
- client send: one line per changed record/signature, never at the 2 Hz poll rate when unchanged;
- embedded page relay: acknowledge projection receipt back to Lua or expose a bounded counter/error event;
- native dispatch: log record path, envelope version, flat count and restore flag before applying;
- native apply: existing applied/captured/refused counts, plus health refresh.

Do not paper over a missing nested GlobalState value. If the live client cannot read the 11-record map reliably,
replace this one transport with a targeted server-to-client event and retain GlobalState only as recovery. There
is precedent in `client/race.lua`: the entrant-targeted stream became primary after nested session state failed
live. Preserve late-join behavior by sending the current bounded projection snapshot when NCM reaches ready.

Do not ask the owner to compare handling until the native log contains a nonzero apply receipt.

#### 3. Make input authority honest - KB-135, containment only

Do not build the real detour in this change. Contain the false claim:

- An RTTI miss returns no offset; it must not silently select the 2.31 fallback in a runtime-independent plugin.
- `hookInstalled()` must remain false until a real detour is attached.
- Rename logs/status so offset discovery is not called installation.
- Leave `onVehicleTick()` unused and input command authority disabled.
- Keep record-flat projection and the loopback bridge independent of this refusal.

A later input-authority work packet must identify a build-pinned game-thread symbol, attach/detach a real detour,
observe at least one tick, prove the watchdog, and only then advertise `hook=true`. That is not this task.

#### 4. Preserve lifecycle safety

- RED4ext `Main(Load)` remains registration-only.
- Runtime construction stays in Running `OnEnter`.
- Teardown stays in Running `OnExit`, while game memory is valid.
- Every optional stage may decline without preventing the game from launching.
- `ncm_carrier.log` remains beside the DLL and is truncated once per process.

### Offline acceptance before hosting

1. Bump the project and RED4ext query versions together. Do not allow CMake/package version and `Query()` version
   to disagree.
2. Build Release with `tools/build-carrier.ps1`.
3. The ZIP must contain exactly:
   - `red4ext/plugins/ncm_carrier/ncm_carrier.dll`
   - `red4ext/plugins/ncm_carrier/SDL2.dll`
   - `red4ext/plugins/ncm_carrier/THIRD_PARTY_LICENSES.md`
4. Record ZIP path, byte size and full SHA-256.
5. Run the full repository gate. A green compile alone is insufficient.
6. Run `git diff --check`.
7. Inspect the diff. Preserve unrelated edits, especially
   `ncm/online/resources/ncm_world/server/main.lua` and shared ledgers.
8. Update KB-134-KB-136 and MASTER_TEST with what is actually built, not what is hoped.

### Live acceptance sequence

Use the in-place upgrade runbook below. Then:

1. Fully stop Cyberpunk. A warm reconnect cannot load a replaced native DLL.
2. Join NCM Online through its launcher catalogue row, never by raw address.
3. Confirm launcher digest equals the new public manifest digest.
4. Confirm RED4ext loads the new semantic version and script validation passes.
5. Confirm Production records connected then NCM ready for the existing driver.
6. Confirm typed handshake in both logs: version, honest `hook=false`, device and projection counters.
7. In Warden Live Console run `ncm.machine` and capture its current weather/record count.
8. Run `ncm.machine weather rain`.
9. Require, in order: server changed publication -> client read/send -> page relay -> native dispatch -> native apply
   with a nonzero applied count. If any receipt is absent, stop at that boundary and fix it.
10. Only after the nonzero native receipt, spawn a fresh NCM vehicle and have the owner compare lateral grip and
    braking. An already-spawned vehicle is not a valid test because record flats are spawn-cached.
11. Run `ncm.machine weather sunny`, require a corresponding restore/baseline receipt, then spawn fresh again.
12. Disconnect or quit and verify Carrier restores every captured original and logs the restoration count.

AT4 passes only when the calculation, wire envelope, native apply receipt and intended fresh-car behavior all
agree. Subjective feel without a receipt is not a pass; a receipt without the intended in-game change is not a
pass.

### Second proof: composition, not just mutation

After the single rain proof passes, prove two independent inputs without Parts:

- use two existing/test-fixture contributions owned by `machine.projection`, each with a distinct trace name;
- ensure both are composed server-side into one final envelope for one record;
- require the trace to name both contributors;
- require one native apply receipt for the final profile, not two competing writes;
- remove either input and prove only its contribution disappears while the other remains;
- restore both and confirm the captured original returns.

Do not introduce a second writer and do not implement Parts merely to manufacture a second input. If no safe
existing pair can produce two record-flat contributions, add an explicitly test-only fixture behind an operator
command and remove/disable it after the experiment. The point is to prove one owner composes; it is not gameplay.

### Stop conditions

- Stop if any command would overwrite or copy a database.
- Stop if Production and local package hashes disagree.
- Stop if the package root is not exactly `red4ext/plugins` or contains unexpected files.
- Stop if the load-list guard fails.
- Stop if another package appears in RequiredMods.
- Stop if server restart produces a pending migration or boot error.
- Stop if a cold launch lacks the new digest/version.
- Stop at the first missing projection receipt; do not compensate with subjective driving.
- Do not manually copy or delete files in the game's `red4ext/plugins/ncm_carrier` directory. The launcher owns
  projection and removal.

### Required handoff

Return:

- files changed and why;
- tests run and exact result;
- ZIP name, size and SHA-256;
- Production backup path and hashes;
- old and new manifest digests;
- public full-download hash and Range result;
- cold-launch launcher, RED4ext, client, carrier and server receipts;
- AT rows advanced, with PASS/PARTIAL/FAIL stated honestly;
- exact rollback state;
- remaining gaps, especially any unproven input authority or per-player record constraint.

Do not say “Carrier works” without naming which of delivery, startup, handshake, projection, restoration, feel,
composition, input authority and force feedback actually passed.

## Operator runbook - upgrade the hosted Carrier in place

Run from PowerShell in `C:\Users\eveng\Documents\cyberpunk2077`. Substitute the new semantic version and the
hash printed by the build. Commands intentionally separate upload, declaration, preflight and restart so a
failure cannot silently roll into the next step.

### A. Local build and package receipt

1. Bump both version sites:
   - `ncm/carrier/CMakeLists.txt`: `project(... VERSION X.Y.Z ...)`
   - `ncm/carrier/src/main.cpp`: `RED4EXT_V1_SEMVER(X, Y, Z)`
2. Build and package only:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build-carrier.ps1
```

3. Record the printed ZIP, bytes and SHA-256. Independently verify:

```powershell
$zip = '.\dist\ncm-carrier-X.Y.Z.zip'
Get-Item -LiteralPath $zip | Select-Object FullName,Length
Get-FileHash -LiteralPath $zip -Algorithm SHA256
tar.exe -tf $zip
```

Expected: exactly three files under `red4ext/plugins/ncm_carrier/`. `Compress-Archive` uses Windows separators;
`publish-carrier.py` normalizes them when classifying the package.

4. Run the repository gate:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\ncm-test.ps1
git diff --check
```

Do not publish a package merely because CMake succeeded.

### B. Confirm the target and protect Production state

The target is explicitly NCM Online at `52.60.225.137`. Never infer it from a current terminal.

Upload and run a fresh protective snapshot:

```powershell
$key = 'C:\Users\eveng\.ssh\lightsail-ncm.pem'
$hostName = 'ubuntu@52.60.225.137'
scp -q -i $key .\tools\staging\backup-production-state.sh "${hostName}:/tmp/backup-production-state.sh"
ssh -i $key $hostName "bash /tmp/backup-production-state.sh"
```

Record `BACKUP=...`, both hashes, both sizes, and the table count. The script does not print the database
password or row contents. A successful native-mod upgrade must apply zero database migrations.

Check the current service and recent player lifecycle before scheduling the restart:

```powershell
ssh -i $key $hostName "systemctl is-active ncm-server; grep -E 'connected:|disconnected:' /opt/ncm/logs/server.log | tail -n 12"
```

The world is whitelisted, but do not drop the owner mid-test. Coordinate the one restart.

### C. Upload the exact package and guarded publisher

```powershell
$version = 'X.Y.Z'
$zip = ".\dist\ncm-carrier-$version.zip"
scp -q -i $key $zip .\tools\staging\publish-carrier.py .\tools\staging\check-load-list.py "${hostName}:/tmp/"
```

No broad `deploy-staging.ps1` is required for a Carrier-only change. That script replaces the entire NCM resource
tree and may carry unrelated coder work. Use it only when the intended release explicitly includes resources.

### D. Replace the declaration and blob - no restart yet

```powershell
ssh -i $key $hostName "sudo python3 /tmp/publish-carrier.py /opt/ncm/server --zip /tmp/ncm-carrier-$version.zip --version $version --import-blob --enable --drop archivexl --drop tweakxl --note 'NCM Carrier X.Y.Z - projection proof'"
```

Expected publisher output:

- server root `/opt/ncm/server`;
- the local ZIP's full SHA-256 and byte count;
- exactly 3 files;
- root `red4ext/plugins`;
- older Carrier blob pruned;
- a timestamped `server.jsonc.bak-*`;
- declared package list exactly `ncm-carrier`.

Do not add `--drop ncm-carrier`; the publisher always replaces every prior Carrier declaration itself. Do not
put `capability` in `server.jsonc`; executable classification belongs in store metadata.

### E. Preflight before the running process is touched

Run the resource/dependency guard:

```powershell
ssh -i $key $hostName "python3 /tmp/check-load-list.py /opt/ncm/server"
```

Expected today: 41 resources, every dependency satisfied, and all four NCM resources named.

Verify the remote blob hash. Replace `FULL_SHA256` with the build receipt:

```powershell
ssh -i $key $hostName "sha256sum /opt/ncm/server/.open77/mods/FULL_SHA256.blob; python3 -m json.tool /opt/ncm/server/.open77/mods/FULL_SHA256.json"
```

Metadata must say id `ncm-carrier`, the new version, exact filename/hash/size, `fileCount: 3`, root
`red4ext/plugins`, capability `executable`.

### F. Activate with exactly one restart

```powershell
ssh -i $key $hostName "sudo systemctl restart ncm-server"
```

The current server often takes about 90 seconds to stop and may be SIGKILLed by systemd at its stop timeout.
Keep the first command attached. Do not issue a second restart merely because it is quiet.

After it returns:

```powershell
ssh -i $key $hostName "systemctl is-active ncm-server; grep -E 'migrations:|no pending migrations|Registered server|scheduler started|race control started|published 11|\[ERR\]|script error|resource start failed' /opt/ncm/logs/server.log | tail -n 40"
```

Required: active; `0 applied; pending=[]`; registered; five-series scheduler; race control; 11 machine records;
no new matching boot error.

### G. Verify public HTTPS bytes, not only server configuration

Read the new public manifest:

```powershell
curl.exe -fsS https://52-60-225-137.sslip.io:11779/mods/v1/manifest
```

It must declare one package, `ncm-carrier`, at the new version/hash/size and a new digest.

Verify the full public blob and Range behavior:

```powershell
$sha = 'FULL_SHA256'
$url = "https://52-60-225-137.sslip.io:11779/mods/v1/blobs/$sha"
$download = Join-Path $env:TEMP "ncm-carrier-$version-prod.zip"
curl.exe -fsS -o $download $url
Get-Item -LiteralPath $download | Select-Object Length
Get-FileHash -LiteralPath $download -Algorithm SHA256
curl.exe -fsS -D - -o NUL -H 'Range: bytes=0-63' $url
Remove-Item -LiteralPath $download -Force
```

Required: exact byte count/hash, HTTP 206, `Content-Range: bytes 0-63/<size>`, 64-byte body, and hash ETag.

### H. Client upgrade acceptance

1. Fully quit Cyberpunk. Confirm no `Cyberpunk2077.exe` remains.
2. Select NCM Online through the launcher catalogue row.
3. Accept the unsecured executable package if prompted.
4. Read `%LOCALAPPDATA%\Open77\launcher.log`:
   - new world digest;
   - NCM Carrier accepted;
   - projection/reconciliation summary;
   - a newly launched PID carrying the new digest.
5. Read `<game>\red4ext\logs\red4ext-<timestamp>.log`:
   - NCM Carrier new version loaded;
   - validation completes; no fatal dialog.
6. Read `<game>\red4ext\plugins\ncm_carrier\ncm_carrier.log`:
   - new version;
   - lifecycle registration;
   - bridge listening;
   - NCM connected;
   - typed health/device and later projection receipts.
7. Read `/opt/ncm/logs/server.log`:
   - connected;
   - existing identity/driver;
   - NCM ready.

A warm reconnect is not acceptance: an already-running process cannot load the replaced DLL.

### I. Emergency rollback

If the new Carrier prevents the game from launching, remove the requirement server-side; never hunt files in the
game install:

```powershell
ssh -i $key $hostName "sudo python3 /tmp/publish-carrier.py /opt/ncm/server --remove"
ssh -i $key $hostName "sudo systemctl restart ncm-server"
curl.exe -fsS https://52-60-225-137.sslip.io:11779/mods/v1/manifest
```

On the next cold catalogue join, the launcher removes the projected Carrier files. This is the safest fast
rollback because it follows the same ownership path that installed them.

To restore the last known-good 0.1.1 instead of removing Carrier, re-upload
`dist/ncm-carrier-0.1.1.zip` and repeat sections D-G with version `0.1.1`. Its known-good SHA-256 is
`6966a75d228cb70105f6201aaff4a2ab60ca6681ba78d65ad40acad4d2306301`.

If the server itself fails after the declaration edit, restore only the exact `server.jsonc.bak-<timestamp>` path
printed by the publisher, restart once, and inspect the boot log. Do not restore a whole server tree or any
database as a reflex.

## Why this procedure is intentionally strict

Previous failed attempts each skipped a different boundary:

- Development raw-address launch never received the mod digest even though the server manifest was correct.
- A non-loopback HTTP URL was invalid for Production; trusted HTTPS was required.
- Windows ZIP separators made a valid native package look rootless until normalized.
- The Production NCM resource symlink made a dependency guard falsely report NCM absent until links were followed.
- Client/server protocol drift blocked the join before mod behavior could be tested.
- A warm reconnect reached the server but proved nothing about native projection or loading.
- Carrier 0.1.0 loaded but initialized before RED4ext's safe lifecycle boundary and killed the game.
- Carrier 0.1.1 loads and connects, but that still does not prove projection, composition or input authority.

The runbook keeps each layer independently observable: build, package, store, declaration, load graph, restart,
public bytes, cold projection, RED4ext load, bridge handshake, native apply, fresh-car effect and restoration.
