# NCM server-mod licensing catalog

> **STATUS: LEDGER** - living evidence register for third-party packages considered for NCM-hosted delivery.
> Checked 2026-09-25. This is project risk triage, not legal advice.

## Current answer

Of the first nine vehicle bases selected for NCM's install/test cohort, **zero are cleared for NCM to host and
automatically deliver today**.

- **Seven have a plausible permission path:** RB15, Opel Corsa/Vauxhall Nova, Mizutani Hozuki Widebody,
  Porsche 996 GT3, Lancia Stratos, FZR 3000 and BMW M3 GTR. Their current pages forbid re-uploading the
  package. Written permission is required before NCM serves the bytes. Some also need a dependency or
  real-world-brand issue cleared.
- **Two are off the table for hosted delivery today:** the yellingintothevoid R34 and Formula Drift Supra.
  Their pages both forbid re-upload, limit add-ons to packages that require the original Nexus mod, and say
  that some bundled assets belong to other authors. Permission from the vehicle porter alone would not clear
  the whole package.
- **The shared open-source loader layer is different:** ArchiveXL, TweakXL, RED4ext, redscript, Cyber Engine
  Tweaks, mod_settings, Let There Be Flight and Direct Wheel were already verified as MIT in
  [Report 36](../../ncm-online/36_DRIVEABILITY_MOD_CARRIER_ASSESSMENT.md).
  NCM may redistribute exact compatible builds with the MIT notices preserved. Codeware and every other
  dependency still need their own row before inclusion; do not infer a license from an ecosystem neighbor.

This result is deliberately narrower than "can players use the mod?" A Nexus Collection that points users to
the author's own file, a player-installed prerequisite, and a server-hosted RequiredMods package are three
different acts.

## Classification rule

| Class | Meaning for NCM |
|---|---|
| **HOST NOW** | The exact package/version has an explicit redistribution license or a recorded written grant; all bundled third-party assets and required packages are cleared; notices and source obligations are known. |
| **ASK** | The current terms forbid or do not grant server redistribution, but the named author appears able to grant the missing permission. Nothing is hosted until the grant is recorded against the exact package. |
| **OFF TABLE TODAY** | NCM lacks a complete rights chain, an upstream owner is unidentified/unreachable, the page expressly restricts distribution to another channel, or a hard dependency is uncleared. This is not a claim that clearance is impossible forever. |
| **REFERENCE ONLY** | NCM may link to the original page or publish a clean add-on that contains only NCM-authored files and requires the original, if both the author terms and the platform's player-fetch path allow it. NCM does not serve the base bytes. |

The test is package-specific, not creator-wide. A friendly livery policy does not license a base archive. A
base author's permission does not license a hard dependency. A permissive 3D model does not automatically
license scripts, compiled game data, logos or other bundled art.

