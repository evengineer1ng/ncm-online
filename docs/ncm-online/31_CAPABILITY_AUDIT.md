# 31 — Capability audit: what the platform will actually tell us about a machine

> **STATUS: PROPOSAL** - a recommendation with **no authority until ruled on**. Covers: *what OPEN//77 and Cyberpunk expose or let NCM derive about a machine, classified before any observation vocabulary is frozen*
> Authority map: [INDEX.md](INDEX.md) - classified 2026-09-24 (L125)

**2026-09-24.** `IDEA-339`, the gate `28_MACHINE_KNOWLEDGE.md` §36 puts in front of the vocabulary:

> *"Perform a capability audit before freezing any vocabulary, classifying each candidate as DIRECTLY
> OBSERVABLE · DERIVABLE · DOCUMENTABLE/AUTHORABLE · SCANNER/ENGINEERING CANDIDATE · UNSUPPORTED. **The
> audit's job is to discover what falls into our lap.**"*

**Nothing built. No runtime, schema or behaviour changed.** This is read-only research against the published
API cards and against NCM's own working code.

---

## 1. Headline

**Three results, in order of how much they change the design.**

1. **Far more falls into our lap than §36 hoped.** The platform hands over throttle, brake, **steering input**,
   RPM, gear, wheel phase and **longitudinal and transversal suspension forces** — for *any streamed vehicle*,
   not only the one you are sitting in. Nearly every performance characteristic §36 names is reachable.
2. **The observation surface is split down the middle, and the halves do not overlap.** The authoritative
   server snapshot has the velocity vectors and no drivetrain; the client snapshot has the whole drivetrain
   and no velocity vectors. Neither side alone can answer "does this car understeer".
3. **There are no components to recognise. At all.** Not unimplemented — absent from the engine. That
   retires the observational half of the parts design outright, and tells us what `configuration_ref` must be.

## 2. Method, and what this audit is allowed to claim

Sources, in descending order of authority:

| Source | What it proves |
|---|---|
| Published API cards, queried this session via `query_open77.ps1` | the documented field lists and contracts |
| `docs/research/open77/evidence/2026-09-19/guide-vehicles-drivetrain.md` | how the drivetrain values get there, and at what rate |
| NCM's own running code (`client/telemetry.lua`, `server/telemetry.lua`) | what actually works today |

**A build gap that must not be glossed.** Every card below answers for **`2.31.13+op77.78`** — the service
says plainly *"no index published for 2.31.13+op77.84; serving 2.31.13+op77.78, the newest at or below it"*.
**Development and Online both run `.87`**, nine builds ahead. So the field lists here are a floor, not a
ceiling: a field may have been added since and no card would show it.

**The empirical check already exists and has never been run.** `client/telemetry.lua` logs the field names of
the first vehicle snapshot it reads, once per session, precisely as the E4/L57 record of *what this build
exposes*. `wp/MASTER_TEST.md` §103 asks for that line to be pasted in. **It never has been.** One line of a
client log, from the actual `.87` runtime, is worth more than every card in this document — and it costs a
race that is going to happen anyway.

## 3. The split surface — the fact the rest of the audit hangs on

Both lists below are complete, taken from the two `vehicles.get` cards.

| | **Server** `vehicles.get` (authoritative) | **Client** `vehicles.get` (streamed) |
|---|---|---|
| Position / heading / orientation | ✅ | ✅ |
| `speed`, `speedKph`, `onGround`, `reversing` | ✅ | ✅ |
| **`velocity` (vector)** | ✅ | ❌ |
| **`angularVelocity` (yaw rate)** | ✅ | ❌ |
| `moving`, `driverPlayerId` | ✅ | — (`occupants`, `physicsOwner`) |
| **`rpm`, `rpmMax`, `gear`** | ❌ | ✅ |
| **`throttle`, `brake`, `burnout`** | ❌ | ✅ |
| **`steering`** (−1..1, real input) | ❌ | ✅ |
| **`suspensionLongitudinal` / `suspensionTransversal`** | ❌ | ✅ |
| `wheelRotation` (wrapped radian phase) | ❌ | ✅ |
| Damage: 30-cell body grid, glass, lights, tires, detached parts, `health` | ✅ | ✅ |
| Performance ceiling, lifetime policy, authority state | ✅ | `physicsOwner`, `authorityEpoch`, `locallyOwned` |
| `record` (TweakDB identity) | via `getProperties` | ✅ |

