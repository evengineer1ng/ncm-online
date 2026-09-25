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

#include <RED4ext/RED4ext.hpp>

#include <memory>
#include <string>

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

void onLoad()
{
    g_carrier = new Carrier();
    auto& c = *g_carrier;

    stage("config", [&] { c.config = ncm::Config::load(directoryOf(g_module)); });

    // Input and feel come up first because they are useful even with no server connection: a player can
    // verify their wheel is seen before they ever join a world.
    stage("devices", [&] {
        c.devices = std::make_unique<ncm::input::Devices>();
        c.devices->open();
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
            NCM_INFO("projection v%d on %s: %d applied, %d captured, %d refused",
                     p.version, p.record.c_str(), r.applied, r.captured, r.refused);
        });
        c.server->onFrame([&c](const ncm::bridge::Frame& f) {
            if (c.mixer) c.mixer->feed(f);
        });
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

    NCM_INFO("ncm_carrier %s ready (bridge %s, hook %s, devices %s)",
             NCM_CARRIER_VERSION,
             c.server && c.server->listening() ? "up" : "down",
             ncm::vehicle::hookInstalled() ? "installed" : "absent",
             c.devices ? c.devices->describe().c_str() : "none");
}

void onUnload()
{
    if (!g_carrier) return;
    auto& c = *g_carrier;

    // Order matters and this is the order: stop taking instructions, stop moving the wheel, then put
    // TweakDB back. Restoring while a projection is still arriving would race.
    if (c.server) c.server->stop();
    ncm::vehicle::removeHook();
    if (c.mixer) c.mixer->shutdown();
    c.tweaks.restoreAll();
    if (c.devices) c.devices->close();

    delete g_carrier;
    g_carrier = nullptr;
    NCM_INFO("ncm_carrier unloaded cleanly");
}

}  // namespace

RED4EXT_C_EXPORT void RED4EXT_CALL Query(RED4ext::v1::PluginInfo* info)
{
    info->name = L"NCM Carrier";
    info->author = L"Night City Motorsports";
    info->version = RED4EXT_V1_SEMVER(0, 1, 0);
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

RED4EXT_C_EXPORT bool RED4EXT_CALL Main(RED4ext::PluginHandle handle, RED4ext::v1::EMainReason reason,
                                        const RED4ext::v1::Sdk* sdk)
{
    switch (reason) {
        case RED4ext::v1::EMainReason::Load: {
            g_module = static_cast<HMODULE>(handle);
            ncm::log::init(directoryOf(g_module));
            NCM_INFO("loading on sdk %d.%d", sdk ? sdk->runtime->major : 0, sdk ? sdk->runtime->minor : 0);
            // Even the top-level load is wrapped. Returning true with a half-built carrier is strictly
            // better than letting an exception reach RED4ext.
            try {
                onLoad();
            } catch (...) {
                NCM_ERR("load failed entirely -- the carrier is inert, the game is unaffected");
            }
            break;
        }
        case RED4ext::v1::EMainReason::Unload: {
            try {
                onUnload();
            } catch (...) {
                // Nothing useful left to do; do not propagate.
            }
            break;
        }
    }
    return true;
}
