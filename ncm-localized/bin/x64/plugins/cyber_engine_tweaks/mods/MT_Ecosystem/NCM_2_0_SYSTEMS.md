# NCM 2.0 Systems

This document turns the 2.0 pitch into implementation language that matches the current MT_Ecosystem codebase.

The goal is not to invent a second game next to the current mod.

The goal is to extend the systems that already exist:

- `MTE.Careers` for career-scoped progression and persistence
- `MTE.Roster` for seeded driver pools and driver stats
- `MTE.Championships` for scheduled seasons and standings
- `MTE.Racing` for live race state, route config, field simulation, and in-world execution
- `modules/event_definitions.lua` for canonical event snapshots
- `MTE.Roots` and `MTE.Routes` for route selection and route resolution
- `MTE.Settings` for CET-facing world tuning
- `race_commands.lua` and `MTEJournalHandler.reds` for SMS and contact delivery

## Current Nomenclature

2.0 should use the names the project already uses.

### Prestige Tiers

It is:

- `Gonk`
- `Streetkid`
- `Solo`
- `Fixer`
- `Edgerunner`

This prestige ladder already lives in `modules/careers.lua` and should remain the backbone for progression, field quality, stake limits, and roster pressure.

### Driver Stats

Roster drivers are already built around seeded stats and mutable race history.

Core live stats already in use:

- `pace`
- `aggression`
- `precision`
- `consistency`
- `rivalScore`
- `headToHeadWins`
- `wins`
- `recentFinishes`
- `currentTier`
- `rep`

Do not replace these with a new management vocabulary like `discipline` unless it is explicitly mapped to an existing field. In practice, `precision` and `consistency` already cover most of that design space.

### Event Types

Current event handling already recognizes:

- `sprint`
- `drag`
- `knockout`

`Racing.RACE_TYPES` still includes `endurance`, but the active event-definition and championship path is centered on `sprint`, `drag`, and `knockout`. Ambient and management phase one should stay aligned to that path.

### Difficulty, Field Size, Districts

Current custom/quick race nomenclature already exists and should be reused:

- Difficulty bands: `Street`, `Serious`, `Elite`
- Field sizes: `4-car`, `6-car`, `8-car`, `10-car`
- District keys and labels: `Watson`, `Westbrook`, `Heywood`, `Pacifica`, `Santo Domingo`, `City Center`, `Badlands`

### Faction Layer

The player-facing team/faction layer already exists in the career schema:

- `playerFactionMode`
- `playerFactionId`
- `playerFactionName`
- `playerFactionColor`
- `activeSeasonId`
- `seasons`

This matters because Management Mode is not a fresh concept. The shell is already there in `careers.lua` and `championships.lua`.

## System Positioning

NCM 2.0 is a layered ecosystem.

- Ambient Races make the city move without the player.
- SMS lets the player read and influence that movement.
- Management Mode lets the player operate inside that movement as something larger than a single driver.

That is one loop, not three disconnected features.

## Ambient Races

### Definition

Ambient Races are career-scoped, background-simulated race events that can become in-world races when the player is near enough for them to matter.

They are not cutscenes.

They are not scripted encounters.

They are scheduled race events built out of the same event model already used by championship and live race systems.

### Core Rule

Ambient Races should be career-scoped, not account-global.

Reason:

- `Roster` is seeded per career.
- `Championships` are stored per career.
- rivalry, recent finishes, and faction standings are already mutated per career.
- betting context and phone commentary are already tied to the active career.

If Ambient Races are made account-global, they will fight the architecture that already exists.

If they are made career-scoped, they plug directly into `MTE.Careers`, `MTE.Roster`, and `MTE.Championships`.

### Recommended Ownership

Add a new module:

- `modules/ambient_races.lua`

Primary responsibilities:

- schedule ambient event windows for the active career
- resolve event candidates using `EventDefinitions`, `Roots`, `Routes`, and knockout circuits
- simulate off-screen outcomes using `Roster` driver stats
- promote eligible events into in-world staged/live races when the player is nearby
- feed lightweight intel into Rico, Billie, Foreman, and the Fan layer

### Data Model

Ambient events should reuse the existing event shape, not invent a parallel race object.

Base event creation should go through:

- `EventDefinitions.buildPointToPoint(...)`
- `EventDefinitions.buildKnockout(...)`

Then attach ambient-specific metadata.

Recommended shape:

