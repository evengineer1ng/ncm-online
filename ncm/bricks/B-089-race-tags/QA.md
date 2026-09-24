# QA — B-089-race-tags v1

Live QA is integrator-owned. This procedure checks only behavior that cannot be proven by the offline Rule suite: host shaping, settlement call placement, compact presentation, and the returned-id log line.

## Preconditions
- Candidate has first passed the repository gate under both required interpreters after admission review.
- The integrator has wired the settlement seam to call `competition.race_tags.evaluate(facts)` once with the normalized whole-session facts described by the assignment.
- The host logs one line per driver in the form `tags driver=<id8> <id,id,…>` using the ids returned by this Rule.

## QA-1 — dirty solo time trial
1. Start a one-driver race session so the host classifies it as a time trial.
2. Finish with at least one recorded incident.
3. Observe the post-event banner and the server tag log.

**PASS:** the result presentation contains no `CLEAN RACE` and no `CLEAN RUN`; it contains no position-based descriptor. The server log contains neither `clean_race` nor `clean_run` for that driver.

## QA-2 — clean solo time trial
1. Start a one-driver race session so the host classifies it as a time trial.
2. Finish with zero incidents, no penalties, and no jump start.
3. Observe the post-event banner and log.

**PASS:** the compact descriptor line contains `CLEAN RUN`, never `CLEAN RACE`. The server log contains `clean_run` and does not contain `clean_race`.

## QA-3 — two humans, close finish
1. Run a two-driver race.
2. Have both finish with corrected times within `0.5` seconds of one another.
3. Keep at least one driver clean: zero incidents, no penalties, no jump start.
4. Observe both presentations and both log lines.

**PASS:** both drivers receive `CLOSE FINISH` / `close_finish`. Every driver whose clean conditions are factually satisfied also receives `CLEAN RACE` / `clean_race`. No descriptor is shown as a separate toast; the labels appear in the one compact post-event descriptor line.

## QA-4 — jump start excludes clean
1. Run a multi-driver race.
2. Have one driver trigger the host’s jump-start fact and otherwise record zero contact.
3. Finish the race.

**PASS:** that driver’s presentation includes `JUMP START`; it does not include `CLEAN RACE`. The log contains `jump_start` and does not contain `clean_race` for that driver.

## QA-5 — log/presentation identity
For each scenario above, compare the compact descriptor labels to the ids on the corresponding server line.

**PASS:** each shown label maps to the same stable id in `M.CATALOGUE`, tag order matches the Rule output, and no driver has more than four default tags. Expected line shape: `tags driver=<id8> clean_race,close_finish` (ids vary by scenario and priority/cap).

## Offline/live boundary
Offline tests prove tag semantics, priority/cap behavior, determinism, and purity against normalized Lua data. Only live QA can prove the OPEN//77 host is shaping the same facts, calling at the intended settlement seam, rendering one compact descriptor presentation, and logging the returned stable ids without reordering or reinterpretation.
