# Night City Motorsports 2.0 Package Audit

This folder is the isolated 2.0 release payload, built from the current live runtime footprint rather than from the CET workspace state.

## Package scope

Included roots:
- `bin/x64/plugins/cyber_engine_tweaks/mods/MT_Ecosystem`
- `archive/pc/mod`
- `r6/scripts/MT_Ecosystem`
- `r6/tweaks/MT_Ecosystem`

Runtime payload file count before this audit document was added:
- `1.83`: 58 files
- `2.0`: 76 files

## Explicitly included runtime assets

CET mod payload:
- `init.lua`
- `data/*.lua`
- `modules/*.lua`
- `README.md`
- `NCM_2_0_SYSTEMS.md`
- `VOICE_GUIDE.md`

Archive / XL payload:
- `archive/pc/mod/mt_ecosystem.archive`
- `archive/pc/mod/mt_ecosystem.xl`
- `archive/pc/mod/mt_ecosystem_localization.xl`
- `archive/pc/mod/mt_ecosystem_named_rivals.xl`
- `archive/pc/mod/mt_ecosystem_named_rivals/localization/en-us/onscreens/mt_ecosystem_named_rivals.json`

REDscript payload:
- `r6/scripts/MT_Ecosystem/*.reds`

Tweaks payload:
- `r6/tweaks/MT_Ecosystem/mt_ecosystem_named_rivals.yaml`

## Explicitly excluded non-release artifacts

Excluded on purpose:
- `save/**`
- `.venv/**`
- `*.bak*`
- `*.vortex_backup`
- `log.txt`
- `db.sqlite3`
- `temp_roster.csv`
- `user_nodes.json`
- `ncm_race_state.json`
- `xbox2_to_vjoy1.py`
- Vortex marker files such as `__folder_managed_by_vortex`
- ad hoc backup folders such as `RadioOSBridge-abtest-backup-*`

These are runtime outputs, local tooling, or backup debris and should not ship in the release.

## New package-level payload since 1.83

New runtime roots/assets now required by 2.0:
- `archive/pc/mod/mt_ecosystem.archive`
- `archive/pc/mod/mt_ecosystem.xl`
- `archive/pc/mod/mt_ecosystem_localization.xl`
- `archive/pc/mod/mt_ecosystem_named_rivals.xl`
- `archive/pc/mod/mt_ecosystem_named_rivals/localization/en-us/onscreens/mt_ecosystem_named_rivals.json`
- `r6/tweaks/MT_Ecosystem/mt_ecosystem_named_rivals.yaml`

New CET data files since 1.83:
- `data/contact_event_archetypes.lua`
- `data/vehicle_slot_profiles.lua`

New CET modules since 1.83:
- `modules/ambient_races.lua`
- `modules/betting.lua`
- `modules/contact_events.lua`
- `modules/fan_engine.lua`
- `modules/management.lua`
- `modules/named_rivals.lua`
- `modules/phone_bridge.lua`
- `modules/race_commands.lua`
- `modules/voice_harness.lua`

## What changed since 1.83

2.0 is not just an incremental Lua patch. The runtime footprint expanded in four major directions:

1. Management and ambient simulation
- offscreen race simulation
- broader management/career orchestration
- betting, fan economy, and supporting telemetry/state systems

2. Phone, SMS, and journal-driven control flow
- REDscript phone/journal bridge remains central
- CET now has shared command routing through `phone_bridge.lua` and `race_commands.lua`
- package now depends on the archive/localization layer that supports the newer contact and message flows

3. Named rivals and richer identity content
- named rivals now have dedicated CET logic, tweak data, and localization payload
- roster identity depth and rival presentation moved beyond the older 1.83 baseline

4. Vehicle/build depth and supporting systems
- hardware/build-aware systems expanded across AI, parts, garage, tuning, and race orchestration
- additional data layers such as vehicle slot profiles and contact-event archetypes support the newer runtime

## Packaging conclusion

`release2.0` is the correct clean package base for Night City Motorsports 2.0.
It includes the full current runtime footprint and excludes save data, logs, backups, and local development residue that polluted the first raw compare.
