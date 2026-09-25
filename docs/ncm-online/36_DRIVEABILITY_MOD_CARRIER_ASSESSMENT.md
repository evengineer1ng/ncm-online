# 36 - the driveability-mod avenue: can a hosted mod widen vehicle control, and carry FFB natively?

> **STATUS: PROPOSAL** - capability assessment only. It authorises no mod, no carrier, no companion change,
> no Parts/Engineering work, no schema, no deployment and no Production change.
> **Revision 2, 2026-09-25** - see section 0 for what the owner rulings and the research pass changed.
> Authority map: [INDEX.md](INDEX.md) - classified 2026-09-24 (L125).

**Research date: 2026-09-25.** This report **extends** [33](33_PARTS_ENGINEERING_FINAL_RECONCILIATION.md),
[34](34_GATE6_INPUT_AUTHORITY_REQUIRED_MOD_AUDIT.md) and [35](35_REQUIREDMODS_FORENSIC_AUDIT.md). It does not
restart them and it reverses none of their conclusions. It answers one owner question raised once mods became
deliverable over HTTPS:

> *Can a hosted mod give us finer control over vehicular driveability than the three exposed fields — and can it
> carry our FFB natively instead of deriving feel from a thin telemetry snapshot?*

Owner reference point: [`natpoh/cp2077-wheel-mod-moza`](https://github.com/natpoh/cp2077-wheel-mod-moza)
("Direct Wheel"), read at commit-head on 2026-09-25.

---

## 0. Revision 2 - 2026-09-25, after owner rulings and existing-implementation research

This report was written before the owner completed the RequiredMods join and before the owner ruled on RB15
and on the §AR experiment. **Four things changed. The original text is amended in place rather than reissued,
and each change says what superseded what.**

| # | What changed | Where |
|---|---|---|
| 1 | **§AR is no longer needed, and is deferred by owner ruling (L143).** The spawn-cached question was answered from existing shipping implementations instead. Surface B is **SPAWN-CACHED**, not UNPROVEN. | §4, rewritten |
| 2 | **The handling flat inventory is far wider than this report first described.** `vehDriveModelData` carries brakes, grip/slip, suspension, weight transfer, mass and `engineMaxTorque`. Report 33 §6.4's BLOCKED list is a **platform-API** limit, never an engine limit. | §3.3, §8, expanded |
| 3 | **Surface C is now the important unknown, and its structure is fully mapped.** The live `WheeledPhysics` instance holds a named per-instance copy of the record's handling fields. Writing them is still unproven; nothing found writes them. | §3.4, rewritten |
| 4 | **RB15 licensing is no longer "terms not established."** The owner has ruled that NCM ceases public redistribution pending permission (L142). | §7, rewritten |

Unchanged and reaffirmed: Surface A, the multiplayer-integrity analysis in §5, the FFB migration order in §6.4,
and every naming rule inherited from Report 34 §8.

**Research method note, now a standing rule (L143).** Everything in this revision came from reading shipping
mods, their installers and a maintained SDK. No owner session, no environment change, no single-player probe.
Before proposing an experiment, exhaust existing implementation evidence first.

---

## 1. Answer first

**Yes to both, and the "yes" is much bigger than expected — but every part of it is demonstrated in
single-player Cyberpunk 2.31 by a third party, and not one line of it has ever run under OPEN//77.** That gap is
the whole risk of this report. Nothing below should be read as an OPEN//77 capability.

| # | Question | Short answer | Grade |
|---|---|---|---|
| 1 | Do executable roots work end-to-end? | Roots, classification and consent are DOCUMENTED and NCM's transport now passes §AP1. What additionally gates executables is **review (secured) or a permanent per-world `unsecured` flag plus a red badge and an unskippable named-package consent gate**. The funnel cost is real and lands exactly where KB-60 already bleeds testers. | DOCUMENTED |
| 2 | What widens control past the three fields? | Three surfaces. **(a)** `vehicle::BaseObject` final-command fields — per-instance, per-player, demonstrated. **(b)** TweakDB `vehDriveModelData` flats — the real handling surface and **much wider than the three fields**: brakes, grip, slip, suspension, weight transfer, mass and engine torque all exist — but **per-record, client-local and spawn-cached**. **(c)** the live `WheeledPhysics` instance, which holds a per-instance copy of (b) — readable, mapped, and the only path to genuinely per-machine handling. | DEMONSTRATED (a, b) / mapped-but-unwritten (c) |
| 3 | Spawn-cached or live? | **SPAWN-CACHED. Answered without an owner experiment.** Vehicle Physics Config states it as an engine limitation and builds its entire UX around resummon; Direct Wheel's contradicting CET module turns out to be **unshipped**; and the live `WheeledPhysics` instance is literally a per-instance copy of the record. Surface B is a **configuration-at-instantiation** carrier: it can express factory spec, Parts and setup, and it cannot express mid-stint wear or an expiring Chrome effect. | DOCUMENTED, triple-corroborated |
| 4 | Multiplayer integrity? | Worse than the existing carrier, structurally. The server's `getPerformance` reads **its own stored intent**, never the client's applied state, and `getVelocity`/`getSpeed` are *"the last thing the owner reported"*. There is no read-back analogue for handling and none can be constructed from the current API. The parts economy needs **INFLUENCE**, not AUTHORITY — and influence is already affordable. | DOCUMENTED |
| 5 | FFB? | The companion's **input** side becomes redundant; its **output policy** does not and must not. A native source is 250 Hz, in-process, against the engine's own fields — strictly better than the 30 Hz WebUI/WebSocket snapshot. It would supersede KB-106's units problem. **It must not be used as a reason to defer KB-106's measurement**, which is one drive with instrumentation that already ships. Direct Wheel is **a whole stack, not a telemetry source** — no shared memory, no UDP, no file, no IPC. | DEMONSTRATED / INFERRED |
| 6 | Licensing? | The entire loader and reference-mod chain is **MIT**, verified per repository. **RB15 is settled by owner ruling, not by research:** NCM has not established sufficient redistribution permission for the exact package it was hosting and will **cease public redistribution** pending permission or provenance resolution (L142). The NCM liveries are NCM-owned but are RB15 content and park with it. | DOCUMENTED + owner ruling |
| 7 | Downstream? | It unlocks **Brakes, Suspension, Steering, tyre/grip and above-native power as felt families at spawn** — Report 33 §6.4's BLOCKED list and 06_CHROME_ROSTER's "settled technical negatives" are now known to be **platform-API limits, not engine limits**. It does **not** unlock per-player differentiation on a shared model, and — question 3 having resolved spawn-cached — it does **not** make wear or an expiring Chrome effect felt mid-stint. Weather is the one place the per-record scope is semantically correct. | INFERRED |

**Recommended next action: none that requires the owner to change environments.** Question 3 is answered.
The one fact that would still change NCM's ceiling — whether the live `WheeledPhysics` handling fields can be
written per-instance — is a **code-reading and prototype question, not an owner-session question**, and §11
states exactly what is left of it. RB15's withdrawal is an owner ruling awaiting a safe operational slot in
Report 37's sequence.

### Evidence grades used here

| Grade | Meaning |
|---|---|
| **DEMONSTRATED** | Working code that does this exists and was read. The file is named. For third-party code this means *demonstrated in single-player Cyberpunk 2.31*, never under OPEN//77. |
| **DOCUMENTED** | Current official OPEN//77 or vendor documentation states it. Queried 2026-09-25. |
| **INFERRED** | Follows from DEMONSTRATED or DOCUMENTED facts by reasoning. No artifact does it. |
| **UNPROVEN** | No evidence either way is held here. |

---

## 2. Executable roots, end to end

### 2.1 What §AP1 actually proved, and what it did not

MASTER_TEST §AP1 is a **LIVE PASS for transport of INERT archives plus two executable loader blobs as bytes**.
It proved public HTTPS, exact sizes, exact SHA-256, ETag identity, Range behaviour and a coherent master row.
It proved nothing about consent, projection, loading or classification *behaviour*. The launcher has not yet
been asked to accept anything. **A transport PASS is not an in-game PASS** (NOW.md says this; it remains true).

Note the classification already relayed in the master row: ArchiveXL and TweakXL are **executable**; RB15 and
the NCM liveries are **inert**. So NCM is not standing at the executable threshold — **it is already carrying
two executable packages through the funnel it is about to test.** That is a material and previously
under-stated fact: §AP Case A is already an executable-delivery proof for the loader class, and if it passes,
the marginal step to a `.reds`/CET/RED4ext NCM package is smaller than Report 34 §5.1 assumed.

### 2.2 What additionally gates a `.reds` / CET / RED4ext root

**DOCUMENTED**, from the current mods guide and required-mods guide, queried 2026-09-25:

| Gate | What it is | Applies to an NCM control package |
|---|---|---|
| **Root** | Permitted roots include `r6/scripts`, `red4ext/plugins`, `bin/x64/plugins`, `bin/x64/plugins/cyber_engine_tweaks/mods`, `archive/pc/mod`, `r6/tweaks`, `engine/config`, `r6/input`, `r6/config`, `engine/tools`, `bin/x64`, `mods`. Out-of-root content is **rejected by the launcher**. | Not a gate. Every layer NCM might choose already has a legal root. |
| **Classification** | *"The most privileged file type determines the package's classification."* `.dll`/`.asi`/`.reds`/CET Lua/tooling ⇒ **executable**. | Automatic. A one-line `.reds` file makes the whole package executable. There is no "mostly inert" package. |
| **Hash attestation** | Packages pin exact `version`, `sha256`, `sizeBytes`. Current attestation replies for all four NCM hashes are `safety=unknown, redistribution=unknown` — **not blocked** (Report 35 §A). | Not a gate today. `unknown` is warned, not refused. |
| **Review status** | On a **secured** world an executable package needs a `verified` verdict for those **exact bytes**. Every changed release needs a new review. Approval throughput is explicitly unproven (Report 34 §5.1). | **The real gate** for a public secured NCM. A control extension that iterates weekly cannot live behind a per-byte review of unknown latency. |
| **`unsecured=true`** | Lifts the unreviewed-executable cap after consent. Documented as a **per-world, permanent property** set by `requiredMods.unsecured`. | The practical path — at a cost stated below. |

**One documentation conflict is preserved, not resolved.** The required-mods guide describes resource-owned
`preload_mod` as an inert path on secured worlds; the complete mod guide says an executable preload is accepted
when the world is unsecured **or** the hash is verified. Report 34 §5 already flagged this. Do not design
around secured executable `preload_mod` until the platform says which statement governs.

**A second tension, new here.** The mods guide calls `unsecured` a *"per-world, permanent property"*, yet
NCM's own operations have set and parked it repeatedly via `tools/staging/set-unsecured.py` and
`set-mods-off.py`. Either "permanent" describes the world's presented identity rather than an immutable
config bit, or the documentation is loose. **UNPROVEN.** It matters: if a world that has ever been unsecured
carries the badge permanently, then flipping it for a Development proof is free but flipping it on Online is a
one-way door. Establish this before Online is ever advertised unsecured beyond the current bounded proof.

### 2.3 What each gate costs the join funnel

This is the part that should worry the owner more than the technology, because **NCM already loses testers at
the connect wall** and KB-60 is the proof: a visitor connected, appeared in chat, was visible to `ncm.where`
with a position, watched `appearance_failed` log 44 times over 11 minutes, said *"cant join the pvp"* and
*"shit looks promising though"*, and left. That is the funnel NCM is about to add steps to.

**DOCUMENTED** pre-connect and connect-time cost of an unsecured world:

1. **Server browser:** a **red `UNSECURED` badge** on the row and a red note in the detail pane. This is paid
   by every player who never clicks Connect, and it is paid before NCM gets to say anything.
2. **Unsecured warning dialog**, first, for worlds requiring executable packages.
3. **Mod consent gate** naming each required package individually with size, source and verdict —
   `verified` shows *"reviewed by Open77"*, unknown shows *"supplied by this world, not reviewed by Open77"*.
4. **An explicit confirmation that cannot be click-through:** *"A double-click cannot skip it, and the shell
   refuses a join that did not carry the confirmation."*
5. **Then** a download. NCM's current set is **48.4 MB** across four packages — ArchiveXL 1,037,774 +
   TweakXL 1,046,349 + RB15 38,537,004 + liveries 7,829,853 bytes. RB15 alone is 80% of that.
6. **Then** a projection, and **then** a game boot.

**INFERRED, and stated plainly because nobody else will:** for a first-time visitor this converts NCM from
"click a server, play" into "accept a red security warning, read a list of four unreviewed packages, confirm,
wait for 48 MB, launch". Each step is a place to leave. A returning player pays only the consent (cached blobs
are content-addressed and reused), so the cost is front-loaded onto exactly the population NCM is worst at
keeping.

