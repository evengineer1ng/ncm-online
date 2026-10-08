NIGHT CITY MOTORSPORTS 3.0 (alpha) -- single player
===================================================

NCM runs on Race Weeks. Race Week follows real time, including while you are away. When a Race Week ends,
competition regenerates around a new seed and your machines return to Night City. Some things you learn and
build may persist.

TAPES
  A tape is one NCM continuity: its own Race Week clock and its own history. It is not a Cyberpunk save:
  loading an older save never rewinds a tape, and starting a new tape never changes another one.
  Choose a tape from the game's own menus: NIGHT CITY MOTORSPORTS on the main menu or the pause menu (Esc).
  A choice made on the main menu is used when your save finishes loading; one made from the pause menu at once.
  Nothing of NCM runs until you choose. "CYBERPUNK WITHOUT NCM" leaves NCM dormant.
  While a tape is in play, the Race Week line (tape, Race Week, day, time to the next possible end) is on the HUD.

REQUIREMENTS
  RED4ext, redscript, Codeware. No Cyber Engine Tweaks: NCM 3.0 does not use CET.
  NCM's own plugins (Carrier, Rig Bridge, Scanner, Broadcast, Pace) are reached directly when installed.

WHERE YOUR NCM DATA LIVES (red4ext/plugins/ncm_host)
  ncm.sqlite3              every tape's world (one database; each tape is its own server id inside it)
  save/ncm_tapes.json      the tape index (+ .bak, the previous copy)
  ncm_host.log             what NCM did this session (readable while the game runs)

GOING BACK TO ORDINARY CYBERPUNK
  1. Any session: choose CYBERPUNK WITHOUT NCM from the menu. Nothing of NCM runs.
  2. To remove NCM entirely: tools/install-ncm3-kimiko.ps1 -Uninstall (or delete red4ext/plugins/ncm_host and
     r6/scripts/ncm_host). Your Cyberpunk saves are not modified by NCM's tapes. What a session WITH NCM can leave
     in a save is only what happened in the world while it ran: where V was standing (NCM can move V at a Race
     Week reset), a car you claimed into V's garage, and anything the game itself saved.
  To keep your NCM history for later, copy ncm.sqlite3 and the save folder somewhere safe first.
