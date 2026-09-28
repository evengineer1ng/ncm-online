# NCM character / message archaeology and the lightweight PvE substrate

> **STATUS: PROPOSAL** - reconnaissance and design mapping, dated 2026-09-27. **No production behaviour was
> changed.** Nothing here is authorised for implementation; three items require an owner decision before any
> build, and one of them contradicts a CURRENT authority document.
> Authority map: [../../ncm-online/INDEX.md](../../ncm-online/INDEX.md). This document does **not** take
> authority over markets, market discovery, machine knowledge or the economy from the documents that hold it.

## What this is

Archaeology of the Night City Motorsports **single-player character/message system** from its actual
implementation, then a systems map of what that design becomes in a persistent multiplayer world, then a
creative expansion. Written so the owner and a collaborator can author the world graph in detail without
re-deriving any of it.

**Proof ladder used throughout** (the same one as `PRESENTATION_CAPABILITY_AUDIT.md`):

| Rung | Meaning |
|---|---|
| **PROVEN** | in-tree shipping code, read and quoted |
| **AVAILABLE** | a build-pinned official API card or schema exists; NCM does not call it yet |
| **PLAUSIBLE** | reasoned from what exists; nothing measured |
| **BLOCKED** | something concrete prevents it |
| **UNKNOWN** | needs a prototype before anyone should plan on it |

**Nothing in this document was measured in-engine.** Every SP claim is read from source. Every platform claim is
a build-pinned card from the hosted devkit MCP, which answers for **2.31.13+op77.78** while staging runs
**op77.102** - so any card may lag the deployed build (`NOW.md`'s standing caveat: when the index lags, grep the
binary).

> **The index staleness is not a footnote, and section VII.7 is the proof.** On first writing, this document
> declared shared AI traffic **BLOCKED** on the strength of the .78 index and a guide paragraph, three days
> after OPEN//77 shipped it. The owner caught it from the changelog. **An absent card means the index does not
> know, never that the platform cannot** - and the index is currently 24 builds behind staging. Before relying
> on any BLOCKED or UNKNOWN verdict here, check the platform's release channel and devblog, and list the
> resources actually running on the deployed server. That correction is recorded in `KB-162`.

---

# PART I - ARCHAEOLOGY REPORT

## I.1 Architecture: four layers, one bridge

The SP system is not a phone mod. It is a **command bus with a diegetic front end**, and the phone is the
thinnest of its four layers.

```text
  WolvenKit archive          mt_ecosystem.journal          static structure: contacts, conversations,
  (ArchiveXL resource)       mt_ecosystem.json             choice groups, choice entries, string keys
          |                                                (114 localization entries)
          v
  redscript                  MTEJournalHandler.reds        state->menu projection, choice interception,
  (85 KB, 1 service)                                       token substitution, quest-fact bridge
          |
          |  ~30 quest facts (ncm_phone_cmd_seq, ncm_race_state, ncm_foreman_builder_step, ...)
          v
  CET Lua                    phone_bridge.lua              polls facts at 0.25 s, routes to commands
  (bridge + command surface) race_commands.lua  (164 KB)   every contact's actual behaviour
          |
          v
  CET Lua                    racing / betting / roster /   the systems the characters are interfaces to
  (domain systems)           parts / fan_engine / ...
```

The load-bearing decision, and the one worth carrying forward: **the characters were never the system.** Each
contact is a *routing channel* onto a command surface that also answers to F6 UI and to console commands. The
phone was one of three front ends onto `race_commands.lua`. That is why the SP design survives losing the phone.

**Files.** Payload root `ncm-localized/`.
- CET entry `bin/x64/plugins/cyber_engine_tweaks/mods/MT_Ecosystem/init.lua`
- `modules/phone_bridge.lua` (469 lines) - the Lua half of the bridge
- `modules/race_commands.lua` (3,800+ lines) - every command handler and every authored brief
- `modules/contact_events.lua` (1,092 lines) - the Dynamic Contact Event System (see I.7)
- `modules/betting.lua` (1,227 lines) - Billie
- `modules/fan_engine.lua` - #1 Fan
- `modules/voice_harness.lua` (428 lines) + `VOICE_GUIDE.md` - the voice constitution and its validator
- `modules/onboarding.lua` - contact-unlock state (largely inert; see I.3)
- `data/contact_event_archetypes.lua` - the DCES archetype table
- `r6/scripts/MT_Ecosystem/MTEJournalHandler.reds` - the native half
- `wolvenkit-projects/mt_ecosystem/source/{archive,raw}/mt_ecosystem/{journal,localization}/`

## I.2 WolvenKit integration

Two authored resources, nothing else.

**`mt_ecosystem.journal`** - a `gameJournalResource` carrying two primary folders:

```text
gameJournalRootFolderEntry
|-- gameJournalPrimaryFolderEntry  id=quests
|   `-- gameJournalFolderEntry     id=ncm
|       `-- gameJournalQuest       id=ncm_onboarding
|           `-- gameJournalQuestPhase     id=contact_dex
|               `-- gameJournalQuestObjective id=contact_dex
`-- gameJournalPrimaryFolderEntry  id=contacts
    |-- gameJournalContact id=ncm_motorsports   (Dex)
    |   |-- gameJournalPhoneConversation id=race_setup
    |   |   |-- gameJournalPhoneMessage     id=msg_welcome
    |   |   `-- gameJournalPhoneChoiceGroup id=main_menu   (6 route entries)
    |   `-- gameJournalPhoneConversation id=phone_response
    |       `-- gameJournalPhoneMessage     id=msg_phone_response
    |-- gameJournalContact id=ncm_quickie      (4 choices)
    |-- gameJournalContact id=ncm_setup_stu    (4 choices)
    |-- gameJournalContact id=ncm_control      (39 choices - the constructor lives here)
    |-- gameJournalContact id=ncm_ledger       (2 choices)
    |-- gameJournalContact id=ncm_scout        (9 choices)
    `-- gameJournalContact id=ncm_bookie       (13 choices)
```

Every contact has exactly the same two-conversation shape: a **menu** conversation (one message + one choice
group) and a **`phone_response`** conversation (one message, no choices). That is the whole protocol. The menu is
the question, `phone_response` is the answer, and the answer is one string written from Lua.

**`localization/en-us/onscreens/mt_ecosystem.json`** - a `JsonResource` of 114
`localizationPersistenceOnScreenEntry` rows, primary keys `9000001`-`9000301`. Contact names, choice labels,
subjects and mappin labels are authored here. **Message bodies are not.** Seven of them are single substitution
tokens:

```text
9000004  NCM_msg_quickie_intro  -> {NCM_QUICKIE_MESSAGE}
9000006  NCM_msg_stu_intro      -> {NCM_SETUP_MESSAGE}
9000008  NCM_msg_control_intro  -> {NCM_CONTROL_MESSAGE}
9000010  NCM_msg_ledger_intro   -> {NCM_LEDGER_MESSAGE}
9000014  NCM_msg_scout_intro    -> {NCM_SCOUT_MESSAGE}
9000016  NCM_msg_bookie_intro   -> {NCM_BOOKIE_MESSAGE}
9000017  NCM_msg_phone_response -> {NCM_PHONE_RESPONSE}
```

`MTEJournalHandler.ReplaceNCMTokens` (reds:1679) swaps them for live strings. **Only Dex has a static body:**
`"You're through to NCM. What are you looking for?"` That asymmetry is the design in one line - Dex is the only
contact who does not need to know anything.

**A finding worth having before anyone reads the localization file as a spec.** Secondary keys were *repurposed
without renaming*, so the key no longer describes the string:

| Key | Actual displayed label |
|---|---|
| `NCM_choice_wager_max` | "Light contract" |
| `NCM_choice_wager_clear` | "Standard contract" |
| `NCM_choice_wager_earnings` | "Heavy contract" |
| `NCM_choice_back_dex_bookie` | "Void the slip" |
| `NCM_choice_close_results` | "Route me to the race" |
| `NCM_choice_start_quali` | "Create a custom race" |
| `NCM_choice_cancel_setup` | "Fit the best part" |
| `NCM_choice_back_dex_stu` | "Set and save a tune" |

Any port must read `femaleVariant`, never the key name. Several `back_dex_*` keys survive as labels for entirely
unrelated actions, which also means **there is no "Back to Dex" affordance in the shipped tree** - return to Dex
is done in code by `OpenContactRoute`, not by a choice.

## I.3 Contact registration and conditional availability

`OnJournalLoadedResource` (reds:280) finds the `contacts` folder, resolves seven contacts and fourteen
conversations, then calls `ActivateContact(false)` - which activates **only `ncm_motorsports`**. The other six
are activated lazily by `ActivateContactById` when something routes to them, via `AddPhoneContact` - a
synthesised `questPhoneManagerNodeDefinition` + `questAddRemoveContact_NodeType` executed through
`QuestsSystem.ExecuteNode`. That is how a CET/redscript mod adds a phone contact without owning a quest.

**So Dex *is* the unlock mechanism, in practice.** Choosing a route in Dex's menu is what makes that contact
exist in the player's phone. There is no separate gate.

`modules/onboarding.lua` shows a **designed-but-unwired** conditional unlock layer: a versioned, idempotent store
with fifteen milestones (`introDelivered` ... `nextRacePromptDelivered`), a `unlockedContacts` set seeded to
`{ncm_motorsports, ncm_quickie}`, `contactUnlockReasons`, and inference rules for pre-existing careers - Billie
unless `allowStakes == false`, Stu at 3 races **or** any DNF **or** any owned part, Rico at any race run or any
bounty. **`Onboarding.unlockContact` has no callers anywhere in the tree.** The conditional-unlock design exists
as data and was never connected. Carry the *design*; do not assume it ever ran.

## I.4 Dialogue-tree structure: state projection, not a tree

There is no dialogue tree. There is a **pure function from world state to the visible choice set.**

`ShouldActivateChoiceEntry(contactId, choiceId) -> Bool` (reds:353-521) is the whole mechanism, and it is worth
reading as the design document it effectively is. It reads quest facts and answers which choices exist *right
now*:

- **Quinn** - if `ncm_phone_quickie_offer_active == 1`, exactly two choices exist (`confirm_preview`,
  `refresh_offer`); otherwise exactly two others (`quick_race`, `knockout_setup`). Four authored entries, never
  more than two visible.
- **Stu** - if a DCES setup contract is live, only `accept`/`decline`; otherwise the four standing actions.
- **Foreman** - a six-step wizard keyed on `ncm_foreman_builder_step` 1..6, then a five-state knockout machine on
  `ncm_foreman_knockout_state`, then a seven-state race machine on `ncm_race_state` (idle / config / prerace /
  quali / countdown / racing / results). **39 authored choices, at most 9 visible.**
- **Rico** - contract choices when a scout contract is live; `scout_status` always; ambient/management choices
  only when **no** board is active; grid/field/watchlist choices only when `raceState` is 2..6.
- **Billie** - a three-branch menu (`m_bookieMenuBranch`) that only opens at all when `raceState == 2`
  (pre-race); outside that window only the read-only and streak choices exist.
- **#1 Fan** - two choices, unconditionally.

**No choice is ever greyed out. An inapplicable choice is absent.** This is the same law NCM Online later wrote
down independently in `competition.venue_options` ("an option that cannot apply right now is ABSENT, not greyed
out"). The SP phone already obeyed it.

**The corresponding message body is a state projection too.** `DefaultControlMessageText()` (reds:69) is a
fifteen-branch cascade that narrates the board's current state - *"Builder step 3/6. Select launch: grid, rolling,
or side-by-side."*, *"Qualifying live. Route to next target or log forfeit / DNF."* Foreman's personality is
literally a state machine that talks.

## I.5 State handling

Three stores, deliberately separate:

| Store | Holds | Lifetime |
|---|---|---|
| ~30 **quest facts** (`ncm_*`) | the bridge: sequence numbers, race state, builder step, offer/contract active flags | reset every load by `ResetBridgeFacts` (reds:149) |
| **career JSON** (`careers.json`) | `contactEventState`, betting state, `fanState`, stats, history | durable |
| **`onboarding.json`** | versioned milestone/unlock profile | durable, and explicitly non-load-bearing ("Gameplay must never depend on this file saving successfully.") |

The bridge is a **monotonic sequence protocol**: Lua writes `ncm_phone_cmd_seq` + `ncm_phone_cmd_id`; reds reads,
acts, writes `ncm_phone_response_seq` + the response text; both sides keep `lastSeq` and ignore replays. There is
also a debug channel (`ncm_phone_debug_seen_seq`, `debug_press_seq`, `debug_last_cmd`, `debug_last_route`) purely
for diagnosing which choice the renderer actually saw - a detail that tells you this integration was hard.

**Choice interception is by rendered text, not by id.** `@wrapMethod(MessengerDialogViewController) ActivateReply`
and `@wrapMethod(MessangerItemRenderer) SetMessageView` (reds:1803, 1841) catch the *displayed string*, and
`ProcessRenderedChoiceText(rawText, localizedText)` matches it back to a choice id (`MatchesChoiceText`, plus a
`ResolveBookieChoiceOverride` for Billie's rebranded labels). This is the most fragile part of the whole system
and the strongest argument against porting the phone integration: **the contract is a string comparison against a
vanilla UI widget.**

## I.6 System invocation

`CommandIdForChoiceId` (reds:1488) maps choice to numeric command id; `phone_bridge.lua` polls and dispatches
into `race_commands.lua`, which calls the domain modules and returns `(ok, text)`. `SetLastPhoneResponse(seq, ok,
message, returnToControlBoard, contactOverrideId)` carries the answer back, and `ReplyContactForChoiceId` decides
**which contact appears to be speaking the answer** - so a command invoked from Dex can reply as Foreman. That
indirection is how one command surface wore seven voices.

## I.7 The forgotten system: DCES (Dynamic Contact Event System)

**This was not in the brief and it is the most valuable thing recovered.** `modules/contact_events.lua` +
`data/contact_event_archetypes.lua` implement an **event-driven, world-reactive, off-screen character layer** that
the seven named contacts merely *deliver*.

**Twelve archetypes**, each a small declarative record:

```lua
rival_mechanic_leak = {
    archetype     = "intel_leak",
    triggerTypes  = { "post_race", "rivalry_proximity" },
    sourceActor   = { type = "rival_mechanic", relationship = "hostile" },
    intent        = { type = "revenge", description = "A rival-side mechanic wants payback through a clean leak." },
    offer         = { type = "intel" },
    riskProfile   = { level = "low", visibility = "explicit" },
    systemImpact  = { type = "information_advantage" },
    legibility    = { level = "clear" },
    deliveryContactId = "ncm_scout",
}
```

The twelve: `rival_mechanic_leak`, `tuner_counter_build`, `scavenger_experimental_deal`, `fan_build_reflection`,
`crew_warning`, `tuner_setup_contract`, `rival_heat_warning`, and four `tier_*_promotion_contract` variants
(Streetkid / Solo / Fixer / Edgerunner).

**Nineteen unnamed actors** drawn from five pools - `rival_mechanic` (Jax, Leda, Timo, Iris, Vale),
`independent_tuner` (Hex, Morrow, Taji, Rin, Kells), `scavenger` (Scrap, Lockjaw, Mica, Spindle), `fan` (Glow,
Sparx, Meli), `crew_member` (Stu, Marrow, Kade). The actor name is **deterministic**:
`actorName(archetypeId, hashString(eventKey) + career.seed)`, so the same world state always produces the same
person.

**Triggers** are real state, evaluated in a priority cascade in `onRaceFinished` (line 1001):

```text
champPos <= 3 AND rival.rivalScore >= 12                -> rival_heat_warning         (Rico)
rival.rivalScore >= 10 OR rival.headToHeadWins > 0      -> scout_intel_contract       (Rico, accept/decline)
     ... then                                           -> rival_mechanic_leak        (Rico)
