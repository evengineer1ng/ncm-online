// NCM Carrier -- RED4ext plugin entry.
//
// **THE ONE RULE THIS FILE EXISTS TO ENFORCE: never take the game down.**
//
// A RED4ext plugin that throws, or that declares a game version it does not get, can stop Cyberpunk
// launching at all -- RED4ext puts up a MessageBox and terminates. That is the worst failure NCM could ship,
// because it happens before any of our UI exists to explain it, it happens to everyone at once on a patch
// day, and the player's only clue is that the game is broken after installing our mod.
//
// So: every stage is independent, every stage is wrapped, and any stage may fail without stopping the
// others. A carrier that loads and does nothing is a bad afternoon. A carrier that does not load is a
// refund. The log beside this DLL is the only thing that explains which happened.
#include "bridge/server.hpp"
#include "config.hpp"
#include "effects/tweak.hpp"
#include "ffb/mixer.hpp"
#include "input/devices.hpp"
#include "log.hpp"
#include "vehicle/hook.hpp"
#include "vehicle/arch_dump.hpp"
#include "vehicle/physics_probe.hpp"

#include <RED4ext/RED4ext.hpp>
#include <nlohmann/json.hpp>

#include <atomic>
#include <memory>
#include <string>
#include <vector>

namespace {

struct Carrier {
    ncm::Config config;
    ncm::effects::TweakStore tweaks;
    std::unique_ptr<ncm::input::Devices> devices;
    std::unique_ptr<ncm::ffb::Mixer> mixer;
    std::unique_ptr<ncm::bridge::Server> server;
};

Carrier* g_carrier = nullptr;
HMODULE g_module = nullptr;

// Kept from Main(Load) because the hooking API lives on the sdk and the probe attaches in Running::OnEnter,
// long after Main has returned.
RED4ext::v1::PluginHandle g_handle{};
const RED4ext::v1::Sdk* g_sdk = nullptr;

// Running totals for the health snapshot. Reported, never inferred: if nothing has been applied this says
// zero, which is the fact `KB-136` is about.
std::atomic<int> g_appliedFlats{0};

std::wstring directoryOf(HMODULE module)
{
    wchar_t path[MAX_PATH] = {};
    if (GetModuleFileNameW(module, path, MAX_PATH) == 0) return L".";
    std::wstring full(path);
    const auto slash = full.find_last_of(L'\\');
    return (slash == std::wstring::npos) ? L"." : full.substr(0, slash);
}

/// Run one startup stage. A stage that throws is reported and skipped; it never reaches RED4ext.
template <typename Fn>
bool stage(const char* name, Fn&& fn)
{
    try {
        fn();
        return true;
    } catch (const std::exception& e) {
        NCM_ERR("%s failed: %s -- continuing without it", name, e.what());
    } catch (...) {
        NCM_ERR("%s failed: unknown exception -- continuing without it", name);
    }
    return false;
}

/// Introduce the carrier to whoever just connected. `client/carrier_bridge.lua` already listens for
/// `ncm:carrier.health` and logs `carrier <version> | hook=<bool> | <n> flat(s) on <m> record(s)`, so this
/// reaches NCM's own client log with no resource change at all.
///
/// TWO DELIBERATE CHOICES, BOTH ABOUT NOT LYING.
///
///   * `hook` is FALSE, flatly. In 0.1.2 it reported the physics probe, which was honest about the probe
///     and misleading about everything else: the Lua log renders it as `hook=true` right where a reader
///     expects `KB-135`'s input authority, which does not exist. No detour writes a vehicle command, so
///     the field that means "we can command this car" says no. The probe has its own words below.
///   * The probe counters ride in the `version` string. The Lua rebuilds this object field by field and
///     would silently drop a new one, and changing that file means deploying a resource. A shim, and it
///     should be replaced by typed fields when `KB-134` is done properly.
void sendHealth(Carrier& c)
{
    if (!c.server) return;
    nlohmann::json health{
        { "version", std::string(NCM_CARRIER_VERSION) + " " + ncm::vehicle::probe::status() },
        { "hook", false },
        { "applied", g_appliedFlats.load(std::memory_order_relaxed) },
        { "records", static_cast<int>(c.tweaks.recordsHeld()) },
    };
    c.server->sendJson(nlohmann::json{ { "health", health } }.dump());
}

void onLoad()
{
    if (g_carrier) return;
    g_carrier = new Carrier();
    auto& c = *g_carrier;

    stage("config", [&] { c.config = ncm::Config::load(directoryOf(g_module)); });

    // Input and feel come up first because they are useful even with no server connection: a player can
    // verify their wheel is seen before they ever join a world.
    stage("devices", [&] {
        c.devices = std::make_unique<ncm::input::Devices>();
        // The return value used to be discarded, so "SDL found nothing at all" and "everything is fine"
        // produced an identical log. That is how a session with four working controllers attached could
        // report `devices none` with no explanation anywhere.
        if (!c.devices->open()) {
            NCM_WARN("no input device was opened -- the wheel and pedals will do nothing this session");
        }
    });

    stage("mixer", [&] {
        c.mixer = std::make_unique<ncm::ffb::Mixer>(c.devices.get());
    });

    // The bridge is what the NCM resource dials into. It listens on loopback only.
    stage("bridge", [&] {
        c.server = std::make_unique<ncm::bridge::Server>(c.config.port);
        c.server->onProjection([&c](const ncm::bridge::Projection& p) {
            if (p.restore) {
                c.tweaks.restore(p.record);
                return;
            }
            const auto r = c.tweaks.apply(p.record, p.flats);
            g_appliedFlats.fetch_add(r.applied, std::memory_order_relaxed);
            NCM_INFO("projection v%d on %s: %d applied, %d captured, %d refused",
                     p.version, p.record.c_str(), r.applied, r.captured, r.refused);
        });
        c.server->onFrame([&c](const ncm::bridge::Frame& f) {
            if (c.mixer) c.mixer->feed(f);
            // The yardstick the probe measures itself against: NCM's own idea of how fast the player is
            // going. A frame with no speed, or an idle frame, means "not in a car" and is reported as such
            // rather than as zero -- absent and stationary are different claims.
            ncm::vehicle::probe::noteReportedSpeed((f.hasSpeed && !f.idle) ? f.speed : -1.0);
        });
        // IDEA-507: read the game's own drive-model data for a list of records and write it to a file.
        // Read-only, so it needs no decision line and cannot leave the player's game altered. The list comes
        // from NCM's vendored `data.vehicle_catalogue`, so the carrier never has to know what a car is.
        c.server->onArchDump([](const std::vector<std::string>& records) {
            ncm::vehicle::arch::dump(records);
        });
        c.server->onConnect([&c] { sendHealth(c); });
        c.server->onDisconnect([&c] {
            // The world went away. Put the player's game back the way we found it, immediately, without
            // waiting to be asked -- the resource may not get a chance to ask.
            c.tweaks.restoreAll();
            if (c.mixer) c.mixer->silence();
        });
        c.server->start();
    });

    // The vehicle hook is last and is the only stage that touches game code. If RTTI does not know what we
    // are looking for, it declines and the rest of the carrier still works -- effects and feel do not
    // depend on it.
    stage("vehicle hook", [&] {
        ncm::vehicle::installHook();
    });

    // The physics probe goes LAST, on purpose. It is the only stage that detours game code, so everything
    // else is already up before it runs, and it is the stage most worth being able to blame. It writes
    // nothing to the game; see `vehicle/physics_probe.hpp` for what it is for and why it declines loudly.
    if (c.config.enablePhysicsProbe) {
        stage("physics probe", [&] {
            ncm::vehicle::probe::attach(g_handle, g_sdk, directoryOf(g_module));
        });
    } else {
        NCM_INFO("physics probe disabled by config");
    }

    NCM_INFO("ncm_carrier %s ready (bridge %s, offsets %s, %s, devices %s)",
             NCM_CARRIER_VERSION,
             c.server && c.server->listening() ? "up" : "down",
             // "installed" was the `KB-135` lie: nothing is hooked here, offsets were merely resolved.
             ncm::vehicle::hookInstalled() ? "resolved" : "unresolved",
             ncm::vehicle::probe::attached() ? "physics probe attached" : "no physics probe",
             c.devices ? c.devices->describe().c_str() : "none");
}

void onUnload()
{
    if (!g_carrier) return;
    auto& c = *g_carrier;

    // Order matters and this is the order: stop taking instructions, stop moving the wheel, then put
    // TweakDB back. Restoring while a projection is still arriving would race.
    if (c.server) c.server->stop();
    // Before anything else touches game memory: stop observing and unhook while the game thread is still
    // alive, which is the whole reason teardown lives in Running::OnExit rather than Main(Unload).
    ncm::vehicle::probe::detach(g_handle, g_sdk);
    ncm::vehicle::removeHook();
    if (c.mixer) c.mixer->shutdown();
    c.tweaks.restoreAll();
    if (c.devices) c.devices->close();

    delete g_carrier;
    g_carrier = nullptr;
    NCM_INFO("ncm_carrier unloaded cleanly");
}

// RED4ext calls plugin Main(Load) before the game's memory allocators and RTTI lifecycle are ready.  The
// official contract explicitly forbids touching game memory there.  Version 0.1.0 did exactly that: it opened
// devices, started the bridge and queried RTTI immediately.  That build loaded immediately before RED4ext's
// later script validation failed; whether the ordering was causal is the 0.1.1 cold-launch test. Running-state
// callbacks are the supported boundary regardless:
// script/native registration has completed and game memory is live on enter, and is still live on exit.
bool onRunningEnter(RED4ext::CGameApplication*)
{
    try {
        onLoad();
    } catch (...) {
        NCM_ERR("running-state startup failed entirely -- the carrier is inert");
    }
    return true;
}

bool onRunningExit(RED4ext::CGameApplication*)
{
    try {
        onUnload();
    } catch (...) {
        NCM_ERR("running-state shutdown failed -- process exit will reclaim remaining state");
    }
    return true;
}

}  // namespace

