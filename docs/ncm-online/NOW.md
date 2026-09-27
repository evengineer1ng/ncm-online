# NOW - the single next-action index

> **STATUS: LEDGER** - living session memory, rewritten at the end of every working session.
> Authority map: [INDEX.md](INDEX.md) - classified 2026-09-24 (L125).

Last rewritten: **2026-09-27 - The broad Economy v1 vertical is built locally and offline-green (`L169`,
`IDEA-564`-`IDEA-567`), not deployed.** It includes migration 035; authored Street/GT/Hypercar/NCX economics;
one centralized host money service; paid event check-in; atomic solo/contested settlement and refunds; itemized
statements; Race Tag evaluation and capped clean-driving bounties; explicit personal-first Research submissions;
and once-only rewards for the three existing unique accomplishments. Fuel, generalized player trade, Research
contracts/world-first calls and tiered Badges remain unbuilt. Lap ghosts, Parts and Machine Knowledge remain on
the previously deployed Online tree with their live test sections still owed.

> **Claim before writing:** decisions through **L169**; MASTER_TEST through **§BJ**; next QA letter **§BK**.
> BACKLOG next free **IDEA-595**; known issues through **KB-159**. Read ledger tails before allocating.
>
> The next-free guard matters: overlapping 2026-09-26/27 sessions previously made this block stale several
> times (`IDEA-380`). The docs gate asserts ID uniqueness and the BACKLOG next-free line.

## One next action

**Run a time trial twice, then run MASTER_TEST §BJ.**

**Ghosts first, because the last attempt found a defect rather than a result.** The owner ran a time trial on
the cut at 16:41 UTC and saw nothing (`KB-156`): a race session record carried `routeName` but never `routeId`,
so every time trial was unkeyable -- the client refused the session, recorded no poses, and prefetched nothing,
while the host claimed with an empty route. `ghost_lap` was confirmed empty, so nothing was mis-stored. Fixed
and redeployed 16:55 UTC; both ends now name the missing key instead of failing silently. Read the server line
first: `time trial ghost invited ... route=<a real id>`, never `route=nil`. **Two runs are needed** -- the first
stores the ghost, the second is the first one that can show it. Then §BI2: find out whether it draws as a car.

**Economy v1 is ON ONLINE, not only local.** Migration 035 applied at 16:55 UTC in the same deploy that carried
the `KB-156` fix, because `deploy-staging.ps1` ships the working tree rather than a selected change. The owner
accepted that promotion. So §BJ runs against Online: confirm boot, then starter balance, paid/denied/duplicate
check-in, solo and contested settlement, qualifying-without-payout, clean and dirty Tags, repeat floor,
abort/restart refunds, unique-Badge rewards and explicit Research submissions, reconciling receipts, typed
ledger rows and balances in SQL.

The rest of the live queue is not displaced: §BH for Machine Knowledge, §AZ for Parts, plus twice-applied
migration dry-runs for 033-035 when `NCM_DB_ROOT` is available.

## Economy v1 - deployed to Online 2026-09-27 16:55 UTC (`L168`, `L169`, document 40)

- Launch now has a genuine one-human income loop. A scheduled field of one uses time-trial completion/target
  economics and never receives P1; fields of two or more use contested completion, placement and field bonuses.
- Free practice and qualifying mint nothing. Scheduled paid events freeze their authored economics, charge at
  check-in, and settle through one idempotent transactional service with itemized receipts.
- Street begins at €$50 entry, €$250 solo completion and €$300 contested completion. GT and Hypercar use authored
  10× and 100× scales; NCX is sponsor-funded with free entry. All numbers remain observable tuning data.
- Repeating the same route/economy opportunity in its window receives the authored repeat floor instead of an
  unlimited first-completion payment. DNF/DNS/DSQ receive no purse.
- Race Tags are factual first: the runtime evaluator emits all qualified facts separately from its capped display
  set. Settlement consumes only an authored allow-list and cap; initial money rewards clean driving, not negative,
  contact, penalty, placement-duplicate or position-manipulation Tags.
- `/ncm.research` lists and submits finite personal-first physical identity and server-measured capability
  evidence. Catalogue exposure and incremental maxima/configuration revisions cannot farm money.
- Existing first-finish, first-time-trial and first-win accomplishments pay €$100 / €$100 / €$300 exactly once,
  after progression persists. The five-tier Badge reducer is not built.
- Cars and serialized Parts remain the principal progression sinks. Player trade will redistribute existing
  assets/value; fuel should follow measured event economics and retain a bankruptcy road back.

## Presentation capability audit - 2026-09-27, reconnaissance only (`IDEA-568`-`IDEA-581`, `KB-157`, `KB-158`)

