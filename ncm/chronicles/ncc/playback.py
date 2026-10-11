"""Playback: one speaker, a priority queue, and no stale commentary.

Items carry an expiry in wall-clock time. Before an item plays it is checked again: a race beat that waited behind a
news bulletin past its moment is DROPPED (traced), not played late. Higher-priority items (Race Control, News) go to
the front of the queue but never cut an utterance off mid-word. A short gap separates items so the Narrator returns
"naturally" after a segment rather than butting in.

Audio goes out through winsound (stdlib, Windows) from a rendered WAV, so the game keeps its own audio device.
Captions (the sanitized transcript) can go to RibbonOS over its existing UDP contract (ribbon_bridge.py:
{"type":"subtitle","text":...,"voice":...}).
"""
from __future__ import annotations

import heapq
import itertools
import json
import socket
import threading
import time
from dataclasses import dataclass, field
from typing import Callable, Optional


@dataclass(order=True)
class Item:
    sort_key: tuple
    wav: str = field(compare=False)
    station: str = field(compare=False)
    transcript: str = field(compare=False)
    expires_at: float = field(compare=False)
    trace_id: str = field(compare=False)
    duration: float = field(compare=False, default=0.0)


class Player:
    def __init__(self, on_result: Callable[[Item, str], None], play: bool = True, gap_s: float = 0.8,
                 ribbon: Optional[tuple] = None, max_depth: int = 4):
        self.q: list = []
        self.cv = threading.Condition()
        self.counter = itertools.count()
        self.on_result = on_result
        self.play_audio = play
        self.gap_s = gap_s
        self.ribbon = ribbon
        self.max_depth = max_depth
        self.busy = False
        self._stop = False
        self.t = threading.Thread(target=self._run, daemon=True)
        self.t.start()

    def submit(self, wav: str, station: str, priority: int, transcript: str, ttl_s: float, trace_id: str,
               duration: float) -> None:
        it = Item((-priority, next(self.counter)), wav, station, transcript, time.time() + ttl_s, trace_id, duration)
        with self.cv:
            heapq.heappush(self.q, it)
            # a full queue sheds its lowest-priority, newest item: silence beats a backlog
            while len(self.q) > self.max_depth:
                worst = max(self.q)
                self.q.remove(worst)
                heapq.heapify(self.q)
                self.on_result(worst, "dropped: queue full")
            self.cv.notify()

    def idle(self) -> bool:
        with self.cv:
            return not self.q and not self.busy

    def drain(self, timeout: float = 600) -> None:
        end = time.time() + timeout
        while time.time() < end and not self.idle():
            time.sleep(0.1)

    def stop(self) -> None:
        with self.cv:
            self._stop = True
            self.cv.notify()

    def _caption(self, it: Item) -> None:
        if not self.ribbon:
            return
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.sendto(json.dumps({"type": "subtitle", "text": it.transcript, "voice": it.station}).encode("utf-8"), self.ribbon)
            s.close()
        except OSError:
            pass

    def _run(self) -> None:
        while True:
            with self.cv:
                while not self.q and not self._stop:
                    self.cv.wait()
                if self._stop:
                    return
                it = heapq.heappop(self.q)
                self.busy = True
            try:
                if time.time() > it.expires_at:
                    self.on_result(it, f"dropped: stale by {time.time() - it.expires_at:.1f}s before playback")
                    continue
                self._caption(it)
                if self.play_audio:
                    import winsound
                    winsound.PlaySound(it.wav, winsound.SND_FILENAME)
                else:
                    time.sleep(min(it.duration, 0.05))
                self.on_result(it, "played" if self.play_audio else "rendered (audio off)")
                time.sleep(self.gap_s if self.play_audio else 0)
            except Exception as e:  # a playback failure is a trace line, never a crash
                self.on_result(it, f"playback failed: {e}")
            finally:
                with self.cv:
                    self.busy = False
