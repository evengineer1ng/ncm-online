# RequiredMods forensic audit - existing RB15 and NCM livery packages

> **STATUS: PROPOSAL** - forensic finding and Development acceptance plan; no Production change authorised.
> Authority map: [INDEX.md](INDEX.md). Operational state remains governed by
> [OPS_STAGING.md](OPS_STAGING.md); live evidence remains governed by
> [wp/MASTER_TEST.md](wp/MASTER_TEST.md).

Date: **2026-09-25**. Scope: the existing `rb15-f1-inert-v10` and `ncm-rb15-liveries` artifacts, their
ArchiveXL/TweakXL dependencies, the OPEN//77 RequiredMods resolver, and the exact `Unverifiable` failure.
No dummy package was created. No package was rebuilt. No game file, server configuration, deployment or
Production process was changed.

## Executive finding

The old conclusion was wrong in one crucial respect: `Unverifiable` did **not** mean awaiting review, unknown
attestation, an unsupported package class, or a collision with the manually installed RB15. It meant the
launcher had no usable URL.

Both launcher `2.31.13+op77.89` (the build that produced the retained failure log) and the current official
`2.31.13+op77.100` implement this sequence:

1. `MasterClient.Sanitize` passes each hosted URL through `CatalogUrls.ModBlob`.
2. `ModBlob` returns null for every `http:` URL whose host is not loopback. HTTPS and loopback HTTP survive.
3. NCM advertised `http://52.60.225.137:11779/...` in Online and currently advertises
   `http://<lan-host>:11779/...` in Development.
4. After the player accepts the unsecured warning, `WorldRequirement.Resolve` sees a blank URL and returns
   `WorldModRefusalKind.Unverifiable`: the world did not say where/how large the package was.
5. The generic UI/log collapses that to “requires mods that cannot be installed.” No HTTP request occurs.

This is deterministic and affects **every hosted package in the set**, inert or executable. `unsecured=true`
lifts only the unreviewed-executable capability cap; it cannot restore a URL discarded earlier. Review status
is irrelevant to this branch.

The package declarations, active staged bytes, archive layouts, roots, sizes and hashes are clean. The smallest
same-PC Development correction is to advertise `http://127.0.0.1:11779/`, which the launcher explicitly permits;
the smallest public/remote-client correction is to serve the resource/mod endpoint through HTTPS. Build alignment
is also required before the public retest because Online server `.87`, the running launcher `.89`, and the current
supported builds have diverged. The final in-game acceptance is **not yet run**: it requires launcher consent and
in-game observation, the UI is not available to this audit environment, and the owner expressly prohibited a
Production deployment/restart in this task.

## A. Current documented contract