A second, read-only UI/UX investigation ran alongside the live queue and **changed no production behaviour**. It
asks what NCM can *paint with*, not what NCM should *say* — a separate player-visibility audit owns the second
question. Full document: [docs/research/open77/PRESENTATION_CAPABILITY_AUDIT.md](../research/open77/PRESENTATION_CAPABILITY_AUDIT.md),
prototypes in `docs/research/open77/prototypes/`. **Nothing in it was measured in-engine**, so nothing in it is a
live PASS; the proof ladder used is PROVEN (in-tree shipping code) / AVAILABLE / PLAUSIBLE / BLOCKED.

- **NCM is off the platform design system and did not know it.** `open77-ui.css` is a documented token contract
  shipped byte-identical in 11 OPEN//77 resources; NCM ships no copy and re-derived a divergent subset. Consequence
  already visible in source: `panel.html` renders in Bahnschrift Condensed and `nameplates.css` in Arial Narrow,
  because no resource bundles a font and `"Rajdhani"` never resolves in-game (`KB-157`).
- **The binding constraint is eight CEF surfaces per resource, and NCM can already hold seven** — three of them
  invisible 16×16 pages used as transport to the local Carrier. One spare. This governs every future NCM surface.
- **Two latent z-index collisions** on layer `hud`: NCM venue at z720 against the notification toasts, NCM race HUD
  at z730 against `open77_admin`. Not observed misdrawing; logged so it is not rediscovered as a mystery (`KB-158`).
- **NCM is silent and still.** No `sfx`/`vfx`/`effects`/music call anywhere in `ncm/`, zero `@keyframes` in every
  page. The platform proves the exact vanilla race cues by name (`sq024_race_*`, `ui_jingle_quest_*`,
  `ui_menu_onpress`) and 38 keyframe animations in-engine. `Open77.sfx.play2d` takes no quota and no handle.
- **Bigger than expected, and unused:** NCM's own SVG glyphs can be drawn as **native Ink geometry inside the
  vanilla map** via `blips.create{icon=…}`; `Open77.anchors` generalises the per-frame projection NCM already ships
  for Driver Cards; a live NCM page can run on a world television up to `cinema.150ft`; and a curated racing kit
  already exists (`race.firework.burst`, `race.checkpoint`, `race.route_arrow`, `street.traffic_light`, `barrier.*`).
- **Delivery is nearer than the record suggested.** Per `35_REQUIREDMODS_FORENSIC_AUDIT.md`, `Unverifiable` meant the
  launcher discarded a non-loopback plain-`http:` URL — HTTPS is the fix — so client-component techniques (liveries,
  sky holograms, a bundled webfont) are reachable engineering rather than fantasy.

Nothing here displaces the live queue above. The cheapest items are additive and reversible: the token file
(`IDEA-568`), an audio vocabulary (`IDEA-571`), separating the two z-indices (`KB-158`), and declaring
`ui.vanilla.hud` (`IDEA-576`). No decision was taken, so `DECISION_RECORD.md` is unchanged.

**Addendums A-C, added the same day at owner request** (`IDEA-582`-`IDEA-586`): market presentation identity as a
scoped **token override block** rather than a per-market interface — which is the only affordable shape, because a
themed market must cost **zero** WebUI surfaces; the themeable/never-themeable boundary, where the shell, the money
figure and the legibility floors are never a market's to change; and **Player Banners, which already exist in
embryo** — `driver.presentation` ships the registry, `theme` field, entitlement *reason*, validated selection,
persistence, public projection and renderer, and lacks only an earning path, so the delta is one write-once
`banner_grant` table plus a second input to `M.entitlements()`. Banner format is already fixed by the renderer:
206×84 ≈ 2.45:1 at opacity 0.72 under text, so a banner is **a wash, not a picture**. Addendum C codifies the
communication register the repository already writes in. Prototype:
`docs/research/open77/prototypes/market-identity-and-banners.html`.

## Visibility/communication work in progress - NOT mine, and now green again

The working tree carries an **unfinished player-visibility implementation** from a concurrent session that stopped
mid-flight: `core/player/communication.lua` (+ 7 core tests), `ncm_league/server/communication.lua`,
`ncm_league/server/visibility.lua`, migration **036** `player_message_exposure`, the new **DRIVER FILE** shell
surface in `panel.html`, and a tyre readout in `race.html` that now names state, trend and grip cost. It is good
work and it is **uncommitted, undeployed and unfinished** — migration 036 has had no twice-applied dry-run, and
nothing in it has a live PASS.

**It left the gate red; the gate is green again.** Both failures were stale harness expectations, not defects:
`tools/panel-render-check.js` asserted an exact five-entry shell nav and the shell now has six (DRIVER FILE), and
`tools/race-render-check.js` asserted the old tyre copy `"OK"`/`"-15%"` where the readout now says
`"FULL GRIP"`/`"-15% GRIP"`. Both guards were **updated to the new intent rather than loosened**, and the new
behaviour gained cover: the driver panel is now itself checked for the full nav, and the tyre state word and trend
arrow are asserted. Panel **131** assertions (was 129), race **50** (was 46), both 0 bad; whole gate ALL GREEN
under both interpreters, including that session's 7 communication tests.

