// NCM Carrier -- what Windows itself thinks is plugged in.
//
// WHY THIS EXISTS. On 2026-09-25 the carrier reported one device -- an Xbox pad -- on a rig with four
// working controllers: a Logitech G29 wheelbase, Thrustmaster pedals, a custom ESP32 rim over Bluetooth
// LE, and the pad. All four are healthy in Windows. The pad is the only one of the four that reaches the
// process through XInput/RAWINPUT; the other three are DirectInput/HID devices.
//
// The owner's standing observation about this game -- that it "only sees one device at a time and is
// picky" -- has an obvious mechanism behind it: acquiring DirectInput devices EXCLUSIVELY. If that is what
// Cyberpunk does, then SDL's DirectInput backend is locked out of exactly the three devices we are missing
// and exactly none of the ones we can see, which fits the evidence without needing a second explanation.
//
// This module does not test that theory by arguing about it. It asks Windows directly, underneath
// DirectInput, and then asks the one question that decides what to build next:
//
//   1. How many HID game controllers does Windows say are present, with what VID/PID and product names?
//   2. Can this process obtain a READ handle to each one **right now, while the game is running**?
//
// If Windows says four and SDL says one, the DirectInput path is the problem, not the hardware. If a read
// handle opens anyway, a raw-HID reader is a viable route and does not need DirectInput's permission --
// which is the same reason Direct Wheel goes through the Logitech SDK for the wheel rather than asking
// DirectInput nicely.
//
// **STRICTLY READ-ONLY, AND DELIBERATELY UNOBTRUSIVE.** Devices are opened for metadata with NO access
// rights at all, which queries without acquiring. The read-handle probe asks for shared read only, reads
// no report, and closes immediately. Nothing here can take a device away from the game.
#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace ncm::input::hid {

struct Device {
    uint16_t vendorId = 0;      // from the interface path when no handle could be opened
    uint16_t productId = 0;
    uint16_t usagePage = 0;
    uint16_t usage = 0;
    std::string path;
    std::string product;        // as Windows reports it, or empty
    std::string manufacturer;

    bool queryHandleOpened = false;     // could we open it at all, even with no access rights?
    std::string queryHandleError;
    bool capsRead = false;              // did it tell us its usage page and usage?
    std::string capsError;
    bool isGameController = false;      // only meaningful when capsRead
    bool readHandleAvailable = false;   // could WE open it for reading, with the game running?
    std::string readHandleError;        // why not, when not
};

/// EVERY present HID interface, classified but never silently dropped. The first version of this filtered
/// before it counted and so reported one controller on a rig with four; a device we could not interrogate
/// and a device that is absent are different findings and must not collapse into the same number.
/// Never throws. Returns an empty list if the HID subsystem is unavailable.
std::vector<Device> scanGameControllers();

/// Enumerate and write the result to the carrier log, including what was dropped and why. Returns how
/// many interfaces classified as game controllers, which is the number SDL ought to be able to match.
int logGameControllers();

}  // namespace ncm::input::hid