```lua
AmbientRaceEvent = {
    eventId = "ambient_...",
    sourceType = "ambient_schedule",
    eventType = "sprint" | "drag" | "knockout",
    raceType = "sprint" | "drag" | "knockout",
    district = "Westbrook",
    districtLabel = "Westbrook",
    trackName = "...",
    titleLabel = "...",
    nodeA = { ... } or nil,
    nodeB = { ... } or nil,
    circuitId = "..." or nil,
    fieldSize = 6,
    startType = "grid",
    routeMode = "scheduled" | "root" | "circuit",
    allowCombat = false,
    allowStakes = false,
    timeOfDay = "night" | "day" | nil,

    ambientState = "scheduled" | "staging" | "active" | "completed" | "expired",
    scheduledDay = 12,
    scheduledWindowStartHour = 19,
    scheduledWindowEndHour = 22,
    activationHour = nil,
    resolveHour = nil,

    field = { driverId1, driverId2, ... },
    highlightedDriverIds = { ... },
    simulatedResults = nil,
    playerObserved = false,
    playerInterfered = false,
    promotedToWorld = false,
}
```

The important constraint is this:

- `eventId`, route fields, district fields, and event-type fields stay compatible with current event handling
- only lifecycle and scheduling metadata are new

### Scheduling Logic

Ambient scheduling should not be exact.

It should be pattern-readable.

Meaning:

- the player should learn that some districts are hotter at certain times
- the player should not know the exact minute an event will go live

Recommended scheduler inputs:

- active career tier from `career.tier`
- active career config from `career.config`
- district weighting table
- in-game day index
- in-game hour window
- ambient frequency settings from `Settings.current`

Recommended district activity profile for phase one:

- `Watson`: frequent lower-pressure sprint and drag activity
- `Westbrook`: strong night activity, higher prestige fields
- `Heywood`: mixed sprint activity, moderate aggression
- `Pacifica`: volatile fields, more chaos-heavy race reads
- `Santo Domingo`: drag-friendly and industrial sprint-friendly
- `City Center`: cleaner, higher-prestige events
- `Badlands`: longer routes, more faction flavor, more nomad presence

These should be weight tables, not hard locks.

### Scheduling Windows

Each ambient event should be created with a window, not a timestamp.

Example:

- `scheduledWindowStartHour = 19`
- `scheduledWindowEndHour = 22`

The actual activation time should be rolled inside the window.

This gives the player pattern recognition without turning the world into a train timetable.

### Field Selection

Ambient fields should come from `Roster`, not from a separate ambient-only driver pool.

Use:

- prestige tier bounds compatible with current quick/custom logic
- current driver `currentTier`
- `wins`, `recentFinishes`, `rivalScore`, and `headToHeadWins` to season the field
- faction diversity where possible

Phase one should prefer readable fields over maximum realism.

That means:

- 4 to 8 total cars most of the time
- 10-car ambient fields should be rare and high-load
- knockout should be rarer than sprint/drag

### Lifecycle

Ambient lifecycle should be independent from `Racing.STATE`, but capable of promoting into it.

Ambient lifecycle:

- `scheduled`
- `staging`
- `active`
- `completed`
- `expired`

Live race lifecycle remains:

- `idle`
- `config`
- `prerace`
- `quali`
- `countdown`
- `racing`
- `results`

The bridge between them is simple:

- ambient event reaches `staging`
- player is near enough and the world is safe to materialize
- event is promoted into live world execution and uses the existing `MTE.Racing` machinery

If the player never comes near it, the event stays background-simulated and resolves off-screen.

### World Promotion Rule

Ambient Races should not always become fully spawned world races.

They should only promote when:

- the player is within a configured observation radius
- the district chunk is reasonable to stage
- there is no active player-managed race already occupying `MTE.Racing`
- the scheduler marks the event as worth world promotion

Otherwise they resolve by simulation only.

This is what keeps them from becoming constant noise.

### Discovery Surfaces

Ambient Races should be discoverable through the contact network, not through hard HUD spam.

Phase-one surfaces:

- Rico mentions district activity bands and likely heat
- Billie references live paper when a meaningful ambient event is near activation
- Foreman stays mostly out of ambient surfacing unless a board is intentionally opened later
- the Fan reacts if a notable rivalry, upset, or streak result came out of ambient resolution

Recommended Rico command additions later:

- ambient district read
- tonight's pressure read
- what moved while you were away

These should use the current SMS pattern, not a separate UI.

### Settings Layer

Ambient Races belong in `modules/settings.lua` as world-tuning settings, not as diegetic UI.

Recommended initial settings:

