# E27 — Vehicle Collection authoritative encounter

> **STATUS: HISTORICAL** - experiment record. A record of a moment, never architecture.
> Authority map: [INDEX.md](../../INDEX.md) - classified 2026-09-24 (L125)

Date: 2026-09-22  
Status: **NOT RUN — implementation ready for the next clean deploy**  
Build target: current staging OPEN//77 op77.87

## Claim under test

The server can award durable discovery without trusting the client: an NCM-registered canonical vehicle's exact
runtime record resolves to a stable `vehicleKey`, and the server can compare its canonical position/bucket with a
Driver's position/bucket for a short dwell. Arbitrary ambient traffic is outside the registry and cannot award.

Candidate policy: same bucket, exact authoritative record match, distance ≤18 m for three consecutive one-second
samples. Optional client streaming evidence is not required unless this experiment finds the server snapshots stale
or misleading.

## Setup and evidence

Deploy migration 014 and both resources during an announced clean restart with no clients connected. Confirm:

- migration 014 applies once;
- `[ncm_league/collection] ready generation=1 vehicles=27 radius=18.0m dwell=3s`;
- issuing an NCM car reaches the league registry (`ncm.collection.probe <pid>` reports a nonzero registry);
- the probe prints separate live vehicle id, registered/snapshot records, vehicle key, buckets, distance and verdict.

Capture server logs and the resulting `vehicle_discovery` row for each case. A visual observation alone is not a pass.

## Matrix

| Case | Action | Required result | Result |
|---|---|---|---|
| E27.1 nearby | Client A stands within 18 m of an NCM-issued supported native car in bucket 0 for ≥3 s. | One discovery row; one restrained notification; F10 reveals exactly that slot. | NOT RUN |
| E27.2 far | Same bucket, stay beyond 18 m for ≥5 s. | Probe rejects by distance; no row. | NOT RUN |
| E27.3 bucket | Put client B in another bucket while coordinates are near the car. | Probe rejects by bucket; no row. | NOT RUN |
| E27.4 drive-by | Cross the radius in under three samples. | No discovery. | NOT RUN |
| E27.5 leave/reapproach | Hold 1–2 s, leave radius, return and hold ≥3 s. | First dwell resets; only the complete second dwell awards. | NOT RUN |
| E27.6 repeat | Leave and reapproach after discovery. | No second first-discovery notification/row; encounter count may increment. | NOT RUN |
| E27.7 reconnect | Reconnect A, encounter the same car, then open F10. | Existing discovery remains; no first award; dossier remains revealed. | NOT RUN |
| E27.8 restart | Record counts, perform an announced clean server restart, rejoin and open F10. | Discovery and first timestamp survive unchanged; generation membership remains 27. | NOT RUN |
| E27.9 two clients | A and B approach the same car independently. | Each Driver has independent state; neither grants for the other. | NOT RUN |
| E27.10 self/dev | A encounters the NCM-issued car provisioned for A. | It qualifies as registered world state; method remains proximity, not ownership/driven. | NOT RUN |
| E27.11 unregistered | Stand beside ordinary ambient traffic. | Never awards. | NOT RUN |
| E27.12 stream edge | Move the registered car beyond client stream range and compare probe snapshots, then return. | No false nearby award; document whether transform remains current enough without stream evidence. | NOT RUN |
| E27.13 aliases | Encounter a native `_player` record and an RB15 team livery where available. | Each resolves to its intended single `vehicleKey`; no duplicate conceptual slot. | NOT RUN |
| E27.14 catalogue append | In an isolated build, add one generation-2 definition without editing discovery rows. | Existing history remains; total grows by one and the new slot is `???`. Restore normal build afterward. | NOT RUN |

## Stop conditions

Stop and disable encounter awards before attaching any competitive/economic consequence if registration does not
cross resources, snapshot record/bucket is absent or inconsistent, a rapid drive-by awards, cross-bucket proximity
awards, or restart persistence fails. Catalogue, identity, persistence schema and UI remain valid independently.
