// ncm_rig_devices -- what the Rig Bridge's DirectInput provider can actually see, outside the game.
//
// "The mod does not detect my wheel" has two very different causes and one of them is not the mod:
//
//   * the device is not exposed to DirectInput at all (driver/filter/mode), or
//   * it is exposed and the plugin mishandled it.
//
// This runs the SAME enumeration the plugin runs -- DI8DEVCLASS_GAMECTRL, DIEDFL_ATTACHEDONLY -- in an
// ordinary process, so the two cases separate immediately and without launching the game.

#include <dinput.h>
#include <windows.h>

#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

namespace {

std::string utf8(const wchar_t* value)
{
    if (!value) return {};
    const int count = WideCharToMultiByte(CP_UTF8, 0, value, -1, nullptr, 0, nullptr, nullptr);
    if (count <= 1) return {};
    std::string out(static_cast<size_t>(count), '\0');
    WideCharToMultiByte(CP_UTF8, 0, value, -1, out.data(), count, nullptr, nullptr);
    out.pop_back();
    return out;
}

std::string guidText(const GUID& guid)
{
    wchar_t buffer[64]{};
    StringFromGUID2(guid, buffer, static_cast<int>(std::size(buffer)));
    return utf8(buffer);
}

int found = 0;
IDirectInput8W* g_api = nullptr;

BOOL CALLBACK onDevice(const DIDEVICEINSTANCEW* value, void* context)
{
    auto* api = static_cast<IDirectInput8W*>(context);
    ++found;

    const DWORD type = value->dwDevType & 0xFF;   // low byte is the DI8DEVTYPE_*
    const char* kind = "other";
    switch (type) {
        case DI8DEVTYPE_JOYSTICK:       kind = "joystick"; break;
        case DI8DEVTYPE_GAMEPAD:        kind = "gamepad"; break;
        case DI8DEVTYPE_DRIVING:        kind = "DRIVING (wheel)"; break;
        case DI8DEVTYPE_FLIGHT:         kind = "flight"; break;
        case DI8DEVTYPE_1STPERSON:      kind = "first-person"; break;
        case DI8DEVTYPE_SUPPLEMENTAL:   kind = "supplemental (pedals/shifter)"; break;
        default: break;
    }

    std::printf("\n[%d] %s\n", found, utf8(value->tszProductName).c_str());
    std::printf("    instance GUID : %s   <-- put this in ncm_rig_bridge.json\n",
                guidText(value->guidInstance).c_str());
    std::printf("    product GUID  : %s\n", guidText(value->guidProduct).c_str());
    std::printf("    vid:pid       : %04X:%04X\n",
                static_cast<unsigned>(value->guidProduct.Data1 & 0xFFFFu),
                static_cast<unsigned>((value->guidProduct.Data1 >> 16) & 0xFFFFu));
    std::printf("    type          : %s\n", kind);

    IDirectInputDevice8W* device = nullptr;
    if (FAILED(api->CreateDevice(value->guidInstance, &device, nullptr))) {
        std::printf("    CreateDevice  : FAILED\n");
        return DIENUM_CONTINUE;
    }
    DIDEVCAPS caps{};
    caps.dwSize = sizeof(caps);
    if (SUCCEEDED(device->GetCapabilities(&caps))) {
        std::printf("    axes/buttons  : %lu axis, %lu button, %lu POV\n",
                    caps.dwAxes, caps.dwButtons, caps.dwPOVs);
        std::printf("    force feedback: %s\n",
                    (caps.dwFlags & DIDC_FORCEFEEDBACK) ? "YES" : "no");
    }
    device->Release();
    return DIENUM_CONTINUE;
}
}

// ---- live axis watch -------------------------------------------------------------------------------
// Which of a pedal set's three axes is the brake is not knowable from enumeration -- it is whatever the
// maker wired. Guessing it and shipping the guess as configuration is how a rig ends up braking when the
// driver accelerates. So: move one control, read which axis moved, write that down.

struct Watch { IDirectInputDevice8W* device; std::string name; LONG base[8]; bool seeded; };

const char* kAxisNames[8] = {"x", "y", "z", "rx", "ry", "rz", "slider0", "slider1"};

void readAxes(const DIJOYSTATE2& s, LONG* out)
{
    out[0] = s.lX;  out[1] = s.lY;  out[2] = s.lZ;
    out[3] = s.lRx; out[4] = s.lRy; out[5] = s.lRz;
    out[6] = s.rglSlider[0]; out[7] = s.rglSlider[1];
}