The server list is exhaustive: **there is no `getRpm`, `getThrottle` or `getSteering` anywhere in the 138
server natives of `Open77.vehicles`.** That is a complete enumeration, not a failed search.

**The consequence.** Every characteristic that depends on driver input — power delivery, braking technique,
understeer↔oversteer, traction under throttle — is observable **only from a client**, and a client is not an
authority. Every characteristic that depends on the velocity vector is observable **only on the server**.
Understeer↔oversteer needs `steering` (client) *and* `angularVelocity` (server) in the same sample, so it is
the first characteristic in the spec that **cannot be measured by either side alone**.

## 4. The classification §36 asked for

**O** directly observable · **D** derivable · **A** documentable/authorable · **S** scanner/engineering
candidate · **X** unsupported. Several classes per row is expected and normal.

### Performance

| Characteristic | Class | Where it comes from, and what it costs |
|---|---|---|
| Speed, instantaneous | **O** | Both sides. Already sampled at 5 Hz by NCM. |
| Top speed, **rated** | **A** | `ratedTopSpeed(id)` — the record's own gearing figure, from `vehEngineData`. **Authored, not measured** (§5). |
| Top speed, **observed** | **O** | The running maximum of a sampled speed. This is the spec's worked example, and it is already in reach. |
| Acceleration, launch and interval | **D** | Δspeed/Δt. Honest at 5 Hz for a 0–100 interval; **not** for a launch transient. Needs the rate test in §8. |
| Braking, and braking distance | **D** | Δspeed/Δt, plus `brake` (client) to know a brake event happened rather than a lift. Distance integrates position. |
| Power delivery | **D** | Acceleration as a function of speed and `gear`, gated on `throttle` near 1. Needs client sampling. |
| Lateral acceleration | **D** | `speed × angularVelocity` (server), or the rotation of the `velocity` vector. Server-only and clean. |
| Yaw behaviour, stability | **O/D** | `angularVelocity` is measured directly; stability is its variance. Server-only. |
| **Understeer ↔ oversteer** | **D**, split | Needs `steering` (client) against `angularVelocity` (server). **The one characteristic no single side can measure.** |
| Traction, slip | **D** | Slip angle = angle between `velocity` and `heading` (server). Plus `burnout`, `onGround` and suspension forces (client). The drivetrain guide confirms the engine derives its own slip signal the same way. |
| Speed retention through corners | **D** | Minimum speed across a curvature window, from server samples alone. |
| Uphill / downhill performance | **D** | Pitch from the `orientation` quaternion, plus Δz. Both sides carry orientation. |
| Cornering, as a rated quality | **D** | A composite of the four rows above; not a primitive. Do not introduce it as one. |

### Non-performance

