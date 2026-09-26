# NOW - the single next-action index

> **STATUS: LEDGER** - living session memory, rewritten at the end of every working session.
> Authority map: [INDEX.md](INDEX.md) - classified 2026-09-24 (L125).

Last rewritten: **2026-09-26 - discovery of the physics surface closed with two clean negatives; Parts begins (`L149`, §AV).**

> **Claim before writing:** decisions through **L149**; MASTER_TEST through **§AV**; next QA letter **§AW**.
> BACKLOG next free **IDEA-506**; known issues through **KB-143** plus pre-existing duplicate labels noted by
> `KB-114`. Read the ledger tails before allocating an ID.

## One next action

**Build Parts as the first consumer of the grip lever, and let Parts specify what it needs rather than
guessing further.** This is the owner's sequencing instruction and it is now a ruling (`L149`): three
experiments were authorised, all three ran, two came back negative, and the expected value of a fourth fell
below the value of connecting the one capability we have.

Start from `IDEA-505`, which is the rule that makes Parts shippable under uncertainty: **every Part declares
which of three channels its felt effect terminates in** - vehicle-level live (the proven `gripScale` write,
`L148`), NCM-simulated (server-authoritative, already safe, `IDEA-458`), or per-corner physical (does not
exist today and may never, `IDEA-503`). The composer must refuse to promise a felt effect on the third.

**Expect Parts to run straight into `KB-136` and treat that as the point.** `gripScale` still comes from a
JSON file a human edits (`IDEA-502`); nothing the server computes has ever reached the carrier. The first
Part that wants to be *felt* rather than *simulated* needs that transport, so the projection work is now
scheduled by a consumer instead of being argued for in the abstract. `KB-136` holds the evidence that
narrows it: in one live session `GlobalState.ncmCalendar` (array-shaped) was read successfully while both
`ncmCeilings` and `ncmProjections` (maps keyed by record path) produced total silence. Class ceilings are
therefore silently broken too, which is a shipped feature nobody has noticed. Discriminate map-shape from
payload size first; the `client/race.lua` precedent - an entrant-targeted stream replacing nested session
state - is the fallback.

## Production live state

Verified directly against the server on 2026-09-26, not carried forward from notes.

- Host `52.60.225.137`; server id `6b154fdc-d515-4903-97dd-df37cb966151`; unlisted and whitelisted
  (`KB-137` closed).
- OPEN//77 `2.31.13+op77.102 linux-x64`, protocol **1.40**. `ncm-server` **active**.
- RequiredMods enabled/unsecured; sole declaration `ncm-carrier` **0.1.13**, 914,065 bytes, SHA-256
  `4fa43a64dfbd52bd5429bb55ebd6e3eb65cc49d76a434412a2f7983f3a1eded4` - **re-read from
  `/opt/ncm/server/server.jsonc` and byte-identical to `dist/ncm-carrier-0.1.13.zip`.** Manifest digest at
  publish time was `0f82d831ef301bcd5acc7c2ab756443a2959704810624b6905a60077a954d7d6`; the manifest endpoint
  did not answer from loopback during this check, so that digest is publish-time observed rather than
  re-verified.
- **`KB-138` is currently satisfied:** `find /opt/ncm/server ! -user ubuntu` returns **0 files**. The `chown`
  after the last publish was done.

> **Every carrier publish still needs a `chown` afterwards (`KB-138`).** `publish-carrier.py` runs under
> `sudo` and writes the blob, its metadata and `server.jsonc` back as `root:root`, partially recreating what
> broke the whitelist. Run `sudo chown -R ubuntu:ubuntu /opt/ncm/server` after every publish and verify with
> `find /opt/ncm/server ! -user ubuntu`. This belongs in section D of the runbook and in the publisher itself.

## What changed this session

Two sessions' work sits here: §AU built the capability, §AV established its shape. **Read §AV before designing
anything physical.**

### The capability, unchanged and proven (§AU, `L148`)