RED4EXT_C_EXPORT void RED4EXT_CALL Query(RED4ext::v1::PluginInfo* info)
{
    info->name = L"NCM Carrier";
    info->author = L"Night City Motorsports";
    info->version = RED4EXT_V1_SEMVER(0, 1, 16);
    info->runtime = RED4EXT_V1_RUNTIME_VERSION_INDEPENDENT;  // see the note below
    info->sdk = RED4EXT_V1_SDK_VERSION_CURRENT;
}

RED4EXT_C_EXPORT uint32_t RED4EXT_CALL Supports()
{
    return RED4EXT_API_VERSION_1;
}

// RUNTIME_INDEPENDENT is a deliberate choice and it is the safety-critical one.
//
// Pinning an exact game build means the plugin refuses to load after a patch -- annoying, but safe.
// Declaring independence means we load on any build, so WE are responsible for checking that what we hook
// is still there. That responsibility is discharged in `vehicle/hook.cpp`, which resolves everything
// through the game's own RTTI and declines when RTTI does not recognise a field, rather than writing to an
// address that used to mean something. The alternative -- a hardcoded offset on an unexpected build -- is
// how a mod corrupts memory instead of failing.
//
// **THAT REASONING DOES NOT COVER HASH RESOLUTION, AND 0.1.2 ADDS SOME.** `RED4ext::UniversalRelocBase`
// calls `ShowErrorAndTerminateProcess` when a hash is not in the address table: a MessageBox and a dead
// process, not an exception. `stage()` above cannot catch it, so on a patch day that moved
// `RigidBody::Recalculate`, an independent-runtime carrier would take the game down for everyone at once
// -- precisely the failure this file exists to prevent. The probe therefore reads the game's own address
// table off disk and declines BEFORE anything can resolve, which restores the decline-don't-die contract.
// If hash-resolved hooks become load-bearing rather than diagnostic, revisit this declaration: a pinned
// runtime fails safe, at the cost of locking players out of NCM Online until a new carrier ships.

