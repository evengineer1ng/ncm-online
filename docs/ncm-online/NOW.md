# NOW - the single next-action index

> **STATUS: LEDGER** - living session memory, rewritten at the end of every working session.
> Authority map: [INDEX.md](INDEX.md).

**LATEST 2026-10-02 - OVAL BUBBLE VEHICLE AND RACE CLASSIFICATION FIX DEPLOYED (L289, IDEA-838, KB-279/280).**
- Read-only pre-update server inventory captured in [SERVER_BASELINE_2026-10-02.md](archive/SERVER_BASELINE_2026-10-02.md): both servers still advertise OPEN//77 `2.31.21+op77.120`; Development requires eight hosted client packages, Online three. The Online freeze remains in force. The launcher-version rejection has not been traced to an exact compatibility rule.
- Explained the nearby-player bubble: the Paddock field gets physical vehicles around a player and keeps them present while the player stays close; it is not a separate race type.
- Fixed actual oval bubble spawning to select NCM Pace RaceDrive clones. Corrected the canonical and all four resource session-kernel copies so DNS happens at green, and active drivers are not timed out by the generic short oval limits. Oval limits: 60 minutes, 20-minute finish window, extended while a human keeps moving.
- Paddock grid ring now draws through native marker APIs directly. Restarted private dev at 12:45 ET; 44 Lua resources started and resource generation 1 published. No tests run (not requested).
- **THE ONE NEXT ACTION:** live check that the grid ring is visible; run an oval and confirm the near-player NPC pace, human lap progression, and finish classification. These behaviors remain unverified in-game. Startup also logged repeated MariaDB SQL 1292 failures in one NCM League 33-statement transaction (KB-281); its affected persistence path is unresolved and should be investigated.