- `ambientRacesEnabled`
- `ambientRaceFrequency`
- `ambientRaceMaxConcurrent`
- `ambientRaceObservationRadiusM`
- `ambientRacePromotionRadiusM`
- `ambientRaceDistrictWeights`
- `ambientRaceTypeWeights`
- `ambientRaceAggressionBias`
- `ambientRaceCrashBias`
- `ambientRaceWindowVarianceHours`

Persistence should live in `config.json` beside the rest of shared settings.

### Result Effects

Ambient resolution should feed existing mutable state.

At minimum:

- driver `wins`
- driver `recentFinishes`
- driver `rivalScore` where player-related spillover makes sense
- faction standings if the ambient event is considered championship-relevant later
- Rico summary hooks
- Billie sheet context later

Phase one should not award or remove player rep just for off-screen events unless the player had direct stake or management involvement.

### Non-Goals For Phase One

Do not do these yet:

- joining an ambient race in progress
- permanent HUD markers for every ambient event
- large spectator UI
- ambient events running in every district at once
- full citywide account-global persistence independent of the active career

The correct first target is a city that occasionally moves without you, not a dispatcher simulator.

## Management Mode

### Definition

Management Mode turns the player from a single-entry racer into an operator working inside the existing racing ecosystem.

In code terms, this is not a replacement for the current player career.

It is an extension of the existing career object and championship layer.

### Core Rule

Management Mode should be legible before it is deep.

That means:

- few drivers
- clear race placement
- obvious outcomes
- no heavy contract simulator in phase one

### Existing Foundation

The codebase already contains the skeleton needed for team identity:

- `career.playerFactionMode`
- `career.playerFactionId`
- `career.playerFactionName`
- `career.playerFactionColor`
- `career.activeSeasonId`
- `career.seasons`

It also already has:

- seeded driver generation in `Roster`
- season scheduling and standings in `Championships`
- faction catalog in `data/factions.lua`

So the right move is to extend that state, not duplicate it.

### Recommended Ownership

Management Mode can start in a new module:

- `modules/management.lua`

Responsibilities:

- own managed-driver slots
- track signed drivers and simple acquisition state
- submit managed drivers into eligible events
- resolve management-only simulation when the player is not the entrant
- surface driver/team status to Rico, Stu, Foreman, Billie, and the Fan

### Career Schema Extension

Recommended new career block:

```lua
career.management = {
    enabled = false,
    maxDrivers = 2,
    driverIds = {},
    reserveDriverIds = {},
    scoutingShortlist = {},
    lastResultSummary = "",
    budgetLedger = {
        entryFeesPaid = 0,
        prizeMoneyWon = 0,
        driverCostsPaid = 0,
    },
}
```

This belongs on the career object because team ownership, faction identity, standings, and roster relationships are already career-scoped.

### Managed Driver Source

Managed drivers should come from `Roster`.

Not from a new generated pool.

That gives Management Mode immediate alignment with:

- seeded driver identity
- prestige tiers
- faction identity
- recent form
- rival history

Recommended acquisition rules for phase one:

- one or two active managed drivers max
- hire from current or adjacent prestige tiers only
- no poaching diplomacy yet
- no deep salary negotiation yet

If a driver is signed, store the driver ID and small management metadata, not a duplicate driver record.

### Team Identity

Faction choice should use the current career faction layer.

Supported phase-one modes:

- `independent`
- signed to an existing faction from `data/factions.lua`
- custom faction using the custom-team path already implied by `Championships._resolveDisplayFaction`

This means the player is not inventing a new system. They are finally using the faction/team scaffolding already in the save schema.

### Race Placement

Management placement should plug into scheduled events first.

Primary entry sources:

- championship schedule from `Championships`
- ambient schedule later
- custom/generated events later

Phase-one command model should stay simple:

- enter managed driver in next eligible event
- inspect managed driver status
- inspect team status
- spectate managed run
- simulate managed run

Foreman should own placement/logistics language.

Rico should own read/assessment.

Stu should own car-prep talk.

Billie should own risk and sheet temptation around those runs.

### Simulation Logic

Managed-driver races that do not involve the player directly should resolve through the same stat logic the rest of the ecosystem uses.

Inputs should include at minimum:

- `pace`
- `aggression`
- `precision`
- `consistency`
- `wins`
- `recentFinishes`
- `rivalScore`
- route distance and route type
- event type
- field strength

If the player chooses to spectate, the system should only materialize the managed driver and immediate competitive context, not the entire ecosystem.

Critical constraint:

- you spectate your driver, not a free-roaming omniscient race replay

