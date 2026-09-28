# 43 - NCM Rig Bridge: why Carrier did not replace the companion, and the bounded route that can

> **STATUS: CURRENT** - authority for: *physical rig input and force feedback* - accepted diagnosis and
> the governing boundary for the built Rig Bridge. Runtime behaviour is governed by `ncm/rig_bridge/`;
> live acceptance remains in `MASTER_TEST §BU`.
> Authority map: [INDEX.md](INDEX.md). Owner direction is recorded in `L185`; the evidence rule correcting
> an overclaim in the first assessment is recorded in `L186`; multi-vendor scope is recorded in `L188`; the
> full-product build is authorised and executed under `L191`.

**Assessment date: 2026-09-27.** This answers the owner's request to examine `ncm/carrier`, explain why its
wheel/pedal/custom-rig subgoal fell away, and shape a dedicated Rig Bridge without changing Carrier.

## 1. Answer first

Carrier did not fail at one difficult native call. **The rig path was never connected end to end.** Four
independent edges are absent in the current source:

1. `Devices::poll()` has no caller.
2. `Devices::controls()` has no consumer.
3. `vehicle::setCommand()` has no caller.
4. `vehicle::onVehicleTick()` is not attached to a detour.

`installHook()` resolves three offsets and flips `g_installed`; it installs no hook. `KB-135` already caught
the resulting false claim in Carrier 0.1.1, and the current log now says `offsets resolved` rather than `hook
installed`. The behavior itself was never completed.

Connecting those four edges would only have completed Carrier's command path; it would not by itself have
explained the separate device-acquisition observation. In one specific in-process SDL diagnostic, SDL saw the
Xbox pad and did not acquire the G29, Thrustmaster pedals or ESP32 rim. Windows enumerated them, while zero-access
HID opens returned `ERROR_ACCESS_DENIED` (`KB-140`). That result says the attempted SDL/HID paths failed in that
process and lifecycle. It does **not** identify the holder, prove an unavoidable ownership conflict, or establish
that an in-process bridge cannot read the devices by another API or integration path. The external companion
worked as a separate process, normally started before the game, reading SDL devices and presenting a ViGEm Xbox
pad. Treating its SDL-shaped code as a drop-in plugin port was an unproved assumption; the failed port is not a
verdict on the native idea.

The correct next product is a separate **NCM Rig Bridge** RED4ext mod. Carrier remains the machine-effects mod.
Rig Bridge owns hardware, mapping, direct vehicle input, force output and local safety. Its server connection is
a low-rate control/health plane; steering and pedals never make a round trip through OPEN//77 or WebUI.

## 2. What exists today

### 2.1 The external companion was a complete product loop

The canonical companion at `C:/Users/eveng/Documents/ncm-wheel` contains all of the product work that the
workspace reference harness does not:

- multi-device discovery and manual reassignment;
- wheel/pedal/rim role and axis mapping, including split rigs and all-in-one wheels;
- steering range, curve and deadzone;
- button learning and gamepad merge;
- on-foot gating;
- a 120 Hz input loop;
- ViGEm virtual-pad output;
- FFB arming, ceilings, slew, condition effects, resume and destructive cleanup;
- visible diagnostics and packaged-build checks.

It also had real defects (`KB-103`, `KB-104`, `KB-110`, `KB-127`), but those were defects in a complete loop.
Carrier received only a small subset of that behavior.

### 2.2 Carrier's rig side is a scaffold beside a successful machine-effects product

Carrier does construct `Devices`, a `Mixer`, the localhost server and the `hook` module. Its machine side then
grew into the working product: record projections, the live physics probe, per-Machine body binding, handling
leases, top-speed and gearing. The rig side stayed almost exactly where the skeleton commit placed it:

- `input/devices.cpp` was changed only by the initial skeleton and the later device-diagnostic pass;
- `vehicle/hook.cpp` has never changed since the initial skeleton;
- no worker polls the devices;
- no atomic/latest input frame exists;
- no player-vehicle pointer gates command injection;
- no hook fire counter can prove a detour ran;
- no input watchdog can neutralise a stale command;
- rim buttons, profiles, manual mapping, gamepad merge and steering shaping are absent.

The comment in `CMakeLists.txt` says ViGEm is gone because the plugin writes the final vehicle command directly.
That would be a sound end state. The write was simply never built.

### 2.3 Force feedback is only half-native

Carrier does accept NCM's 30 Hz telemetry frames and feed its native mixer. That is a real connected path.
It still depends on the same in-process SDL device acquisition that failed to reach the owner's wheel, and it
does not use the richer native physics source contemplated by Report 36. On the only rig that matters for the
first proof, an FFB mixer with no haptic handle is inert.