**Three consequences worth ruling on separately:**

- **RB15 is 80% of the download and is not NCM's.** If required-mod delivery ever becomes the default join
  path, the cheapest funnel win is to stop making a 38 MB third-party vehicle mandatory for everyone.
- **A control extension is a small package.** A `.reds`/CET NCM extension is kilobytes. Its funnel cost is
  entirely in the *classification*, not the bytes — it turns the world unsecured (or review-bound), which is a
  step change, not an incremental one.
- **Fail-closed readiness must never become fail-closed driving.** Report 34 §5.2 already ruled this; it is
  restated because a mod-gated funnel makes the temptation stronger. Absence or version mismatch withholds
  sanctioned *readiness*; it must not zero anybody's steering at speed.

---

## 3. The narrowest mod that widens vehicle control

The owner's question presumes one surface. There are three, they behave completely differently, and
conflating them is the mistake this section exists to prevent.

### 3.1 First: OPEN//77's resource sandbox cannot reach any of them

**DOCUMENTED.** The current client vehicles API exposes 42 functions and exactly three performance fields —
`topSpeedKph`, `taperKph` (default 12, minimum 3) and `accelerationScale` (0 < x ≤ 1). *"No grip, brake,
suspension, steering, or handling fields are exposed."* TweakDB is referenced for vehicle model declarations
and `vehEngineData` gearing, but the API *"exposes no direct TweakDB manipulation APIs."* `ncm/core` is
explicitly pure Lua with *"no Game/TweakDB/MTE/os/io/require"* (01_ARCHITECTURE.md).

So Report 34 §4.3's verdict — **BLOCKED BY CURRENT PLATFORM** for an ordinary OPEN//77 resource — stands
without amendment. Everything below requires code **outside** the resource sandbox, which is precisely why it
requires a required-mod package, and why §2 comes first.

### 3.2 Surface A — the final vehicle command. Per-instance. Per-player. Demonstrated.

**DEMONSTRATED in single-player Cyberpunk 2.31** by Direct Wheel's RED4ext plugin
(`direct_wheel/src/vehicle_hook.{h,cpp}`, documented in its `ARCHITECTURE.md`):

```text
RED4ext detour on vehicle::BaseObject::UpdateVehicleCameraInput   (UniversalRelocBase::Resolve(501486464u))
  -> writes three floats on the vehicle struct, every tick
       0x264  throttle  0..1
       0x268  brake     0..1   (also drives reverse while stationary)
       0x278  steer     -1..+1, + = right
  -> merges with vanilla keyboard/gamepad input, max-magnitude wins
  -> native vehicle physics
```

The detour fires for **every** vehicle per tick; a cached `g_playerVehicle` pointer — set from redscript
mount/unmount wrappers — gates writes to the player's own car. The plugin's own note on why that gate exists is
the useful part: *"Without this gate, our writes would propagate to parked cars, AI traffic, and anything else
with active camera updates."*