BOOL CALLBACK onWatchDevice(const DIDEVICEINSTANCEW* value, void* context)
{
    auto* list = static_cast<std::vector<Watch>*>(context);
    IDirectInputDevice8W* device = nullptr;
    if (FAILED(g_api->CreateDevice(value->guidInstance, &device, nullptr))) return DIENUM_CONTINUE;
    if (FAILED(device->SetDataFormat(&c_dfDIJoystick2))) { device->Release(); return DIENUM_CONTINUE; }
    DIPROPRANGE range{};
    range.diph.dwSize = sizeof(range);
    range.diph.dwHeaderSize = sizeof(range.diph);
    range.diph.dwHow = DIPH_DEVICE;
    range.lMin = 0; range.lMax = 65535;
    device->SetProperty(DIPROP_RANGE, &range.diph);
    HWND window = GetConsoleWindow();
    device->SetCooperativeLevel(window ? window : GetDesktopWindow(),
                                DISCL_NONEXCLUSIVE | DISCL_BACKGROUND);
    device->Acquire();
    list->push_back(Watch{device, utf8(value->tszProductName), {}, false});
    return DIENUM_CONTINUE;
}

int watch(int seconds)
{
    std::vector<Watch> devices;
    g_api->EnumDevices(DI8DEVCLASS_GAMECTRL, onWatchDevice, &devices, DIEDFL_ATTACHEDONLY);
    if (devices.empty()) { std::printf("nothing to watch\n"); return 1; }

    std::printf("Watching %zu device(s) for %d seconds.\n", static_cast<size_t>(devices.size()), seconds);
    std::printf("Move ONE control at a time; each axis that moves is named.\n\n");
    std::fflush(stdout);

    const DWORD until = GetTickCount() + static_cast<DWORD>(seconds) * 1000u;
    while (GetTickCount() < until) {
        for (auto& w : devices) {
            if (FAILED(w.device->Poll())) w.device->Acquire();
            DIJOYSTATE2 s{};
            if (FAILED(w.device->GetDeviceState(sizeof(s), &s))) continue;
            LONG now[8];
            readAxes(s, now);
            if (!w.seeded) { readAxes(s, w.base); w.seeded = true; continue; }
            for (int i = 0; i < 8; ++i) {
                const LONG delta = now[i] - w.base[i];
                if (delta > 8000 || delta < -8000) {
                    std::printf("  %-40s axis %-8s %5ld -> %5ld  (delta %+ld)\n",
                                w.name.c_str(), kAxisNames[i], w.base[i], now[i], delta);
                    std::fflush(stdout);
                    w.base[i] = now[i];
                }
            }
            for (int b = 0; b < 32; ++b) {
                if (s.rgbButtons[b] & 0x80) {
                    std::printf("  %-40s button %d DOWN\n", w.name.c_str(), b);
                    std::fflush(stdout);
                }
            }
        }
        Sleep(60);
    }
    for (auto& w : devices) { w.device->Unacquire(); w.device->Release(); }
    std::printf("\nwatch finished.\n");
    return 0;
}

int main(int argc, char** argv)
{
    std::printf("NCM Rig Bridge -- DirectInput device report\n");
    std::printf("Same enumeration the plugin performs: DI8DEVCLASS_GAMECTRL, attached only.\n");

    IDirectInput8W* api = nullptr;
    const HRESULT created = DirectInput8Create(GetModuleHandleW(nullptr), DIRECTINPUT_VERSION,
                                               IID_IDirectInput8W, reinterpret_cast<void**>(&api), nullptr);
    if (FAILED(created)) {
        std::printf("\nDirectInput8Create FAILED: 0x%08lX\n", created);
        return 2;
    }

    g_api = api;
    if (argc > 1 && std::string(argv[1]) == "--watch") {
        const int seconds = argc > 2 ? std::atoi(argv[2]) : 20;
        const int rc = watch(seconds > 0 ? seconds : 20);
        api->Release();
        return rc;
    }

    api->EnumDevices(DI8DEVCLASS_GAMECTRL, onDevice, api, DIEDFL_ATTACHEDONLY);

    std::printf("\n-------------------------------------------------------------\n");
    if (found == 0) {
        std::printf("NOTHING FOUND.\n\n");
        std::printf("No attached device is exposed to DirectInput as a game controller. A wheel that\n");
        std::printf("Windows lists in Device Manager but that does not appear here is being held by a\n");
        std::printf("driver or filter above the standard HID game-controller stack -- the plugin cannot\n");
        std::printf("reach it either, and that is a device/driver state rather than a plugin fault.\n");
    } else {
        std::printf("%d device(s) visible to DirectInput.\n", found);
        std::printf("Anything attached but missing from this list is invisible to the plugin too.\n");
    }
    api->Release();
    return found == 0 ? 1 : 0;
}
