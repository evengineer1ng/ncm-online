# NCM AV

Required mod for NCM Online. One TweakXL file: it points `Vehicle.av_zetatech_atlus` at the base-game Atlus entity,
which has a chassis collider. Phantom Liberty's override of that entity does not, so without this the AV has no
rigid body and nothing can fly it (KB-467). Vanilla assets only.

Build: `python tools/build-ncm-av.py` -> `dist/ncm-av-<version>.zip`.
