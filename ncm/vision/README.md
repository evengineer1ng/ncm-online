# NCM Vision

The vanilla scanner's green render in NCM Online, without the scanner (`IDEA-679`).

- **Hold Tab** for green while held. **Tap Caps Lock** to toggle it. These are the game's own Vision Hold and
  Vision Toggle bindings, so a player's rebinds carry over.
- It works on foot and while driving.
- There is **no scan HUD, no walk-only restriction and no slow motion.** It makes only the render call,
  `VisionModeSystem.EnterMode(player, Focus)`. The scanner controller that OPEN//77 refuses is never used.

Redscript only: one file, vanilla symbols only, no per-frame work, and it never consumes the key. It is a
separate package from the Carrier and the Rig Bridge and shares nothing with them.

Build: `tools\build-vision.ps1`. This compiles the script against vanilla plus every installed script in a
scratch cache before it zips. Deploy as a hosted required mod with `--id ncm-vision`. The `.reds` is
executable content, so the world must be unsecured or the hash verified.

Evidence and reasoning: `docs/research/open77/evidence/2026-09-28/scanner-vision-look.md`.