### 2.4 The bridge became two channels already

`client/carrier_bridge.lua` documents why the old one-peer model broke: the external companion really drove the
rig while Carrier really drove machine physics, so it created **two hidden surfaces** and discriminated the
machine peer by `health.version`. This is useful inheritance, not something to erase.

The new mod can replace the companion side of that two-channel arrangement without adding a third WebUI surface.
It should not share Carrier's `38480-38483` discovery range, because role discovery by bind order is the same
ambiguity the two-surface split was written to end. Give Rig Bridge a dedicated port range and protocol identity;
retain the existing machine surface for Carrier.

### 2.5 Working in-process mods are positive evidence, not just inspiration

The first assessment cited Direct Wheel's architecture but did not trace its implementation deeply enough to
let that evidence change the conclusion. That was a due-diligence failure (`KB-170`). Three source precedents
materially change the starting point:

- **clevergrant/cp2077-wheel-mod** is an all-in-process RED4ext product. Its 250 Hz pump reads a Logitech wheel
  through the Logitech SDK; a real `UpdateVehicleCameraInput` detour writes steering/throttle/brake only to the
  cached mounted-player vehicle; redscript supplies mount state and vehicle signals; and the plugin drives FFB
  and buttons locally. Its README says no virtual gamepad or XInput shim is involved. It was tested on G923 and
  G920 and its device table includes G29 variants. This is positive existence evidence for the architecture on
  Cyberpunk 2.31, though not yet a live PASS on the owner's G29.
- **natpoh/cp2077-wheel-mod-moza** replaces the single-vendor assumption with source-visible DirectInput. It
  calls `DirectInput8Create`, enumerates every attached game controller, opens the selected wheel against the
  game's own `HWND` as `EXCLUSIVE|BACKGROUND` for FFB, opens a separately selected pedal device as
  `NONEXCLUSIVE|BACKGROUND`, polls both at 250 Hz, exposes configurable axis mapping, creates DirectInput force
  effects, and feeds the same working vehicle detour. Its README records a Moza R5 test and describes other
  DirectInput wheels as candidates. That is not proof of every brand, but it directly refutes the claim that an
  in-process DirectInput route was merely hypothetical.
- **jackhumbert/custom_game_controller** is a separate MIT Cyberpunk RED4ext mod for multiple arbitrary input
  devices. Its C++ uses Windows `RawGameController` (Windows.Gaming.Input, not the `WM_INPUT` Raw Input API),
  listens for add/remove events, reads axes/buttons/switches from every controller, and injects them into the
  game's input collection. The repository ships Fanatec and dual-Thrustmaster mappings. This proves another
  in-process multi-device acquisition and game-input path exists; it does not provide our FFB or NCM product.

None of those projects alone is the requested product. Together they move the open question from *can a native
rig mod exist?* to *which proven mechanisms compose cleanly for the owner's G29 + separate Thrustmaster pedals +
ESP32 rim, and what must NCM add for stable identity, mapping, safety and Online context?*

## 3. Why it failed

### 3.1 Scope failure: one mod was asked to become two products at once

`L146` deliberately made Carrier the owner of machine effects and rig support. The machine-effects research
immediately produced useful live discoveries and became the critical path. The hardware product needed a very
different discipline: device matrices, manual mapping, hotplug, output safety and per-backend testing. The single
name hid two roadmaps, and the one with visible server consumers displaced the one whose code compiled but did
nothing.

### 3.2 Integration failure: components were mistaken for a path

The presence of `Devices`, `Controls`, `Command`, `Mixer` and `onVehicleTick()` looked like progress. There was
no executable assertion connecting them. The first live log even said `final-command authority installed` when
only offsets had been resolved (`KB-135`). Later wording became honest, but no acceptance item required a device
sample to become a command and a detour fire to change the player's car.

### 3.3 Acquisition failure: one SDL port was mistaken for an architecture test

The companion acquired devices as a separate process and normally started before the game. Carrier initializes
from RED4ext's Running state, after the game and its input stack already exist. In the recorded diagnostic,
Windows could enumerate every device while the attempted SDL/HID paths did not acquire the G29, pedals or rim.
The evidence did not establish whether timing, window registration, backend selection, process state, another
handle owner, or something else caused that result. We stopped at a symptom and promoted a plausible explanation
to a limit of the architecture (`KB-170`).

Windows Raw Input is a genuinely different candidate: the application registers top-level HID collections and
receives `WM_INPUT`; it does not have to open the input device. **This is a candidate to prove, not a conclusion
to code from.** Force feedback is separate again: DirectInput requires exclusive device access for force effects,
so Raw Input can solve generic input without solving generic output.