lossStreak >= 2 AND a known weakest axis                -> crew_warning               (Stu)
     ... then                                           -> tuner_setup_contract       (Stu, accept/decline)
     ... then                                           -> tuner_counter_build        (Stu, part offer)
finished top half AND a known weakest axis              -> tuner_counter_build        (Stu)
finished top half AND (raceCount + hash(build)) % 4 = 0 -> scavenger_experimental_deal (Rico, tradeoff part)
winStreak >= 2                                          -> fan_build_reflection       (#1 Fan)
```

plus `onPrestigeChange(dir="up")` for the tier promotion contract, and `onOfferClaimed` / `onOfferExpired`.

**Budget and anti-spam, already solved:** `MAX_ACTIVE_EVENTS = 2`, `COOLDOWN_RACE_GAP = 2` races between any two
events, `INTEL_EXPIRY_RACES = 3`, `DEFAULT_OFFER_EXPIRY_RACES = 3`, plus a permanent `sentEventKeys` set so no
event key ever fires twice. Expiry is measured **in races, not in time** - which matters, because it means the
pacing is tied to play rather than to the clock.

**Inputs it reads** (`buildContext`, line 376): current vehicle key, `Parts.getVehicleSummary` (build identity
headline, strengths, weakest axis and slot), the current rival and `Parts.getDriverVehicleBuild` for that rival's
strongest/weakest race fit, championship position and points, career stats, race count.

**Outputs it produces:** a message emitted as `MTE.Events.emit("ContactEventMessage", {contactId, message,
title})`; optionally a real **part offer** written into the garage (`deliverPartOffer` -> `chooseOfferItems` with
`minimumRarity` and `requiresTradeoff` filters); optionally a **two-sided contract** (`pushSetupContract` /
`pushScoutContract`) that the phone then exposes as accept/decline; optionally **pending intel** that folds into
Rico's later reads.

Representative DCES prose, which is a different register from the seven named contacts - these people do not know
you:

> *"You don't know me. I wrench for Vale. They burned me after the last run. Build reads heavy in long pulls.
> Weakest when the race turns into launch phases. Do what you want with that."*

> *"Scrap. Pulled something ugly off a wreck near Charter Hill. Still runs. Definitely not clean. It's aimed at
> the drivetrain. It'll wake the car up, but you'll feel the cost. If you want it, check the garage before
> someone else pays for the mistake."*

> *"Kade. Stop chasing the wrong edge. You're not losing because the car is slow. You're losing in low-speed
> rotation. Next move is suspension, not more of the same."*

**This is the lightweight authored PvE substrate the addendum is asking for, and it already shipped once.** It is
declarative, event-driven, budgeted, state-conditioned, deterministic, persistent, expiring, and it produces both
narrative and mechanical consequences. What it lacks is *places*, *markets* and *a graph* - see Part VII.

## I.8 The seven characters, as implemented

### DEX - `ncm_motorsports`

| | |
|---|---|
| **Exact name** | contact `Dex - NCM Dispatch`; subjects `NCM Dispatch` / `Dispatch Update` |
| **Role** | dispatcher and front door. Nothing else. |
| **Voice** | short, clean, neutral. 1-2 sentences, <=22 words. Required vocabulary: route / looking / line / board / through. **Forbidden:** odds, chassis, podium, favorite, chalk, heater. |
| **Body** | `"You're through to NCM. What are you looking for?"` - the only static message body in the system |
| **Actions** | six routes: Quick Race, Setup Tuning, Grid Control, Stats/History, Scouting and Management, Betting |
| **System function** | `OpenContactRoute(contactId)`: sync state, seed that contact's default message, activate the contact in the journal (creating it on first use), notify, then re-activate Dex's own conversation so the player can come back |
| **Inputs** | none about the world. Dex inspects nothing. |
| **Conditions** | none. Always available, always the same six routes. |
| **State** | none |
| **Dependencies** | the journal resource; nothing else |

Dex is the purest object in the system: **a router with a name**. Every scenario in `voice_harness.lua` gives Dex
a one-line deflection to the correct owner - *"Book line. Billie."*, *"Garage line. Setup Stu."*, *"You want
structure or a field read? Foreman handles one. Rico handles the other."*

### QUICKIE QUINN - `ncm_quickie`

| | |
|---|---|
| **Role** | the hookup. Off-calendar races, right now. |
| **Voice** | ultra-short, bursty. 2-5 sentences, <=26 words. Street vocabulary, actionable only. **Forbidden:** because, analysis, odds, chassis, rep, claim. |
| **Default body** | *"Got one. You in?"* |
| **Representative** | *"Got one. 5.2km sprint. Watson to Japantown. Sport only. You in?"* / *"Fast one. Tight streets. That's the sell."* / *"Not my problem. I line races up."* / *"Knew that one had teeth. Nice work."* |
| **Actions** | Line me one up / Line up a knockout - then, once an offer exists, only: You're on, choom / Got anything else? |
| **System function** | `createQuickRacePhoneOffer` -> `Racing.openQuickRaceConfig()` -> `getDraft()` -> `evaluateQuickRaceCompatibility(draft)` -> `previewDraft()` -> `lockQuickRacePreviewDraft(preview)` |
| **Inputs** | the career's saved quick-race preferences, the current vehicle, the compatibility ruleset |
| **Conditions** | `ncm_phone_quickie_offer_active` flips the menu wholesale |
| **State** | one live offer at a time (`activePhoneOffer`), plus persisted quick-race preferences |

**The critical finding for Part III is in Quinn's implementation.** `Racing.openQuickRaceConfig()` is, verbatim:

```lua
function Racing.openQuickRaceConfig()
    return Racing.openConfig({ sourceType = "quick_race" })
end
```

Quinn and Foreman already operate on **one race object through one entry point**. See III.1.

### FOREMAN - `ncm_control`

| | |
|---|---|
| **Role** | authority. Staging, routing, board state, and the full custom-race constructor. |
| **Voice** | structured, directive. 1-3 sentences, <=28 words. Operational vocabulary, procedural priority. **Forbidden:** lucky, obsessed, chassis, favorite, myth. |
| **Representative** | *"Grid staged. Six cars. Standing start. Street pressure."* / *"No board staged. If you want control, open the race board."* / *"Vehicle state is not a board function."* / *"Board's idle. Review the next heat, check ambient, queue management, or stage a run."* / *"Result posted. Board ready for next action."* |
| **Actions** | 39 authored choices across three state machines (I.4). Standing set: Stage next career race / Create a custom race / Show ambient board / Stage live ambient heat / Queue managed sim / Queue managed spectate / Simulate managed run |
| **The constructor** | six steps: **type** (sprint/drag/knockout) -> **field** (4/6/8/10) -> **launch** (grid/rolling/side-by-side) -> **pressure** (street/serious/elite) -> **district** (any + 7 Night City districts) -> **confirm or scrap**. `ApplyLocalForemanBuilderChoice` (reds:697) advances `ncm_foreman_builder_step` locally so the wizard does not round-trip. |
| **System function** | `Racing.openConfig` / `confirmConfig` / `previewDraft` / the race lifecycle; ambient race staging; managed-driver queueing |
| **Inputs** | `ncm_race_state`, `ncm_foreman_builder_step`, `ncm_foreman_knockout_state`, the championship season config |
| **State** | the draft; the board |

Foreman is **system characterization**, not a character system: no interiority, no memory of the player, nothing
to say that is not a fact about the board. `VOICE_GUIDE.md` calls him "already the clearest voice" - because he
is the one whose voice is fully determined by state.

### SETUP STU - `ncm_setup_stu`

| | |
|---|---|
| **Role** | the builder. Reads the car, names the fault, proposes the next move. |
| **Voice** | medium, think-aloud. 2-4 sentences, <=50 words. Mechanical/analog vocabulary, advisory. **Forbidden:** odds, board, favorite, claim, poster. |
| **Default body** | *"Pull it onto the lift. I'll tell you what's bolted on, what's sandbagging the chassis, and what I'd change before the next green. If the line is open, I can hang parts and burn you a shop map."* |
| **With a live contract** | *"Stu here. Live contract on the bench. 'Source me parts' locks the package and pushes it to the garage. 'Tune it' passes and kills the lead."* |
| **Representative** | *"All right... it's not dead, but the rear's arguing with you on exit. I'd calm the map down first, then talk about hardware."* / *"Ask Rico about the people in it. I care what the car will do when they lean on you."* / *"If the car's wrong, don't get cute with money."* / *"Good. Now let's make sure the car can do it again without complaining."* |
| **Actions** | Read the car / What's wrong with it? / Fit the best part / Set and save a tune - or, under contract, accept/decline |
| **Inputs** | `Parts.getVehicleSummary(career, vehicleKey)`: installed parts, a **build identity headline**, ranked strengths, a **weakest axis** mapped to a slot via `AXIS_TO_SLOT`; `Parts.getRaceFitForConfig` |
| **Outputs** | prose diagnosis; a part offer written to the garage; a saved tune |
| **Conditions** | the contract branch replaces the whole menu |
| **State** | DCES setup contracts persist in `contactEventState.activeContracts` |
| **Dependencies** | `parts.lua` (80 KB), `tuning.lua`, `data/vehicle_slot_profiles.lua` |

Stu is the character whose **claims were the most load-bearing and whose evidence was the thinnest** - see V.2.

### RICO - `ncm_scout`

| | |
|---|---|
| **Role** | insider analyst. Field reads, rivals, ladder movement, pressure points. |
| **Voice** | medium-long, composed. 2-4 sentences, <=56 words. Analytical + street, **interpretive**. Proactive - the only contact whose declared initiative is pushing unasked. **Forbidden:** odds, chassis, bolt, poster, shrine. |
| **Default body** | *"Ask clean and I'll cut the noise. Current grid, pressure points, watch list, or the wider ladder."* |
| **Actions** | What's happening out there? (always) / Who's in this race? / What am I up against? / Who should I watch? (race-day only) / Where's the heat? / Show management targets / Sign target 1-3 (no-board only) |
| **System function** | six brief builders in `race_commands.lua`: `buildCurrentFieldScoutBrief`, `buildFieldRosterScoutBrief`, `buildFieldReadScoutBrief`, `buildWatchlistScoutBrief`, `buildLastOutcomeScoutBrief`, `buildWorldScoutBrief` |
| **Inputs** | the live field (`Racing._field`), per-driver `pace` / `consistency` / `aggression` / `wins` / `rivalScore` / `headToHeadWins` / `recentFinishes` / `personality`, the leaderboard, race history, ambient district activity, management targets |
| **State** | DCES pending intel folds into later reads; scout contracts persist |

**Rico's engine is the one piece of SP writing that is genuinely reusable as-is**, because it is a
**data-to-prose translator** rather than a script. `driverReason(driver)` (race_commands:2341) is a priority
cascade from numbers to characterful claims:

```text
headToHeadWins >= 2             -> "already has %d clean beats on you and knows exactly how to turn this into a personal race"
pace>=1.12 AND consistency>=.72 -> "has the cleanest outright pace in this field and usually does not waste it with mistakes"
aggression>=.78 AND cons<=.48   -> "forces the issue early, then starts leaking time the second the race gets untidy"
aggression >= .78               -> "will throw the first punch on the launch and make every overlap feel expensive"
form <= 2.5                     -> "is coming in hot off front-running form and will expect this race to bend toward them"
wins >= 3                       -> "already has %d wins banked and usually knows how to close once they smell the front"
rivalScore >= 12                -> "keeps turning up as your direct problem in this tier, which is not something I ignore anymore"
personality == "crash magnet"   -> "has real speed, but the line gets risky the moment the race stops behaving"
```

and `buildFieldReadScoutBrief` composes a four-line brief with a **reference driver**, a **field-character
judgement** from aggregate aggression/consistency/threat, and a closing **"Read:"** line naming the one thing to
do about it:

> *"This grid looks sharp. Vale sets the reference here because they have the cleanest outright pace in this field
> and usually does not waste it with mistakes. This is a patient field. Miss the first clean chance to pass, and
> they will keep the order neat enough to make you earn the next one properly. Read: clear Timo early or you
> spend the whole run reacting instead of dictating."*

The watchlist brief is structurally different on purpose: it names a **reference**, a **chaos piece** (highest
aggression) and a **rival** (rivalScore >= 10 or any head-to-head), then closes with a conditional. Rico's own
post-race register is drier than the Fan's and that contrast is deliberate: *"That result moves the room. People
stop treating you like traffic after a win like that."* `VOICE_GUIDE` flags the standing risk: *"Rico should not
overuse the same framing device for every read."*

### BOOKQUEEN BILLIE - `ncm_bookie`

Recovered in full in **Part IV**. Summary row:

| | |
|---|---|
| **Exact name** | contact `BookQueen Billie` - one word, no space. The brief's "Book Queen Billie" is not what shipped. Subjects `Bet Window` / `Slip Update`. |
| **Role** | the tempter. Sells risk against the player's own future performance. |
| **Voice** | medium, rhythmic. 2-4 sentences, <=42 words. Bookmaker, **predatory**, risk-framing. Opportunistic initiative. **Forbidden:** chassis, "route to", poster, "grid is staged". |
| **Products** | fronted single-race contracts (light/standard/heavy); winner slips on any runner including self; 3- and 5-race streak tickets |

### #1 FAN - `ncm_ledger`

| | |
|---|---|
| **Exact name** | contact `#1 Fan`; subjects `Fan Mail` / `Hype Drop`. The internal id `ncm_ledger` is a fossil of an earlier "ledger/stats" conception. |
| **Role** | obsessed supporter. Turns results into myth. |
| **Voice** | short-medium, punchy. 1-3 sentences, <=30 words. Emotional/celebratory, milestone + hype. **Milestone-triggered** initiative. **Forbidden:** odds, route, chassis, confirm, discipline. |
| **Default body** | *"I archive every time you make this city scream. Want the numbers, or the part where I tell you why everyone's obsessed?"* |
| **Actions** | Show me the receipts / Tell me what that meant (`view_player_stats`, `reroll_fan_message`) |
| **Dependencies** | `fan_engine.lua`, `race_telemetry.lua`, `records.lua`, `careers.lua` |

**The Fan is not a stats mirror, and the brief's suspicion that Driver Profile supersedes him is not supported by
the code.** `fan_engine.lua` is a **telemetry-driven narrative interpreter** with four generators and a push
governor:

- `buildSignatureMessage(summary, context)` - a ~12-rung priority cascade over **race telemetry**, three authored
  variants per rung, keyed on `overtakes`, `positionsGainedLap1`, `recoveries`, `majorCollisions`, `crashHeavy`,
  `recordFlags.routeBestRaceTime` / `routeBestLap`, start-to-finish delta, the clean flag, field size, promotion
  and records.
- `buildMilestoneMessage` - threshold ladders with a permanent `sentMilestones` set so a milestone lands once.
- `buildIdentityMessage` - who the player is becoming across a career.
- `buildPullFallback` - what he says when nothing special happened.
- `canPush(career, state, minRaceGap, allowRepeatKey, nextKey, minSeconds)` - **a real pacing governor**, by both
  race gap and wall-clock seconds, with a dispatch key per race (`buildRaceDispatchKey`) so one race produces at
  most one push.

Representative, and note that these are claims **no leaderboard can make**:

> *"YOU DID NOT just pull off 7 clean passes in one race. I need that replay again."*
> *"They hit you and you still took the race back. I can't stop thinking about that."*
> *"That launch cracked the whole race open. 4 spots in lap one before they even got settled."*
> *"Started P8 and still won it clean. That's the kind of race people bring up twice."*
> *"You left a number behind there. Not just a finish. A number people are going to look at twice."*
> *"That was clean. Like CLEAN clean. No waste, no panic, no free mistakes anywhere."*
> *"THAT is the one. Big lights, clean finish, whole city watching. You're a problem now!"*

## I.9 The voice system as a testable artifact

`VOICE_GUIDE.md` + `modules/voice_harness.lua` are the most transferable asset in the archaeology, because the
voices are **enforced by a validator rather than by a style note**.

`voice_harness.lua` holds, per character: `sentencePattern`, `minSentences`, `maxSentences`, `maxWords`,
`infoPriority`, `relationship`, `initiative`, `requiredAny` (domain vocabulary that must appear) and
`forbiddenAny` (vocabulary that must not). `Harness.validateCharacter(id, text)` checks all of it.
`Harness.validateBundle(id, bundle)` additionally computes **pairwise Jaccard token overlap across all 21
character pairs and fails the bundle at >= 0.55** - a mechanical guard against seven writers converging.

Five **scenarios** declare *ownership* and carry a full seven-voice example bundle: `need_race` (owner: Quinn),
`race_shape` (Rico), `car_feel` (Stu), `bet_pick` (Billie), `big_win` (Fan). The ownership rules are stated as
law:

> *"If the player asks what the race feels like, Rico interprets, Foreman structures, Quinn rerolls, Stu
> deflects."*
> *"If the player asks what the car needs, Stu advises, Rico does not cross lanes, Billie does not pretend to
> care."*
> *"If the player wants risk, Billie tempts. Rico can mention danger, but he does not price it."*
> *"If the player wins big, the Fan hypes. Rico interprets later. Billie settles paper. Foreman says nothing
> unless the board changed."*

and the target outcome is stated as a falsifiable test:

> *"Personality should come from constraint, not ornament. If the same prompt can be handed to every contact and
> they all answer with the same cadence, the system failed."*

Exposed at runtime as `GetMod("MT_Ecosystem").VoiceMatrix()` / `VoiceScenario(id)` / `VoiceExample(id)`.

**Open risks recorded in the guide itself**, still unresolved: Quinn drifts into medium-density system copy once
an offer is generated; Stu becomes "Foreman with car nouns" when too clipped; Billie has betting vocabulary but
not enough rhythm and temptation; Rico reuses one framing device.

## I.10 Answers to the brief's specific questions

| Question | Answer |
|---|---|
| Where do contact definitions live? | `mt_ecosystem.journal`, `contacts` primary folder; names in `mt_ecosystem.json` |
| Where do dialogue trees live? | Nowhere. Choice *entries* are in the journal; visibility is computed by `ShouldActivateChoiceEntry`; bodies are generated in Lua |
| How were contacts registered? | `AddPhoneContact` -> synthesised `questPhoneManagerNodeDefinition` -> `QuestsSystem.ExecuteNode`; lazily, on first route |
| How did phone integration work? | Two `@wrapMethod` hooks on vanilla messenger widgets, matching **rendered text**; ~30 quest facts as the bus |
| WolvenKit assets involved? | Exactly two: one `.journal`, one localization `.json`. No custom UI, no custom quest, no custom audio |
| CET/redscript pieces? | reds: one `ScriptableService` + two wrapMethods. Lua: `phone_bridge` + `race_commands` + the domain modules |
| How did choices invoke NCM? | choice text -> choice id -> numeric command id -> quest fact -> Lua poll -> command handler -> response text + reply-contact override |
| Where was state stored? | quest facts (volatile bridge), `careers.json` (durable domain), `onboarding.json` (durable, non-load-bearing) |
| Could NCM initiate messages? | **Yes.** `NotifySMS(messageType)` + `MTE.Events.emit("ContactEventMessage", ...)`. DCES and the Fan engine both push unasked |
| Did contacts unlock conditionally? | Designed in `onboarding.lua`, **never wired**. In practice, routing through Dex is the unlock |
| Did trees change with state? | Constantly. That is the entire mechanism |
| Persistence? | Yes - DCES event keys, contracts, intel, betting slips, fan milestones, all in the career |
| Scheduled/delayed responses? | **Not by clock.** Expiry and cooldown are measured in **races**. `Fan.canPush` has a `minSeconds` term, the only wall-clock pacing anywhere |
| Contextual race information? | Yes: route, distance, field, start type, discipline, district, rival identity, build identity, weakest axis |
| Forgotten functionality | **DCES** (I.7); the **voice validator** (I.9); Quinn and Foreman sharing one draft object (III.1); the **unwired conditional-unlock layer** (I.3); the repurposed-key hazard (I.2); `reroll_fan_message`; managed-driver signing through Rico; ambient-heat staging through Foreman |

---

# PART II - CHARACTER PORTABILITY MATRIX

| Character | SP role | Underlying system | Still needed? | MP opportunity | Likely surface | Preserve character? | Major questions |
|---|---|---|---|---|---|---|---|
| **Dex** | router / front door | `OpenContactRoute`; journal contact activation | **Function yes, contact form doubtful** | Onboarding voice and the first authored thread; sender identity for world announcements | Landing panel + Messages sender identity; **not** a menu | **Partly** - keep the name and the register, drop the six-route menu (F6 nav already routes) | Does a router survive when the shell *is* the router? Is "NCM Dispatch" an organization or a person? |
| **Quickie Quinn** | fast off-calendar race offers | `Racing.openConfig{sourceType="quick_race"}` | **Function critically needed; separate character probably not** | The *default-accepting* depth of one race-authoring object; nearby-player invitation | Lightweight world prompt / venue option; chat command | **Voice yes, contact no** - Quinn becomes the register the fast path speaks in | If the constructor opens pre-filled, is Quinn just the confirm button's tone of voice? |
| **Foreman** | board state, staging, 6-step constructor | `Racing` lifecycle; `ncm_race_state` | **Function yes** | The *deep* depth of the same object; session/race-control identity | F6 for authoring; toast/HUD for board state | **Yes, as system characterization** | `venue_options` forbids sub-menus and trees. Where can a 6-step builder legally live? |
| **Setup Stu** | car/parts diagnosis in prose | `parts.getVehicleSummary`, `getRaceFitForConfig` | **Yes - and stronger than SP** | NCM Online has a real parts + physics + observation stack; Stu finally has evidence | Vehicle / parts / Engineering surfaces, contextually | **Yes** | What may he *claim*? Machine Knowledge's epistemic vocabulary must bound him (V.2) |
| **Rico** | field read, rivals, ladder | `driverReason`, six brief builders over roster stats | **Yes - the biggest upgrade of any character** | Real player records instead of synthetic AI attributes | Race-entry context + Messages archive | **Yes, strongly** | Which player facts are authoritative and publishable? Does he read *humans* about humans? |
| **BookQueen Billie** | fronted paper on own performance | `betting.lua`: softmax book, escrow, settlement | **Function yes; economics need re-derivation** | Genuine sink plus conditional faucet on a persistent economy | Messages primary; race-entry secondary | **Yes - she is the feature** | Collusion, small fields, disconnects, and who the counterparty is when the house is the economy (Part IV) |
| **#1 Fan** | telemetry to myth, milestones | `fan_engine.lua` + `race_telemetry` | **Yes - the redundancy hypothesis is not supported** | Recognition of things no leaderboard states; already has a pacing governor | Push messages + Driver File archive | **Yes** | Does he notice *other players'* reactions to you? One Fan, or an audience? |
| *(DCES actors)* | 19 unnamed off-screen people | `contact_events.lua` + archetypes | **Yes - this is the substrate** | Places, markets, manufacturers and leads as new archetypes | Messages | **N/A - they are generated** | Do they stay nameless-but-deterministic, or graduate into recurring contacts? |

**Where uncertainty is more useful than a verdict:** Dex and Quinn. Both are strong *functions* wearing thin
character. Both could survive as pure voice. Neither should be decided before the surface question (Part VI) is
settled, because the answer changes which one is even possible.

---

# PART III - SPONTANEOUS RACING STUDY

## III.1 Quinn/Foreman convergence: already done, in SP

The brief proposes that quick and deep become two interaction depths of one race object. **In single player they
already are**, and the evidence is three lines of Lua:

```lua
function Racing.openQuickRaceConfig()
    return Racing.openConfig({ sourceType = "quick_race" })
end
```

`buildOpenDraft(career, options)` then branches on `sourceType` *only* to choose which defaults to seed:

| `sourceType` | Seeding |
|---|---|
| `"quick_race"` | `applySavedQuickRaceDraft(draft, career)` - **the player's own remembered preferences** - then `normalizeQuickRaceConfig` |
| anything else | `Championships.applySeasonConfig(career, draft)` - match the scheduled round |

Everything after that is identical: `normalizeDraftRouteConfig`, `previewDraft`, `confirmConfig`, one
`Racing._draft`, one state machine. Quinn's "You're on, choom" and Foreman's six-step wizard **write to the same
object**; Quinn simply never shows the steps.

**So the model the brief wants is not a redesign. It is the removal of a UI accident.** Quick Race is
`openConfig` with remembered defaults and the form collapsed; Constructor Race is `openConfig` with the form
expanded. One object, two depths - and SP already persisted the player's defaults, so the fast path got faster the
more they used it.

**Recommendation:** carry this forward literally. Do not build "quick race" and "custom race" as two MP features.
Build **one race draft with an authored default set, a remembered per-player default set, and progressive
disclosure.** Accepting = quick; changing one field = light; expanding = deep.

## III.2 What NCM Online already supports - honest inventory

The **hard architectural fact** for this whole section: NCM Online's event model is **cadence-derived,
deterministic and pure**.

```lua
-- ncm/core/competition/calendar.lua
--- Turns series cadence into posted slots. Pure and deterministic:
--- the same series + horizon always yields the same event ids, so re-materialising never duplicates.
function M.materialize(series, nowUnix, horizonSec)
```

An event is **not a row someone creates.** It is a function of `(series, cadence, routes, entryWindow, economy)`
over a time horizon. A series requires `seriesId`, `name`, `rulesetId`, `cadence.everyMinutes >= 1`, a non-empty
`routes` list of resolvable roots, and a valid `entryWindow`. **A player-authored ad-hoc race has no series and no
cadence, so the calendar cannot represent it at all.** This is the biggest gap between the brief's ambition and
the current architecture, and it is a real one, not a detail.

| Authoring dimension | Status | Evidence |
|---|---|---|
| Route / course (start, finish, intermediate gates, distance) | **supported now** | `course.routes.resolve(rootId)`; **10 authored roots, 35 nodes** in `data.roots` / `data.nodes` |
| Discipline / format | **supported now** | `competition.discipline`, `competition.format` |
| Vehicle class restriction | **supported now** | `competition.class`, `competition.eligibility` |
| Entry requirements / refusal reasons | **supported now** | `competition.eligibility` |
| Entry fee, purse, settlement, refunds | **supported now** (Economy v1, `L168`/`L169`) | `economy.settlement`; paid check-in; atomic solo/contested settlement |
| Field size | **supported now** | entry/grid modules; scheduled field-of-one is a first-class case |
| Laps | **supported now** | `session.race`; calendar route entries |
| Qualifying / practice | **supported now** | `session.quali`, `session.practice` |
| Grid / start type | **supported now** | `session.grid` |
| Race Tags, incidents, penalties | **supported now** | `competition.race_tags`, `competition.incidents` |
| Weather | **supported now, as world state** | `world.weather`, `Open77.environment`, `ncm_weather_probe` |
| **Ad-hoc event creation (no series)** | **requires architecture** | `calendar.materialize` is the only event producer |
| **Player as event author / owner** | **requires architecture** | no `created_by` on an event anywhere |
| **Direct player-to-player invitation** | **easy extension** - the platform primitive exists | `Open77.playerInteractions.request(actorId, targetId, kind, options)` - AVAILABLE, op77.63 |
| **Author-controlled start timing** | **easy extension** | the entry window already has `opensMinutes`/`closesMinutes`; an ad-hoc event needs an absolute start instead of a cadence slot |
| Player-authored *new* courses (arbitrary start/finish) | **future possibility** | roots are an authored pack; `course.gates` is authored |
| Route-conflict / occupancy intelligence | **future possibility** | nothing tracks route occupancy |

## III.3 Solo creation, and why it matters most

The brief is right that the creator must not need another human. Two facts make this cheap:

1. **Economy v1 already pays a field of one.** A scheduled field of one uses time-trial completion/target
   economics and never receives P1; fields of two or more use contested economics. So an ad-hoc race nobody joins
   is already a *legitimate, payable* activity rather than a broken event.
2. **`competition.venue_options` already models "what can I do here right now"** as a short flat list of final
   acts.

**The cheapest honest alpha shape** is therefore not "let players create events". It is: **let a player post an
ad-hoc slot onto an existing series' route set, with an absolute start time instead of a cadence slot, authored
economics frozen at post time, and an `authorDriverId`.** That reuses eligibility, entry, settlement, grid,
session, Tags and the Guide unchanged, and confines the new architecture to one event *origin*.

## III.4 Direct invitation - the platform already has the primitive

`Open77.playerInteractions` (op77.63, 15 natives) is a **first-class two-player invitation and reservation
service**:

```text
server  request(actorId, targetId, kind, options?)   reserve and coordinate a two-player interaction
server  current(playerId)     the interaction reserving a player, INCLUDING an unanswered invitation
server  isReserved(playerId)  exclusively reserved by this service
server  cancel(interactionId, reason?)
client  respond(interactionId, accepted)             "Only the target may respond."
client  accept / decline / cancel / current / get / list / isReserved / result
```

This is exactly the brief's section 8: initiator requests, target gets a lightweight prompt, accept places them
in, exclusivity prevents double-invites, and `result` caches the server acknowledgement for 30 s. **AVAILABLE, not
PROVEN** - NCM has never called it, and the card lists no permission, which should be confirmed against the
deployed build rather than the index.

**Nearby-player targeting** has server-side support too: `Open77.vehicles.nearby(point|player, radius)` and
`Open77.vehicles.closest` (both op77.67, `world.vehicles` - **already declared** by `ncm_world` and `ncm_league`),
plus `Open77.players.all`. For a racing game, "nearest eligible player" is best derived from *nearest registered
vehicle with a driver*, which NCM can already ask for.

## III.5 Start timing

| Option | Fit |
|---|---|
| short countdown (e.g. 30 s) | reuse the existing pre-race countdown; cheapest |
| longer countdown / wait for entrants | reuse `entryWindow.closesMinutes` semantics with an absolute base |
| start when ready (author presses go) | **new**: an author-authorised transition. Needs a rule for the author disconnecting |
| scheduled a few minutes out | this is just an ad-hoc slot with a later `startsAt`; the Guide already renders slots |

**The one needing a decision is "start when ready"**, because every other option is a timer and that one is a
*person* holding a session open. Minimum guardrail: an absolute maximum hold, after which it starts or voids.

## III.6 Interaction surface - what the law already says

The brief asks not to assume F6. **The repository has already ruled, and the ruling is stricter than the brief
assumes:**

> `competition.venue_options`: *"at most four options, each one a FINAL ACT and never a branch, no sub-menus and
> no tree. An option that cannot apply right now is ABSENT, not greyed out - a disabled row is a dead end the
> player has to read and reject, which is the failure KB-32 describes from the other side."* (owner, 2026-09-21;
> raised to five on 2026-09-23 when every option became always-present.)

