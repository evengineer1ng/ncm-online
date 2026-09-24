# Adjacent racing projects

Checked 2026-09-18 against creator-published pages. This is a focused landscape sample, not an exhaustive census or runtime comparison. No third-party implementation/assets were copied. Compatibility suggestions below are proposals requiring source/permission review and testing.

| Project / primary source | Publicly demonstrated or described strength | Concrete lesson or interoperability question for NCM |
|---|---|---|
| [CyberTrials](https://www.nexusmods.com/cyberpunk2077/mods/16094), page version 2.31, updated 2025-10-22 | Time trials, in-game course authoring/sharing, sample tracks and native map/start interaction. Exported tracks require restart/reload; last-mounted-car selection shapes entry flow | Give route authors a complete capture/validate/export/test loop. Examine the documented `timeTrials.raceActive` integration surface before adding mutual activity exclusion; do not assume event/schema compatibility. Public reuse restrictions require permission before copying implementation/assets |
| [Gran Choomismo](https://www.nexusmods.com/cyberpunk2077/mods/16150?tab=description) and [CyberTrials custom tracks](https://www.nexusmods.com/cyberpunk2077/mods/16097) | A route-pack ecosystem beyond the base timer. Gran Choomismo's changelog emphasizes readable checkpoint placement ahead of turns | Make course quality an acceptance gate, not just valid coordinates. NCM root metadata could export to another schema, but authored courses remain separately licensed content; do not bundle them by inference |
| [NCGT](https://www.nexusmods.com/cyberpunk2077/mods/31730), updated 2026-09-10; header 21j versus changelog 2.8.4 | Broad handling/traction/weather/terrain simulation, per-vehicle tuning, live RPM/gear feedback and specialized shops; advertises performance batching and Authentic Shift dependency | Evaluate a coherent build/tuning screen and measured handling feedback. Its standalone handling/shop scope conflicts with casually stacking NCM TweakDB modifications. Prototype one owner for physical handling and exchange only validated build/class metadata; current interoperability is unverified |
| [It's Race Time](https://www.nexusmods.com/cyberpunk2077/mods/31602), version 1, 2026-07-15 | Focused native racing-AI adjustment with Native Settings or a small settings file; exposes forward-target/minimum/maximum-distance controls affecting pace/waiting | Target selection and rubberband behavior deserve controlled comparative tests in single player. Public settings do not establish compatibility with NCM custom spawned AI or OPEN//77 leased AI; no native code port claim is made |
| [ShaderDrift](https://www.nexusmods.com/cyberpunk2077/mods/16279), version 0.9.0, updated 2026-02-12 | Burnout entry, angle/speed drift scoring, combos, collision consequences, contextual feedback, saved runs and filtered club history. Explicit coexistence behavior with CyberTrials and flight/autodrive mods | Good model for discoverable discipline-specific entry and immediate scoring feedback. NCM could support a drift ruleset and activity-exclusion contract. Online scoring would need trustworthy angle/input/contact observations; a client-reported score alone is insufficient |

## Where NCM is differentiated

Local code supports the combination of persistent seeded competitors, population advancement, season standings, live and off-screen results, box scores, management, recurring contacts, parts and progression. That integrated league/career ecosystem is a different contribution from a course timer, a handling overhaul or an AI-distance tweak. This conclusion comes from NCM execution paths in [NCM_ARCHITECTURE.md](NCM_ARCHITECTURE.md); it is not a claim that other projects lack every comparable feature.

The most useful borrowed ideas are a visible authoring loop, clear checkpoint placement, purpose-built feedback, readable history filters, explicit race-activity ownership and a single physical-handling authority. None requires preserving NCM's existing UI or copying another project's code.

## Follow-up priority

1. Improve NCM's first-race discovery and route-author workflow before adding more feature names to public documentation.
2. Specify an optional single-player activity-status adapter so other racing/drift mods can avoid overlapping starts. Verify each actual exported contract first.
3. Compare AI target/pace behavior on one controlled NCM course; do not equate vanilla quest AI with NCM or OPEN//77 AI.
4. Test tuning ownership with a minimal mod stack if NCGT interoperability becomes a product requirement.

Status: bounded public-feature review complete. Source-level adjacent-mod analysis and compatibility tests are deferred; they are not prerequisites to the initial OPEN//77 human-race prototype.
