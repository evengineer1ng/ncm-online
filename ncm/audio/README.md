# NCM Audio (package `ncm-audio`)

The continuous sound of NCM's physics (NCM FX, 2026-10-12): engines whose pitch and gain follow throttle and exhaust
speed, strokes and hops, cold-gas puffs, the roar of entry, sonic booms, the experimental drives.

| Piece | Where | Job |
|---|---|---|
| `ncm_audio.dll` | `red4ext/plugins/ncm_audio/` | loopback transport (127.0.0.1:38800-38803) + a miniaudio mixer |
| `pack/*.wav` | `red4ext/plugins/ncm_audio/pack/` | the voices, synthesised by `tools/render_pack.py` (NCM-owned, no samples) |
| `ncm_audio` resource | `ncm/online/resources/ncm_audio/` | forwards the voices ncm_world's renderer (`client/fx.lua`) asks for |

What sounds is decided in core (`presentation.fx` + `presentation.fx_cues`): a cue names a voice and maps physical
quantities to its pitch and gain. The DLL only mixes: looping voices glide to their targets and fade out when no
longer named; one-shots play once; position becomes stereo pan and distance gain from the listener (the car).

## Safety

- **Nothing outlives the feed.** A dropped socket fades every voice out.
- **Only its own pack.** A file name with a path separator, `..` or anything but `[A-Za-z0-9._-]` is refused.
- **Only this game's process tree may connect.** A second game instance on the same PC walks to the next port.

## Build

`powershell -File tools\build-audio.ps1`: the DLL, the math tests, the pack, and `dist/ncm-audio-<version>.zip`.
