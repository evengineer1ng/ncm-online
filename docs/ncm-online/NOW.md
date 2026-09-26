# NOW - the single next-action index

> **STATUS: LEDGER** - living session memory, rewritten at the end of every working session.
> Authority map: [INDEX.md](INDEX.md) - classified 2026-09-24 (L125).

Last rewritten: **2026-09-26 - discovery of the physics surface closed with two clean negatives; Parts begins (`L149`, §AV).**

> **Claim before writing:** decisions through **L150**; MASTER_TEST through **§AV**; next QA letter **§AW**.
> BACKLOG next free **IDEA-508**; known issues through **KB-143** plus pre-existing duplicate labels noted by
> `KB-114`. Read the ledger tails before allocating an ID.

## One next action

**Fill the architecture profile from the running game with the carrier, rather than authoring 254 facts by
hand (`IDEA-507`).** Layers 1-3 of 18_PARTS_ECOSYSTEM are built (`IDEA-506`), and the resolver works - but it
knows only **124 of 378 (vehicle, facet) pairs, 33 percent**, because the rest live in `vehDriveModelData`
and only a running game can read TweakDB.

**The carrier already does that traversal.** `effects/tweak.cpp` resolves a vehicle record to its drive-model
record and reads float flats off it. A read-only enumeration over the 27 catalogue records, dumped to a file,
answers most of the profile from the game's own data instead of from anyone's memory of what a Galena is. It
needs **no write, no new decision line and no risk** - `L148` is not involved because nothing is mutated.

This is Parts consuming the carrier's ability to **read**, which is the more valuable half and was not the
half anybody expected to need first.

**Parts implementation is authorised but narrowly** (`L150`): the periodic table, the grammar and the
compatibility factory - all three now exist. **Not** R&D generation, manufacturing, supply, inventory, the
secondary market, barter or procedural naming; those stay SPEC and need their own authorisation when reached.

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
with the ordered checks and the seven assets we hold that Report 36 did not when it called this UNPROVEN.
**Check 0 ran the same day**, because the SDK header was already on disk and it cost one read:

- **`insert1` is real.** `physics::VehiclePhysicsInsert1 insert1[4]`, 300 bytes per wheel, `insert1Count` at
  `0x5C0`, `insert2[0]` asserted at `0x5E0`. The shorthand was right.
- **It is not on the object the carrier holds, and the original step 1 would have failed.** `insert1` lives on
  `WheeledPhysics`; our detour receives `vehiclePhysicsData`, and the header proves those are separate objects
  (`Physics` holds a `PhysicsData*` at `+0x60`; `Physics::sub_50` sets its velocity *from* the data object).
  **Revised step 1: get from `PhysicsData` to `WheeledPhysics` first**, and the verified `+0x180` back-pointer
  is the candidate route.
- **The configuration-versus-derived question is already answered in our favour.** Virtual slot `0x140`,
  `LoadSomeVehiclePhysicsStuff(Handle<VehicleDriveModelData_Record>*)`, is annotated *"populates some
  variables along with most of insert1"*. `insert1` is **fed from the drive-model record** - the signature of
  configuration, and the opposite of `insert2`'s *WheelRuntimeData*.

Two headers are worth reading before any code: `vehiclePhysicsInsert1.hpp` (it names the fields) and
`vehiclePhysicsData.hpp` (it should explain our own verified `+0x18`, `+0x180` and `+0x1BC`). Neither was on
disk. `IDEA-504` bookmarks the re-apply route and was amended the same day: `LoadSomeVehiclePhysicsStuff` is a
better candidate than `SetupInsert()`. **Neither is scheduled, and neither is safe to call yet.**

### Third-party vehicle hosting audit began

The first nine vehicle bases from the Collection install/test cohort now have exact-source licensing rows in
`docs/research/open77/NCM_SERVER_MOD_LICENSING_CATALOG.md`. **Zero are cleared for NCM-hosted delivery today.**
Seven have a plausible written-permission path; the yellingintothevoid R34 and Formula Drift Supra are off the
table today because their pages declare third-party assets and limit published add-ons to files that require
the original Nexus mod. FZR's base is an ASK, but its runnable chain stays red until Arch V4 is independently
cleared. The open-source loader layer remains separately hostable under its MIT notices. This continues
`IDEA-468`'s package-custody rule, does not change `L149`, and changed no package or server state.

## Parts - what exists

**Layers 1-3 of 18_PARTS_ECOSYSTEM are built**, 38 tests green under Lua 5.4 and LuaJIT.

### Compatibility, derived and never listed (`IDEA-506`)

- **`parts.architecture`** - fourteen mechanical facets over closed vocabularies, one profile per vehicle.
  **Every facet value carries a provenance**: `derived` (computed from the catalogue, true by construction),
  `authored` (**none yet**) or `unknown`.
- **`parts.compat`** - relates a component's constraints to a vehicle's architecture. **No fitment table
  exists anywhere**, which is what makes vehicle #83 a one-row change instead of a thousand-row edit. A test
  asserts it rather than a comment promising it.
- **Three outcomes, not a boolean:** `fits`, `mismatch` (a real, permanent no) and `unknown_facet` (*nobody
  has authored this yet*). Collapsing the last two would have produced a system that reports an empty world
  and looks like it is working.
- **Derived for free:** `axle_config`, `steering` and `platform` for all 27; the full motorcycle and Formula
  architectures. **27 vehicles collapse to 22 platforms** - the Type-66 and its Nomad, the Shion and its
  Nomad, the three Brennan Apollos and the two Yaiba Kusanagis each share one. `thorton_colby_pickup`
  deliberately does not collapse into `thorton_colby`.
- **Exact model fitment stays possible** through `fitsPlatforms`, in its own field so an audit can find every
  component that needed an exception.

### The periodic table (`L150`)

- **`parts.ontology`** (`ncm/core/parts/ontology.lua`, 17 tests green under both interpreters). The component
  periodic table: twelve families with meanings, subfamilies and what each abstracts away. It **reuses**
  `engineering.competency.FAMILIES` rather than declaring a second list of twelve, and refuses to load if the
  two ever disagree.
- **The four expression channels, asserted rather than described.** `record` (TweakDB flat - built, broad,
  but spawn-cached and shared across every instance of a model on a client), `instance` (the `L148` live grip
  write - built, personal, one quantity wide), `simulated` (always available, never felt), and `per_corner`
  (**declared absent**, with the refusal naming `IDEA-503`).
- **`declarationIsHonest(family, channel)`** is `IDEA-505` as an assertion: a Part cannot claim a channel its
  family does not have, and nothing can claim `per_corner`.
- **The constraint Parts must design around**, now a passing test rather than a paragraph: **tyres are the
  only family with a per-player felt expression.** Every other family that can be felt at all is felt through
  the record channel, where two drivers in the same car model cannot differ from each other.
- **Spec conflict 5 resolved:** a tyre asset is a **set of four**, not a corner and not an axle pair - partly
  because motorsport already works that way, and partly because §AV2 means per-corner identity would be
  identity without consequence. `axle_pair` and `corner` are named in the vocabulary as the migration steps
  if `IDEA-503` ever lands.

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
changes, especially `ncm/online/resources/ncm_world/server/main.lua`. The licensing pass added one OPEN//77
research catalog, linked it from the research README and updated this session memory; it did not touch runtime
code, packages or server state. Do not reset or blanket-checkout.