### 3.4 Product-regression failure: the port discarded most of the working companion

Carrier's shape-based classifier is not a replacement for the companion's device product. It has no saved manual
assignments, no profiles, no button mapping, no steering range/curve/deadzone, no hotplug/reload UI, no gamepad
merge and no on-foot action policy. A four-edge wiring fix would have produced a narrow axis demo, not replicated
`NCM-Wheel-Support.exe`.

### 3.5 Test-contract failure: no rig-specific live gate owned the claim

The workspace rule is that built is not done without a live PASS (`L69`). The carrier test sequence correctly
split delivery, startup, handshake, projection and physics feel, but the rig promise never gained a small,
mandatory proof of its own. A truthful `hook=false` health message became an accepted long-term state while the
machine-effects work continued. The subgoal did not fail loudly; it had no gate capable of failing.

### 3.6 Transport failure: high-rate hardware work was entangled with server transport

The localhost/WebUI bridge is clever and necessary for OPEN//77's sandbox, but it is not an input bus. It brings
CEF startup, port arbitration, process ancestry checks, 30 Hz cadence and the eight-surface budget with it.
Steering must remain useful when the server, resource or WebHost is absent. The server should learn only health,
capabilities and intentionally shared control context; it should never sit in the physical control loop.

### 3.7 Research failure: we did not start from the working implementations

The original Carrier path was assessed mostly against its own SDL/HID diagnostics. The first version of this
document then repeated that narrowness: it called Direct Wheel a useful detour reference, described the
DirectInput fork by what it *advertised*, and still framed two provider spikes as a referendum on whether native
integration was viable. A source trace should have happened before that conclusion. It would have found a
working Logitech SDK product, a working DirectInput fork with split pedals, and a separate multi-controller
Windows.Gaming.Input mod. The lesson is operational: clone/read the implementation, trace the complete device to
game path, and distinguish a README claim, source evidence and an NCM live PASS.

## 4. The new boundary

### 4.1 Carrier remains unchanged

Carrier continues to own:

- server-to-client machine projection;
- record/TweakDB mutation and restoration;
- bound live-physics handling levers;
- machine/body leases and identity;
- its existing machine bridge and logs.

Its unused input/FFB scaffold may remain inert initially. Removing it is a later cleanup decision, not a
precondition for Rig Bridge.

### 4.2 Rig Bridge owns the whole local rig product

Rig Bridge owns:

- device discovery, stable identity, hotplug and reconnect;
- explicit wheel, throttle, brake, clutch, rim and button assignment;
- calibration, deadzones, curves and steering range;
- a hardware-provider interface and an output-provider interface;
- the latest normalized input snapshot;
- direct injection into the player's vehicle on the game thread;
- buttons/action mapping and on-foot/menu policy;
- native physics sampling for FFB;
- FFB mixing, per-backend safety limits, arming, watchdog and teardown;
- local configuration, diagnostics and self-test;
- an optional low-rate Online adapter.

### 4.3 The hot path is local

```text
hardware providers                 game thread
------------------                 -----------
Windows.Gaming.Input / DirectInput / vendor SDK
          -> normalized RigFrame -> atomic latest snapshot
                                      -> UpdateVehicleCameraInput detour
                                      -> exact mounted player vehicle

native vehicle physics -> FFB model -> safety gate -> output backend -> wheel motors
```

No Lua, WebUI, WebSocket or server event appears in either hot path.

### 4.4 The Online path is a control plane

```text
NCM server/resource -> existing hidden FFB surface -> dedicated Rig Bridge port
                    settings / race context / health / capabilities only
```

The current two-surface budget is preserved: the machine surface stays with Carrier; the former companion/FFB
surface becomes Rig Bridge's. Use distinct port ranges and explicit protocol identities. A missing Rig Bridge
must not affect Carrier, Parts, race entry or ordinary gamepad driving.

## 5. Hardware strategy: multi-vendor adapters, not one universal library

### 5.1 Input providers

Build one `IRigInputProvider -> device endpoints -> role bindings -> RigFrame` seam. No vendor is the core and no
wheel VID/PID whitelist decides whether a device is usable:

1. **Windows.Gaming.Input `RawGameController` provider.** Use the Custom Game Controller precedent for arbitrary
   controller count, hotplug, axes, buttons and switches. It is especially promising for the ESP32 rim and other
   button boxes. Retain `NonRoamableId`/hardware identity instead of copying that mod's array-index identity.