**This is the exact interception point Report 34 §6 described as desired and could not locate.** It is
device-independent by construction (it sits after aggregation, and merges with keyboard/gamepad), per-instance,
per-player, and it is the narrowest surface in this report. Report 34 §6's escalation table should be read with
this correction: *"No repository or official API evidence yet proves which extension technology can own that
exact point"* is now answered for the **RED4ext/native** row. The REDscript/CET row remains unanswered.

**What it is not.** It is input authority, not physics. Everything in Report 34 §8's honesty table still
applies verbatim: a brake command cap is `brake_command_authority = 0.60`, never `native_brake_force = 60%`.
Surface A cannot express grip, and Report 34's ruling that presenting it as grip is **semantically dishonest**
is unchanged.

### 3.3 Surface B — TweakDB `vehDriveModelData`. Per-record. Client-local. Spawn-cached.

**DEMONSTRATED in single-player Cyberpunk 2.31** by Direct Wheel's CET companion
(`cet/direct_wheel_steering/init.lua`), which is ordinary CET Lua and needs no native code at all:

```lua
local vehStr = tostring(vehicle:GetRecordID())
local ref    = TweakDB:GetFlat(vehStr .. ".vehDriveModelData")   -- record -> drive model
TweakDB:SetFlat(ref .. ".maxWheelTurnDeg",          turn)
TweakDB:SetFlat(ref .. ".wheelTurnMaxAddPerSecond", addRate)
TweakDB:SetFlat(ref .. ".wheelTurnMaxSubPerSecond", subRate)
```

It caches the stock values on first encounter and restores them on dismount. Three flats are all that module
touches. **`vehDriveModelData` holds far more, and this is the correction that matters most to NCM.**

Per the RedModding wiki's `gamedataVehicleDriveModelData_Record` reference, and the flats Vehicle Physics
Config reads back live from TweakDB, the record carries at least:

| Domain | Flats |
|---|---|
| **Engine / power** | `engineMaxTorque`, `flyWheelMomentOfInertia`, `resistanceTorque`, `maxRPM`, `minRPM`, `gearChangeTime`, `gearChangeCooldown`, `wheelsResistanceRatio` |
| **Mass / balance** | `total_mass`, `chassis_mass`, `center_of_mass_offset`, `momentOfInertia`, `momentOfInertiaScale` |
| **Aerodynamics** | `airResistanceFactor`, plus the `driveHelpers` downforce set |
| **Steering** | `maxWheelTurnDeg`, `wheelTurnMaxAddPerSecond`, `wheelTurnMaxSubPerSecond`, `perfectSteeringFactor`, the `turnUpdate*` family |
| **Brakes** | `brakingFrictionFactor`, `handbrakeBrakingTorque`, `lowVelStoppingDeceleration` |
| **Suspension / body** | `antiSwaybarDampingScalor`, `bankBodyFBTanMultiplier`, `bankBodyLRTanMultiplier`, `turningRollFactor*`, `slopeTractionReduction*`, and per-wheel `springStiffness` through `wheelSetup` |
| **Tyres / grip** | `bodyFriction`, `slipAngleCurveScale`, `slipRatioCurveScale`, `wheelsFrictionMap`, and per-wheel `frictionMulLateral` / `frictionMulLongitudinal` through `wheelSetup` into `FrontPreset` / `BackPreset` |

**Read that against Report 33 §6.4.** It classifies grip, brakes, suspension and steering as **BLOCKED** with
the words *"those fields do not exist."* **That sentence is true of the OPEN//77 API and false of the engine.**
Every one of those families is a named flat on a documented record. The same correction applies to
06_CHROME_ROSTER's *"settled technical negatives"* list and to its finding 4, *"tyre sabotage is the only
handling lever that exists."* Neither document was wrong about what NCM can reach today; both stated a
**platform** limit in language that reads as an **engine** limit, and that framing has since shaped two design
documents. **Amend the framing, not the caution:** none of this is reachable from an OPEN//77 resource, and
Report 34 §4.3 stands unchanged.

One further consequence worth naming. `engineMaxTorque` and `total_mass` are real flats. `accelerationScale`
is capped at 1, so the existing carrier can only ever *withhold* power — Report 33 §6.4's point that positive
parts can only restore withheld headroom. **Surface B has no such ceiling.** A positive part could express a
genuine gain rather than the release of a reserve. At spawn, and per record.

The chain is `vehicle record -> vehDataPackage / vehDriveModelData -> handling flats`.

**State this plainly, because it is the answer to the owner's actual question and it is not the comfortable
one:**

> **Surface B is per-RECORD, not per-instance, and TweakDB is per-CLIENT.**

Consequences, **INFERRED** from that one fact:

- Writing a flat changes **every vehicle spawned from that record** on that client — the player's car, every
  other player's car *as this client simulates it*, and every AI traffic car of the same model.
- There is **no per-instance variant.** OPEN//77's own three fields have both scopes —
  `setPerformanceClass(record, profile)` is per-record and *"applies to every present and future vehicle
  spawned from one TweakDB record"*, while `setPerformance(id, profile)` overrides per instance. **The
  handling flats have no such pair.** The per-instance half of the API is exactly the half that does not exist
  for handling.
- Therefore **two players in the same model cannot have different handling through Surface B.** Two players in
  the same model with different *installed components* is the entire premise of 18_PARTS_ECOSYSTEM. Surface B
  cannot express it.
- The dismount-restore pattern Direct Wheel uses is single-player logic. In a shared world, "restore the stock
  value on dismount" restores it for every other car of that model this client is rendering, mid-race.

**The honest combination**, and it is not bad: Surface B for facts that are *true of the model* (a homologation
ruleset applied to a whole class in a sanctioned race, a weather-wide handling state), Surface A for facts that
are *true of the driver's machine* (this car's brakes, this car's wear). That split is not arbitrary — it falls
straight out of the scopes each surface actually has, and it is compatible with the L135 invariant without any
new vocabulary.

### 3.4 Surface C - the live physics instance. Fully mapped. Readable. Writing found nowhere.

**This is now the most important unknown in the report.** Research moved it from a footnote to the thing that
decides NCM's physical-expression ceiling.

**DEMONSTRATED readable** (`direct_wheel/src/vehicle_physics_ext.h`): `vehicleBaseObject.physics` gives
`WheeledPhysics` and `.physicsData` gives the base `Physics`, reached through offsets resolved at load from the
game's own `CClass::GetProperty` RTTI metadata, with hardcoded fallbacks logged when RTTI does not know a field.

**MAPPED, in a maintained public SDK.** `RED4ext/Scripting/Natives/vehiclePhysics.hpp` in the Let There Be
Flight SDK fork declares `vehicle::WheeledPhysics` as a plain struct of named floats. It is not a black box.
It is **a per-instance copy of the drive-model record**:

```cpp
struct WheeledPhysics : Physics {
    uint32_t numDriveWheels;  float frontBackWheelDistance;  float frontBackBias;  float turnRate;
    physics::VehiclePhysicsInsert2 insert2[4];    // "WheelRuntimeData" - per wheel, incl. dampedSpringForce
    float antiSwaybarDampingScalor;   float turningRollFactor;        // + the weak-contact family
    float maxWheelTurnDeg;  float wheelTurnMaxAddPerSecond;  float wheelTurnMaxSubPerSecond;
    // the whole turnUpdate* family, twelve floats
    float airResistanceFactor;          float brakingFrictionFactor;
    float lowVelStoppingDeceleration;   float handbrakeBrakingTorque;
    float forwardWeightTransferFactor;  float sideWeightTransferFactor;
    TweakDBID wheelsFrictionMap;
    float slipAngleCurveScale;   float slipAngleMinSpeedThreshold;
    float slipRatioCurveScale;   float slipRatioMinSpeedThreshold;
    float slopeTractionReductionBegin, slopeTractionReductionMax, slopeTractionReductionFactor;
    DynArray<uintptr_t> driveHelpers;
};                                                  // RED4EXT_ASSERT_SIZE(WheeledPhysics, 0xDE0)
```

