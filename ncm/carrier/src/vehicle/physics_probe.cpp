#include "vehicle/physics_probe.hpp"
#include "vehicle/gearbox_levers.hpp"
#include "vehicle/thrust_levers.hpp"
#include "vehicle/seam_levers.hpp"

#include "log.hpp"

#include <RED4ext/RED4ext.hpp>

#include <nlohmann/json.hpp>

#include <atomic>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <cstdio>
#include <cfloat>
#include <cstring>
#include <fstream>
#include <mutex>
#include <thread>
#include <vector>

namespace ncm::vehicle::probe {
namespace {

// --------------------------------------------------------------------------------------- struct layout
//
// Offsets into `vehiclePhysicsData`, taken from LTBF's RED4ext.SDK fork (which derived them on 1.52-1.63)
// and used unchanged by our own March build. The two shallow ones are corroborated by that build having
// worked. NONE of them is verified on 2.31 -- verifying them is the entire point of this probe, which is
// why every one of them is read defensively and cross-checked against a value we already know.
//
//   +0x00  Vector3 force            accumulated force about to be solved
//   +0x18  Vector3 velocity         linear velocity, m/s  <- cross-checked against NCM's own speedometer
//   +0x180 BaseObject* vehicle      back-pointer to the owning vehicle, or junk if this is not a vehicle
//   +0x1BC float    total_mass      kg  <- cross-checked against "does this look like a car"
constexpr uint32_t kOffForce = 0x00;
// ---------------------------------------------------------------------------------------------------
// THE TORQUE CANDIDATE. Read-only in 0.1.16; nothing writes it.
//
// `force / ??? / velocity / angularVelocity` is the textbook rigid-body layout and `+0x0C` is the only
// unexamined Vector3 in it -- three floats sitting exactly where a torque accumulator belongs, in a struct
// we already hold a verified pointer to.
//
// **Why this matters more than it looks.** `force` at `+0x00` carries NO POSITION: all sixteen
// per-contributor calls add into one triple. So a zero-sum redistribution of the four vertical wheel
// entries is byte-identical in net force and cannot produce a moment -- there is nowhere in that field for
// a moment to live. That is the single explanation for three separate results: §AV2's front/rear negative,
// 0.1.15's left/right `rollBias` firing 240 writes a second on a parked car with no lean, and §AU3's "sag"
// (which was scaling all four DOWN, breaking vertical equilibrium -- less upward force, not a suspension
// response). The per-corner load entries are dead as an actuator, and moments must live somewhere else.
//
// If `+0x0C` is torque, then anti-roll, yaw balance and brake bias are all torque writes through the
// interception we have already proven, and the unknown-signature `ApplyTorqueAtPosition` is unnecessary.
//
// **It is NOT claimed until measured**, because a plausible offset that reads plausible numbers is exactly
// what §AV3's "orientation quaternion" was before the variance check killed it. The oracle here is the same
// one that validated mass against `m*g*dt`: for a rigid body, `torque_z * dt` should integrate to
// `I_zz * delta(angular velocity z)`. So the implied `I_zz` must come out POSITIVE and roughly CONSTANT
// across a drive. A field that varies but yields a wandering or negative inertia is not torque.
constexpr uint32_t kOffTorqueCandidate = 0x0C;
constexpr uint32_t kOffVelocity = 0x18;
constexpr uint32_t kOffAngularVelocity = 0x24;   // Vector3, rad/s -- 12 bytes past a verified field
constexpr uint32_t kOffOrientation = 0x30;       // Quaternion (x,y,z,w)
constexpr uint32_t kOffVehicleBackPtr = 0x180;
constexpr uint32_t kOffTotalMass = 0x1BC;
// `vehicle::BaseObject` inherits `ent::Entity`; the SDK asserts `ent::Entity::entityID` at +0x48.
// OPEN//77's vehicle snapshot publishes this same value as `engineEntity`. Unlike speed/mass/proximity,
// exact identity equality is suitable for authorising a write.
constexpr uint32_t kOffEntityID = 0x48;

// Final-command fields on `vehicleBaseObject`, reached through the verified back-pointer at +0x180.
// READ ONLY here -- `KB-135` refuses input authority and `L148` does not authorise it. These are read so
// Test 3's result can be normalised against what the driver was actually asking for; a yaw-rate change is
// only evidence if the steering input was the same either side of it.
constexpr uint32_t kOffInThrottle = 0x264;
constexpr uint32_t kOffInBrake = 0x268;
constexpr uint32_t kOffInSteer = 0x278;
constexpr uint32_t kInputsDeepestRead = kOffInSteer + sizeof(float);

// The deepest byte we ever touch. Anything claiming to be a PhysicsData must be at least this big; a
// smaller rigid body would fault, which is why the deep read is both rare and guarded.
constexpr uint32_t kDeepestRead = kOffTotalMass + sizeof(float);

// --------------------------------------------------------------------------------------- probe state

using RecalculateFn = uint64_t(__fastcall*)(void*);

RecalculateFn g_original = nullptr;
void* g_target = nullptr;

std::atomic<bool> g_attached{false};
// Observation is separable from attachment: we keep the detour in place but stop looking the moment
// anything faults, and while shutting down.
std::atomic<bool> g_observing{false};
std::atomic<uint64_t> g_ticks{0};
std::atomic<uint64_t> g_faults{0};
std::atomic<uint64_t> g_deepFaults{0};

// NCM's own view of the player's speed, from the telemetry frames the bridge already receives.
std::atomic<double> g_reportedSpeed{-1.0};

// --------------------------------------------------------------------------------------- distinct bodies
//
// How many different rigid bodies pass through per window. A stamped open-addressed table: the reporter
// bumps the generation once a second and every slot whose stamp is stale counts as new. Collisions
// undercount, which is fine -- this is an order-of-magnitude question, not an audit.
constexpr size_t kBodyTableSize = 512;
std::atomic<uint64_t> g_bodySlotStamp[kBodyTableSize];
std::atomic<uint32_t> g_generation{1};
std::atomic<uint32_t> g_distinctThisWindow{0};

// --------------------------------------------------------------------------------------- fastest body
//
// Plain atomics, deliberately not a locked struct: the detour runs on the physics thread and must not be
// able to block it. A torn read across these fields would misreport one log line once a second, which is
// an acceptable price for never holding a lock in a physics callback.
std::atomic<float> g_bestSpeedSq{0.0f};
std::atomic<uintptr_t> g_bestBody{0};
std::atomic<uintptr_t> g_bestBackPtr{0};
std::atomic<float> g_bestVelX{0.0f}, g_bestVelY{0.0f}, g_bestVelZ{0.0f};
std::atomic<float> g_bestForceX{0.0f}, g_bestForceY{0.0f}, g_bestForceZ{0.0f};
std::atomic<float> g_bestMass{0.0f};
std::atomic<bool> g_bestDeepOk{false};

// ------------------------------------------------------------------------------------- force cycle
//
// WHAT THE 0.1.3 BURST FOUND, WHICH IS WHY THIS EXISTS.
//
// `force` is not a total. It is a sequence of SIXTEEN writes per rendered frame, one per contributor, and
// the values are IMPULSES -- force x dt at the frame step, which is why they looked absurdly small when
// mistaken for newtons. 1100 kg x 9.81 / 60 Hz = 180 N.s, against an observed 182-184.
//
// One cycle, decoded:
//
//     (0,0,-182)                                   gravity, once
//     (4,-3,58) (4,-3,57) (2,-2,33) (2,-2,34)      four wheels: suspension normal loads
//     (-13,11,1) x2                                traction / drive
//     (1,-1,-0) x2                                 drag / rolling resistance
//     zeros                                        unused slots
//
// The four positive-Z entries summed to the negation of the single negative-Z entry in all three bursts
// (183/-184, 182/-182, 182/-182), and the front/rear split went from 93/89 at steady speed to 115/67
// under braking. Weight transfer, visible in the raw numbers. That is what identifies them as wheels.
//
// TWO THINGS ARE STILL UNPROVEN, AND THEY ARE WHAT THIS TRACKS.
//
//   1. WHICH wheel is which. Front/rear is inferable from braking; left/right is not, and needs
//      cornering. A left-right sweep should swing one pair against the other.
//   2. Whether a slot keeps its meaning frame to frame. It held within a 48-call burst. Indexing a write
//      by slot number would depend on it holding for as long as the game runs, which is a stronger claim
//      and needs a stability ratio rather than a spot check.
//
// So: anchor on gravity, number the calls after it, and report the four wheel loads with their slot
// indices, their envelope since the last report, and how often the cycle length came out the same.
constexpr uint32_t kMaxSlots = 32;
constexpr uint32_t kWheelCount = 4;

/// Gravity is the anchor: near-zero horizontally, strongly negative vertically. Nothing else in the cycle
/// looks remotely like it.
constexpr float kGravityFlatMax = 2.0f;
constexpr float kGravityDownMax = -50.0f;
/// A wheel's normal load. Well clear of the noise around zero, well under gravity's magnitude.
constexpr float kWheelLoadMin = 10.0f;

// WHY THERE IS NO CYCLE MODEL ANY MORE.
//
// 0.1.5 asked whether one thread owns a body's physics calls. It does not. The thread guard fired on the
// very first report and never stopped: `RigidBody::Recalculate` is called for a SINGLE body from MULTIPLE
// threads. Cycle length came out 13, 14, 21, 41, 80, 111, 402, 473, 737 -- not because the game varies,
// but because any one thread sees only a subset of the calls and the gravity anchor often lands on a
// different thread entirely. `modal=14 (17/82)` was noise dressed as a measurement.
//
// So indexing anything by position in a cycle is dead, and good riddance: it was the fragile part.
//
// WHAT REPLACES IT IS SIMPLER AND CANNOT RACE. A wheel is identifiable by the shape of its OWN value --
// a positive-Z entry in the load range that is not gravity -- so every call can be classified on its own,
// acted on, and forgotten. No shared cycle state, no slot arithmetic, nothing to coordinate across
// threads. That is the shape the March clutch hook already had, and why it worked.
//
// The one thing order is still needed for is telling the four corners apart, and that needs no global
// state either: the four wheel entries arrive CONSECUTIVELY on whichever thread is handling them, so a
// THREAD-LOCAL run counter gives 0..3 correctly, with no atomics and no possibility of interleaving.
enum class Kind { Zero, Gravity, Wheel, Horizontal, Other };

constexpr float kZeroEpsilon = 0.5f;

Kind classify(const float* f)
{
    if (std::fabs(f[0]) < kZeroEpsilon && std::fabs(f[1]) < kZeroEpsilon &&
        std::fabs(f[2]) < kZeroEpsilon)
        return Kind::Zero;
    if (std::fabs(f[0]) < kGravityFlatMax && std::fabs(f[1]) < kGravityFlatMax &&
        f[2] < kGravityDownMax)
        return Kind::Gravity;
    if (f[2] > kWheelLoadMin) return Kind::Wheel;
    if (std::fabs(f[2]) <= kWheelLoadMin) return Kind::Horizontal;
    return Kind::Other;
}

std::atomic<uintptr_t> g_trackedBody{0};   // latched once a body reads as a plausible vehicle

// -------------------------------------------------------------------------------- authoritative binding
//
// KB-146: `g_trackedBody` is useful diagnostics, not identity. It was historically selected by the
// fastest plausible vehicle and therefore must never authorise a force write. The bridge now supplies the
// REDengine EntityID for the locally seated, asset-backed Machine. A body becomes writable only when its
// vehicle back-pointer carries that exact ID. No pointer is accepted from Lua and no nearest/fastest
// fallback exists.
std::atomic<uint64_t> g_expectedEngineEntity{0};
std::atomic<uintptr_t> g_boundBody{0};
std::atomic<uintptr_t> g_boundVehicle{0};
std::atomic<uint64_t> g_bindingExpiresAtMs{0};
std::atomic<bool> g_bindingMatchedPending{false};
std::atomic<bool> g_bindingLostPending{false};
std::mutex g_bindingMetaMutex;
std::string g_bindingAssetId;
std::string g_bindingVehicleId;
std::string g_bindingAuthorityEpoch;

// The client publishes at 2 Hz. Four missed heartbeats is enough tolerance for an ordinary frame hitch
// and short enough that a lost ownership/seat update cannot leave another Machine tuned indefinitely.
constexpr uint64_t kBindingLeaseMs = 2000;

uint64_t monotonicMs() noexcept
{
    return static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count());
}

// Thread-local run state. No atomics: nothing here is shared, by construction.
thread_local uint32_t t_wheelRun = 0;
thread_local float t_wheelZ[kWheelCount] = {};
thread_local float t_wheelXY[kWheelCount] = {};
thread_local bool t_threadCounted = false;

// Counts, per second, across every thread. These are the validation: at 60 fps physics should produce
// about 60 gravity calls, 240 wheel calls and 60 complete four-wheel runs. If the classifier is sound the
// arithmetic comes out; if it is not, the numbers will say which way.
std::atomic<uint32_t> g_cntGravity{0}, g_cntWheel{0}, g_cntHorizontal{0}, g_cntZero{0}, g_cntOther{0};
std::atomic<uint32_t> g_runsComplete{0}, g_runsShort{0}, g_runsLong{0};
std::atomic<uint32_t> g_threadsSeen{0};

// The last complete four-wheel run, and the envelope since the last report.
std::atomic<float> g_cornerZ[kWheelCount];
std::atomic<float> g_wheelMin[kWheelCount];
std::atomic<float> g_wheelMax[kWheelCount];
std::atomic<float> g_lastGravity{0.0f};

// ----------------------------------------------------------------------------- the friction question
//
// WHY SCALING THE Z VALUES WOULD HAVE BEEN WRONG, WHICH IS WORTH WRITING DOWN BEFORE SOMEONE TRIES IT.
//
// The four corner Z values are what HOLDS THE CAR UP -- they sum to exactly the negation of gravity, every
// second the car is at rest, to within 0.0. Scaling them to 0.8 would leave 144 against gravity's 180: a
// net 36 downward, about 2 m/s^2 of unopposed sink. The car would not lose grip, it would sag into its
// suspension and bottom out. "Less normal load" is "less support", not "less friction".
//
// Friction is horizontal, and there are two candidates in the data, which is what this measures:
//
//   1. The XY part of each WHEEL entry -- (4,-3,58), (2,-2,33). Small beside Z, matched within each axle.
//      That is the shape a tyre's horizontal reaction should have.
//   2. The separately classified HORIZONTAL entries, whose count already tracks effort: about 86-93 per
//      second while barely moving, 216-339 while cornering.
//
// Whichever grows with lateral demand is the tyre channel, and scaling it reduces grip while leaving the
// car properly supported. Measured, not guessed: magnitudes are accumulated in hundredths as integers
// because an atomic float has no fetch_add.
std::atomic<float> g_cornerXY[kWheelCount];
std::atomic<float> g_cornerXYMax[kWheelCount];
std::atomic<uint64_t> g_horizMagSum{0};    // hundredths
std::atomic<uint32_t> g_horizMagMax{0};    // hundredths

// ------------------------------------------------------------------ decomposing the horizontal channel
//
// 0.1.7 SETTLED WHICH CHANNEL CARRIES FRICTION, AND IT IS NOT THE WHEEL ENTRIES.
//
// `wheelXY / wheelZ` came out CONSTANT across all four corners in every sample -- .011 straight and level,
// .037 rolled in a corner, .067 pitched under braking. One shared coefficient across four differently
// loaded wheels is not friction; it is the horizontal projection of each wheel's normal force as the body
// pitches and rolls. The magnitudes agree: all four wheels' XY summed to 7.2 during a hard left, about
// 0.04g, when turning the car needs nearer 90 N.s per frame.
//
// The separately classified horizontal entries do carry it -- peaking at 102 N.s in that same corner,
// against 21-28 in a straight line and 1.9 at rest.
//
// BUT THEY ARE NOT ONLY GRIP. The 0.1.3 burst showed `(-13,11,1) x2` as drive and `(1,-1,-0) x2` as drag,
// and both land in this class: five entries a frame, mixed. Scaling them uniformly would cut thrust and
// drag along with grip, and the car would feel slow rather than slippery.
//
// Decomposing against velocity separates them exactly, which is the technique the March clutch hook
// already proved on this engine: the component ALONG velocity is thrust and drag, the PERPENDICULAR
// component is lateral grip. This build only measures the split. The write that follows scales one of
// them, and this is the arithmetic it will use.
constexpr float kMinSpeedForDirection = 0.5f;   // below this, "along velocity" has no meaning

std::atomic<uint64_t> g_longAbsSum{0};      // hundredths
std::atomic<int64_t> g_longSignedSum{0};    // hundredths; sign says thrust (+) or drag (-) on balance
std::atomic<uint32_t> g_longPeak{0};
std::atomic<uint64_t> g_latAbsSum{0};
std::atomic<uint32_t> g_latPeak{0};
std::atomic<uint32_t> g_horizUndirected{0};  // seen while too slow to define a direction

void notePeak(std::atomic<uint32_t>& slot, uint32_t value)
{
    uint32_t seen = slot.load(std::memory_order_relaxed);
    while (value > seen && !slot.compare_exchange_weak(seen, value, std::memory_order_relaxed)) {}
}

// ------------------------------------------------------------------------------------------- the write
//
// The bounds are not decoration. Below 0.3 a car is on ice and may be unrecoverable at speed, which is a
// bad thing to discover through a typo in a config file; above 1.5 the extra grip is no longer a weather
// effect and starts to look like a physics exploit. Anything outside is clamped and logged, never obeyed.
constexpr float kGripScaleMin = 0.3f;
constexpr float kGripScaleMax = 1.5f;
constexpr float kGripScaleInert = 1.0f;
/// Closer to 1.0 than this and we do not touch the force at all -- no write, no rounding, no receipt.
constexpr float kGripScaleEpsilon = 0.001f;

std::atomic<float> g_gripScale{kGripScaleInert};
std::atomic<bool> g_writesEnabled{true};   // cleared for the session by a single fault
std::atomic<uint32_t> g_writes{0};
std::atomic<uint64_t> g_writeFaults{0};
std::wstring g_configPath;

/// Counting and per-second logging, separable from the effect. Every finding this probe was built to make
/// has been made; the bookkeeping now costs more than it earns. It runs ~2,000 times a second on the
/// tracked body and past 19,000 while the world streams, and the owner could not fairly judge a subtle
/// `gripScale` through the resulting hitches. Measured frame rate says the WRITES cost nothing -- 59.1
/// frames/s mean while writing against 55.6 while inert -- so the reading is the only candidate left.
std::atomic<bool> g_diagnostics{true};

// -------------------------------------------------------------------- TEST 2: does the force budget close?
//
// The vertical axis is known to close: four corner loads against one gravity entry, residual -0.0. The
// HORIZONTAL axis has never been checked, and if it does not close there are contributors we are not
// seeing -- which would undercut the force-channel model everything else is about to be built on.
//
// Summed over a one-second window rather than per frame, deliberately. Frames are not cleanly delimited
// on any single thread (twelve of them), so a per-frame boundary would race; over ~60 frames a boundary
// error is under 2% and the question is whether this closes at all, not to three decimal places.
//
// Sum(impulse)/mass should equal the measured change in velocity over the same window. At rest both
// should be ~0, because the wheels already cancel gravity.
constexpr double kImpulseScale = 1000000.0;   // millionths of N.s, rounded -- see the accumulation site
std::atomic<int64_t> g_impulseSumX{0}, g_impulseSumY{0}, g_impulseSumZ{0};

// Velocity of the TRACKED body, captured in the deep read. 0.1.11 differenced `g_bestVel`, which holds
// the velocity at the moment of the fastest sample in a window rather than at report time -- two
// misaligned instants differenced across a window boundary, which is not a measurement of anything.
std::atomic<float> g_trackedVelX{0.0f}, g_trackedVelY{0.0f}, g_trackedVelZ{0.0f};
std::atomic<bool> g_trackedVelOk{false};

// The torque candidate, published from the deep read. Read-only.
std::atomic<float> g_torqueX{0.0f}, g_torqueY{0.0f}, g_torqueZ{0.0f};
std::atomic<bool> g_torqueOk{false};
// Variance, because persistence alone passes a constant -- the §AV3 lesson, applied before the claim
// rather than after it.
std::atomic<uint32_t> g_torqueSamples{0};
std::atomic<int64_t> g_torqueAbsSumZ{0};        // x1000
std::atomic<int64_t> g_torqueMinZ{0}, g_torqueMaxZ{0};   // x1000
// The oracle: sum(torque_z * dt) against delta(omega_z) gives an implied yaw inertia. Accumulated as
// integers so two threads cannot tear a float.
std::atomic<int64_t> g_torqueImpulseZ{0};       // x1000, sum of torque_z * dt
std::atomic<int64_t> g_omegaZStart{0};          // x1000, first omega_z in the window
std::atomic<bool> g_omegaZStarted{false};
// Sign agreement with steering: a yaw torque should oppose or follow steer consistently, not at random.
std::atomic<int64_t> g_torqueSteerAgree{0}, g_torqueSteerTotal{0};

// ---------------------------------------------------------------------------------------------------
// 0.1.17: the torque oracle, sampled ONCE PER FRAME instead of once per second.
//
// 0.1.16 read the torque candidate inside the deep-read block, which is gated twice -- rate-limited
// 1-in-16 AND only for whichever body is fastest that window. That yielded 1-8 samples a second, each
// standing for 0.3-1s of elapsed time, and then multiplied each by dt = 1/60. **The integration was wrong
// by a factor of twenty to sixty and irregularly so, which is why `impliedIzz` wandered and flipped sign.**
// That number was never evidence about `+0x0C`; it was evidence about the sampler. Exactly the class of
// error KB-143 records, committed again one build after writing it down.
//
// The fix was already proven and sitting unused: **the gravity entry fires exactly once per frame per
// body** (§AU4 -- `grav=60` at 60 fps, repeatedly exact). Sampling there makes dt = 1/60 true rather than
// assumed, and gives an exact frame count to divide by.
// **0.1.18. The gravity entry was the WRONG instant, and the way it was wrong is the finding.**
// 0.1.17 sampled once per frame on the gravity entry and got `impulseZ = +0.000` in every window while
// yaw moved by up to 1.4 rad/s. 0.1.16, sampling at effectively random points in the cycle, saw the same
// field reach 71.5. Both are true: **the gravity entry is the FIRST of the sixteen contributor calls**, so
// it catches the accumulator empty. Zero at frame start, non-zero later, is what an accumulator does --
// the same behaviour `force` at `+0x00` has, which is the field we already know accumulates across the
// cycle.
//
// So sample on EVERY call for the tracked body and keep the frame's peak magnitude, snapshotting and
// resetting it at the gravity entry -- which is now used as a frame BOUNDARY rather than as a sample
// point. For a value that fills monotonically across the cycle, the peak is the frame's total.
//
// Cost: ~16 extra SEH float reads per frame on one body. That is not the KB-141 hazard, which was
// `VirtualQuery` per access rather than the read itself; the span for this body is already validated.
std::atomic<int64_t> g_tqFrameMaxAbs{0};    // x1000, |torque_z| peak within the current frame
std::atomic<int64_t> g_tqFrameSigned{0};    // x1000, the signed value at that peak

std::atomic<uint32_t> g_tqFrames{0};
std::atomic<int64_t> g_tqSumZ{0};          // x1000, summed once per frame
std::atomic<float> g_tqOmegaFirst{0.0f};
std::atomic<float> g_tqOmegaLast{0.0f};
std::atomic<bool> g_tqHaveFirst{false};

// Attitude, published from the deep read.
std::atomic<float> g_angVelX{0.0f}, g_angVelY{0.0f}, g_angVelZ{0.0f};
std::atomic<float> g_quatX{0.0f}, g_quatY{0.0f}, g_quatZ{0.0f}, g_quatW{1.0f};
std::atomic<bool> g_attitudeOk{false};

// Driver inputs, read through the back-pointer. Read only.
std::atomic<float> g_inThrottle{0.0f}, g_inBrake{0.0f}, g_inSteer{0.0f};
std::atomic<bool> g_inputsOk{false};

/// Write back the horizontal pair only, for the lateral grip scale. Z is untouched on horizontal entries.
bool writeForceXY(void* body, float fx, float fy) noexcept
{
    __try {
        auto* f = reinterpret_cast<float*>(reinterpret_cast<uint8_t*>(body) + kOffForce);
        f[0] = fx;
        f[1] = fy;
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}

// ------------------------------------------------------------------ TEST 3: zero-sum axle load bias
//
// THE QUESTION: is lateral force in this engine load-dependent? If it is, moving load between the axles
// moves grip between them, and anti-roll, brake bias, front/rear balance, per-corner tyre temperature and
// downforce all become expressible without ever finding `insert1`. If it is not, all of those collapse to
// magnitude-only and two Part families need a different design. That binary is worth one experiment.
//
// **ZERO-SUM IS THE SAFETY PROPERTY, NOT A REFINEMENT.** The four corner loads sum to exactly the negation
// of gravity -- residual pinned at -0.0 across twenty seconds of a parked car. Scaling them down makes the
// car sag into its suspension; that was measured and rejected. Shifting load between axles while holding
// the sum keeps vertical equilibrium exact, so the worst case here is that nothing happens.
//
// Per-call statelessness means one entry cannot see the others, so the shift is sized from the LAST
// completed run's axle totals -- one frame stale at 60 Hz, which is 16 ms and irrelevant. The existing
// residual line is the built-in check: if it stays near zero with a bias applied, the redistribution is
// genuinely zero-sum. If it drifts, the write is wrong and the log says so without anyone having to guess.
constexpr float kAxleBiasMax = 0.30f;
constexpr float kRearScaleFloor = 0.30f;   // never invert or null a rear corner, whatever the arithmetic

// ------------------------------------------------------- measuring the response, instead of sampling it
//
// THREE ATTEMPTS AT TEST 3 HAVE FAILED FOR THE SAME REASON IN DIFFERENT DISGUISES: reading one yaw value
// and one steering value per second and hoping to compare them. Against a driver slamming the wheel to
// +/-1.00 through hard turns, a 1 Hz sample of a transient is very nearly random -- 0.1.12 produced
// yaw=-1.66 and yaw=+1.84 for the same steer=+1.00, which is not evidence of anything.
//
// The fix is to stop sampling and start MEASURING: accumulate the regression on the hot path across every
// sample, and report the slope. Yaw per unit steer, least-squares through the origin, because zero steer
// must mean zero yaw. That needs no steady-state cornering, tolerates any input the driver produces, and
// gets better the messier the driving is rather than worse.
//
// Binned by speed, because yaw gain falls sharply with it -- pooling 5 m/s and 25 m/s would hide exactly
// the effect we are looking for. Accumulators reset when the bias changes, so each setting gets its own
// clean population and the two slopes are directly comparable.
constexpr uint32_t kSpeedBins = 3;
constexpr float kSpeedBinEdges[kSpeedBins - 1] = { 8.0f, 18.0f };   // m/s
constexpr float kRegressionScale = 1000000.0;
constexpr float kMinSteerForRegression = 0.10f;
constexpr float kMinSpeedForRegression = 2.0f;

std::atomic<uint32_t> g_regN[kSpeedBins];
std::atomic<int64_t> g_regSteerYaw[kSpeedBins];   // sum of steer * yaw
std::atomic<int64_t> g_regSteerSq[kSpeedBins];    // sum of steer^2
std::atomic<int64_t> g_regYawSq[kSpeedBins];      // sum of yaw^2, for the correlation

void resetRegression()
{
    for (uint32_t b = 0; b < kSpeedBins; ++b) {
        g_regN[b].store(0, std::memory_order_relaxed);
        g_regSteerYaw[b].store(0, std::memory_order_relaxed);
        g_regSteerSq[b].store(0, std::memory_order_relaxed);
        g_regYawSq[b].store(0, std::memory_order_relaxed);
    }
}

std::atomic<float> g_axleBias{0.0f};       // + moves load to the front axle
std::atomic<float> g_axleFrontSum{0.0f};   // last complete run, corners 0+1
std::atomic<float> g_axleRearSum{0.0f};    // last complete run, corners 2+3
std::atomic<float> g_leftSum{0.0f};        // last complete run, corners 0+3 (FL, RL)
std::atomic<float> g_rightSum{0.0f};       // last complete run, corners 1+2 (FR, RR)

// ---------------------------------------------------------------------------------------------------
// THE CHANNEL IS NOT ONE QUANTITY. Widening the proven write from lateral grip to four levers.
// ---------------------------------------------------------------------------------------------------
//
// `gripScale` was the smallest possible demonstration that a horizontal force entry can be decomposed
// against travel, one component scaled, and the vector put back -- statelessly, reversibly, on the player's
// car only. **The along-travel component was sitting untouched in the same expression the whole time.**
//
//   `driveScale`  scales longitudinal force when it is PUSHING  -> power delivery, per player, live
//   `brakeScale`  scales longitudinal force when it is RETARDING -> braking, per player, live
//   `rollBias`    shifts normal load LEFT/RIGHT, zero-sum        -> roll stiffness / anti-roll feel
//
// Drive and brake are deliberately separate multipliers rather than one `longScale`. They belong to
// different Part families -- an engine and a set of pads -- and a single number could not express a car that
// gains power without gaining stopping ability, which is most of the interesting ones.
//
// **`rollBias` is the left/right axis `§AV2` never tested.** That experiment moved load front-to-rear and
// found no change in lateral capability, which killed load redistribution as a GRIP lever. It did not test
// left/right, and it does not speak to ATTITUDE at all -- `§AU3` separately observed that scaling these
// entries makes a car sag into its suspension, so they demonstrably do move the body. Roll is what an
// anti-roll bar is for, and this is the axis that would express it. Expect a change in how the car LEANS,
// and on the evidence of `§AV2` expect no change in how much grip it has. Those are different claims and
// this is built to tell them apart rather than to hope.
//
// Every one of these inherits `L148`'s five properties unchanged -- stateless, exactly reversible at the
// inert value, inert by default, bounded, and scoped to the latched player vehicle under SEH.
constexpr float kDriveScaleMin = 0.30f, kDriveScaleMax = 2.00f;
constexpr float kBrakeScaleMin = 0.30f, kBrakeScaleMax = 2.00f;
constexpr float kRollBiasMax = 0.30f;

std::atomic<float> g_driveScale{kGripScaleInert};
std::atomic<float> g_brakeScale{kGripScaleInert};

// ---------------------------------------------------------------------------------------------------
// THE GOVERNOR. Top speed as a speed-dependent taper on drive, not as a number written somewhere.
// ---------------------------------------------------------------------------------------------------
//
// **Why this exists at all.** Three live drag runs at drive 1.000, 1.217 and 1.575 accelerated visibly
// differently and finished at exactly the same speed. That is not a drag equilibrium -- a real one would
// have moved terminal velocity by sqrt(1.575) = 1.25, which nobody could miss -- it is the GEARBOX. A car
// will not be pulled past the top of its last gear's speed band, so at the ceiling the drive force is
// already zero and `driveScale` has nothing left to multiply.
//
// So the design inverts: raise the gear ceiling once, per model, until the car is DRAG-limited rather
// than gear-limited, and then place each Machine's real top speed inside that window by withholding
// drive. The record sets the headroom; the instance sets the car.
//
// **Why a taper and not a flat scale.** `driveScale` alone is both acceleration AND top speed -- halve it
// and the car is slower everywhere, which makes "a part that costs you 10 km/h at the top" impossible to
// express without also gutting the launch. Tapering by SPEED separates them: full authority low down,
// falling to nothing as the target is approached. That is also what a real drag-limited car does, and what
// a rev limiter feels like, rather than a clamp that stops the car dead at a number.
//
// **Downward only, as everything here is.** The taper can only ever remove drive. It cannot push a car
// past a ceiling it would not otherwise have reached, so it inherits `L156` point 3 and needs no new
// authority to add force.
//
// Zero means no governor -- absent, not "a top speed of zero".
std::atomic<float> g_topSpeedMps{0.0f};

// How much of the approach is spent tapering. At 0.12 a car aimed at 200 km/h pulls at full authority to
// 176 and then eases off, which reads as running out of legs rather than hitting a wall.
constexpr float kTopSpeedTaper = 0.12f;

// ---------------------------------------------------------------------------------------------------
// DRAG IS NOT BRAKING, AND THE WRITE SITE COULD NOT TELL THEM APART (`IDEA-538`)
// ---------------------------------------------------------------------------------------------------
//
// Retarding force was discriminated by SIGN alone, so aerodynamic drag was scaled by `brakeScale` along
// with the brakes. Measured live 2026-09-26: `brakes 0.5` took the Galena from 131 to 139 km/h and
// `brakes 0.3` to 142. Two independent points both imply this hook sees about 22% of the car's drag --
// so a brake part silently moved terminal velocity, which is wrong on its face.
//
// **The discriminator is the driver's brake PEDAL, and it fails CLOSED.** A retarding force with the
// pedal at rest is drag. Anything else -- pedal down, never told, or a value too old to trust -- is
// treated as braking and keeps the brake lever, because the failure modes are not symmetric: scaling
// drag as though it were braking costs a little top speed, while scaling braking as though it were drag
// means a car that will not stop. Only one of those is worth risking on a dropped message.
std::atomic<double> g_brakeInput{-1.0};          // <0 means "never told"
std::atomic<uint64_t> g_brakeInputAtMs{0};
constexpr uint64_t kBrakeInputStaleMs = 250;     // the feed runs at 30 Hz; this is ~7 missed frames
constexpr float kBrakePedalRest = 0.02f;         // pedal noise floor, not a real application
constexpr float kDragScaleMin = 0.50f, kDragScaleMax = 1.50f;
std::atomic<float> g_dragScale{1.0f};

/// True only when we are CONFIDENT the driver is not braking. Every uncertainty answers false.
bool coastingConfidently(uint64_t nowMs) noexcept
{
    const double pedal = g_brakeInput.load(std::memory_order_relaxed);
    if (!(pedal >= 0.0)) return false;                     // never told
    const uint64_t at = g_brakeInputAtMs.load(std::memory_order_relaxed);
    if (at == 0 || nowMs < at || (nowMs - at) > kBrakeInputStaleMs) return false;   // too old to trust
    return pedal <= static_cast<double>(kBrakePedalRest);
}
// Below this there is no meaningful governor and the arithmetic stops being trustworthy.
constexpr float kMinGovernedMps = 3.0f;

// ---------------------------------------------------------------------------------------------------
// THE MANUAL'S GEAR (L306 phase 3, owner ruling 2026-10-04: NCM Gearbox drives through these levers)
// ---------------------------------------------------------------------------------------------------
//
// A manual car's engine sees one long native gear; the gear the driver selected lives in NCM Gearbox, which publishes
// that gear's share of the drive and its rev ceiling into per-process shared memory every frame (gearbox_levers.hpp).
// Here they multiply into the levers this hook already applies: the drive share into `driveScale` (neutral and the
// shift cut are 0), the ceiling into the governor as a sharp limiter. **Downward only, as everything here is:** a
// gear can take drive away and cap speed; it can never add either. A stale or absent publish (no Gearbox, an
// automatic, out of the car) is exactly the old behaviour. Opened lazily; retried every 2 s while absent.
HANDLE g_gearboxMapping = nullptr;
const ncm::gearbox_levers::Block* g_gearbox = nullptr;
std::atomic<uint64_t> g_gearboxRetryAtMs{0};
std::atomic<uint32_t> g_gearboxApplied{0};

bool gearboxLevers(uint64_t nowMs, float& drive, float& ceiling) noexcept
{
    drive = 1.0f; ceiling = 0.0f;
    if (!g_gearbox) {
        if (nowMs < g_gearboxRetryAtMs.load(std::memory_order_relaxed)) return false;
        g_gearboxRetryAtMs.store(nowMs + 2000, std::memory_order_relaxed);
        wchar_t name[96];
        ncm::gearbox_levers::name(name, 96, GetCurrentProcessId());
        HANDLE h = OpenFileMappingW(FILE_MAP_READ, FALSE, name);
        if (!h) return false;
        void* view = MapViewOfFile(h, FILE_MAP_READ, 0, 0, sizeof(ncm::gearbox_levers::Block));
        if (!view) { CloseHandle(h); return false; }
        const auto* b = static_cast<const ncm::gearbox_levers::Block*>(view);
        if (b->magic != ncm::gearbox_levers::kMagic || b->version != ncm::gearbox_levers::kVersion) {
            UnmapViewOfFile(view); CloseHandle(h); return false;
        }
        g_gearboxMapping = h;
        g_gearbox = b;
        NCM_INFO("gearbox: NCM Gearbox levers found -- a manual's selected gear now scales drive and caps speed");
    }
    const uint64_t at = g_gearbox->stampMs;
    if (at == 0 || nowMs < at || nowMs - at > ncm::gearbox_levers::kStaleMs) return false;
    const float d = g_gearbox->driveMul, c = g_gearbox->ceilingMps;
    if (!(d >= 0.0f && d <= 1.0f)) return false;              // not a value we trust: ignore the publish entirely
    drive = d;
    ceiling = (c > kMinGovernedMps) ? c : 0.0f;
    return true;
}

/// The gear's limiter: full drive to 97 % of the ceiling, none at it -- a rev limiter, not a governor's long taper.
float gearLimitAt(float speedMps, float ceiling) noexcept
{
    if (!(ceiling > 0.0f)) return 1.0f;
    if (speedMps >= ceiling) return 0.0f;
    const float start = ceiling * 0.97f;
    if (speedMps <= start) return 1.0f;
    return (ceiling - speedMps) / (ceiling - start);
}

// ---------------------------------------------------------------------------------------------------
// THE LIFT LEVER (L316 F0, owner ruling 2026-10-04: dev-only experiments on the flight ladder)
// ---------------------------------------------------------------------------------------------------
//
// **The one lever that ADDS force, and the explicit exception to "downward only".** NCM Thrust publishes a
// thrust-to-weight ratio and a burn (thrust_levers.hpp); here, at the bound body's gravity entry, the entry is
// rewritten to `gravZ * (1 - twr)`. Gravity's Z is -m*g*dt (§AU4: 1100 kg x 9.81 / 60 Hz = 180 N.s observed 182), so
// the ratio is exact with no knowledge of mass or step: 0 is untouched, 1 is weightless, 2 is a 1 g net climb.
//
// The same gates as every write: the positively bound, seated car only (KB-146), the session kill switch, SEH. A
// stale publish ends a burn on the next frame. The burn is timed in PHYSICS time (dt from the gravity entry itself),
// and each one is measured -- start and peak vertical speed, the integrated rise to the apex -- against the rise the
// ratio predicts, so a hop is a measurement and not an anecdote. No I/O here; the reporter turns it into a line.
bool readDeep(const void* body, float* outForceXyz, float* outMass, uintptr_t* outBackPtr) noexcept;
bool readVelocity(const void* body, float* outXyz) noexcept;
bool writeForceXYZ(void* body, float fx, float fy, float fz) noexcept;

HANDLE g_thrustMapping = nullptr;
const ncm::thrust_levers::Block* g_thrust = nullptr;
std::atomic<uint64_t> g_liftSupersededUntilMs{0};    // L324: GetTickCount64() until which installed components own lift
std::atomic<uint32_t> g_liftSupersededPresses{0};
std::atomic<uint64_t> g_thrustRetryAtMs{0};
std::atomic<bool> g_thrustFoundPending{false};

bool thrustLever(uint64_t nowMs, float& twr, uint32_t& burnMs, uint32_t& burnSeq, bool& holding) noexcept
{
    if (!g_thrust) {
        if (nowMs < g_thrustRetryAtMs.load(std::memory_order_relaxed)) return false;
        g_thrustRetryAtMs.store(nowMs + 2000, std::memory_order_relaxed);
        wchar_t name[96];
        ncm::thrust_levers::name(name, 96, GetCurrentProcessId());
        HANDLE h = OpenFileMappingW(FILE_MAP_READ, FALSE, name);
        if (!h) return false;
        void* view = MapViewOfFile(h, FILE_MAP_READ, 0, 0, sizeof(ncm::thrust_levers::Block));
        if (!view) { CloseHandle(h); return false; }
        const auto* b = static_cast<const ncm::thrust_levers::Block*>(view);
        if (b->magic != ncm::thrust_levers::kMagic || b->version != ncm::thrust_levers::kVersion) {
            UnmapViewOfFile(view); CloseHandle(h); return false;
        }
        g_thrustMapping = h;
        g_thrust = b;
        g_thrustFoundPending.store(true, std::memory_order_release);
    }
    const uint64_t at = g_thrust->stampMs;   // GetTickCount64() on both sides: one clock, no epoch to reconcile
    if (at == 0 || nowMs < at || nowMs - at > ncm::thrust_levers::kStaleMs) return false;
    const float r = g_thrust->twr;
    if (!(r >= 0.0f && r <= ncm::thrust_levers::kMaxTwr)) return false;   // not a value we trust
    twr = r;
    burnMs = g_thrust->burnMs > ncm::thrust_levers::kMaxBurnMs ? ncm::thrust_levers::kMaxBurnMs : g_thrust->burnMs;
    burnSeq = g_thrust->burnSeq;
    holding = g_thrust->holding != 0;
    return true;
}

enum class ThrustPhase { Idle, Burning, Coasting };

struct ThrustState {
    bool seqKnown = false;
    uint32_t lastSeq = 0;
    ThrustPhase phase = ThrustPhase::Idle;
    bool hold = false;
    uint32_t burnNo = 0;
    float twr = 0.0f;
    float remainingS = 0.0f;
    float mass = 0.0f;
    uint32_t frames = 0;
    float burnS = 0.0f;
    double impulse = 0.0;     // N.s added over the burn (beyond gravity's own)
    float vz0 = 0.0f, peakVz = 0.0f;
    double rise = 0.0, maxRise = 0.0;
    float coastS = 0.0f;
    uint32_t faults = 0;
    const char* why = "";
};

struct ThrustResult {
    uint32_t burnNo, frames, faults;
    float twr, burnS, mass, vz0, peakVz, maxRise, predVz, predRise;
    bool hold;
    const char* why;
};

std::mutex g_thrustMutex;
ThrustState g_thrustState;
// KB-337: a queue, not one slot -- two presses inside one reporter second used to overwrite each other's line.
constexpr uint32_t kThrustResults = 16;
ThrustResult g_thrustResults[kThrustResults]{};
uint32_t g_thrustResultCount = 0;          // guarded by g_thrustMutex
uint32_t g_thrustResultsDropped = 0;       // guarded: more than kThrustResults in one second
uint32_t g_thrustRefusals = 0;             // guarded: frames a burn was asked for with no bound car, for the reporter
constexpr float kG = 9.81f;

void finishThrust(ThrustState& s, const char* why) noexcept
{
    const float a = (s.twr - 1.0f) * kG;
    const float predVz = a > 0.0f ? a * s.burnS : 0.0f;
    const float predRise = a > 0.0f ? 0.5f * a * s.burnS * s.burnS + predVz * predVz / (2.0f * kG) : 0.0f;
    if (g_thrustResultCount < kThrustResults)
        g_thrustResults[g_thrustResultCount++] = {s.burnNo, s.frames, s.faults, s.twr, s.burnS, s.mass, s.vz0, s.peakVz,
                                                  static_cast<float>(s.maxRise), predVz, predRise, s.hold, why};
    else
        ++g_thrustResultsDropped;
    s.phase = ThrustPhase::Idle;
}

/// Called on every gravity entry of the tracked body, before the diagnostics gate. Costs one stale check when
/// NCM Thrust is absent or idle.
void thrustAtGravity(void* body, const float* force, bool authorised) noexcept
{
    float twr = 0.0f; uint32_t burnMs = 0, seq = 0; bool holding = false;
    const bool fresh = thrustLever(GetTickCount64(), twr, burnMs, seq, holding);
    std::unique_lock<std::mutex> lock(g_thrustMutex, std::try_to_lock);
    if (!lock.owns_lock()) return;
    ThrustState& s = g_thrustState;
    if (!fresh && s.phase == ThrustPhase::Idle) return;

    const bool newPress = fresh && s.seqKnown && seq != s.lastSeq;
    if (fresh && !s.seqKnown) { s.seqKnown = true; s.lastSeq = seq; }   // presses before Carrier saw the block never fire
    if (newPress) s.lastSeq = seq;
    // L324: a Machine whose installed components own its propulsion (a fresh wrench lease said so) ignores the legacy
    // lift lever entirely -- one owner for the car's thrust. Presses are consumed above, so none fires later.
    if (GetTickCount64() < g_liftSupersededUntilMs.load(std::memory_order_relaxed)) {
        if (s.phase != ThrustPhase::Idle) finishThrust(s, "superseded by installed components");
        if (newPress) g_liftSupersededPresses.fetch_add(1, std::memory_order_relaxed);
        return;
    }
    const bool startHold = fresh && holding && s.phase != ThrustPhase::Burning;
    const bool canWrite = authorised && g_writesEnabled.load(std::memory_order_relaxed);

    if (newPress || startHold) {
        if (s.phase != ThrustPhase::Idle) finishThrust(s, "interrupted by the next burn");
        if (!canWrite) { ++g_thrustRefusals; return; }
        float deep[3]; uintptr_t back = 0;
        s = ThrustState{s.seqKnown, s.lastSeq};
        s.burnNo = seq;
        s.phase = ThrustPhase::Burning;
        s.hold = startHold && !newPress;
        s.twr = twr;
        s.remainingS = static_cast<float>(burnMs) / 1000.0f;
        if (!readDeep(body, deep, &s.mass, &back)) s.mass = 0.0f;
        float v[3];
        if (readVelocity(body, v)) { s.vz0 = v[2]; s.peakVz = v[2]; }
    }
    if (s.phase == ThrustPhase::Idle) return;

    // dt from the gravity entry itself (-m*g*dt); a frame at 60 Hz if the mass is not one we believe.
    float dt = 1.0f / 60.0f;
    if (s.mass > 100.0f) {
        const float d = -force[2] / (s.mass * kG);
        if (d > 0.001f && d < 0.1f) dt = d;
    }

    if (s.phase == ThrustPhase::Burning) {
        const bool keepGoing = fresh && canWrite && (s.hold ? holding : s.remainingS > 0.0f);
        if (!keepGoing) {
            s.phase = ThrustPhase::Coasting;
            s.why = !fresh ? "lever went stale" : !canWrite ? "car unbound or writes disabled" : "burn complete";
        } else if (writeForceXYZ(body, force[0], force[1], force[2] * (1.0f - s.twr))) {
            s.frames++;
            s.burnS += dt;
            s.remainingS -= dt;
            s.impulse += -static_cast<double>(force[2]) * s.twr;
            g_writes.fetch_add(1, std::memory_order_relaxed);
        } else {
            s.faults++;
            g_writeFaults.fetch_add(1, std::memory_order_relaxed);
            g_writesEnabled.store(false, std::memory_order_relaxed);
            s.phase = ThrustPhase::Coasting;
            s.why = "write fault: writes disabled for the session";
        }
    }

    float v[3];
    if (readVelocity(body, v)) {
        if (v[2] > s.peakVz) s.peakVz = v[2];
        s.rise += static_cast<double>(v[2] - s.vz0) * dt;
        if (s.rise > s.maxRise) s.maxRise = s.rise;
        if (s.phase == ThrustPhase::Coasting) {
            s.coastS += dt;
            const bool falling = v[2] < s.vz0 - 0.2f && s.rise < s.maxRise;
            if (falling || s.coastS > 8.0f) finishThrust(s, s.why);
        }
    }
}

// ---------------------------------------------------------------------------------------------------
// THE WRENCH (L324): installed components as a force on the bound Machine
// ---------------------------------------------------------------------------------------------------
//
// NCM's engineering layer (core `engineering.installation`, `ncm_world/client/engineering.lua`) decides what an
// installed propulsor or impulse actuator does; it sends the result here as WORLD-space Newtons. This interprets
// none of it. At the bound body's gravity entry -- the channel F0 and the seam kick already proved -- it adds F * dt to
// the accumulator, with dt recovered from the gravity entry itself (-m g dt), so the impulse is exact at any step
// rate and the body's own mass decides the acceleration. A pulse is timed here in physics time, like a burn.
//
// Force at the centre of mass only: torque from an off-centre mount is NOT applied (no torque channel is known on
// 2.31). That expression loss is stated in the client's telemetry. Same gates as every write: bound + seated body,
// session kill switch, SEH. A stale lease (> ttl) applies nothing.
bool readForce(const void* body, float* outForceXyz) noexcept;

constexpr float kMaxWrenchN = 400000.0f;      // 2026-10-12: an AV's lift (four fans + two FD-1s, ~172 kN) plus margin
constexpr float kMaxAngularAcc = 8.0f;        // rad/s^2: the most any lease may spin a body up, per axis
constexpr int kMaxWrenchTtlMs = 300;
constexpr int kMaxPulseMs = 1000;

struct WrenchState {
    float sus[3] = {0, 0, 0};
    uint64_t susExpireMs = 0;
    bool pulsePending = false, pulseActive = false;
    uint32_t lastPulseSeq = 0;
    bool pulseSeqKnown = false;
    float pf[3] = {0, 0, 0}, pendingF[3] = {0, 0, 0};
    float pulseRemainingS = 0, pendingS = 0;
    float mass = 0;
    uint64_t massAtMs = 0;
    // for the reporter
    uint32_t frames = 0, pulsesStarted = 0, pulsesDropped = 0, refusedUnbound = 0, faults = 0;
    double impulse[3] = {0, 0, 0};
    double activeS = 0;
    float lastSus[3] = {0, 0, 0};
    // 2026-10-12, the AV (a Machine flown by an installed flight computer)
    float alpha[3] = {0, 0, 0};   // world rad/s^2, applied with the force at the gravity entry
    float ncmMass = 0;            // the NCM Machine's mass: force * (body mass / this) = NCM's acceleration
    bool av = false;
    uint32_t spinWrites = 0, spinFaults = 0;
};
std::atomic<uint64_t> g_avUntilMs{0};       // GetTickCount64() until which an `av` lease asks for physics on the bound body
std::atomic<uint64_t> g_boundTickMs{0};     // monotonicMs() of the bound body's last Recalculate
std::mutex g_wrenchMutex;
WrenchState g_wrench;
std::atomic<uint32_t> g_wrenchRefusedAsset{0};
std::atomic<bool> g_wrenchFirstPending{false};
std::atomic<bool> g_wrenchSeen{false};

void clearWrench() noexcept
{
    std::lock_guard<std::mutex> lock(g_wrenchMutex);
    g_wrench.susExpireMs = 0;
    g_wrench.pulsePending = g_wrench.pulseActive = false;
    g_liftSupersededUntilMs.store(0, std::memory_order_relaxed);
}

bool readSpin(const void* body, float* outXyz) noexcept;
bool writeSpin(void* body, const float* xyz) noexcept;

void wrenchAtGravity(void* body, const float* force, bool authorised) noexcept
{
    std::unique_lock<std::mutex> lock(g_wrenchMutex, std::try_to_lock);
    if (!lock.owns_lock()) return;
    WrenchState& w = g_wrench;
    const uint64_t now = GetTickCount64();
    if (w.pulsePending) {
        w.pulsePending = false;
        w.pulseActive = true;
        for (int i = 0; i < 3; ++i) w.pf[i] = w.pendingF[i];
        w.pulseRemainingS = w.pendingS;
        w.pulsesStarted++;
    }
    const bool spin = now < w.susExpireMs && (w.alpha[0] != 0.0f || w.alpha[1] != 0.0f || w.alpha[2] != 0.0f);
    const bool sus = (now < w.susExpireMs && (w.sus[0] != 0.0f || w.sus[1] != 0.0f || w.sus[2] != 0.0f)) || spin;
    if (!sus && !w.pulseActive) return;
    if (!(authorised && g_writesEnabled.load(std::memory_order_relaxed))) {
        w.refusedUnbound++;
        if (w.pulseActive) { w.pulseActive = false; w.pulsesDropped++; }
        return;
    }
    if (now >= w.massAtMs) {
        float deep[3]; uintptr_t back = 0; float m = 0.0f;
        if (readDeep(body, deep, &m, &back) && m > 100.0f) w.mass = m;
        w.massAtMs = now + 500;
    }
    float dt = 1.0f / 60.0f;
    if (w.mass > 100.0f) {
        const float d = -force[2] / (w.mass * kG);
        if (d > 0.0005f && d < 0.1f) dt = d;
    }
    float add[3] = {0, 0, 0};
    // the NCM Machine's acceleration, whatever the host body weighs (an AV body's mass is the game's, not the Machine's)
    const float massScale = (w.ncmMass > 100.0f && w.mass > 100.0f) ? w.mass / w.ncmMass : 1.0f;
    if (sus) for (int i = 0; i < 3; ++i) add[i] += w.sus[i] * massScale * dt;
    if (spin && now < w.susExpireMs) {
        float om[3];
        if (readSpin(body, om)) {
            for (int i = 0; i < 3; ++i) om[i] += w.alpha[i] * dt;
            if (writeSpin(body, om)) w.spinWrites++; else { w.spinFaults++; }
        }
    }
    if (w.pulseActive) {
        const float a = dt < w.pulseRemainingS ? dt : w.pulseRemainingS;
        for (int i = 0; i < 3; ++i) add[i] += w.pf[i] * a;
        w.pulseRemainingS -= a;
        if (w.pulseRemainingS <= 0.0f) w.pulseActive = false;
    }
    float cur[3];
    if (!readForce(body, cur)) { cur[0] = force[0]; cur[1] = force[1]; cur[2] = force[2]; }
    if (writeForceXYZ(body, cur[0] + add[0], cur[1] + add[1], cur[2] + add[2])) {
        w.frames++;
        w.activeS += dt;
        for (int i = 0; i < 3; ++i) w.impulse[i] += add[i];
        g_writes.fetch_add(1, std::memory_order_relaxed);
    } else {
        w.faults++;
        g_writeFaults.fetch_add(1, std::memory_order_relaxed);
        g_writesEnabled.store(false, std::memory_order_relaxed);
    }
}

// ---------------------------------------------------------------------------------------------------
// THE SEAM'S VELOCITY KICK (L317 SEAM-1c)
// ---------------------------------------------------------------------------------------------------
//
// The server's move (`setTransform`) keeps the car and its driver but erases the velocity (§SG4). NCM Snowglobe
// publishes ONE kick (seam_levers.hpp) once the lease is back; here, at the bound car's next gravity entry, the
// accumulator gets m * dv added -- an impulse through the channel F0 proved -- and two gravity entries later the
// velocity is read back, so the kick is a measurement. Same gates as every write. Re-reads the accumulator so a
// thrust write earlier in the same entry is kept, not overwritten.
bool readForce(const void* body, float* outForceXyz) noexcept;

HANDLE g_seamMapping = nullptr;
const ncm::seam_levers::Block* g_seam = nullptr;
std::atomic<uint64_t> g_seamRetryAtMs{0};
std::atomic<bool> g_seamFoundPending{false};

struct SeamResult {
    uint32_t seq;
    float target[3], dv[3], mass, vBefore[3], vAfter[3];
    uint32_t heldMs;
    bool applied;
    const char* why;
};
std::mutex g_seamMutex;
bool g_seamSeqKnown = false;          // guarded by g_seamMutex
uint32_t g_seamLastSeq = 0;
bool g_seamHolding = false;           // a target waiting for the car to be bound again
SeamResult g_seamHeld{};
uint64_t g_seamReceivedMs = 0;
SeamResult g_seamPending{};           // an applied kick waiting for its after-velocity
int g_seamFramesSince = -1;           // -1 = nothing pending
SeamResult g_seamResult{};
bool g_seamResultReady = false;

float clampDv(float d) noexcept
{
    if (!(d == d)) return 0.0f;
    return d < -ncm::seam_levers::kMaxDv ? -ncm::seam_levers::kMaxDv : (d > ncm::seam_levers::kMaxDv ? ncm::seam_levers::kMaxDv : d);
}

void seamAtGravity(void* body, bool authorised) noexcept
{
    const uint64_t now = GetTickCount64();
    if (!g_seam) {
        if (now < g_seamRetryAtMs.load(std::memory_order_relaxed)) return;
        g_seamRetryAtMs.store(now + 2000, std::memory_order_relaxed);
        wchar_t name[96];
        ncm::seam_levers::name(name, 96, GetCurrentProcessId());
        HANDLE h = OpenFileMappingW(FILE_MAP_READ, FALSE, name);
        if (!h) return;
        void* view = MapViewOfFile(h, FILE_MAP_READ, 0, 0, sizeof(ncm::seam_levers::Block));
        if (!view) { CloseHandle(h); return; }
        const auto* b = static_cast<const ncm::seam_levers::Block*>(view);
        if (b->magic != ncm::seam_levers::kMagic || b->version != ncm::seam_levers::kVersion) {
            UnmapViewOfFile(view); CloseHandle(h); return;
        }
        g_seamMapping = h;
        g_seam = b;
        g_seamFoundPending.store(true, std::memory_order_release);
    }
    std::unique_lock<std::mutex> lock(g_seamMutex, std::try_to_lock);
    if (!lock.owns_lock()) return;

    // an applied kick: read the velocity back two gravity entries later
    if (g_seamFramesSince >= 0 && ++g_seamFramesSince >= 2) {
        float v[3];
        if (readVelocity(body, v)) for (int i = 0; i < 3; ++i) g_seamPending.vAfter[i] = v[i];
        g_seamResult = g_seamPending;
        g_seamResultReady = true;
        g_seamFramesSince = -1;
    }

    // a new request: hold its target until the car is bound again (the lease is back)
    const uint32_t seq = g_seam->kickSeq;
    if (!g_seamSeqKnown) { g_seamSeqKnown = true; g_seamLastSeq = seq; }
    if (seq != g_seamLastSeq) {
        g_seamLastSeq = seq;
        const uint64_t at = g_seam->stampMs;
        if (at != 0 && now >= at && now - at <= ncm::seam_levers::kHoldMs) {
            if (g_seamHolding) {
                g_seamHeld.why = "superseded by a newer target";
                g_seamResult = g_seamHeld; g_seamResultReady = true;
            }
            g_seamHeld = SeamResult{};
            g_seamHeld.seq = seq;
            for (int i = 0; i < 3; ++i) g_seamHeld.target[i] = g_seam->target[i];
            g_seamHolding = true;
            g_seamReceivedMs = at;
        }
    }
    if (!g_seamHolding) return;
    if (now - g_seamReceivedMs > ncm::seam_levers::kHoldMs) {
        g_seamHeld.heldMs = static_cast<uint32_t>(now - g_seamReceivedMs);
        g_seamHeld.why = "not applied: the car was not bound again within the hold";
        g_seamResult = g_seamHeld; g_seamResultReady = true;
        g_seamHolding = false;
        return;
    }
    if (!authorised || !g_writesEnabled.load(std::memory_order_relaxed)) return;   // still waiting for the binding

    SeamResult r = g_seamHeld;
    g_seamHolding = false;
    r.heldMs = static_cast<uint32_t>(now - g_seamReceivedMs);
    float v[3] = {0, 0, 0}, deep[3], cur[3];
    uintptr_t back = 0;
    readVelocity(body, v);
    for (int i = 0; i < 3; ++i) { r.vBefore[i] = v[i]; r.dv[i] = clampDv(r.target[i] - v[i]); }
    if (!readDeep(body, deep, &r.mass, &back) || !(r.mass > 100.0f) || !readForce(body, cur)) {
        r.why = "not applied: mass or force unreadable";
        g_seamResult = r; g_seamResultReady = true;
        return;
    }
    if (writeForceXYZ(body, cur[0] + r.mass * r.dv[0], cur[1] + r.mass * r.dv[1], cur[2] + r.mass * r.dv[2])) {
        g_writes.fetch_add(1, std::memory_order_relaxed);
        r.applied = true;
        r.why = "applied";
        g_seamPending = r;
        g_seamFramesSince = 0;
    } else {
        g_writeFaults.fetch_add(1, std::memory_order_relaxed);
        g_writesEnabled.store(false, std::memory_order_relaxed);
        r.why = "write fault: writes disabled for the session";
        g_seamResult = r; g_seamResultReady = true;
    }
}

/// The fraction of drive authority left at this speed. 1.0 well below the target, 0.0 at or past it.
float governorAt(float speedMps) noexcept
{
    const float target = g_topSpeedMps.load(std::memory_order_relaxed);
    if (!(target >= kMinGovernedMps)) return 1.0f;          // absent, zero or NaN -- no governor
    if (speedMps >= target) return 0.0f;
    const float taperStart = target * (1.0f - kTopSpeedTaper);
    if (speedMps <= taperStart) return 1.0f;
    const float span = target - taperStart;
    if (!(span > 0.0f)) return 0.0f;
    const float left = (target - speedMps) / span;
    return left < 0.0f ? 0.0f : (left > 1.0f ? 1.0f : left);
}

// ---------------------------------------------------------------------------------------------------
// WHO OWNS THE THREE LEVERS (`L152`)
// ---------------------------------------------------------------------------------------------------
//
// Two writers now want these: `ncm_carrier.json`, re-read once a second, and the server's composed Parts
// setup arriving over the bridge. **Two writers on one value is not a design** -- a driver would fit an
// engine, feel it, and lose it a second later when the config loop wrote 1.0 back over the top.
//
// So the setup takes ownership on arrival and keeps it for the session, or until the bridge drops. The
// config file remains exactly what it has been: the bench-test path, for an A/B you can do in seconds
// while nothing is publishing. It is not silently ignored -- the config loop says so, once.
std::atomic<bool> g_handlingOwns{false};
std::atomic<uint32_t> g_handlingApplied{0};
std::atomic<bool> g_handlingNoticed{false};   // so "config ignored" is logged once, not 3600 times an hour
std::atomic<float> g_rollBias{0.0f};

/// A wheel entry's horizontal pair is the geometric projection of its own normal load -- proven, by the
/// ratio holding constant across all four corners in every sample. So a load shift scales all three
/// components together; scaling Z alone would leave the projection describing a load that is no longer
/// there.
bool writeForceXYZ(void* body, float fx, float fy, float fz) noexcept
{
    __try {
        auto* f = reinterpret_cast<float*>(reinterpret_cast<uint8_t*>(body) + kOffForce);
        f[0] = fx;
        f[1] = fy;
        f[2] = fz;
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}

/// The body's angular velocity (world rad/s, `+0x24`), guarded like every access. 2026-10-12: the AV's torque channel.
bool readSpin(const void* body, float* outXyz) noexcept
{
    __try {
        const auto* w = reinterpret_cast<const float*>(reinterpret_cast<const uint8_t*>(body) + kOffAngularVelocity);
        outXyz[0] = w[0]; outXyz[1] = w[1]; outXyz[2] = w[2];
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}

bool writeSpin(void* body, const float* xyz) noexcept
{
    if (!(xyz[0] == xyz[0]) || !(xyz[1] == xyz[1]) || !(xyz[2] == xyz[2])) return false;
    __try {
        auto* w = reinterpret_cast<float*>(reinterpret_cast<uint8_t*>(body) + kOffAngularVelocity);
        w[0] = xyz[0]; w[1] = xyz[1]; w[2] = xyz[2];
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}

void noteMax(std::atomic<float>& slot, float value)
{
    float seen = slot.load(std::memory_order_relaxed);
    while (value > seen && !slot.compare_exchange_weak(seen, value, std::memory_order_relaxed)) {}
}

std::thread g_reporter;
std::atomic<bool> g_reporterRunning{false};
std::mutex g_reporterMutex;
std::condition_variable g_reporterWake;

// --------------------------------------------------------------------------------------- guarded reads
//
// SEH, not C++ exceptions: an access violation in game memory is not a C++ throw and `catch (...)` will
// not see it. These two functions hold no object with a destructor so that `__try` is legal in them.

/// Shallow: velocity only, at a low offset that any rigid body plausibly has. Runs on every call.
bool readVelocity(const void* body, float* outXyz) noexcept
{
    __try {
        const auto* v = reinterpret_cast<const float*>(reinterpret_cast<const uint8_t*>(body) + kOffVelocity);
        outXyz[0] = v[0];
        outXyz[1] = v[1];
        outXyz[2] = v[2];
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}

/// Read the only native identity join used by handling. A physics body points at its owning
/// `vehicle::BaseObject`; that object inherits `ent::Entity::entityID`. Both reads remain under SEH because
/// Recalculate also receives non-vehicle/short rigid bodies. A miss is ordinary and never disables the
/// diagnostic probe.
bool readOwnerIdentity(const void* body, uintptr_t* outVehicle, uint64_t* outEntityId) noexcept
{
    __try {
        const auto* base = reinterpret_cast<const uint8_t*>(body);
        const auto vehicle = *reinterpret_cast<const uintptr_t*>(base + kOffVehicleBackPtr);
        if (vehicle < 0x10000 || (vehicle & 0x7) != 0) return false;
        const auto entityId = *reinterpret_cast<const uint64_t*>(vehicle + kOffEntityID);
        if (entityId == 0) return false;
        *outVehicle = vehicle;
        *outEntityId = entityId;
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}

/// Deep: force, mass and the vehicle back-pointer. Only for a body that has already read shallowly and has
/// then become the fastest thing we have seen this second.
bool readDeep(const void* body, float* outForceXyz, float* outMass, uintptr_t* outBackPtr) noexcept
{
    __try {
        const auto* base = reinterpret_cast<const uint8_t*>(body);
        const auto* f = reinterpret_cast<const float*>(base + kOffForce);
        outForceXyz[0] = f[0];
        outForceXyz[1] = f[1];
        outForceXyz[2] = f[2];
        *outMass = *reinterpret_cast<const float*>(base + kOffTotalMass);
        *outBackPtr = *reinterpret_cast<const uintptr_t*>(base + kOffVehicleBackPtr);
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}

/// Angular velocity and orientation. Read with the rest of the deep block, so they cost nothing extra.
bool readAttitude(const void* body, float* outAngular, float* outQuat) noexcept
{
    __try {
        const auto* base = reinterpret_cast<const uint8_t*>(body);
        const auto* w = reinterpret_cast<const float*>(base + kOffAngularVelocity);
        const auto* q = reinterpret_cast<const float*>(base + kOffOrientation);
        outAngular[0] = w[0]; outAngular[1] = w[1]; outAngular[2] = w[2];
        outQuat[0] = q[0]; outQuat[1] = q[1]; outQuat[2] = q[2]; outQuat[3] = q[3];
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}

/// The torque candidate at `+0x0C`. Strictly read-only.
bool readTorqueCandidate(const void* body, float* outXyz) noexcept
{
    __try {
        const auto* t = reinterpret_cast<const float*>(
            reinterpret_cast<const uint8_t*>(body) + kOffTorqueCandidate);
        outXyz[0] = t[0]; outXyz[1] = t[1]; outXyz[2] = t[2];
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}

/// Throttle, brake and steer as the physics step sees them. Read only.
bool readInputs(const void* vehicle, float* outThrottleBrakeSteer) noexcept
{
    __try {
        const auto* base = reinterpret_cast<const uint8_t*>(vehicle);
        outThrottleBrakeSteer[0] = *reinterpret_cast<const float*>(base + kOffInThrottle);
        outThrottleBrakeSteer[1] = *reinterpret_cast<const float*>(base + kOffInBrake);
        outThrottleBrakeSteer[2] = *reinterpret_cast<const float*>(base + kOffInSteer);
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}

/// Force alone, at the lowest offset there is. Read on every call for the tracked body, so it stays as
/// small as a guarded read can be.
bool readForce(const void* body, float* outForceXyz) noexcept
{
    __try {
        const auto* f = reinterpret_cast<const float*>(reinterpret_cast<const uint8_t*>(body) + kOffForce);
        outForceXyz[0] = f[0];
        outForceXyz[1] = f[1];
        outForceXyz[2] = f[2];
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}

// ------------------------------------------------------------------------------------ span cache
//
// `VirtualQuery` is a kernel transition, and 0.1.11 called it up to TWICE PER DEEP READ while deep reads
// fired on every new speed record -- which during acceleration is very nearly every call. Physics kept its
// ~55 Hz but the render thread was starved down to about 15 fps. The span for a given pointer does not
// change while that object lives, so validate once per pointer and remember the answer.
std::atomic<uintptr_t> g_spanCheckedBody{0};
std::atomic<bool> g_spanBodyOk{false};
std::atomic<uintptr_t> g_spanCheckedVehicle{0};
std::atomic<bool> g_spanVehicleOk{false};

/// Is this address committed and readable for the whole span we intend to touch? One VirtualQuery, done
/// only before a deep read, never on the hot path.
bool spanIsReadable(const void* address, size_t bytes) noexcept
{
    MEMORY_BASIC_INFORMATION mbi{};
    if (VirtualQuery(address, &mbi, sizeof(mbi)) == 0) return false;
    if (mbi.State != MEM_COMMIT) return false;
    constexpr DWORD kNoRead = PAGE_NOACCESS | PAGE_GUARD;
    if (mbi.Protect & kNoRead) return false;
    const auto start = reinterpret_cast<uintptr_t>(mbi.BaseAddress);
    const auto end = start + mbi.RegionSize;
    const auto want = reinterpret_cast<uintptr_t>(address) + bytes;
    return want <= end;
}

/// The same question, asked once per pointer. This is the fix for 0.1.11's frame-rate collapse.
bool spanIsReadableCached(const void* address, size_t bytes, std::atomic<uintptr_t>& cachedPtr,
                          std::atomic<bool>& cachedOk) noexcept
{
    const auto value = reinterpret_cast<uintptr_t>(address);
    if (cachedPtr.load(std::memory_order_relaxed) == value) {
        return cachedOk.load(std::memory_order_relaxed);
    }
    const bool ok = spanIsReadable(address, bytes);
    cachedOk.store(ok, std::memory_order_relaxed);
    cachedPtr.store(value, std::memory_order_relaxed);
    return ok;
}

// ------------------------------------------------------------------------- TEST 1 retry: find the quaternion
//
// `+0x30` was refuted outright: |q| read 0.002 to 0.085 where a unit quaternion must read 1.000. The LTBF
// layout is right about velocity (+0x18) and mass (+0x1BC), both verified, so the struct is not wholesale
// wrong -- the quaternion simply is not there on 2.31.
//
// So stop trusting the header and search, with the oracle method that has worked every time tonight: scan
// for four consecutive floats whose norm is 1.0, and count how often each candidate holds that property
// across many samples. A run of four floats that is unit-norm by coincidence will not stay unit-norm while
// the car turns; a quaternion will.
constexpr uint32_t kQuatScanBegin = 0x20;
constexpr uint32_t kQuatScanEnd = 0x180;   // stop before the back-pointer
constexpr uint32_t kQuatCandidates = (kQuatScanEnd - kQuatScanBegin) / 4;

std::atomic<uint32_t> g_quatHits[kQuatCandidates];
std::atomic<uint32_t> g_quatSamples{0};
std::atomic<bool> g_quatScanWanted{false};

// **PERSISTENCE ALONE WAS THE WRONG DISCRIMINATOR, AND 0.1.12 PROVED IT.** Eight offsets held unit norm
// in 100% of samples -- and a CONSTANT unit vector, or a row of an identity matrix, does that trivially.
// Those offsets sit exactly where LTBF puts the inertia tensors, which for a rigid body are constant.
// A quaternion is never constant while the car moves. So track the spread of each candidate's first
// component: constants collapse to zero range and eliminate themselves.
std::atomic<float> g_quatMin[kQuatCandidates];
std::atomic<float> g_quatMax[kQuatCandidates];

/// One pass over the candidate offsets. Rate-limited to once per second by the reporter, so its cost is
/// irrelevant next to the deep read it rides along with.
void scanForQuaternion(const void* body) noexcept
{
    __try {
        const auto* base = reinterpret_cast<const uint8_t*>(body);
        for (uint32_t i = 0; i < kQuatCandidates; ++i) {
            const auto* f = reinterpret_cast<const float*>(base + kQuatScanBegin + i * 4);
            const float norm = f[0] * f[0] + f[1] * f[1] + f[2] * f[2] + f[3] * f[3];
            if (norm > 0.98f && norm < 1.02f) {
                g_quatHits[i].fetch_add(1, std::memory_order_relaxed);
                if (f[0] < g_quatMin[i].load(std::memory_order_relaxed))
                    g_quatMin[i].store(f[0], std::memory_order_relaxed);
                if (f[0] > g_quatMax[i].load(std::memory_order_relaxed))
                    g_quatMax[i].store(f[0], std::memory_order_relaxed);
            }
        }
        g_quatSamples.fetch_add(1, std::memory_order_relaxed);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        // A short body: nothing to report, nothing to fix.
    }
}

void disableObservation(const char* why)
{
    if (g_observing.exchange(false)) {
        NCM_ERR("physics probe stopped observing: %s -- the detour stays in place and passes through", why);
    }
}

// --------------------------------------------------------------------------------------- the detour

void observe(void* body) noexcept
{
    if (!g_observing.load(std::memory_order_relaxed)) return;
    if (body == nullptr) return;
    const auto address = reinterpret_cast<uintptr_t>(body);
    if (address < 0x10000 || (address & 0x7) != 0) return;  // not a plausible heap object

    g_ticks.fetch_add(1, std::memory_order_relaxed);

    float vel[3];
    if (!readVelocity(body, vel)) {
        g_faults.fetch_add(1, std::memory_order_relaxed);
        disableObservation("an access violation on the shallow velocity read");
        return;
    }

    // Resolve and continuously validate the positive binding. While waiting, this costs two guarded
    // pointer reads per encountered body; once matched, only the bound body is revalidated. The expected
    // EntityID is stored last by applyHandling(), so seeing it means the complete setup is published.
    bool handlingAuthorised = false;
    uint64_t expectedEntity = g_expectedEngineEntity.load(std::memory_order_acquire);
    if (expectedEntity != 0 && monotonicMs() >= g_bindingExpiresAtMs.load(std::memory_order_acquire)) {
        // Lease expiry executes on the physics thread and therefore cannot wait for the 1 Hz reporter.
        // Atomics only: immediately disarm identity and levers; the reporter emits the human-readable line.
        g_expectedEngineEntity.store(0, std::memory_order_release);
        g_boundBody.store(0, std::memory_order_release);
        g_boundVehicle.store(0, std::memory_order_relaxed);
        g_gripScale.store(kGripScaleInert, std::memory_order_relaxed);
        g_driveScale.store(kGripScaleInert, std::memory_order_relaxed);
        g_brakeScale.store(kGripScaleInert, std::memory_order_relaxed);
        g_rollBias.store(0.0f, std::memory_order_relaxed);
        g_axleBias.store(0.0f, std::memory_order_relaxed);
        g_bindingLostPending.store(true, std::memory_order_release);
        expectedEntity = 0;
    }
    if (expectedEntity != 0) {
        const uintptr_t currentlyBound = g_boundBody.load(std::memory_order_relaxed);
        if (currentlyBound == 0 || currentlyBound == address) {
            uintptr_t owner = 0;
            uint64_t entityId = 0;
            const bool read = readOwnerIdentity(body, &owner, &entityId);
            if (read && entityId == expectedEntity &&
                g_expectedEngineEntity.load(std::memory_order_acquire) == expectedEntity) {
                if (currentlyBound == 0) {
                    uintptr_t none = 0;
                    if (g_boundBody.compare_exchange_strong(none, address, std::memory_order_acq_rel)) {
                        g_boundVehicle.store(owner, std::memory_order_relaxed);
                        // Keep the diagnostic classifier on the positively identified body too. This does
                        // not grant authority; the gate below still does that independently.
                        g_trackedBody.store(address, std::memory_order_relaxed);
                        g_bindingMatchedPending.store(true, std::memory_order_release);
                    }
                }
                handlingAuthorised = g_boundBody.load(std::memory_order_acquire) == address;
                if (handlingAuthorised) g_boundTickMs.store(monotonicMs(), std::memory_order_relaxed);
            } else if (currentlyBound == address) {
                uintptr_t stale = address;
                if (g_boundBody.compare_exchange_strong(stale, 0, std::memory_order_acq_rel)) {
                    g_boundVehicle.store(0, std::memory_order_relaxed);
                    g_bindingLostPending.store(true, std::memory_order_release);
                }
            }
        }
    }

    // Distinct-body count for this window.
    const uint64_t stamp = (static_cast<uint64_t>(g_generation.load(std::memory_order_relaxed)) << 48) ^ address;
    const size_t slot = static_cast<size_t>((address >> 4) % kBodyTableSize);
    if (g_bodySlotStamp[slot].exchange(stamp, std::memory_order_relaxed) != stamp) {
        g_distinctThisWindow.fetch_add(1, std::memory_order_relaxed);
    }

    // Cycle tracking, before the fastest-body bookkeeping so consecutive calls stay consecutive. Only for
    // the latched vehicle: every other body in the world would scramble the slot numbering.
    if (g_trackedBody.load(std::memory_order_relaxed) == address) {
        const bool diagnostics = g_diagnostics.load(std::memory_order_relaxed);
        if (diagnostics && !t_threadCounted) {
            t_threadCounted = true;
            g_threadsSeen.fetch_add(1, std::memory_order_relaxed);
        }

        float force[3];
        if (readForce(body, force)) {
            const Kind kind = classify(force);

            // Every contributor, regardless of kind, into the budget. This is the whole point of Test 2:
            // if we only counted the ones we recognise, a closure check would be circular.
            //
            // **ROUNDED, AND AT A MILLION.** 0.1.11 truncated toward zero at hundredths, across ~50,000
            // accumulations a second. Truncation toward zero biases a mixed-sign sum DOWNWARD, by an
            // amount of the same order as the signal -- which is exactly the direction that run's 0.10-0.20
            // ratio went. That was a measurement artefact, not a finding about the engine.
            if (diagnostics) {
                g_impulseSumX.fetch_add(std::llround(static_cast<double>(force[0]) * kImpulseScale),
                                        std::memory_order_relaxed);
                g_impulseSumY.fetch_add(std::llround(static_cast<double>(force[1]) * kImpulseScale),
                                        std::memory_order_relaxed);
                g_impulseSumZ.fetch_add(std::llround(static_cast<double>(force[2]) * kImpulseScale),
                                        std::memory_order_relaxed);
            }

            // The lift lever (L316 F0) acts on the gravity entry, so it is served before the diagnostics gate below.
            if (kind == Kind::Gravity) {
                thrustAtGravity(body, force, handlingAuthorised);
                wrenchAtGravity(body, force, handlingAuthorised);
                seamAtGravity(body, handlingAuthorised);
            }

            // With diagnostics off, only horizontal and wheel entries matter -- the two the writes touch.
            if (!diagnostics && kind != Kind::Horizontal && kind != Kind::Wheel) return;

            // A run of consecutive wheel calls ends the moment anything else arrives. Closing it here,
            // rather than counting to four, is what makes a short run visible instead of silently
            // merging into the next group.
            if (kind != Kind::Wheel && t_wheelRun > 0) {
                if (t_wheelRun == kWheelCount) {
                    g_runsComplete.fetch_add(1, std::memory_order_relaxed);
                    // Axle totals for the next run's load shift. One frame stale by construction.
                    g_axleFrontSum.store(t_wheelZ[0] + t_wheelZ[1], std::memory_order_relaxed);
                    g_axleRearSum.store(t_wheelZ[2] + t_wheelZ[3], std::memory_order_relaxed);
                    // Corner ordering is a RING -- FL, FR, RR, RL -- proven across two cars in §AU3, so
                    // left is 0+3 and right is 1+2. Row-major intuition gets this wrong, which is exactly
                    // the mistake the ring ordering was established to prevent.
                    g_leftSum.store(t_wheelZ[0] + t_wheelZ[3], std::memory_order_relaxed);
                    g_rightSum.store(t_wheelZ[1] + t_wheelZ[2], std::memory_order_relaxed);
                    for (uint32_t w = 0; w < kWheelCount; ++w) {
                        g_cornerZ[w].store(t_wheelZ[w], std::memory_order_relaxed);
                        g_cornerXY[w].store(t_wheelXY[w], std::memory_order_relaxed);
                        noteMax(g_cornerXYMax[w], t_wheelXY[w]);
                        if (t_wheelZ[w] < g_wheelMin[w].load(std::memory_order_relaxed))
                            g_wheelMin[w].store(t_wheelZ[w], std::memory_order_relaxed);
                        if (t_wheelZ[w] > g_wheelMax[w].load(std::memory_order_relaxed))
                            g_wheelMax[w].store(t_wheelZ[w], std::memory_order_relaxed);
                    }
                } else if (t_wheelRun < kWheelCount) {
                    g_runsShort.fetch_add(1, std::memory_order_relaxed);
                } else {
                    g_runsLong.fetch_add(1, std::memory_order_relaxed);
                }
                t_wheelRun = 0;
            }

            // Every call: track the frame's peak |torque_z|. Read-only.
            {
                float tqAny[3];
                if (readTorqueCandidate(body, tqAny)) {
                    const int64_t signed1000 = static_cast<int64_t>(std::llround(tqAny[2] * 1000.0));
                    const int64_t abs1000 = signed1000 < 0 ? -signed1000 : signed1000;
                    int64_t seen = g_tqFrameMaxAbs.load(std::memory_order_relaxed);
                    while (abs1000 > seen &&
                           !g_tqFrameMaxAbs.compare_exchange_weak(seen, abs1000,
                                                                  std::memory_order_relaxed)) {}
                    if (abs1000 >= seen) g_tqFrameSigned.store(signed1000, std::memory_order_relaxed);
                }
            }

            switch (kind) {
                case Kind::Gravity: {
                    g_cntGravity.fetch_add(1, std::memory_order_relaxed);
                    g_lastGravity.store(force[2], std::memory_order_relaxed);

                    // The gravity entry is the frame BOUNDARY, not the sample. Close out the frame that
                    // just ended: take its peak, add it to the window, then reset for the new frame.
                    const int64_t frameTotal = g_tqFrameSigned.exchange(0, std::memory_order_relaxed);
                    g_tqFrameMaxAbs.store(0, std::memory_order_relaxed);

                    float om[3], q[4];
                    if (readAttitude(body, om, q)) {
                        g_tqFrames.fetch_add(1, std::memory_order_relaxed);
                        g_tqSumZ.fetch_add(frameTotal, std::memory_order_relaxed);
                        if (!g_tqHaveFirst.exchange(true, std::memory_order_relaxed))
                            g_tqOmegaFirst.store(om[2], std::memory_order_relaxed);
                        g_tqOmegaLast.store(om[2], std::memory_order_relaxed);
                    }
                    break;
                }
                case Kind::Wheel: {
                    g_cntWheel.fetch_add(1, std::memory_order_relaxed);
                    const uint32_t corner = t_wheelRun;
                    if (corner < kWheelCount) {
                        t_wheelZ[corner] = force[2];
                        t_wheelXY[corner] =
                            std::sqrt(force[0] * force[0] + force[1] * force[1]);
                    }
                    ++t_wheelRun;

                    // --------------------------------------------- normal-load redistribution, two axes
                    //
                    // Front/rear (`axleLoadBias`, §AV2 -- NEGATIVE for grip) and left/right (`rollBias`,
                    // never tested). Both zero-sum, so the four corners still sum to the negation of
                    // gravity and the residual line stays the built-in check that they do.
                    //
                    // The two multiply rather than being applied in sequence, so a car can be asked for
                    // front bias AND left bias at once and the arithmetic stays one write per entry.
                    const float bias = g_axleBias.load(std::memory_order_relaxed);
                    const float roll = g_rollBias.load(std::memory_order_relaxed);
                    const bool wantAxle = std::fabs(bias) > kGripScaleEpsilon;
                    const bool wantRoll = std::fabs(roll) > kGripScaleEpsilon;
                    if (handlingAuthorised && corner < kWheelCount &&
                        g_writesEnabled.load(std::memory_order_relaxed) &&
                        (wantAxle || wantRoll)) {
                        const float front = g_axleFrontSum.load(std::memory_order_relaxed);
                        const float rear = g_axleRearSum.load(std::memory_order_relaxed);
                        const float left = g_leftSum.load(std::memory_order_relaxed);
                        const float right = g_rightSum.load(std::memory_order_relaxed);
                        // No totals yet, or a car in the air: no basis to size the shift from.
                        const bool axleOk = front > 1.0f && rear > 1.0f;
                        const bool rollOk = left > 1.0f && right > 1.0f;
                        if ((wantAxle ? axleOk : true) && (wantRoll ? rollOk : true) &&
                            (axleOk || rollOk)) {
                            float scale = 1.0f;
                            if (wantAxle && axleOk) {
                                // Front gains bias x front; rear must lose exactly that, which is a
                                // different multiplier because the axles do not carry equal load (~60/40).
                                if (corner < 2) {
                                    scale *= 1.0f + bias;
                                } else {
                                    float rearScale = 1.0f - (bias * front) / rear;
                                    if (rearScale < kRearScaleFloor) rearScale = kRearScaleFloor;
                                    scale *= rearScale;
                                }
                            }
                            if (wantRoll && rollOk) {
                                // Left is corners 0 and 3; right is 1 and 2. Same zero-sum arithmetic
                                // against the side totals rather than the axle totals.
                                const bool isLeft = (corner == 0 || corner == 3);
                                if (isLeft) {
                                    scale *= 1.0f + roll;
                                } else {
                                    float rightScale = 1.0f - (roll * left) / right;
                                    if (rightScale < kRearScaleFloor) rightScale = kRearScaleFloor;
                                    scale *= rightScale;
                                }
                            }
                            if (writeForceXYZ(body, force[0] * scale, force[1] * scale,
                                              force[2] * scale)) {
                                g_writes.fetch_add(1, std::memory_order_relaxed);
                            } else {
                                g_writeFaults.fetch_add(1, std::memory_order_relaxed);
                                g_writesEnabled.store(false, std::memory_order_relaxed);
                            }
                        }
                    }
                    break;
                }
                case Kind::Horizontal: {
                    g_cntHorizontal.fetch_add(1, std::memory_order_relaxed);
                    const float magnitude = std::sqrt(force[0] * force[0] + force[1] * force[1]);
                    const auto hundredths = static_cast<uint32_t>(magnitude * 100.0f);
                    g_horizMagSum.fetch_add(hundredths, std::memory_order_relaxed);
                    notePeak(g_horizMagMax, hundredths);

                    // Decompose against the direction of travel. Below walking pace "forward" is not a
                    // direction, so those are counted apart rather than folded in against a meaningless
                    // axis -- absent and zero are different claims here as everywhere else.
                    const float speedSq = vel[0] * vel[0] + vel[1] * vel[1];
                    if (speedSq < kMinSpeedForDirection * kMinSpeedForDirection) {
                        g_horizUndirected.fetch_add(1, std::memory_order_relaxed);
                        // ------------------------------------------------- the standstill branch (0.1.16)
                        // **Recovered from the owner's March 2026 anti-crawl work, which handled this and
                        // 0.1.15 did not.** Below walking pace "along travel" has no meaning, so 0.1.15
                        // bailed out entirely -- leaving `driveScale` inert under ~1.8 km/h. That is
                        // precisely the regime the March fix existed for: each gear applies continuous
                        // forward force down to a gear-dependent floor, so a car in 2nd would not drop
                        // below ~21 km/h however hard it was braked. A power lever that switches itself off
                        // at creep cannot express that.
                        //
                        // With no direction to decompose against, the March code scaled the whole
                        // horizontal vector and so does this. It is the conservative choice: at a true
                        // standstill there is no lateral component to protect.
                        float gbDrive = 1.0f, gbCeiling = 0.0f;
                        const bool gbStill = gearboxLevers(monotonicMs(), gbDrive, gbCeiling);
                        // a manual in neutral (or mid-shift) does not creep away from a standstill either --
                        // but ONLY while the throttle may be pressed (0.1.32, owner QA 2026-10-04: "some weird
                        // rotation of car at neutral"). This branch scales the WHOLE horizontal vector, so
                        // neutral's 0 also erased the tyres' static hold: a stopped car in N had no grip at all
                        // and pivoted on anything. Off the throttle the force here is the tyres holding the car,
                        // not drive, so the gear leaves it alone. Fails closed: unread inputs keep the old cut.
                        const bool throttleOff = g_inputsOk.load(std::memory_order_relaxed) &&
                                                 std::fabs(g_inThrottle.load(std::memory_order_relaxed)) <= 0.02f;
                        const float gearShare = (gbStill && !throttleOff) ? gbDrive : 1.0f;
                        const float kCreep = g_driveScale.load(std::memory_order_relaxed) * gearShare;
                        if (handlingAuthorised && g_writesEnabled.load(std::memory_order_relaxed) &&
                            std::fabs(kCreep - kGripScaleInert) > kGripScaleEpsilon) {
                            if (writeForceXY(body, force[0] * kCreep, force[1] * kCreep)) {
                                g_writes.fetch_add(1, std::memory_order_relaxed);
                            } else {
                                g_writeFaults.fetch_add(1, std::memory_order_relaxed);
                                g_writesEnabled.store(false, std::memory_order_relaxed);
                            }
                        }
                        break;
                    }
                    const float inverse = 1.0f / std::sqrt(speedSq);
                    const float dirX = vel[0] * inverse, dirY = vel[1] * inverse;
                    const float longitudinal = force[0] * dirX + force[1] * dirY;
                    const float lateral = force[0] * -dirY + force[1] * dirX;

                    const auto longAbs = static_cast<uint32_t>(std::fabs(longitudinal) * 100.0f);
                    const auto latAbs = static_cast<uint32_t>(std::fabs(lateral) * 100.0f);
                    g_longAbsSum.fetch_add(longAbs, std::memory_order_relaxed);
                    g_longSignedSum.fetch_add(static_cast<int64_t>(longitudinal * 100.0f),
                                              std::memory_order_relaxed);
                    g_latAbsSum.fetch_add(latAbs, std::memory_order_relaxed);
                    notePeak(g_longPeak, longAbs);
                    notePeak(g_latPeak, latAbs);

                    // ------------------------------------------------------------------- THE WRITE
                    //
                    // Three levers on one decomposition. `gripScale` acts across travel; `driveScale` and
                    // `brakeScale` act along it, chosen by the SIGN of the longitudinal component -- which
                    // §AU4 established inverts under braking and even resolves a tapped throttle as
                    // alternating per-second signs, so the sign is a measured discriminator and not an
                    // assumption.
                    const float k = g_gripScale.load(std::memory_order_relaxed);
                    float gbDrive = 1.0f, gbCeiling = 0.0f;
                    const bool gb = gearboxLevers(monotonicMs(), gbDrive, gbCeiling);
                    const float kDrive = g_driveScale.load(std::memory_order_relaxed) * (gb ? gbDrive : 1.0f);
                    const float kBrake = g_brakeScale.load(std::memory_order_relaxed);
                    const bool wantGrip  = std::fabs(k - kGripScaleInert) > kGripScaleEpsilon;
                    const bool wantDrive = std::fabs(kDrive - kGripScaleInert) > kGripScaleEpsilon;
                    const bool wantBrake = std::fabs(kBrake - kGripScaleInert) > kGripScaleEpsilon;
                    const float kDrag = g_dragScale.load(std::memory_order_relaxed);
                    const bool wantDrag = std::fabs(kDrag - kGripScaleInert) > kGripScaleEpsilon;
                    // The governor is computed from the speed we already decomposed against, so it costs
                    // one square root that was going to happen anyway.
                    const float speedNow = std::sqrt(speedSq);
                    float governor = governorAt(speedNow);
                    if (gb && gbCeiling > 0.0f) {
                        const float limit = gearLimitAt(speedNow, gbCeiling);
                        if (limit < governor) governor = limit;
                    }
                    if (gb) g_gearboxApplied.fetch_add(1, std::memory_order_relaxed);
                    // **A governor at full authority is not a reason to write.** It only becomes one when
                    // it is actually withholding something, or the write path would engage on every frame
                    // of every governed car for no change at all.
                    const bool wantGovernor = governor < 1.0f;
                    if (handlingAuthorised && g_writesEnabled.load(std::memory_order_relaxed) &&
                        (wantGrip || wantDrive || wantBrake || wantDrag || wantGovernor)) {
                        const float scaledLateral = wantGrip ? lateral * k : lateral;
                        float scaledLong = longitudinal;
                        if (longitudinal > 0.0f) {
                            // Parts first, then the governor on top of them. Multiplication commutes, but
                            // the ORDER is the story: the driver's engine decides how hard the car pulls,
                            // and the governor decides how much of that pull survives at this speed.
                            float alongDrive = wantDrive ? kDrive : 1.0f;
                            if (wantGovernor) alongDrive *= governor;
                            scaledLong *= alongDrive;
                        } else {
                            // **Retarding force -- and which KIND decides which lever.** Drag and braking
                            // arrive here as the same negative number; only the pedal separates them.
                            // `coastingConfidently` answers false for every uncertainty, so an unknown or
                            // stale pedal keeps the brake lever and the car still stops.
                            //
                            // **The governor never touches retarding force**, of either kind. Scaling a
                            // brake by a top-speed term would make a car harder to stop the faster it
                            // went, which is the opposite of every intention here.
                            if (coastingConfidently(monotonicMs())) {
                                if (wantDrag) scaledLong *= kDrag;
                            } else if (wantBrake) {
                                scaledLong *= kBrake;
                            }
                        }
                        // long*dir + lat*perp, with perp = (-dirY, dirX). With every multiplier at 1 this
                        // is the vector we just took apart, put back together, identically.
                        const float newX = scaledLong * dirX + scaledLateral * -dirY;
                        const float newY = scaledLong * dirY + scaledLateral * dirX;
                        if (writeForceXY(body, newX, newY)) {
                            g_writes.fetch_add(1, std::memory_order_relaxed);
                        } else {
                            g_writeFaults.fetch_add(1, std::memory_order_relaxed);
                            g_writesEnabled.store(false, std::memory_order_relaxed);
                        }
                    }
                    break;
                }
                case Kind::Zero: g_cntZero.fetch_add(1, std::memory_order_relaxed); break;
                case Kind::Other: g_cntOther.fetch_add(1, std::memory_order_relaxed); break;
            }
        }
    }

    // Horizontal speed: Z is up in this engine and a falling body is not the interesting one.
    const float speedSq = vel[0] * vel[0] + vel[1] * vel[1];
    if (!std::isfinite(speedSq)) return;

    float best = g_bestSpeedSq.load(std::memory_order_relaxed);
    if (speedSq <= best) return;
    if (!g_bestSpeedSq.compare_exchange_strong(best, speedSq, std::memory_order_relaxed)) return;

    // This body is now the window's fastest, which is rare enough to afford the deep read.
    g_bestBody.store(address, std::memory_order_relaxed);
    g_bestVelX.store(vel[0], std::memory_order_relaxed);
    g_bestVelY.store(vel[1], std::memory_order_relaxed);
    g_bestVelZ.store(vel[2], std::memory_order_relaxed);

    // Rate-limited. Nothing the deep read produces is needed at contributor rate, and running it on every
    // speed record is what cost 0.1.11 its frame rate. One in sixteen gives roughly 60 Hz against the
    // observed ~1000 calls/s -- ample for telemetry, invisible in cost.
    if ((g_ticks.load(std::memory_order_relaxed) & 0xF) != 0) return;

    if (!spanIsReadableCached(body, kDeepestRead, g_spanCheckedBody, g_spanBodyOk)) {
        g_bestDeepOk.store(false, std::memory_order_relaxed);
        return;
    }

    float force[3] = {0.0f, 0.0f, 0.0f};
    float mass = 0.0f;
    uintptr_t back = 0;
    if (!readDeep(body, force, &mass, &back)) {
        g_deepFaults.fetch_add(1, std::memory_order_relaxed);
        g_bestDeepOk.store(false, std::memory_order_relaxed);
        return;  // NOT fatal to the probe: a short rigid body is an ordinary thing to meet
    }

    g_bestForceX.store(force[0], std::memory_order_relaxed);
    g_bestForceY.store(force[1], std::memory_order_relaxed);
    g_bestForceZ.store(force[2], std::memory_order_relaxed);
    g_bestMass.store(mass, std::memory_order_relaxed);
    g_bestBackPtr.store(back, std::memory_order_relaxed);
    g_bestDeepOk.store(true, std::memory_order_relaxed);

    // ------------------------------------------------------------- TEST 1, attitude and driver inputs
    float angular[3], quat[4];
    if (readAttitude(body, angular, quat)) {
        g_angVelX.store(angular[0], std::memory_order_relaxed);
        g_angVelY.store(angular[1], std::memory_order_relaxed);
        g_angVelZ.store(angular[2], std::memory_order_relaxed);
        g_quatX.store(quat[0], std::memory_order_relaxed);
        g_quatY.store(quat[1], std::memory_order_relaxed);
        g_quatZ.store(quat[2], std::memory_order_relaxed);
        g_quatW.store(quat[3], std::memory_order_relaxed);
        g_attitudeOk.store(true, std::memory_order_relaxed);
    } else {
        g_attitudeOk.store(false, std::memory_order_relaxed);
    }

    // ------------------------------------------------------ 0.1.16: the torque candidate at +0x0C
    // Read-only. Sampled at the same instant as angular velocity so the oracle below compares two
    // quantities from one moment rather than two -- the misaligned-sampling mistake KB-143 recorded.
    float torque[3];
    if (readTorqueCandidate(body, torque)) {
        g_torqueX.store(torque[0], std::memory_order_relaxed);
        g_torqueY.store(torque[1], std::memory_order_relaxed);
        g_torqueZ.store(torque[2], std::memory_order_relaxed);
        g_torqueOk.store(true, std::memory_order_relaxed);

        const auto tz = static_cast<int64_t>(std::llround(torque[2] * 1000.0));
        g_torqueSamples.fetch_add(1, std::memory_order_relaxed);
        g_torqueAbsSumZ.fetch_add(tz < 0 ? -tz : tz, std::memory_order_relaxed);

        int64_t lo = g_torqueMinZ.load(std::memory_order_relaxed);
        while (tz < lo && !g_torqueMinZ.compare_exchange_weak(lo, tz, std::memory_order_relaxed)) {}
        int64_t hi = g_torqueMaxZ.load(std::memory_order_relaxed);
        while (tz > hi && !g_torqueMaxZ.compare_exchange_weak(hi, tz, std::memory_order_relaxed)) {}

        // The oracle. For a rigid body, integrating torque_z over time gives I_zz * delta(omega_z), so the
        // implied yaw inertia must come out positive and roughly constant. A field that merely VARIES
        // proves nothing -- that was exactly the §AV3 trap.
        if (g_attitudeOk.load(std::memory_order_relaxed)) {
            if (!g_omegaZStarted.exchange(true, std::memory_order_relaxed)) {
                g_omegaZStart.store(static_cast<int64_t>(std::llround(angular[2] * 1000.0)),
                                    std::memory_order_relaxed);
            }
            // dt from the physics itself, not the OS clock: 1/60 is the measured frame time and the deep
            // read is rate-limited to 1-in-16, so this is an approximation whose only job is to keep the
            // implied inertia in a believable ORDER, not to be exact.
            g_torqueImpulseZ.fetch_add(tz / 60, std::memory_order_relaxed);

            const float steer = g_inSteer.load(std::memory_order_relaxed);
            if (std::fabs(steer) > 0.10f && std::fabs(torque[2]) > 1e-3f) {
                g_torqueSteerTotal.fetch_add(1, std::memory_order_relaxed);
                if ((steer > 0.0f) == (torque[2] > 0.0f))
                    g_torqueSteerAgree.fetch_add(1, std::memory_order_relaxed);
            }
        }
    } else {
        g_torqueOk.store(false, std::memory_order_relaxed);
    }

    // Velocity at a known instant, for the budget check. Same moment as everything else in this block.
    g_trackedVelX.store(vel[0], std::memory_order_relaxed);
    g_trackedVelY.store(vel[1], std::memory_order_relaxed);
    g_trackedVelZ.store(vel[2], std::memory_order_relaxed);
    g_trackedVelOk.store(true, std::memory_order_relaxed);

    // One scan pass per second, riding along with a deep read that is already happening.
    if (g_quatScanWanted.exchange(false, std::memory_order_relaxed)) {
        scanForQuaternion(body);
    }

    // The back-pointer is a vehicleBaseObject, a different and much larger object than this one, so its
    // span gets its own check rather than riding on the one above.
    auto* vehicle = reinterpret_cast<void*>(back);
    if (spanIsReadableCached(vehicle, kInputsDeepestRead, g_spanCheckedVehicle, g_spanVehicleOk)) {
        float inputs[3];
        if (readInputs(vehicle, inputs)) {
            g_inThrottle.store(inputs[0], std::memory_order_relaxed);
            g_inBrake.store(inputs[1], std::memory_order_relaxed);
            g_inSteer.store(inputs[2], std::memory_order_relaxed);
            g_inputsOk.store(true, std::memory_order_relaxed);

            // The regression, on the hot path, every sample. ~60 Hz rather than 1 Hz.
            const float steer = inputs[2];
            const float yaw = angular[2];
            const float speed = std::sqrt(vel[0] * vel[0] + vel[1] * vel[1]);
            if (std::fabs(steer) >= kMinSteerForRegression && speed >= kMinSpeedForRegression &&
                std::isfinite(yaw)) {
                uint32_t bin = 0;
                while (bin < kSpeedBins - 1 && speed >= kSpeedBinEdges[bin]) ++bin;
                g_regN[bin].fetch_add(1, std::memory_order_relaxed);
                g_regSteerYaw[bin].fetch_add(
                    std::llround(static_cast<double>(steer) * yaw * kRegressionScale),
                    std::memory_order_relaxed);
                g_regSteerSq[bin].fetch_add(
                    std::llround(static_cast<double>(steer) * steer * kRegressionScale),
                    std::memory_order_relaxed);
                g_regYawSq[bin].fetch_add(
                    std::llround(static_cast<double>(yaw) * yaw * kRegressionScale),
                    std::memory_order_relaxed);
            }
        }
    }

    // Latch this as THE vehicle once it reads like one: a car-shaped mass and a back-pointer to something.
    // Cycle tracking follows the latch, so slot numbering belongs to one body and not to whatever moved
    // fastest this second. Re-latching on a different body resets the numbering, which is correct.
    if (g_expectedEngineEntity.load(std::memory_order_relaxed) == 0 &&
        mass > 200.0f && mass < 10000.0f && back != 0 &&
        g_trackedBody.load(std::memory_order_relaxed) != address) {
        g_trackedBody.store(address, std::memory_order_relaxed);
        // Nothing else to reset: the classifier holds no state that belongs to a particular body, and
        // each thread's run counter closes itself on the next non-wheel call it sees.
    }
}

uint64_t __fastcall recalculateDetour(void* body)
{
    observe(body);
    // Pass rax through verbatim. The March build declared this `short`, which would truncate a wider
    // return; a 64-bit passthrough cannot lose anything the caller might read.
    return g_original(body);
}

// --------------------------------------------------------------------------------------- reporter

/// The classifier's own report card. Every count is per second and across every thread, so the physics
/// has to add up: at 60 fps we should see about 60 gravity calls, 240 wheel calls and 60 complete
/// four-wheel runs. Short or long runs mean the thread-local grouping is wrong somewhere; `other` means
/// the classifier met something it has no name for. None of it is inferred -- it is all counted.
void reportClassification(double speed)
{
    if (!g_diagnostics.load(std::memory_order_relaxed)) return;
    const uint32_t gravity = g_cntGravity.exchange(0, std::memory_order_relaxed);
    const uint32_t wheels = g_cntWheel.exchange(0, std::memory_order_relaxed);
    const uint32_t horizontal = g_cntHorizontal.exchange(0, std::memory_order_relaxed);
    const uint32_t zeros = g_cntZero.exchange(0, std::memory_order_relaxed);
    const uint32_t other = g_cntOther.exchange(0, std::memory_order_relaxed);
    const uint32_t complete = g_runsComplete.exchange(0, std::memory_order_relaxed);
    const uint32_t shortRuns = g_runsShort.exchange(0, std::memory_order_relaxed);
    const uint32_t longRuns = g_runsLong.exchange(0, std::memory_order_relaxed);

    // Staleness is a state, not a blank: 0.1.4 reprinted the last wheel loads for two and a half minutes
    // after the tracked body went quiet, which reads exactly like a car sitting still.
    if (gravity == 0 && wheels == 0) {
        if (g_trackedBody.load(std::memory_order_relaxed) != 0) {
            NCM_INFO("classify: no physics call for the tracked body this second (idle, despawned, or we "
                     "are no longer simulating it)");
        }
        return;
    }

    float z[kWheelCount], lo[kWheelCount], hi[kWheelCount];
    float sum = 0.0f;
    for (uint32_t w = 0; w < kWheelCount; ++w) {
        z[w] = g_cornerZ[w].load(std::memory_order_relaxed);
        lo[w] = g_wheelMin[w].exchange(FLT_MAX, std::memory_order_relaxed);
        hi[w] = g_wheelMax[w].exchange(-FLT_MAX, std::memory_order_relaxed);
        sum += z[w];
    }
    const float gravityZ = g_lastGravity.load(std::memory_order_relaxed);

    const uint32_t writes = g_writes.exchange(0, std::memory_order_relaxed);
    const float k = g_gripScale.load(std::memory_order_relaxed);
    NCM_INFO("classify: grav=%u wheel=%u horiz=%u zero=%u other=%u | runs %u complete, %u short, %u long "
             "| threads=%u | k=%.2f writes=%u/s%s",
             gravity, wheels, horizontal, zeros, other, complete, shortRuns, longRuns,
             g_threadsSeen.load(std::memory_order_relaxed), static_cast<double>(k), writes,
             g_writesEnabled.load(std::memory_order_relaxed) ? "" : " [WRITES DISABLED BY FAULT]");
    NCM_INFO("  corners z=[%.0f %.0f %.0f %.0f] min=[%.0f %.0f %.0f %.0f] max=[%.0f %.0f %.0f %.0f]"
             " | sum=%.0f grav=%.0f residual=%.1f v=%.1f",
             static_cast<double>(z[0]), static_cast<double>(z[1]), static_cast<double>(z[2]),
             static_cast<double>(z[3]),
             static_cast<double>(lo[0] == FLT_MAX ? 0.0f : lo[0]),
             static_cast<double>(lo[1] == FLT_MAX ? 0.0f : lo[1]),
             static_cast<double>(lo[2] == FLT_MAX ? 0.0f : lo[2]),
             static_cast<double>(lo[3] == FLT_MAX ? 0.0f : lo[3]),
             static_cast<double>(hi[0] == -FLT_MAX ? 0.0f : hi[0]),
             static_cast<double>(hi[1] == -FLT_MAX ? 0.0f : hi[1]),
             static_cast<double>(hi[2] == -FLT_MAX ? 0.0f : hi[2]),
             static_cast<double>(hi[3] == -FLT_MAX ? 0.0f : hi[3]),
             static_cast<double>(sum), static_cast<double>(gravityZ),
             static_cast<double>(sum + gravityZ), speed);

    // The friction question. Both candidates on one line so they can be compared at a glance against the
    // cornering the driver just did.
    float xy[kWheelCount], xyMax[kWheelCount];
    for (uint32_t w = 0; w < kWheelCount; ++w) {
        xy[w] = g_cornerXY[w].load(std::memory_order_relaxed);
        xyMax[w] = g_cornerXYMax[w].exchange(0.0f, std::memory_order_relaxed);
    }
    const uint64_t horizSum = g_horizMagSum.exchange(0, std::memory_order_relaxed);
    const uint32_t horizMax = g_horizMagMax.exchange(0, std::memory_order_relaxed);
    const double horizAvg = horizontal ? (static_cast<double>(horizSum) / 100.0) / horizontal : 0.0;

    NCM_INFO("  friction: wheelXY=[%.1f %.1f %.1f %.1f] peak=[%.1f %.1f %.1f %.1f] | horiz n=%u "
             "avg=%.1f peak=%.1f",
             static_cast<double>(xy[0]), static_cast<double>(xy[1]), static_cast<double>(xy[2]),
             static_cast<double>(xy[3]), static_cast<double>(xyMax[0]), static_cast<double>(xyMax[1]),
             static_cast<double>(xyMax[2]), static_cast<double>(xyMax[3]), horizontal, horizAvg,
             horizMax / 100.0);

    // The split the write depends on: thrust and drag along the direction of travel, grip across it.
    const uint64_t longAbs = g_longAbsSum.exchange(0, std::memory_order_relaxed);
    const int64_t longSigned = g_longSignedSum.exchange(0, std::memory_order_relaxed);
    const uint32_t longPeak = g_longPeak.exchange(0, std::memory_order_relaxed);
    const uint64_t latAbs = g_latAbsSum.exchange(0, std::memory_order_relaxed);
    const uint32_t latPeak = g_latPeak.exchange(0, std::memory_order_relaxed);
    const uint32_t undirected = g_horizUndirected.exchange(0, std::memory_order_relaxed);
    const uint32_t directed = horizontal > undirected ? horizontal - undirected : 0;

    // ------------------------------------------------------------- 0.1.16: the torque candidate verdict
    //
    // Three things have to hold together before `+0x0C` may be called torque, and any one of them failing
    // is the answer. This prints all three rather than a conclusion, so the verdict is readable from the
    // numbers instead of taken on trust.
    {
        const uint32_t n = g_torqueSamples.exchange(0, std::memory_order_relaxed);
        const int64_t absSum = g_torqueAbsSumZ.exchange(0, std::memory_order_relaxed);
        const int64_t lo = g_torqueMinZ.exchange(0, std::memory_order_relaxed);
        const int64_t hi = g_torqueMaxZ.exchange(0, std::memory_order_relaxed);
        const int64_t impulse = g_torqueImpulseZ.exchange(0, std::memory_order_relaxed);
        const int64_t agree = g_torqueSteerAgree.exchange(0, std::memory_order_relaxed);
        const int64_t total = g_torqueSteerTotal.exchange(0, std::memory_order_relaxed);
        g_omegaZStarted.store(false, std::memory_order_relaxed);

        if (n > 0) {
            const double meanAbs = static_cast<double>(absSum) / (1000.0 * n);
            const double spread = static_cast<double>(hi - lo) / 1000.0;
            const double omega0 = static_cast<double>(g_omegaZStart.load(std::memory_order_relaxed)) / 1000.0;
            const double omega1 = static_cast<double>(g_angVelZ.load(std::memory_order_relaxed));
            const double dOmega = omega1 - omega0;
            const double impulseZ = static_cast<double>(impulse) / 1000.0;
            // Implied yaw inertia. Only meaningful when omega actually moved; a near-zero denominator
            // produces a number that looks precise and means nothing, so it is withheld rather than shown.
            const bool inertiaMeaningful = std::fabs(dOmega) > 0.05;
            const double impliedIzz = inertiaMeaningful ? impulseZ / dOmega : 0.0;

            NCM_INFO("torque? +0x0C n=%u meanAbsZ=%.3f spread=%.3f | dOmegaZ=%+.3f impulseZ=%+.3f "
                     "impliedIzz=%s | steerSign %lld/%lld",
                     n, meanAbs, spread, dOmega, impulseZ,
                     inertiaMeaningful ? "see next" : "n/a (omega flat)",
                     static_cast<long long>(agree), static_cast<long long>(total));
            if (inertiaMeaningful) {
                NCM_INFO("  impliedIzz=%.1f kg.m2 %s", impliedIzz,
                         impliedIzz > 0.0 ? "(positive -- consistent with torque)"
                                          : "(NEGATIVE -- not a torque about this axis)");
            }
            if (spread < 1e-3) {
                NCM_WARN("  +0x0C is CONSTANT this window -- not an accumulator. Same trap as the §AV3 "
                         "quaternion, caught by variance rather than by persistence.");
            }
        } else if (g_torqueOk.load(std::memory_order_relaxed) == false) {
            NCM_INFO("torque? +0x0C unreadable this window");
        }
    }

    // ------------------------------------------------- 0.1.17: the frame-rate torque oracle
    {
        const uint32_t frames = g_tqFrames.exchange(0, std::memory_order_relaxed);
        const int64_t sumZ = g_tqSumZ.exchange(0, std::memory_order_relaxed);
        const float om0 = g_tqOmegaFirst.load(std::memory_order_relaxed);
        const float om1 = g_tqOmegaLast.load(std::memory_order_relaxed);
        g_tqHaveFirst.store(false, std::memory_order_relaxed);

        if (frames > 0) {
            // Each sample is exactly one physics frame, so the integral is the sum times the frame time.
            const double impulse = (static_cast<double>(sumZ) / 1000.0) / 60.0;
            const double dOmega = static_cast<double>(om1) - static_cast<double>(om0);
            // A near-zero denominator makes a precise-looking number that means nothing, so it is withheld.
            if (std::fabs(dOmega) > 0.05) {
                const double izz = impulse / dOmega;
                NCM_INFO("torqueIzz: frames=%u impulseZ=%+.3f dOmegaZ=%+.3f -> Izz=%+.1f %s",
                         frames, impulse, dOmega, izz,
                         izz > 0.0 ? "(positive)" : "(NEGATIVE)");
            } else {
                NCM_INFO("torqueIzz: frames=%u impulseZ=%+.3f dOmegaZ=%+.3f -> withheld (yaw flat)",
                         frames, impulse, dOmega);
            }
        }
    }

    // ------------------------------------------------------------------------ TEST 1: attitude report
    //
    // Which body axis is "forward" is MEASURED, not assumed: rotate each unit axis by the orientation and
    // report its alignment with the direction of travel. Driving straight, exactly one should read ~1.0,
    // and that one is forward. The same trick that proved velocity against the speedometer.
    if (g_attitudeOk.load(std::memory_order_relaxed)) {
        const float qx = g_quatX.load(std::memory_order_relaxed);
        const float qy = g_quatY.load(std::memory_order_relaxed);
        const float qz = g_quatZ.load(std::memory_order_relaxed);
        const float qw = g_quatW.load(std::memory_order_relaxed);
        const float vx = g_bestVelX.load(std::memory_order_relaxed);
        const float vy = g_bestVelY.load(std::memory_order_relaxed);
        const float planar = std::sqrt(vx * vx + vy * vy);

        auto rotate = [&](float ax, float ay, float az, float* out) {
            // v' = v + 2*cross(q.xyz, cross(q.xyz, v) + w*v)
            const float tx = qy * az - qz * ay + qw * ax;
            const float ty = qz * ax - qx * az + qw * ay;
            const float tz = qx * ay - qy * ax + qw * az;
            out[0] = ax + 2.0f * (qy * tz - qz * ty);
            out[1] = ay + 2.0f * (qz * tx - qx * tz);
            out[2] = az + 2.0f * (qx * ty - qy * tx);
        };
        float bx[3], by[3], bz[3];
        rotate(1, 0, 0, bx);
        rotate(0, 1, 0, by);
        rotate(0, 0, 1, bz);

        double dotX = 0.0, dotY = 0.0, dotZ = 0.0;
        if (planar > 1.0f) {
            const float nx = vx / planar, ny = vy / planar;
            dotX = bx[0] * nx + bx[1] * ny;
            dotY = by[0] * nx + by[1] * ny;
            dotZ = bz[0] * nx + bz[1] * ny;
        }
        const double norm = std::sqrt(static_cast<double>(qx * qx + qy * qy + qz * qz + qw * qw));
        NCM_INFO("  attitude: q=(%.3f %.3f %.3f %.3f) |q|=%.3f | angVel=(%.2f %.2f %.2f) rad/s | "
                 "axis-vs-travel X=%.2f Y=%.2f Z=%.2f",
                 static_cast<double>(qx), static_cast<double>(qy), static_cast<double>(qz),
                 static_cast<double>(qw), norm,
                 static_cast<double>(g_angVelX.load(std::memory_order_relaxed)),
                 static_cast<double>(g_angVelY.load(std::memory_order_relaxed)),
                 static_cast<double>(g_angVelZ.load(std::memory_order_relaxed)), dotX, dotY, dotZ);
    } else {
        NCM_WARN("  attitude: could not be read");
    }

    // ------------------------------------------------------- TEST 1 retry: quaternion candidate report
    //
    // Offsets that read unit-norm most of the time. Persistence is the discriminator: four floats that
    // happen to sum to 1.0 once will not keep doing it while the car turns.
    g_quatScanWanted.store(true, std::memory_order_relaxed);
    {
        const uint32_t samples = g_quatSamples.load(std::memory_order_relaxed);
        if (samples >= 5) {
            char line[512];
            int written = std::snprintf(line, sizeof(line), "  quat-scan: %u sample(s), unit-norm at", samples);
            int found = 0;
            for (uint32_t i = 0; i < kQuatCandidates && found < 8; ++i) {
                const uint32_t hits = g_quatHits[i].load(std::memory_order_relaxed);
                if (hits * 10 >= samples * 9) {   // unit-norm in at least 90% of samples
                    written += std::snprintf(line + written, sizeof(line) - static_cast<size_t>(written),
                                             " +0x%X(%u/%u)", kQuatScanBegin + i * 4, hits, samples);
                    ++found;
                    if (written < 0 || static_cast<size_t>(written) >= sizeof(line)) break;
                }
            }
            if (found == 0) {
                NCM_INFO("  quat-scan: %u sample(s), NO offset held unit norm -- no quaternion in "
                         "+0x%X..+0x%X", samples, kQuatScanBegin, kQuatScanEnd);
            } else {
                NCM_INFO("%s", line);
            }

            // The discriminator that 0.1.12 lacked: which unit-norm candidates actually MOVE. A constant
            // -- an identity matrix row, a fixed axis -- collapses to zero spread and rules itself out.
            char varying[512];
            int vw = std::snprintf(varying, sizeof(varying), "  quat-vary:");
            int varyingFound = 0;
            for (uint32_t i = 0; i < kQuatCandidates && varyingFound < 6; ++i) {
                const uint32_t hits = g_quatHits[i].load(std::memory_order_relaxed);
                if (hits * 10 < samples * 9) continue;
                const float spreadLo = g_quatMin[i].load(std::memory_order_relaxed);
                const float spreadHi = g_quatMax[i].load(std::memory_order_relaxed);
                if (spreadHi - spreadLo < 0.10f) continue;   // constant: not a quaternion
                vw += std::snprintf(varying + vw, sizeof(varying) - static_cast<size_t>(vw),
                                    " +0x%X[%.2f..%.2f]", kQuatScanBegin + i * 4,
                                    static_cast<double>(spreadLo), static_cast<double>(spreadHi));
                ++varyingFound;
                if (vw < 0 || static_cast<size_t>(vw) >= sizeof(varying)) break;
            }
            if (varyingFound == 0) {
                NCM_INFO("  quat-vary: every unit-norm candidate is CONSTANT -- none of them is an "
                         "orientation");
            } else {
                NCM_INFO("%s", varying);
            }
        }
    }

    // ------------------------------------------------------------------ TEST 3: measured yaw response
    //
    // Slope of yaw against steer, per speed band, accumulated across every sample since the bias last
    // changed. `r` is the correlation: a slope with low r is arithmetic, not a relationship.
    {
        char line[512];
        int written = std::snprintf(line, sizeof(line), "  yawgain: bias=%+.2f",
                                    static_cast<double>(g_axleBias.load(std::memory_order_relaxed)));
        for (uint32_t b = 0; b < kSpeedBins; ++b) {
            const uint32_t n = g_regN[b].load(std::memory_order_relaxed);
            const double sy = static_cast<double>(g_regSteerYaw[b].load(std::memory_order_relaxed));
            const double ss = static_cast<double>(g_regSteerSq[b].load(std::memory_order_relaxed));
            const double yy = static_cast<double>(g_regYawSq[b].load(std::memory_order_relaxed));
            const double slope = ss > 0.0 ? sy / ss : 0.0;
            const double r = (ss > 0.0 && yy > 0.0) ? sy / std::sqrt(ss * yy) : 0.0;
            const char* band = (b == 0) ? "slow" : (b == 1 ? "mid" : "fast");
            written += std::snprintf(line + written, sizeof(line) - static_cast<size_t>(written),
                                     " | %s n=%u slope=%+.3f r=%+.2f", band, n, slope, r);
            if (written < 0 || static_cast<size_t>(written) >= sizeof(line)) break;
        }
        NCM_INFO("%s", line);
    }

    // ------------------------------------------------------------------ TEST 2: force budget closure
    //
    // Sum(impulse)/mass against the measured change in velocity over the same window. At rest both should
    // be ~0, because the wheels already cancel gravity.
    {
        static float lastVx = 0.0f, lastVy = 0.0f, lastVz = 0.0f;
        static bool havePrevious = false;

        const double sx =
            static_cast<double>(g_impulseSumX.exchange(0, std::memory_order_relaxed)) / kImpulseScale;
        const double sy =
            static_cast<double>(g_impulseSumY.exchange(0, std::memory_order_relaxed)) / kImpulseScale;
        const double sz =
            static_cast<double>(g_impulseSumZ.exchange(0, std::memory_order_relaxed)) / kImpulseScale;
        const float vx = g_trackedVelX.load(std::memory_order_relaxed);
        const float vy = g_trackedVelY.load(std::memory_order_relaxed);
        const float vz = g_trackedVelZ.load(std::memory_order_relaxed);
        const float mass = g_bestMass.load(std::memory_order_relaxed);

        if (havePrevious && mass > 1.0f && g_trackedVelOk.load(std::memory_order_relaxed)) {
            const double px = sx / mass, py = sy / mass, pz = sz / mass;
            const double mx = vx - lastVx, my = vy - lastVy, mz = vz - lastVz;
            const double predicted = std::sqrt(px * px + py * py + pz * pz);
            const double measured = std::sqrt(mx * mx + my * my + mz * mz);
            NCM_INFO("  budget: predicted dV=(%.2f %.2f %.2f)|%.2f  measured dV=(%.2f %.2f %.2f)|%.2f  "
                     "ratio=%.2f", px, py, pz, predicted, mx, my, mz, measured,
                     measured > 0.01 ? predicted / measured : 0.0);
        }
        lastVx = vx; lastVy = vy; lastVz = vz;
        havePrevious = true;
    }

    if (g_inputsOk.load(std::memory_order_relaxed)) {
        NCM_INFO("  inputs: throttle=%.2f brake=%.2f steer=%+.2f | axleBias=%+.2f front=%.0f rear=%.0f",
                 static_cast<double>(g_inThrottle.load(std::memory_order_relaxed)),
                 static_cast<double>(g_inBrake.load(std::memory_order_relaxed)),
                 static_cast<double>(g_inSteer.load(std::memory_order_relaxed)),
                 static_cast<double>(g_axleBias.load(std::memory_order_relaxed)),
                 static_cast<double>(g_axleFrontSum.load(std::memory_order_relaxed)),
                 static_cast<double>(g_axleRearSum.load(std::memory_order_relaxed)));
    }

    if (directed > 0) {
        NCM_INFO("  horiz: %u directed, %u undirected | long avg=%.1f peak=%.1f net=%+.1f "
                 "| lat avg=%.1f peak=%.1f",
                 directed, undirected, (static_cast<double>(longAbs) / 100.0) / directed,
                 longPeak / 100.0, (static_cast<double>(longSigned) / 100.0) / directed,
                 (static_cast<double>(latAbs) / 100.0) / directed, latPeak / 100.0);
    } else if (undirected > 0) {
        NCM_INFO("  horiz: %u entr(ies), all below walking pace -- no direction to decompose against",
                 undirected);
    }
}

/// The lift lever's report: found, refused, and one measured line per burn (predicted beside measured).
void reportThrust()
{
    if (g_thrustFoundPending.exchange(false, std::memory_order_acq_rel))
        NCM_INFO("thrust: NCM Thrust lift lever found -- a burn lifts the bound, seated car by its thrust-to-weight ratio");
    ThrustResult results[kThrustResults];
    uint32_t count = 0, dropped = 0, refusals = 0;
    {
        std::lock_guard<std::mutex> lock(g_thrustMutex);
        count = g_thrustResultCount;
        for (uint32_t i = 0; i < count; ++i) results[i] = g_thrustResults[i];
        g_thrustResultCount = 0;
        dropped = g_thrustResultsDropped;
        g_thrustResultsDropped = 0;
        refusals = g_thrustRefusals;
        g_thrustRefusals = 0;
    }
    if (refusals)
        NCM_WARN("thrust: burn requested but NOT applied (%u frame(s)): no bound NCM car is seated, or writes are disabled",
                 refusals);
    if (dropped) NCM_WARN("thrust: %u burn result(s) dropped this second (more than %u)", dropped, kThrustResults);
    for (uint32_t i = 0; i < count; ++i) {
        const ThrustResult& r = results[i];
        const float ratio = r.predRise > 0.001f ? r.maxRise / r.predRise : 0.0f;
        NCM_INFO("thrust: burn #%u%s twr=%.2f %u frame(s) %.3f s mass=%.0f kg | vz %+.2f -> peak %+.2f m/s (pred dv %.2f) | "
                 "rise %.3f m (pred %.3f, x%.2f) | faults=%u | ended: %s",
                 r.burnNo, r.hold ? " (hold)" : "", r.twr, r.frames, r.burnS, r.mass, r.vz0, r.peakVz, r.predVz,
                 r.maxRise, r.predRise, ratio, r.faults, r.why);
    }
}

/// The wrench's report (L324): one line a second while installed components pushed, measured, not requested.
void reportWrench()
{
    if (g_wrenchFirstPending.exchange(false, std::memory_order_acq_rel))
        NCM_INFO("wrench: installed components now drive the bound Machine (world force at the centre of mass; legacy lift parked while they do)");
    WrenchState snap;
    {
        std::lock_guard<std::mutex> lock(g_wrenchMutex);
        snap = g_wrench;
        g_wrench.frames = g_wrench.pulsesStarted = g_wrench.pulsesDropped = g_wrench.refusedUnbound = g_wrench.faults = 0;
        g_wrench.impulse[0] = g_wrench.impulse[1] = g_wrench.impulse[2] = 0.0;
        g_wrench.spinWrites = g_wrench.spinFaults = 0;
        g_wrench.activeS = 0.0;
    }
    const uint32_t refusedAsset = g_wrenchRefusedAsset.exchange(0, std::memory_order_relaxed);
    const uint32_t parked = g_liftSupersededPresses.exchange(0, std::memory_order_relaxed);
    if (refusedAsset) NCM_WARN("wrench: %u message(s) REFUSED -- assetId is not the bound Machine", refusedAsset);
    if (snap.refusedUnbound) NCM_WARN("wrench: %u frame(s) not applied -- no bound, seated car, or writes disabled", snap.refusedUnbound);
    if (parked) NCM_INFO("wrench: %u NCM Thrust press(es) ignored -- this Machine's installed components own its lift", parked);
    if (snap.frames == 0 && snap.pulsesStarted == 0) return;
    const double t = snap.activeS > 1e-6 ? snap.activeS : 1.0;
    const double imp = std::sqrt(snap.impulse[0] * snap.impulse[0] + snap.impulse[1] * snap.impulse[1] + snap.impulse[2] * snap.impulse[2]);
    NCM_INFO("wrench: %u frame(s) %.3f s mass=%.0f kg | impulse (%.0f, %.0f, %.0f) N s = mean (%.0f, %.0f, %.0f) N = %.2f m/s^2 | "
             "lease (%.0f, %.0f, %.0f) N | pulses %u started, %u dropped | faults=%u",
             snap.frames, snap.activeS, snap.mass, snap.impulse[0], snap.impulse[1], snap.impulse[2],
             snap.impulse[0] / t, snap.impulse[1] / t, snap.impulse[2] / t,
             snap.mass > 100.0f ? imp / t / snap.mass : 0.0,
             snap.lastSus[0], snap.lastSus[1], snap.lastSus[2], snap.pulsesStarted, snap.pulsesDropped, snap.faults);
    if (snap.av || snap.spinWrites || snap.spinFaults)
        NCM_INFO("wrench AV: Machine %.0f kg on a %.0f kg body (force x%.2f) | spin (%.2f, %.2f, %.2f) rad/s^2, %u write(s), %u fault(s)",
                 snap.ncmMass, snap.mass, (snap.ncmMass > 100.0f && snap.mass > 100.0f) ? snap.mass / snap.ncmMass : 1.0f,
                 snap.alpha[0], snap.alpha[1], snap.alpha[2], snap.spinWrites, snap.spinFaults);
}

/// The seam kick's report: found, and one measured line per kick (asked for, velocity before, velocity two entries after).
void reportSeam()
{
    if (g_seamFoundPending.exchange(false, std::memory_order_acq_rel))
        NCM_INFO("seam: NCM Snowglobe seam lever found -- a target velocity is restored once the car is bound again (m*dv, held up to 8 s)");
    SeamResult r{};
    bool ready = false;
    {
        std::lock_guard<std::mutex> lock(g_seamMutex);
        ready = g_seamResultReady;
        if (ready) { r = g_seamResult; g_seamResultReady = false; }
    }
    if (!ready) return;
    NCM_INFO("seam: target #%u %s after %u ms held | target (%.2f, %.2f, %.2f) m/s | v at the bind (%.2f, %.2f, %.2f) "
             "-> dv (%.2f, %.2f, %.2f), mass %.0f kg -> after (%.2f, %.2f, %.2f)",
             r.seq, r.why, r.heldMs, r.target[0], r.target[1], r.target[2], r.vBefore[0], r.vBefore[1], r.vBefore[2],
             r.dv[0], r.dv[1], r.dv[2], r.mass, r.vAfter[0], r.vAfter[1], r.vAfter[2]);
}

void reportOnce()
{
    reportThrust();
    reportWrench();
    reportSeam();
    // ------------------------------------------------------------------------------------- `KB-146`
    // The physics thread may bind, lose or expire a binding at any moment, and it cannot log: the detour
    // does no I/O by construction. It raises a flag; this is where that becomes a sentence.
    //
    // Reported BEFORE the early return below, because "0 calls this second" is exactly when a binding was
    // most likely lost, and that is the line someone will be looking for.
    if (g_bindingMatchedPending.exchange(false, std::memory_order_acq_rel)) {
        std::string asset, vehicle;
        {
            std::lock_guard<std::mutex> guard(g_bindingMetaMutex);
            asset = g_bindingAssetId;
            vehicle = g_bindingVehicleId;
        }
        NCM_INFO("handling: BOUND to body %p -- asset=%s vehicle=%s entity=%llu; forces now apply to this "
                 "Machine and no other",
                 reinterpret_cast<void*>(g_boundBody.load(std::memory_order_relaxed)),
                 asset.empty() ? "?" : asset.c_str(), vehicle.empty() ? "?" : vehicle.c_str(),
                 static_cast<unsigned long long>(g_expectedEngineEntity.load(std::memory_order_relaxed)));
    }
    if (g_bindingLostPending.exchange(false, std::memory_order_acq_rel)) {
        // Two causes, and they are worth telling apart: the identity stopped matching (the car despawned,
        // or the body was recycled), or the 2 s lease ran out because NCM stopped heartbeating. Either way
        // the levers are already inert -- the physics thread did that itself rather than waiting for us.
        const bool armed = g_expectedEngineEntity.load(std::memory_order_relaxed) != 0;
        NCM_WARN("handling: UNBOUND (%s) -- levers inert until a body matches again",
                 armed ? "the bound body stopped matching" : "the binding lease expired");
    }

    static uint64_t lastTicks = 0;
    const uint64_t total = g_ticks.load(std::memory_order_relaxed);
    const uint64_t delta = total - lastTicks;
    lastTicks = total;

    const uint32_t distinct = g_distinctThisWindow.exchange(0, std::memory_order_relaxed);
    g_generation.fetch_add(1, std::memory_order_relaxed);

    const float speedSq = g_bestSpeedSq.exchange(0.0f, std::memory_order_relaxed);
    if (delta == 0) {
        NCM_WARN("physics probe: attached but 0 call(s) in the last second (total %llu)",
                 static_cast<unsigned long long>(total));
        return;
    }

    const double speed = std::sqrt(static_cast<double>(speedSq));
    const double reported = g_reportedSpeed.load(std::memory_order_relaxed);
    const bool deep = g_bestDeepOk.load(std::memory_order_relaxed);

    char agreement[64];
    if (reported < 0.0) {
        std::snprintf(agreement, sizeof(agreement), "ncm=n/a");
    } else {
        std::snprintf(agreement, sizeof(agreement), "ncm=%.2f d=%+.2f", reported, speed - reported);
    }

    if (deep) {
        NCM_INFO("physics probe: %llu call(s)/s, %u bod(ies) | fastest %p v=%.2f m/s [%s] "
                 "mass=%.0f kg force=(%.0f,%.0f,%.0f) veh=%p",
                 static_cast<unsigned long long>(delta), distinct,
                 reinterpret_cast<void*>(g_bestBody.load(std::memory_order_relaxed)), speed, agreement,
                 static_cast<double>(g_bestMass.load(std::memory_order_relaxed)),
                 static_cast<double>(g_bestForceX.load(std::memory_order_relaxed)),
                 static_cast<double>(g_bestForceY.load(std::memory_order_relaxed)),
                 static_cast<double>(g_bestForceZ.load(std::memory_order_relaxed)),
                 reinterpret_cast<void*>(g_bestBackPtr.load(std::memory_order_relaxed)));
    } else {
        NCM_INFO("physics probe: %llu call(s)/s, %u bod(ies) | fastest %p v=%.2f m/s [%s] "
                 "| deep read declined (short body or unreadable span)",
                 static_cast<unsigned long long>(delta), distinct,
                 reinterpret_cast<void*>(g_bestBody.load(std::memory_order_relaxed)), speed, agreement);
    }

    reportClassification(speed);
}

/// Re-read the grip scale from `ncm_carrier.json` once a second, so it can be changed while the game is
/// running. Alt-tab, edit, save, feel it, set it back -- an A/B you can do in seconds instead of a deploy
/// cycle. This is only possible at all because the config path carried the `KB-133` newline bug until
/// 0.1.2, so the file has never once been read before now.
void refreshGripScale()
{
    if (g_configPath.empty()) return;

    float wanted = kGripScaleInert;
    try {
        std::ifstream in(g_configPath);
        if (in) {
            nlohmann::json j;
            in >> j;
            wanted = j.value("gripScale", kGripScaleInert);
            g_diagnostics.store(j.value("diagnostics", true), std::memory_order_relaxed);
            // ---------------------------------------------------------- the three new levers
            // Same discipline as `gripScale`: clamp on the way in, announce only on change, and say in the
            // log whether the value is doing anything. A lever that is silently inert is how §AV2 came to
            // be driven three times without ever running (`KB-142`).
            auto readScale = [&j](const char* key, float lo, float hi) {
                float v = j.value(key, kGripScaleInert);
                if (!std::isfinite(v)) return kGripScaleInert;
                return v < lo ? lo : (v > hi ? hi : v);
            };

            // `L152`: a composed Parts setup outranks the file. Said once, then silent.
            if (g_handlingOwns.load(std::memory_order_relaxed)) {
                if (!g_handlingNoticed.exchange(true, std::memory_order_relaxed)) {
                    NCM_INFO("ncm_carrier.json: gripScale/driveScale/brakeScale are now owned by the "
                             "server's Parts setup and this file no longer drives them");
                }
                return;
            }

            const float drive = readScale("driveScale", kDriveScaleMin, kDriveScaleMax);
            const float previousDrive = g_driveScale.load(std::memory_order_relaxed);
            if (std::fabs(drive - previousDrive) > kGripScaleEpsilon) {
                g_driveScale.store(drive, std::memory_order_relaxed);
                NCM_INFO("driveScale %.2f -> %.2f (%s)", static_cast<double>(previousDrive),
                         static_cast<double>(drive),
                         std::fabs(drive - kGripScaleInert) > kGripScaleEpsilon
                             ? "SCALING longitudinal force under power" : "inert");
            }

            const float brake = readScale("brakeScale", kBrakeScaleMin, kBrakeScaleMax);
            const float previousBrake = g_brakeScale.load(std::memory_order_relaxed);
            if (std::fabs(brake - previousBrake) > kGripScaleEpsilon) {
                g_brakeScale.store(brake, std::memory_order_relaxed);
                NCM_INFO("brakeScale %.2f -> %.2f (%s)", static_cast<double>(previousBrake),
                         static_cast<double>(brake),
                         std::fabs(brake - kGripScaleInert) > kGripScaleEpsilon
                             ? "SCALING longitudinal force under braking" : "inert");
            }

            float roll = j.value("rollBias", 0.0f);
            if (!std::isfinite(roll)) roll = 0.0f;
            if (roll < -kRollBiasMax) roll = -kRollBiasMax;
            if (roll > kRollBiasMax) roll = kRollBiasMax;
            const float previousRoll = g_rollBias.load(std::memory_order_relaxed);
            if (std::fabs(roll - previousRoll) > kGripScaleEpsilon) {
                g_rollBias.store(roll, std::memory_order_relaxed);
                NCM_INFO("rollBias %+.2f -> %+.2f (%s)", static_cast<double>(previousRoll),
                         static_cast<double>(roll),
                         std::fabs(roll) > kGripScaleEpsilon
                             ? "SHIFTING load left/right, zero-sum" : "inert");
            }

            float bias = j.value("axleLoadBias", 0.0f);
            if (!std::isfinite(bias)) bias = 0.0f;
            if (bias < -kAxleBiasMax) bias = -kAxleBiasMax;
            if (bias > kAxleBiasMax) bias = kAxleBiasMax;
            const float previousBias = g_axleBias.load(std::memory_order_relaxed);
            if (std::fabs(bias - previousBias) > kGripScaleEpsilon) {
                g_axleBias.store(bias, std::memory_order_relaxed);
                resetRegression();
                NCM_INFO("axleLoadBias %+.2f -> %+.2f, yaw regression reset (%s)", static_cast<double>(previousBias),
                         static_cast<double>(bias),
                         std::fabs(bias) > kGripScaleEpsilon
                             ? "SHIFTING load between axles, zero-sum" : "inert");
            }
        }
    } catch (...) {
        // A half-saved file is the ordinary case when someone is editing it live. Keep the last good
        // value rather than lurching to a default mid-corner.
        return;
    }

    if (!std::isfinite(wanted)) return;
    const float clamped = wanted < kGripScaleMin ? kGripScaleMin
                        : (wanted > kGripScaleMax ? kGripScaleMax : wanted);

    const float current = g_gripScale.load(std::memory_order_relaxed);
    if (std::fabs(clamped - current) <= kGripScaleEpsilon) return;

    g_gripScale.store(clamped, std::memory_order_relaxed);
    if (clamped != wanted) {
        NCM_WARN("gripScale %.2f is outside [%.2f, %.2f] -- clamped to %.2f",
                 static_cast<double>(wanted), static_cast<double>(kGripScaleMin),
                 static_cast<double>(kGripScaleMax), static_cast<double>(clamped));
    }
    NCM_INFO("gripScale %.2f -> %.2f (%s)", static_cast<double>(current), static_cast<double>(clamped),
             std::fabs(clamped - kGripScaleInert) > kGripScaleEpsilon ? "WRITING lateral force"
                                                                      : "inert, no writes");
}

void reporterLoop()
{
    // First line immediately, so "attached but never fired" shows up within a second rather than looking
    // like a silent success.
    while (g_reporterRunning.load(std::memory_order_acquire)) {
        std::unique_lock<std::mutex> lock(g_reporterMutex);
        g_reporterWake.wait_for(lock, std::chrono::seconds(1),
                                [] { return !g_reporterRunning.load(std::memory_order_acquire); });
        if (!g_reporterRunning.load(std::memory_order_acquire)) break;
        lock.unlock();
        try {
            refreshGripScale();
            reportOnce();
        } catch (...) {
            // Never let the reporter be the thing that kills the session.
        }
    }
}

// --------------------------------------------------------------------------------------- address table

std::wstring addressTablePath()
{
    // The table ships with the GAME, not with RED4ext -- its header carries the build's linker-map
    // timestamp and preferred load address, and RED4ext 1.30.0's package contains only winmm.dll and
    // RED4ext.dll. It sits beside Cyberpunk2077.exe, so the running module's own path finds it.
    wchar_t exePath[MAX_PATH] = {};
    if (GetModuleFileNameW(nullptr, exePath, MAX_PATH) == 0) return {};
    std::wstring full(exePath);
    const auto slash = full.find_last_of(L'\\');
    if (slash == std::wstring::npos) return {};
    return full.substr(0, slash) + L"\\cyberpunk2077_addresses.json";
}

}  // namespace

// --------------------------------------------------------------------------------------- public surface

bool addressTableCarries(uint32_t hash)
{
    const std::wstring path = addressTablePath();
    if (path.empty()) {
        NCM_ERR("cannot locate the game's address table -- declining to resolve hash %u", hash);
        return false;
    }

    std::ifstream in(path, std::ios::binary);
    if (!in) {
        NCM_ERR("address table is not readable -- declining to resolve hash %u", hash);
        return false;
    }

    // Exactly the spelling the table uses: {"hash": "593628708","secondary hash": ...
    char needle[64];
    const int needleLength = std::snprintf(needle, sizeof(needle), "\"hash\": \"%u\"", hash);
    if (needleLength <= 0) return false;
    const auto needleSize = static_cast<size_t>(needleLength);

    // 132 MB, so stream it. The overlap carries a needle that straddles a chunk boundary.
    const auto started = std::chrono::steady_clock::now();
    constexpr size_t kChunk = 1u << 20;
    std::vector<char> buffer(kChunk + needleSize);
    size_t carried = 0;
    bool found = false;

    while (!found && in) {
        in.read(buffer.data() + carried, static_cast<std::streamsize>(kChunk));
        const auto got = static_cast<size_t>(in.gcount());
        if (got == 0) break;
        const size_t filled = carried + got;
        if (filled >= needleSize) {
            const void* hit = std::memchr(buffer.data(), needle[0], filled);
            const char* cursor = static_cast<const char*>(hit);
            while (cursor != nullptr) {
                const size_t remaining = filled - static_cast<size_t>(cursor - buffer.data());
                if (remaining < needleSize) break;
                if (std::memcmp(cursor, needle, needleSize) == 0) {
                    found = true;
                    break;
                }
                const void* next = std::memchr(cursor + 1, needle[0], remaining - 1);
                cursor = static_cast<const char*>(next);
            }
        }
        carried = (filled >= needleSize - 1) ? needleSize - 1 : filled;
        std::memmove(buffer.data(), buffer.data() + filled - carried, carried);
    }

    const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
                             std::chrono::steady_clock::now() - started).count();
    if (found) {
        NCM_INFO("address table carries hash %u (scanned in %lld ms)", hash, static_cast<long long>(elapsed));
    } else {
        NCM_ERR("address table does NOT carry hash %u (scanned in %lld ms) -- declining, because "
                "UniversalRelocBase::Resolve terminates the process on a miss",
                hash, static_cast<long long>(elapsed));
    }
    return found;
}

bool attach(void* pluginHandle, const void* sdkOpaque, const std::wstring& dllDirectory)
{
    if (g_attached.load()) return true;

    // A separator, not a newline. `L"\n..."` is the KB-133 bug that hid the log in 0.1.0 and the config
    // file until 0.1.2, and it is astonishingly easy to reintroduce -- this is its third appearance.
    g_configPath = dllDirectory + L"\\ncm_carrier.json";

    // WRITE THE DEFAULT IF IT IS NOT THERE. Asking a human to hand-create a file with an exact name is a
    // needless failure point, and on 2026-09-26 it cost a test: the file did not exist, and when created
    // by hand Windows' hidden extensions turned it into `ncm_carrier.json.json`. The plugin knows the
    // path, the schema and the defaults. Whatever it writes is exactly what it reads back, so the file is
    // self-documenting. An existing file is never touched.
    //
    // **AND MERGE MISSING KEYS INTO AN EXISTING FILE.** 0.1.11 shipped `axleLoadBias` and the experiment
    // never ran, because the file already existed from 0.1.9, only-write-when-absent left it alone, and a
    // missing key silently defaulted to inert. Nobody did anything wrong and nothing in the log said so.
    // A settable surface that can silently not exist is worse than one that does not exist at all.
    {
        bool merged = false;
        try {
            std::ifstream in(g_configPath);
            if (in) {
                nlohmann::json j;
                in >> j;
                in.close();
                if (j.is_object()) {
                    if (!j.contains("gripScale")) { j["gripScale"] = 1.0; merged = true; }
                    if (!j.contains("driveScale")) { j["driveScale"] = 1.0; merged = true; }
                    if (!j.contains("brakeScale")) { j["brakeScale"] = 1.0; merged = true; }
                    if (!j.contains("rollBias")) { j["rollBias"] = 0.0; merged = true; }
                    if (!j.contains("axleLoadBias")) { j["axleLoadBias"] = 0.0; merged = true; }
                    if (!j.contains("diagnostics")) { j["diagnostics"] = true; merged = true; }
                    if (merged) {
                        std::ofstream out(g_configPath);
                        if (out) {
                            out << j.dump(2) << "\n";
                            NCM_INFO("added missing key(s) to ncm_carrier.json -- every settable now "
                                     "present and editable while the game runs");
                        }
                    }
                }
            }
        } catch (...) {
            NCM_WARN("ncm_carrier.json is unreadable -- leaving it alone, running on defaults");
        }
    }
    {
        std::ifstream probe(g_configPath);
        if (!probe) {
            std::ofstream out(g_configPath);
            if (out) {
                out << "{\n"
                    << "  \"_comment\": \"Edited live: re-read once a second, no restart needed.\",\n"
                    << "  \"gripScale\": 1.0,\n"
                    << "  \"driveScale\": 1.0,\n"
                    << "  \"_driveScale\": \"longitudinal force under power, [0.3, 2.0]. "
                       "1.0 is inert.\",\n"
                    << "  \"brakeScale\": 1.0,\n"
                    << "  \"_brakeScale\": \"longitudinal force under braking, [0.3, 2.0]. "
                       "1.0 is inert.\",\n"
                    << "  \"rollBias\": 0.0,\n"
                    << "  \"_rollBias\": \"zero-sum left/right normal load, [-0.3, 0.3]. "
                       "positive loads the LEFT. 0.0 is inert.\",\n"
                    << "  \"_gripScale\": \"lateral grip multiplier, clamped to [0.3, 1.5]. "
                       "1.0 is inert and writes nothing at all. Lower is a wet road, not a slow car -- "
                       "acceleration and braking are untouched.\",\n"
                    << "  \"diagnostics\": true,\n"
                    << "  \"_diagnostics\": \"false stops the per-second classification counting and "
                       "logging, keeping the grip effect.\"\n"
                    << "}\n";
                NCM_INFO("wrote default config to ncm_carrier.json beside this DLL -- edit it while the "
                         "game runs, changes apply within a second");
            } else {
                NCM_WARN("could not write a default ncm_carrier.json -- grip stays inert at 1.00");
            }
        }
    }

    const auto* sdk = static_cast<const RED4ext::v1::Sdk*>(sdkOpaque);
    if (!sdk || !sdk->hooking || !sdk->hooking->Attach) {
        NCM_ERR("RED4ext hooking API unavailable -- physics probe declines");
        return false;
    }

    // Order matters and this is the order: verify the hash BEFORE anything can resolve it.
    if (!addressTableCarries(kRecalculateHash)) return false;

    const uintptr_t resolved = RED4ext::UniversalRelocBase::Resolve(kRecalculateHash);
    if (resolved == 0) {
        NCM_ERR("hash %u resolved to null -- physics probe declines", kRecalculateHash);
        return false;
    }
    g_target = reinterpret_cast<void*>(resolved);

    for (auto& slot : g_bodySlotStamp) slot.store(0, std::memory_order_relaxed);
    for (uint32_t i = 0; i < kQuatCandidates; ++i) {
        g_quatMin[i].store(FLT_MAX, std::memory_order_relaxed);
        g_quatMax[i].store(-FLT_MAX, std::memory_order_relaxed);
    }
    resetRegression();
    for (uint32_t w = 0; w < kWheelCount; ++w) {
        g_wheelMin[w].store(FLT_MAX, std::memory_order_relaxed);
        g_wheelMax[w].store(-FLT_MAX, std::memory_order_relaxed);
        g_cornerZ[w].store(0.0f, std::memory_order_relaxed);
        g_cornerXY[w].store(0.0f, std::memory_order_relaxed);
        g_cornerXYMax[w].store(0.0f, std::memory_order_relaxed);
    }

    if (!sdk->hooking->Attach(static_cast<RED4ext::v1::PluginHandle>(pluginHandle), g_target,
                              reinterpret_cast<void*>(&recalculateDetour),
                              reinterpret_cast<void**>(&g_original))) {
        NCM_ERR("could not attach to RigidBody::Recalculate at %p -- physics probe declines", g_target);
        g_target = nullptr;
        return false;
    }

    g_attached.store(true);
    g_observing.store(true);
    g_reporterRunning.store(true, std::memory_order_release);
    g_reporter = std::thread(reporterLoop);

    NCM_INFO("physics probe attached to RigidBody::Recalculate (hash %u) at %p -- READ ONLY, no writes",
             kRecalculateHash, g_target);
    return true;
}

void detach(void* pluginHandle, const void* sdkOpaque)
{
    if (!g_attached.exchange(false)) return;

    // Stop looking first, then stop reporting, then unhook. The detour may be mid-flight on the physics
    // thread while we do this; from here it does nothing but call the original.
    g_observing.store(false);
    g_reporterRunning.store(false, std::memory_order_release);
    g_reporterWake.notify_all();
    if (g_reporter.joinable()) g_reporter.join();

    const auto* sdk = static_cast<const RED4ext::v1::Sdk*>(sdkOpaque);
    if (sdk && sdk->hooking && sdk->hooking->Detach && g_target) {
        sdk->hooking->Detach(static_cast<RED4ext::v1::PluginHandle>(pluginHandle), g_target);
    }
    NCM_INFO("physics probe detached after %llu call(s), %llu shallow fault(s), %llu deep decline(s)",
             static_cast<unsigned long long>(g_ticks.load()),
             static_cast<unsigned long long>(g_faults.load()),
             static_cast<unsigned long long>(g_deepFaults.load()));
    g_target = nullptr;
    g_original = nullptr;
}

bool attached() noexcept
{
    return g_attached.load(std::memory_order_relaxed);
}

bool ticking() noexcept
{
    return g_attached.load(std::memory_order_relaxed) && g_ticks.load(std::memory_order_relaxed) > 0;
}

uint64_t ticks() noexcept
{
    return g_ticks.load(std::memory_order_relaxed);
}

void noteReportedSpeed(double metresPerSecond) noexcept
{
    g_reportedSpeed.store(metresPerSecond, std::memory_order_relaxed);
}

void noteBrakeInput(double pedal, bool hasBrake) noexcept
{
    if (!hasBrake) {
        // Withdraw rather than hold. A remembered pedal is exactly the value that would let a stale
        // frame scale real braking as drag.
        g_brakeInput.store(-1.0, std::memory_order_relaxed);
        g_brakeInputAtMs.store(0, std::memory_order_relaxed);
        return;
    }
    g_brakeInput.store(pedal, std::memory_order_relaxed);
    g_brakeInputAtMs.store(monotonicMs(), std::memory_order_relaxed);
}

namespace {

/// Clamp, store, and announce only when the value actually moved. Returns true if it moved.
///
/// The announcement is not decoration. `KB-142` was a lever that sat inert through three drives while
/// everybody believed it was running, and the only reason it took three drives is that nothing ever said
/// out loud what was being applied. Every change to a force scale is now a line in the log, and a clamp
/// says it clamped -- which is `L148`'s fifth property written down rather than promised.
bool storeLever(std::atomic<float>& cell, const char* name, double wanted, float lo, float hi) noexcept
{
    if (!std::isfinite(wanted)) {
        NCM_INFO("handling: %s ignored, not a finite number", name);
        return false;
    }
    float value = static_cast<float>(wanted);
    const bool clamped = (value < lo) || (value > hi);
    if (value < lo) value = lo;
    if (value > hi) value = hi;

    const float previous = cell.load(std::memory_order_relaxed);
    if (std::fabs(value - previous) <= kGripScaleEpsilon) return false;

    cell.store(value, std::memory_order_relaxed);
    if (clamped) {
        NCM_INFO("handling: %s %.3f -> %.3f (CLAMPED from %.3f to [%.2f, %.2f])", name,
                 static_cast<double>(previous), static_cast<double>(value), wanted,
                 static_cast<double>(lo), static_cast<double>(hi));
    } else {
        NCM_INFO("handling: %s %.3f -> %.3f (%s)", name, static_cast<double>(previous),
                 static_cast<double>(value),
                 std::fabs(value - kGripScaleInert) > kGripScaleEpsilon ? "ACTIVE" : "inert");
    }
    return true;
}

}  // namespace

void applyHandling(const std::string& assetId, const std::string& vehicleId,
                   const std::string& authorityEpoch, uint64_t engineEntity,
                   bool hasGrip, double grip, bool hasDrive, double drive,
                   bool hasBrake, double brake, bool hasDrag, double drag,
                   bool hasTopSpeed, double topSpeedKph) noexcept
{
    // ------------------------------------------------------------------------------------- `KB-146`
    // **A setup without an identity is refused, not applied.** The whole defect this closes was that the
    // carrier decided for itself which body was the player's, by choosing the fastest car-shaped thing it
    // had seen. It now applies force only to the body whose `ent::EntityID` equals the one NCM published
    // for this Machine, and if that number is missing there is nothing to match, so there is nothing to do.
    if (engineEntity == 0) {
        NCM_WARN("handling: refused -- no engineEntity, so no body can be positively identified");
        clearHandling(false);
        return;
    }

    if (!g_handlingOwns.exchange(true, std::memory_order_relaxed)) {
        NCM_INFO("handling: the server's Parts setup now owns grip/drive/brake for this session");
    }

    // Publish the human-readable identity BEFORE arming, so a log line written the instant the physics
    // thread matches already names the right Machine.
    {
        std::lock_guard<std::mutex> guard(g_bindingMetaMutex);
        g_bindingAssetId = assetId;
        g_bindingVehicleId = vehicleId;
        g_bindingAuthorityEpoch = authorityEpoch;
    }

    const uint64_t previous = g_expectedEngineEntity.load(std::memory_order_acquire);
    if (previous != engineEntity) {
        // A different Machine, a different body. Drop the old binding and every lever with it rather than
        // letting one Machine's Parts survive into another -- which is exactly the seat-change failure.
        g_boundBody.store(0, std::memory_order_release);
        g_boundVehicle.store(0, std::memory_order_relaxed);
        g_gripScale.store(kGripScaleInert, std::memory_order_relaxed);
        g_driveScale.store(kGripScaleInert, std::memory_order_relaxed);
        g_brakeScale.store(kGripScaleInert, std::memory_order_relaxed);
        NCM_INFO("handling: binding asset=%s vehicle=%s epoch=%s entity=%llu",
                 assetId.c_str(), vehicleId.c_str(), authorityEpoch.c_str(),
                 static_cast<unsigned long long>(engineEntity));
    }

    // Levers first, identity last. The physics thread arms on `g_expectedEngineEntity`, so storing it last
    // (with release ordering) guarantees a matched body never sees a half-published setup.
    int moved = 0;
    if (hasGrip)  moved += storeLever(g_gripScale,  "gripScale",  grip,  kGripScaleMin,  kGripScaleMax)  ? 1 : 0;
    if (hasDrive) moved += storeLever(g_driveScale, "driveScale", drive, kDriveScaleMin, kDriveScaleMax) ? 1 : 0;
    if (hasDrag) moved += storeLever(g_dragScale, "dragScale", drag, kDragScaleMin, kDragScaleMax) ? 1 : 0;
    if (hasBrake) moved += storeLever(g_brakeScale, "brakeScale", brake, kBrakeScaleMin, kBrakeScaleMax) ? 1 : 0;

    // The governor is a TARGET, not a lever, so it is stored rather than clamped into a lever's range.
    // Absent leaves whatever was set; an explicit 0 withdraws it, which is how a Machine with no declared
    // top speed runs ungoverned rather than stopped.
    if (hasTopSpeed) {
        const double mps = topSpeedKph / 3.6;
        const float was = g_topSpeedMps.exchange(
            (std::isfinite(mps) && mps > 0.0) ? static_cast<float>(mps) : 0.0f,
            std::memory_order_relaxed);
        const float now = g_topSpeedMps.load(std::memory_order_relaxed);
        if (std::fabs(now - was) > 0.05f) {
            if (now > 0.0f) {
                NCM_INFO("handling: topSpeed %.1f -> %.1f km/h (governor taper %.0f%%)",
                         static_cast<double>(was) * 3.6, static_cast<double>(now) * 3.6,
                         static_cast<double>(kTopSpeedTaper) * 100.0);
            } else {
                NCM_INFO("handling: topSpeed withdrawn -- this Machine is ungoverned");
            }
            ++moved;
        }
    }

    g_bindingExpiresAtMs.store(monotonicMs() + kBindingLeaseMs, std::memory_order_release);
    g_expectedEngineEntity.store(engineEntity, std::memory_order_release);

    const uint32_t n = g_handlingApplied.fetch_add(1, std::memory_order_relaxed) + 1;
    if (moved == 0 && previous == engineEntity && (n % 60) == 0) {
        // This is a LEASE, so an unchanged setup arrives twice a second forever. Saying so every time
        // would bury every other line; saying it never would lose the distinction `KB-136` was invisible
        // inside -- "received and matched" versus "never arrived". Once every thirty seconds keeps both.
        NCM_INFO("handling: heartbeat #%u, binding held, no lever moved", n);
    }
}

bool applyWrench(const std::string& assetId, double fx, double fy, double fz, int ttlMs, bool supersedeLift,
                 bool hasPulse, uint32_t pulseSeq, double px, double py, double pz, int pulseMs,
                 bool av, double ncmMassKg, double ax, double ay, double az) noexcept
{
    {
        std::lock_guard<std::mutex> guard(g_bindingMetaMutex);
        if (assetId.empty() || assetId != g_bindingAssetId) {
            g_wrenchRefusedAsset.fetch_add(1, std::memory_order_relaxed);
            return false;
        }
    }
    auto clampVec = [](double x, double y, double z, float* out) {
        if (!(x == x) || !(y == y) || !(z == z)) { out[0] = out[1] = out[2] = 0.0f; return; }
        const double m = std::sqrt(x * x + y * y + z * z);
        const double k = m > kMaxWrenchN ? kMaxWrenchN / m : 1.0;
        out[0] = static_cast<float>(x * k); out[1] = static_cast<float>(y * k); out[2] = static_cast<float>(z * k);
    };
    const uint64_t now = GetTickCount64();
    const int ttl = ttlMs < 0 ? 0 : (ttlMs > kMaxWrenchTtlMs ? kMaxWrenchTtlMs : ttlMs);
    {
        std::lock_guard<std::mutex> lock(g_wrenchMutex);
        WrenchState& w = g_wrench;
        clampVec(fx, fy, fz, w.sus);
        for (int i = 0; i < 3; ++i) w.lastSus[i] = w.sus[i];
        auto clampAcc = [](double a) -> float {
            if (!(a == a)) return 0.0f;
            return static_cast<float>(a > kMaxAngularAcc ? kMaxAngularAcc : (a < -kMaxAngularAcc ? -kMaxAngularAcc : a));
        };
        w.alpha[0] = clampAcc(ax); w.alpha[1] = clampAcc(ay); w.alpha[2] = clampAcc(az);
        w.ncmMass = (ncmMassKg == ncmMassKg && ncmMassKg > 100.0 && ncmMassKg < 1.0e6) ? static_cast<float>(ncmMassKg) : 0.0f;
        w.av = av;
        w.susExpireMs = now + static_cast<uint64_t>(ttl);
        if (hasPulse) {
            const bool fresh = !w.pulseSeqKnown || pulseSeq != w.lastPulseSeq;
            w.pulseSeqKnown = true;
            w.lastPulseSeq = pulseSeq;
            if (fresh && pulseMs > 0) {
                clampVec(px, py, pz, w.pendingF);
                w.pendingS = static_cast<float>(pulseMs > kMaxPulseMs ? kMaxPulseMs : pulseMs) / 1000.0f;
                w.pulsePending = true;
            }
        }
    }
    if (supersedeLift) g_liftSupersededUntilMs.store(now + 600, std::memory_order_relaxed);
    if (av) g_avUntilMs.store(now + 600, std::memory_order_relaxed);
    if (!g_wrenchSeen.exchange(true, std::memory_order_relaxed)) g_wrenchFirstPending.store(true, std::memory_order_release);
    return true;
}

void clearHandling(bool releaseBenchConfig) noexcept
{
    clearWrench();
    const bool wasArmed = g_expectedEngineEntity.exchange(0, std::memory_order_acq_rel) != 0;

    // Disarm identity first: once `g_expectedEngineEntity` is zero the physics thread cannot authorise a
    // write, so the levers below are being reset on something already inert. Order matters here in the
    // opposite direction to `applyHandling`, and for the same reason.
    g_boundBody.store(0, std::memory_order_release);
    g_boundVehicle.store(0, std::memory_order_relaxed);

    if (!g_handlingOwns.load(std::memory_order_relaxed)) return;

    storeLever(g_gripScale,  "gripScale",  kGripScaleInert, kGripScaleMin,  kGripScaleMax);
    storeLever(g_driveScale, "driveScale", kGripScaleInert, kDriveScaleMin, kDriveScaleMax);
    storeLever(g_dragScale, "dragScale", kGripScaleInert, kDragScaleMin, kDragScaleMax);
    storeLever(g_brakeScale, "brakeScale", kGripScaleInert, kBrakeScaleMin, kBrakeScaleMax);
    // Losing the server must not leave a car governed forever.
    g_topSpeedMps.store(0.0f, std::memory_order_relaxed);
    g_brakeInput.store(-1.0, std::memory_order_relaxed);
    g_brakeInputAtMs.store(0, std::memory_order_relaxed);

    {
        std::lock_guard<std::mutex> guard(g_bindingMetaMutex);
        g_bindingAssetId.clear();
        g_bindingVehicleId.clear();
        g_bindingAuthorityEpoch.clear();
    }

    if (!releaseBenchConfig) {
        // **An authoritative unbind, not a lost socket.** NCM is connected and is telling us this client
        // has no Machine to tune -- on foot, a passenger, ambiguous authority, a refused payload. Staying
        // inert is the answer; handing the levers back to `ncm_carrier.json` would let a stale bench value
        // silently become the car's handling at the precise moment NCM said it should have none.
        if (wasArmed) NCM_INFO("handling: unbound by NCM -- inert, bench config stays suppressed");
        return;
    }

    g_handlingOwns.store(false, std::memory_order_relaxed);
    g_handlingNoticed.store(false, std::memory_order_relaxed);
    NCM_INFO("handling: cleared to inert after %u setup(s); ncm_carrier.json drives the levers again",
             g_handlingApplied.load(std::memory_order_relaxed));
}

std::string status()
{
    // `KB-146`: the binding is the first thing anyone debugging handling needs, because "armed but never
    // matched" and "not armed at all" are different faults with different causes, and both look like
    // "my parts do nothing".
    const char* binding = "none";
    if (g_expectedEngineEntity.load(std::memory_order_relaxed) != 0) {
        binding = g_boundBody.load(std::memory_order_relaxed) != 0 ? "matched" : "waiting";
    }

    char buffer[256];
    const int n = std::snprintf(
        buffer, sizeof(buffer), "probe=%s ticks=%llu faults=%llu binding=%s",
        g_attached.load() ? (g_ticks.load() > 0 ? "ticking" : "silent") : "off",
        static_cast<unsigned long long>(g_ticks.load()),
        static_cast<unsigned long long>(g_faults.load() + g_deepFaults.load()),
        binding);
    return n > 0 ? std::string(buffer, static_cast<size_t>(n)) : std::string("probe=?");
}

}  // namespace ncm::vehicle::probe

namespace ncm::vehicle::probe {
uint64_t avEntityNeedingPhysics() noexcept
{
    if (GetTickCount64() >= g_avUntilMs.load(std::memory_order_relaxed)) return 0;
    const uint64_t entity = g_expectedEngineEntity.load(std::memory_order_acquire);
    if (entity == 0) return 0;
    const uint64_t last = g_boundTickMs.load(std::memory_order_relaxed);
    if (last != 0 && monotonicMs() - last < 300) return 0;   // its physics is running: nothing to switch on
    return entity;
}
}  // namespace ncm::vehicle::probe
