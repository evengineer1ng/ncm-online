# What Piper actually responds to (measured 2026-10-08)

Raw numbers: [TTS_PROBE_RESULTS.md](TTS_PROBE_RESULTS.md) (`tools/tts_probe.py`; the same sentence, 3 syntheses per
variant, voices en_US-ryan-high and en_GB-alba-medium, piper-tts 1.8.0).

| control | effect | used? |
|---|---|---|
| commas | +0.9 s and ~3 real pauses (0.25-0.3 s each) per sentence | **yes**: the main phrasing tool |
| sentence fragments ("On the last lap. And lost it.") | +1.2 s, real pauses, pitch reset per sentence, slightly louder | **yes**: the turn of a story gets its own sentence |
| inter-sentence gap | Piper emits one chunk per sentence with ~no silence; we insert our own | **yes**: per station (`sentence_gap_s`) |
| `length_scale` | linear tempo (0.85 -> -9 %, 1.25 -> +15 %) | **yes**: per station |
| `noise_scale` | no measurable change at 0.2-1.0 | set per station, not relied on |
| `noise_w_scale` | small at 0.2-1.0; **at 1.4 the high-quality voice breaks** (14 s, 19 pauses) | capped at 0.95 |
| `?` | slight pitch lift | allowed |
| `!`, `!!!` | barely measurable; `!!!` = `!` | collapsed to one |
| ellipses `...`, dashes `--` | **nothing** (dropped by the phonemizer) | rewritten into commas / sentence breaks |
| CAPS for stress | **nothing** | long all-caps words respelled normally |
| paragraph breaks | nothing beyond a sentence break | not used |

Consequence for `perform.py`: phrasing is commas, sentence breaks and our own gaps; tempo is `length_scale`;
everything else that "looks expressive" in a script is removed before Piper sees it. Acoustic identity therefore lives
in the scene (`scene.py`), not in punctuation tricks: see [SCENE_REPORT.md](SCENE_REPORT.md).