Compare those names with the record's flats in §3.3. **They are the same names.** Brakes, grip, slip,
suspension damping, weight transfer and steering rates all exist per instance, on the live object, with
per-wheel runtime data beside them.

**So the architecture hypothesis is confirmed**, and it is exactly the chain §4 establishes:

```text
TweakDB vehDriveModelData  ->  vehicle spawn / physics construction
                           ->  values copied into this instantiated WheeledPhysics
                           ->  live behaviour reads the INSTANCE, never the record
```

**Writing it: found nowhere — and the shape of that absence is itself informative.**

| Evidence | READ/WRITE | RECORD/INSTANCE | Demonstrated where |
|---|---|---|---|
| Direct Wheel reads five `WheeledPhysics` fields to derive per-car FFB references | READ | INSTANCE | SP, shipped |
| LTBF reads `physicsData` velocity, angular velocity, centre of mass, inertia tensors | READ | INSTANCE | SP, shipped |
| LTBF **writes** `physicsData->unk1B0` via `EnableGravity(bool)`, exposed to scripts by RTTI expansion | **WRITE** | INSTANCE | SP, shipped - but one boolean on the base `Physics`, not a handling float |
| LTBF exposes `GetDampedSpringForce(wheelIndex)` out of `insert2[]` | READ | INSTANCE, per wheel | SP, shipped |
| LTBF's `ResetWheels()`, intended to call `vehicleUnkD10::Reset(physics->unkD10, numWheels)` | WRITE | INSTANCE | **present but COMMENTED OUT.** The one open-source attempt at a wheel-reinit path was never landed. |
| `WheeledPhysics::SetupInsert()`, a named engine function that populates the per-wheel inserts | - | INSTANCE | **NAMED in the SDK, called by no inspected mod.** The obvious candidate for re-applying a drive model to a live instance. |
| Any mod writing `brakingFrictionFactor`, `slipAngleCurveScale`, `maxWheelTurnDeg` or the friction map on a live instance | - | - | **NONE FOUND.** |

**Do not read "mechanically possible" as "safe".** These are plain struct fields, so a native plugin can store
to them. That says nothing about whether the engine re-reads them each tick, re-copies from the record and
overwrites, or maintains a derived invariant elsewhere that a raw write desynchronises. `insert2[]` being named
*WheelRuntimeData* is a direct warning that some of this is derived state rather than configuration. Every
offset above is also from a **1.52-1.61** map: Direct Wheel found `maxWheelTurnDeg` at `0x1A4` on 2.31 where
this header says `0xC10`. **The names carry forward. The offsets do not.**

**Classification: WRITE / INSTANCE / UNPROVEN** - but now precisely stated rather than vaguely open. The
question is no longer *"is there a per-instance surface"* (there is, and it is mapped field by field) but
*"does writing it hold, and for which fields"*.

---

## 4. Spawn-cached versus live - ANSWERED, without an owner experiment

**Verdict: SPAWN-CACHED.** Drive-model handling values are read into the instantiated physics object when the
vehicle loads, and a change to the record does not reach a vehicle that already exists. A fresh spawn reads
the new values.

Revision 1 of this report called it UNPROVEN and proposed §AR, an offline single-player probe, to settle it.
**That probe is no longer the way to answer this, and the owner has deferred it (L143).** Three independent
lines of existing evidence converge, and two of them are from shipping products whose entire user experience is
built around the answer.

### 4.1 The evidence

**(1) Vehicle Physics Config states the mechanism explicitly, and builds its product around it.**
A CET-overlay configurator exposing roughly 26 handling parameters per vehicle - mass, torque, suspension,
tyres, steering, braking - reading each slider's baseline live from TweakDB through the
`Vehicle -> vehDriveModelData -> wheelSetup -> FrontPreset / BackPreset` getter chain. Its documentation says:

> *"Spawned vehicles cache their physics when they load in. TweakDB changes update the database, but the car
> you're sitting in keeps its old values. A fresh spawn reads the new ones. **This is a game engine limitation,
> not a mod limitation.**"*

Its workflow is: open the overlay, pick a car, drag sliders, apply, **then resummon the vehicle so it drives
differently.** That is an author statement rather than a demonstration - but it is behavioural evidence too. No
author imposes a resummon step on every user of a tuning tool if a live write would have worked.

**(2) Direct Wheel's apparent contradiction dissolves: the contradicting module is not shipped.**
Revision 1 called this *"a conflict inside a single project"* - the CET module writes the flats every frame
while the README calls the same values *"(Requires game restart to apply)"*. Checking the installers settles
it:

- `deploy.ps1` copies **the DLL and six `.reds` files**. It does not reference `cet/`.
- `fomod/ModuleConfig.xml` contains **no CET or `cyber_engine_tweaks` entry at all**.

`cet/direct_wheel_steering/init.lua` is an **unshipped experiment left in the repository.** The shipped product
solves the same problem on the *input* side instead, with the `sqrt` pre-inverse of the game's quadratic
steering curve and a speed-sensitive boost. An abandoned TweakDB approach replaced by an input-side approach is
exactly the residue a failed live-write attempt leaves behind. The README's *"requires game restart"* is then
not a contradiction but the user-facing phrasing of the same cache: for a car you already own and are sitting
in, restarting is the instruction a user can actually follow.

**(3) The engine's own layout says so.** §3.4: the live `WheeledPhysics` instance carries its own named copies
of `maxWheelTurnDeg`, `brakingFrictionFactor`, `slipAngleCurveScale`, `antiSwaybarDampingScalor` and the rest.
A per-instance copy **is** a cache. Behaviour reads the instance; the record is only its source at construction.

### 4.2 The one counter-indication, recorded rather than resolved

The RedModding handling guide notes that these values can be changed *"live in game"* using **Whip Wizard**,
whose description claims stance and suspension adjustment *"both visually and functionally"* in *"real time"*.

**Do not treat that as refuting the above**, and do not treat it as confirmed either:

- *"Live in game"* plausibly means *through an in-game UI* rather than *with live effect* - the sentence appears
  in a guide about editing YAML by hand, where the contrast being drawn is tooling, not timing.
- Whip Wizard's headline features are stance, engine audio, lights and windows. Stance is visual.
- A tool can present a change as instant by despawning and respawning the vehicle underneath the player.

**Classification: ambiguous marketing language, not mechanism.** If Whip Wizard genuinely mutates live handling,
the interesting part is not that Surface B is live - it is that it has found a **Surface C** write path, which
is §3.4's open question. If that becomes worth chasing, read its source rather than its store page.

### 4.3 What spawn-cached means for NCM

Revision 1 named three possible outcomes. The middle one is the answer.

- **Surface B is a configuration-at-instantiation carrier.** It expresses what a machine *is* when it is brought
  out, and nothing that happens during a stint.
- **It can honestly carry:** factory vehicle specification, installed Parts, setup and gearing, model or
  class-wide ruleset limits, and weather-wide handling states where the per-record scope is semantically right.
- **It cannot honestly carry:** per-Machine wear that changes during a race, a Chrome effect that expires
  mid-stint, damage taken in the current session, or anything that must differ between two drivers of the
  same model. Those stay on `setPerformance` (which is live and per-instance but only three fields), stay
  NCM-simulated, or wait for Surface C.
- **20_WEAR_LIFECYCLE and 18_PARTS_ECOSYSTEM are unaffected as designs.** L135 already separates mechanical
  truth from host expression. What changes is only which carrier a given fact may honestly reach, and when.

**§AR's status:** superseded as the method, and deferred by the owner as an activity. It stays in MASTER_TEST
as a recorded, unrun row rather than being deleted, because a future session with a reason to confirm this
directly should find the design already written. It is not scheduled and it is not the next action.

