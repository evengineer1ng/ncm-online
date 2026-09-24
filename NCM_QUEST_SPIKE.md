# NCM Native Quest Spike

Date: 2026-09-03  
Scope: establish a verified native journal pattern before enabling any NCM quest behavior.

## Safety boundary

- The historical failure was a looping `NCPD: Assault in Progress` activity.
- Do not reactivate the legacy race-quest bridge as the implementation path.
- Do not attach `QuestStaticMappinDefinition/DefaultQuestVariant` markers without a valid owning journal quest.
- Do not toggle entries Inactive → Active from an update loop to force notifications.
- The first runtime proof has no map pin and no race-state dependency.
- Deployment begins behind an independent quest-spike kill switch. Existing phone and racing behavior must remain available when the spike is disabled.

## Repository diagnosis

The current NCM journal contains only the `contacts` primary folder. It has no `quests` primary folder and no `gameJournalQuest`, `gameJournalQuestPhase`, or `gameJournalQuestObjective` entries.

`MTERaceQuestEvent` in `MTEQuestNav.reds` does not manipulate the Journal. It only writes the `ncm_race_active` quest fact. The current `MTERaceRuntime.PlaceRaceMappins`, `ClearRaceMappins`, and `TrackRaceMappin` methods are no-ops.

Separately, `MTEcosystemHUD.reds` registers race markers as `Mappins.QuestStaticMappinDefinition` with `DefaultQuestVariant`. Because no NCM journal quest owns those markers, this orphaned quest classification is the leading repository-backed explanation for the vanilla NCPD fallback seen in earlier tests. This remains an inference until reproduced or disproved in game.

The Lua constant `ENABLE_QUEST_UI_BRIDGE` is currently `true`, despite comments in `init.lua` describing the experimental quest/SMS bridge as disabled. It also gates race-state and SMS synchronization, so it must not be flipped casually. The new quest controller must have a separate switch.

## Known-good vanilla reference

Source archive:

```text
C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077\archive\pc\content\basegame_4_gamedata.archive
```

Exact extracted member:

```text
base\journal\cooked_journal.journal
```

Local reference:

```text
references\vanilla-journal\cooked\base\journal\cooked_journal.journal
references\vanilla-journal\cooked\base\journal\cooked_journal.journal.json
```

Safe reproduction commands:

```powershell
& ".\tools\WolvenKit.Console-8.20.0\WolvenKit.CLI.exe" extract `
  --path "C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077\archive\pc\content\basegame_4_gamedata.archive" `
  --outpath ".\references\vanilla-journal\cooked" `
  --regex "cooked_journal\.journal$" `
  --verbosity Minimal

& ".\tools\WolvenKit.Console-8.20.0\WolvenKit.CLI.exe" convert serialize `
  ".\references\vanilla-journal\cooked\base\journal\cooked_journal.journal" `
  --verbosity Minimal
```

Do not pass the game directory to extraction and do not use a broad wildcard.

## Verified minimal hierarchy

Vanilla quest `quests/meta/10_survive` provides a minimal, mapless example:

```text
gameJournalPrimaryFolderEntry  id=quests
└── gameJournalFolderEntry     id=meta
    └── gameJournalQuest       id=10_survive, type=MainQuest
        └── gameJournalQuestPhase      id=01_survive
            └── gameJournalQuestObjective id=01_survive
```

Required quest fields observed:

- `districtID`
- `entries`
- `id`
- `journalEntryOverrideDataList`
- `recommendedLevelID`
- localized `title`
- `type`

Required phase fields observed:

- `entries`
- `id`
- `journalEntryOverrideDataList`
- `locationPrefabRef`

Required objective fields observed:

- `counter`
- localized `description`
- `districtID`
- `entries`
- `id`
- `itemID`
- `journalEntryOverrideDataList`
- `locationPrefabRef`
- `optional`

No map-pin child is required for a valid objective. That is intentional for the `Contact Dex` proof.

For later race routing, vanilla `gameJournalQuestMapPin` children carry `enableGPS = 1`, mappin data, and an entity or node reference. NCM does not have stable authored world references for generated race starts, so Phase 1 retains the already working Lua `CustomPositionVariant` waypoint for GPS rather than inventing journal map-pin references.

