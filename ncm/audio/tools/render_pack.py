"""NCM Audio's pack: every voice `presentation.fx_cues` VOICES names, synthesised here (NCM-owned, no samples, no
licences). Loops are rendered seamless (the last 0.25 s cross-faded into the start); one-shots are dry hits.
Pure Python (no numpy on the build VM): mono 16-bit WAV at 22,050 Hz, which miniaudio decodes natively.

    python -I ncm/audio/tools/render_pack.py [out_dir]     (default: ncm/audio/pack)

Deterministic: a fixed seed per voice, so a re-render is byte-identical."""
import math
import os
import random
import struct
import sys
import wave

SR = 22050
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "pack")


def write(name, samples):
    os.makedirs(OUT, exist_ok=True)
    peak = max(1e-9, max(abs(s) for s in samples))
    k = 0.89 / peak
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s * k)) * 32767)) for s in samples))
    print("%-18s %5.2f s" % (name, len(samples) / SR))


def loop(samples, xfade_s=0.25):
    """Seamless loop: the tail is cross-faded into the head and dropped."""
    n = int(xfade_s * SR)
    body = samples[: len(samples) - n]
    tail = samples[len(samples) - n:]
    for i in range(n):
        a = i / n
        body[i] = body[i] * a + tail[i] * (1 - a)
    return body


class Noise:
    def __init__(self, seed):
        self.r = random.Random(seed)
        self.b = [0.0] * 7

    def white(self):
        return self.r.uniform(-1, 1)

    def pink(self):   # Paul Kellet's economy filter
        w = self.white()
        b = self.b
        b[0] = 0.99886 * b[0] + w * 0.0555179
        b[1] = 0.99332 * b[1] + w * 0.0750759
        b[2] = 0.96900 * b[2] + w * 0.1538520
        b[3] = 0.86650 * b[3] + w * 0.3104856
        b[4] = 0.55000 * b[4] + w * 0.5329522
        b[5] = -0.7616 * b[5] - w * 0.0168980
        out = b[0] + b[1] + b[2] + b[3] + b[4] + b[5] + b[6] + w * 0.5362
        b[6] = w * 0.115926
        return out * 0.11


class LP:   # one-pole low-pass
    def __init__(self, hz):
        self.a = 1 - math.exp(-2 * math.pi * hz / SR)
        self.y = 0.0

    def __call__(self, x):
        self.y += self.a * (x - self.y)
        return self.y


class HP:
    def __init__(self, hz):
        self.lp = LP(hz)

    def __call__(self, x):
        return x - self.lp(x)


def band(hz_lo, hz_hi):
    hp, lp = HP(hz_lo), LP(hz_hi)
    return lambda x: lp(hp(x))


def render(seconds, fn):
    return [fn(i, i / SR) for i in range(int(seconds * SR))]


def rocket_roar():
    n, lp1, lp2 = Noise(1), LP(900), LP(140)
    def f(i, t):
        x = n.pink()
        crackle = (n.white() if n.r.random() < 0.004 else 0) * 0.6
        return lp1(x) * 0.8 + lp2(n.white()) * 2.2 + crackle * 0.3
    return loop(render(4.25, f))


def fusion_hum():
    n, lp = Noise(2), LP(3000)
    def f(i, t):
        s = 0.0
        for h, a in ((55, 1.0), (110, 0.5), (165, 0.25), (220, 0.18), (440, 0.06)):
            s += a * math.sin(2 * math.pi * h * t + h)
        s *= 0.8 + 0.2 * math.sin(2 * math.pi * 0.5 * t)
        return s * 0.6 + lp(n.white()) * 0.08
    return loop(render(4.25, f))


def jet_whine():
    n, bd = Noise(3), band(600, 4000)
    def f(i, t):
        vib = 1 + 0.004 * math.sin(2 * math.pi * 5 * t)
        return bd(n.white()) * 0.7 + 0.25 * math.sin(2 * math.pi * 2400 * vib * t) + 0.12 * math.sin(2 * math.pi * 1200 * t)
    return loop(render(3.25, f))


def fan():
    n, bd = Noise(4), band(150, 900)
    def f(i, t):
        am = 0.6 + 0.4 * (0.5 + 0.5 * math.sin(2 * math.pi * 38 * t))
        return bd(n.white()) * am
    return loop(render(3.25, f))


