# Online, the night of 2026-10-03/04: what the data says

> **STATUS: HISTORICAL** - a read-only analysis of NCM Online's database (server id `ncm-dev`, Baseline 2 code) over the
> 24 h to 2026-10-04 02:30 ET, plus dev's history since 2026-10-01. Evidence, not architecture.
> Authority map: [INDEX.md](../INDEX.md). Ideas IDEA-916 to IDEA-922.

The owner raced on Online, so dev had one human race all night (a DNS: KB-327). Online in 24 h: **214 resolved Paddock
races: 191 simulated, 16 mixed grids (the owner), 7 bubble**. One human, one night: patterns, not proof.

## 1. A human in the race cuts the NPC field in half

| Provenance | Races | Field | NPCs classified | Win margin | Leader-to-last spread | Crash/contact DNFs per race |
|---|---|---|---|---|---|---|
| simulated | 191 | 11.2 | **93.7 %** | 4.6 s | 35 s | 1.04 |
| mixed grid (human) | 16 | 11.7 | **53.2 %** | 13.4 s | 60 s | 0 |
| bubble | 7 | 12.0 | **53.6 %** | 1.9 s | 22 s | 0 |

Simulated NPCs DNF for racing reasons (crash 87, mechanical 37, contact 11). In human races they DNF as **stopped 46,
flagged 31, retired 4** (mixed grid) and retired 19, flagged 11, stopped 9 (bubble). The flag ends the race at the
leader's crossing plus a window, and every NPC still on the model or physically stalled is a DNF. Results, points, purses
and Spotlight in human races are computed on half a field.

## 2. Model NPCs are much faster than the human, then the flag hides it

Owner vs the best NPC time in the same race: regional 174.6 / 128.0, 159.0 / 126.4, 218.9 / 145.4 s; street 54.7 / 34.5,
80.2 / 61.4, 187.8 / 109.8, 349.5 / 324.9, 100.6 / 70.1 s (20-60 % slower), but late street 261.3 / 343.5 and
365.8 / 382.4 (faster, and won). Yet the owner placed P3, P6, P11, P7, P5, P3, P3, P7, P1, P1, because the fast NPCs
were partly flagged out. Three owner DNFs were the flag (17:30, 18:06, 20:12 ET). Two errors cancel: the sim pace is high
on early regional/street runs, and the truncation inflates the human's place.

## 3. Facts the Racing Week curve does not get

Crashes in human races are recorded as stopped / retired, never `crash`, so `race_crash` facts (L302's live signal, the
district climate) undercount exactly the races humans are in. Online's simulated crash rate is **1.04 per race**, dev's
tonight 0.54 and dev's week 1.02: L302's constant EXPECTED (0.50) is a dev-night number.

## 4. Money

- NPCs: purses 809,387; entry fees -309,870; part purchases -389,240 (236 parts, avg 1,649); repairs -180,782. Roughly balanced (a slight drain). **Cars bought: 0. Exchange settlements: 0.** Teams hold 49.6 M across 170 orgs and never buy a car (L297's "teams never buy", still true).
- **SQL 1690 x56** in Online's log: KB-328, fixed on dev, not deployed.
- The owner: 15 settlements, net +3,825 (P1 nets 650-725; a DNF -50). One average NPC part costs 2-3 of the owner's wins.

## 5. Wrong machine

Two owner DNFs were `wrong_machine` (15:15, 16:00): entered in one car, raced another (IDEA-312's rule). Correct, but
learned only at the result.
