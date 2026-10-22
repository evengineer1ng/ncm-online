---
title: Maintaining These Docs
description: How this website is built, what is generated from the game's own data, and how to keep it current without a page edit after every commit.
status: dev
---

# Maintaining These Docs

The site is built to survive a project that changes daily: few pages, labelled states, and generated sections where
the game already holds the truth.

## How it is built

- **Source:** Markdown in `site/content/`, one file per page, with a small front-matter block (`title`,
  `description`, optional `status`). The navigation is `site/nav.json`.
- **Build:** `python site/build.py` (one pinned dependency, `Markdown`, in `site/requirements.txt`) writes
  `site/_site/`. `--check` fails on broken internal links, missing nav pages and file paths that no longer exist.
- **Deploy:** `.github/workflows/pages.yml` builds and publishes to GitHub Pages on every push to `main` that touches
  `site/` or a generated source. It does not touch the game build.
- **Search:** the build writes `search-index.json`, and a small script searches it in the browser. No service.

## What is generated

| Section | Generated from |
|---|---|
| [Controls & Commands](../commands.md) → the Help catalogue | `ncm/core/player/help.lua` (`CATALOGUE`) |
| [Changelog](../changelog.md) → in-game release notes | `ncm/online/resources/ncm_world/client/landing_content.lua` (`releases`) |
| [Home](../index.md) → what works today | the same file (`capabilities`) |
| The footer's build line | the commit the site was built from |

Edit those files and the site follows at the next build. If either file changes shape, the build fails rather than
publishing an empty table.

## Rules for content

- **Status labels are mandatory** for any system. Use `{{!status:live}}`, `{{!status:experimental}}`,
  `{{!status:in-development}}`, `{{!status:planned}}`, `{{!status:historical}}` or `{{!status:dev}}`. See
  [Status Labels](../status.md).
- **Verify against the code**, in this order: current code, tests, configuration, recent decisions, git history,
  older designs. A design document alone never makes something LIVE.
- **Document contracts, not internals.** Player pages say what a player can do and what to expect. Developer pages
  point at paths and the decision record rather than copying them.
- **Link to `.md` files** inside `site/content/`; the build turns them into `.html`.
- **No fake numbers**: no invented player counts, quotes or statistics.
- **Never publish private details**: no credentials, private IPs, account identifiers or screenshots with other
  players' names.
- `{{!root}}` inside raw HTML resolves to the site root. `{{!!x}}` writes a token literally.

## Releasing a change

1. Edit `site/content/…` (and `nav.json` for a new page).
2. `python site/build.py --check`
3. Commit and push to `main`. The Pages workflow publishes it.