def sputter():
    base = rocket_roar()
    r = random.Random(5)
    out, gate, hold = [], 1.0, 0
    for s in base:
        if hold <= 0:
            gate, hold = (1.0 if r.random() < 0.55 else 0.05), int(r.uniform(0.04, 0.18) * SR)
        hold -= 1
        out.append(s * gate)
    return loop(out, 0.1)


def thump(seed, f0, f1, dur, noise_amt, ring=None):
    n, lp = Noise(seed), LP(1500)
    def f(i, t):
        env = math.exp(-t * 6 / dur)
        hz = f1 + (f0 - f1) * math.exp(-t * 12)
        s = math.sin(2 * math.pi * hz * t) * env
        s += lp(n.white()) * noise_amt * math.exp(-t * 30)
        if ring:
            s += 0.25 * math.sin(2 * math.pi * ring * t) * math.exp(-t * 9)
        return s
    return render(dur, f)


def click():
    n = Noise(6)
    return render(0.03, lambda i, t: n.white() * math.exp(-t * 300) + math.sin(2 * math.pi * 3000 * t) * math.exp(-t * 200))


def cold_gas():
    n, hp = Noise(7), HP(2500)
    return loop(render(2.25, lambda i, t: hp(n.white()) * (0.9 + 0.1 * math.sin(2 * math.pi * 7 * t))))


def entry_roar():
    n, lp = Noise(8), LP(400)
    def f(i, t):
        crackle = n.white() * 1.5 if n.r.random() < 0.01 else 0
        return lp(n.pink() * 3) * (0.8 + 0.2 * math.sin(2 * math.pi * 0.7 * t)) + crackle * 0.2
    return loop(render(4.25, f))


def wind():
    n, bd = Noise(9), band(300, 1400)
    return loop(render(4.25, lambda i, t: bd(n.white()) * (0.6 + 0.4 * math.sin(2 * math.pi * 0.31 * t) * math.sin(2 * math.pi * 0.13 * t))))


def boom():
    n, lp = Noise(10), LP(220)
    def f(i, t):
        s = 0.0
        for t0 in (0.0, 0.14):
            u = t - t0
            if u >= 0:
                s += math.exp(-u * 9) * (lp(n.white()) * 4 + math.sin(2 * math.pi * 38 * u))
        return s
    return render(1.6, f)


def impact():
    return thump(11, 160, 60, 0.7, 1.4, ring=640)


def drive_rise():
    def f(i, t):
        s = 0.0
        for h, a in ((220, 1), (330, 0.5), (440, 0.35), (661, 0.2)):
            s += a * math.sin(2 * math.pi * h * t) * (0.7 + 0.3 * math.sin(2 * math.pi * (h / 220) * 0.5 * t))
        return s * 0.5
    return loop(render(3.25, f))


def drive_field():
    def f(i, t):
        trem = 0.75 + 0.25 * math.sin(2 * math.pi * 3 * t)
        return trem * (math.sin(2 * math.pi * 98 * t) + 0.6 * math.sin(2 * math.pi * 147 * t) + 0.4 * math.sin(2 * math.pi * 196.5 * t)) * 0.4
    return loop(render(4.25, f))


def mouth_hum():
    n, lp = Noise(12), LP(200)
    def f(i, t):
        ph = 2 * math.pi * 41 * t
        return (math.sin(ph) + math.sin(ph * 1.006 + 1) + 0.5 * math.sin(ph * 2.013)) * 0.4 + lp(n.white()) * 0.6
    return loop(render(5.25, f))


VOICES = {
    "rocket_roar.wav": rocket_roar, "fusion_hum.wav": fusion_hum, "jet_whine.wav": jet_whine, "fan.wav": fan,
    "sputter.wav": sputter, "pulse_thump.wav": lambda: thump(13, 140, 38, 0.7, 1.0),
    "ram_thump.wav": lambda: thump(14, 110, 30, 0.9, 1.6, ring=420), "click.wav": click, "cold_gas.wav": cold_gas,
    "entry_roar.wav": entry_roar, "wind.wav": wind, "boom.wav": boom, "impact.wav": impact,
    "drive_rise.wav": drive_rise, "drive_field.wav": drive_field, "mouth_hum.wav": mouth_hum,
}

if __name__ == "__main__":
    for name, fn in VOICES.items():
        write(name, fn())