2. **Generic DirectInput provider.** Start from the source-verified Moza fork for enumeration, configurable axis
   mapping, separate wheel/pedal handles, reconnect and the game-window cooperative level. Generalise its
   wheel-plus-one-pedal shape into an arbitrary endpoint list so wheel, pedals, rim, shifter and handbrake can be
   separate devices. Persist instance GUID/path plus VID/PID/product metadata, not its product-name substring.
3. **`WM_INPUT` Raw Input provider only if an exact device needs it.** It remains a useful third path for an HID
   collection that WGI/DirectInput cannot read, but it is no longer the unresearched default escape hatch.
4. **Vendor SDK providers only as optional capability adapters.** The Logitech SDK is a strong G29 input/output
   route and a working source precedent. Future Thrustmaster/Fanatec/Moza SDKs may add output or LEDs, but a user
   must still get generic input when no vendor adapter is installed.

A profile binds each role/control independently: steering may come from the G29, throttle/brake/clutch from the
Thrustmaster device, actions from the ESP32 rim, and force output back to the G29. One physical device may own
several roles. A fourth or fifth device must not require an architectural change.

### 5.2 Force-output providers

Input and output must be separate interfaces. Raw Input has no FFB output path. Candidate order:

1. DirectInput FFB where the selected wheel exposes it, using the game's own window and explicit cooperative-level
   diagnostics demonstrated by the Moza fork.
2. Logitech SDK adapter for Logitech wheels, because a shipped in-process mod proves the path through G HUB.
3. Further vendor SDK adapters only after their licenses, redistribution and normalization are established.

Unsupported force output must never mean unsupported input. The capability report says which provider owns input,
which (if any) owns output, and why output is unavailable.

The existing SDL ceilings do **not** transfer automatically. They are measurements of SDL-normalized effects on
one G29. Every new output backend begins at the unknown/direct-drive conservative ceiling and earns a calibrated
profile on real hardware.

## 6. Game integration strategy

Use the demonstrated `vehicle::BaseObject::UpdateVehicleCameraInput` detour, resolved by the build's address
table, and gate it with the exact player-vehicle pointer supplied by mount/unmount wrappers. The current Carrier
hook module has the field offsets but not this detour or identity gate.

Required properties:

- unsupported/missing address resolves to **disabled**, not a guessed write;
- the hook exposes `attached` and a monotonic `fireCount`;
- injection occurs only for the cached mounted player vehicle;
- keyboard/gamepad and rig merge by explicit policy;
- stale input expires to neutral within a bounded interval;
- dismount, device loss, plugin stop and game shutdown all release commands;
- FFB has an independent 200 ms watchdog and destructive effect cleanup;
- patch support is build-pinned and proven before the package is promoted.

The maintained Direct Wheel architecture is a useful MIT reference for the detour, player-vehicle gate,
hardware-neutral `Frame` seam and fire counter. Do not adopt its whole product: its device, settings and force
model are not NCM's, and its Logitech SDK material has separate vendor terms.

## 7. Proof order

The full product is built under `L191`; these are now its ordered live acceptance gates. The cheapest falsifying
observations still come first.

### P0 - exact-rig acquisition, in-process and read-only

Run the full Rig Bridge with force output disarmed. With Cyberpunk running, enumerate and sample the G29,
Thrustmaster pedals and ESP32 rim concurrently. Log stable device identity, provider, report/axis/button layout,
values, hotplug and reconnect. This proves our exact rig composition; working upstream projects have already
supplied the broader architectural existence proof.

**If DirectInput does not read all three:** preserve the exact negative result:
API, device, access mode, process lifecycle, window/thread context, error and observed handle owner where it can
be measured. That falsifies those implementations only. Diagnose the boundary and test the next smallest
in-process mechanism before changing the architecture; it does not prove that an external process is technically
necessary.

### P1 - one axis reaches one exact car

Install only the vehicle detour. Feed a synthetic bounded steering ramp, then a real wheel sample. Prove:

- hook attached and `fireCount` advances;
- only the mounted player car changes;
- on foot, AI, parked and remote cars do not;
- disconnect/stall/dismount returns to neutral;
- ordinary gamepad remains usable.

No FFB and no Online bridge.

### P2 - split-rig input product

Steering, throttle, brake, clutch and rim buttons from the three real devices; manual reassignment; range,
deadzone and curve; hot unplug/replug; on-foot/menu gating; restart persistence. This is the point at which the
new mod has actually replaced the companion's **input** half.

### P3 - force output, one backend

G29 only, conservative ceiling, explicit arm, ramped self-test, native-physics signal, watchdog, focus loss,
device loss, dismount, plugin unload and process exit. Re-earn magnitude limits on this backend. This replaces the
companion's **output** half.

