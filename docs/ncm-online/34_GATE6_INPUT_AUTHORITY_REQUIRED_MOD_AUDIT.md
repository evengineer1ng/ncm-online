# 34 - Gate 6 input authority and required-world-mod delivery audit

> **STATUS: PROPOSAL** - capability reconnaissance and bounded experiment design. It does not authorise a
> client extension, a required mod, a companion change, Parts/Engineering implementation, schema, deployment or
> Production test.
> Authority map: [INDEX.md](INDEX.md) - classified 2026-09-24 (L125).

**Research date: 2026-09-25.** This report extends the Gate 6 Chrome/setPerformance audit in
[Report 33](33_PARTS_ENGINEERING_FINAL_RECONCILIATION.md). It preserves both existing Gate 6 proofs. The
question here is whether NCM has, or could gain, an additional honest carrier between mechanical truth and the
native vehicle.

## 1. Answer first

There are three different answers.

1. **Can NCM modify a driver's command before the car consumes it?**
   **Yes in the existing local companion for inputs routed through that companion.** Its 120 Hz loop already
   normalises wheel/pedal/controller values, applies a steering curve, merges them and writes one virtual Xbox
   pad. A bounded brake/throttle/steering transform is a small Development experiment at that seam. It is not
   implemented now, and raw versus transformed values are not currently retained separately.
2. **Can an ordinary OPEN//77 `.87` resource do the same for every device?**
   **No demonstrated analogue replacement layer exists.** `.87` demonstrably exposes the resulting
   throttle/brake/steering state for reading. Current official APIs can also read physical XInput slot 0 and
   block curated actions or the whole gameplay stream. They expose no analogue injection, replacement or
   scaling API. `setControlLock` is a binary stationary-grid control; `setPerformance` is a special native
   throttle governor, not a general input writer.
3. **Could a common in-game NCM extension eventually do it for controller, keyboard and the companion's virtual
   pad?** **Plausible, but unproved and not presently enforceable as competitive anti-cheat.** The best candidate
   intercepts the final vehicle command after device aggregation, not each HID device. OPEN//77's current world
   mod model explicitly allows `.reds`, CET Lua and native/RED4ext plugin roots when the exact package hash is
   verified, or with conspicuous consent on an unsecured world. Report 35 has now explained NCM's old refusal
   as public-HTTP URL sanitation (`KB-112`), but no NCM package has yet completed the corrected HTTPS Connect ->
   projection -> boot -> in-game-content path.

The clean long-term player path, **if that pipeline passes**, is:

```text
Click Connect in OPEN//77
  -> launcher resolves the NCM world's exact required-mod digest
  -> player consents; launcher fetches, hashes and projects the exact NCM package
  -> game boots; REDengine/redscript/RED4ext loads it before the connection
  -> NCM resource and extension complete a version/capability/health handshake
  -> server admits the driver to sanctioned driving
```

That is the right architecture to investigate instead of sending every controller player to GitHub for an EXE.
It is **documented platform intent, not an NCM-proven delivery path**. A public secured NCM world would need an
exact-hash platform review for every executable release. The existing hardware companion can then remain an
optional adapter for non-XInput wheels, pedals and force feedback, while its virtual controller enters the same
game-side rules layer as an ordinary controller.

## 2. Evidence grades used here

| Label | Meaning in this report |
|---|---|
| **PROVEN NOW** | Present in inspected code and/or has a live `.87` observation. It does not imply anti-cheat. |
| **PLAUSIBLE - DEVELOPMENT PROOF REQUIRED** | The seam exists or platform policy permits it, but NCM has not run the physical/end-to-end proof. |
| **DEVELOPMENT-ONLY / NOT ENFORCEABLE** | Useful for feel and measurement, but another device/client can bypass it. |
| **BLOCKED BY CURRENT PLATFORM** | No adequate API, or the NCM delivery route currently refuses before install. |
| **UNSUITABLE / SEMANTICALLY DISHONEST** | It could produce a sensation but would falsely claim a different mechanical property. |