Live, per-instance, reversible mutation of vehicle physics on an already-spawned car - no respawn, no record
edit, no TweakDB, no restart. Lateral grip scaled on the player's car only, hot-reloaded from config
mid-session; at 0.30 the owner reported *"unmistakable, over the top understeer"*, at 1.00 an instant return
to default physics. Interception at `RigidBody::Recalculate` (hash `593628708`), the force field decoded as
sixteen per-contributor impulse writes per frame, the four corners identified as **FL, FR, RR, RL**, and the
classifier validated by arithmetic across the twelve threads that drive one body.

### The shape, established tonight (§AV, `L149`) - two negatives

- **§AV2 NEGATIVE: the per-corner force entries are not a grip channel.** Shifting 20 percent of axle load,
  zero-sum, changed lateral capability by under 5 percent. Stated precisely: this rules out *this channel as
  a control surface*, not load-dependence in principle - the entries we scale may be suspension **output**
  rather than the tyre model's **input**. Either way, front/rear balance, brake bias, anti-roll, per-corner
  tyre temperature and downforce-as-grip are all unreachable this way. `IDEA-499` is refuted for this channel.
- **§AV3 REFUTED: there is no orientation quaternion in `+0x20..+0x180`.** Every unit-norm candidate is
  constant - inertia-tensor rows. No sideslip, no body-frame telemetry, no g-g diagram.
- **§AV1 PASS: the write itself was correct.** Residuals 16.08 / 16.19 / 8.90 against a ~180 N.s gravity
  impulse. It held vertical equilibrium exactly and did nothing, which is the cleanest possible form of a
  negative result.

### What that leaves, and where it is written down

`insert1` is now **the only credible route to per-corner grip**, and it is bookmarked in full at `IDEA-503`
with the ordered checks and, more usefully, the seven assets we hold now that Report 36 did not when it
called this UNPROVEN - a live pointer to the struct at 60 Hz, two verified landmarks inside it, a shipped
third-party write 12 bytes from one of them, proven corner identity to correlate against, an SEH harness, a
gravity-residual oracle, and a patch-day address pre-check. `IDEA-504` bookmarks the riskier alternative
(`SetupInsert()`). Neither is scheduled.

## Carrier proof status

- **AT0, AT1 PASS.** Delivery, native load, script validation, world connection.
- **AT2 PASS as of 0.1.2:** the typed health snapshot is sent on WebSocket connect and reaches NCM's own
  client log. `KB-134`'s connecting half is closed; typed fields rather than a version-string shim are owed.
- **AT3 not run.** `KB-140` means only the pad enumerates, so the panel has nothing real to draw.
- **AT4 still blocked by `KB-136`.** Note §AU sidesteps its spawn-cached premise entirely.
- **AU1-AU5 PASS.** See MASTER_TEST §AU.
- **AV1 PASS, AV2 NEGATIVE, AV3 REFUTED.** See MASTER_TEST §AV. A negative is a result, not a gap.

## Standing carrier constraints

- **No input authority.** `KB-135` stands: no detour writes throttle, brake or steer, and neither `L148` nor
  `L149` authorises one. `vehicle/hook.cpp` still asks RTTI for `throttleInput`/`brakeInput`/`steerInput`,
  names that do not exist - the SDK calls them `acceleration` and `deceleration`. Its log wording was made
  honest ("offsets resolved", not "installed"); the containment itself is still owed.
- **No per-wheel friction.** §AV2 above.
- **Only the XInput pad enumerates** (`KB-140`): the G29, the Thrustmaster pedals and the ESP32 rim are all
  held exclusively and refuse `CreateFile` even with zero access rights. RawInput is the candidate route
  (`IDEA-497`).
- **`L"\\ncm_..."` has been written three times** (`KB-139`). All four wide path literals are audited and
  correct; `IDEA-498` proposes a gate check so the fourth occurrence is refused rather than noticed.

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
