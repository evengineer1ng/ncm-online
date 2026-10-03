#pragma once

// NCM Pace state (Paddock phase 5, doc 44 §15). Pure C++: no RED4ext, so the tests run without the game.
//
// One drive plan at a time, set by the `ncm_paddock` resource over loopback (`drive.start`): a road line of up to
// 64 points, the race's timing gates, and each car's engine entity hash with a speed ceiling per leg. Two flows:
//
//   * redscript, on the game thread, calls `step(i, x, y, z)` for every car ~20 times a second. `step` records any
//     gate the car crossed since its last report (dated by interpolation between the two reports, the same rule
//     as ncm-core course.gates), advances the car's target along the line before it gets there (so the native
//     planner never brakes for an intermediate point), and answers with the command the car should hold:
//     "seq|mode|x|y|z|max|min|forced|dist|boost". Redscript sends a fresh command only when `seq` changes.
//   * the bridge thread drains `outbox()`: gate reports and acks for the resource. They are evidence; the server
//     times the race itself from canonical positions and counts these only when they agree.
//
// Modes: 0 hold (before the lights), 1 drive to the point at up to `speed` m/s, 2 stop (finished, ended, or the
// resource went away). A dropped socket stops every car: a plan nobody is watching must not keep driving.

#include <chrono>
#include <cstdint>
#include <mutex>
#include <memory>
#include <string>
#include <vector>

