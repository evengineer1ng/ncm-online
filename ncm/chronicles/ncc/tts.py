"""TTS: Piper (offline, ONNX) behind one small interface.

The engine returns float32 mono audio and its sample rate. Everything acoustic (EQ, rooms, ambience, stingers)
happens afterwards in `scene.py`, so a different TTS engine only has to implement `synth`.
"""
from __future__ import annotations

import os
import threading
import wave
from typing import Dict, Tuple

import numpy as np


class PiperEngine:
    def __init__(self, voice_dir: str):
        self.voice_dir = voice_dir
        self._voices: Dict[str, object] = {}
        self._lock = threading.Lock()

    def _voice(self, name: str):
        with self._lock:
            v = self._voices.get(name)
            if v is None:
                from piper import PiperVoice
                path = os.path.join(self.voice_dir, name + ".onnx")
                if not os.path.exists(path) or os.path.getsize(path) == 0:
                    raise FileNotFoundError(f"voice {name} missing at {path} (python -m piper.download_voices)")
                v = PiperVoice.load(path)
                self._voices[name] = v
            return v

    def synth(self, voice: str, text: str, length_scale=None, noise_scale=None, noise_w_scale=None,
              sentence_gap_s: float = 0.0) -> Tuple[np.ndarray, int]:
        """Synthesize `text`. Piper yields one chunk per sentence; `sentence_gap_s` inserts silence between them
        (measured: Piper itself leaves almost none, so the gap is a real performance control we own)."""
        from piper import SynthesisConfig
        v = self._voice(voice)
        cfg = SynthesisConfig(length_scale=length_scale, noise_scale=noise_scale, noise_w_scale=noise_w_scale)
        parts, sr = [], v.config.sample_rate
        for chunk in v.synthesize(text, syn_config=cfg):
            sr = chunk.sample_rate
            if parts and sentence_gap_s > 0:
                parts.append(np.zeros(int(sentence_gap_s * sr), dtype=np.float32))
            parts.append(chunk.audio_float_array.astype(np.float32))
        if not parts:
            return np.zeros(1, dtype=np.float32), sr
        return np.concatenate(parts), sr


def write_wav(path: str, x: np.ndarray, sr: int) -> None:
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    y = np.clip(x, -1.0, 1.0)
    pcm = (y * 32767.0).astype("<i2")
    if pcm.ndim == 2:
        channels = pcm.shape[1]
    else:
        channels = 1
    with wave.open(path, "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())


def read_wav(path: str) -> Tuple[np.ndarray, int]:
    with wave.open(path, "rb") as w:
        sr, ch, n = w.getframerate(), w.getnchannels(), w.getnframes()
        data = np.frombuffer(w.readframes(n), dtype="<i2").astype(np.float32) / 32767.0
    if ch > 1:
        data = data.reshape(-1, ch).mean(axis=1)
    return data, sr