External evidence was rechecked against the current official
[required-mod guide](https://open2077.net/docs/server-mods),
[complete mod guide](https://open2077.net/docs/mods),
[key/input guide](https://open2077.net/docs/keybindings),
[input-blocking guide](https://open2077.net/docs/input-blocking), and
[vehicle guide](https://open2077.net/docs/vehicles). Current pages may describe a newer alpha than NCM's
`.87` server. Therefore `.87` claims below are limited to NCM's captured runtime evidence; current-doc-only
features remain documented candidates until a `.87` or upgraded Development runtime probe passes.

## 3. Exact current wheel/input path

### 3.1 Forward path

```text
physical wheel / separate pedals / SDL-recognised gamepad
  -> SDL2 joystick + GameController polling
  -> rig classification and pedal rest calibration
  -> normalisation
       steering: raw axis -> range scale -> clamp -> deadzone -> exponent curve
       pedals:   distance from learned rest -> 0..1
       gamepad:  XInput-shaped SDL map -> deadzone -> normalised axes/triggers
  -> merge
       steering: larger absolute deflection wins
       throttle/brake: maximum value wins
       buttons: union
  -> vgamepad / ViGEm `VX360Gamepad`
  -> one virtual Xbox 360 controller update
  -> Cyberpunk vehicle input
```

Repository anchors: `tools/ncm-wheel.py` `Input.open`, `_pedal`, `_steer`, `_gamepad_state`, `_tick`, `start`
and `stop`.

| Question | Exact finding | Classification |
|---|---|---|
| HID acquisition | SDL2 opens joystick devices and SDL GameControllers. It can recognise a steering device, separate or combined pedals, a profiled rim and one or more SDL gamepads. | **PROVEN NOW** |
| Pedal normalisation | Rest is sampled on startup. Travel becomes `abs(value-rest)/span`, clamped `0..1`. | **PROVEN NOW** |
| Steering normalisation | Raw `-1..1` is multiplied by the configurable physical-range scale, clamped, dead-zoned, then raised to `steer_curve` (default 1.3). | **PROVEN NOW** |
| Xbox output | `left_joystick_float`, left/right triggers and buttons are written to a ViGEm Xbox 360 pad, followed by `pad.update()`. | **PROVEN NOW** |
| Rate | The companion loop targets 120 Hz with `sleep(1/120)`. It is not a hard real-time schedule. | **PROVEN NOW** |
| Existing transformations | Steering range, clamping, deadzone and response curve are transformations already in production code. Gamepad deadzone and max/absolute merge are also transformations. | **PROVEN NOW** |
| Arbitrary bounded transforms | A pure `0..1 -> 0..cap` pedal function or `-1..1 -> bounded curve` can sit after merge and before the virtual-pad calls. | **PLAUSIBLE - DEVELOPMENT PROOF REQUIRED** |
| Raw versus transformed capture | Not available as distinct observables today. `_steer()` already returns the transformed value; `_tick()` stores only merged output in `self.last`. The monitor asks for a nonexistent `raw` key and prints its fallback zero. | **BLOCKED until the Development diagnostic records both** |

This is companion-based input translation, not native wheel support. A source comment currently calls it
"native rather than a companion hack" because the game sees an ordinary Xbox pad. That describes the game's
interface, not the delivery architecture; players still require the local Python/ViGEm/SDL companion.

### 3.2 Reverse telemetry/FFB path

```text
local client's streamed vehicle snapshot (`Open77.vehicles.get`)
  -> NCM `driver.feedback.frame`
       rpm/rpmMax, throttle, brake, steering, speed, gear,
       longitudinal/lateral/total slip, suspension axes, onGround
  -> hidden WebUI surface, 30 Hz, scoped to the occupied vehicle
  -> companion-served same-origin page
  -> loopback WebSocket
  -> Python `Mixer.feed`
  -> bounded/slew-limited SDL haptic effects
```

The source is a **client vehicle snapshot**. `.87` live evidence confirms every named input/drivetrain channel.
It is not a server-authoritative mechanical sensor. NCM's race telemetry separately sends dense position/speed
samples to the server at 5 Hz in batches of five; that slower path is not the FFB loop.

Rates relevant to a future loop:

| Path | Nominal rate | Authority / use |
|---|---:|---|
| Companion HID -> virtual pad | 120 Hz | Local physical inputs; optional companion |
| Vehicle snapshot -> FFB bridge | 30 Hz | Client-local/replicated snapshot; force feel and possible Development measurement |
| Driver-input HUD | 20 Hz while seated | Quantised presentation only |
| Race telemetry -> server | 5 Hz, batches of 5 | Client-attested race evidence, not a low-latency controller |

### 3.3 Failure, disconnect and stale-output behavior

- A normal `Input.stop()` resets and updates the virtual pad. The main `finally` calls it on ordinary shutdown.
- A dropped FFB WebSocket calls `Mixer.silence()`. Explicit idle frames slew force toward zero when the player
  is not seated. These protect **force output**, not driving input.
- The input loop is deliberately independent of NCM and telemetry. If the bridge disappears, the virtual pad
  continues to translate hardware. That is desirable for ordinary driving and means server loss cannot enforce
  a companion-side restriction.
- `_tick()` catches every exception and silently continues. If failure occurs after a non-zero virtual update,
  there is no input freshness watchdog to neutralise that previous value. `stop()` is safe when reached; the
  code does not prove that every thread/device failure reaches it. This is `KB-110` and must be corrected in any
  Development transform harness before a physical test.
- The companion has no HID-hiding/exclusive-input enforcement. A controller can be merged if the companion
  opens it, but the physical device is not removed from the game's view, and a player can simply not run the
  companion. Ordinary controller and keyboard paths therefore bypass companion-only mechanics.

## 4. OPEN//77 `.87` and current input/control surface

### 4.1 What `.87` has actually demonstrated

- The occupied/streamed vehicle snapshot exposes numeric `throttle`, `brake` and `steering`, plus RPM, gear,
  suspension and slip. These values drive the live NCM input HUD and FFB bridge.
- NCM uses keyboard reads (`isDown`) and keyboard-capture state (`isCaptured`) on `.87`.
- The server API does not expose independent throttle/brake/steering getters. The input/drivetrain half is a
  client snapshot and any submitted observation is client-attested.

This proves command **observation**. It does not prove command mutation.

### 4.2 What current official documentation adds

The current input guide documents direct physical reads for keyboard/mouse and XInput slot 0. Gamepad sticks
and triggers are readable, with deadzones removed and rescaled. It is explicit that these are physical-device
reads: they do not know Cyberpunk's bindings, in-game remapping or whether gameplay consumes the value.

The current blocking API is client-only and resource-owned. It can block a curated action or consume the whole
gameplay stream, with automatic claim release. The documented blockable vocabulary is oriented around movement,
menus and combat; it does not provide replacement throttle/brake/steering values. A server resource can request
that its client resource take the block, but the act remains client-side and is not anti-cheat.

The current vehicle guide is decisive: Cyberpunk 2.31 exposes **no writable input system** to the ordinary API.
OPEN//77's governor is a purpose-built native throttle withdrawal at the drive update. `setControlLock` can
consume zero acceleration and brake/reverse for a stationary car and later restore the snapshot; it cannot
scale an analogue command continuously.

### 4.3 Middle-layer verdict

| Candidate | Read | Block | Inject/replace analogue | Server decides policy | Sanctioned enforcement |
|---|---:|---:|---:|---:|---:|
| `.87` vehicle snapshot | yes | no | no | no | no |
| Current `Open77.input.axis` | documented physical XInput read; `.87` probe owed | no | no | no | no |
| Current input blocking | yes | yes, curated/all-or-nothing | no | can signal client | cooperative client only |
| `setControlLock` | n/a | zero drive input while locked/stationary | no continuous value | yes | same client trust boundary |
| `setPerformance` | reads profile/resulting telemetry | native throttle withdrawal | only its three-profile envelope | yes | replicated policy, client-applied; docs say not anti-cheat |
| Ordinary OPEN//77 resource transform | partial | partial | **no API found** | n/a | **BLOCKED BY CURRENT PLATFORM** |

There is therefore no ordinary resource architecture of `read raw axis -> compute value -> inject authorised
axis` today. Reading an axis and blocking the original still leaves no supported way to supply the replacement.

## 5. Required world mods: what the platform now says versus what NCM proved

The current official model is materially broader than the 2026-09-20 rationale behind L50/L71:

- World packages may place inert archives/configuration and executable `.reds`, CET Lua, `.dll`/`.asi` and
  RED4ext/native content in known roots.
- On a secured server, an exact executable package SHA-256 must be **verified**. Review attaches to those exact
  bytes; every changed release needs a new review, and approval throughput is explicitly unproven.
- An unsecured world may distribute unreviewed executable content after explicit warning/consent, but blocked
  hashes, hash mismatches, out-of-root content and non-indexed indexed IDs remain refused.
- Hosted packages pin exact `version`, `sha256` and size. Indexed dependencies express `minVersion`.
- Connect obtains the catalogue set/digest and master verdicts, asks for consent, fetches/hashes/projects the
  packages into a per-world profile, then boots the game. The Solo profile is separate.
- The launcher passes `OP77_WORLD_MODS_DIGEST`; the in-game shell compares it with the selected world's digest
  and relaunches through the launcher when they differ.
- A changed required set changes the digest after server restart. The next Connect derives the new world layer;
  content-addressed unchanged blobs are reused.

There is one current documentation conflict to preserve rather than resolve by preference. The required-mod
guide describes resource-owned `preload_mod` as an inert-package path on secured worlds and says executable
preloads are accepted in unsecured mode. The complete mod guide says an executable preload is allowed when the
world is unsecured **or the hash is verified**. Warden-hosted verified packages are unambiguously documented;
do not make secured executable `preload_mod` part of NCM's design until the platform clarifies which statement
governs.

### 5.1 Status matrix

| Capability | Status for NCM on 2026-09-25 | Evidence / limit |
|---|---|---|
| Server hosts manifest/blobs | **SUPPORTED AND WORKING TODAY** | NCM's public manifest returned HTTP 200 with correct hashes; `KB-8` proved transport was not the refusal point. |
| Required set prevents an unsatisfied join | **SUPPORTED AND WORKING TODAY** | NCM Connect was refused before game/server connection when verdicts were unsatisfied. Mandatory can include decline/refusal; it does not mean silent install. |
| Automatic inert world package install | **HIGH-CONFIDENCE AFTER ROOT-CAUSE RECOVERY; NCM LIVE PASS OWED** | Report 35 proves NCM advertised public HTTP and `.89`/current `.100` erased the URLs before download. HTTPS §AP remains not run. |
| REDscript/CET/RED4ext/native world package | **REQUIRES PLATFORM REVIEW/INDEXING** on a secured public world | Current policy explicitly permits executable roots only for a verified exact hash. This class is not prohibited. |
| Same executable on an unsecured Development world | **DOCUMENTED AND IMPLEMENTED; NCM LIVE PASS OWED** | Consent did lift the executable cap. The old refusal was the independent HTTP URL rule, not an attestation-policy contradiction. |
| ArchiveXL/TweakXL/CET loader dependency | **REQUIRES A REAL INDEX ENTRY OR VERIFIED/HOSTED PACKAGE** | Current docs call loaders indexed; NCM's observed signed index generation 61 lacked ArchiveXL/TweakXL and returned `NotInIndex`. Do not declare an index ID merely because the guide names it. |
| Exact package/version resolution | **DOCUMENTED; PARTIALLY OBSERVED** | Catalogue showed id/version/hash/size and a digest; no NCM successful projection/boot has proven the happy path. |
| Automatic update | **DOCUMENTED/INTENDED; NOT NCM-PROVEN** | New exact hash/version -> changed digest -> projection on next Connect. A verified executable update requires review of the new hash. |
| Server knows this boot's expected set | **DOCUMENTED AT WORLD/SHELL CONTRACT LEVEL** | Launcher context carries the installed digest and the shell checks equality. No inspected server resource API exposes a per-player runtime mod digest/attestation. |
| Mod actually initialised and stayed healthy | **UNKNOWN / NOT PROVIDED BY DIGEST ALONE** | Digest proves what the launcher prepared for boot. Official verification steps separately inspect loader logs and in-game behavior, which proves projection is not runtime health. |
| Strong anti-tamper/anti-cheat | **NOT SUPPORTED BY THE EVIDENCE** | Required bytes and a cooperative handshake catch ordinary absence/outdated/init failure. They do not prove an adversarial client executes or obeys the code after boot. |

The trust cap is policy, not an alpha accident: known roots, byte hashing, player consent and exact-hash review
for executable content on a secured public world are deliberate safety boundaries. Report 35 explains NCM's
old `Unverifiable`: public HTTP URLs were sanitized to null. Missing indexed loader IDs remain a separate index
fact; current official worlds demonstrate hosted loader resources over HTTPS.

`requiredMods.enabled=false` must remain parked until a controlled re-test says otherwise. Current docs strengthen
the eventual architecture; they do not close `KB-112`, §AP/R5, or L76.

### 5.2 Cleanest eventual click-Connect delivery

For an NCM-owned client extension:

1. Import the smallest client package through Warden with a stable package ID and exact version/hash. Package
   only the shallowest proven extension layer. A resource-owned preload may become the cleaner source layout,
   but the secured executable-preload documentation conflict above must be resolved first.
2. Declare loader dependencies only by IDs/versions actually present in the signed index, or package and review
   them under their redistribution terms.
3. For the public secured world, request review for the exact NCM executable hash and wait for `verified`.
   Private Development may use `unsecured` only after R5 proves the current launcher/master path actually accepts
   it.
4. Restart so the world digest changes. Player clicks Connect, accepts the named dependency, and the launcher
   resolves/projects/boots it automatically. No GitHub visit and no independent updater.
5. After boot, require a bounded extension handshake before sanctioned readiness: package/extension version,
   protocol version, supported carrier capabilities, world digest/revision, current driver/vehicle/authority
   epoch, heartbeat freshness and a server nonce.
6. Absence, version mismatch or init failure withholds sanctioned vehicle/race readiness and explains the fix.
   It must not suddenly zero steering/brakes at speed.

The handshake is a **compatibility/health gate**, not cryptographic proof against a modified client. The exact
platform questions still owed are:

> Does OPEN//77 bind each admitted connection to the launcher's installed `modsDigest`, expose that digest to
> server resources per player, and provide any attested runtime signal that a verified executable package
> initialised and remains loaded? If not, is such an admission/runtime-attestation API planned?

> For a secured world, may a resource-owned `preload_mod` contain executable files after that exact hash is
> verified, or must verified executable packages be declared/imported through Warden? Which signed-index IDs
> presently exist for ArchiveXL/TweakXL, and what lifecycle/status should Warden show for a pending hosted
> review? Separately, why do current guides show public HTTP hosting when the launcher rejects it?

## 6. Smallest common in-game control extension

The desired interception point is after keyboard/controller/virtual-pad aggregation and before the native
vehicle drive update consumes throttle, brake and steering:

```text
keyboard / ordinary controller / wheel companion's virtual XInput pad
  -> Cyberpunk device mapping and aggregation
  -> smallest NCM game-side command interceptor
  -> bounded effective vehicle command
  -> native vehicle physics
```

That location is device-independent by construction. It also keeps the wheel companion a hardware adapter,
not a different mechanical ruleset.

No repository or official API evidence yet proves which extension technology can own that exact point. Do not
choose native/RED4ext merely because it is most powerful:

| Escalation layer | Current verdict |
|---|---|
| OPEN//77 resource/API | Insufficient: read/block, no analogue replacement. |
| Lightweight REDscript or CET client extension | **PLAUSIBLE - DEVELOPMENT PROOF REQUIRED.** Prefer it if it can intercept the final command and exchange a versioned projection with the NCM resource. Existing generic mods prove deeper modification generally, not this exact multiplayer-safe hook. |
| RED4ext/native extension | **PLAUSIBLE, higher risk.** OPEN//77 itself demonstrates a native drive-update throttle hook is possible. Use only if the lighter layer cannot supply a stable downstream command hook/bridge. It adds ABI, crash, review and multiplayer-coexistence cost. |
| External companion for everyone | Technically easy for routed devices; **DEVELOPMENT-ONLY / NOT ENFORCEABLE** and poor universal UX. Retain for hardware/FFB. |

The first extension spike should therefore prove only three things: final-command interception for one axis,
a resource-to-extension policy/health bridge, and clean release through driver/vehicle/authority changes. It
should not build Parts or deeper physics.

## 7. Device coverage and bypass resistance

| Path | Wheel | Controller | Keyboard | Ordinary failure coverage | Adversarial bypass resistance |
|---|---:|---:|---:|---:|---:|
| Current companion | yes, when routed | only when opened/merged | no | weak; process optional, no input watchdog | none |
| OPEN//77 physical read/block APIs | virtual XInput only, not arbitrary HID | XInput slot 0 | keys/block stream | resource-owned release guards | cooperative client only |
| Game-side final-command extension | likely, after virtual pad | likely | likely | can fail closed at race admission if handshake exists | unknown; required bytes are not runtime attestation |
| setPerformance | device-independent throttle governor | yes | yes | replication/reapply across vehicle projection | explicitly not anti-cheat in current docs |

Bypasses to design for include: not running or modifying the companion; using a second/direct controller;
keyboard driving; alternative virtual devices; extension absent/outdated/failed; client script conflict; vehicle
ownership/authority epoch changes; resource reload; stale server policy; reconnect; and modification after the
launcher projected a correct hash.

Under P11's relaxed present-day threat model, an automatically installed extension plus fail-closed readiness
may be enough to create consistent stock-client behavior. It must never be described as competitive anti-cheat.

## 8. What input mediation can honestly express

| Mechanical idea | Honest input-mediated expression | Verdict |
|---|---|---|
| Brake authority / damaged brakes | Bound the maximum effective brake request. Native brakes then act on the reduced command. This is a real physical consequence of **command authority**, not changed native brake force or heat/fade. | **PLAUSIBLE - DEVELOPMENT PROOF REQUIRED**; best first proof. |
| Throttle authority / response | Static cap or monotonic response curve. This can express an electronic/command restriction, limp mode or control response. It overlaps the existing acceleration governor and needs one projection owner to avoid double reduction. | **PLAUSIBLE**, but use setPerformance where its meaning already fits. |
| Steering authority / response | Static bounded authority or response curve can represent a control-system limitation. It does not change steering geometry, tire forces or suspension. Accessibility and high-speed safety require care. | **DEVELOPMENT-ONLY first; proof required.** |
| Traction control | Read slip and withdraw throttle locally. Honest as an electronic driver aid/control policy. | **PLAUSIBLE but closed-loop proof required.** It is not increased tire grip. |
| ABS-like behavior | Modulate requested brake from slip/wheel evidence. Honest as an electronic brake-control aid if signals and rate suffice. | **PLAUSIBLE but substantially riskier than a static cap.** Not native brake hardware. |
| Brake fade | A slowly changing brake-authority envelope could be a proxy if NCM explicitly calls it input-mediated brake authority. | **Crude proxy.** Do not claim native temperature/friction fade. |
| Tire grip/friction | Reducing throttle or steering after slip does not change the tire-road coefficient. | **UNSUITABLE / SEMANTICALLY DISHONEST** if presented as grip. |
| Suspension | Steering/throttle transforms derived from suspension telemetry do not change springs, damping or geometry. | **UNSUITABLE / SEMANTICALLY DISHONEST** as suspension. |
| Gear ratios / above-native power | Input shaping cannot change ratios or add torque beyond native maximum. | **BLOCKED / DISHONEST**. Keep simulated or escalate to a real deeper carrier. |

Every UI/evidence name must preserve the distinction: `brake_command_authority = 0.60`, not
`native_brake_force = 60%`.

## 9. Telemetry-closed-loop feasibility and risk

The loop is technically possible in the companion for a Development prototype:

```text
120 Hz raw input -> bounded local command -> native physics
  -> approximately 30 Hz client snapshot -> local bridge -> next policy update
```

It should **not** put a server RPC in each control frame. Server authority supplies a slowly changing,
versioned envelope; a local carrier applies it at control rate. Server telemetry can validate sporting outcomes
and freshness, not stabilize a 120 Hz vehicle controller.

Risks:

- The 30 Hz bridge has WebUI/WebSocket/scheduler jitter and no measured end-to-end latency distribution.
- The snapshot may be buffered, extrapolated or stale; the current FFB frame omits packet-age/authority metadata.
- Feeding transformed steering/brake back into a controller can create gain, oscillation, chatter or driver
  compensation. A rate limiter also creates phase lag even without explicit feedback.
- A missing frame is not zero. Every dynamic policy needs a monotonic timestamp, freshness TTL, bounded slew and
  a defined stale transition.
- Fail-open makes a competitive bypass; abrupt fail-closed at speed is unsafe. The safe product response is to
  invalidate/withdraw sanctioned readiness, hold the last bounded policy only for a short grace if safe, and
  transition predictably - never snap steering or brakes.
- Server and local state need a vehicle ID plus authority epoch/revision so a late policy for the old car/owner
  cannot touch the next one.

Static non-amplifying envelopes are the first viable experiment. Dynamic steering feedback is not.

## 10. Smallest safe Development companion proof

### Proof A - brake command authority

No NCM server change, schema, Parts state, required mod or Production deployment is needed. The temporary local
companion experiment should be explicitly Development-only and stateless.

1. Add a test-only brake-cap option at the single post-merge/pre-ViGEm seam. Default exactly `1.00`; accept only
   finite `0..1`; never amplify.
2. Record, with monotonic timestamps: physical normalised pedal, merged request, cap, transformed virtual trigger,
   `pad.update` success, and last-success age. The existing monitor is insufficient (`KB-111`).
3. Add an input watchdog before driving: any tick/device exception neutralises the virtual pad, logs once and
   aborts the test. Normal exit resets the pad. This closes the known stale-value risk (`KB-110`).
4. Use one ordinary known vehicle, one flat straight, the same tire/damage/weather state and a repeatable 80
   km/h entry. Do three A/B/A runs: cap `1.00`, obvious cap `0.55`, restored `1.00`.
5. At the same timestamps capture the `.87` vehicle snapshot brake, speed and position. Measure entry speed,
   time to rest and integrated/marked stopping distance. The in-game/HUD brake indication should follow the
   transformed command rather than the raw pedal.
6. PASS requires: raw pedal reaches about 1.00 in both conditions; virtual/game brake is bounded near 0.55 only
   in B; B produces a materially longer stop; restored A returns to the baseline envelope; process stop/failure
   leaves no held trigger.

This proves only that input-mediated brake authority has a convincing/measurable consequence for inputs routed
through the companion. It does not prove native brake-force modification, device independence or enforcement.

### Proof B - steering, only after A

At less than 30 km/h in an empty open area, apply one static symmetric clamp such as `[-0.50, +0.50]`, with no
telemetry feedback. Log physical, transformed, HUD/snapshot and vehicle response; restore to `[-1,+1]`. Abort on
any asymmetric sign, stale tick or discontinuity. Do not test dynamic steering control in this pass.

Throttle is lower-value because Gate 6's existing governor already owns a documented throttle carrier. Test it
only if a later mechanical meaning cannot be expressed honestly by `accelerationScale`.

## 11. Relationship to the Gate 6 composer

The authoritative shape remains:

```text
NCM machine / component / condition truth
  -> one versioned projection calculation
       -> performance carrier owner
            topSpeedKph / accelerationScale / taperKph
       -> input-authority carrier owner (only separately proven honest dimensions)
            e.g. brake command cap
       -> deeper vehicle carrier owner (only when required and proven)
       -> simulation-only consequences
```

- Gate 6 Proof 1 and Proof 2 in `MASTER_TEST` section AN remain first and unchanged.
- One owner composes all influences for each carrier slot. Independent systems never write the same platform
  slot; removal recomputes the remaining inputs.
- Cross-carrier policy must also avoid double expression. If `accelerationScale` already expresses reduced
  pickup, a second throttle cap cannot silently express the same fact again.
- Mechanical identity, realised characteristics, wear and provenance never depend on today's carrier. Replacing
  a crude input proxy with a future native brake API changes the projection adapter/version, not the component.
- Unsupported characteristics stay NCM-simulated. Physical expression is optional evidence, not ontology.

## 12. The required-mod proof after `KB-112`

Report 35 supersedes this audit's earlier first-test choice. The old NCM `Unverifiable` wall was public-HTTP URL
sanitation, not review. Per the owner's forensic-audit instruction, the first delivery proof now uses the
existing RB15 and NCM livery packages plus their real ArchiveXL/TweakXL dependencies; it does not create a dummy.

MASTER_TEST §AP owns the exact contract: HTTPS endpoint and aligned builds; Case A with the named manual files
present; consent/fetch/hash/projection; loader logs and actual RB15/livery availability in game; reconnect/Solo
restoration; then Case B with only the relevant manual files safely isolated. Production remains parked.

A later control-extension delivery proof may still use a minimal init/version/capability/heartbeat package, but
only after the real-package pipeline passes. Wrong/missing/outdated/runtime-failed readiness, automatic update,
removal and secured exact-hash review remain separate later gates. Passing inert vehicle/livery delivery must
not be misreported as proof that executable NCM control code booted and stayed healthy.

This proof is independent of today's setPerformance and companion experiments. It must not delay AN or the
local brake proof.

## 13. Future OPEN//77 capabilities that would remove the limitation

The smallest useful platform additions, in order:

1. A server-authored, per-vehicle, replicated **input-authority profile** applied at the native final vehicle
   command point: bounded throttle/brake/steering scales/curves with instance identity, precedence, read-back,
   clear/reset and authority-transition semantics. Do not expose arbitrary force injection first.
2. A client API that can atomically replace a named vehicle axis after blocking the original, with resource
   ownership and automatic teardown. This is less authoritative but enables safe prototypes.
3. Server-visible per-player launcher digest and a platform-owned runtime capability/health attestation for
   required executable packages.
4. Server-observable/corroborated effective control values with timestamps/authority epochs, plus snapshot age,
   so rules can distinguish requested, applied and stale commands.
5. Eventually, native per-instance brake/grip/steering/suspension primitives where the platform can express
   the real property. Those supersede proxies without changing NCM mechanical truth.

## 14. Final classification

| Discovered path | Classification | May Parts depend on it now? |
|---|---|---:|
| Current `setPerformance` carrier | **PLAUSIBLE - DEVELOPMENT PROOF REQUIRED** (AN unchanged) | no |
| Companion wheel/pedal -> virtual pad path | **PROVEN NOW** as translation; not as NCM mechanical effect | no |
| Companion static brake cap | **DEVELOPMENT-ONLY / NOT ENFORCEABLE; proof required** | no |
| Companion static steering cap/curve | **DEVELOPMENT-ONLY / NOT ENFORCEABLE; proof required** | no |
| Telemetry-based TC/ABS prototype | **PLAUSIBLE - DEVELOPMENT PROOF REQUIRED**, stability-sensitive | no |
| Ordinary OPEN//77 analogue middle layer | **BLOCKED BY CURRENT PLATFORM** | no |
| Required NCM game-side final-command extension | **PLAUSIBLE - DEVELOPMENT PROOF REQUIRED**; HTTPS real-package delivery proof owed under `KB-112` / §AP | no |
| Secured automatic delivery of that executable | **REQUIRES PLATFORM REVIEW/INDEXING; NCM happy path unproved** | no |
| Required-mod digest as runtime/anti-cheat attestation | **UNSUPPORTED BY CURRENT EVIDENCE** | no |
| Input shaping represented as native grip/brake/suspension physics | **UNSUITABLE / SEMANTICALLY DISHONEST** | never under that name |
| NCM-simulated mechanical truth with no carrier | **PROVEN architectural fallback** | yes, once its own Parts design is authorised |

## 15. What changed, and what did not

Changed by this audit:

- L50/L71's old absolute platform rationale (executable content cannot be a secured world requirement) is no
  longer supported by current official documentation. Exact-hash verified executables are explicitly inside
  the world-mod model. This does not reverse the owner's inert-fleet/third-party-dependency choices by itself.
- The companion is confirmed as the cheapest brake-authority laboratory, with two diagnostic/safety gaps that
  must be fixed inside any temporary harness.
- A common game-side extension is a credible future architecture, but only after two separate proofs:
  final-command interception/bridge, and automatic delivery/runtime readiness.

Unchanged:

- `KB-112`, the reshaped real-package §AP/R5 and L76 remain active; KB-8's observations are historical but its
  review/attestation causal conclusion is superseded.
- Gate 6 AN remains mandatory and first.
- No Parts/Engineering implementation or carrier mapping is authorised.
- No claim of native brake force, tire grip, suspension or steering-physics modification has been made.
- No server, companion, client package, schema or Production behavior changed during this research.
