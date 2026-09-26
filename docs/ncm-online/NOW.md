# NOW - the single next-action index

> **STATUS: LEDGER** - living session memory, rewritten at the end of every working session.
> Authority map: [INDEX.md](INDEX.md) - classified 2026-09-24 (L125).

Last rewritten: **2026-09-26 - a car was made to slide on command, live, on an already-spawned vehicle (`L148`, §AU).**

> **Claim before writing:** decisions through **L148**; MASTER_TEST through **§AU**; next QA letter **§AV**.
> BACKLOG next free **IDEA-503**; known issues through **KB-140** plus pre-existing duplicate labels noted by
> `KB-114`. Read the ledger tails before allocating an ID.

## One next action

**Fix `KB-136` -- the projection transport -- because it is now the only thing between a working grip lever
and rain that actually changes how a car drives.** The carrier can change lateral grip on a spawned car,
live and reversibly (`L148`, §AU5). `machine.projection` already computes wetness and publishes 11 records.
Not one has ever reached a client. Until that transport works, `gripScale` comes from a JSON file a human
edits, which is a capability and not a feature (`IDEA-502`).

The evidence gathered on 2026-09-25 narrows it sharply and is recorded in `KB-136`: in the same live
session, `GlobalState.ncmCalendar` (array-shaped) **was** read successfully by the client, while both
`GlobalState.ncmCeilings` and `GlobalState.ncmProjections` (maps keyed by record path) produced **total
silence** -- no log line from either branch of the loop. Class ceilings are therefore silently broken too,
which is a shipped feature nobody has noticed. Start by discriminating map-shape from payload size; the
`client/race.lua` precedent (an entrant-targeted stream replacing nested session state) is the fallback.

## Production live state

- Host `52.60.225.137`; server id `6b154fdc-d515-4903-97dd-df37cb966151`; unlisted and **whitelisted again**
  (`KB-137` closed: the tree was root-owned so Warden could not save; `chown -R ubuntu:ubuntu` plus a restore
  of `access.json` from the `.87` backup fixed it, and a successful Warden write confirmed it live).
- OPEN//77 `2.31.13+op77.102 linux-x64`, protocol **1.40**.
- RequiredMods enabled/unsecured; sole declaration `ncm-carrier` **0.1.9**, executable, 907,490 bytes,
  SHA-256 `e744a13fd504fdd826a1a5f479ecd7c1a4eaac5526680f762f7fc938d1fc3ac7`, digest
  `71ae63e217d1e8bb06d56a281e799f16b4c7bc89da61892c9e4ed24722d0acf6`.
- **0.1.10 is built and packaged but NOT published:** `dist/ncm-carrier-0.1.10.zip`, 908,510 bytes, SHA-256
  `0b3f1a8421ebd7d0dde3e659c2a21f0e05ac8c10c0b24ea6a1acbb432a6c6be6`. It adds the self-written default
  config (`IDEA-500`) and the `diagnostics` switch (`IDEA-501`). Publishing it needs one restart.
- Boot is clean: `0 applied; pending=[]`; schedulers/race control started; 11 machine records published.

> **Every carrier publish needs a `chown` afterwards (`KB-138`).** `publish-carrier.py` runs under `sudo` and
> writes the blob, its metadata and `server.jsonc` back as `root:root`, partially recreating what broke the
> whitelist. Run `sudo chown -R ubuntu:ubuntu /opt/ncm/server` after every publish and verify with
> `find /opt/ncm/server ! -user ubuntu`. This belongs in section D of the runbook and in the publisher itself.

## What changed this session - the carrier can now change physics

Carrier **0.1.2 through 0.1.9**, all proven live on Production with the owner driving. Full evidence in
MASTER_TEST **§AU**; the ruling that permits the write is `L148`.

- **The interception point.** `RigidBody::Recalculate`, RED4ext hash `593628708`, whose argument **is** the
  vehicle's `vehiclePhysicsData`. Recovered from the owner's March 2026 `ManualClutch` experiment and
  re-verified against this build's own address table. The hash is checked on disk **before** anything
  resolves it, because `UniversalRelocBase::Resolve` terminates the process on a miss and no `try`/`catch`
  can intercept that (`IDEA-494`).
