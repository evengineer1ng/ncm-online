"""Acoustic scenes: each station lives in its own space.

    narrator      audiobook / impossible clean space: warm, close, almost dry, nothing from the street reaches it
    studio        news booth: presence, tight compression, a small dead room
    race_control  motorsport comms: band-limited radio, saturation, hiss, squelch, a far PA slap
    street        location recording: handheld mic band, outdoor reflections, distance, live traffic/crowd bed
    garage        workshop/paddock: hard metallic room, tools, hum, a distant engine

Everything is numpy (FFT EQ, FFT convolution with synthesized impulse responses, block compressor), so there is
no native dependency. Ambience is procedural and seeded per item: a placeholder you replace by dropping a WAV bed
into `assets/beds/<scene>.wav` (looped and level-matched automatically). Output: stereo float32 at the voice rate.
"""
from __future__ import annotations

import os
from dataclasses import dataclass, field
from typing import List, Optional, Tuple

import numpy as np

from .tts import read_wav


# ------------------------------------------------------------------------------------------------ primitives
def db(x: float) -> float:
    return 10 ** (x / 20.0)


def fft_eq(x: np.ndarray, sr: int, points: List[Tuple[float, float]]) -> np.ndarray:
    """Zero-phase EQ: gain (dB) interpolated over log frequency between `points`."""
    n = len(x)
    if n < 8:
        return x
    nfft = 1 << (n - 1).bit_length()
    X = np.fft.rfft(x, nfft)
    f = np.fft.rfftfreq(nfft, 1.0 / sr)
    pts = sorted(points)
    lf = np.log10(np.maximum(f, 1.0))
    g = np.interp(lf, [np.log10(max(p[0], 1.0)) for p in pts], [p[1] for p in pts])
    y = np.fft.irfft(X * (10 ** (g / 20.0)), nfft)[:n]
    return y.astype(np.float32)


def band(x, sr, lo, hi, slope_db=24.0):
    return fft_eq(x, sr, [(20, -slope_db * 2 if lo > 40 else 0), (lo * 0.5, -slope_db), (lo, 0), (hi, 0),
                          (min(hi * 1.6, sr / 2 - 1), -slope_db), (sr / 2, -slope_db * 2)])


def convolve(x: np.ndarray, h: np.ndarray) -> np.ndarray:
    n = len(x) + len(h) - 1
    nfft = 1 << (n - 1).bit_length()
    return np.fft.irfft(np.fft.rfft(x, nfft) * np.fft.rfft(h, nfft), nfft)[:n].astype(np.float32)


def impulse(sr: int, rng: np.random.Generator, rt60: float, predelay_ms: float = 0.0,
            early: Optional[List[Tuple[float, float]]] = None, bright: float = 0.0) -> np.ndarray:
    length = int(sr * (predelay_ms / 1000.0 + rt60 * 1.1)) + 1
    h = np.zeros(length, dtype=np.float32)
    h[0] = 1.0
    for ms, g in (early or []):
        i = int(sr * ms / 1000.0)
        if i < length:
            h[i] += g
    start = int(sr * predelay_ms / 1000.0)
    tail_n = length - start
    t = np.arange(tail_n) / sr
    tail = rng.standard_normal(tail_n).astype(np.float32) * np.exp(-6.91 * t / max(rt60, 0.05))
    tail = fft_eq(tail, sr, [(100, -6), (500, 0), (3000, bright), (8000, -6 + bright * 1.5)])
    h[start:] += tail * 0.35
    return h


def reverb(x, sr, rng, rt60, mix, predelay_ms=0.0, early=None, bright=0.0):
    wet = convolve(x, impulse(sr, rng, rt60, predelay_ms, early, bright))
    dry = np.pad(x, (0, len(wet) - len(x)))
    wet = wet / (np.max(np.abs(wet)) + 1e-9) * (np.max(np.abs(dry)) + 1e-9)
    return (dry * (1 - mix) + wet * mix).astype(np.float32)


