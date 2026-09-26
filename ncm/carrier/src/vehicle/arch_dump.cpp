#include "vehicle/arch_dump.hpp"

#include "effects/tweak.hpp"
#include "log.hpp"

#include <cstdio>
#include <fstream>
#include <string>
#include <vector>

namespace ncm::vehicle::arch {
namespace {

// The directory the log and the config already use. **`L"\\..."` and not `L"\..."`** -- the second is a
// newline and it has been written three times in this codebase (`KB-139`). It is spelled out here because
// this is the fourth wide path literal in the plugin.
std::wstring g_outDir;

/// The candidate flats, grouped only for the reader's benefit -- the probe treats them as a flat list.
///
/// Sourced from Report 36 section 3.3's account of `gamedataVehicleDriveModelData_Record` and from
/// `machine.flats`. **Several of these are guesses about the name**, particularly the drivetrain group,
/// because nothing in the repository establishes what a drivetrain layout is called on the record. That is
/// the point: an unresolved name is a result, and a resolved one is a discovery.
struct Candidate {
    const char* suffix;
    const char* group;
};

constexpr Candidate kCandidates[] = {
    // ---- mass and balance. `total_mass` is graded `documented` in machine.flats and is worth settling.
    { ".total_mass",                      "mass" },
    { ".chassis_mass",                    "mass" },
    { ".momentOfInertiaScale",            "mass" },

    // ---- the drivetrain group: what we most want and are least sure how to ask for.
    { ".frontBackWheelDistance",          "layout" },
    { ".frontBackBias",                   "layout" },
    { ".wheelsResistanceRatio",           "layout" },
    { ".numberOfWheels",                  "layout" },
    { ".numDriveWheels",                  "layout" },
    { ".driveWheels",                     "layout" },
    { ".drivenWheels",                    "layout" },

    // ---- power. `engineMaxTorque` has no `accelerationScale <= 1` ceiling, which is why it matters.
    { ".engineMaxTorque",                 "power" },
    { ".maxRPM",                          "power" },
    { ".minRPM",                          "power" },
    { ".flyWheelMomentOfInertia",         "power" },
    { ".resistanceTorque",                "power" },
    { ".accelerationBoost",               "power" },
    { ".maxWheelTorque",                  "power" },

    // ---- transmission. A gear count would settle `transmission` for every vehicle at once.
    { ".gearChangeTime",                  "transmission" },
    { ".gearChangeCooldown",              "transmission" },
    { ".numGears",                        "transmission" },

    // ---- tyres and grip. `frictionMulLateral` is THE grip field and is graded `documented`.
    { ".frictionMulLateral",              "tires" },
    { ".frictionMulLongitudinal",         "tires" },
    { ".bodyFriction",                    "tires" },
    { ".slipAngleCurveScale",             "tires" },
    { ".slipRatioCurveScale",             "tires" },

    // ---- brakes.
    { ".brakingFrictionFactor",           "brakes" },
    { ".brakingFriction",                 "brakes" },
    { ".handbrakeBrakingTorque",          "brakes" },
    { ".lowVelStoppingDeceleration",      "brakes" },

    // ---- suspension. Both graded `documented`.
    { ".springStiffness",                 "suspension" },
    { ".antiSwaybarDampingScalor",        "suspension" },
    { ".turningRollFactor",               "suspension" },
    { ".forwardWeightTransferFactor",     "suspension" },
    { ".sideWeightTransferFactor",        "suspension" },

    // ---- steering.
    { ".maxWheelTurnDeg",                 "steering" },
    { ".wheelTurningMax",                 "steering" },
    { ".perfectSteeringFactor",           "steering" },

    // ---- aero.
    { ".airResistanceFactor",             "aero" },
};

/// JSON string escaping. Record paths are `Vehicle.v_...` and contain nothing exotic, but the output is a
/// data file another tool parses and a hand-rolled writer that cannot escape is a trap for the next person.
std::string escape(const std::string& in)
{
    std::string out;
    out.reserve(in.size() + 2);
    for (const char c : in) {
        switch (c) {
            case '"':  out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n";  break;
            case '\r': out += "\\r";  break;
            case '\t': out += "\\t";  break;
            default:
                if (static_cast<unsigned char>(c) < 0x20) {
                    char buf[8];
                    std::snprintf(buf, sizeof(buf), "\\u%04x", c);
                    out += buf;
                } else {
                    out += c;
                }
        }
    }
    return out;
}

std::string number(float value)
{
    char buf[64];
    std::snprintf(buf, sizeof(buf), "%.6g", static_cast<double>(value));
    return buf;
}

}  // namespace

void setOutputDirectory(const std::wstring& dllDirectory)
{
    g_outDir = dllDirectory;
}

DumpResult dump(const std::vector<std::string>& records)
{
    DumpResult result;
    result.records = static_cast<int>(records.size());
    if (records.empty()) {
        NCM_WARN("architecture dump asked for zero records -- nothing to do");
        return result;
    }
    if (g_outDir.empty()) {
        NCM_ERR("architecture dump has no output directory");
        return result;
    }

    // Built in memory first, so a failure to open the file cannot leave a half-written dump that a later
    // importer would read as complete.
    std::string body;
    body.reserve(records.size() * 512);
    body += "{\n  \"v\": 1,\n  \"records\": [\n";

    bool firstRecord = true;
    for (const auto& record : records) {
        const uint64_t driveModel = effects::resolveDriveModel(record);

        if (!firstRecord) body += ",\n";
        firstRecord = false;

        body += "    { \"record\": \"";
        body += escape(record);
        body += "\", \"driveModelResolved\": ";
        body += (driveModel != 0) ? "true" : "false";

        if (driveModel == 0) {
            // Not an error: a record with no drive model is a real answer about that record, and the
            // importer needs to see it rather than have it silently missing from the list.
            body += ", \"flats\": {} }";
            continue;
        }
        ++result.resolved;

        body += ", \"flats\": {";
        bool firstFlat = true;
        for (const auto& candidate : kCandidates) {
            const uint64_t flatId = effects::composeFlatId(driveModel, candidate.suffix);
            float value = 0.0f;
            if (!effects::readFlat(flatId, value)) continue;   // unresolved is reported by absence

            if (!firstFlat) body += ", ";
            firstFlat = false;
            body += "\"";
            body += escape(candidate.suffix);
            body += "\": ";
            body += number(value);
            ++result.flatsRead;
        }
        body += "} }";
    }

    body += "\n  ]\n}\n";

    const std::wstring path = g_outDir + L"\\ncm_architecture_dump.json";
    std::ofstream out(path, std::ios::trunc | std::ios::binary);
    if (!out) {
        NCM_ERR("architecture dump could not open its output file");
        return result;
    }
    out << body;
    out.close();

    result.written = true;
    result.path = "ncm_architecture_dump.json";
    NCM_INFO("architecture dump: %d record(s), %d resolved, %d flat(s) read -> %s",
             result.records, result.resolved, result.flatsRead, result.path.c_str());

    // The headline number for the log, because it is the one that decides whether this was worth doing: how
    // many distinct flats resolved anywhere. Zero would mean the traversal is wrong, not that the game is.
    if (result.flatsRead == 0) {
        NCM_WARN("architecture dump read NO flats -- the traversal is suspect, not the data");
    }
    return result;
}

}  // namespace ncm::vehicle::arch