A six-step Foreman wizard is a tree. **It cannot live at a world-space prompt** without contradicting that
ruling. So the split is forced, and usefully so:

| Weight | Surface | Contents |
|---|---|---|
| tiny | world/venue prompt (<=5 final acts) | `Race Here` / `Invite <player>` / `Enter Race` / `Practice` / `History` |
| small | toast with action, or a `playerInteractions` prompt | `<Player> wants to race. [Accept] [Decline]` |
| medium | chat commands | `/ncm.race`, `/ncm.race @player`, `/ncm.race start` |
| large | F6 panel mode | the deep constructor, the Guide, Messages, Market, Machine Index |

There is a hard budget on the large end: **eight CEF surfaces per resource, and `ncm_world` already holds seven**
(`IDEA-570`) - three of them invisible 16x16 transport pages to the local Carrier. **One spare.** So a new
constructor must be a *mode of `panel.html`*, exactly as the Landing panel was, not a new page.

## III.7 Race creation cost

Where a fee fits cleanly, without inventing anything: **Economy v1 already charges at check-in and freezes
authored economics at post time.** An authoring cost is therefore naturally *a second, separate debit at post
time*, itemised in the same statement, through the same idempotent transactional service, with the same refund
path used for abort/restart. Its fiction is administrative - NCM sanctioning a run - which is also its spam
control and its commitment device.