def compress(x, sr, threshold_db=-20.0, ratio=3.0, attack_ms=5.0, release_ms=80.0, makeup_db=0.0):
    blk = max(1, int(sr * 0.005))
    nb = (len(x) + blk - 1) // blk
    pad = np.pad(x, (0, nb * blk - len(x)))
    lvl = np.sqrt(np.mean(pad.reshape(nb, blk) ** 2, axis=1) + 1e-12)
    ldb = 20 * np.log10(lvl)
    over = np.maximum(0.0, ldb - threshold_db)
    target = -over * (1 - 1 / ratio)
    a = np.exp(-5.0 / max(attack_ms, 0.1))
    r = np.exp(-5.0 / max(release_ms, 0.1))
    g = np.zeros(nb)
    cur = 0.0
    for i in range(nb):
        coef = a if target[i] < cur else r
        cur = coef * cur + (1 - coef) * target[i]
        g[i] = cur
    gains = np.repeat(10 ** ((g + makeup_db) / 20.0), blk)[:len(x)]
    return (x * gains).astype(np.float32)


def saturate(x, drive=2.0):
    return (np.tanh(x * drive) / np.tanh(drive)).astype(np.float32)


def rms_norm(x, target_db):
    r = np.sqrt(np.mean(x ** 2)) + 1e-9
    return (x * (db(target_db) / r)).astype(np.float32)


def fade(x, sr, fin=0.01, fout=0.05):
    y = x.copy()
    a, b = int(sr * fin), int(sr * fout)
    if a:
        y[:a] *= np.linspace(0, 1, a, dtype=np.float32)
    if b:
        y[-b:] *= np.linspace(1, 0, b, dtype=np.float32)
    return y


def noise_pink(n, rng):
    w = rng.standard_normal(n)
    X = np.fft.rfft(w)
    f = np.arange(len(X), dtype=np.float64)
    f[0] = 1
    return np.fft.irfft(X / np.sqrt(f), n).astype(np.float32)


def noise_brown(n, rng):
    w = rng.standard_normal(n)
    X = np.fft.rfft(w)
    f = np.arange(len(X), dtype=np.float64)
    f[0] = 1
    return np.fft.irfft(X / f, n).astype(np.float32)


def norm(x):
    return (x / (np.max(np.abs(x)) + 1e-9)).astype(np.float32)