namespace ncm::pace {

uint64_t nodeRefHash(const std::string& path);
class RoadGraph;

// A plan arrives as a TAPE (0.3.1, KB-223): `drive.start` with the first stretch and `"more": true`, then `drive.more`
// messages appending points, gates and each car's per-leg speeds, the last with `"last": true`. One WebUI message
// could not carry an oval (the hop drops large payloads silently), and the tape lifts the 64-point cap with it.
//
// DYNAMIC plans (0.4.0, KB-223): the continuous race model (L230) makes cars physical near a player and hands them
// back when they leave, so a car joins and leaves mid-race. `drive.start` with `"dynamic": true` may carry no cars;
// `car.add` appends one at a line point with one speed ceiling; `car.remove` retires it IN PLACE. Nothing mid-race
// bumps the revision or reorders the list: redscript keys its per-car state by index, and a revision change
// releases every car.
constexpr size_t kMaxPoints = 4096;
constexpr size_t kMaxCars = 64;
constexpr size_t kMaxRoadLegs = 24;        // 0.5.2: beyond this a plan is a dense line, not checkpoints (KB-241)
constexpr double kBehindStartM = 150.0;    // 0.5.2: a grid car this far behind the plan's first point is on it (KB-243)
constexpr double kOffPlanCapMps = 38.0;    // 0.5.2: the ceiling off the plan in a road-planned race (KB-243)
constexpr size_t kMaxGates = 1024;

struct Point { double x = 0, y = 0, z = 0; };
struct RoadSpeedLeg { std::vector<Point> points; std::vector<double> limits; };

struct Gate {
    double x = 0, y = 0, z = 0;
    double dx = 1, dy = 0;          // unit direction of travel through the line
    double halfWidth = 28, capture = 35, arm = 60;
};

// Signed distance along the approach (positive = still approaching) and lateral offset. ncm-core course.gates.
double signedDistance(const Gate& g, const Point& p, double* perp = nullptr);
// Fraction 0..1 of the move a -> b at which g was crossed, or -1 when it was not crossed.
double crossFraction(const Gate& g, const Point& a, const Point& b);

// How a car is driven, ported from NCM single player's ai_vehicles.lua (L234): every command is a fresh
// AIVehicleDriveToPointAutonomousCommand, as SP's issueAutonomousCommand sends it.
//   * launch release: the first command out of the grid is capped (buildLaunchReleaseProfile) -- the whole field
//     leaves at once, but gently, so it does not rocket into itself off the line;
//   * launch grace: for graceS nothing is judged; then the full race command (SP's post-launch command);
//   * recommand: a new command every recommandS while healthy, and at once when the car has been under stallMps for
//     stallS (SP's stall detection). A crashed or blocked car is told to drive again, forever -- it never parks.
struct Launch {
    double graceS = 1.75;
    double relMax = 35, relMin = 18, relForced = 18, relDist = 7.5;
    double minFrac = 0.55;          // race minimum speed = ceiling * minFrac (SP aiMinSpeedFrac)
    double forcedFrac = 0.25;       // race forced start speed = ceiling * forcedFrac (SP buildDriveProfile, raceActive)
    double raceDist = 12;           // minimumDistanceToTarget in the race
    double recommandS = 3.1, stallMps = 5.5, stallS = 1.9;
    double rampFloorMps = 6.0, rampMps2 = 4.6;   // 0.5.3: the ceiling's curve from the lights (0-100 km/h in ~6 s)
};

struct Car {
    uint64_t entity = 0;
    int64_t vehicleId = 0;
    std::vector<float> speeds;      // ceiling per leg: leg i runs from point i to point i+1
    size_t target = 1;              // index of the next point on the line (legs, gates, "passed")
    size_t aim = 0;                 // with lookaheadM: the point the car is actually sent to, far ahead (0.4.1)
    size_t nextGate = 1;            // gate 0 is the start line; timing starts at 1
    bool haveLast = false;
    Point last{};
    int64_t lastMs = 0;
    int64_t prevMs = 0;
    bool finished = false;
    uint32_t seq = 0;
    int mode = 0;
    Point cmd{};
    float cmdSpeed = 0;
    int phase = 0;                  // 0 grid, 1 launch release, 2 racing
    int64_t cmdMs = 0;              // when the current command was issued (race clock)
    int64_t stallMs = 0;            // how long the car has been under stallMps
    Point speedAt{};                // speed is measured over >= 250 ms windows of the reported positions
    int64_t speedAtMs = 0;
    bool haveSpeedAt = false;
    double speed = 0;
    uint32_t renewals = 0;
    uint32_t logged = 0;
    bool dynamic = false;           // joined mid-race (car.add): ended only by car.remove, never by a gate
    int64_t releaseMs = 0;          // 0.8.6: held on the grid until this long after the go (a staggered start, by row)
    double startMps = 0;            // 0.8.8: a car joining mid-race starts rolling at this speed (spline pre-roll)
    int64_t prerollUntil = -1;      // 0.8.8: race clock until which the pre-roll command holds (0.9.0: unused, see launch)
    int64_t launchUntil = -1;       // 0.9.0: a car joining mid-race is watched until this race clock for a dead launch
    uint32_t launchKicks = 0;       // 0.9.0: fresh racer commands sent to get it going
    bool reacquire = false;         // 0.8.1: its entity was swapped (car.entity): a fresh command on the next step
    // the wrong-way guard (0.4.6): its motion over >= 300 ms windows, how long it has gone against the ring
    bool haveMotion = false;
    Point motionFrom{};
    int64_t motionMs = 0;
    int64_t wrongMs = 0;
    int64_t forceUntil = -1;
    Point forceAt{};
    uint32_t wrongEvents = 0;
    size_t roadIndex = 0;
    size_t roadLeg = 0;
    bool roadLocated = false;
    // 0.5.0: the native driver is sent along the road plan, not to the next checkpoint (owner, 2026-09-30: the field
    // fell apart at the first checkpoint once the aim jumped to the finish and the engine replanned its own way)
    size_t roadAim = 0;
    bool roadAimed = false;
    bool onRoad = true;             // last reported: within reach of the road plan
    uint32_t roadEvents = 0;
    // 0.5.0: a car the game stops reporting (streamed out, destroyed) and that comes back must be re-commanded:
    // redscript only sends on a new seq, so a re-created vehicle object would otherwise sit with no command
    std::chrono::steady_clock::time_point lastStepAt{};
    bool haveStep = false;
    bool missing = false;
    uint32_t dropouts = 0;
    int64_t statusMs = -1000000;
    size_t leg = 0;                 // 0.7.0: the leg (race spline) the car's racing command is on
    int64_t slowMs = 0;             // 0.7.0: time under 2 m/s since the racing command was sent
};

class State {
public:
    using Clock = std::chrono::steady_clock;

    // A message from the resource. Returns false (and changes nothing) for anything it does not understand.
    bool apply(const std::string& json, Clock::time_point now = Clock::now());
    void setRoadGraph(std::shared_ptr<const RoadGraph> graph);
    void disconnect();

    int count(Clock::time_point now = Clock::now());
    int revision();
    uint64_t entity(int index);
    // 0.7.0: the NodeRef (hash) of the race spline car `index` is on now; 0 when the plan has none
    uint64_t spline(int index);
    std::string step(int index, double x, double y, double z, Clock::time_point now = Clock::now());