Anyone resuming that work should read `visibility.lua` first — its `currentCommitment()` copy is the clearest
statement of NCM's voice in the repository, and `IDEA-586` codifies it.

**`KB-159`, found while integrating and worth knowing about:** `player/communication.lua` was in `MANIFEST.lua`
but had **never been vendored** — `tools/ncm-build.ps1` had not been run — so it was missing from both
resources' `shared/core/` and from their generated `shared_script` lists. `NcmCore.get` **raises** on an unknown
module and `ncm_league/server/communication.lua` calls it at file scope, so `ncm_league` would have failed to
start on deploy. Fixed by running the build. **Run `tools\ncm-build.ps1` after touching `MANIFEST.lua`, every
time** — and `IDEA-594` proposes the gate assert it instead of relying on memory.

## Input accessibility and the Session Landing Panel - BUILT 2026-09-27, live input test owed (`IDEA-587`-`IDEA-594`)

Owner implementation request, delivered. Full recon, design and honest test limits are Addendum D of
[docs/research/open77/PRESENTATION_CAPABILITY_AUDIT.md](../research/open77/PRESENTATION_CAPABILITY_AUDIT.md).

- **Every NCM panel mode is now keyboard- and gamepad-navigable**, from one focus-scope push in `panel.html`'s
  `show()` rather than surface by surface: Guide, Market, Machine Index, Driver File, Help, Wheel, Questionnaire,
  Inbox and the new Landing panel. The race HUD and Driver Cards stay passive and take no focus, which is right.
- **A CEF page cannot see a gamepad.** So `client/nav_input.lua` reads the pad (`Open77.input.isDown`/`axis`),
  turns it into semantic actions, and sends those to `web/ncm-nav.js`, which never mentions a button.
- **Pad BACK is authoritative in Lua and does not wait for the page** — the direct extension of `KB-61`, where
  both exits ran through the page and a player had to kill the game. Escape stays owned by `panel.html`.
- **The Landing Panel is a mode of the existing page, not a new surface**, because NCM holds seven of eight
  (`IDEA-570`). Content is authored data in `client/landing_content.lua`, validated by `core/player/landing.lua`;
  a `partial` capability is refused unless it states its limit. Chat twins `/ncm.whatsnew` and `/ncm.alpha`;
  `/ncm.input` prints every pad control and axis for the first live session.
- **Offline evidence:** 522 core tests (+12 landing), panel render **148** (was 131), a new
  `nav-render-check.js` at **33** assertions, 226 resource files, whole gate ALL GREEN under both interpreters.
  The nav harness **caught a real bug on its first run** — a bare half-plane test treated a control 700 px below
  as "to the right"; a directional cone fixed it (`IDEA-589`).
- **Not tested, and this is the limit: no gamepad has touched any of it.** Repeat timings and stick thresholds
  are reasoned, not tuned; the §31 mouse-only / keyboard-only / pad-only matrix is owed in full. One known gap:
  hold-to-confirm controls are not yet completable from a pad (`IDEA-593`).

A build string check worth keeping: the devkit MCP publishes cards only to **op77.78** while staging runs
**.102**, so it reports newer natives as "not in any published build". `setConsumedKeys` is one of those, and
reading the installed `Open77.dll` (2026-09-25) shows it **is** present. When the index lags the deployed build,
grep the binary.

## Offline evidence

- Core: **504 passed, 0 failed** under Lua 5.4 and LuaJIT.
- Cross-scope: **51 checked, 0 bad**; QA observer **17 / 0**; vehicle access **35 / 0**.
- `luac -p`: **217 resource files, 0 bad**.
- Render checks: panel **129**, nameplate **26**, race **46**, all green.
- Documentation authority: **76 valid documents, 446 unique ledger IDs**. The final complete repository gate is
  **ALL GREEN under every interpreter** after session-close bookkeeping.

## Still live and unchanged

- Ghosts are deployed PERSONAL BEST only under `L166`; §BI remains awaiting live driving proof, including the
  exact vehicle visual, non-collision, heading seam, penalty time and both practice/time-trial claim paths.
- Machine Knowledge migration 033 and the first typed observation vocabulary are deployed under `L164`; §BH and
  the twice-applied dry-run remain owed. No estimator, envelopes or confidence were added.
- Parts economy/UI v1 is deployed under `L162`-`L163`; §AZ and later performance work remain owed. Economy v1 did
  not change the Carrier's proven three-lever boundary or resolve the brakeScale/drag coupling (`IDEA-538`).
- Useful live commands remain `/ncm.topspeed 40`, `/ncm.ratedtopspeed`, `/ncm.setup power_unit 2.0`,
  `/ncm.setup tires 1.4` and `/ncm.setup brakes 2.0`.