# ------------------------------------------------------------------------------------------------ ambience beds
def bed_street(n, sr, rng):
    t = np.arange(n) / sr
    rumble = band(norm(noise_brown(n, rng)), sr, 30, 400) * 0.5
    hiss = band(norm(noise_pink(n, rng)), sr, 400, 6000) * 0.12 * (0.7 + 0.3 * np.sin(2 * np.pi * 0.07 * t + rng.uniform(0, 6)))
    out = rumble + hiss
    # pass-bys: a filtered swell with a falling centre (the doppler you hear as the car goes past)
    for _ in range(rng.integers(1, 3)):
        c = rng.uniform(0.15, 0.85) * n / sr
        w = rng.uniform(1.2, 2.2)
        env = np.exp(-((t - c) / (w / 2.5)) ** 2)
        car = norm(noise_pink(n, rng))
        lo_part = band(car, sr, 60, 900)
        hi_part = band(car, sr, 900, 5000)
        mixw = np.clip(0.5 + (c - t) / w, 0, 1)
        out += (lo_part * (1.2 - mixw * 0.6) + hi_part * mixw * 0.8) * env * rng.uniform(0.6, 1.0)
    # crowd murmur: band noise with syllable-rate wobble
    mur = band(norm(noise_pink(n, rng)), sr, 250, 2500)
    wob = np.abs(np.convolve(rng.standard_normal(n // 200 + 2), np.ones(3) / 3, mode="same"))
    out += mur * np.interp(t, np.linspace(0, n / sr, len(wob)), wob).astype(np.float32) * 0.25
    # a distant horn, once in a while
    if rng.random() < 0.6:
        c = rng.uniform(0.2, 0.8) * n / sr
        seg = (t > c) & (t < c + rng.uniform(0.25, 0.6))
        horn = (np.sign(np.sin(2 * np.pi * 415 * t)) + np.sign(np.sin(2 * np.pi * 523 * t))) * seg
        out += band(horn.astype(np.float32), sr, 300, 2200) * 0.05
    return norm(out)


def bed_garage(n, sr, rng):
    t = np.arange(n) / sr
    hum = (np.sin(2 * np.pi * 60 * t) * 0.5 + np.sin(2 * np.pi * 120 * t) * 0.3 + np.sin(2 * np.pi * 180 * t) * 0.1) * 0.08
    room = band(norm(noise_pink(n, rng)), sr, 80, 3000) * 0.15
    out = (hum + room).astype(np.float32)
    # clanks: inharmonic decaying partials (metal on metal)
    for _ in range(rng.integers(2, 5)):
        at = int(rng.uniform(0.05, 0.9) * n)
        L = min(n - at, int(sr * 0.6))
        if L <= 0:
            continue
        tt = np.arange(L) / sr
        f0 = rng.uniform(600, 1400)
        k = sum(np.sin(2 * np.pi * f0 * r * tt) * np.exp(-tt * d) for r, d in ((1, 9), (1.73, 14), (2.61, 20), (3.9, 30)))
        out[at:at + L] += (k * rng.uniform(0.2, 0.45)).astype(np.float32)
    # an air ratchet burst
    if rng.random() < 0.8:
        at = int(rng.uniform(0.1, 0.7) * n)
        L = min(n - at, int(sr * rng.uniform(0.4, 0.8)))
        tt = np.arange(L) / sr
        gate = (np.sin(2 * np.pi * 22 * tt) > 0.3).astype(np.float32)
        out[at:at + L] += band(rng.standard_normal(L).astype(np.float32), sr, 1500, 7000) * gate * 0.25
    # a distant engine blip through a wall
    if rng.random() < 0.7:
        at = int(rng.uniform(0.2, 0.6) * n)
        L = min(n - at, int(sr * 1.6))
        tt = np.arange(L) / sr
        f = 38 + 55 * np.exp(-((tt - 0.5) / 0.35) ** 2)
        ph = 2 * np.pi * np.cumsum(f) / sr
        eng = sum(np.sin(ph * h) / h for h in range(1, 9)).astype(np.float32) * np.minimum(1, tt * 4) * np.minimum(1, (tt[-1] - tt) * 3)
        out[at:at + L] += band(eng, sr, 30, 700) * 0.3
    return norm(out)


def bed_radio(n, sr, rng):
    return band(rng.standard_normal(n).astype(np.float32), sr, 500, 4000) * 0.3


BEDS = {"street": bed_street, "garage": bed_garage, "race_control": bed_radio}


def load_bed(scene: str, n: int, sr: int, rng, assets: str) -> Optional[np.ndarray]:
    path = os.path.join(assets, "beds", scene + ".wav")
    if os.path.exists(path):
        x, bsr = read_wav(path)
        if bsr != sr:
            x = np.interp(np.arange(0, len(x), bsr / sr), np.arange(len(x)), x).astype(np.float32)
        reps = int(np.ceil(n / max(1, len(x))))
        start = int(rng.integers(0, max(1, len(x))))
        return norm(np.tile(x, reps + 1)[start:start + n])
    gen = BEDS.get(scene)
    return gen(n, sr, rng) if gen else None


# ------------------------------------------------------------------------------------------------ presets
@dataclass
class Preset:
    name: str
    eq: List[Tuple[float, float]]
    band: Optional[Tuple[float, float]] = None
    comp: Tuple[float, float] = (-22.0, 2.5)
    drive: float = 0.0
    rt60: float = 0.0
    mix: float = 0.0
    predelay_ms: float = 0.0
    early: List[Tuple[float, float]] = field(default_factory=list)
    bright: float = 0.0
    bed_db: Optional[float] = None       # bed level relative to the voice
    preroll_s: float = 0.0
    tail_s: float = 0.25
    pan: float = 0.0                      # -1 left .. +1 right
    width: float = 0.0                    # stereo decorrelation of the bed
    target_db: float = -19.0
    squelch: bool = False


PRESETS = {
    "narrator": Preset("narrator", eq=[(60, -12), (90, 0), (160, 2.0), (500, 0), (3000, 1.5), (9000, 1.0)],
                       comp=(-24.0, 2.5), rt60=0.35, mix=0.05, predelay_ms=8, bright=-2, target_db=-18.0, tail_s=0.4),
    "studio": Preset("studio", eq=[(80, -12), (110, 0), (250, -1.5), (2500, 3.0), (5000, 2.5), (10000, 0.5)],
                     comp=(-26.0, 4.0), rt60=0.18, mix=0.05, early=[(3.5, 0.15)], target_db=-17.0),
    "race_control": Preset("race_control", eq=[(1500, 4.0)], band=(320, 3300), comp=(-28.0, 6.0), drive=2.6,
                           rt60=1.3, mix=0.10, predelay_ms=60, early=[(95, 0.28), (180, 0.12)], bed_db=-34.0,
                           preroll_s=0.15, tail_s=0.3, target_db=-18.0, squelch=True),
    "street": Preset("street", eq=[(5000, -4.0), (900, 1.5)], band=(170, 6800), comp=(-24.0, 2.0), rt60=0.75, mix=0.16,
                     predelay_ms=12, early=[(12, 0.35), (27, 0.22), (41, 0.15)], bed_db=-15.0, preroll_s=1.3,
                     tail_s=1.1, pan=-0.15, width=0.8, target_db=-20.0),
    "garage": Preset("garage", eq=[(400, 1.5), (2500, 2.0), (7000, -2.0)], band=(110, 8200), comp=(-24.0, 3.0), rt60=0.95,
                     mix=0.22, predelay_ms=6, early=[(7, 0.4), (15, 0.3), (23, 0.2)], bright=3.0, bed_db=-13.0,
                     preroll_s=1.0, tail_s=0.8, pan=0.12, width=0.6, target_db=-19.0),
}


def render(voice: np.ndarray, sr: int, preset_name: str, seed: int = 0, assets: str = "") -> np.ndarray:
    """Voice (mono) -> the scene (stereo float32, same rate)."""
    p = PRESETS[preset_name]
    rng = np.random.default_rng(seed)
    x = voice.astype(np.float32)
    x = x / (np.max(np.abs(x)) + 1e-9) * 0.8
    if p.band:
        x = band(x, sr, *p.band)
    x = fft_eq(x, sr, p.eq)
    if p.drive:
        x = saturate(x, p.drive)
    x = compress(x, sr, p.comp[0], p.comp[1], makeup_db=0.0)
    if p.rt60:
        x = reverb(x, sr, rng, p.rt60, p.mix, p.predelay_ms, p.early, p.bright)
    x = rms_norm(x, p.target_db)
    pre, tail = int(sr * p.preroll_s), int(sr * p.tail_s)
    v = np.concatenate([np.zeros(pre, np.float32), x, np.zeros(tail, np.float32)])
    n = len(v)
    L = v * np.sqrt(0.5 * (1 - p.pan)) * np.sqrt(2)
    R = v * np.sqrt(0.5 * (1 + p.pan)) * np.sqrt(2)
    if p.bed_db is not None:
        bedL = load_bed(p.name, n, sr, rng, assets)
        if bedL is not None:
            bedR = np.roll(bedL, int(sr * 0.013 * p.width)) if p.width else bedL
            if p.width:
                bedR = (bedR * p.width + bedL * (1 - p.width))
            voice_rms = np.sqrt(np.mean(x ** 2)) + 1e-9
            scale = voice_rms * db(p.bed_db) / (np.sqrt(np.mean(bedL ** 2)) + 1e-9)
            env = np.ones(n, np.float32)
            fi, fo = int(sr * min(0.6, p.preroll_s or 0.05)), int(sr * min(0.8, p.tail_s or 0.05))
            env[:fi] = np.linspace(0, 1, fi)
            env[n - fo:] = np.linspace(1, 0, fo)
            L = L + bedL * scale * env
            R = R + bedR * scale * env
    out = np.stack([L, R], axis=1)
    if p.squelch:
        out = np.concatenate([squelch(sr, rng), out, squelch(sr, rng, close=True)])
    peak = np.max(np.abs(out)) + 1e-9
    if peak > 0.98:
        out = out * (0.98 / peak)
    return out.astype(np.float32)


def squelch(sr, rng, close=False):
    n = int(sr * (0.09 if close else 0.12))
    t = np.arange(n) / sr
    s = band(rng.standard_normal(n).astype(np.float32), sr, 800, 5000) * np.exp(-t * (40 if close else 25)) * 0.25
    s[: int(sr * 0.004)] += 0.5 if not close else 0.3        # the key click
    return np.stack([s, s], axis=1).astype(np.float32)
