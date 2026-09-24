### Network vehicles › Drivetrain, wheels, and engine audio

The live vehicle blackboard and input state are appended to every owner motion sample.
RPM, maximum RPM, gear, speed, and longitudinal/transversal suspension forces are read from the
2.31 `VehicleDef` blackboard. Throttle, brake, burnout, reverse, and on-ground state come from the
native `vehicleBaseObject`. Observers smooth these values, write them into their streamed
vehicle's blackboard, and update entity-scoped mechanical audio parameters at 30 Hz. Engine pitch,
load, braking, gear, and lateral load therefore follow the network owner instead of being inferred
independently by each client.

Remote engine audio starts when the canonical engine state, a remote driver, or fresh drivetrain
activity proves the engine active. It stops when the engine and driver are inactive, the vehicle
streams out, or authority becomes local. This avoids initial silence while the durable engine bit
lags the realtime motion. Two switchable strategies exist (debug bridge
`vehicle.audiomode_<0-3>`: `0` off, `1` traffic, `2` mechanical, `3` both; **default mechanical**):
*mechanical* engages the vanilla driver-mix state
machine (`vehicleAudioEvent OnPlayerDriving`) and feeds the measured 2.31 RTPC names
(`paramEngineRPM`, `paramVehicleSpeed`, `paramWheelAngularSpeed`, `veh_speed`, `veh_accel`,
`veh_engine_throttle_input`, `paramLongSLip`, `paramLatSlip`, and `paramTotalSlip`) from the
replicated motion at 30 Hz, so pitch, load, and tire stress follow the
network owner. Each engine value is published to the vehicle entity scope consumed by its
model-specific `gameaudioVehicleAudioComponent`, plus the authored engine and general emitters for
spatial voices. *Traffic* is a diagnostic-only mode: it plays the discrete
`<audioResourceName>_traffic_engine_loop` Wwise pair resolved from the live TweakDB record, but
that simplified traffic voice cannot reproduce the local vehicle's complete mechanical timbre.
Four global tyre loops target the template's named wheel emitters and receive
their RTPC slip values independently, which preserves spatial tyre roll and squeal. Replicated
gear transitions additionally play the model's `_gear_up`/`_gear_down` one-shots.

Observer tire smoke uses
`base\fx\vehicles\_skid_marks\skid_fx.effect`; the asphalt trail is a separate native
`base\fx\vehicles\_wheels\skid_marks\sport\v_skid_mark_s_m_01.effect` backed by
`trail_decal.mt`. A deterministic slip signal is derived from
chassis-relative velocity, brake, throttle, and burnout. Hysteresis prevents VFX flicker; one
pair of emitters per rear wheel (one centered pair on bikes) follows safe chassis-relative contact
points. When slip stops, the native effect loop is broken instead of killed: smoke fades for about
2.5 seconds and trail decals remain for their roughly 31-second authored lifetime. Stream-out,
despawn, or authority handoff still performs an immediate cleanup. Exact
surface-material particles are outside the v1 contract.

Body damage is replayed only after the streamed vehicle's authored components have attached.
Broken-glass bits are resolved against that exact vehicle record's destruction-glass list and
then applied through native glass events, so custom/model-specific window component names are
preserved for current viewers and late joiners.

`steering` is normalized to `-1..1` and `wheelRotation` is a wrapped radian phase. REDengine 2.31
does not expose its live steering input through RTTI, but Open77's audited 2.31 adapter reads the
native lateral vehicle input at `vehicleBaseObject+0x278`. The owner therefore transmits real
keyboard/controller steering even while stationary. The authoritative wrapped wheel phase initializes
the observer and replicated velocity advances it every rendered frame without packet-phase feedback.
These values remain available in read-only client snapshots. Open77 does not currently write the
observer's hard-transform wheel bindings: their parent animation graph can be incomplete immediately
after streamed attachment, and querying that graph caused a reproducible null dereference inside
REDengine on both clients. The locally driven vehicle keeps its native wheel animation and real
physics; a lifecycle-safe observer chassis adapter remains required for guaranteed visual wheel pose.

The server validates bucket, claim proximity, owner-to-vehicle proximity, generation/epoch,
monotonic tick, finite values, velocity/RPM/input/suspension bounds, and travelled distance. Client scripts cannot
claim authority directly.

