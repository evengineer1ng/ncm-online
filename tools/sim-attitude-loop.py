"""One attitude axis of the AV as flown on 2026-10-13: game at 60 Hz; the flight computer runs every `every` frames;
it reads the attitude `lagF` frames late, estimates the rate by finite difference smoothed with `a`; the torque it asks
for reaches the body through the fans' first-order throttle lag `tau` (differential thrust). Start tilted 5 deg."""
import math


def run(K_ATT, K_RATE, a=0.35, tau=0.35, every=3, lagF=4, maxAcc=2.5, T=20.0, kickDeg=5.0):
    dt = 1 / 60
    th, w = math.radians(kickDeg), 0.0
    act = 0.0                      # angular acceleration actually delivered
    hist = [th] * (lagF + 2)
    cmd, west, prev = 0.0, 0.0, th
    peak_late = 0.0
    n = int(T / dt)
    for i in range(n):
        hist.append(th)
        if i % every == 0:
            seen = hist[-1 - lagF]
            wraw = (seen - prev) / (dt * every)
            prev = seen
            west += (wraw - west) * a
            wantW = K_ATT * (0 - seen)
            cmd = max(-maxAcc, min(maxAcc, K_RATE * (wantW - west)))
        act += (cmd - act) * (dt / tau if tau > 0 else 1)
        w += act * dt
        th += w * dt
        if i * dt > T - 5:
            peak_late = max(peak_late, abs(th))
    return math.degrees(peak_late)


print("current K_ATT 2.2 K_RATE 5.0 :", round(run(2.2, 5.0), 2), "deg peak in the last 5 s")
for ka, kr in [(1.5, 3.0), (1.2, 2.5), (1.0, 2.0), (0.8, 1.6), (0.6, 1.2)]:
    for a in (0.35, 0.7):
        print("K_ATT", ka, "K_RATE", kr, "smooth", a, ":", round(run(ka, kr, a=a), 3), "| lag 8 frames:", round(run(ka, kr, a=a, lagF=8), 3))
