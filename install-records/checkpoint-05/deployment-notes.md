# checkpoint-05 follow-up (2026-09-18 ~18:00)

- Milestone 1 PASSED in game (stock Red Bull + green NCM TEST RB15 side by side).
- Replaced the hand-built single-livery test archive with the generated two-livery build from
  `wolvenkit-projects/ncm_rb15_liveries/tools/build_liveries.py --with-test` (liveries: ncm_test, demo_orange).
  Files: archive/pc/mod/ncm_rb15_liveries.archive (+.xl), r6/tweaks/ncm_rb15_liveries.yaml, r6/tweaks/ncm_rb15_liveries.manifest.json.
- Diagnostic fallback (`rb15_ncm_fallback.ent`, record `_fb`) is no longer shipped.
- CET test mod NCM_RB15_LiveryTest updated to cycle liveries from the manifest (copy in wolvenkit-projects/.../tools/NCM_RB15_LiveryTest.init.lua).
- RB15 (checkpoint-04) files remain untouched.

# 2026-09-18 18:45 — per-livery badges
- Rebuilt/deployed with optional `rb15_badges` support: ncm_test (stock badges, unpatched), demo_orange (own orange "NCX" sheet).
- Same 4 files replaced (archive, .xl, yaml, manifest). RB15 files untouched.