## Proposed NCM proof paths

```text
quests/ncm/ncm_onboarding
quests/ncm/ncm_onboarding/contact_dex
quests/ncm/ncm_onboarding/contact_dex/contact_dex
```

Classes:

```text
gameJournalQuest
gameJournalQuestPhase
gameJournalQuestObjective
```

Initial copy:

- Quest title: `Night City Motorsports`
- Objective: `Contact Dex`

The proof contains no journal mappin, description attachment, codex link, phone entry, or dynamic race text.

## Required runtime experiment

- [x] Add the three-entry hierarchy and localization to the recovered WolvenKit project.
- [x] Deserialize and repack it; confirm the new archive lists only the intended two resources.
- [x] Add an isolated REDscript controller with explicit `activate`, `complete`, `status`, and `disable` operations.
- [x] Default the controller to inert; enable it manually for the first test. No load/update callback invokes it.
- [x] On activation, apply parent-to-child state once and request tracking once.
- [ ] Log the previous and resulting state of every path; runtime state lookup still needs a verified API.
- [x] On completion, complete objective, phase, then quest once; do not reactivate automatically.
- [ ] Confirm the phone/SMS command IDs and routes are byte/logically unchanged.
- [ ] Run the NCPD regression matrix from `NCM_PHASE1_PLAYTEST.md`.
- [ ] Only after the static proof passes, connect activation to normal session onboarding and completion to an existing Dex interaction.

### Offline build evidence

- Project journal path: `quests/ncm/ncm_onboarding/contact_dex/contact_dex`.
- Quest class/type: `gameJournalQuest` / `SideQuest`.
- The objective contains no map-pin child.
- Localization keys: `9000300` (`Night City Motorsports`) and `9000301` (`Contact Dex`).
- Packed spike archive: `references/quest-spike-pack/archive.archive`.
- Packed archive SHA-256: `19BC55A316D8F3F12902848DF7536ED345BDF92E9FB074F577AD5CC7D6330C02`.
- Archive inventory contains exactly:
  - `mt_ecosystem\journal\mt_ecosystem.journal`
  - `mt_ecosystem\localization\en-us\onscreens\mt_ecosystem.json`
- Re-extracted journal serialized successfully and retained the quest hierarchy and LocKeys.
- Runtime payload now contains `MTEQuestSpike.reds` and four manual CET helpers: `NCM_QuestSpikeEnable()`, `NCM_QuestSpikeActivate()`, `NCM_QuestSpikeComplete()`, and `NCM_QuestSpikeDisable()`.
- No helper is called automatically. Enabling the spike alone does not activate the quest.
- Deployed spike build compiled successfully in the game on 2026-09-03 at 04:04 local time. `redscript_rCURRENT.log` reports `Compilation complete` and saved `final.redscripts.modded` with `MTEQuestSpike.reds` in the input list.
- This is offline structural evidence only. No runtime activation claim has been made.

### First controlled runtime sequence

Run each command separately in CET and observe the Journal/notifications between steps:

```lua
NCM_QuestSpikeEnable()
NCM_QuestSpikeActivate()
```

After activation, do not invoke `Activate` again. Check the Journal and tracker, idle for five minutes, open/close menus, fast travel, save, and reload. If any NCPD activity or notification loop appears, immediately run:

```lua
NCM_QuestSpikeDisable()
```

The spike has no automatic callback, so disabling prevents any later manual operation; it does not alter phone or race state. If the quest remains stable, complete it once:

```lua
NCM_QuestSpikeComplete()
NCM_QuestSpikeDisable()
```

## Pass criteria

- `Night City Motorsports` appears under the intended journal category.
- `Contact Dex` appears once and can be tracked.
- Save/reload preserves one coherent state.
- Completion removes it from active tracking and records it in completed quests as expected.
- No `NCPD: Assault in Progress` or other vanilla activity notification appears.
- Disabling the spike stops all further quest operations without affecting SMS, Quick Race, or active racing.