| Characteristic | Class | Finding |
|---|---|---|
| Identity of the model | **O** | `record` client-side, `getProperties.record` server-side. Works for modded records — §38 satisfied. |
| Manufacturer, model name, class | **A** | `Open77.data` answers `class`, `seats`, `manufacturer` — **badly**: it reports the MaiMai's manufacturer as `"Cs"`. NCM's own `META` table already authors this properly. **NCM's authoring is the better source and must stay the source.** |
| Paint, appearance variant, lights hue | **O** | `getProperties` / `getPaint` / `getAppearance`. This is the **entire** visual customisation surface. |
| **Identifiable configuration** | **X** → **A** | See §6. Nothing to read; NCM must author it. |
| **Visible modifications** | **X** → **A** | See §6. |
| **Component families / exact component recognition** | **X** → **A/S** | See §6. There are no components. |
| **Deviation from factory configuration** | **X** → **A** | Only meaningful against an NCM-authored factory spec, since the engine has no configuration to deviate from. |
| Condition — **damage** | **O** | 30-cell body grid, glass, lights, tires, detached parts, `health`, `drivable`. Rich, both sides, already replicated. |
| Condition — **wear** | **X** | `dirtLevel` and `fuelLevel` are both on the unsupported list. **There is no wear.** Any wear NCM wants is NCM's own bookkeeping — and the odometer is already exactly that. |
| Plate / number | **X** → **A** | `plateText` and `plateIndex` have no counterpart. NCM's car numbers (`IDEA-312`) are already authored, which is now confirmed as the only way they could have worked. |
| Who was driving, and whether it was an NPC | **O** | `vehicles.owner(id)` returns `driver`, `steward`, **`aiDriven`**, `epoch`, `reason`. Directly provenance-bearing. |

## 5. Three things that fall into our lap

**Steering input, which the card says should not exist.** *"REDengine 2.31 does not expose its live steering
input through RTTI, but Open77's audited 2.31 adapter reads the native lateral vehicle input at
`vehicleBaseObject+0x278`. The owner therefore transmits real keyboard/controller steering even while
stationary."* Someone did difficult work so that `steering` is a real number. Without it, the
understeer↔oversteer meter of §40 could not be honest at all.

**`ratedTopSpeed` is a published figure that is *provably not* the observed one.** The card is explicit: *"It
is **not** the measured terminal velocity, which torque and aerodynamic drag carry higher."* §37 demands that
authored knowledge never masquerade as observation. Here the platform hands us a number that is authored, is
useful, and **disagrees with the observed value in a known direction**. That is not an awkwardness — it is the
best possible teaching case for a two-source display, and a free consistency check on our own estimator: an
envelope whose floor sits below the rated figure while a driver has already exceeded it is visibly wrong.

**`aimed()` — the replicated vehicle the local player is looking at.** §9's scene is a player noticing a car.
`aimed()` is that gesture, already a native, with `nearby()` and `closest()` alongside it. The observation
trigger does not have to be invented.

## 6. The biggest result: there are no components

From the `getProperties` card, verbatim:

> *"Vehicle visual customisation on build 2.31 is one struct, `GenericTemplatePersistentData` — primary RGB,
> secondary RGB and a lights hue — plus the entity appearance variant. There are **no mod slots, no wheel
> types, no neon, no window tint and no numbered extras: not unimplemented, absent, with no RTTI type for any
> of them**."*

`unsupportedProperties` names them: `modEngine`, `modBrakes`, `modTransmission`, `modSuspension`, `modTurbo`,
`modArmour`, `mods`, `modKit`, `wheels`, `wheelType`, `wheelColor`, `windowTint`, `neonEnabled`, `livery`,
`extras`, `dirtLevel`, `fuelLevel`, `plateText`, `plateIndex`.

**A whole engine's worth of car customisation that every FiveM framework assumes is simply not there.**

Three consequences, and they are load-bearing:

1. **The parts system cannot read the engine.** Components, fitment, deviation from factory and component
   recognition are **not observation problems**. They are authoring problems. The scanner of §39 would be
   reading NCM's own records, not the game's.
2. **`configuration_ref` is settled.** Migration 028 reserved it, and §24 warned against inventing its meaning
   early. It is now decidable: **it can only ever be a reference to an NCM-authored configuration record.**
   There is no engine object for it to point at. It stays unwritten until that record exists, but its nature
   is no longer an open question.
3. **A machine's visible identity is: record + appearance variant + two RGB colours + a lights hue.** If two
   serialised machines are to look different, that is the whole palette. Worth knowing before liveries and
   team presentation are designed.

## 7. Four epistemic hazards that belong in the vocabulary, not in a comment

