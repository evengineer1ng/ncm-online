# NCM WolvenKit Source Recovery

This project was reconstructed from the shipped NCM 2.0 `mt_ecosystem.archive`
using WolvenKit CLI 8.20.0 on 2026-09-02.

The recovered `mt_ecosystem.journal` was serialized to JSON and deserialized back
to CR2W. The rebuilt journal was byte-for-byte identical to the extracted input:

`CFA363C0CA528B2D1437B51A27AD4DFFAFB843F6E43DBBD74D0BD67301F2D39F`

Project layout:

- `source/archive`: the two resources packed into `mt_ecosystem.archive`.
- `source/raw`: the editable, losslessly round-tripped journal JSON.

Do not change journal IDs or localization keys during recovery. Establish a clean
project build first, then make Phase 1 phone-flow changes as reviewed source edits.
