# Evidence — 2026-09-24 — capability audit (`IDEA-339`)

Raw API cards pulled with `query_open77.ps1` for [`docs/ncm-online/31_CAPABILITY_AUDIT.md`](../../../ncm-online/31_CAPABILITY_AUDIT.md).
Unedited. **Read these rather than the audit's tables when the two disagree.**

| File | Why it was pulled |
|---|---|
| `client-vehicles-get.txt` | **The decisive card.** The client snapshot's complete field list — the whole drivetrain (`rpm`, `throttle`, `brake`, `steering`, suspension forces) and **no** `velocity`/`angularVelocity`. |
| `ns-vehicles-client.txt` | All 42 client natives. Source for `aimed()`, `nearby()`, `ratedTopSpeed()`. |
| `getProperties.txt` | *"no mod slots, no wheel types… not unimplemented, absent, with no RTTI type for any of them"* — audit §6. |
| `unsupportedProperties.txt` | The named list of FiveM properties with no Cyberpunk counterpart. |
| `ratedTopSpeed.txt` | An authored figure explicitly **not** the measured terminal velocity — audit §5. |
| `owner.txt` | `aiDriven`, `steward`, `physicsOwner = 0` when parked — audit §7. |
| `data-vehicles.txt` | What `Open77.data` answers for a vehicle, including the poor `"Cs"` manufacturer parse. |

**Build caveat.** Every card answers for `2.31.13+op77.78`; the service reports *"no index published for
2.31.13+op77.84"*. Development and Online run `.87`. **These field lists are a floor, not a ceiling.**
The empirical check is the `telemetry fields:` line NCM's own client logs once per session — still owed
(`wp/MASTER_TEST.md` §103).

The server-side counterparts pulled earlier live one directory up: `ns-vehicles-server.txt`,
`Open77.vehicles.get.txt`, `Open77.vehicles.setPerformance.txt`, and
`2026-09-19/guide-vehicles-drivetrain.md`.