Each of these produces a *wrong* number rather than a missing one, which is the dangerous kind.

**A parked car reads zero, not unknown.** The server card: the motion half is *"all of it the last thing the
physics owner reported, and all of it **zeroed when the vehicle has no owner**, because nobody is simulating
it then"*, and `owner()` returns `physicsOwner = 0` when parked. **A sampler that does not check ownership
will faithfully persist `0 km/h` as an observation.** Every observation write must carry a live physics owner,
or refuse for want of one.

**A client-sourced observation is an attestation, not a measurement.** The drivetrain half only exists
client-side. The server does validate *the owner's* report — *"bucket, claim proximity, owner-to-vehicle
proximity, generation/epoch, monotonic tick, finite values, velocity/RPM/input/suspension bounds, travelled
distance"* — but that validates the **owner**, not an **observer** reporting on someone else's car. NCM
already has the pattern: `collection.lua` does bucket and distance checks on discovery. **Observed evidence
needs an epistemic class that distinguishes server-measured from observer-attested.** `EPISTEMIC` today is
`{ observed, published, ownership_verified }` — `observed` currently spans both, and should not.

**An NPC-driven car is not a driver's achievement.** `owner().aiDriven` is available and must be recorded.
Otherwise platform AI traffic contributes observations of machines nobody drove.

**Rated is not measured.** §5. If `ratedTopSpeed` is ever stored, it is `published`, never `observed`.

## 8. Test, do not assume — the experiments owed before anything is frozen

§37 says derivation is legitimate *"only if inputs and methodology support the meaning presented"*. Four cheap
tests, none of which needs new schema:

1. **Paste the `telemetry fields:` line** from a `.87` client. Closes the nine-build gap and settles §3
   empirically. *(MASTER_TEST §103 — already owed.)*
2. **Sampling rate.** NCM samples at 5 Hz; the platform's own observers run at 30 Hz. Measure the same launch
   at both rates and compare. **If a 5 Hz launch figure is not reproducible, acceleration is not derivable at
   that rate and must not be offered as though it were.**
3. **Read another player's car.** Confirm that a client `vehicles.get` on a *streamed but not locally owned*
   vehicle really returns live `rpm`/`throttle`/`steering` rather than zeroes. The whole observer half of the
   design depends on this one fact, and the card does not state it outright.
4. **Sample a parked car** and confirm it reads zero rather than nil. Proves the §7 hazard is real before it
   is designed around.

## 9. What this audit recommends freezing, and what it does not

**Safe to define now**, because every input is confirmed present, server-side and authoritative: observed
speed maximum · lateral acceleration · yaw rate and stability · slip angle · speed retention · gradient. All
six are computable from position, orientation, `velocity` and `angularVelocity` alone.

**Do not define yet**: acceleration and braking (pending test 2); power delivery and understeer↔oversteer
(pending test 3, and a decision about split-source sampling); anything about components.

**Do define now, because they are provenance rather than measurement**: the `aiDriven` flag, the
physics-owner requirement, and the split of `observed` into server-measured and observer-attested. These are
the facts that become unrecoverable if the first observations are written without them — the same argument
that made migrations 024 and 028 worth doing early.

## 10. Recommended order

1. **Run tests 1 and 4** — both are free, and both happen during a race that is happening anyway.
2. **Split `EPISTEMIC`**, and add the ownership / `aiDriven` provenance to `vehicle_knowledge_evidence`.
   Small, additive, and it is the irrecoverable part.
3. **Then the six safe characteristics**, as the first typed observation vocabulary, server-sampled.
4. **Then tests 2 and 3**, and only then the input-dependent characteristics.
5. **The estimator stays where §6 of [30_MACHINE_KNOWLEDGE_DEEP_DIVE.md](30_MACHINE_KNOWLEDGE_DEEP_DIVE.md)
   left it** — its own reviewed proposal.

**Components are not on this list, and that is the audit's answer rather than a deferral.**