- **`force` decoded.** Not a total: sixteen per-contributor writes per frame -- gravity once, four per-wheel
  normal loads, a traction pair, a drag pair -- expressed as impulses (`IDEA-495`).
- **The four corners identified:** `FL, FR, RR, RL`, a ring rather than row-major, from three independent
  manoeuvres across two cars. Resting residual against gravity: `-0.0` (`IDEA-496`).
- **Slot indexing refuted.** The callsite runs for one body from **twelve threads**. The thread guard caught
  it; without it, `modal=14 (17/82)` would have been reported as a real stability figure and a write designed
  on top of it. Replaced by stateless per-call classification, validated by arithmetic: `grav=60 wheel=240`,
  60 complete runs, `other=0`, repeatedly exact at 60 fps.
- **The first write.** Lateral grip scaled on the player's car only, hot-reloaded from config mid-session.
  At 0.30 the owner reported "unmistakable -- unrealistic, over the top understeer"; at 1.00, instant return
  to default physics. Writes cost no measurable frame rate (59.1 mean while writing, 55.6 while inert).
- **`KB-140`:** every DirectInput/HID device on the rig is held exclusively -- the G29, the Thrustmaster
  pedals and the ESP32 rim all refuse `CreateFile` even with zero access rights. Only the XInput pad is
  reachable. RawInput never opens a device and is the candidate route (`IDEA-497`).
- **`KB-139`:** `L"\ncm_..."` has now been written three times. All four wide path literals audited and
  correct. `config.cpp` carried it silently until 0.1.2, so the config file had **never once loaded** before
  this session.

## What §AU does not establish

- **No per-wheel friction.** The lateral channel is vehicle-level; the addressable per-corner values are
  normal loads, and scaling those makes a car sag rather than slide. Front/rear balance is out of reach
  through this channel (`IDEA-499`).
- **No connection to NCM.** See the next action above.
- **No input authority.** `KB-135` stands: no detour writes throttle, brake or steer, and `L148` explicitly
  does not authorise one. `vehicle/hook.cpp` still asks RTTI for `throttleInput`/`brakeInput`/`steerInput`,
  names that do not exist -- the SDK calls them `acceleration` and `deceleration`. Its log wording was made
  honest ("offsets resolved", not "installed"); the containment itself is still owed.

## Carrier proof status

- **AT0, AT1 PASS.** Delivery, native load, script validation, world connection.
- **AT2 PASS as of 0.1.2:** the typed health snapshot is sent on WebSocket connect and reaches NCM's own
  client log. `KB-134`'s connecting half is closed; typed fields rather than a version-string shim are owed.
- **AT3 not run.** `KB-140` means only the pad enumerates, so the panel has nothing real to draw.
- **AT4 still blocked by `KB-136`.** Note §AU sidesteps its spawn-cached premise entirely.
- **AU1-AU5 PASS.** See MASTER_TEST §AU.

## Data boundary and rollback

Unchanged (`L147`). Verified 63-table dump and operator-state archive at
`/opt/ncm/backups/pre-carrier-prod-20260925T213201Z`. The pre-upgrade `.87` tree is retained at
`/opt/ncm/backups/server-20260925T200746Z` and is where `access.json` was restored from.

Carrier rollback is one command and needs no file hunting:

```
ssh -i C:\Users\eveng\.ssh\lightsail-ncm.pem ubuntu@52.60.225.137 \
  'sudo python3 /tmp/publish-carrier.py /opt/ncm/server --remove && sudo systemctl restart ncm-server'
```

## Working-tree caution

The tree is intentionally dirty and contains overlapping work from another coder. Preserve unrelated
changes, especially `ncm/online/resources/ncm_world/server/main.lua`. This session touched only
`ncm/carrier/**` plus the ledgers. Do not reset or blanket-checkout.
