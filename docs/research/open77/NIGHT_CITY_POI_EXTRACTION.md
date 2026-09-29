# Night City points of interest, from the game's own data

> Research extraction, 2026-09-29 (IDEA-736, L224). Static read of the installed game's cooked files; no NCM runtime change and no live PASS. Nothing here is verified in-engine yet.
> Tool: [`tools/world-pois/build_registry.py`](../../../tools/world-pois/build_registry.py). Outputs live in git-ignored `references/world-pois/`, because raw game data is not redistributed.

## Why this exists

L224 makes Night City's publicly accessible places a major input to the sim. Garages matter first: Paddock teams rent garages and share them across the day (IDEA-735). The owner supplied [itemaps.com's map](https://itemaps.com/maps/cyberpunk-2077) (1,027 pins). It has no garage category and no height, and it states no licence, so the game's own data is the primary source, and itemaps is a cross-check.

## What was extracted

| File | Archive | Contents |
|---|---|---|
| `base/worlds/03_night_city/_compiled/default/03_night_city.poimappins` | `ep1/ep1_1_nightcity.archive` | **702** point-of-interest pins, each with world X/Y/Z, entity ID and `journalPathHash` |
| `.../03_night_city.mappins` | same | **4,337** quest and activity pins, plus 41 GPS pins and 5 multi-point pins |
| `base/journal/cooked_journal.journal`, `ep1/journal/cooked_journal.journal` | `ep1/ep1_2_gamedata.archive` | 38,622 journal entries that name those pins |

The Phantom Liberty (`ep1`) archives override the base-game copies, so the data includes Dogtown and 2.x content.

**The key finding.** A cooked pin names its meaning only by `journalPathHash`. That hash is **Murmur3-32 of the `/`-joined journal entry path, seed `0x5EEDBA5E`**. It resolves **702 of 702** points of interest and 4,968 of 5,039 pins overall. FNV-1a and CRC32 variants match nothing.

## What is there

Point-of-interest groups (702): minor activities 194, Phantom Liberty points of interest 164 (111 of them sandbox activities), service points 129 (shops, ripperdocs, gunsmiths, food, clothing, trainers, each named by district, e.g. `wat_kab_ripperdoc_01`), street stories 73, minor quests 56, vehicles for sale 29, tarot 21, Autofixer spots 18, safehouses 10, street races 4, apartments for sale 4.

**Garage and workshop sites.** 229 garage, parking, workshop and Autofixer pins cluster into **102 distinct sites** within 25 m: **53 garages, 23 parking sites, 19 Autofixers, 7 workshops**. Most come from quest and activity pins that mark a real garage: Phantom Liberty courier and car-retrieval garages (25 sites), main-quest garages, and street stories in Westbrook, Heywood, Santo Domingo and the Badlands.

## Limits

- **Pins only mark places the game points at.** A garage that no quest or activity ever marks is not in this data. Finding those needs a second, heavier pass over world streaming sectors (entities such as garage doors and car lifts).
- **A pin position is not a doorway.** Quest pins can sit on a roof, an interior or a trigger volume. Every site needs an in-engine check before a scene uses it (a MASTER_TEST case, dev first under L223).
- **Clustering is naive.** A 25 m radius can merge two neighbouring garages or split one large one.
- **Rights.** NCM carries derived facts (coordinates, category, district) into its own registry, never the raw cooked files, and credits no third-party map. This is ordinary practice for a mod of the same game. It matches how the fuel stations were handled (IDEA-704).

## Reproduce

```powershell
$cli  = ".\tools\WolvenKit.Console-8.20.0\WolvenKit.CLI.exe"
$pc   = "C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077\archive\pc"
$out  = ".\references\world-pois\cooked"
& $cli extract "$pc\ep1\ep1_1_nightcity.archive" --outpath $out --regex "03_night_city\.(poimappins|mappins)$"
& $cli extract "$pc\ep1\ep1_2_gamedata.archive"  --outpath $out --regex "cooked_journal\.journal$"
Get-ChildItem $out -Recurse -Include *.poimappins,*.mappins,*.journal | ForEach-Object { & $cli convert serialize $_.FullName }
python tools\world-pois\build_registry.py
```

Extract named files only. Never pass the game directory to extraction or use a broad wildcard (`NCM_QUEST_SPIKE.md`).

## Next

1. Cross-check against the itemaps pins (same categories, X/Y within tolerance), and against NCM's 20 owner-supplied Autofixer terminals (L206) versus the game's 19 Autofixer sites.
2. Pass two: search streaming sectors for unmarked garages and workshops.
3. Define the NCM place registry as a pure `ncm/core` data module (id, kind, district, position, open hours), feeding the Paddock's garage rental schedule (IDEA-735) and the presence planner.