The one thing to avoid: making the author's fee a share of the purse. That couples authoring to field size and
creates an incentive to invite weak fields. Keep it a flat sanctioning cost.

## III.8 Scheduled-race coexistence - alpha guardrails vs later intelligence

**Minimum guardrails required now**, all cheap and all local:

1. One live ad-hoc event per author.
2. A player may hold at most one entry/reservation at a time - `playerInteractions.isReserved` gives this free.
3. An ad-hoc event may not start inside a scheduled event's entry window **on the same route**. One route
   comparison, not a network model.
4. An absolute cap on concurrent ad-hoc events per server.
5. An absolute hold timeout for "start when ready".
6. Ad-hoc events are excluded from anything settlement-authoritative until Part IV's eligibility rules exist.

**Later, and explicitly not now:** occupied start areas, overlapping-route detection, shared node/checkpoint
arbitration, traffic interaction, simultaneous-session isolation. The brief is right that overlap chaos is useful
alpha data. One platform lever for the eventual answer: `Open77.npcs.setBucket` and `Open77.routingBuckets.*` mean
**session isolation is achievable by bucket** rather than by scheduling - which may make most conflict
intelligence unnecessary.

---

# PART IV - BOOK QUEEN BILLIE STUDY

## IV.1 What actually shipped

`modules/betting.lua`, 1,227 lines. Her exact contact name is **`BookQueen Billie`**. She sells three products,
and the first one is not a bet.

### Product 1 - fronted single-race contracts

```lua
light    = { ratio = 0.25, winMultiplier = 1.70, podiumMultiplier = 0.55, lossPayoutRatio = 0.18, repPenalty = 20 }
standard = { ratio = 0.50, winMultiplier = 2.05, podiumMultiplier = 0.80, lossPayoutRatio = 0.30, repPenalty = 35 }
heavy    = { ratio = 1.00, winMultiplier = 2.65, podiumMultiplier = 1.05, lossPayoutRatio = 0.50, repPenalty = 60 }
```

**Stake is not chosen. It is derived**: `roundStake(Careers.maxStake(career) * ratio)`, where `maxStake` is
`config.stakeMaxByTier[career.tier]` = `{Gonk 2000, Streetkid 8000, Solo 25000, Fixer 75000, Edgerunner 200000}`,
rounded to the nearest 100 and floored at 100. **The player picks a risk *posture*, not a number** - which is why
the choices read "Light / Standard / Heavy contract" and not "how much?".

Settlement (`resolveRace`):
- **P1**: `addEddies(stake * winMultiplier * riskModifier)`
- **podium** (<= `podiumFloor`, 3): `addEddies(stake * podiumMultiplier * riskModifier)` - a partial return
- **otherwise**: the stake is already gone, **plus** `payoutPenalty = min(racePurse, stake * lossPayoutRatio)` is
  clipped off the purse, **plus** `repPenalty` reputation

So a loss is punished three ways - lost stake, a bite out of the race purse, and reputation - and the purse bite
is **capped by the purse itself** (`math.min(updates.payout, ...)`), which is the one anti-bankruptcy safeguard in
the system. That is the "fronted paper" fiction made mechanical: Billie is not holding a bet, she has advanced you
standing and takes it out of your winnings.

### Product 2 - winner slips (a real book)

`buildWinnerBoard` prices **every runner including the player**, with a genuine market model:

```lua
score   = driverThreatScore(entry)              -- pace*100 + consistency*34 + aggression*12
                                               -- + wins*4 + rivalScore*0.45 + h2hWins*8 + formScore
weight  = math.exp((score - maxScore) / 26.0)   -- softmax, temperature 26
prob    = clamp(weight / totalWeight, 0.06, 0.72)   -- floor 6 %, ceiling 72 %
odds    = clamp(round1(0.92 / prob), 1.5, 9.5)      -- 8 % overround; 1.5x .. 9.5x
```

The player's own entry is synthesised by `playerWinnerEntry`: pace from **vehicle race fit**
(`Parts.getRaceFitForConfig`), reputation and win streak, adjusted by average field threat; consistency from
podiums/racesFinished; aggression from win streak.

The board derives three named picks the dialogue exposes:
- **favorite** = highest probability
- **value** = the best `probability * odds` edge among entries **other than the favorite**, requiring
  `probability >= 0.12`
- **dog** = lowest probability (computed, never surfaced)

Flow: `Who's the favorite?` / `Where's the value?` -> `Back me` / `Back the favorite` / `Back the value` (writes
`state.winner.pending`) -> `Light` / `Standard` / `Heavy` at ratios `{0.25, 0.40, 0.65}` -> `armWinnerBet` escrows
and inks the slip.

**Two anti-staleness guards, and they are good:**

```lua
marketId = "<routeId>|<startType>|<fieldCount>"
if board.marketId ~= pending.marketId then -> "Board moved. Pull me fresh odds before I ink anything."
if selected.driverId ~= pending.driverId   -> "That price moved under your hand. Pull the board again."
```

Settlement finds the winner from `context.results` (lowest position) and pays `stake * odds` on a match.

### Product 3 - streak tickets

```lua
[3] = { ratio = 0.75, completionMultiplier = 4.60, failurePayoutRatio = 0.18, repPenalty = 45, podiumFloor = 3 }
[5] = { ratio = 1.25, completionMultiplier = 7.90, failurePayoutRatio = 0.28, repPenalty = 80, podiumFloor = 3 }
```

A leg **succeeds on a podium, not a win**. Each success accumulates `riskSum`; the projected payout is
`stake * completionMultiplier * (riskSum / progress)` - i.e. **the ticket pays more for having been earned in
harder races**, which is a genuinely elegant piece of design. One failed leg snaps the ticket, clips the purse and
costs rep. Note `ratio` can exceed 1.0, so a streak ticket can stake **more than the tier's nominal max**.

### The risk model

`Betting.getRaceRisk(career, config, field, activeEvent)` produces a multiplier that scales *every* payout:

```text
base 0.92
+ min(0.20, max(0, (distance - 2800) / 10000))    longer is riskier
+ min(0.18, max(0, (driverCount - 4) * 0.035))    bigger field is riskier
+ tierRiskBonus(career)                           -- SEE THE DEFECT BELOW
+ 0.14 endurance | -0.05 drag | +0.18 knockout
+ 0.04 rolling start
+ 0.06 allowCombat
+ 0.03 qualiEnabled
+ min(0.10, winStreak * 0.02)                     confidence is priced
+ min(0.12, lossStreak * 0.03)                    desperation is priced
clamped to [0.85, 1.60]
labelled: <1.00 "safe" | <1.15 "steady" | <1.30 "live" | else "chaotic"
```

### A live defect, found in the archaeology

```lua
-- betting.lua, tierRiskBonus
local byTier = { Gonk = -0.04, Street = 0.00, Amateur = 0.04, SemiPro = 0.08, Pro = 0.12, Legend = 0.16 }
```

```lua
-- careers.lua, TIER_TABLE
{ "Gonk", "Streetkid", "Solo", "Fixer", "Edgerunner" }
```

**Only `Gonk` matches.** `Streetkid`, `Solo`, `Fixer` and `Edgerunner` all fall through to `0.0`, so the entire
tier-progression term of Billie's risk multiplier has been dead for every player above the lowest tier, and dead
silently - the table lookup has a default, so it can never report having missed. Logged as **`KB-161`**. It is the
same failure shape as `KB-155`: *a guard that can never report having fired is indistinguishable from a bug.*

### State, safeguards and cancellation

`career.bettingState` holds `{single, winner = {pending, slip}, streak, lastOutcome}`. Safeguards actually
present:

- the stake is **escrowed up front** via `removeEddies`, with an affordability pre-check (`getPlayerEddies`)
- `syncRaceStake(amount, escrowed)` publishes the exposure to the race HUD
- `onRaceCancelled`: single and winner paper are **voided and the stake returned** - but only if the state is not
  `countdown` or `racing`. Once the lights are out, the paper stands.
- one live product of each kind; re-arming a single contract explicitly clears the old one first
- Billie's **menu only opens at `raceState == 2`** (pre-race). During `countdown`/`racing`: *"Window's shut while
  the grid is moving."*

### Presentation

Every outcome string is `pick({variantA, variantB})` - two authored phrasings per event, chosen at random, so
repeated interaction does not read as a template. Representative voice:

> *"Mmm. It's playable. Chalk is short, value's mean, and the board still has room to hurt you. You feeling sharp
> or noisy?"*
> *"I sell fronted single-race paper, winner slips, and long streak tickets. Pick your risk and wear it."*
> *"Board's warm. Pull the winner sheet, take legacy paper, or keep a long ticket breathing before the lights
> drop."*
> *"Pick the name first. I don't ink blank paper."*
> *"Paper landed. Clean. I do enjoy it when confidence cashes."*
> *"%s burned. I clipped %s off the purse and tagged you for %d rep."*
> *"No board, no paper. Bring me a field and then we can flirt with risk."*
> *"If it finishes, I'll price it. If it rattles, that's Stu's romance."*
> *"My book stays shut until you've got a live career."*

Her lexicon is tight and worth preserving as a controlled vocabulary: **paper, sheet, ink, slip, chalk, board,
purse, breathing, burned, clipped, playable, live, void.** `voice_harness` enforces
`requiredAny = {sheet, paper, odds, ink, risk, pay, chalk}` and forbids
`{chassis, "route to", poster, "grid is staged"}`.

## IV.2 What survives the move to a persistent economy, and what does not

| SP mechanism | MP verdict |
|---|---|
| Risk **posture** rather than a free stake amount | **Keep, and keep hard.** The best anti-exploit property in the design: exposure is bounded by progression, not by wallet. It caps the blast radius of every exploit below. |
| Escrow up front, atomic settlement | **Keep.** Economy v1 already has exactly this service - idempotent, transactional, itemised receipts. Billie must not get her own money path. |
| Loss clips the **race purse**, capped by the purse | **Keep.** It is the bankruptcy floor. |
| Reputation penalty on loss | **Re-derive.** SP rep is a single-player ladder; MP has ratings, Tags and Badges instead. |
| Softmax book over a *synthetic AI field* | **Cannot port as-is.** MP fields are humans. Pricing a human's win probability from server-held records is a *different and much more dangerous* act (IV.4). |
| **Winner slip on another runner** | **Dangerous in MP.** Betting on a specific human is the collusion surface. See IV.5. |
| Winner slip **on yourself** | **This is the portable core.** "I am confident, so I increase my exposure" needs no opponent pricing at all. |
| Streak tickets | **Keep, with a settlement-authority filter.** Podium legs and risk-weighted payout are good; legs must only count from settlement-authoritative races. |
| `marketId` staleness guard | **Keep and strengthen** - in MP the field changes until the window shuts, so the market key must include the *entrant set*, not just `route|start|count`. |
| Void on cancellation before countdown | **Keep**, and extend: MP has abort/restart refunds already, and disconnects, which SP did not. |

## IV.3 The economic shape, stated plainly

The loop is a **sink with a conditional faucet**, and that is genuinely good for NCM Online, because the
repository's stated problem is the opposite of a money shortage: `IDEA-558` is explicitly about needing bounded
liquidity and explicit, capped faucets, and `IDEA-554` about a positive solo loop.

The danger is precise: **a self-wager is a player-controlled faucet whose tap is their own skill.** Three
properties keep it honest:

1. exposure bounded by progression (the `ratio * maxStake` design),
2. payouts scaled by a risk model the player cannot cheaply inflate,
3. eligibility restricted to races whose results are settlement-authoritative.

SP has (1) and (2). (3) does not exist in SP because SP had no concept of an inauthentic race.

## IV.4 Exploit surfaces that are new in multiplayer

| # | Surface | Mechanism | Mitigation direction |
|---|---|---|---|
| E1 | **Solo time-trial self-wager** | a deterministic, repeatable, opponent-free activity; back yourself heavy every time | **Exclude entirely.** The brief is right. Also excludes free practice and qualifying, which already mint nothing. |
| E2 | **Manufactured weak field** | author an ad-hoc race, invite a slow friend, back yourself | require >= N *unaffiliated* human entrants; make player-authored races ineligible in alpha; rate-limit repeat pairings |
| E3 | **Head-to-head money printing** | two players alternate wins, both cash | per-pair repeat floor - the economy already has a **repeat floor** concept for route/economy opportunities (`L169`); reuse the pattern for wager pairs |
| E4 | **Disconnect abandonment** | wager, then disconnect when losing to dodge the purse clip and rep | treat disconnect-after-start as a **loss**, not a void. SP already stands the paper once the lights are out. |
| E5 | **Restart/abort farming** | arm, abort before countdown, repeat to fish for a favourable risk multiplier | voids are free pre-countdown in SP; add a cooldown or a small non-refundable ink fee on the *second* void in a window |
| E6 | **Field collapse** | back yourself in a contested race; everyone leaves; it settles as solo | `IDEA-554` already names this hazard for entry fees. **Wager economics must freeze at window close, and a collapse to solo must void the paper rather than pay contested odds.** |
| E7 | **Collusive odds shaping** | entrants coordinate so the board misprices a chosen runner | do not sell paper on *other humans* in alpha (IV.5) |
| E8 | **Record shaping** | deliberately tank races to depress your own priced probability, then cash a long self-price | price self-wagers from **posture and race properties**, never from the player's own win-probability estimate |
| E9 | **Multi-account** | a second client as a compliant opponent | out of scope for this design; belongs to account policy |

**E8 deserves emphasis because it is the one the SP design walks straight into.** The moment Billie prices *your*
probability from *your* record, deliberately losing becomes profitable. The SP book does exactly this
(`playerWinnerEntry` -> softmax -> odds) and it is safe there only because the opponent is a machine and the
economy is private.

## IV.5 Eligibility - a concrete proposal

Not "prohibit everything risky". A property test on the race, evaluated at window close:

```text
WAGER-ELIGIBLE if and only if all of:
  settlement_authoritative   the race pays through economy.settlement (not practice, not quali)
  provenance in {scheduled}  alpha: official calendar events only; ad-hoc later
  human_entrants >= 2        at window close AND at the flag
  field_not_collapsed        did not fall below 2 humans after the window shut
  distinct_pairing_ok        this exact entrant pair/set is under its repeat floor for the window
  author_not_wagering        if ad-hoc is ever allowed: the author cannot hold paper on their own event
  result_is_final            not DSQ-pending, not under review
```

with product-level gates on top:

| Product | Minimum field | Notes |
|---|---|---|
| **Self-paper** (light/standard/heavy on own finish) | 2 humans | the core loop; the podium floor must scale - in a 2-car field "podium" is meaningless, so a 2-human race pays **win or nothing** |
| **Streak ticket** | 2 humans per leg | legs count only from eligible races; a leg run in an ineligible race is *skipped*, not failed |
| **Winner slip on another human** | **not in alpha** | revisit only with >= 6 humans, a pairing-history check, and published odds |

## IV.6 Small fields - the two-human case in detail

A two-human race is legitimate racing and should stay wagerable. But its *wager* behaves differently:

