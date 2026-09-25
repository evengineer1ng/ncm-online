#include "ffb/mixer.hpp"

#include "input/devices.hpp"
#include "log.hpp"

#include <algorithm>
#include <cmath>

namespace ncm::ffb {
namespace {

double unitOf(double v) { return std::min(1.0, std::abs(v)); }

}  // namespace

Mixer::Mixer(input::Devices* devices) : devices_(devices)
{
    const auto cls = devices_ ? devices_->deviceClass() : DeviceClass::Unknown;
    out_ = std::make_unique<Output>(cls);

    // Start at the middle rung rather than the floor: the floor is a safety bound, not a sensible default,
    // and a first-run wheel that does nothing reads as broken.
    const auto rungs = ladder(cls);
    setRung(static_cast<int>(rungs.size()) / 2);

    if (devices_ && devices_->haptic()) out_->arm(devices_->haptic());
    last_ = std::chrono::steady_clock::now();
}

Mixer::~Mixer() { shutdown(); }

void Mixer::setRung(int index)
{
    const auto cls = devices_ ? devices_->deviceClass() : DeviceClass::Unknown;
    const auto rungs = ladder(cls);
    if (rungs.empty()) return;
    rungIndex_ = std::clamp(index, 0, static_cast<int>(rungs.size()) - 1);
    rung_ = rungs[static_cast<size_t>(rungIndex_)];
}

void Mixer::observe(const char* channel, double value, bool live)
{
    auto& record = observed_[channel];
    record.frames += 1;
    record.live = record.live || live;
    const double magnitude = std::abs(value);
    if (magnitude > record.max) record.max = magnitude;
}

void Mixer::feed(const bridge::Frame& frame)
{
    const auto now = std::chrono::steady_clock::now();
    const double dt = std::chrono::duration<double>(now - last_).count();
    last_ = now;
    started_ = true;

    // `idle` is an instruction, not silence. A car we can no longer see must not keep pushing at the wheel
    // with the last frame we happened to hold.
    if (frame.idle) {
        level_ = slew(level_, 0.0, dt);
        torque_ = slew(torque_, 0.0, dt);
        emit();
        return;
    }

    double contributions = 0.0;

    if (frame.hasEngine) {
        engineRatio_ = std::clamp(frame.engine, 0.0, 1.0);
        // Never zero at idle: a running engine is felt even stopped at a light, and a wheel that goes
        // completely dead reads as a disconnection.
        const double hum = 0.25 + 0.75 * engineRatio_;
        contributions += 1.2 * tune_.engine * hum;
        observe("engine", frame.engine, true);
    }

    // Slip is MEASURED, not derived (`IDEA-376`) -- these three come off the client snapshot directly, which
    // is the whole reason the feel model can be honest about grip without any engine RTTI.
    if (frame.hasSlipTotal) { contributions += 2.5 * tune_.texture * unitOf(frame.slipTotal); observe("slipTotal", frame.slipTotal, true); }
    if (frame.hasSlipLong)  { contributions += 1.5 * tune_.texture * unitOf(frame.slipLong);  observe("slipLong", frame.slipLong, true); }
    if (frame.hasSlipLat)   { contributions += 2.0 * tune_.texture * unitOf(frame.slipLat);   observe("slipLat", frame.slipLat, true); }

    if (frame.hasSuspLong) {
        contributions += 1.2 * tune_.road * std::min(1.0, std::abs(frame.suspLong) * kRoadScale);
        observe("suspLong", frame.suspLong, true);
    }
    if (frame.hasSuspLat) {
        contributions += 1.2 * tune_.road * std::min(1.0, std::abs(frame.suspLat) * kRoadScale);
        observe("suspLat", frame.suspLat, true);
    }

    const double intensity = std::min(1.0, contributions);
    const double target = clamp(devices_ ? devices_->deviceClass() : DeviceClass::Unknown, intensity * rung_);
    level_ = slew(level_, target, dt);

    // Self-aligning torque: the weight that pulls a real wheel back toward centre, and it builds with speed
    // because a stationary car has none. Full effect by roughly 70 km/h.
    if (frame.hasSteering && frame.hasSpeed) {
        const double loading = std::min(1.0, std::abs(frame.speed) / 20.0);
        const double direction = (frame.steering > 0.0) ? 1.0 : -1.0;
        const double want = -direction * unitOf(frame.steering) * loading * rung_;
        torque_ = slew(torque_, want, dt);
        observe("steering", frame.steering, true);
    } else {
        torque_ = slew(torque_, 0.0, dt);
    }

    emit();
}

void Mixer::emit()
{
    if (out_) out_->write(level_, torque_, engineRatio_);
}

void Mixer::silence()
{
    level_ = 0.0;
    torque_ = 0.0;
    if (out_) out_->stop();
}

void Mixer::shutdown()
{
    if (!out_) return;
    // Destroy, never merely stop -- see IDEA-412 in output.hpp.
    out_->destroy();
    out_.reset();

    if (started_) {
        // The KB-106 measurement, printed where it cannot be missed. If `suspLong`/`suspLat` peaked far
        // below 1.0 then `kRoadScale` is wrong and the road channel has been inaudible all session.
        for (const auto& [channel, record] : observed_) {
            NCM_INFO("measured %s: peak %.5f over %ld frame(s)%s", channel.c_str(), record.max,
                     record.frames, record.max < 0.05 ? "  <-- too small to feel" : "");
        }
    }
}

std::string Mixer::describe() const
{
    char buffer[256];
    const auto cls = devices_ ? devices_->deviceClass() : DeviceClass::Unknown;
    std::snprintf(buffer, sizeof(buffer), "%s rung %d/%zu (%.2f of %.2f), %s",
                  nameOf(cls), rungIndex_ + 1, ladder(cls).size(), rung_, ceilingFor(cls),
                  (out_ && out_->armed()) ? "armed" : "not armed");
    return buffer;
}

}  // namespace ncm::ffb