---

## 5. Multiplayer integrity

CP2077 under OPEN//77 is client-simulated, and this section is where that stops being an abstraction.

### 5.1 What the server actually knows

**DOCUMENTED**, current server vehicles API:

- `getVelocity(id)` is *"linear velocity from last owner report"*, and *"a vehicle with no physics owner is not
  being simulated by anyone"* — losing the lease **zeroes** it. `getSpeed`/`getSpeedKph` are the same.
- `getPerformance(id)` returns the **server's own stored profile**, not the client's applied state.
- Authority is a lease: `owner(id)` gives `physicsOwner`/`authorityPlayerId`, `driver`, `steward`, `leaseMs`.
- The server API exposes **no** independent throttle/brake/steering getters (Report 34 §4.1, unchanged).

### 5.2 The quantified surface

**INFERRED** from the above:

| Property | Current `setPerformance` carrier | Client-applied handling (Surface A or B) |
|---|---|---|
| Where the value is decided | server | client |
| Where it is applied | client | client |
| Server read-back | `getPerformance` — **intent**, not compliance | **none exists, and none can be constructed** |
| What a modified client must do to cheat | ignore the applied ceiling | edit one float, or not load the package |
| What the server would observe | a car exceeding its published ceiling in reported telemetry | nothing distinguishable from being a better driver |
| Corroborating witness | other clients replicate the ceiling and see the same car | **none** — each client's TweakDB is its own |

**The key asymmetry, and it is not a matter of degree.** `getPerformance` being intent-only is *tolerable*
today because the profile is replicated: every observer's client applies the same ceiling to that car, so a
client that ignores its own ceiling desyncs visibly against every witness. **Surface B removes the witnesses.**
TweakDB is per-client, so a player who strengthens their own handling produces a car that *they* simulate as
faster through a corner and that *every other client* — position-fed from that player's owner reports — simply
renders where the owner says it is. There is nothing to disagree with. The desync is not a visual artifact; it
is the absence of any second opinion.

**Detection.** A read-back analogue for handling does not exist and cannot be built from the current API. What
*could* be built is statistical: NCM already sends dense position/speed samples to the server at 5 Hz in
batches of five (Report 34 §3.2). Cornering speed against a known radius, at a known ruleset, for a known
model, is a distribution. Outliers are findable. **That is anomaly detection over client-attested evidence,
not enforcement**, and Report 34's rule holds: it must never be described as anti-cheat. It is also expensive
and has a false-positive cost paid by good drivers.

### 5.3 INFLUENCE versus AUTHORITY — and what the parts economy actually needs

- **Server INFLUENCE:** the server decides a policy, publishes it, and a cooperative client applies it. Failure
  shows up as inconsistency, not as a rules violation. This is what `setPerformance` is; the docs say outright
  it is not anti-cheat.
- **Server AUTHORITY:** the server decides the outcome and no client can contradict it. OPEN//77 has this for
  the things the *server* owns — ownership, wallets, results, schedules, market state, `server_id`-keyed rows.
  It has it for **nothing** in the physics layer, because it simulates no physics.

**The parts economy needs INFLUENCE, and it already has enough of it.** This follows directly from
18_PARTS_ECOSYSTEM's own structure: a component is a persistent asset with an owner, an origin, a condition
and a history, and **every one of those facts is server-authoritative today**. What a part *feels like* is
presentation of a server-authoritative fact. Report 34 §11's ordering — mechanical truth first, carrier
second — is not a compromise here, it is the thing that makes the economy safe on a client-simulated game.

The honest boundary:

- A part's existence, provenance, ownership, transfer, wear and failure: **server authority. Uncheatable.**
- A part's felt effect: **client-applied influence. Cheatable, in the same way and to the same degree that
  every client-simulated racing game is cheatable.**
- **Never** make a server-authoritative outcome depend on a client-applied feel. A race result computed from
  client-reported trajectory already has this exposure; a handling carrier widens it. Sanctioned results
  should lean harder on server-owned facts, not on how fast a client says it went round a corner.

---

## 6. Force feedback

### 6.1 Direct Wheel is a whole stack, not a telemetry source

**DEMONSTRATED.** There is no shared memory, no UDP broadcast, no file export and no IPC anywhere in the
repository. It reads devices, computes FFB in-process at a 250 Hz pump, and writes to the wheel itself. Its
`.reds` side pushes RPM/radio/collision/surface events *inward* to its own DLL, not outward.

**So NCM cannot consume it. NCM could fork it** (see §7) **or learn from it.** Those are different projects
with very different costs, and only the second one is free.

Two generations exist in the repository and they disagree; note this before anyone reads one and plans from it:
`ARCHITECTURE.md` describes a **Logitech Steering Wheel SDK** design with a device table restricted to VID
`0x046D`; the README for **3.2.0** describes **DirectInput** with a device selector, axis mapping and explicit
Moza/Fanatec support. The README is the newer artifact. NCM's own companion is **SDL**, which is a third path
again.

### 6.2 Does the input side become redundant? Yes — and that is the larger prize

**INFERRED, and this is the finding the owner should weigh most heavily.** Surface A (§3.2) writes the final
throttle/brake/steer floats directly. If NCM ever owned that point, the entire ViGEm/virtual-Xbox-pad
translation layer stops being necessary — and with it:

- **KB-110** (stale non-zero virtual-pad value after a silent tick failure) stops existing, because there is no
  virtual pad to strand.
- **KB-111** (`--monitor` prints a nonexistent `raw` key; raw and transformed are not retained separately)
  becomes trivial, because both values exist in one process at one point.
- **Report 34 §7's bypass table collapses.** "Not running the companion", "using a second controller",
  "keyboard driving" and "alternative virtual devices" are all bypasses *of the companion*. A hook after
  aggregation has none of them, which is the same reason Direct Wheel's merge works for keyboard users.
- The 120 Hz Python loop, the SDL device opening, the pedal-rest calibration and the merge rules — the parts
  Report 34 §3.1 marks **PROVEN NOW** — become redundant rather than wrong.

### 6.3 What must be preserved, exactly

None of this is about the transport, and all of it survives a source change unaltered:

| Proven thing | Where it lives now | Why it survives |
|---|---|---|
| **Device classes and ceilings** — `{gear 0.24, belt 0.20, direct_drive 0.06, unknown 0.04}`, measured 2026-09-24 and corrected by ~60% from reasoned values | `CEILING` in the companion; mirrored from `ncm/core/driver/feedback.lua`, which is authoritative | These are facts about **hardware**, not about where the numbers came from. A native source changes neither. |
| **`clamp()` as the only exit** — L133: *"The protection is `CEILING` and the `clamp()` that enforces it"*, and a slider bounded by the same maximum is exactly as safe as rungs | `clamp(device_class, requested)` | This is the wrist-safety property. It must remain the single point where a magnitude leaves NCM, whatever computes the magnitude. |
| **Slew limiting** — `MAX_SLEW_PER_SECOND = 1.5`; *"a spike is what hurts, not a sustained level"*; an unreadable target **holds** rather than dropping to zero | `slew()` | Becomes **more** important at 250 Hz, not less. |
| **The mixer's channel weights and the engine-hum floor** | `Mixer.feed` | Tuned against feel. A better source improves the inputs, not the balance. |
| **The panel** — WHEEL/PEDALS, every knob a slider, the KB-105 drag/echo guards, the KB-107 connected-path fix, the MEASURED block | `ncm_world/web/panel.html`, gated by `tools/panel-render-check.js` | The panel talks to NCM state, not to a device. |
| **The rung as a shared unit** — L133: *"a T128, a G29, a G923 — and 'rung 4 was right' travels between them in a way 'about 60%' does not"* | rung index displayed beside magnitude | **This is the single most valuable thing in the FFB work** and it is pure vocabulary. Losing it in a migration would be the real regression. |

