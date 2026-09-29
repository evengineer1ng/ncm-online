#pragma once

#include "pad/pad_model.hpp"

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
    void setFfbStrength(float strength);   // legacy magnitude
    void setFfbFraction(float fraction);   // the slider, 0..1 of the ceiling
    float ffbFraction() const;
    void resetFfbPeaks();                  // zero the per-channel peak readouts
    float ffbCeiling() const;              // for the attached wheel
    void setRatedTorque(float nm);         // 0 = recognised/assumed
    void setFfbSpring(float strength);
    void setFfbDamper(float strength);
    void setFfbTexture(float strength);
    void setFfbEngine(float strength);
    void setFfbRoad(float strength);
    void setFfbCollision(float strength);
    void testPulse(float strength = 0.25f);
    std::string deviceJson() const;
    /// Every live DirectInput device as a gamepad-layer source, keyed `di:<VID:PID>`: buttons `b<n>`,
    /// hats `hat<n>_<dir>`, axes normalised -1..1. What the rim looks like to the mapping engine when
    /// DirectInput CAN see it; SDL3 covers it when it cannot.
    void rawSamples(pad::Samples& out) const;
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
    float ffbCollision() const;
    feel::DeviceClass deviceClass() const;
    void setDeviceClass(const std::string& name);
    void setSteerDegrees(float degrees);

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};
}
