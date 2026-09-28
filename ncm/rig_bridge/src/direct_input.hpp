#pragma once

#include "config.hpp"

#include <atomic>
#include <memory>
#include <string>
#include <thread>

namespace ncm::rig {

class DirectInputRig {
public:
    explicit DirectInputRig(Config config);
    ~DirectInputRig();
    DirectInputRig(const DirectInputRig&) = delete;
    DirectInputRig& operator=(const DirectInputRig&) = delete;

    bool start();
    void stop();
    void setFfbEnabled(bool enabled);
    void setFfbArmed(bool armed);
    void setFfbStrength(float strength);
    void setFfbSpring(float strength);
    void setFfbDamper(float strength);
    void setFfbTexture(float strength);
    void setFfbEngine(float strength);
    void setFfbRoad(float strength);
    void testPulse(float strength = 0.25f);
    std::string deviceJson() const;
    /// Assign a role to a device+axis chosen in the panel. `device` is the stable VID:PID key; empty
    /// clears the role. Returns false only for an unknown role name.
    bool bind(const std::string& role, const std::string& device, const std::string& axis,
              bool invert, float deadzone = -1.0f);
    void persist(const std::wstring& directory) const;
    const Config& config() const;
    bool hasFfb() const;
    bool ffbArmed() const;
    float ffbStrength() const;
    float ffbSpring() const;
    float ffbDamper() const;
    float ffbTexture() const;
    float ffbEngine() const;
    float ffbRoad() const;
    feel::DeviceClass deviceClass() const;
    void setDeviceClass(const std::string& name);
    void setSteerDegrees(float degrees);

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};
}
