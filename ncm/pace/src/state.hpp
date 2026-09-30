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
#include <string>
#include <vector>

namespace ncm::pace {

constexpr size_t kMaxPoints = 64;
constexpr size_t kMaxCars = 24;
constexpr size_t kMaxGates = 80;

struct Point { double x = 0, y = 0, z = 0; };

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
};

struct Car {
    uint64_t entity = 0;
    int64_t vehicleId = 0;
    std::vector<float> speeds;      // ceiling per leg: leg i runs from point i to point i+1
    size_t target = 1;              // index of the point being driven to
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
};

class State {
public:
    using Clock = std::chrono::steady_clock;

    // A message from the resource. Returns false (and changes nothing) for anything it does not understand.
    bool apply(const std::string& json, Clock::time_point now = Clock::now());
    void disconnect();

    int count(Clock::time_point now = Clock::now());
    int revision();
    uint64_t entity(int index);
    std::string step(int index, double x, double y, double z, Clock::time_point now = Clock::now());

    std::vector<std::string> outbox();
    std::string health();

    // The race-start warning (0.2.0): a native HUD banner, not a WebUI page. "rev|visible|title|detail|secondsLeft";
    // empty text fields are "~". Set by {"cmd":"banner","title":..,"detail":..,"seconds":N}; seconds 0 clears it.
    std::string banner(Clock::time_point now = Clock::now());

    // The native crowd/traffic null area over a staging grid (0.3.0, KB-219): gameCommunitySystem
    // .EnableDynamicCrowdNullArea(box, transform, savable, duration). {"cmd":"area","x","y","z","half","halfZ","seconds"};
    // seconds 0 clears it. "rev|visible|x|y|z|half|halfZ|secondsLeft".
    std::string area(Clock::time_point now = Clock::now());

    double advanceM = 40.0;         // switch to the next point this far before reaching the current one
    Launch launch;

private:
    void stopAll(const char* why);  // caller holds mutex_
    void push(const std::string& json);
    std::mutex mutex_;
    int revision_ = 0;
    std::string raceId_;
    std::vector<Point> points_;
    std::vector<Gate> gates_;
    std::vector<Car> cars_;
    Clock::time_point goAt_{};
    bool active_ = false;
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
