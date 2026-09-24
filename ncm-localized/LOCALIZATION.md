# NCM localization contributor guide

NCM uses `locales/en-us.json` as its authoritative Lua catalog. Copy
`locales/translator-template.json` to `<locale>.json`, set `locale`, and translate
values only. Never edit keys, Lua, Redscript, IDs, save fields, or placeholders.

Run the audit from the repository root:

```powershell
$env:UV_CACHE_DIR="$PWD\.uv-cache"
uv run --no-project python tools/ncm_i18n.py validate --strict
```

`context.json` records source locations, surfaces, placeholders, and protected
names. UTF-8 is required. Keep `{rival_name}`, `{position}`, `{credits}` and all
other named placeholders exactly as written. Plural entries must contain
`other`; supported forms are `one`, `few`, `many`, and `other`.

## Work packages

- Core UI: keys beginning `ui.`
- Settings: keys beginning `settings.`
- Race HUD: keys beginning `hud.`
- SMS contacts: keys beginning `sms.`
- Parts/economy: the data catalog generated from `data/` (maintainer-owned until
  its migration pass lands)
- Journal choices: ArchiveXL/WolvenKit catalog, handled separately from Lua

Submit catalogs only. The maintainer integrates and validates them.

## Voice and terminology

- NCM: Night City Motorsports. Treat it as a proper organization name.
- eddies: Eurodollars; retain the natural Cyberpunk term for the target locale.
- grid: the staged race starting order, not a street power grid.
- heat: district attention/pressure unless the context says a scheduled race.
- DNF: did not finish. Use the conventional motorsport abbreviation if one exists.
- rolling start, qualifying, knockout, sprint, drag, endurance: use established
  motorsport terminology and keep a term consistent across UI, HUD, and SMS.
- Rico/scout text is clipped and information-dense. Stu/mechanic text is direct,
  technical, and conversational. Race-control text is terse and authoritative.

Do not translate Night City, Dogtown, district names, character names, rival
names, vehicle models, or manufacturers. Prefer concise HUD text; allow roughly
35% expansion in ordinary UI and SMS. Do not change units embedded in a source
entry without maintainer approval.

## Static phone/journal content

Lua catalogs cover runtime-generated messages. Static phone contacts, choices,
and journal messages are cooked into `mt_ecosystem.archive` and require the
canonical WolvenKit project. Preserve all journal IDs and `LocKey#9000xxx`
values. The distributed archive is not an editable volunteer source.

The canonical WolvenKit project was not present in the NCM 2.0 distribution used
for this refactor. It must be restored from the maintainer's source history before
static journal translations can be safely generated. Do not recreate journal
resources with new IDs: that would break routing and existing saves.
