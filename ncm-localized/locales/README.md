# Catalog layout

- `en-us.json`: canonical English runtime catalog.
- `translator-template.json`: blank volunteer starting point.
- `context.json`: generated source and translation notes.
- `reverse_index.lua`: generated legacy-boundary bridge; do not edit.

Run `tools/ncm_i18n.py extract` after changing player-facing English source, then
review the diff. Extraction intentionally never edits an existing translation.
Run `validate` before accepting any catalog.