### 6.4 Migration path — three steps, and never two at once

1. **Keep `ncm/core/driver/feedback.lua` as the frame contract.** It is already the authority the companion
   mirrors. A native source becomes a *second producer of the same frame shape*, not a second feel model.
   Nothing about the mixer, the ceilings or the panel changes in this step.
2. **Swap the source, keep the sink.** Native mod reads engine physics → emits the existing frame → existing
   bridge → existing Python mixer → existing SDL haptics with the existing `CEILING`/`clamp()`/`slew()`.
   Everything that is proven stays proven, and exactly one thing is new. This is the step that supersedes
   KB-106 (see below).
3. **Only then** consider moving the device layer into the mod as well. That is a separate project with its
   own device-class evidence to re-earn — Direct Wheel's DirectInput/Logi-SDK path shares no device
   classification with NCM's SDL path, and NCM's ceilings were measured against SDL normalisation. **Do not
   assume they transfer.** Transport and device layer must not move in the same step.

### 6.5 It supersedes KB-106 — and must not be used to postpone it

**KB-106** exists because `suspensionLongitudinal`/`suspensionTransversal` are the only telemetry channels
never normalised — their units were never established — so `ROAD_SCALE` was introduced at **1.0**, which
reproduces current behaviour exactly, and the companion now records peak magnitude and non-trivial frequency
per channel (`Mixer._observe`), surfaced in the panel under **MEASURED** with a *too small to feel* marker
below 0.05.

A native source **would** supersede it: Surface C reads the engine's own `velocity`, `angularVelocity`,
`turnRate` and `slipAngleCurveScale` through RTTI-resolved offsets with known field identities. Units stop
being inferred from a snapshot and become readable from the build. Direct Wheel derives its per-car FFB
references from exactly these (*"turn rate → yaw reference, wheelbase → cruise speed and centering baseline"*).

**And that is precisely why this must be said:** KB-106 is closed by **one drive**, with instrumentation that
already ships, on hardware that already exists. The native path is a project of unknown length. KB-106's own
note is the argument — *"A divisor invented at a desk would be the same mistake IDEA-411 already caught: the
FFB ladder was fixed by measurement, not argument."* A native mod is a better desk. **Take the measurement
first.** It is also the only way to tell whether monki's *"Slip couldn't figure out the output"* was KB-103 or
a scaling fault, which the two are indistinguishable without.

### 6.6 Assessment of `natpoh/cp2077-wheel-mod-moza`

