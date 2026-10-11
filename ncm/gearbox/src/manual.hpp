// NCM Gearbox -- the manual (L306 phase 3; owner design 2026-10-04: "slice gear 1 into an eight speed").
//
// A manual clone's ENGINE sees one long native gear (clones.cpp): 0 to the top of the spec, the model's strongest
// forward torque, the model's rpm range. The native gearbox therefore has nothing to shift, and nothing of its live
// state is ever written (0.1.2/0.1.3 wrote the native gear byte and crashed the game twice: KB-330).
//
// The gears the driver uses are VIRTUAL, here: N, 1..n, each with its own share of that long gear's torque (the model
// gear the spec took its band from, against the long gear's) and its own rev ceiling (the spec's band top). Every frame
// while a manual is driven this publishes the selected gear's share and ceiling to NCM Carrier (levers_shm.hpp), which
// scales drive and limits speed in the physics step -- downward only. The HUD's gear and rpm read the virtual gear.
//
// Input: two keys (config `manual.upKey` / `manual.downKey`, default Left Shift / Left Ctrl) and two pad buttons (XInput,
// `manual.padUp` / `manual.padDown`, default X / A -- owner, 2026-10-04), read only while THIS game
// window has focus, so two games on one PC never take each other's shifts. An upshift cuts drive for the spec's
// shift time; a downshift that would over-rev (speed above the target gear's ceiling) is refused, as a real box would
// be. Reversing is the game's own: while the native gear reads reverse, the levers stand aside.
#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace ncm::gearbox::manual {

struct VirtualGear {
    float ceilingMps = 0.0f;   // this gear's rev ceiling as a road speed
    float share = 1.0f;        // its share of the long native gear's torque, 0..1
};

struct VirtualSpec {
    std::string spec;
    std::vector<VirtualGear> gears;   // 1..n
    float idleRpm = 800.0f, maxRpm = 5000.0f;
    float audioMaxRpm = 4500.0f;   // the engine note's top: where the model's own gears shift (clones.cpp)
    int shiftMs = 250;
    std::string audio;   // the car's sound-event prefix, e.g. v_car_archer_hella (its _gear_up / _gear_down)
    // 0.4.0 (owner 2026-10-10: "apply our 1 gear chop over all 7 gears"): the clone's native box is SEVEN gear
    // records, `<clone>_engine_s1..s7`. Each shift re-slices the selected virtual gear's band 0..limiter across them --
    // rpm continuous from landing to redline, so a 4-speed is still four sweeps -- and each slice takes the torque the
    // model's own automatic has at that speed. 0.3.x had ONE long gear: always the game's "final" gear (its
    // finalGearTorqueDecimationScalor ~0.9 on everything) and always the strongest gear's torque spread over the band.
    std::vector<uint64_t> slices;
    float longTopMps = 0.0f;     // the top virtual gear + 2 %: the full-range layout, restored when the band is not in use
    std::vector<float> modelTopMps;    // the model's forward gears, their tops stretched to the reference top (as Carrier does the automatic)
    std::vector<float> modelTorque;    // ... and their torque multipliers
};

/// Called by clones.cpp for every manual clone it builds (keyed by the clone record's TweakDBID value).
void registerSpec(uint64_t record, VirtualSpec spec);

/// Keys and pad buttons from the config (`manual` block). Missing = the defaults (LShift / LCtrl, pad X / A).
void configure(const std::string& upKey, const std::string& downKey, const std::string& padUp, const std::string& padDown);

/// One frame of the player's car. Returns the virtual gear (-1 = R, 0 = N, 1..n), or -2 when this car is not a manual.
int32_t tick(uint64_t record, float speedMps, int32_t nativeHudGear);

/// The HUD's rpm for the virtual gear (valid after tick on a manual), and the same as 0 (idle) .. 1 (the gear's limiter).
float rpm();
float rpmFraction();

/// The current manual's sound-event prefix ("" when none), and whether to drive the engine audio parameters.
std::string audioName();
bool engineAudio();
void setEngineAudio(bool on);
/// What `veh_engine_rpm` gets (`manual.engineAudioScale`). The game feeds that parameter from its engine's rpm
/// (cooked audio metadata: `rpm` -> `veh_engine_rpm`), so its units are rpm:
///   rpm      (default, 0.2.5) idle .. the model's shift rpm across each gear -- the range the car's own gears play
///   limiter  idle .. the top gear's limiter (0.2.3: owner heard "redline basically the whole time")
///   fraction 0 .. 1 (0.2.4: owner heard it "too mute, sounds low rpm always" -- idle, in rpm units)
///   off      -1 = do not write; the game's own sweep
void setEngineAudioScale(const std::string& scale);
float engineAudioValue();
/// 0.2.6, the sound experiment (owner QA 2026-10-04: "goes from quiet to redline whine in a snap, no ramp"): a key
/// (`manual.audioCycleKey`, default PAGEUP) cycles the scale live -- rpm, limiter, fraction, off -- and the HUD names it.
void setAudioCycleKey(const std::string& name);
/// 0.2.7: the blend's layers, quietest first (`manual.blend.layers`), and every layer's minimum weight (`manual.blend.floor`).
void setBlend(const std::vector<std::string>& layers, float floor);
/// The car's own dash speed (vehicle blackboard SpeedValue), for the trace: the owner's one source of truth.
void noteDashSpeed(float value);
/// 0.2.8: the continuous engine-voice curve (`manual.curve`): lo..hi rpm across a gear, shaped by gamma, pulled `follow`
/// toward the game's own rpm, slewed with a `smoothMs` time constant.
void setCurve(float lo, float hi, float gamma, float follow, float smoothMs);
/// 0.3.1: the band's rpm window (`manual.band`): where an upshift lands, where the limiter is, and how far below zero
/// the computed minimum may go.
void setBand(float landingRpm, float redlineRpm, float minRpmFloor);
/// 0.4.0: how many of the seven native gears a selected gear is sliced over (`manual.band.slices`, 1..7, default 7).
void setSlices(int slices);
std::string audioMode();
/// 0.2.9: one HUD line under the rev bar -- the live curve values, a warning when follow switches the curve off, or
/// CONFIG ERROR when the last save did not parse.
std::string audioDetail();
void setConfigError(const std::string& error);
/// Once a second while a manual is driven: speed, gear, the value written to `veh_engine_rpm`, and the vehicle
/// blackboard's RPMValue as the script read it at the top of the frame (before our own write that frame).
void trace(float blackboardRpm, float speedMps);

/// +1 an upshift happened this tick, -1 a downshift, 0 none (for the shift sound).
int32_t shiftEvent();

/// What the dash should show: the virtual gear / rpm while a manual is being driven (ticked in the last 300 ms),
/// else the value the game passed in.
int32_t displayGear(int32_t native);
float displayRpm(float native);

/// Out of the car: stop publishing (Carrier falls back within 200 ms anyway).
void leave();

std::string status();

}  // namespace ncm::gearbox::manual