The current official [Required mods guide](https://open2077.net/docs/server-mods) and
[mods guide](https://open2077.net/docs/mods) say:

- A hosted package is identified by `id`, exact `version`, `sha256`, archive `sizeBytes`, and a server-provided
  URL. Indexed and hosted declaration shapes do not mix.
- On Connect, the launcher obtains attestations, applies content policy, asks for consent, downloads missing
  bytes, hashes them, inspects roots, projects a per-world layer, then boots the game with the world digest.
- Unverified inert packages are warned, not blocked. On an unsecured world, explicit player consent also lifts
  the unreviewed-executable cap. `blocked`, redistribution refusal, a missing indexed ID, bad hash, traversal,
  unknown root, malformed declaration or other structural refusal still wins.
- The world layer is separate from Solo. Removal re-derives the layer; cached blobs may remain.

Current `.100` code agrees with that policy. `WorldRequirement.Resolve` assigns missing attestation
`ModSafety.Unknown`, places unknown inert packages in `Unverified`, and accepts unknown executable packages only
when unsecured consent supplies `allowUnverifiedExecutable=true`. `MasterClient.AttestModsAsync` uses
`POST api/v1/mods/attest`; current replies for all four NCM/test hashes are `safety=unknown`,
`redistribution=unknown`, not blocked/refused.

One current documentation/implementation contradiction remains: the guides show public hosting as
`GET http://<host>:<resource-port>/mods/v1/blobs/<sha256>` and the reference repeats an HTTP URL, but `.89` and
`.100` refuse all non-loopback HTTP mod URLs before resolution. The launcher does not name this security rule;
it converts the URL to null and reports `Unverifiable`. That is a platform documentation and diagnostic defect,
even though NCM can safely correct its own endpoint by using HTTPS.

## B. Actual NCM package state

### Active declarations and blobs

| Package | Declaration | Active archive | Warden classification |
|---|---|---|---|
| RB15 | hosted; `rb15-f1-inert-v10`; `10.0.0` | 38,537,004 bytes; `d597ceb456f4d1c3b843d0f7e4fe691ba8328524d8634f5f596da8e4405f8e39` | inert; 7 files; roots `archive/pc/mod`, `r6/tweaks` |
| NCM liveries | hosted; `ncm-rb15-liveries`; `1.0.0` | 7,829,853 bytes; `d1fe9bd0ad1b2c8d6a4d9cfc73327660c4d8ec3386391d3d39b387940b0840f9` | inert; 3 files; same roots |

The local declaration and live parked declaration name the same versions, sizes and hashes. The server store
contains exact matching blobs. An older repository artifact,
`tools/open77/mods/ncm_rb15_liveries_20260919-1026.zip`, is 5,382,498 bytes with hash
`53443d82f285c3002c89d2cabf03b452bc287e26639c4730f97e82d083d2eb3b`; it is **not** the declared/staged
livery artifact. That provenance drift is not the refusal cause, but future custody must name artifacts by
hash rather than by a nearby filename.

### Archive trees and destination map

All paths are game-root relative and map directly to permitted world-mod roots. There is no wrapper directory,
traversal, unsupported root, duplicate destination between packages, executable/script file, or ERS component.

| Package | Package-relative path | Intended/projected Cyberpunk path | Class |
|---|---|---|---|
| RB15 | `archive/pc/mod/fable5.archive` | same | inert archive |
| RB15 | `archive/pc/mod/fable5.archive.xl` | same | inert ArchiveXL descriptor |
| RB15 | `r6/tweaks/rb15_f1_standalone.yaml` | same | inert tweak |
| RB15 | `r6/tweaks/rb15_f1_ui.yaml` | same | inert tweak |
| RB15 | `r6/tweaks/rb15_f1_virtual_car_dealer.yaml` | same | inert tweak |
| RB15 | `r6/tweaks/zz_rb15_f1_performance.yaml` | same | inert tweak |
| RB15 | `r6/tweaks/zzz_rb15_f1_realistic_race_trim.yaml` | same | inert tweak |
| liveries | `archive/pc/mod/ncm_rb15_liveries.archive` | same | inert archive |
| liveries | `archive/pc/mod/ncm_rb15_liveries.archive.xl` | same | inert ArchiveXL descriptor |
| liveries | `r6/tweaks/ncm_rb15_liveries.yaml` | same | inert tweak |

Both packages require ArchiveXL and TweakXL at runtime but do not themselves declare dependency metadata.
The old signed stable index (generations 58 and 61, six packages) did not contain `archivexl` or `tweakxl`, so
the old indexed declarations correctly returned `NotInIndex`. Current official worlds demonstrate a working
alternative: the official Freeroam/Unstable catalogue advertises hosted `archivexl-assets` and
`tweakxl-assets` over HTTPS on an unsecured world. The exact older loader hashes already retained in NCM's live
store are also the hashes currently advertised by the official world:

- ArchiveXL 1.27.1: 1,037,774 bytes,
  `608b7b2fed4c35751cd264a87dcfe9d9074fb6d48458d29bde955f1c03dc0d5c`.
- TweakXL 1.11.4: 1,046,349 bytes,
  `13033a1f10cb1dbfa534964b22e3405aa33e8f29145f17164d318b021402883f`.

This does not waive upstream redistribution terms. The acceptance run must use the platform's loader resources
or already-authorised exact hosted packages, not invent another custody path.

### Served bytes

With local RequiredMods enabled, independent GETs of both real resource URLs returned 200, no redirect,
`application/octet-stream`, immutable cache headers and ETag equal to the hash. Full downloads matched the
declared sizes and SHA-256 values; Range returned 206. The manifest carried the same declarations and digest.
No authentication or transformation altered the bytes.

The live endpoint is currently parked: `GET /mods/v1/manifest` returns 200 with `enabled=false` and the empty-set
digest; blob GETs return 404. That is correct current behavior, not evidence against the earlier transport.

## C. Failure pipeline

The retained `.89` launcher log proves this order on 2026-09-22:

1. The server row was received with `unsecured=true`.
2. First Connect paused for unsecured consent.
3. After acceptance, the launcher logged `capability cap lifted ... unreviewed executable packages will be
   accepted`.
4. It immediately refused both real packages as `Unverifiable`.
5. No blob GET, store insertion, archive inspection, root classification, collision plan, projection, game boot
   or loader initialization followed.

The exact `.89` and `.100` code path is:

```text
catalogue requiredMods[].url
  -> MasterClient.Sanitize
  -> CatalogUrls.ModBlob
       public HTTP => null
  -> unsecured consent accepted
  -> WorldRequirement.Resolve
       blank url => Unverifiable
  -> generic “cannot be installed” UI
```

For the two NCM packages, failure therefore occurred **after consent and before download**. For old indexed
ArchiveXL/TweakXL declarations, failure occurred at index lookup (`NotInIndex`). When those loaders were changed
to hosted public-HTTP declarations, they followed the same URL-null/`Unverifiable` branch as the NCM packages.

## D. Hypothesis matrix

| Candidate cause | Evidence/test | Result | Status |
|---|---|---|---|
| Awaiting review / unknown attestation | Resolver source inspected; live attestation endpoint queried for all four hashes | Unknown is warn/consent, not `Unverifiable`; none is blocked/refused | **ELIMINATED** |
| Unsecured flag or consent did not propagate | Historic log records pause, explicit acceptance and capability-lift line before refusal | Capability lift reached resolver | **ELIMINATED** |
| Public HTTP URL rejected | Live config is `http://52.60.225.137:11779/`; Dev is `http://<lan-host>:11779/`; `.89` and verified current `.100` source null non-loopback HTTP URLs | Exact input and return branch recovered | **PROVEN ROOT CAUSE** |
| Declared size/hash wrong | Active blobs hashed; local full endpoint downloads hashed; sizes compared | Both exact | **ELIMINATED** |
| HTML/error/redirect/compression/auth/range problem | Full and Range GETs inspected locally; public live endpoint inspected while parked | Correct bytes and behavior when enabled; no request occurred in failed run | **ELIMINATED as historic refusal cause** |
| Malformed hosted declaration | IDs, versions, SHA-256 and positive archive sizes compared with current schema and startup acceptance | Shape is valid | **ELIMINATED** |
| Wrong roots/layout/classification | Every archive entry inspected and mapped; Warden metadata agrees | Both are genuinely inert and permitted | **ELIMINATED** |
| RB15 secretly contains executable ERS content | Seven entries enumerated | No `.reds`, Lua, DLL, ASI or ERS file | **ELIMINATED** |
| Existing manual install collision | Resolver/fetcher source inspected; current files inventoried | Resolver consults mod store, not game-root foreign files, before fetch; refusal preceded projection | **ELIMINATED for `Unverifiable`** |
| Existing manual install affects later custody/projection | RB15 manual files are byte-identical; livery archive differs and tweak uses an older name; Case B not run | May produce quarantine/replace/restore behavior only after URL issue is fixed | **STILL POSSIBLE at projection; bounded acceptance test owed** |
| Stale/corrupt NCM blob cache | Mod store searched for both hashes/package IDs; temporary fetch/peek dirs inspected | Neither package is cached and no relevant partial exists | **ELIMINATED** |
| Indexed loader ID/version wrong | Historic signed index generation 61 contained six packages, no ArchiveXL/TweakXL; current catalogue still shows worlds with failing indexed shapes and official worlds with hosted loader assets | `NotInIndex` was accurate for that index | **PROVEN separate dependency failure** |
| Server/launcher version skew | Online server `.87`, running launcher `.89`; current official launcher `.100`, stable server `.91`, unstable server `.99` | Material skew; `.100` still has same HTTPS rule | **PROVEN risk, not root cause** |
| Platform cannot deliver real vehicle mods | Current official worlds advertise hosted real vehicles, tweaks and executable loaders over HTTPS; docs show the same pipeline | Strong platform evidence, not an NCM live PASS | **ELIMINATED as a general claim** |

### Existing-local-install comparison

Case A was inspected, not projected: all seven RB15 destinations already exist and are byte-identical to the
hosted entries. The livery `.archive.xl` and tweak bytes match, though the installed tweak is named
`zzzz_ncm_rb15_liveries.yaml`; the installed livery archive is an older/different 7,569,408-byte build while
the package entry is 8,003,584 bytes. Launcher settings explicitly allow these foreign files.

Case B has not been performed because it becomes meaningful only after the URL correction and a joinable test
world exist. The acceptance plan below isolates/moves only these named files after backup, never wipes the mod
store or general game installation, and compares both states.

## E. Root cause

**Observed symptom:** after unsecured consent, both real inert NCM packages returned `Unverifiable` in about
300 ms; no server request occurred.

**Actual cause:** NCM's `resources.download.publicBaseUrl` was a non-loopback HTTP URL. Launcher URL sanitation
discarded it. The resolver uses the same `Unverifiable` enum for the resulting missing URL/size condition, so
the log did not expose the rejected scheme.

**Why unsecured did not help:** unsecured consent changes only the unverified-executable policy boolean. URL
sanitation is unconditional and occurs while the master catalogue is read, before the consent-dependent
resolver call.

**Affected packages:** all hosted packages—RB15, liveries, and the hosted loader attempts. The indexed loader
attempts had a separate genuine `NotInIndex` failure.

**What did not matter:** manual RB15/livery files, package review requests, inert versus executable class,
archive layout, hash, size, endpoint reachability and stale cache were never reached by the failing branch.

**Why the wrong conclusion lasted:** current official docs explicitly show public HTTP resource URLs, the server
accepts/advertises `allowInsecureHttp`, the live HTTP endpoint worked, the UI said only “cannot be installed,”
and `Unverifiable` was previously inferred to be an attestation state. It is actually a local launcher resolver
state for missing URL/size.

## F. Smallest safe correction

1. For the fastest same-PC Development proof today, change only the local Development
   `resources.download.publicBaseUrl` to `http://127.0.0.1:11779/` and set `unsecured=true`. `.89` and `.100`
   explicitly accept loopback HTTP. This proves resolver/fetch/projection on that machine; it does not prove a
   remote player's reachability.
2. For the real public/remote-client path, put NCM's resource listener behind an owned HTTPS origin (valid public
   certificate; no authentication or content transformation). Reverse-proxy the resource/mod routes and preserve
   Range, ETag and byte identity. Change `publicBaseUrl` to that exact HTTPS base. Do not expose Warden.
   Reconnaissance found no reusable route: the catalogue has no NCM hostname/website, Caddy/nginx/apache are
   inactive on the host, and only plain HTTP `11779` is listening.
3. Align the Development proof on current supported builds: launcher `.100` and a current compatible server
   (stable `.91` is the conservative target; test any later chosen build first). Re-run configuration/load-list
   guards after upgrade.
4. Keep the two existing NCM package hashes unchanged. Supply ArchiveXL/TweakXL through current platform loader
   resources or the exact authorised hosted loader packages; do not retry absent indexed IDs.
5. Enable `requiredMods` and `unsecured` only on the bounded Development/test world. Confirm the master row
   contains four usable URLs (loopback HTTP for the same-PC proof, HTTPS for any remote proof) and
   `unsecured=true` before clicking Connect.
6. After proof, park the flags again unless the owner separately authorises Production promotion.

No package rebuild, review approval or cache wipe is needed to correct the old refusal. A platform issue should
also be filed narrowly: either document/enforce HTTPS at server registration/config validation, or make the
launcher report `InsecureDownloadUrl` rather than erasing the URL and returning `Unverifiable`.

## G. Acceptance result

**Result today: NOT YET ACCEPTED IN GAME.** The forensic root cause is proven and the exact artifacts pass every
pre-download/package audit, but no clean client has yet completed consent -> HTTPS fetch -> hash -> projection ->
boot -> RB15/livery availability -> restoration. Production stayed parked and no restart/deployment occurred.

The real acceptance run is MASTER_TEST section AP, amended to use these packages rather than a dummy:

1. Capture the advertised usable URLs, four-package digest, `unsecured=true`, versions and hashes. Record whether
   this is the same-PC loopback proof or the public HTTPS proof; do not conflate them.
2. Back up saves and the ten named RB15/livery destinations. Record launcher store/projection state.
3. **Case A:** retain the current manual files. Connect, consent, and capture URL resolution, fetch/cache,
   archive inspection, collision/quarantine decisions, projection receipt, boot digest, ArchiveXL/TweakXL logs,
   the RB15 vehicle record and all NCM livery records in game.
4. Disconnect/reconnect and switch to Solo. Prove no redownload, no corruption, and exact restoration of every
   foreign/manual file.
5. **Case B:** safely isolate only the named manual RB15/livery files (and manual loader files only if the
   loader test plan explicitly owns them). Connect again from a clean world projection. Prove OPEN//77 supplies
   the complete required set and the same content works.
6. Remove/park the world requirement, reconnect/switch profile, and prove clean removal/restoration. Restore the
   backup if any byte differs.

PASS requires evidence at all fourteen stages in the owner's request. Any result short of in-game RB15 plus
NCM liveries and a clean profile round trip remains NOT RUN/FAIL, regardless of how convincing the static audit
is.

## H. Architectural consequence

**Classification: UNKNOWN - EXACT REMAINING QUESTION IDENTIFIED.**

The general OPEN//77 pipeline is no longer credibly “blocked behind review”: current implementation, current
official worlds and exact resolver code support an unsecured Development path for inert and executable hosted
packages after consent. NCM's own old wall is now explained by HTTP URL sanitation.

NCM still lacks its own live acceptance receipt. Therefore future NCM input/control mods may treat RequiredMods
as a high-confidence candidate delivery mechanism, but may not depend on it until the HTTPS four-package RB15 +
livery acceptance above passes. After that pass, the proper classification becomes **WORKING NOW - UNSECURED
DEVELOPMENT PATH** for package types/roots actually exercised; secured public delivery of executable control
code still requires exact-hash review and separate runtime-readiness evidence.

This audit changes delivery confidence only. It does not select or implement a vehicle-control hook, Parts,
Engineering, physics, anti-cheat or a client-extension architecture.

## Evidence inventory

- Active source declaration: `tools/open77/server/server.jsonc`.
- Active staged blobs/metadata: `tools/open77/server/.open77/mods/`.
- Historic client evidence: `%LOCALAPPDATA%/Open77/launcher.log`, especially 2026-09-22 14:48 UTC.
- Client store/projection state: `%LOCALAPPDATA%/Open77/modstore/`.
- Installed-game comparison: the configured Cyberpunk 2077 game root; read-only audit only.
- Live read-only evidence: targeted SSH config query, public manifest/blob requests, and boot/store metadata.
- Current launcher evidence: official `.100` binary, SHA-256
  `fbb5c209d8d6ccde67a7bca18ddd532503724ea1b5fdd3ad0130da69f568e425`; decompiled
  `CatalogUrls`, `MasterClient`, `WorldRequirement`, and `WorldModFetcher`.
- Current external evidence: official build manifest, server catalogue, attestation endpoint, and the two
  official guides linked above, queried 2026-09-25.

## Post-audit implementation receipt — 2026-09-25 14:56-15:00 UTC

L137 subsequently authorised the whitelisted Online world instead of the loopback-first Development sequence.
Caddy 2.11.4 now terminates trusted TLS at `https://52-60-225-137.sslip.io:11779/` and proxies to OPEN//77's
loopback-only `127.0.0.1:11782` origin. Warden remains loopback-only. Online booted with four declared packages,
`enabled=true`, `unsecured=true` and digest
`06ab5485585f57f29cb5a1ad30b3e99bcdbd99985216765f76e7d01a268c90a7`; the master row relayed the same digest,
flag, classifications and four HTTPS URLs.

MASTER_TEST §AP1 is a live PASS: a normal system trust path accepted the Let's Encrypt certificate; independent
full downloads matched all four declared sizes and SHA-256 values; each ETag matched its hash; and a public RB15
Range request returned `206` with `bytes 0-1023/38537004`. This removes the transport/configuration block only.
§AP2-§AP7 remain owner-run launcher/game work, so the report's final delivery classification remains unknown
until consent, projection, loader boot, actual RB15/liveries, reconnect, Solo isolation and restoration pass.