### Driver Lifecycle

Managed drivers must not feel static.

Phase-one lifecycle changes can be light:

- incremental stat improvement after good results
- loss of form after repeated poor results
- status changes like `available`, `signed`, `inactive`, `burned_out`, `retired`

The cyberpunk tone supports darker exits later, but phase one does not need a melodrama engine.

What it does need is turnover.

Otherwise the management layer freezes.

### Financial Layer

Management financial flow should stay understandable.

Phase-one ledger:

- entry fees
- prize payouts
- optional driver running cost
- optional Billie-linked betting exposure

This should not replace the player's eddies model.

It should extend it with a few management-visible lines in the career ledger.

### Contact Responsibilities

2.0 gets stronger if the contact network explains the management loop instead of a new screen.

Recommended ownership:

- Rico: scouting, trend reads, managed-driver fit, rival/faction movement
- Foreman: race placement, availability, board state, schedule logistics
- Stu: car prep, vehicle suitability, setup recommendation for a managed entry
- Billie: winner sheet, managed-driver paper, risk framing
- #1 Fan: team myth-making, streak response, public heat
- Dex: routing and clean front-door menu separation

This should remain true to the voice guide rule:

- no two characters solve the same management problem the same way

### Outcome Effects

Management outcomes should update real ecosystem state.

At minimum:

- driver record
- faction/team standing
- season points if the event is season-linked
- player management ledger
- Rico/Fan/Billie commentary hooks

Phase one should avoid heavy simulation of staff, sponsors, facility upgrades, or multi-car logistics.

The first win condition is that the player can name a driver, place them, watch or simulate the run, and feel that the ecosystem changed.

## Ambient + Management Integration

Ambient Races and Management Mode should converge, but not on day one.

Correct order:

1. Ambient scheduling and off-screen resolution.
2. Management shell and one-driver placement flow.
3. Managed-driver placement into ambient-linked opportunities.
4. Billie and Rico using ambient and management state for smarter commentary.

If this order is reversed, the project will drown in integration edge cases before the ambient scheduler is trustworthy.

## Module Boundaries

### New Modules

- `modules/ambient_races.lua`
- `modules/management.lua`

### Existing Modules To Extend

- `modules/settings.lua`
  add ambient world-tuning fields

- `modules/racing.lua`
  add a safe bridge for promoting ambient events into live execution without breaking the player-driven race loop

- `modules/championships.lua`
  allow managed-driver and ambient-linked standings updates where appropriate

- `modules/roster.lua`
  expose helpers for signed-driver lookup, eligibility, and driver lifecycle updates

- `modules/race_commands.lua`
  add SMS command surfaces for ambient intel and management flow

- `MTEJournalHandler.reds`
  extend route/default messaging for the new contact options where needed

### Persistence Targets

Recommended persistence split:

- career-owned management state stays inside `careers.json`
- ambient scheduler state gets its own file, for example `ambient_races.json`, keyed by active career ID

That keeps the career schema readable while still letting the ambient world have its own lifecycle.

## Phase Plan

### Phase 1

Build the smallest version that feels like a system.

- ambient scheduler creates district-weighted event windows
- off-screen events resolve against the active career roster
- a small number of events can promote into visible in-world races
- Rico can report district heat in SMS
- management enables one signed driver slot
- managed driver can be entered into the next eligible scheduled event
- player can spectate or simulate that managed run

### Phase 2

- second managed driver slot
- Billie sheets informed by ambient and managed-driver form
- better faction standings surfacing
- stronger driver lifecycle updates
- more contact-specific management commands

### Phase 3

- ambient and management systems cross-feed more heavily
- managed entries can target ambient opportunities directly
- standings and betting markets react more visibly to background results

## Build Discipline

If 2.0 is going to feel like a shipped feature, it needs a few hard rules.

### Rule 1

Use existing nouns unless there is a real schema gap.

### Rule 2

Do not split the world into separate player, ambient, and management simulations.

There should be one driver pool, one event language, one standings language, and one contact network.

### Rule 3

Ambient Races should be seen less often than they are resolved.

That is what makes them feel real when they do appear.

### Rule 4

Management Mode should be clearer than it is deep in the first pass.

The right early reaction is:

- I understand what happened
- I understand who owns what
- I want to do it again

Not:

- I guess there is a spreadsheet in here somewhere

## Final Read

What 2.0 actually is:

`MT_Ecosystem` becomes a racing world that can move without the player, talk to the player through the phone layer, and let the player operate inside it as a racer, bettor, spectator, or fixer.

