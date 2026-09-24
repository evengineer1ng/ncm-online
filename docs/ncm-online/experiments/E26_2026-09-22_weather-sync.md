# E26 — OPEN//77 weather authority synchronization retest

Date: 2026-09-22, approximately 19:13–19:40 UTC.  
Platform: staging `52.60.225.137`, OPEN//77 `2.31.13+op77.87`.  
Probe: temporary `ncm_weather_probe`.  
Status: **PASS** — KB-6 is not reproducible on this build.

## Question

Can NCM safely treat OPEN//77's canonical environment as synchronized authority across two clients, including
transitions, late/rejoining clients and per-bucket overrides? The old KB-6 observation was rain on one client and
clear weather on another in the same bucket.

## Participants and method

Two local clients were the intended pair (initial player ids 1/2; the second returned as player 5 after the rejoin
step). Two unrelated visitors briefly joined; player 4 happened to be present for the fog capture and agreed with
the same canonical state. For every capture the probe recorded the server's canonical state and each client's
`open77_weather.getState()` projection: scope, bucket, authority epoch, global revision, weather revision, preset,
transition remaining time, next-change time and game clock.

## Results

| Queue item | Result | Evidence |
|---|---|---|
| W1 default scope | **PASS** | Both clients matched `default`, epoch `2286879`, revision/weather revision `4`, `lightclouds / 24h_weather_light_clouds`; scheduler deltas were 25–64 ms. |
| W2 supported presets | **PASS** | `sunny`, `lightclouds`, `cloudy`, `rain`, `heavyclouds`, `fog`, `pollution` and `sandstorm` all projected consistently and settled on both clients. Revisions advanced monotonically. Fog additionally matched on visitor player 4. |
| W3 natural scheduling | **PASS** | A platform `random_weather` change occurred with both clients connected; the subsequent canonical and client observations agreed without manual resynchronization. |
| W4 mid-transition rejoin | **PASS** | During a 240 s rain transition, player 2 disconnected and returned as player 5. Canonical/p1/p5 remaining times were 65,766/65,726/65,710 ms at capture, all on epoch `2286879`, revision `14`; the returner joined the current transition rather than restarting it. |
| W5 shared override | **PASS** | Both clients in bucket `7701` matched `bucket:7701`, sandstorm, weather revision `16`; canonical/client timing differed by no more than 35 ms. |
| W6 leave override | **PASS** | Player 5 moved to bucket 0 and acquired default `lightclouds` revision `15`, while player 1 remained on bucket `7701` sandstorm revision `16`. |
| W7 clear override | **PASS** | Player 1 returned to bucket 0; both clients matched default epoch/revision `2286879/22`, weather revision `15`, `lightclouds`. Their next-change timers were 52–59 ms from canonical. `getState(7701)` returned `unknown_bucket`. |
| W8 tuple review | **PASS** | No stale epoch, wrong scope, divergent preset, unexplained transition restart or material clock/timer divergence was found. |

The bucket scheduler changed its override naturally from sandstorm to rain shortly before cleanup. This did not leak
into the default environment and further demonstrated that scoped schedules are independent.

## Diagnostic limitations found

These are probe-output defects, not weather-authority discrepancies:

- The probe asks `getState(0)` for a player in the default bucket. OPEN//77 correctly answers `unknown_bucket`;
  the comparable default canonical state is the top-level state already logged by the capture.
- Successful `set`/`move`/`clear` calls are logged with misleading `error=true` or `error=table: ...` text because
  the temporary probe assumes a different return tuple. The operation result and subsequent state prove success.

Correct these if the probe is retained. Do not interpret either line as a platform failure.

## Conclusion

KB-6 is closed for `op77.87`. The required gate for an NCM Weather Service has passed. NCM may now build against
canonical weather, but downstream competitive/economic behavior still requires its own implementation and live QA;
this experiment validates the platform synchronization contract only.
