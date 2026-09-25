// NCM Carrier -- settings that live beside the DLL.
//
// Deliberately tiny. Everything that is a PLAYER choice -- strength, which device -- belongs in the NCM
// panel and arrives over the bridge, because a player should not edit a file to turn their wheel down.
// What is here is what must be known before the bridge exists.
#pragma once

#include <cstdint>
#include <string>

namespace ncm {

struct Config {
    uint16_t port = 38480;        // the port the companion used; the resource's DEFAULT_URL still points here
    bool enableHook = true;       // final-command authority; off leaves effects and feel working
    bool enableFfb = true;

    static Config load(const std::wstring& directory);
};

}  // namespace ncm