OPEN//77's own guide makes the operational boundary explicit: safety and redistribution are separate; when
redistribution is refused, the server cannot host the bytes and the player-fetch route is used instead. See
the preserved [server-mods guide excerpt](evidence/2026-09-19/guide-server-mods-excerpt.md#mods-your-server-requires--redistribution-is-a-separate-axis).

CD PROJEKT RED's current [Fan Content Guideline](https://www.cdprojektred.com/en/fan-content) also requires
fan work to be noncommercial and unofficial, and says permission may be needed from third parties and
real-life brands. Therefore a Nexus permission panel is necessary evidence, not the entire rights analysis.

## Cohort 1 - package verdicts

| Candidate / exact source | Author | Page evidence | Required package issue | Verdict for hosted server delivery |
|---|---|---|---|---|
| [RB15 F1 Car Mod Demo](https://www.nexusmods.com/cyberpunk2077/mods/31543) | ehgudqo | The model-derived portions are CC BY 4.0 from Dave Bored's Sketchfab model. The author's scripts, configuration, vehicle implementation, lighting controller and TweakDB work require prior written permission; the complete package may not be redistributed without it. Compatibility add-ons are allowed only when they require the original and include none of its files. | The model portion has a real license, but the complete archive does not. Red Bull/F1 marks and any game-derived content remain separate. | **ASK** for the exact complete package. **REFERENCE ONLY** for the current NCM livery add-on. Existing ruling `L142` correctly keeps the base and liveries out of public RequiredMods meanwhile. |
| [Nissan Skyline R34 V-Spec II](https://www.nexusmods.com/cyberpunk2077/mods/30450) | yellingintothevoid | No re-upload. Credited modifications/assets are broadly allowed, but author notes restrict published add-ons to Nexus, require the original mod, and require an add-on ZIP to contain only edited files. The page declares third-party assets and lists numerous outside model/part sources. | ArchiveXL/TweakXL are clear; Codeware and any selected optional integrations need separate rows. The many source assets require license-by-license review. | **OFF TABLE TODAY** as a hosted base. **REFERENCE ONLY** for an original NCM livery/add-on that follows the page terms. |
| [Opel Corsa / Vauxhall Nova](https://www.nexusmods.com/cyberpunk2077/mods/13399) | Corsagsti | No re-upload; modification and asset reuse require permission. The page says assets are the author's or free-to-use resources but supplies no separate asset credits. | ArchiveXL is clear. Virtual Car Dealer is not needed for Online and should not be bundled by inference. Real-world Opel/Vauxhall branding remains a separate review item. | **ASK** the author for server redistribution and a short provenance confirmation. |
| [Mizutani Hozuki Widebody](https://www.nexusmods.com/cyberpunk2077/mods/25785) | Oranje3 | No re-upload; modification and asset reuse require permission. Page says assets are author-owned or free-to-use and credits no outside asset owner. | ArchiveXL/TweakXL/RED4ext are clear. CET/VCD are Solo features and should not enter the Online package unless actually required and separately cleared. | **ASK**. This is one of the cleanest first permission targets because it is lore-native and the page presents a single-author/free-resource chain. |
| [Porsche 996 GT3 Mk.1](https://www.nexusmods.com/cyberpunk2077/mods/21727) | SDH0 | No re-upload; modification and asset reuse require permission. Page says assets are author-owned or free-to-use and gives no outside file credit. | Hard-depends on [SDH0's Vehicle Resources](https://www.nexusmods.com/cyberpunk2077/mods/20956), whose page carries the same no-reupload/permission-required terms. Porsche branding remains separate. | **ASK SDH0 for both packages in one written grant.** Not cleared if only the car is granted. |
| [Lancia Stratos HF](https://www.nexusmods.com/cyberpunk2077/mods/14030) | SDH0 | No re-upload; modification and asset reuse require permission. Page says assets are author-owned or free-to-use and gives no outside file credit. | Its listed framework dependencies include MIT loaders; VCD is not needed for Online. Confirm whether the tested build also requires Vehicle Resources. Lancia branding remains separate. | **ASK SDH0**, with the exact dependency set and tested archive named in the request. |
| [Toyota Supra Mk4 Formula Drift](https://www.nexusmods.com/cyberpunk2077/mods/22469) | yellingintothevoid | No re-upload. Author notes allow Nexus add-ons that require the original and contain only edited files. The page declares third-party assets; even where individual livery elements have permissive terms, that does not clear the whole vehicle archive. | ArchiveXL/TweakXL are clear; Codeware needs its own recorded row. Toyota/Formula Drift branding and the unidentified parts of the asset chain remain separate. | **OFF TABLE TODAY** as a hosted base. **REFERENCE ONLY** for a compliant NCM-authored add-on. |
| [FZR 3000 Street Racer](https://www.nexusmods.com/cyberpunk2077/mods/26783) | Oranje3 | No re-upload; modification and asset reuse require permission. Page says assets are author-owned or free-to-use and supplies no outside credit. | Hard-depends on [Bikes of the Dark Future - Arch V4](https://www.nexusmods.com/cyberpunk2077/mods/18736). That dependency's current permission panel has not yet been captured. | Base is **ASK**; the complete runnable chain is **OFF TABLE TODAY** until Arch V4 is independently cleared. |
| ['01 BMW M3 GTR Most Wanted](https://www.nexusmods.com/cyberpunk2077/mods/9871) | ctxrlsec | No re-upload; modification and asset reuse require permission. Page says assets are author-owned or free-to-use and gives no outside file credit. | ArchiveXL/TweakXL are clear. Material and Texture Override and Vehicle Manufacturers Resource need rows if the Online build truly requires them. BMW/Need for Speed-inspired branding and livery remain separate. | **ASK** for the base package and provenance. A clean NCM livery package is not permission to rehost the base. |

### Cohort accounting

| Result | Vehicle bases | Count |
|---|---|---:|
| HOST NOW | none | 0 |
| ASK | RB15; Opel/Vauxhall; Hozuki; Porsche 996; Stratos; FZR base; BMW M3 GTR | 7 |
| OFF TABLE TODAY | R34; Formula Drift Supra | 2 |

FZR's runnable chain is red despite its base being yellow because Arch V4 is unresolved. The Porsche chain is
yellow only if SDH0 grants both the vehicle and Vehicle Resources.

## Known hostable infrastructure

These are not vehicle approvals. They are the already-verified lower layer that does not need to be
re-litigated for every car.

| Package | License / basis | Hosting condition |
|---|---|---|
| NCM Carrier and wholly NCM-authored RequiredMods payloads | NCM-owned source | **HOST NOW** after the package manifest proves no uncleared third-party bytes are included. |
| ArchiveXL | MIT | Preserve the MIT notice and exact upstream attribution. |
| TweakXL | MIT | Preserve the MIT notice and exact upstream attribution. |
| RED4ext | MIT | Preserve the MIT notice and exact upstream attribution. |
| redscript | MIT | Preserve the MIT notice and exact upstream attribution. |
| Cyber Engine Tweaks | MIT | Preserve the MIT notice and exact upstream attribution. |
| mod_settings | MIT | Preserve the MIT notice; identify any patched build. |
| Let There Be Flight | MIT | Preserve the MIT notice if any forked material is distributed. |
| Direct Wheel / cp2077-wheel-mod | MIT | Preserve Grant Perdue's notice; do not bundle Logitech SDK material whose vendor terms do not permit it. |

The source and verification date for this table are preserved in
[Report 36 section 7](../../ncm-online/36_DRIVEABILITY_MOD_CARRIER_ASSESSMENT.md).

## Permission request must cover

A casual "sure" is not enough for a package gate. Preserve the reply and record:

1. Exact Nexus mod, file/version and hash NCM wants to serve.
2. Permission for NCM to **host the package on its own HTTPS server and automatically deliver it to players
   who join an OPEN//77 world**. Do not describe this merely as "using it in a collection."
3. Whether the grant covers an unmodified archive, NCM's documented inert subset, or both.
4. Noncommercial use, no paywall/resale and the intended attribution text/link.
5. Whether updated versions are covered automatically or require a new approval.
6. Confirmation that the author can grant redistribution rights for every bundled model, texture, sound,
   logo and code file, plus a list of exceptions that need separate permission.
7. Every hard dependency that must be distributed with it. Each dependency still receives its own catalog row.
8. A revocation/update contact and the operational response: withdraw the package, preserve local research,
   and prevent new joins from receiving it.

## Next audit batches

1. Resolve the FZR chain: Arch V4 exact permissions and whether an inert FZR subset can function without its
   executable/garage pieces.
2. Capture Codeware, Material and Texture Override, Vehicle Manufacturers Resource and any other hard cohort
   dependency not already in the MIT table.
3. Audit the lore-native Oranje3 family first. It is the most promising route to a legally simpler server
   fleet and avoids multiplying real-world manufacturer questions.
4. Audit SDH0 as one negotiated ecosystem: Vehicle Resources plus a named vehicle/version list, rather than
   asking the same author thirty disconnected questions.
5. Keep yellingintothevoid cars in the player-fetch/reference lane unless the complete third-party asset
   chain is supplied. Their livery friendliness is valuable, but it is not a base-package license.
6. Audit the surrounding gameplay stack separately (Virtual Car Dealer, Car Modification Shop, persistence,
   physics and camera mods). Technical compatibility and server redistribution are independent fields.

## Evidence notes

- Permission panels and author notes were read from the exact Nexus pages linked above on 2026-09-25.
- The candidate names and cohort came from the user-supplied `NCM Collection - Candidate Matrix` research pool;
  ambiguous vehicle names outside Cohort 1 remain unclassified until an exact page and author are attached.
- OPEN//77 platform behavior and the distinction between hosting and player-fetch are preserved in the local
  guide excerpt linked above.
- NCM's own published custom Nexus permissions remain summarized in
  [NCM_ARCHITECTURE.md](NCM_ARCHITECTURE.md#published-permissions-verified); they do not flow downstream to
  third-party cars or dependencies.