RED4EXT_C_EXPORT bool RED4EXT_CALL Main(RED4ext::v1::PluginHandle handle, RED4ext::v1::EMainReason reason,
                                        const RED4ext::v1::Sdk* sdk)
{
    switch (reason) {
        case RED4ext::v1::EMainReason::Load: {
            g_module = static_cast<HMODULE>(handle);
            g_handle = handle;
            g_sdk = sdk;
            ncm::log::init(directoryOf(g_module));
            // Same directory as the log and the config, so a dump lands where somebody already looks.
            ncm::vehicle::arch::setOutputDirectory(directoryOf(g_module));
            NCM_INFO("registering lifecycle on sdk %d.%d", sdk ? sdk->runtime->major : 0,
                     sdk ? sdk->runtime->minor : 0);

            // Main(Load) is registration-only. Do not access RTTI, TweakDB, SDL or start worker threads here;
            // RED4ext has not initialized the game's memory yet.
            RED4ext::v1::GameState state{
                .OnEnter = &onRunningEnter,
                .OnUpdate = nullptr,
                .OnExit = &onRunningExit,
            };
            if (!sdk || !sdk->gameStates || !sdk->gameStates->Add(
                    handle, RED4ext::EGameStateType::Running, &state)) {
                NCM_ERR("could not register Running-state lifecycle -- carrier remains inert");
            }
            break;
        }
        case RED4ext::v1::EMainReason::Unload: {
            // Running::OnExit owns teardown while game memory is still valid. RED4ext documents that game
            // memory is already freed by Main(Unload), so touching TweakDB/RTTI here would repeat 0.1.0's bug.
            NCM_INFO("plugin unload reached after game-state teardown");
            break;
        }
    }
    return true;
}
