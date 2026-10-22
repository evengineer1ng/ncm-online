# 63 - Making NCM Online public: the audit, the gate and the exact steps

> **STATUS: CURRENT** - authority for: *the public release of the repository and the NCM Online website* - affirmed 2026-10-22 (L372)
> Decision: [DECISION_RECORD.md](DECISION_RECORD.md) L372. Authority map: [INDEX.md](INDEX.md).

**Owner brief (2026-10-22):** make NCM Online publicly inspectable and open source, and launch a GitHub Pages website
from this repository as NCM Online's public front door. Owner rulings on the four questions the audit raised are in
L372: **MIT**; the third-party Manual Transmission and RB15-derived files are **removed from the tree and from
history**; commit emails are **rewritten to the GitHub noreply address**; SSH target, LAN IP and player/account
UUIDs are **scrubbed in HEAD** (history keeps the old text).

## 1. Safety audit (2026-10-22)

**Tools.** gitleaks 8.21.2 over the full history (`git` mode, all refs, redacted). A blob scanner over every unique
blob in history (< 3 MB, text) for IPs, emails, password assignments, DSNs, licence keys, private keys, bearer
tokens, AWS/GitHub/OpenAI keys, Discord webhooks, user paths and SSH targets, marking HEAD vs history-only. Filename
sweep for `.env`, `.pem`, `.key`, `server.jsonc`, dumps, databases, logs and saves. Size sweep for blobs > 5 MB.

