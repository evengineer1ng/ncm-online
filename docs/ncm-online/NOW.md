# NOW - the single next-action index

> **STATUS: LEDGER** - living session memory, rewritten at the end of every working session.
> Authority map: [INDEX.md](INDEX.md).

**LATEST 2026-10-02 - BOTH SERVERS ON OPEN//77 `2.31.21+op77.124`; DEV CLIENT MODS RESTORED (L290).**
- Pre-upgrade state is preserved in [SERVER_BASELINE_2026-10-02.md](archive/SERVER_BASELINE_2026-10-02.md) and pushed checkpoint commit `6628744` on `checkpoint/pre-op77-upgrade-2026-10-02`. Development still requires eight hosted packages; Online still requires its original three with digest `879af328...`. Online NCM code, required mods, and data remain frozen at Baseline 1.
- The Windows Development server is running on `.124` with 44 loaded resources and unchanged required-mod digest `8dc855d1...`. The raw-address Development join needs local mod installation: all eight packages were installed into the game with a reversible record under `%LOCALAPPDATA%/NCM/dev-mods/20261002-132708`, and their NCM RED4ext plugins were removed from the ignore list. The owner has not yet rejoined to confirm Rig Bridge and Scanner.
- Online is active on `.124`; its three mod blobs still hash correctly, the public HTTPS manifest is unchanged, and the prior server tree is backed up at `/opt/ncm/backups/server-20261002T172506Z`.
- Explained the nearby-player bubble: the Paddock field gets physical vehicles around a player and keeps them present while the player stays close; it is not a separate race type.
- Fixed actual oval bubble spawning to select NCM Pace RaceDrive clones. Corrected the canonical and all four resource session-kernel copies so DNS happens at green, and active drivers are not timed out by the generic short oval limits. Oval limits: 60 minutes, 20-minute finish window, extended while a human keeps moving.
- Paddock grid ring now draws through native marker APIs directly. Restarted private dev at 12:45 ET; 44 Lua resources started and resource generation 1 published. No tests run (not requested).
- **THE ONE NEXT ACTION:** rejoin Development and confirm Rig Bridge and Scanner load after the local reinstall. Then live check the grid ring and oval race behavior. The MariaDB SQL 1292 persistence failure (KB-281) remains unresolved.
