#include "input/hid_scan.hpp"

#include "log.hpp"

#include <windows.h>

#include <setupapi.h>

extern "C" {
#include <hidsdi.h>
}
#include <hidpi.h>

#include <cstdio>
#include <memory>

namespace ncm::input::hid {
namespace {

// Generic Desktop page, and the three usages that mean "something you steer or press".
constexpr uint16_t kUsagePageGenericDesktop = 0x01;
constexpr uint16_t kUsageJoystick = 0x04;
constexpr uint16_t kUsageGamepad = 0x05;
constexpr uint16_t kUsageMultiAxis = 0x08;

bool isGameController(uint16_t page, uint16_t usage)
{
    return page == kUsagePageGenericDesktop &&
           (usage == kUsageJoystick || usage == kUsageGamepad || usage == kUsageMultiAxis);
}

std::string narrow(const wchar_t* wide)
{
    if (!wide || !*wide) return {};
    const int needed = WideCharToMultiByte(CP_UTF8, 0, wide, -1, nullptr, 0, nullptr, nullptr);
    if (needed <= 1) return {};
    std::string out(static_cast<size_t>(needed - 1), '\0');
    WideCharToMultiByte(CP_UTF8, 0, wide, -1, out.data(), needed, nullptr, nullptr);
    return out;
}

std::string lastErrorText(DWORD code)
{
    switch (code) {
        case ERROR_ACCESS_DENIED: return "access denied (another process holds it exclusively)";
        case ERROR_SHARING_VIOLATION: return "sharing violation (held exclusively)";
        case ERROR_FILE_NOT_FOUND: return "not found";
        case ERROR_GEN_FAILURE: return "general failure";
        case ERROR_NOT_SUPPORTED: return "not supported";
        default: {
            char buffer[32];
            std::snprintf(buffer, sizeof(buffer), "win32 error %lu", code);
            return buffer;
        }
    }
}

/// Pull `vid_xxxx` / `pid_xxxx` straight out of the interface path. **This is why a device that will not
/// open is still identifiable**: the path is handed to us by SetupAPI and needs no handle at all.
void idsFromPath(const std::wstring& path, uint16_t& vendor, uint16_t& product)
{
    std::wstring lowered;
    lowered.reserve(path.size());
    for (wchar_t c : path) lowered.push_back(static_cast<wchar_t>(::towlower(c)));

    auto grab = [&](const wchar_t* key, uint16_t& out) {
        const auto at = lowered.find(key);
        if (at == std::wstring::npos) return;
        unsigned value = 0;
        if (swscanf_s(lowered.c_str() + at + wcslen(key), L"%4x", &value) == 1) {
            out = static_cast<uint16_t>(value);
        }
    };
    grab(L"vid_", vendor);
    grab(L"pid_", product);
    // Bluetooth LE interfaces spell it `dev_vid&01e502_pid&bbab` rather than `vid_046d&pid_c24f`, which
    // is why the ESP32 rim logged as 0000:0000 in 0.1.5 while its path named it plainly.
    if (vendor == 0) grab(L"vid&", vendor);
    if (product == 0) grab(L"pid&", product);
}

/// Query-only handle: no access rights requested at all. Windows normally permits metadata on such a
/// handle even for a device another process owns, which is why the metadata pass cannot disturb the game.
HANDLE openForQuery(const wchar_t* path)
{
    return CreateFileW(path, 0, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING, 0, nullptr);
}

}  // namespace

std::vector<Device> scanGameControllers()
{
    std::vector<Device> found;

    GUID hidGuid{};
    HidD_GetHidGuid(&hidGuid);

    HDEVINFO set = SetupDiGetClassDevsW(&hidGuid, nullptr, nullptr,
                                        DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
    if (set == INVALID_HANDLE_VALUE) {
        NCM_WARN("HID: could not enumerate device interfaces (%s)", lastErrorText(GetLastError()).c_str());
        return found;
    }

    SP_DEVICE_INTERFACE_DATA interfaceData{};
    interfaceData.cbSize = sizeof(interfaceData);

    for (DWORD index = 0; SetupDiEnumDeviceInterfaces(set, nullptr, &hidGuid, index, &interfaceData);
         ++index) {
        DWORD needed = 0;
        SetupDiGetDeviceInterfaceDetailW(set, &interfaceData, nullptr, 0, &needed, nullptr);
        if (needed == 0) continue;

        std::unique_ptr<uint8_t[]> storage(new (std::nothrow) uint8_t[needed]);
        if (!storage) continue;
        auto* detail = reinterpret_cast<SP_DEVICE_INTERFACE_DETAIL_DATA_W*>(storage.get());
        detail->cbSize = sizeof(SP_DEVICE_INTERFACE_DETAIL_DATA_W);
        if (!SetupDiGetDeviceInterfaceDetailW(set, &interfaceData, detail, needed, nullptr, nullptr)) {
            continue;
        }

        // EVERY interface becomes a record, BEFORE any filter can drop it. The previous version filtered
        // first and counted second, so it reported "Windows reports 1 game controller" on a machine with
        // four -- the three it could not open or could not read capabilities from vanished without a word.
        // A device we failed to interrogate and a device that is not there are completely different
        // findings, and only one of them is the game's fault.
        Device device;
        device.path = narrow(detail->DevicePath);
        idsFromPath(detail->DevicePath, device.vendorId, device.productId);

        HANDLE handle = openForQuery(detail->DevicePath);
        if (handle == INVALID_HANDLE_VALUE) {
            device.queryHandleError = lastErrorText(GetLastError());
            found.push_back(std::move(device));
            continue;
        }
        device.queryHandleOpened = true;

        HIDD_ATTRIBUTES attributes{};
        attributes.Size = sizeof(attributes);
        if (HidD_GetAttributes(handle, &attributes)) {
            device.vendorId = attributes.VendorID;
            device.productId = attributes.ProductID;
        }

        PHIDP_PREPARSED_DATA preparsed = nullptr;
        if (HidD_GetPreparsedData(handle, &preparsed) && preparsed) {
            HIDP_CAPS caps{};
            if (HidP_GetCaps(preparsed, &caps) == HIDP_STATUS_SUCCESS) {
                device.usagePage = caps.UsagePage;
                device.usage = caps.Usage;
                device.capsRead = true;
            }
            HidD_FreePreparsedData(preparsed);
        }
        if (!device.capsRead) {
            device.capsError = "preparsed data or caps unavailable";
        }

        wchar_t text[256] = {};
        if (HidD_GetProductString(handle, text, sizeof(text))) device.product = narrow(text);
        text[0] = L'\0';
        if (HidD_GetManufacturerString(handle, text, sizeof(text))) device.manufacturer = narrow(text);
        CloseHandle(handle);

        device.isGameController = isGameController(device.usagePage, device.usage);

        // THE QUESTION THAT DECIDES THE NEXT BUILD. Shared read, no report read, closed at once. If this
        // succeeds while the game is running, a raw-HID reader can have these devices even when
        // DirectInput will not hand them over. Asked of everything, so a device whose caps we could not
        // read still tells us whether it is reachable.
        HANDLE readable = CreateFileW(detail->DevicePath, GENERIC_READ,
                                      FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING, 0,
                                      nullptr);
        if (readable == INVALID_HANDLE_VALUE) {
            device.readHandleError = lastErrorText(GetLastError());
        } else {
            device.readHandleAvailable = true;
            CloseHandle(readable);
        }

        found.push_back(std::move(device));
    }

    SetupDiDestroyDeviceInfoList(set);
    return found;
}

int logGameControllers()
{
    std::vector<Device> devices;
    try {
        devices = scanGameControllers();
    } catch (...) {
        NCM_WARN("HID: enumeration threw -- continuing without it");
        return 0;
    }

    int controllers = 0, unopenable = 0, capsMissing = 0, readable = 0;
    for (const auto& device : devices) {
        if (!device.queryHandleOpened) ++unopenable;
        else if (!device.capsRead) ++capsMissing;
        if (device.isGameController) ++controllers;
        if (device.isGameController && device.readHandleAvailable) ++readable;
    }

    NCM_INFO("HID: %zu interface(s) present; %d could not be opened even for metadata; %d opened but "
             "would not report capabilities; %d classified as game controllers",
             devices.size(), unopenable, capsMissing, controllers);

    for (const auto& device : devices) {
        // Everything that either classified as a controller OR failed to tell us, because the failures
        // are the interesting ones. Keyboards and mice that answered honestly are noise.
        if (!device.isGameController && device.queryHandleOpened && device.capsRead) continue;

        if (!device.queryHandleOpened) {
            NCM_WARN("  HID %04X:%04X UNOPENABLE (%s) %s", device.vendorId, device.productId,
                     device.queryHandleError.c_str(), device.path.c_str());
        } else if (!device.capsRead) {
            NCM_WARN("  HID %04X:%04X no capabilities (%s) \"%s\" -- read handle %s", device.vendorId,
                     device.productId, device.capsError.c_str(),
                     device.product.empty() ? "(no product string)" : device.product.c_str(),
                     device.readHandleAvailable ? "AVAILABLE" : device.readHandleError.c_str());
        } else {
            NCM_INFO("  HID %04X:%04X usage %02X/%02X \"%s\"%s%s -- read handle %s", device.vendorId,
                     device.productId, device.usagePage, device.usage,
                     device.product.empty() ? "(no product string)" : device.product.c_str(),
                     device.manufacturer.empty() ? "" : " by ",
                     device.manufacturer.empty() ? "" : device.manufacturer.c_str(),
                     device.readHandleAvailable ? "AVAILABLE" : device.readHandleError.c_str());
        }
    }

    if (controllers > 0) {
        NCM_INFO("HID: %d of %d game controller(s) can be opened for reading by this process", readable,
                 controllers);
    }
    return controllers;
}

}  // namespace ncm::input::hid