- **What can be bet on?** Finishing first. Nothing else is distinguishable.
- **What is success?** P1 only. `podiumFloor = 3` is nonsense in a field of two - a podium return would pay for
  losing. **`podiumFloor` must be derived from field size**, e.g. `min(3, ceil(humanEntrants / 2))`: 1 for two
  humans, 1 for three, 2 for four, 3 for six.
- **How are payouts calculated?** Keep the risk model. The field term `(driverCount - 4) * 0.035` already gives a
  small field a *lower* multiplier, which is correct - beating one person is worth less.
- **Does opponent strength matter?** It should, and NCM Online has the material - but **not through odds on the
  opponent**. Use it as a *risk-model input*, exactly as SP used average field threat. A high-rated opponent
  raises the multiplier on your own paper. That preserves the interesting question ("am I confident against *this*
  person?") without creating a market in humans.
- **Can two players collude?** Yes, trivially - which is why E3's per-pair repeat floor is mandatory, not
  optional, for two-human wagering.
- **What existing NCM data could inform this?** Driver profile and standings, Race Tags (clean-driving facts),
  incidents, `competition.driver`, `session.standings`, per-route history, and the **Discoveries Inspired**
  standings. All server-held and authoritative.

## IV.7 Character presentation - what must not happen

Billie must not become a betting menu, and the archaeology gives a concrete reason she was not one in SP: **her
mechanics were expressed only through her voice.** The stake tiers are "light / standard / heavy **contract**".
The cancel action is "**Void the slip**". The read-only action is "**Open the books**". The staleness refusal is
*"Board moved. Pull me fresh odds before I ink anything."* There is no neutral system phrasing anywhere in
`betting.lua` - `voice_harness` explicitly forbids it for her.

**Port the vocabulary as a constraint, not as flavour text.** If a future MP betting surface has a button
labelled "Cancel Bet", the character has already been lost.

Surface recommendation: **Messages is her home** - she is the one contact whose history is genuinely worth
re-reading (slips, settlements, streaks) - with a **contextual appearance at race entry** when an eligible race is
about to close. She is `initiative = opportunistic` in the voice matrix, and a persistent world finally lets her
be exactly that: she notices an eligible race and writes to you.

## IV.8 Do we need multiple bookies?

**Recommendation: no, and record why.**

The honest test is whether a second bookie creates a *decision* or a *duplicate*. Differentiation by odds requires
a real market-maker model NCM does not have and should not build. Differentiation by bet type is better expressed
as more products from one bookie. Differentiation by region or category is a filter, not a person. The realistic
outcome of two bookies is two interfaces, two balance surfaces and two settlement paths for one loop.

The *one* version with genuine leverage is a different idea wearing the same clothes: **a discoverable bookie is a
lead, not a competitor.** A world graph in which access to a particular corner of the betting world is something
you learn about from a person (Part VII) uses Billie's identity as a gate rather than diluting it. That is a
discovery feature, not a market feature, and it costs one message and one knowledge row rather than a second
economic subsystem.

---

# PART V - RICO / STU / FAN / DEX

## V.1 Rico

**What he was doing:** translating the synthetic attributes of AI drivers (`pace`, `consistency`, `aggression`,
`wins`, `rivalScore`, `headToHeadWins`, `recentFinishes`, `personality`) into characterful, actionable prose via
`driverReason` and six brief builders, with three structurally different products: a *field read* (what kind of
race is this), a *watchlist* (three named people and why), and a *world read* (ladder movement).

**What now occupies that territory:** nothing. NCM Online has `competition.driver`, `session.standings`,
`competition.race_tags`, `competition.incidents`, entry lists and per-route history - **data without a narrator**.
The Race Guide says what is scheduled; the Driver File says what you did. Nobody says *who you are about to race
and what that means.*

**Multiplayer makes him much stronger.** Everything `driverReason` needed, NCM Online has authoritatively and
truthfully:

| SP synthetic attribute | MP authoritative equivalent | Status |
|---|---|---|
| `recentFinishes` / form | results history per driver | exists |
| `wins` | standings / accomplishments | exists |
| `headToHeadWins` | derivable from shared race results | **derivable, not stored** |
| `rivalScore` | derivable from co-entry plus proximity of finish over time | **derivable, not stored** |
| `aggression` | **Race Tags + incidents** - and these are *factual*, not modelled | exists, and better than SP |
| `consistency` | finish-position variance; clean-run rate | derivable |
| `pace` | route best times; observed capability (Machine Knowledge) | exists, with epistemic bounds |
| `personality` ("crash magnet") | **must not be invented.** Tags already say "contact", "penalty" as *facts* | replace with Tag-derived phrasing |
| - | vehicle choice, manufacturer tendency, course history, badges, Discoveries Inspired | **new material SP never had** |

**The rule that keeps him honest:** `competition.race_tags` evaluates and emits **all qualified facts separately
from its capped display set**, and the Machine Knowledge vocabulary distinguishes `observed_speed_floor` from a
top-speed claim precisely so that *"an observed 156 km/h supports 'at least 156' and never a top-speed claim."*
Rico must inherit that discipline: he may say *"they have never finished a race here without contact"* (a fact) and
must not say *"they're reckless"* (a character judgement about a real person). **That constraint is also what
makes him interesting** - paddock intelligence about real people is more chilling when it is provably factual.

**Surface:** race-entry context - the moment before you commit is when a field read is worth anything - with the
brief persisted to Messages so it can be re-read. **Character: preserve strongly. Function: preserve and extend.**

## V.2 Setup Stu

**What he was doing:** reading `Parts.getVehicleSummary` - installed parts, a build-identity headline, ranked
strengths, and a **weakest axis** mapped through `AXIS_TO_SLOT` to a purchasable slot - and narrating it as
mechanical advice, then routing to parts sourcing or tuning. His DCES role was larger: he is the delivery contact
for five of the twelve archetypes (counter-build, setup contract, crew warning, and all four tier-promotion
contracts).

**What assumptions he made:** the summary's axes were a parts-model abstraction, and Stu spoke about them as if
they were vehicle behaviour - *"the rear's arguing with you on exit"*, *"you're bleeding time in low-speed
rotation"*. In SP that was fine, because the parts model *was* the physics for NCM's purposes.

**This is the character the brief is most right about, and also where the sharpest care is needed.** NCM Online
now has a real Parts catalogue and economy, serialized Part assets, installation, the Carrier's **proven
three-lever physics boundary**, wear/lifecycle work, Engineering, and - crucially - a formal **epistemic
vocabulary** for what may be claimed about a machine (`competition.machine_knowledge`: `identity_reveal`,
`observed_speed_floor`, `observed_lateral_accel`, `observed_yaw_rate`, `observed_slip_angle`,
`observed_speed_retention`, `observed_gradient`, `observed_configuration`, `authoritative_specification`).

**What Stu can truthfully tell the player now:**

| Claim class | Permitted? | Basis |
|---|---|---|
| what is installed, by serial and Design | **yes** | ownership + installation records |
| the authoritative specification of a Part or configuration | **yes** | `authoritative_specification` |
| which of the three Carrier levers this configuration moves, and how | **yes** | the proven boundary |
| "this configuration has been observed to sustain at least X" | **yes, phrased as a floor** | `observed_speed_floor` and siblings |
| measured yaw rate / lateral accel / slip angle from real sessions | **yes, as observations with a basis** | the empirical kinds carry an obligation to name a basis and a live physics owner |
| the trade-offs of a Design, as authored | **yes** | Part design data |
| **"your car oversteers badly"** | **no** | a subjective driving judgement; the server was not driving |
| **"you're bleeding time in low-speed rotation"** | **only with evidence** | requires sector/telemetry comparison NCM does not yet publish |
| a recommendation ("I'd change the map before the hardware") | **yes, as a recommendation** | an opinion clearly owned by Stu is honest; a measurement falsely stated is not |

The distinction to hold: **Stu may interpret configuration and modelled effect, and may have opinions, but may not
report a driver's felt experience as a server fact.** Note that `IDEA-538` records the brakeScale/drag coupling as
*unresolved*, which is exactly the kind of thing Stu must not paper over.

**Surface:** contextual, from vehicle / parts / Engineering surfaces, where the car is already the subject.
**Character: preserve.** He is also the natural voice for the parts *economy* - a shop that tells you what it
would do is more inviting than a catalogue.

## V.3 #1 Fan

**What he was doing:** not statistics. `fan_engine.lua` interprets **race telemetry** into recognition - clean
overtake counts, lap-one gains, recoveries after being hit, deep-grid wins, route records, promotion moments,
clean streaks - with three authored variants per situation, permanent milestone de-duplication, and a genuine push
governor (`canPush` gates on both race gap and wall-clock seconds; one dispatch key per race).

**What now occupies that territory:** the **Driver File** shell surface (new on 2026-09-27) and Driver
Profile/standings. They hold the numbers well.

**The overlap hypothesis does not survive contact with the code.** Driver File can state that you have 7 overtakes
and a P8-to-P1 result. It cannot say *"Started P8 and still won it clean. That's the kind of race people bring up
twice."* The Fan's output is a **claim about significance**, which is a different artifact from a statistic - and
the repository has independently converged on caring about exactly this: `IDEA-586` codifies NCM's communication
register, and `visibility.lua`'s `currentCommitment()` copy is described in `NOW.md` as *"the clearest statement of
NCM's voice in the repository."*

**Multiplayer makes him stronger, for a reason SP could not have:** in SP, "the whole city is watching" was a lie
the player agreed to. In MP there are actual witnesses, actual rivals, and actual records other people can look
up. The Fan's core rhetorical move - *this is the version of the story people will retell* - becomes true.

**But he needs re-scoping.** SP's Fan reacted to every race. In a persistent world that is a notification problem,
and NCM has the solution already built and unused: **`player.communication`** (priority ambient / informative /
actionable / time_sensitive / critical; repeat modes always / once / cooldown / until_ack / adaptive; escalation;
durable exposure rows in migration 036). The Fan should be its **first consumer**.

**Surface:** pushed messages for genuine milestones, archived in Messages; the *numbers* stay in Driver File.
**Character: preserve. Function: narrow to significance, and pace it through `player.communication`.**

Open creative question worth keeping open: **one Fan, or an audience?** A single obsessed supporter is a
relationship. A crowd is a reputation system. They are different features, and the brief's hybrid instinct is
sound - a named Fan whose *intensity* is driven by a real audience signal is more interesting than either.

## V.4 Dex / NCM Dispatch

**What he actually did, precisely:** `OpenContactRoute(contactId)` - sync phone state, seed the target contact's
default message, activate that contact in the journal (**creating it in the player's phone the first time**),
notify, and re-activate his own conversation so the player can return. Plus one static greeting. That is the whole
of Dex.

Against the brief's list:

| Candidate role | Verdict from the implementation |
|---|---|
| onboarding | **partly** - the journal's only quest is `ncm_onboarding` -> phase `contact_dex` -> objective `contact_dex`, and the localized strings are "Night City Motorsports" / "Contact Dex". So Dex *is* the authored first step. |
| directory | **yes** - six routes, unconditional |
| contact unlock mechanism | **yes, de facto.** Routing through Dex is what makes a contact exist. The designed unlock layer in `onboarding.lua` was never wired. |
| dispatcher | **in name only.** He dispatches the player, never a race. |
| narrative glue | **no.** One line, no memory. |
| help system | **no** |
| notification system | **no** - `NotifySMS` is not his |
| race-routing system | **no** - that is Foreman's `ncm_track_start` |

**Does NCM Online still need an NCM Dispatch identity? Not as a contact. Yes as a sender.**

The *directory* function is gone: F6's shell nav already has six modes (Guide, Market, Machine Index, Driver File,
Help, and now the Landing panel), keyboard- and gamepad-navigable from one focus scope. A contact whose job is to
list other surfaces is a second, worse navigation system.

The *unlock* function is exactly what the addendum wants, and it does not need a menu - it needs **a message that
grants knowledge**. That is Dex's real value, and it maps onto machinery that already exists:
`message.from_kind` / `from_id` / `actions` / `ref_kind` / `ref_id` / `expires_at`.

**Recommendation:** Dex becomes **system characterization** - the voice and sender identity of NCM Dispatch, an
*organization* that writes to you. Onboarding voice, event announcements, the first authored thread, world-facing
NCM communications. Keep the register exactly as recovered: short, clean, neutral, <=22 words, routing vocabulary,
no hype and no analysis. His existing line is already perfect for an organization rather than a person:

> *"You're through to NCM. What are you looking for?"*

**One concrete blocker, and it is small:** `message.from_kind` is `ENUM('team','system','race_control')`. A
`dispatch` or `character` sender requires an `ALTER TABLE` migration. That is the total cost of giving the
persistent world a voice.

---

# PART VI - MESSAGES STUDY

## VI.1 What exists - much more than "historical work"

**PROVEN, deployed, and in use.** Not a prototype.

**Server** (`ncm_league/server/organized.lua`, lines 72-140): `messageCreate`, `messageResolve`, `messageList`,
`messageRead`, `pushInbox`, and net events `ncm:inbox`, `ncm:inbox.read`, `ncm:inbox.act`.

**Schema** (migration **006**):

```sql
CREATE TABLE message (
  message_id   CHAR(36) PRIMARY KEY,
  server_id    VARCHAR(96)  NOT NULL,
  to_driver_id CHAR(36)     NOT NULL,
  from_kind    ENUM('team','system','race_control') NOT NULL,
  from_id      VARCHAR(64)  NULL,
  kind         VARCHAR(32)  NOT NULL,
  subject      VARCHAR(120) NOT NULL,
  body         TEXT         NOT NULL,
  actions      JSON         NULL,
  state        ENUM('unread','read','accepted','declined','expired') NOT NULL DEFAULT 'unread',
  ref_kind     VARCHAR(32)  NULL,
  ref_id       VARCHAR(96)  NULL,
  created_at   BIGINT       NOT NULL,
  expires_at   BIGINT       NULL,
  resolved_at  BIGINT       NULL,
  KEY ix_message_driver (server_id, to_driver_id, state)
)
```

**Client** (`ncm_world/client/panel.lua` + `web/panel.html`): a **mode of the existing panel**, opened by **F7** or
`/ncm.msgs`, rendering `#inbox` / `#inboxList` with `"<n> unread . <n> total"`, an empty state (*"Nothing in your
file yet."*), per-item actions dispatched as `ncm:inbox.act(id, action)`, read marking via `ncm:inbox.read(id)`,
and **chat twins** `/ncm.inbox`, `/ncm.read <n>`, `/ncm.accept` so a client whose page cannot take input still
works.

**Against the brief's checklist:**

| Question | Answer |
|---|---|
| What code exists? | server CRUD + net events + schema 006; client panel mode + renderer + chat twins |
| Wired into F6? | **yes** - a mode of `panel.html`, plus its own **F7** shortcut |
| What can it display? | subject, body, sender kind/id, kind, state, actions, refId, timestamps, expiry |
| Conversation/contact structure? | **no.** Flat list, newest first, `LIMIT 20`. `from_kind`/`from_id` exist but nothing threads on them |
| Unread state? | **yes**, authoritative, with a count |
| Notifications? | toast + chat at create (`Open77.notifications.send`, `Open77.chat.send`) |
| Persists? | **yes**, MySQL, server-authoritative |
| Abandoned? | **no.** It is the live seat-offer delivery path. The header calls it "NCM Messages v0 (P30)" |
| Reusable? | **Very.** It is already a generic actionable-message bus that happens to have one sender and one kind |

**Two design decisions already baked in and worth knowing:**

- **Lifecycle:** open messages always shown; resolved ones (accepted/declined/expired) for **6 hours**, then
  archived - *"the rows stay; the thread stops showing them."* An owner QA decision.
- **Privacy:** `KB-97` moved the inbox **off** the `player(id)` state bag, which reached every player in the
  routing bucket, onto a targeted net event plus a stream. Messages are private by construction, and that was a
  fix, not an accident. Any redesign must not regress it.

**Also present and unused for this purpose:** `core/player/communication.lua` (the pacing policy - five
priorities, five repeat modes, escalation, per-priority durations) and migration **036**
`player_message_exposure` (durable `shown_count` / `last_shown_at` / `acknowledged_at` per
`(driver, server, message_key)`). Both are **offline-green, uncommitted, undeployed, with no live PASS.**

## VI.2 The gaps, precisely

1. **`from_kind` is a three-value ENUM.** Characters, markets, manufacturers, dispatch and organizers all need one
   `ALTER TABLE`. This is the only schema blocker in the whole Messages story.
2. **No threading.** A flat `LIMIT 20` list cannot hold "three weeks of Billie messages".
3. **No sender identity presentation.** No display name, no avatar, no per-sender grouping.
4. **`actions` is an untyped JSON array** with a `[%w_]+` extraction regex; there is no action registry, so
   nothing validates that `accept` means anything for this `kind`.
5. **Nothing pushes except the seat offer.** One producer, one kind.
6. **`player.communication` is not wired to it.** The pacing module and the message bus do not know about each
   other.
7. **The 20-row cap and 6-hour archive** are right for offers and wrong for correspondence.

## VI.3 Four futures

### Model A - Contact Inbox
Threaded conversations per contact. Add `thread_id`, sender display identity, per-thread unread, and open the
`from_kind` ENUM.
*Strengths:* familiar; relationships legible; character identity strongest; history natural.
*Weaknesses:* invites player-to-player DMs, which the brief rules out and OPEN//77 already covers; pushes toward
"six characters, one UI", which the brief warns against; the heaviest build.
*Discoverability:* good. *Immersion:* high. *Cost:* highest. *F6 fit:* good - one panel mode.

### Model B - NCM Communications
Keep the flat, kind-driven bus and widen the senders: characters, Dispatch, markets, manufacturers, teams,
championships, researchers. Group by sender *kind*, not by thread.
*Strengths:* smallest delta from what is deployed - one ENUM widening plus producers; the world gets a voice
immediately; matches `from_kind`'s existing design intent; no DM pressure.
*Weaknesses:* a character and a settlement receipt sit in one list; character relationships stay shallow; "three
weeks of Billie" is still not readable.
*Discoverability:* good. *Immersion:* medium. *Cost:* lowest. *F6 fit:* excellent - no new surface.

### Model C - Contextual First, Archive Second
Characters appear where their subject is: Rico at race entry, Stu at the car, Billie at the closing window,
Foreman on the board, the Fan after a result. Messages is the **durable archive and the re-entry point**.
*Strengths:* matches the SP architecture that actually worked (state-to-surface projection, no tree); honours
`venue_options`' "final acts, not branches"; matches surface weight to interaction weight; avoids "one UI, six
contacts"; cheapest per character, because each reuses a surface that already exists.
*Weaknesses:* discoverability is the real risk - a contextual character can be missed entirely; each host surface
must learn a little character presentation; "where do I find Rico?" has no single answer.
*Discoverability:* weakest, and this is the thing to solve. *Immersion:* highest. *Cost:* medium, spread.
*F6 fit:* good - Messages is archive, not stage.

### Model D - **Recommended: a typed message bus with contextual *and* archival rendering, and one Dispatch thread**

Model C's surface strategy on Model B's data model, plus the single structural addition that fixes C's
discoverability problem:

- **One bus, typed.** Widen `from_kind`; add a small **sender registry** (id -> display name, kind, register) and
  an **action registry** (`kind` -> permitted actions) so `actions` stops being free JSON.
- **Every character interaction, wherever it surfaced, writes a message.** Rico's field read at race entry is
  *also* an archived message. That is what makes a contextual system re-readable, and it costs one insert.
- **Add `thread_id` now, use it lazily.** Group Billie's slips into one thread; leave receipts unthreaded. Not a
  conversation UI - a grouping key, which is a column and a `GROUP BY`.
- **One standing thread: NCM Dispatch.** This is the answer to "how do I find anything?" and to Part V.4. A player
  who knows nothing opens Messages and finds Dispatch, which is where threads begin. It replaces Dex's menu with
  Dex's *voice*, and gives the authored PvE layer a front door that is not a tutorial.
- **Pace everything through `player.communication`.** It exists, has tests, and has a durable exposure table. The
  Fan is its first consumer.
- **Keep the deployed privacy and lifecycle properties.** Targeted net event (`KB-97`); open-always - but make the
  6-hour archive and the 20-row cap **per-kind policy** rather than global, because an offer and a letter have
  different half-lives.

*Why not A:* threading is a presentation want, and buying it now buys DM pressure and a real UI with it.
*Why not B alone:* it never becomes a place you go to read about your career.
*Why not C alone:* nothing tells a new player that any of it exists.

The reason D is cheap is worth restating: **the bus, the panel mode, the chat twins, the privacy fix, the
persistence and the pacing policy are all already written.** The delta is one ENUM widening, two small registries,
one nullable column, and producers.

---

# PART VII - CHARACTER / DISCOVERY WORLD GRAPH

## VII.1 The substrate question, answered

The addendum asks for the smallest reusable substrate connecting characters, messages, places, markets, vehicles,
parts, racing, Discovery, Machine Index, research, economy and progression.

**Most of it exists, in three pieces that do not know about each other:**

| Need | What already exists | Status |
|---|---|---|
| declarative authored events with triggers, budget, cooldown, expiry, determinism | **SP DCES** (`contact_events.lua` + `contact_event_archetypes.lua`) | PROVEN in SP; not ported |
| a persistent, actionable, expiring, private delivery bus | **`message` table + inbox panel + chat twins** | PROVEN, deployed |
| repeat/priority/escalation pacing with durable per-player exposure | **`player.communication` + migration 036** | offline-green, undeployed |
| graded knowledge that is not a linear tier ladder | **Machine Knowledge**: `UNKNOWN -> DISCOVERED -> DOCUMENTED -> OBSERVED -> OWNED`, explicitly independent channels | SPEC + partly deployed (migration 033) |
| socially-caused discovery with anti-farming | **`competition.discoveries`** - "Discoveries Inspired": who *caused* another driver to discover a machine, with holding provenance, anti-farmed by the primary key `(driver, server, vehicleKey)` | PROVEN |
| market knowledge as a separate domain from vehicle knowledge | `17_MARKET_NETWORK.md`'s `player_market_knowledge` shape, with `source_kind` / `source_ref` | SPEC |
| a thread/quest engine | **nothing** | the actual gap |

**So the substrate is: DCES's declarative archetype model, retargeted from "parts and rivals" to "places, markets
and people", delivered over the deployed message bus, paced by `player.communication`, writing knowledge rows
whose epistemic vocabulary already exists.** That is a genuinely small build, and none of it is a quest engine.

## VII.2 What a thread needs, against what exists

| Thread element | Precedent | Verdict |
|---|---|---|
| stable id | `nextEventId` -> `dces_<seed>_<nnn>`; `vocabulary.ids.uuid4` | have |
| prerequisites | DCES trigger cascade + `sentEventKeys` | have as code; want as data |
| activation trigger | DCES `triggerTypes` | have |
| current state / step | DCES `activeEvents[].status` | have, shallow - one status, not a step |
| completion conditions | DCES `onOfferClaimed` / `onOfferExpired` | have, per-archetype |
| failure / cancellation | expiry in races; `messageResolve(state)` | have |
| messages | the `message` table | have |
| dialogue with choices | `actions` JSON + `ncm:inbox.act` | have for messages; **not for world NPCs** |
| objectives / leads | **nothing** | gap |
| waypoint / marker actions | `Open77.blips.create` (incl. native Ink geometry from NCM's own SVG glyphs), `Open77.markers`, `map.control` (declared) | AVAILABLE |
| contact unlocks | designed in `onboarding.lua`, never wired | design only |
| market knowledge change | `player_market_knowledge` shape | SPEC |
| item / vehicle / part checks | ownership + parts records | have |
| race checks | results, Tags, standings | have |
| rewards | Economy v1 settlement; part/vehicle assets | have |
| next possible threads | **nothing** | gap - this is the graph edge |
| persistence | career JSON in SP; MySQL in MP | have |
| version / migration | `Persist.loadVersioned` (SP); numbered migrations (MP) | have |

**Three real gaps: objectives/leads, thread steps, and graph edges.** Everything else is plumbing that exists.

## VII.3 Knowledge states - reconciling the addendum with the governing document

**This needs an owner decision and must not be resolved silently.** See Governance G1.

The addendum asks for a 17-slot market grid with sixteen `???` silhouettes, and a three-state
UNKNOWN / LEAD / DISCOVERED model.

`17_MARKET_NETWORK.md` is **STATUS: CURRENT** and is the named authority for *markets and market discovery*. It
says, in two places:

> *"Unknown markets are absent. There is no total market count, completion percentage, locked `???` market roster
> or canonical market catalogue disclosed to the client."*

> **DO NOT BUILD YET** - *"...market completion, undiscovered-market slots, global omniscient inventory..."*

and lists as an architectural test: *"Unknown markets are absent and no total count is exposed."*

**The two halves of the addendum's request separate cleanly, and only one of them conflicts:**

- **The LEAD state does not conflict.** It is consistent with the document's own `access_policy` seam
  (*"knowledge and access may diverge"*), with its `player_market_knowledge.source_kind` / `source_ref` columns,
  and with Machine Knowledge's precedent of independent accumulating channels rather than a tier ladder. A market
  you have *heard of* but cannot yet use is `known` plus `access denied, reason: no relationship`, which the
  schema shape already anticipates.
- **The `???` roster conflicts directly.** Sixteen silhouettes *is* a disclosed total count, and the document
  forbids it by name, with the reason: leaking hidden-market information through UI data, sorting, tooltips, ids or
  inventory calls.

**Options for the owner, stated neutrally:**

| Option | What it costs |
|---|---|
| **A. Amend the authority document** | The `???` grid is a deliberate psychological device and the owner may simply want it. Cost: a decision-record entry superseding that clause, plus the leak discipline the clause was protecting (ids, sort order, tooltips, payload shape). |
| **B. Keep the prohibition; get the same feeling another way** | The Machine Index already creates "there is more than you know" **without a count**, because a catalogue of encountered machines is visibly partial. Markets can do the same: show known markets, plus *leads* as named-but-inaccessible rows. Sixteen anonymous slots say "sixteen"; two named leads say "there is a world out there", and are *better fiction*. Cost: none architecturally; the device is weaker at session zero, when the player has no leads yet. |
| **C. Split the difference** | Disclose a *bounded, non-numeric* shape - "NCM knows of other suppliers in this district" - which is a count of nothing. Cost: needs care not to become a count by another route. |

**Recommendation was B. The owner ruled A on 2026-09-27** (`L171`): the sixteen-slot roster is approved and
supersedes document 17's clause. What follows is therefore no longer a choice, but two things from the B
recommendation survive and are worth keeping:

- **One lead at session zero.** Give a brand-new player a *named but unusable* market immediately, from
  Dispatch. Under option A this is now additive rather than a substitute: the roster supplies the shape, the
  lead supplies the first thread.
- **The leak discipline document 17 was protecting.** The count is now deliberately disclosed; the identities
  behind the slots are not. Slot ordering must not be inventory order, slot ids must not be market ids, and an
  undiscovered slot's payload must carry nothing but its unknown state.

## VII.4 The graph, as facts and edges rather than a ladder

The right shape is the one the addendum names: facts + relationships + conditions + events + consequences.
Concretely, four node kinds and one edge table:

```text
NODES (all already exist as domain objects)
  person    an authored contact, or a DCES-generated actor
  place     a market, venue, shop, district location
  thing     a vehicleKey, a Part Design, a manufacturer
  event     a race, a championship, a research opportunity

KNOWLEDGE (per driver, per node)    unknown | lead | known | accessible
  + source_kind   who/what caused this      <- already specified for markets and machines
  + source_ref    which person, race, trade, place

EDGES (authored)   from_node -> to_node, with a condition and a consequence
  reveals         learning A produces a lead on B
  grants_access   satisfying A makes B accessible
  introduces      A introduces person B
  supplies        place A carries thing B
  originates      thing A came from place B     <- this is the trade/provenance edge
```

A thread is then **a path through the edges**, not a numbered quest. Two players can enter the same subgraph from
different nodes, which is the stated goal. Authoring is writing edges.

**The trade case falls out of `originates` naturally, and this is the elegant part.** Player A buys a Part at a
market Player B has never discovered and trades it to B. B now owns an asset whose provenance names a place. That
does **not** grant knowledge of the market - it creates a **lead**, exactly as the market document's `source_kind`
anticipated. B knows the manufacturer, knows a Design exists, and has a thread to pull. Research can identify
origin; a character can react; a district clue can drop; or nothing happens until B investigates. **The player
economy generates PvE leads instead of bypassing PvE**, and the anti-farm property comes free from the same
primary-key discipline that already protects Discoveries Inspired.

## VII.5 Worked chains, illustrative only

```text
Dispatch --reveals--> [lead: a name in Kabuki]
   --world NPC--> a venue contact --grants_access--> Market #2
   --supplies--> an unfamiliar manufacturer --originates--> a Design
   --introduces--> an independent tuner (DCES `independent_tuner` pool)
   --reveals--> a venue --posts--> a race format you have not run

Rico --reveals--> "the car that beat you came from somewhere you don't know"
   --originates--> place --supplies--> Part Design --introduces--> Stu's specialist
   --grants_access--> engineering location

Stu --reveals--> "this Design has one interface class nobody stocks locally"
   --introduces--> parts broker --grants_access--> component supplier

Billie --reveals--> "the paper on that route is thin because of who runs it"
   --introduces--> venue operator --grants_access--> a race provenance you could not post before

Trade --originates--> a Part from an undiscovered market
   --> lead --> Research identifies origin --> district clue --> place --> supply
```

Every one of these uses a character's **existing** system function as the reveal. Rico reveals through a field
read; Stu through a configuration reading; Billie through market talk. No character acquires a new job. That is
the test of whether the graph is authored rather than bolted on.

## VII.6 Physical NPCs - feasibility, with build-pinned evidence

**This is much stronger than the addendum assumes.** `Open77.npcs` is **36 server natives plus 6 client**, plus
`Open77.npcs.tasks` at **27 server natives**. And `ncm_world`'s manifest **already declares `world.npcs`** - the
permission is in place and unused.

| Question | Verdict | Evidence |
|---|---|---|
| authored NPC exists at a location | **AVAILABLE** | `npcs.create(def)`, `npcs.setTransform(id, {position, yaw})`, `npcs.update(id, patch)` |
| identify / read it | **AVAILABLE** | `npcs.get(id)`, `npcs.all(bucket?)`, `npcs.owner(id)` |
| make it stand still and be harmless | **AVAILABLE** | `setAIEnabled(false)`, `setCombatEnabled(false)`, `setPerceptionEnabled(false)`, `setVoiceEnabled(false)`, `setBehavior(policy)`, `setDamagePolicy(...)`, `setAiMode(...)` |
| dress it / give it identity | **AVAILABLE** | `setAppearance`, `setEquipment(slot -> "Items.*")`, `getEquipment`; `npcs.templates()`; the `npc-templates` data catalogue |
| **voice without VO recording** | **AVAILABLE, and better than expected** | `npcs.speak(id, voice, {ignoreFrustum, ignoreDistance})` plays a line **from the NPC's own voiceset**; `npcs.voices()` returns the documented bark vocabulary with the 2.31 source that plays each. *"`true` is the line queued, not the line heard."* |
| wait until it is really there | **AVAILABLE** | `npcs.whenReady(id, timeoutMs)` - a promise resolving once at least one client has a ready body |
| per-player independent state | **AVAILABLE** | `npcs.setBucket(id, bucket)` + `Open77.routingBuckets.*`; NCM already reasons in buckets |
| determine range | **AVAILABLE** | `Open77.world.nearby(radius)` (client, `world.query` - declared), `vehicles.nearby` / `closest` (server) |
| interaction prompt | **PLAUSIBLE - the gap** | no NPC-interaction-prompt native was found. The platform's own prompts are `open77_interactions` (a CEF surface at z660). NCM would draw its own; `Open77.character.aimedEntity` (client, `player.aim.read` + `world.query`) gives *"the engine's own look-at target"*, the right input for "am I looking at this person" |
| prevent accidental activation | **PLAUSIBLE** | range + aim + an explicit key; `input.actions` is declared |
| dialogue without F6 | **PLAUSIBLE** | a compact panel mode or a small overlay - **but see the surface budget: one spare CEF page** |
| player response choices | **PLAUSIBLE** | same surface; `actions` semantics already exist in the message bus |
| gamepad accessible | **PROVEN pattern** | `client/nav_input.lua` + `web/ncm-nav.js` already do exactly this: Lua reads the pad, sends semantic actions, the page never names a button. Pad BACK is authoritative in Lua (`KB-61`) |
| conversation state | **AVAILABLE** | MySQL; the thread substrate |
| server-authoritative progression | **AVAILABLE** | NPCs are server-authoritative by construction |
| two players talk to the same NPC | **UNKNOWN** | `playerInteractions.isReserved` gives exclusivity for *player-to-player*; whether it can reserve a player against an NPC interaction is untested |
| persistence across restart | **PLAUSIBLE** | re-create from authored data on `onResourceStart`; the id will differ, so **nothing may store an NPC id as identity** |
| vanilla assets safely | **AVAILABLE** | `npcs.templates()` and the `npc-templates` catalogue are the platform's own |
| sync implications | **PLAUSIBLE** | authoritative NPCs are replicated; a standing, AI-disabled, invulnerable NPC is close to the cheapest possible case |

**Conclusion: the modest primitive the addendum describes - NPC stands somewhere, player approaches, prompt, text,
choices, state advances, consequence - is reachable with one genuine unknown (the prompt/dialogue surface,
constrained by the one remaining CEF page) and one untested question (two players at one NPC).** That is a
prototype, not a research programme. Text-first is not a failure state, and `npcs.speak` means even a text NPC can
bark in its own voice.

## VII.7 AI traffic - CORRECTED 2026-09-27 after owner challenge

> **This section originally concluded that shared traffic was BLOCKED. That conclusion was wrong** and is
> retained below only as a correction record. The error was **conflating two different things**: vanilla
> REDengine *ambient population* traffic, which is genuinely client-local, and **shared AI traffic built from
> server-created canonical vehicles**, which has been available since op77.54/.57 and received a dedicated
> release on 2026-09-24. I answered from an op77.78 index without checking the platform's own release channel.
> `AGENTS.md` says to query current build-pinned cards before using methods; the failure here was narrower and
> worse - I did query, got an index three builds stale, and reported its silence as absence.

### What the platform actually shipped

The OPEN//77 changelog of **2026-09-24**, *"AI traffic rolls into Night City"*, leads with:

> **Traffic Sync** - *"Shared AI traffic is now in: cars can join and drive in traffic with synchronized vehicle
> movement across players."*

with supporting items in the same release: **Multiplayer Feel** (nearby players get priority spawning),
**Streaming Fix** (remote players and vehicles no longer held back by brief timing-data gaps), **Vehicle Sync**
(parked owned cars avoid unnecessary high-frequency updates), **Car Attribution**, **Impact Logic** and
**Stability** (structural vehicle records no longer silently dropped at queue limits under heavy world-traffic
situations). The devblog frames the intent plainly: *"Streets can now have believable moving vehicles instead of
only static scenery and human players"*, delivered as *"the traffic resource and the networking support needed
to push car movement cleanly enough for other players to see the same thing."*

### The mechanism, from the build-pinned guide

Shared traffic is **not** the vanilla population being synchronized. It is the existing networked-vehicle-AI
path, which the `vehicle-ai` guide describes exactly:

> *"`Open77.vehicles.ai` is a server API requiring `world.vehicles`. The server owns destinations, seat
> reservations and task lifecycle. **One nearby ready client executes native driving; observers receive
> replicated motion** under the existing authority lease and routing-bucket rules."*

and, decisively for the distinction this section originally got wrong:

> *"`joinTraffic` uses indefinite road-following, **not ambient population spawning**."*

So a shared traffic car is a **server-created canonical vehicle** (`Open77.vehicles.create`) with a driver
controller attached (`ai.attachDriver`, optionally driverless - *"the driver's seat is empty on every client.
No invisible NPC, character model or hidden actor is required"*) and `ai.joinTraffic` issued. Every such car has
a canonical id, is replicated, and is visible to everyone. The 2026-09-24 release adds a dedicated **traffic
resource** on top of that, plus the networking work to make it hold up at density.

### What this changes for NCM

| Claim | Before | Corrected |
|---|---|---|
| Shared AI traffic across clients | "BLOCKED" | **AVAILABLE** - `vehicles.ai.joinTraffic` since op77.57, plus a dedicated traffic resource from 2026-09-24 |
| Vanilla *ambient population* traffic is per-client | true | **still true, and still the reason you cannot simply "turn traffic on" and have it be shared** |
| A race through traffic is a race through different traffic per driver | asserted flatly | **only if the traffic is vanilla population.** Server-created traffic is the same cars for everyone, so the fairness/incident/Tag objection dissolves for that path |
| Racing integrity objection | presented as decisive | **withdrawn for shared traffic**; it applies only to the vanilla-population path |

`ncm_world` and `ncm_league` **already declare `world.vehicles`**, which is the permission `vehicles.ai.*`
requires. NCM needs no new permission to drive this.

### What the op77.102 server package actually shows (inspected 2026-09-27)

The owner supplied `open77-server-2.31.13+op77.102-linux-x64.tar.gz`. Diffing it against the `.87` package in
the workspace root gives **712 files vs 705**, and once the Windows-vs-Linux runtime binaries are discounted the
real content delta is small:

| New in `.102` | What it is |
|---|---|
| `docs/server-configuration.md`, `docs/metrics.md`, `docs/rcon.md` | operator documentation, shipped for the first time |
| `tools/rcon/{cli,client}.mjs`, `README.md` | the RCON client the changelog mentions |
| `resources/gamemodes/freeroam/race/server/state_delivery.lua` | a bounded race-state delivery cache (see below) |
| `resources/gamemodes/freeroam/shared/roster.lua` | 2 lines |

**Confirmed, and it settles part of the question:**

1. **No `open77_traffic` resource ships with the server**, at `.87` or `.102`. The resource set is unchanged:
   `gamemodes`, `open77_equipment`, `open77_wardrobe`, `polyzone`, `system`. Whatever the devblog means by *"the
   traffic resource"*, it is not a Lua resource an operator gets in this package.
2. **The networking half of Traffic Sync is real, and is now operator-configurable.** `server-configuration.md`
   documents a `replication` block: `trafficLanes` (default `true`; `false` *"keeps the native single GNS lane
   instead of ordered / timed motion / voice lanes"*), `timedMotionWindowMs` (20, 5..100),
   `timedVehicleValidationTicks` (6, 1..30), `timedStarvationShareMs` (50), `contactSteward`, `contactEpisodes`,
   `hitRewindStrict`. This is the changelog's *"Replication rollback options are now exposed as normal server
   configuration"*, and it is the motion-lane work that makes replicated vehicle movement hold up.
   **Caution: `trafficLanes` is network lanes, not cars.** The word "traffic" in these binaries and docs is
   almost always *network* traffic - `MessageTraffic`, `NetEventTraffic`, `TrafficPattern`, `OP77_GNS_TRAFFIC_LANES`.
   It is a false friend and it is how this section went wrong the first time.
3. **The ambient-population bindings are definitely present at `.102`.** `Open77.Server.Scripting.dll` carries
   `SetWorldPopulation`, `GetWorldPopulation`, `CanUseWorldPopulation`, `setRoutingBucketPopulationEnabled`, and
   `Open77.Protocol.dll` carries `TryDecodeWorldPopulationState`. `IDEA-606`'s one-line check is against a lever
   that exists.
4. **The traffic budget is measurable.** `metrics.md` exports `open77_entities{kind}` for vehicles, NPCs, props,
   effects, loot; creation/removal counters; and for vehicles specifically *"owned/unowned, moving, destroyed,
   stale motion, **active simulators, maximum per-simulator vehicle count, AI jobs/states**, authority changes,
   rejected NPC/vehicle motion."* So "how many traffic cars can we afford" stops being a guess the moment anyone
   runs the experiment.

**What the package cannot tell us, and the reason is important:** whether a traffic *Lua API* exists.
`joinTraffic`, `attachDriver`, `driveTo`, `whenReady` and `npcs.speak` appear as plain strings in **no** server
binary - yet all are officially documented and shipping. Binding names are evidently not stored as literals.
**So a string grep cannot prove a Lua API is absent**, and any conclusion of that shape - including the tempting
"there is no `Open77.traffic.*`" - is unsupported. That is the same error as the original BLOCKED verdict in a
new costume, and `KB-162` is amended to say so.

**Incidental find worth carrying, unrelated to traffic.** `state_delivery.lua` is the official Race gamemode's
*"bounded admission cache for complete, recoverable Race display states"*, with `maxEntries` 512, `maxBytes` 8 MB,
an `ordinaryLimit` of 46,000 bytes, per-player dedup, explicit-refresh bypass, and **`maxStreams = 16 -- the
runtime's per-resource cap`**. NCM has just built its own chunked Guide transport after `KB-160`, and this is a
reference implementation of the same problem from the platform's own racing gamemode - including a per-resource
stream cap NCM's streaming does not currently reference. Logged as `IDEA-619`.

### Constraints that survive, and they are real

These are from the same guide and are not superseded by the release:

1. **"There is no headless server physics: without a nearby ready player, no AI moves."** Traffic exists where
   players are. An empty district stays empty regardless.
2. **"Vehicle and route compatibility varies; fleet-scale traffic is not guaranteed."** The platform declines to
   promise density. NCM should treat traffic count as a tuned budget, not a setting.
3. **Each traffic car is a canonical network vehicle**, so it competes for the same entity/replication budget as
   players' cars. This is the real cost, and it is the thing to measure.
4. **AI speed ceiling is 0.5-55 m/s.** This is decision `L8`'s known cap, and it does **not** bite here: 55 m/s
   is 198 km/h, far above any traffic speed. The cap blocks physical AI *racers*, not traffic.
5. Tasks wait for a streamed, compatible client to acknowledge native readiness, and the spawn-settling interval
   applies before simulator election - so traffic populates with a delay, not instantly.

### Ambient population is a separate, still-unpulled lever

Everything below this line was correct and still stands. **`grep` over `ncm/` finds no call to `setPopulation`
or `setPopulationEnabled` anywhere.**

```text
server Open77.world.setPopulation(bucket, { crowd? 0..1, traffic? 0..1, police? boolean })   [world.population]
server Open77.world.getPopulation(bucket)                                                    (ungated)
client Open77.world.population()                                                             [world.query] read-only
server Open77.routingBuckets.setPopulationEnabled(bucket, enabled)
```

Three facts that change how this should be approached:

1. **`crowd` is a true fraction** - applied through the engine's community density modifier.
2. **`traffic` is a switch, not a fraction.** *"2.31 exposes no vehicle density modifier, so it is a switch: any
   value above zero means vanilla traffic. `getPopulation` reports that as `trafficGranularity = "binary"` rather
   than letting a caller assume the fraction was honoured."* **So "lighter traffic" is not available.** It is
   vanilla traffic, or none.
3. **Vanilla traffic is client-local and unsynchronised.** *"The traffic car a player is standing next to was
   spawned by REDengine population on that player's own machine, has no canonical id, and is invisible to every
   other client - which is why `Open77.vehicles.aimed()` answers `unknown_entity` when the player is plainly
   looking at a car."* Two players in one street see **different** traffic. `Open77.vehicles.adopt` exists to
   promote one vanilla car to canonical, but adopting a whole city is not a plan.

**Read this as being about the vanilla-population path only.** Ambient population is available as cheap
*atmosphere* and is not shared world state, so a race through *vanilla* traffic is a race through different
traffic for each driver - a fairness/incident/Tag question rather than a rendering one, and plausibly part of why
earlier attempts disappointed. **It is not an argument against traffic in NCM**, because the shared path above
does not use ambient population at all. The two can also coexist: `crowd` for pedestrians, `traffic = 0` to
suppress the unsynchronized vanilla cars, and server-created `joinTraffic` vehicles for the cars that must be
the same for everyone.

**A documentation conflict to resolve before anyone acts** (`AGENTS.md` warns that preview docs conflict):

- the `setPopulation` **card** says *"A bucket nobody has configured is the vanilla world (`1, 1, true`), not an
  empty one."*
- the **guide** section `server-api#ambient-population` says *"An unconfigured bucket has no ambient crowd, traffic
  or police."*

These cannot both be true. If the card is right, NCM's empty city is caused by **something actively suppressing
population** - the platform's vehicle spawn policy and identity sanitizer are named in the docs as *"two client
mechanisms [that] remove vanilla bodies while a session is active"*, which is the likelier culprit. If the guide is
right, one call fixes it. **The check is one line and read-only:** call `Open77.world.getPopulation(bucket)` on
staging and print it. Do that before designing anything.

**Also worth noting:** `crowd` affects *pedestrians*, which the world graph wants for a different reason entirely -
an authored contact NPC standing on an empty street reads as a bug; standing in a crowd reads as a person.

---

# PART VIII - CREATIVE EXPANSION

Separated by cost. "Cheap" means it reuses a deployed mechanism and adds authored data.

## VIII.1 Cheap / near-term

1. **Widen `from_kind`.** One `ALTER TABLE`. The persistent world gains the ability to speak. Everything below
   depends on it.
2. **Dispatch as a sender, not a menu.** Every existing system notification re-voiced in Dex's recovered register.
   Costs nothing and changes the texture of the whole game.
3. **Wire `player.communication` to the message bus.** Both halves are written; they have never met.
4. **The Fan as its first consumer.** Port `buildSignatureMessage`'s telemetry cascade against NCM Online's
   incidents / Tags / records. The highest emotional return per line of code in this document.
5. **Rico's `driverReason` against real records.** A pure function from driver facts to prose. Port it, replace
   synthetic attributes with authoritative ones, delete `personality`.
6. **Port `voice_harness.lua` into the offline gate.** A voice validator that runs in CI is the only reason seven
   voices stayed distinct in SP, and the gate already runs render checks and 522 core tests.
7. **One lead at session zero.** Dispatch names a market you cannot use yet. The whole world graph in one row.
8. **Every contextual character output also writes a message.** One insert; makes a contextual system re-readable.
9. **`thread_id` as a nullable column.** Group slips; leave receipts alone.
10. **Turn `crowd` on** (after the `getPopulation` check). Pedestrians make authored NPCs legible - an authored
    contact standing on an empty street reads as a bug.
10b. **Put a handful of shared traffic cars on one route.** Server-created vehicles plus `ai.joinTraffic`;
    `world.vehicles` is already declared. Small, reversible, and it is the measurement that tells us what
    density costs before anyone designs around it.
11. **Race Tag to character reaction.** A clean-driving Tag is a *fact*; the Fan and Rico can both cite it.
12. **A sender registry and an action registry.** Two small tables; stops `actions` being free-form JSON forever.

## VIII.2 Moderate

13. **The DCES port.** Retarget the archetype model at places / markets / people. Keep `MAX_ACTIVE_EVENTS`,
    `COOLDOWN_RACE_GAP`, `sentEventKeys` and deterministic actor naming; swap "expiry in races" for a policy that
    works when a player races rarely.
14. **Lead state for markets** (subject to G1). `known` plus `access denied, reason`.
15. **`originates` on traded assets.** Provenance creates leads - the best coupling of the player economy to PvE
    in this document.
16. **The unified race draft with progressive disclosure.** Quinn's defaults plus Foreman's depth, one object, as
    SP already had it. A panel mode, not a new surface.
17. **Ad-hoc slots on existing series routes.** Absolute start, frozen economics, `authorDriverId`. Confines new
    architecture to one event origin.
18. **Direct invitation via `playerInteractions.request`.** The primitive is there; NCM has never called it.
19. **Stu against the real parts stack**, bounded by the Machine Knowledge vocabulary - claims with a basis,
    opinions clearly owned.
20. **Billie, self-paper only**, on scheduled races, with field-derived `podiumFloor` and a per-pair repeat floor.
    No market in humans.
21. **The standing NPC primitive.** One authored contact, one location, prompt -> text -> choices -> consequence.
    Prototype the surface first, because there is one CEF page left.
22. **Objectives/leads as a first-class row.** The real gap in the substrate.
23. **Machine Index leads.** A vehicle you have *heard of* - Machine Knowledge's channel model already permits it.

## VIII.3 Ambitious

24. **The edge table** (VII.4). Authoring becomes writing edges; threads become paths.
25. **Characters as reveal sources, systematically.** Every character's existing output gains an optional
    `reveals` edge. No character learns a new job.
26. **Research identifies origin.** An unknown Part's provenance becomes a research submission; the answer is a
    place. Research is already personal-first and finite (`L169`).
27. **The market network as authored identity.** Operator, district, clientele, specialization, token override
    block - `IDEA-582` already established that a themed market must cost **zero** WebUI surfaces, which makes
    this affordable.
28. **Recurring DCES graduates.** An actor who appears three times and is remembered becomes a named contact.
    Relationships the *world* authored rather than the designer.
29. **Vehicle roster expansion** to 45-65 (`12_CANONICAL_VEHICLE_ROSTER.md`'s own plan), with Machine Index
    partiality as the "there is more" device.
30. **A venue operator layer.** Places with people, so a route has a landlord and posting an ad-hoc race there
    means something.
31. **Audience as a real signal** feeding the Fan's intensity. A named supporter whose volume is earned.
32. **Session isolation by routing bucket** instead of scheduling conflict intelligence.

## VIII.4 Wild but plausible

33. **A journalist who publishes.** A per-server bulletin, authored from real results, written in one voice. The
    data exists; the reader does not yet.
34. **Provenance as narrative.** An asset's custody history is already immutable. A collector who cares *which*
    car this is turns a serial number into a story.
35. **The scrutineer.** A character whose entire job is to state facts you would rather not hear about your own
    configuration. Trivially truthful, because everything they say is `authoritative_specification`.
36. **A historian of the server.** World-firsts and route records already exist; someone who remembers them aloud
    is one authored voice.
37. **A rival who is a real player, named by the world.** Rico already computes head-to-head. Having the *world*
    name your rivalry - to both of you - is a social mechanic no leaderboard achieves.
38. **A market that writes to you.** Once `from_kind` is open, a supplier noticing you bought from them is one
    producer.
39. **An NPC who is only ever somewhere.** No dialogue at all. A person standing at a location, `npcs.speak`
    barking in their own voiceset, whose *presence* is the information. The cheapest possible inhabitant.
40. **Dispatch on a world television.** The presentation audit found a live NCM page can run on a world TV up to
    `cinema.150ft`. A Dispatch board in a garage is set dressing that is also a real surface.
41. **Letters that outlive a season.** A per-kind archive policy means a character's correspondence can be a thing
    you still have in three months, which nothing else in NCM currently is.

---

# GOVERNANCE - three things only the owner can decide

## Status after the owner's ruling, 2026-09-27

| | Question | Ruling |
|---|---|---|
| **G1** | the `???` market roster vs `17_MARKET_NETWORK.md` | **DECIDED - option A. The roster supersedes document 17's prohibition.** Recorded as `L171`; document 17's clause is amended in place, not silently overridden |
| **G2** | where a multi-step race constructor may live | **still OPEN** - owner will return to it |
| **G3** | a market in other humans | **DECIDED - agreed. Self-paper only; Billie never quotes odds on another player.** Recorded as `L172` |

**G1. DECIDED - the roster is approved and supersedes document 17.** `17_MARKET_NETWORK.md` forbade a disclosed
market count, a `???` roster and undiscovered-market slots by name, with a leak rationale. The owner has ruled
that the addendum's working target - one Base Market plus sixteen `???` slots - **supersedes that clause**. The
recommendation in VII.3 was option B; the owner chose **option A**, and this document defers to that.

**What carries over from the clause even though the prohibition is lifted**, because it is engineering rather
than policy: the reason document 17 wrote the ban was *leakage*, and that hazard is unchanged. An undiscovered
slot must not leak its market's identity through ids, sort order, tooltips, payload shape, inventory calls or
row ordering. The count is now deliberately disclosed; **nothing else may be.** `L171` states this as the
condition attached to the ruling.

**The LEAD state is unaffected and still recommended** - it was compatible with document 17 and is compatible
with the roster. A `???` slot that becomes a *named but inaccessible* row is a better reveal than a slot that
flips straight to usable, and it is what makes `IDEA-609` (trade provenance creates leads) land somewhere.

**G2. Where may a multi-step race constructor live?** `competition.venue_options` is an owner ruling (2026-09-21,
amended 2026-09-23): at most five options, every one a final act, no sub-menus, no trees, absent rather than
disabled. A six-step builder cannot live at a world prompt under that ruling. Either the constructor is F6-only
(and the world prompt offers `Race Here` as a single final act with defaults), or the ruling is scoped to venues
specifically. **This is a real constraint, not a preference, and it shapes Part III.**

**G3. DECIDED - no. Self-paper only.** Part IV recommended self-paper indefinitely, with Billie never selling
odds on another player; the owner agreed on 2026-09-27 (`L172`). So Billie ports as: light/standard/heavy on the
player's *own* finish, streak tickets on the player's *own* legs, opponent strength entering only as a
**risk-model input** and never as a price on a person. The SP winner board - `buildWinnerBoard`, the softmax over
`driverThreatScore`, `Back the favorite` / `Back the value` - **does not port**. It stays in the archaeology as a
record of what SP did, and `IDEA-610` is scoped accordingly.

This also disposes of exploit **E7** (collusive odds shaping) by construction rather than by rule, and it removes
the need for the "revisit at >= 6 humans" clause in IV.5's product table.

---

# FEASIBILITY SUMMARY

| Capability | Rung | Note |
|---|---|---|
| persistent, private, actionable message bus | **PROVEN** | deployed; `KB-97` made it private |
| Messages panel mode + F7 + chat twins | **PROVEN** | a `panel.html` mode; keyboard/gamepad navigable |
| message pacing policy + durable exposure | **offline-green, undeployed** | `player.communication`, migration 036, no live PASS |
| character senders | **BLOCKED on one ALTER TABLE** | `from_kind ENUM('team','system','race_control')` |
| one race object, two authoring depths | **PROVEN in SP** | `openQuickRaceConfig` = `openConfig{sourceType="quick_race"}` |
| ad-hoc event with no series | **requires architecture** | `calendar.materialize` is the only event producer |
| direct two-player invitation | **AVAILABLE** | `playerInteractions.request`; never called by NCM |
| nearby-player targeting | **AVAILABLE** | `vehicles.nearby` / `closest`, `players.all`, `world.nearby` |
| authored standing NPC at a location | **AVAILABLE** | 36 + 27 natives; `world.npcs` **already declared** |
| NPC voice without VO | **AVAILABLE** | `npcs.speak` from the NPC's own voiceset; `npcs.voices()` |
| per-player NPC state | **AVAILABLE** | `npcs.setBucket` + routing buckets |
| NPC interaction prompt + dialogue surface | **UNKNOWN - prototype first** | no prompt native found; **one spare CEF page** |
| two players at one NPC | **UNKNOWN** | `isReserved` covers player-to-player only |
| ambient pedestrians | **AVAILABLE** | `crowd` is a true 0..1 fraction |
| ambient *vanilla* traffic | **AVAILABLE but binary, and per-client** | `trafficGranularity = "binary"`; no density control in 2.31; not synchronized |
| **shared** AI traffic | **AVAILABLE** *(corrected - was wrongly called BLOCKED)* | server-created canonical vehicles + `vehicles.ai.joinTraffic` (op77.57), plus the dedicated traffic resource released 2026-09-24. `world.vehicles` already declared |
| shared traffic at scale | **UNKNOWN** | *"fleet-scale traffic is not guaranteed"*; each car is a network vehicle on the same budget as players' cars |
| traffic in an empty district | **BLOCKED** | *"no headless server physics: without a nearby ready player, no AI moves"* |
| why NCM's city is empty | **UNKNOWN - conflicting docs** | card says the default is vanilla; guide says the default is empty. Run `getPopulation` |
| socially-caused discovery with anti-farming | **PROVEN** | `competition.discoveries`, anti-farmed by primary key |
| graded, non-linear knowledge states | **SPEC + partly deployed** | Machine Knowledge channels, migration 033 |
| map pins for leads | **AVAILABLE** | `blips.create` (native Ink geometry from NCM's own SVG), `map.control` declared |
| voice validation in CI | **PROVEN in SP, portable** | `voice_harness.lua` plus its pairwise overlap test |

---

# PLANNING MATERIAL FOR THE MARKET / VEHICLE AUTHORING PASS

**Current vehicle roster: 27 conceptual machines** in `ncm/core/data/vehicle_catalogue.lua` - 26 first-party plus
`Vehicle.v_sport1_rb15_f1` (tagged `mod`) - over 29 pool entries. Manufacturers present: Thorton, Villefort,
Quadra, Herrera, Mizutani, Rayfield, Makigai, Archer, Mahir, Chevillon, Brennan, Yaiba, plus Red Bull Racing
(mod). Identity is `vehicleKey` -> `record` (a TweakDB runtime configuration); **a live OPEN//77 vehicle id is
never accepted as identity**, and manufacturer identity is keyed stably rather than by display name precisely so
that renaming "Chevillon" cannot fork a manufacturer's serial history.

**`12_CANONICAL_VEHICLE_ROSTER.md` is STATUS: SPEC - captured owner intent, explicitly NOT authorised for
implementation.** It already answers the addendum's roster question with a plan (45-65 initially, 80-110 later,
from a ~120-chassis candidate matrix) and already names the hard holes: no second serious Formula chassis, no
modern LMP/LMH/LMDh, no literal GT3/GT4 grid, no modern touring/DTM - with the instruction not to disguise road
cars or body kits as those categories. **A full first-party vehicle audit against the installed game plus Phantom
Liberty was not performed in this pass** and should be its own task; doing it inside this document would have
produced a list without the per-vehicle testing that the SPEC document already says it needs.

**What can vary per market, from what exists:** `marketId`, `display_name`, `kind`, `universally_known`,
`discovery_policy`, `access_policy`; per-market allocation of **real `assetId`s** (not catalogue rows); price;
availability state and time. Supply/production levers are in `economy.supply_profiles` and `economy.production`.
Presentation identity is affordable **only** as a scoped token override block (`IDEA-582`), never a per-market
interface - NCM has one spare CEF surface.

**What requires new architecture for markets:** persistent `player_market_knowledge` rows; a lead state; physical
discovery; map pins for markets; component suppliers; secondary classifieds; buyback/consignment (`IDEA-558`).

**Inventory overlap is explicitly fine**, and the document agrees: markets differ by allocation, price, supply,
specialization, operator and district identity, not by exclusivity.

---

# UNRESOLVED QUESTIONS

1. **G2** - the only governance item still open. G1 and G3 were ruled on 2026-09-27 (`L171`, `L172`).
2. **What is the new traffic feature's actual API?** *Partly answered by the `.102` package, 2026-09-27.* No
   traffic resource ships with the server at `.87` or `.102`; the networking half is real and configurable; the
   population bindings exist. **What remains unknown is whether a traffic Lua API exists at all**, and the
   package cannot answer that, because binding names are not stored as strings (`joinTraffic` is absent from
   every binary while officially documented). The remaining reads are: a devkit index published at `.102`, the
   resource list on the **running** staging server rather than the package, or simply calling
   `Open77.vehicles.ai.joinTraffic` on a test vehicle and seeing what happens.
3. **How many traffic cars can NCM afford?** Now **measurable rather than unknown** - `metrics.md` exports
   per-kind entity counts, active simulators, **maximum per-simulator vehicle count** and AI job states. It
   needs an experiment, not more reading.
3. **Why is NCM's Night City empty?** Two candidate causes, now clearly separable. Conflicting platform docs on
   the unconfigured ambient-population default - run `Open77.world.getPopulation(bucket)` on staging - *and*
   the separate fact that NCM has never created any shared traffic vehicles at all.
3. **The NPC dialogue surface.** One spare CEF page. Can a compact dialogue be a *mode* of `panel.html` without
   the weight of F6, or does it need the last surface?
4. **Two players, one NPC.** Does `playerInteractions` reserve against a non-player actor?
5. **What permission does `playerInteractions.request` need?** The card lists none; confirm against the deployed
   build (op77.102) rather than the index (op77.78).
6. **Does an NPC survive a resource restart?** Ids will differ; nothing may persist an NPC id as identity.
7. **Head-to-head and rivalry:** derivable from results, but should they be *stored*? Rico wants them cheap.
8. **Streak legs in ineligible races** - skip or fail? Part IV proposes skip; it is a real balance choice.
9. **`podiumFloor` derivation** from human field size - the formula in IV.6 is reasoned, not tuned.
10. **DCES expiry in a persistent world.** "Three races" is a good unit for a career and a bad one for a player
    who races twice a month.
11. **One Fan, or an audience?** Deliberately left open.
12. **Does the vehicle spawn policy / identity sanitizer suppress traffic?** Named in platform docs as removing
    vanilla bodies during a session; not investigated here.
13. **Full first-party vehicle audit** against installed 2077 plus Phantom Liberty - deliberately not attempted;
    see above.

---

# WHAT WAS NOT DONE

No production behaviour was changed. No code was written. No phone port, no Messages rewrite, no gambling, no
spontaneous races, no new contacts, no dialogue rewritten, no architectural change. Nothing was measured
in-engine. No multiplayer experiment was run. The three governance items were logged, not resolved.

# NEXT ACTION

**G1 and G3 are answered; G2 is not.** Revised, in order:

1. **Run the traffic experiment instead of reading about it.** The `.102` package (inspected 2026-09-27) shows
   the population bindings exist, the replication/motion-lane work is real and configurable, and
   `metrics.md` exports per-kind entity counts, active simulators, **max per-simulator vehicle count** and AI job
   states. Create a handful of server vehicles on one route, `attachDriver` + `joinTraffic`, and read the
   metrics. That answers both "does the API work on this build" and "what does density cost" in one pass, and no
   amount of further document archaeology will.
2. **Print `Open77.world.getPopulation(bucket)` on staging.** One line; settles the ambient-population
   documentation conflict, which is a separate question from (1).
3. **Answer G2**, because it decides the surface for `IDEA-602` / `IDEA-603` and nothing about spontaneous racing
   can be designed around it until then.
4. **Prototype the NPC dialogue surface** against the one remaining CEF page.

Market authoring is **unblocked** by `L171` and can proceed in parallel, subject to the leak conditions attached
to that ruling.