### P4 - OPEN//77 coexistence

Run under the exact Online client build with Carrier also loaded. Prove the input detour coexists with OPEN//77's
vehicle work, the two dedicated localhost protocols bind deterministically, and the existing two hidden surfaces
connect to the intended peers. Test two clients on one PC because Carrier's bridge history proves the single-client
case cannot stand in for it.

### P5 - required-mod delivery and failure isolation

Ship Rig Bridge as its own package/version. A missing or failed Rig Bridge leaves gamepad driving and Carrier
working. A Rig Bridge mismatch may withhold rig readiness; it must never zero steering at speed. Only a live PASS
beside each proof permits retirement of the external app.

## 8. What to reuse and what not to reuse

**Reuse:** the companion's normalized vocabulary, configuration semantics, device mapping UX, safety policy,
watchdogs and diagnostics; Carrier's lifecycle discipline and per-process bridge guard; Direct Wheel's hook shape,
player-vehicle gate, frame seam and fire counter; the existing FFB WebUI surface.

**Do not reuse blindly:** Carrier's SDL device layer; its unresolved `hook` scaffold; the companion's ViGEm
output; SDL-specific force ceilings on another backend; a shared port range whose role depends on bind order; a
server/WebUI round trip for physical control; Direct Wheel's entire settings/FFB stack or proprietary SDK payload.

## 9. Recommendation

**Executed under `L191`: build the full product under `ncm/rig_bridge/`, not a probe, and do not edit Carrier.**
DirectInput is the first complete provider because it has cross-vendor input, split-device and FFB precedent and
requires no redistributed vendor SDK. Keep Windows.Gaming.Input and Raw Input as additive providers when a
specific endpoint demonstrates a gap; do not pre-emptively turn the product into three competing input stacks.

The proof order above is the ordered live acceptance contract, not an implementation schedule. Start with force
output disarmed to identify the exact endpoints, then proceed through control and output. A failure at one stage
narrows the failing edge without deleting the rest of the product.

## 10. Implemented product (0.1.0)

`ncm/rig_bridge/` now contains:

- an independent RED4ext DLL and package, sharing only Carrier's vendored build dependencies;
- DirectInput enumeration of arbitrary game controllers with VID/PID, product name and stable instance GUID;
- independent stable-GUID bindings for steering, throttle, brake, clutch and button sources;
- a 250 Hz poll/merge loop, calibration/inversion/deadzone/curve mapping and hot-plug refresh;
- the source-proven `UpdateVehicleCameraInput` detour, gated by redscript mount events to the exact local vehicle;
- DirectInput spring/damper/constant output, explicit arm state, unknown-device hard ceiling and a 250 ms watchdog;
- a process-tree-guarded localhost/WebSocket bridge on `38520-38523`, reusing the existing WHEEL surface;
- a warning-free static-runtime build, mapping test, package script, default safe config and attribution notices.

Carrier remains on `38480-38483`; none of its runtime source or package changed. `carrier_bridge.lua` is the one
stack seam changed: it now scans the dedicated rig range for the FFB surface and the Carrier range for the
Machine surface, so bind order cannot choose the product.

The build is not called complete in the project sense. Hardware and in-game claims remain NOT RUN until
`MASTER_TEST §BU` records them. The external companion remains the fallback until both native input and FFB pass.

## 11. Evidence

- Local source: `ncm/carrier/src/input/devices.cpp`, `vehicle/hook.cpp`, `main.cpp`, and file history.
- Local live record: `KNOWN_BUGS.md` `KB-135`, `KB-140`, `KB-147`-`KB-150`.
- Canonical companion: `C:/Users/eveng/Documents/ncm-wheel/README.md` and `ncm-wheel.py`.
- Existing bridge: `ncm/online/resources/ncm_world/client/carrier_bridge.lua`.
- Microsoft Raw Input overview: <https://learn.microsoft.com/en-us/windows/win32/inputdev/about-raw-input>
- Microsoft DirectInput cooperative levels: <https://learn.microsoft.com/en-us/previous-versions/windows/desktop/ee416848(v=vs.85)>
- Maintained native precedent: <https://github.com/clevergrant/cp2077-wheel-mod/blob/main/ARCHITECTURE.md>
- DirectInput/split-device fork: <https://github.com/natpoh/cp2077-wheel-mod-moza>
- Source-verified DirectInput device/FFB path: <https://github.com/natpoh/cp2077-wheel-mod-moza/blob/main/direct_wheel/src/wheel.cpp>
- Multi-device Windows.Gaming.Input precedent: <https://github.com/jackhumbert/custom_game_controller>