| Dimension | Finding | Grade |
|---|---|---|
| **Architecture** | RED4ext C++ plugin + six `.reds` files + an optional CET Lua module. 250 Hz pump thread. Hash-resolved detour on `UpdateVehicleCameraInput` (hash sourced from Let There Be Flight, maintained in RED4ext's address database). 28 global native functions registered in `PostRegisterTypes` for the `.reds` side. Settings via jackhumbert/mod_settings. | DEMONSTRATED |
| **Robustness posture, worth stealing** | Offsets resolved from the game's **own RTTI** at load, hardcoded fallbacks used only when RTTI is silent and **every fallback logged** so drift is noticed. A **200 ms watchdog** tears down all effects when the detour stops firing — *"without it the last set effect would persist and the wheel would lock up at the last commanded torque."* That watchdog is the exact shape of the fix KB-110 needs, arrived at independently. | DEMONSTRATED |
| **Fragility, equally worth noting** | If the RED4ext address database is behind the game build, **RED4ext terminates the process with a MessageBox at load — the game will not launch at all.** For a required world mod, that failure mode is a world that cannot be entered after any CDPR patch until a third party updates. Inner `WheeledPhysics` offsets already *"drifted for 2.31"* and were re-discovered by a scanner. | DOCUMENTED |
| **Licence** | **MIT**, `Copyright (c) 2026 Grant Perdue` — the same holder as the upstream it forks, `clevergrant/cp2077-wheel-mod`, which is also MIT (GitHub reports `NOASSERTION` there only because the notice has appended text). Forking is unambiguously permitted. | DOCUMENTED |
| **Telemetry source?** | **No.** No shared memory, UDP, file or IPC. | DEMONSTRATED |
| **Whole stack?** | **Yes**, and one NCM cannot adopt wholesale: its device layer is DirectInput/Logi-SDK, its settings layer is Mod Settings, its FFB model is its own, and none of it knows about NCM's device classes, ceilings, rung or panel. | INFERRED |

**Verdict: it is a proof of existence and a reference implementation, not a component.** Its value to NCM is
that it settles three questions that Report 34 could only mark PLAUSIBLE — the final-command hook exists and
where, the handling flats are reachable and how, and per-frame engine physics is readable and by what
mechanism. That is a large contribution and it cost one afternoon of reading. Adopting its code is a separate,
much larger decision that this report does not recommend either way.

### 6.7 The owner's product threshold, judged

The threshold is explicit:

> **If an OPEN//77-delivered NCM native package can eventually eliminate the separate GitHub companion — so a
> player joins NCM, accepts the RequiredMods package, and uses their wheel, pedals and FFB without installing
> a separate NCM executable — that migration is worth pursuing. If the final architecture still needs the
> companion, do not undertake a large hybrid rewrite merely to make part of the stack native.**

**Every technical precondition for the no-GitHub end state is now demonstrated — in single-player, by one
third-party mod.** Direct Wheel discovers wheel hardware, reads its axes independently of the game's bindings,
injects the final throttle/brake/steer command, reads richer engine physics than NCM's snapshot carries,
computes FFB in-process at 250 Hz, and drives real hardware. There is no missing capability in that list.

**What is not demonstrated is every OPEN//77-specific half of it**, and these are the real gaps:

| Gap | Status |
|---|---|
| An NCM executable package completing Connect → consent → projection → boot | **Now very close.** The owner's join proves that path for four packages including two executable loaders. An NCM `.reds`/CET/RED4ext package is the same pipeline with a different hash. |
| A secured public world accepting it | **Unresolved.** Exact-hash review per release, throughput unproven. Today's answer is the permanent per-world `unsecured` flag and its funnel cost (§2.3). |
| A native plugin coexisting with OPEN//77's own client hooks | **UNPROVEN and untested by anyone.** OPEN//77 already hooks the drive update for `setPerformance`. Two native consumers of the same vehicle update is a coexistence question nobody has asked. |
| RED4ext's address database lagging a CDPR patch | **DOCUMENTED hazard.** RED4ext terminates the process at load. For a *required* world mod that means **the world cannot be entered at all** until a third party updates — a failure mode NCM would be importing into its join funnel. |
| Device-class ceilings for a DirectInput/Logi-SDK path | **Must be re-earned.** NCM's ceilings were measured against SDL normalisation and do not transfer. |
| FFB safety properties in a new host | **Must be re-implemented, not assumed** — §6.3. |

**Assessment: the end state is credible and worth pursuing eventually, and it is not the next thing to
build.** The two gaps that would actually decide it — native coexistence with OPEN//77's own hooks, and
whether the review/unsecured cost is acceptable — are both cheap to investigate and neither needs a line of
code. Nothing here justifies a hybrid rewrite that leaves the companion in place; the companion exists, works
across real hardware, and is the canonical product (`ncm-wheel`, not `tools/ncm-wheel.py` — see Report 37 §8).

---

## 7. Licensing — per package

AGENTS.md is right that these are not interchangeable, and the result is better than feared.

| Package | Licence | Verified | May NCM redistribute as a required package? |
|---|---|---|---|
| **ArchiveXL** (psiberx) — currently hosted, executable, 1,037,774 B | **MIT** | GitHub licence API, 2026-09-25 | **Yes**, with the MIT notice preserved. NCM is doing this today. |
| **TweakXL** (psiberx) — currently hosted, executable, 1,046,349 B | **MIT** | GitHub licence API, 2026-09-25 | **Yes**, same terms. |
| **RED4ext** (WopsS) | **MIT** | GitHub licence API | Yes, if ever hosted. |
| **redscript** (jac3km4) | **MIT** | GitHub licence API | Yes, if ever hosted. |
| **Cyber Engine Tweaks** (yamashi/maximegmd) | **MIT** | GitHub licence API | Yes, if ever hosted. |
| **mod_settings** (jackhumbert) | **MIT** | GitHub licence API | Yes. Note Direct Wheel ships a **patched** build of it. |
| **Let There Be Flight** (jackhumbert) | **MIT** | GitHub licence API | Relevant because Direct Wheel's offsets and detour hash derive from it. MIT, so a fork is clean. |
| **Direct Wheel** / **cp2077-wheel-mod** | **MIT**, Grant Perdue | LICENSE read directly | Fork and redistribute with notice. |
| **Logitech Steering Wheel SDK** | Proprietary, vendor terms | LICENSE statement | **Not applicable to releases** — Direct Wheel states it is *"vendored under `gwheel/vendor/` for build purposes only; it is redistributed at runtime via the system-installed G HUB service, not bundled in releases."* A build-from-source would need to honour Logitech's terms. |
| **RB15 10.0.0** — hosted, inert, 38,537,004 B | **INSUFFICIENT PERMISSION ESTABLISHED** | owner ruling, L142 | **NO. Public redistribution ceases** pending permission or provenance resolution. See §7.1. |
| **NCM liveries 1.0.0** — hosted, inert, 7,829,853 B | NCM's own | — | Yes in principle, **but parked with RB15** — they are RB15 content and are meaningless without it. See §7.1. |
| **Official OPEN//77 Freeroam/Race source** | **noncommercial** (AGENTS.md) | — | Not interchangeable with the MIT devkit. Not a required-package question today — L131/L132 evicted them. |
| **OPEN//77 devkit** | **MIT** (AGENTS.md) | — | Separate from the above; do not conflate. |

### 7.1 RB15 — the owner ruling, and why the liveries go with it

Revision 1 said *"terms not established."* **That is no longer a sufficient description of the state.** The
operative position, ruled by the owner on 2026-09-25 and recorded as **L142**:

> **NCM has not established sufficient redistribution permission for the exact RB15 package it was hosting,
> and has therefore decided to cease public redistribution pending permission or provenance resolution.**

The provenance is genuinely mixed, which is why "unknown" was the wrong word in both directions. Earlier
licensing research found that the underlying model and model-derived portions appear to carry **CC BY 4.0**
provenance, while the Cyberpunk mod author's own implementation, configuration and the complete or modified
package carry **separate redistribution restrictions requiring permission**. A package can therefore be partly
permissively licensed and still not be NCM's to rehost. Permission will be sought and the question revisited.

**RB15 is currently NCM's only open-wheel vehicle candidate.** The owner has accepted that cost explicitly.
**Do not substitute another open-wheel mod**, and do not treat the gap as a reason to soften the ruling.

**The NCM liveries park with it, and this is a technical fact, not a legal one.** Per Report 35's destination
map the livery package is `archive/pc/mod/ncm_rb15_liveries.archive`, its `.archive.xl` descriptor, and
`r6/tweaks/ncm_rb15_liveries.yaml` — ArchiveXL and TweakXL content whose records extend the RB15 vehicle.
NCM owns those bytes outright. They are also **meaningless without the vehicle they livery**: projected alone
they would reference a vehicle record that does not exist on the client. Keeping them in the required set
after RB15 leaves would make every joiner download 7.8 MB to extend nothing. They come out together.

**Preserve, do not delete.** The blobs, the declarations, the hashes, the provenance manifest and the local
authoring sources all stay. This is a withdrawal from **public redistribution**, not a deletion of NCM's work.

The exact operational sequence, and the gate it is currently behind, are in Report 37 — not here.

### 7.2 The standing point this does not change

**NCM's own published permissions cut both ways.** NCM requires attribution and restricts reupload of its
original files (01_ARCHITECTURE.md). A world that asks players to accept *"supplied by this world, not reviewed
by Open77"* while itself rehosting someone else's work without permission is not a position NCM should be in,
whatever the legal exposure. The consent gate names each package **and its source** to the player — the owner
has now seen that screen personally, with all four packages marked **Not reviewed**. Whatever NCM puts on that
list, a player reads NCM's name beside it.

---

## 8. Downstream — what this would and would not unlock

Read this against the four documents that would consume it. None of them changes as a result of this report;
they are all SPEC or CURRENT and this is a PROPOSAL.

### 8.1 Parts ([18_PARTS_ECOSYSTEM](18_PARTS_ECOSYSTEM.md)) and wear ([20_WEAR_LIFECYCLE](20_WEAR_LIFECYCLE.md))

18_PARTS_ECOSYSTEM names nine families including **Brakes** (*"lines, fluid, individual pistons"*),
**Suspension** (*"bushings, ball joints"*) and **Steering** (*"column bearings, small linkage"*). Report 33
§6.4 marks every one of those **BLOCKED** — *"those fields do not exist"*.

**Correction first: *"those fields do not exist"* is false of the engine.** §3.3 lists `brakingFrictionFactor`,
`handbrakeBrakingTorque`, `antiSwaybarDampingScalor`, `springStiffness`, `frictionMulLateral`,
`frictionMulLongitudinal`, `slipAngleCurveScale`, `maxWheelTurnDeg`, `total_mass` and `engineMaxTorque` as
named flats on a documented record, mirrored field-for-field onto the live physics instance. Report 33 §6.4's
verdict remains correct **as a statement about the OPEN//77 API** and should be re-worded to say so. Nothing
about what NCM may build today changes; what changes is that the ceiling is a platform boundary, not physics.

**Would unlock, at spawn:** Brakes, Suspension, Steering and tyre/grip as families with a *felt* consequence
rather than a purely simulated one — through Surface B for facts true of the model, and command authority
(Surface A) for facts true of the driver's machine. It would also lift the `accelerationScale ≤ 1` asymmetry
that currently makes every positive part a restoration of withheld headroom: `engineMaxTorque` has no such
ceiling, so a genuine gain becomes expressible.

**Would not unlock:**

- **Per-player differentiation on a shared model** through Surface B (§3.3). Two drivers in the same car with
  different suspension cannot feel different through the flats. This is the single hardest constraint and it
  sits directly across the premise of a parts economy.
- **Wear or Chrome as a mid-stint felt thing.** §4 resolved: **spawn-cached**. Wear can change what a machine
  is when it comes out of the garage, and nothing after that. A component that degrades over a race distance,
  a brake that fades, a Chrome effect that expires at the chequered flag — none of those reach Surface B.
  They stay on `setPerformance` (live, per-instance, three fields), stay NCM-simulated, or wait for Surface C.
  20_WEAR_LIFECYCLE's model — *"there is no `vehicleHealth = 63%`"*, condition belongs to the physical
  component — is unaffected, because L135 already separates truth from expression. **The design does not
  depend on this. The feel does, and the feel now has a known shape: per-outing, not per-lap.**
- **Anything about the economy's integrity**, which is server-side and already safe (§5.3).

**Do not design Parts against this.** That instruction stands and this report does not soften it.

### 8.2 Chrome ([06_CHROME_ROSTER](06_CHROME_ROSTER.md))

06_CHROME_ROSTER's finding 4 is the one this report touches: *"Tyre sabotage is the only handling lever that
exists — steering, grip, traction and friction are settled negatives"*, and `breakTire` is *"the sole mechanism
NCM has that touches handling rather than power."*

**That statement is true of the OPEN//77 API and was never true of the engine**, and §3.3 now shows exactly
which flats it was ruling out. `wheelsFrictionMap`, `frictionMulLateral`, `slipAngleCurveScale` and
`brakingFrictionFactor` are all real. The settled-negatives list is a **platform** limit, not an **engine**
limit. That distinction should be recorded in 06_CHROME_ROSTER itself, because the roster's whole shape —
LIMITER as the reference hack, everything else orbiting power — was drawn around the stronger claim.

But the roster's design instinct survives intact, and the reason is §3.3, not squeamishness:

- **LIMITER stays the reference implementation.** It is per-instance, server-decided, replicated and reversible
  — everything a hostile effect needs. Surface B is none of those.
- **A per-record handling attack is not targetable.** Degrading grip for "the victim's Quadra" degrades it for
  every Quadra on that client, including the attacker's. This is a genuine technical reason to keep
  `> **BREAK OR DEGRADE THE MACHINE. DO NOT STEAL THE STEERING WHEEL.**` — the maxim now has a mechanism behind
  it rather than only an API absence.
- **TIRE SABOTAGE keeps its special status, and now for a sharper reason.** `breakTire` works through the
  engine's own tyre model **per-instance and live** — precisely the two properties Surface B lacks. It remains
  the only handling-domain effect NCM can currently aim at one car during a race. Its value went up, not down.
- **Spawn-cached also rules out most hostile uses anyway.** A Chrome effect that only takes hold the next time
  the victim's car spawns is not an attack.

### 8.3 Weather ([11_WEATHER](11_WEATHER.md))

11_WEATHER lists *"wet vehicle behavior"* and the *"dry/wet/mixed"* classification vocabulary as open, and
06_CHROME_ROSTER notes *"wet handling remains a separate ceilings approximation (IDEA-057)"*.

**This is Surface B's best fit in the whole report, and it is the one place the per-record scope is a feature
rather than a defect.** Weather is uniform within an environment scope (11_WEATHER's own rule: *"NCM must not
draw geographic radar, storm cells, regional rain"*). A wet-handling state that applies to **every car of every
model on every client at once** is exactly the semantics rain should have. Applying it per-record, on every
record, is a faithful expression of a world-state fact rather than a compromise.

**Would unlock:** rain that is felt as reduced grip rather than approximated as a lowered ceiling — replacing
IDEA-057's approximation with the real thing, and retiring a known semantic dishonesty (Report 34 §8:
presenting a throttle withdrawal as grip is **UNSUITABLE**).

**Would not unlock:** anything per-player. Nor does it remove the need for the weather state itself to stay
server-authoritative and replicated; a client that declines to apply the wet state simply has more grip than
everyone else, with no witness (§5.2).

---

## 9. What this report does not do

- It does not authorise a mod, a package, a hook, a carrier, a fork, a companion change or any experiment.
- It does not touch Production. Nothing was deployed, configured, restarted or changed. No server
  configuration was read except through the existing masked tooling.
- It does not design Parts, and it does not amend 18/20/06/11. Those remain SPEC/CURRENT and unmodified —
  though §8 names two sentences in 33 and 06 whose **framing** should be corrected when they are next touched.
- It does not reverse Report 34 §4.3 (the OPEN//77 **resource** sandbox is still BLOCKED) or Report 34 §8 (the
  semantic-honesty table still governs naming). It **answers** Report 34 §6's open question for the native row
  and leaves the REDscript/CET row open.
- It does not schedule the RB15 withdrawal. That is an owner ruling (L142) and its safe operational slot is
  Report 37's, not this report's.

## 10. Owner decisions this needs

Recorded as **L138** (open) and **L139** (provisional) in [DECISION_RECORD.md](DECISION_RECORD.md); **L142**
and **L143** record the rulings already made.

1. **Does NCM become a mod-required world?** Not "can it" — §2 says it can, and the owner's completed join now
   proves the pipeline end-to-end to session entry. The open question is whether the red `UNSECURED` badge, the
   warning, the named-package consent gate and the download are a price worth paying for a funnel that already
   loses people at the connect wall (KB-60). **This is a product decision and it gates everything.** Note that
   RB15's withdrawal cuts the download by roughly 80%, which changes the arithmetic in NCM's favour.
2. **Does NCM take ownership of native code?** A RED4ext plugin means **the world cannot be entered at all**
   when the RED4ext address database lags a CDPR patch, plus ABI, crash, coexistence and review costs. A
   CET/REDscript layer is lighter and reaches Surface B, but has not been shown to reach Surface A or C.
3. **Does the companion remain the FFB device layer?** §6.4 says migrate the source before the sink, never both
   at once; §6.7 judges the no-GitHub end state credible but not next. The answer decides whether the canonical
   `ncm-wheel` repository is a long-lived product or a bridge.

**Superseded:** revision 1 closed this section by saying *"the §AR probe should happen regardless."* It should
not. §4 is answered, and L143 defers it.

---

## 11. Experiment residue — what, if anything, still needs us to run something

The owner's rule is: exhaust existing implementation evidence before asking for an experiment. Applying it,
here is everything this report once wanted to test, and what is left.

| Question | Status now | Needs an experiment? |
|---|---|---|
| Are drive-model handling values live, spawn-cached or restart-bound? | **Answered: spawn-cached** (§4), from two shipping mods and the engine's own struct layout | **No.** §AR is superseded and deferred. |
| Is the handling surface per-record or per-instance? | **Answered: the record is per-record; the live instance is per-instance** (§3.3, §3.4) | **No.** |
| Does a per-record write affect other cars of the same model? | **Answered by construction** — one record, every vehicle spawned from it | **No.** Revision 1's §AR5 was asking a question the documentation already answers. |
| Can the final vehicle command be intercepted per-player? | **Answered: yes** (§3.2), shipped code, named offsets | **No.** |
| Can native code read richer physics than OPEN//77's snapshot? | **Answered: yes** (§3.4), two independent mods | **No.** |
| **Can the live `WheeledPhysics` handling fields be WRITTEN, and does the write hold?** | **UNPROVEN. Nothing found writes them.** | **This is the residue.** See below. |
| Does a native plugin coexist with OPEN//77's own drive-update hook? | **UNPROVEN, and nobody has asked** | **Yes, eventually** — and it is OPEN//77-specific, so no third party can answer it for us. |
| What is `ROAD_SCALE`? | **KB-106, unmeasured** | **Yes — one drive, instrumentation already ships.** Unchanged and unaffected by any of this. |

### 11.1 The one genuine unknown, stated precisely

> **Can a native plugin write `brakingFrictionFactor`, `slipAngleCurveScale`, `maxWheelTurnDeg`,
> `antiSwaybarDampingScalor` or the per-wheel friction values on an already-spawned `WheeledPhysics` instance
> and have the change take effect and persist — or does the engine overwrite, ignore, or destabilise them?**

Why existing implementations cannot answer it:

- **Nothing writes them.** Direct Wheel reads five of these fields and writes none. LTBF writes exactly one
  live physics field (`EnableGravity`, a boolean on the base `Physics`) and its only wheel-reinit attempt,
  `ResetWheels()`, is **commented out in the shipped source**. Vehicle Physics Config deliberately does not go
  near the instance — its whole design is TweakDB plus resummon.
- **The absence is evidence of difficulty, not of impossibility.** Every one of these authors had the struct
  mapped, the offsets resolved and a native plugin already loaded. None of them took the step. That is worth
  weighing.
- **It is an NCM-specific question anyway**, because the answer NCM needs is *"does it hold under OPEN//77,
  with replication and a physics-owner lease"* — and no single-player mod can answer that half.

**What this is not:** it is not an owner single-player session, and this report does not ask for one. It is a
code-reading and, eventually, an isolated native-prototype question. The cheapest next increments, in order,
are: read Whip Wizard's source if it can be obtained (§4.2 — if it genuinely mutates live handling, it has
already found this path); search for any RED4ext plugin that calls `WheeledPhysics::SetupInsert()`; and only
then consider a throwaway native probe.

**Until it is answered, architect for spawn-cached.** Report 37 §10 and L139 both say the same thing in
different words: do not design around a capability that no working code has yet demonstrated.