    std::vector<std::string> outbox();
    std::string health();
    // Why the last `apply` returned false, for the log (0.4.0: "not understood" alone cost a night, KB-223).
    std::string refusal();
    // Log lines made on the game thread, for the bridge thread to write (0.4.3: no file IO on the game thread).
    std::vector<std::string> drainLog();

    // The race-start warning (0.2.0): a native HUD banner, not a WebUI page. "rev|visible|title|detail|secondsLeft";
    // empty text fields are "~". Set by {"cmd":"banner","title":..,"detail":..,"seconds":N}; seconds 0 clears it.
    std::string banner(Clock::time_point now = Clock::now());

    // The native crowd/traffic null area over a staging grid (0.3.0, KB-219): gameCommunitySystem
    // .EnableDynamicCrowdNullArea(box, transform, savable, duration). {"cmd":"area","x","y","z","half","halfZ","seconds"};
    // seconds 0 clears it. "rev|visible|x|y|z|half|halfZ|secondsLeft".
    std::string area(Clock::time_point now = Clock::now());

    double advanceM = 40.0;         // switch to the next point this far before reaching the current one
    // 0.4.1 (KB-223): send the car to a point this far AHEAD along the line, not to the next point. A dense line (an
    // oval's ring, 15 m a point) otherwise completes each command inside minimumDistanceToTarget and the car stops
    // and starts every few metres; SP and the street run always aim far (the next checkpoint, the finish). The aim
    // moves on once the car has covered half of it. 0 = the next point (the street run, unchanged).
    double lookaheadM = 0.0;
    // 0.4.5: re-aim once the car's remaining distance to its aim falls under this share of the look-ahead. 0.5
    // let a car close on its aim and brake for it ("braking at checkpoints", 06:12); ~0.9 keeps it always ahead.
    double reaimFrac = 0.5;
    // 0.5.0: with a road plan the car is sent this far along it, and re-aimed once fewer than roadReaimM remain
    double roadAimM = 300.0;
    double roadReaimM = 180.0;
    // 0.4.6, the WRONG-WAY GUARD (owner, 06:48: "they do good for a few turns, then wonder which way round is fastest
    // and turn around ... harden their forward travel"). A plan may carry its ring {cx, cy, sign}: a car moving
    // against the ring's direction for wrongWayMs (0.3 s) is sent 25 m further ROUND the ring, the race direction, for 2.5 s -- the
    // planner is left no road but forward -- then back to its mark.
    bool haveRing = false;
    double ringCx = 0, ringCy = 0, ringSign = 1;
    int64_t wrongWayMs = 300;      // owner: 0.7 s was too long; judged on 150 ms windows of real motion
    Launch launch;

private:
    void planRoad(); // caller holds mutex_
    void stopAll(const char* why);  // caller holds mutex_
    void push(const std::string& json);
    std::mutex mutex_;
    int revision_ = 0;
    std::string raceId_;
    std::vector<Point> points_;
    std::shared_ptr<const RoadGraph> roadGraph_;
    std::vector<Point> road_;
    std::vector<double> roadLimits_;
    std::vector<RoadSpeedLeg> roadLegs_;
    std::vector<size_t> pointRoad_;       // 0.5.2: each plan point's index on the continuous road_, in race order
    std::vector<std::string> legNames_;   // 0.7.0: the race spline for each leg, by node path
    std::vector<uint64_t> legHashes_;     // ...and its NodeRef hash
    std::vector<Gate> gates_;
    std::vector<Car> cars_;
    Clock::time_point goAt_{};
    bool active_ = false;
    bool complete_ = true;          // false while a tape is still arriving: no car finishes on a partial plan
    bool dynamic_ = false;          // cars join (car.add) and leave (car.remove) mid-race
    std::string refusal_;
    std::vector<std::string> logQueue_;
    Clock::time_point stoppedAt_{};
    std::vector<std::string> out_;
    uint64_t gateReports_ = 0;
    int bannerRev_ = 0;
    std::string bannerTitle_, bannerDetail_;
    Clock::time_point bannerUntil_{};
    int areaRev_ = 0;
    Point areaAt_{};
    double areaHalf_ = 0, areaHalfZ_ = 0;
    Clock::time_point areaUntil_{};
};

State& state();
uint64_t parseHash(const std::string& text);
}
