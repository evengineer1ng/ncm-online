#include "vehicle/physics_probe.hpp"

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
constexpr uint32_t kOffVelocity = 0x18;
constexpr uint32_t kOffVehicleBackPtr = 0x180;
constexpr uint32_t kOffTotalMass = 0x1BC;

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

/// Write back the horizontal pair only. Z is never touched: it is what holds the car up, and scaling it
/// would make the car sag rather than slide -- the mistake this whole line of work nearly made.
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
            // With diagnostics off, only the horizontal entries matter -- they are the only ones the write
            // touches. Everything else returns immediately and costs a compare.
            if (!diagnostics && kind != Kind::Horizontal) return;

            // A run of consecutive wheel calls ends the moment anything else arrives. Closing it here,
            // rather than counting to four, is what makes a short run visible instead of silently
            // merging into the next group.
            if (kind != Kind::Wheel && t_wheelRun > 0) {
                if (t_wheelRun == kWheelCount) {
                    g_runsComplete.fetch_add(1, std::memory_order_relaxed);
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

            switch (kind) {
                case Kind::Gravity:
                    g_cntGravity.fetch_add(1, std::memory_order_relaxed);
                    g_lastGravity.store(force[2], std::memory_order_relaxed);
                    break;
                case Kind::Wheel:
                    g_cntWheel.fetch_add(1, std::memory_order_relaxed);
                    if (t_wheelRun < kWheelCount) {
                        t_wheelZ[t_wheelRun] = force[2];
                        t_wheelXY[t_wheelRun] =
                            std::sqrt(force[0] * force[0] + force[1] * force[1]);
                    }
                    ++t_wheelRun;
                    break;
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
                    const float k = g_gripScale.load(std::memory_order_relaxed);
                    if (g_writesEnabled.load(std::memory_order_relaxed) &&
                        std::fabs(k - kGripScaleInert) > kGripScaleEpsilon) {
                        const float scaledLateral = lateral * k;
                        // long*dir + lat*perp, with perp = (-dirY, dirX). At k = 1 this is the vector we
                        // just took apart, put back together.
                        const float newX = longitudinal * dirX + scaledLateral * -dirY;
                        const float newY = longitudinal * dirY + scaledLateral * dirX;
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

    if (!spanIsReadable(body, kDeepestRead)) {
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

    // Latch this as THE vehicle once it reads like one: a car-shaped mass and a back-pointer to something.
    // Cycle tracking follows the latch, so slot numbering belongs to one body and not to whatever moved
    // fastest this second. Re-latching on a different body resets the numbering, which is correct.
    if (mass > 200.0f && mass < 10000.0f && back != 0 &&
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

void reportOnce()
{
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
    {
        std::ifstream probe(g_configPath);
        if (!probe) {
            std::ofstream out(g_configPath);
            if (out) {
                out << "{\n"
                    << "  \"_comment\": \"Edited live: re-read once a second, no restart needed.\",\n"
                    << "  \"gripScale\": 1.0,\n"
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

std::string status()
{
    char buffer[192];
    const int n = std::snprintf(
        buffer, sizeof(buffer), "probe=%s ticks=%llu faults=%llu",
        g_attached.load() ? (g_ticks.load() > 0 ? "ticking" : "silent") : "off",
        static_cast<unsigned long long>(g_ticks.load()),
        static_cast<unsigned long long>(g_faults.load() + g_deepFaults.load()));
    return n > 0 ? std::string(buffer, static_cast<size_t>(n)) : std::string("probe=?");
}

}  // namespace ncm::vehicle::probe