| Finding | In HEAD | In history | Verdict / remediation |
|---|---|---|---|
| gitleaks: 186 hits in `ncm/radio/corpus/corpus.json`, `ncm/ncwe/race_week_day1.ncwe`, `ncm/core/tests/test_paddock_mixed.lua` | yes | yes | **False positives**: corpus hash keys, an asset fingerprint, a test fixture key. No action. |
| Credentials of any kind (passwords, keys, tokens, DSNs, licence keys, private keys) | none | none | The password-like matches are scripts reading `$env:` variables or DPAPI secrets. **Nothing to rotate.** |
| `server.jsonc`, `*.env`, `*.pem`, dumps, DB files | never committed | never committed | `.gitignore` excludes them, and has since the first commit. |
| Owner's personal email on all 273 commits | metadata | metadata | **Rewrite** to `191541982+evengineer1ng@users.noreply.github.com` (L372). |
| Patched copies of keanuWheeze's *Manual Transmission* mod (licence unknown) | yes | yes | **Removed from the tree and from history** (L372). Paths in §3. Local copies kept, ignored. |
| Files derived from the third-party RB15 car mod's mesh/entity/appearance | yes | yes | **Removed from the tree and from history** (L372). Liveries' own art and tools stay. |
| Online SSH target `ubuntu@<online-host>`, SSH key path, LAN IP | docs + ops scripts | yes | **Scrubbed in docs (HEAD)**. Ops scripts keep the address so they still work. The game IP itself is public (players connect to it). History keeps the old text (owner chose HEAD only). |
| Player/account UUIDs (owner's driver and account, tester account, a driver in two one-off ops scripts) | yes | yes | **Replaced with fixed placeholder UUIDs in HEAD**, consistently, so tests still pass. The two Hella one-off scripts (`tools/deep/ops/refuel-hella.sh`, `restore-hella.sh`) ran once and now hold a placeholder. |
| Tester handles (`ncmtester2`, owner's driver name, others in logs/bugs) | yes | yes | **Kept** by owner ruling. |
| Owner's Windows username in local paths (`C:\Users\eveng\...`) | yes | yes | Low risk; kept. |
| Untracked `Screenshot 2026-10-05 005814.png` (shows another player's handle and a session id) and `3b887e44f0b6` | untracked | never | **Not published**; now ignored. |
| Large blobs (NCWE export zips 26-34 MB, `city_survey.json` 14 MB, a RED4ext `.lib`) | some | yes | Under GitHub's limits; NCM's own exports and an MIT SDK build. No action. |
| OPEN//77 logs and crash-probe logs in `docs/research/open77/evidence/2026-10-01-*` | yes | yes | Scanned: only loopback, the public server IP and a version-string false positive. No other player data. |

**History rewrite is required** (third-party files and the email), not for secrets. Because no credential was ever
committed, **no credential needs rotating**.

## 2. Licensing

- **NCM's own work:** MIT (`LICENSE`), by owner ruling L372. This also relaxes NCM's older Nexus "no reupload"
  permission for the material in this repository. The Nexus page's own permissions are the owner's to update.
- **Bundled third-party code** keeps its licence: RED4ext.SDK (MIT, submodule), SDL3 (zlib), miniaudio (Unlicense
  / MIT-0), stb_vorbis (public domain / MIT), In-World Navigation (MIT, jackhumbert). See `THIRD_PARTY_NOTICES.md`.
- **Not redistributed:** Cyberpunk 2077 assets (CD PROJEKT), OPEN//77 binaries, runtime loaders (installed by the
  launcher), OmniVoice-rendered voice packs (CC-BY-NC weights; separate downloads), NASA imagery (fetched).
- **Open question for the owner:** the In-World Navigation original script (`packed.reds.orig`) is MIT. Its exact
  copyright line should be copied from the upstream LICENSE into `THIRD_PARTY_NOTICES.md` when convenient.

## 3. Removed third-party paths (tree and history)

```
manual-transmission-*.lua, manual-transmission-*.json                    (repo root, 8 files)
install-records/checkpoint-03/hotfix-block-change-gear/bin/
install-records/checkpoint-04/clutch-bridge-backup/clutch.lua
install-records/checkpoint-04/clutch-bridge-backup/init.lua
install-records/checkpoint-04/mt-blockchangegear-fix/
install-records/checkpoint-04/mt-blockchangegear-fix-backup/
install-records/checkpoint-04/mt-init.lua.pre-diag.bak
wolvenkit-projects/ncm_rb15_liveries/source/ncm/rb15_liveries/meshes/
wolvenkit-projects/ncm_rb15_liveries/source/ncm/rb15_liveries/*.ent, *.ent.json, *.app, *.app.json
```

## 4. The website

- Source `site/` (Markdown + `build.py`, one pinned dependency). Workflow `.github/workflows/pages.yml`. URL:
  **https://evengineer1ng.github.io/ncm-online/**.
- The command reference, in-game release notes and "what works today" are generated from
  `ncm/core/player/help.lua` and `ncm_world/client/landing_content.lua`.
- `--check` fails on broken links, missing nav pages and repository paths that no longer exist.
- **Space stays a spoiler:** NCM Deep appears only on the Experimental page, inside a collapsed spoiler, with no
  directions. This keeps the "secret by placement, never gated" ruling while not pretending the code is absent.

## 5. Publication checklist

- [x] Working tree reviewed (another session's uncommitted L370 host work is present; it is committed with this
      work, see §6).
- [x] Important local changes committed and pushed (§6 step 1).
- [x] Secrets scan clean (gitleaks + blob scan, HEAD and history).
- [x] Git history reviewed for secrets: none ever committed.
- [x] Sensitive credentials rotated if necessary: none needed.
- [x] `.gitignore` reviewed: extended for removed third-party paths, root screenshots, `site/_site/`.
- [x] Large/generated artifacts reviewed.
- [x] Logs reviewed.
- [x] Player/private data excluded (UUIDs placeholdered in HEAD, handles kept by ruling).
- [x] Licensing reviewed (MIT + notices).
- [x] Third-party code and licence obligations reviewed.
- [x] Third-party files purged from history and the email rewritten (§6 steps 2-4); verified: no purged path in any commit, no old address in any commit or blob, gitleaks shows only the known false positives, ncm-test ALL GREEN and the site check green on the rewritten checkout, and the tip tree is byte-identical to the pre-rewrite HEAD.
- [x] README, LICENSE, CONTRIBUTING, SECURITY, CHANGELOG, THIRD_PARTY_NOTICES ready.
- [x] GitHub Pages builds (`python site/build.py --check`).
- [x] Works on desktop and mobile (checked headless at 1366 px and 390 px, light and dark).
- [ ] Getting Started verified against the current server by joining it (owner, MASTER_TEST §PUB1).
- [x] Feature/status claims verified against code, the in-game landing content and the decision record.
- [x] Repository links work (link and path check in the build).
- [x] Issue templates ready.
- [x] No private infrastructure details unintentionally exposed (docs scrubbed).
- [x] Repository public (2026-10-22): published as a **fresh** repository, see §7.
- [ ] Pages enabled with source "GitHub Actions" (§6 step 7).
- [ ] Private vulnerability reporting enabled (§6 step 8).

## 6. The exact steps

1. **Commit** the tree on `main` (owner-confirmed) and push.
2. **Rewrite history in a fresh clone** of the local repository (never in the working tree), with git-filter-repo:
   `--invert-paths` on §3's paths, plus a mailmap
   `evengineer1ng <191541982+evengineer1ng@users.noreply.github.com> <the old personal address>` (the mailmap
   file lives outside the repository so the old address is never committed).
3. **Verify the rewritten clone:** the scans in §1 report no third-party path, no old email, and gitleaks is clean;
   `tools/ncm-test.ps1` is ALL GREEN on the rewritten HEAD.
4. **Force-push** every branch and tag of the rewritten clone to `origin` (owner-confirmed, irreversible for
   collaborators). Then reset the working repository to the rewritten `origin/main`. Ignored local copies of removed
   files stay on disk. GitHub can keep unreferenced old commits reachable by SHA until it garbage-collects them. They
   hold no secret, but if that matters, ask GitHub Support to purge cached views, or publish to a fresh repository.
5. Set future commits to the noreply email: `git config user.email 191541982+evengineer1ng@users.noreply.github.com`.
6. **GitHub → Settings → General → Danger Zone → Change visibility → Public.** Owner only; no tool here does it.
7. **Settings → Pages → Build and deployment → Source: GitHub Actions.** Then re-run the *Website* workflow (or push
   to `site/`). The site appears at https://evengineer1ng.github.io/ncm-online/.
8. **Settings → Code security → Private vulnerability reporting → Enable** (SECURITY.md points there).
9. **The OPEN//77 listing** (Online's `server.jsonc`, through Warden or by hand, then a restart with nobody online):
   ```jsonc
   "identity": {
     "name": "NCM Online",
     "description": "Motorsports in Night City | evengineer1ng.github.io/ncm-online",
     "website": "https://evengineer1ng.github.io/ncm-online/",
     ...
   }
   ```
   `website` is a first-class URI field in OPEN//77's schema (`identity.website`, max 2048). `description` allows 512
   characters. The schema also has `identity.discord`; leave it null. Back up `server.jsonc` first, and never copy
   Online's file wholesale: it holds the server licence.
10. **The Nexus page** (owner, by hand). Suggested text:

    > **NCM Online** is the actively developed multiplayer branch of Night City Motorsports, running on OPEN//77.
    > Its source and documentation are public at **evengineer1ng.github.io/ncm-online**, and the work there is also
    > informing the future NCM 3.0 single-player release. NCM Online is a separate product from this mod and from
    > NCM 3.0.

## 7. What actually happened (2026-10-22)

The old repository had a pull-request ref (`refs/pull/1/head`) reaching 211 commits with the old email and 18 of
the purged paths. GitHub keeps pull refs even after a force-push, so publishing that repository would have exposed
exactly what the rewrite removed. **Owner ruling:** publish to a fresh repository.

- The owner renamed the old repository to `evengineer1ng/ncm-online-private` (private, kept with its PR) and created
  a new, empty, public `evengineer1ng/ncm-online`.
- The rewritten `main` and tags `online-baseline-1..3` and `online-frozen-2026-10-17` were pushed to it. Local-only
  refs (another tool's checkpoint refs, the stash, `checkpoint/pre-op77-upgrade-2026-10-02`) were not pushed.
- The local repository now tracks the new `origin`, keeps the old one as remote `private`, and its local git
  identity is the noreply address. A bundle of the pre-rewrite history was kept outside the repository.
- **Still owed by the owner:** Settings → Pages → Source **GitHub Actions**, then Actions → *Website* → **Run
  workflow** (the first push did not trigger the path filter); private vulnerability reporting; the Online
  `identity.website` change; the Nexus link.
