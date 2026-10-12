# 61 - NCM Deep: the experimental propulsion stable

> **STATUS: CURRENT** - authority for: *the six Deep drives (impulse, fusion, warp, Alcubierre, jump, wormhole), the propulsion laboratory and its one-shot grant ledger, drive telemetry and the Deep travel ledger* - affirmed 2026-10-12 (L364)
> Decision: [DECISION_RECORD.md](DECISION_RECORD.md) L364. Authority map: [INDEX.md](INDEX.md). Written on the Proxmox VM as doc 58 before the bare-metal numbering was merged: code comments cite it as **doc 58**.


> **STATUS: BUILT + DEPLOYED to NCM Online 2026-10-12 05:02 UTC; awaiting the owner's live tests (impulse → wormhole).**
> Owner brief (2026-10-12): six ways of moving through NCM Deep, not six speeds. "First, make the toys."
> Builds on doc 57 (the astronomical substrate). Lab-only: no market, no progression, no balance.

## 1. The stable

| # | Drive | Part | Moves the Machine by | Useful regime | Needs a target | Steering while engaged | Spends |
|---|---|---|---|---|---|---|---|
| 1 | Impulse | ARC-IA10 (existing) | a force stroke (53 kN × 0.2 s ≈ 5.9 m/s on the Hella) | the ground to near space | no | full (it *is* a kick) | ordinary fuel (~3 kg/stroke) |
| 2 | Fusion | ZTC-FD1 + PT-500 (existing) | sustained thrust (30 kN, Isp 100,000 s) | planetary to interplanetary | no | full (AC-6 + gimbal) | fusion pellets |
| 3 | Warp | XLB-WD1 | continuous **drift** of position along the nose, v_eff = c·10^((W−1)·5/8) | interplanetary to nearby interstellar (W1 = 1 c … W9 = 10⁵ c) | no | yes: point the car | charge, W² per second |
| 4 | Alcubierre | XLB-AB1 | the bubble's x_s(t) along a **locked solution** (ramp, cruise at v_s = 10⁶ c, ramp) | major interstellar (≤ 100 ly per solution) | yes (or "ahead N ly") | none (the bubble locks attitude) | charge (1,500 + 60/ly) |
| 5 | Jump | XLB-JD1 | **discrete translation**: one instant, no path | interstellar hops ≤ 10 ly (configurable) | yes | n/a | charge (800 + 300/ly) |
| 6 | Wormhole | XLB-WH1 | **topology**: fly through mouth A, leave mouth B | any separation; constrained by anchors and the throat's life | an anchor (a catalogued mass) | full (you fly into it) | charge (2,500 flat) |

Every number is on the design (`engineering/installation.lua`, `perf`), not in the drive code: prototype settings, not balance.

## 2. Physics basis and the fiction each drive adds

**Impulse, fusion.** Unchanged: `engineering.dynamics` (Newton, rocket equation, gravity from doc 57). Doc 58 only records their activations.

**Warp. Fiction, said so.** No real physics gives a steerable superluminal field. The smallest extension is a field that advances the Machine's *position* along its forward axis at v_eff(W) while its *physical* state is untouched: its own velocity, spin and gravity all carry on as before. So the trip is continuous. Every frame is at a real astronomical coordinate, and stopping leaves the Machine there.
- **Gravity-well interdiction:** the field cannot form or hold within 20 radii of a body. That's the Earth inside ~127,000 km and the Sun inside ~0.09 AU. Crossing that sphere drops the Machine out at its edge.

**Alcubierre. Real metric, speculative engineering.** Alcubierre (1994):
`ds² = −c²dt² + (dx − v_s f(r_s) dt)² + dy² + dz²`, with the top-hat `f` of radius R and wall sharpness σ. Space contracts ahead and expands behind, and the interior is flat. The ship is in free fall: no acceleration, proper time equals coordinate time, and v_s may exceed c.
- **Not established:** the metric needs negative energy in the wall. Pfenning & Ford (1997) estimate |E| ~ (c⁴/G)·v_s²·R²·σ/4, which comes to 8.7×10⁵⁷ J for R = 6 m, σ = 8 m⁻¹, v_s = 10⁶ c. We log that number with each activation.
- **NCM's fiction:** the XLB-AB1 can form a bubble along a prepared solution.
- **In play:** the destination is locked first, the bubble forms (15 s) and settles (2 s), and then the Machine is carried along x_s(t) to the locked emergence point.
  - There is no steering, and no gravity acts on the car inside. The bubble's own interaction with fields en route is **not modelled**.
  - The car's velocity on emergence is what it was going in.
- **Stability** decays with time and with the local field (tidal reference 10⁻³ m/s²). Below 0.15 the bubble collapses early, at the real intermediate coordinate.
- **Emergence error** is seeded and deterministic: 2×10⁻⁶ × distance × (1 − quality), capped at half the standoff.
- **The collapse flash** borrows McMonigal, Lewis & O'Byrne (2012): particles swept up by the wall are released ahead on deceleration.

**Jump. Fiction, said so.** The Machine stops being at one coordinate and is at another. It never occupies the space between and takes no time to cross it.
- **Kept:** the attitude (ICRF axes), and the velocity *relative to the dominant body at the origin*, re-expressed relative to the dominant body at the destination. Without that rule a jump would carry the Sun's 30 km/s orbital velocity to another star.
- **Charge time:** 10 s + 1 s per ly.
- **Arrival:** short of the target by a standoff (2 AU from a star, 10 radii from a body, 2,000 AU from a black hole), off by a seeded error of 10⁻⁶ × distance (capped). Then a 60 s cooldown.

**Wormhole. Real solution, speculative engineering.** The Morris–Thorne traversable wormhole (1988) is a GR solution held open by exotic matter. NCM's fiction is that the generator opens a throat between a mouth beside the car and a far mouth pinned to a catalogued mass (an *anchor*).
- **Mouth A** opens 400 m ahead, comoving, and drifts toward the car at 15 m/s, so a coasting car crosses it.
- **Crossing** maps position, velocity and attitude through the mouth pair. The proper rotation e1 → e1′, e2 → −e2′, n → −n′ means you leave B through its face, moving relative to B as you moved relative to A.
- **Life:** the throat lasts 180 s (opening 6 s, collapse 4 s), and you can cross back through B to A. Distance never enters the cost.

## 3. States and controls (one button, one system)

**Lifecycle:** OFF → (DESTINATION_LOCKED) → SPOOLING / BUBBLE_FORMING / CHARGING → (BUBBLE_STABLE) → ENGAGED / WORMHOLE_OPEN → DISENGAGING → COOLDOWN → OFF, plus FAILED (shown 6 s). Each lab kit binds **only the drive under test** to Triangle and clears every other Triangle / LB / RB binding (§5).

| Drive | Triangle tap | Triangle hold (1 s) | RB / LB | Sticks |
|---|---|---|---|---|
| Impulse | stroke | — | — | AC-6 |
| Fusion | — | throttle | — | AC-6 |
| Warp | engage / disengage | emergency drop-out | warp factor up / down | AC-6: steer by pointing |
| Alcubierre | lock solution → form bubble | unlock / abort (collapse where you are) | next / previous destination | locked while carried |
| Jump | lock → charge | unlock / abort the charge | next / previous destination | AC-6 |
| Wormhole | lock anchor → open throat | collapse the throat | next / previous anchor | AC-6 (fly into it) |

**Default destinations** (`perf.defaultTarget`):
- Alcubierre → Barnard's Star (5.95 ly)
- Jump → Proxima Centauri (4.25 ly)
- Wormhole → Vega (25 ly)

The pad cycles Earth, Moon, Mars, Jupiter, Saturn, Neptune, 0.05 ly ahead, Proxima, α Cen A, Barnard's, Lalande 21185, Sirius, ε Eri, τ Ceti, Procyon, Altair, Vega, Arcturus, Capella, Polaris, Betelgeuse, 1 ly ahead, 10 ly ahead, and Sgr A*. Each drive keeps only what is in its range: a wormhole needs a mass, and a jump needs ≤ 10 ly.

## 4. Telemetry

**Events.** Every activation of all six drives emits `start`, `stream` (once a simulated second while engaged) and `end`, from the host that flies the Machine. That's the client, or the server's unhosted flight.
- **Server log:** `DRIVE <drive> START|STREAM|STATE|TRANSIT|END|DETAIL|CHECKPOINT ...`
- **Database:** one row per activation in **`deep_drive_activation`**, with:
  - drive, vehicle, player, host
  - UTC start/end; start and end astro coordinates (cell + offset JSON); start and end ICRF velocity
  - path vs endpoint distance; simulated and real elapsed time
  - charge, fuel and fusion used; target; frames; end sphere of influence
  - success and termination reason
  - `detail_json`: warp factor history and peak c; bubble R/σ/v_s/Pfenning–Ford energy, profile, stability and miss distance; jump vector, distance, error and dominant bodies; wormhole id, both mouths, separation, transits

**Read it with:**
```
ssh -i ~/.ssh/id_ed25519 ubuntu@52.60.225.137 'tail -c 20000000 /opt/ncm/logs/server.log | grep -a "DRIVE " | cut -c1-400 | tail -40'
ssh -i ~/.ssh/id_ed25519 ubuntu@52.60.225.137 'sudo mysql ncm -t -e "SELECT activation_id, drive, ok, reason, ROUND(path_m/9.4607e15,6) path_ly, ROUND(endpoint_m/9.4607e15,6) endpoint_ly, ROUND(sim_s,1) sim_s, ROUND(real_s,1) real_s, charge_used FROM deep_drive_activation ORDER BY started_utc"'
```

**Termination reasons:**
- `pilot_disengaged`, `aborted`, `charge_exhausted`, `gravity_well:<id>`
- `solution_complete`, `bubble_unstable`, `aborted_in_formation`
- `arrived`, `aborted_in_charge`, `out_of_range_at_jump`
- `traversed`, `collapsed_untraversed`
- `cancelled_in_spool`, `pilot_lost` (the host left; the server ends it where the Machine is)
- `invalid_state_restored: …`, `drive_error: …`
- `burn_complete` (impulse / fusion)

## 5. The laboratory (Alabino's Hella) and the persistence fix

**The 2026-10-11 collision.** A `flight` ownerGrant left in `tunables.json` re-ran at every restart and refitted the Hella to an obsolete layout. It had a second half: the presence record carries its own copy of the parts, and the unhosted flight flies that copy.

**Fixed:**
- **One-shot grants.** `owner_grant_ledger` records every grant spec *before* touching anything. A spec already in the ledger is never applied again; it logs `OWNER GRANT skipped`. An unreadable ledger means the grant is refused. To re-apply a kit, change the `#nonce`.
- **Presence refresh.** After a kit, the presence record's parts are rewritten from the new configuration (`NcmCanonical.refreshMachine`). Position, velocity, attitude and the travel ledger are untouched.
- **Lab overrides logged:** `OWNER GRANT kit lab_<drive> … DEEP LAB: developer test-drive override`, plus a row in `deep_lab_log`.
- **Normal players are unaffected.** Engineering through the panel and pad never passes through grants.

**Kits** (`server/engineering.lua`). Each clears Triangle, LB and RB, then fits exactly one system to them:
- `lab_impulse`: FD-1 to storage, IA-10 under the floor on tap.
- `lab_fusion`: FD-1 under the floor on hold, PT-500 and AC-6; fusion topped up to ≥ 300 kg.
- `lab_warp`, `lab_alcubierre`, `lab_jump`, `lab_wormhole`: the XLB part on the front hardpoint with its store full (about 2 activations). FD-1, PT-500 and AC-6 stay fitted, but nothing commands the FD-1.

Every kit fills the Machine's fuel tank, which the AC-6 and IA-10 burn.

**Workflow:**
```
ssh -i ~/.ssh/id_ed25519 ubuntu@52.60.225.137 'bash ~/deeplab.sh warp'      # impulse | fusion | warp | alcubierre | jump | wormhole
```
The script backs up `tunables.json` and both presence rows, sets the grant with a UTC nonce, restarts, and prints the kit's lines and the Hella's fit and bindings. It then **removes the grant** and prints both expeditions' positions before and after. Join as Alabino, test, read `DRIVE` lines, and run the next drive.

**Developer checkpoint** (not a rewind):
- Each exotic activation snapshots the Machine: on the host (`ds.ckpt`) and on the server (`deep_dev_checkpoint`, which holds the presence record, dynamics and part states).
- **Automatic restore:** the host restores automatically only when the drive produces an invalid state (non-finite, beyond 10²¹ m of its frame, physical speed over 10⁹ m/s, not a rotation, unknown frame). The activation then ends `invalid_state_restored`. A surprising result is never restored.
- **Manual restore:** `ncm.deep.labrestore <activation id>` on the server console, with the Machine unhosted.

## 6. Distance accounting (Race Week)

`space.travel`, carried in the Machine's record and mirrored to `deep_travel`, keeps:

- **path** (m, by method): continuous motion actually traversed.
  - Physical flight counts speed relative to the integration frame's centre, with the rotating Earth frame's own motion removed. It is labelled `coast`, `fusion`, `impulse` or `rocket`.
  - Warp and Alcubierre count the distance their drift carried the Machine.
- **discontinuous** (m and count, by method): the **endpoint separation** of jumps and wormhole crossings. These add **nothing** to path; the space between was never crossed.
- **earth**: current and maximum distance from the Earth's centre, every 5 simulated seconds.

Every increment must be finite, non-negative and within its cap (1.5 × the motion that could have produced it). Anything else is refused and counted, so a NaN or a frame discontinuity cannot reach an odometer.

**The scoring choice stays open:** path only, path + discontinuous, or maximum Earth distance.

## 7. What you see (native first-person and NCM's own views)

The drive layer is a canvas inside the Deep page, which is already the transparent HUD over the native REDengine view. It draws **our own Hipparcos stars** from the Machine's real position: 9,143 stars (every star brighter than Hp 6.5, plus every star within 25 pc), with the Sun as a star. Far from home the sky is the sky from there.
- **Native view:** the game's camera is measured live (`NcmGameCamera`). The sky reaches the cabin through the same cockpit rotation the native universe uses (`space.sky`: G · Rz(−GMST)).
- **The game's star dome is hidden** while a drive redraws the whole sky (warp, an Alcubierre bubble, a jump's charge), and restored after.
- **Discontinuities** get a native screen fade (jump, wormhole crossing). An Alcubierre formation and collapse ask the server for a screen post-process from its catalogue.

| Drive | Signature |
|---|---|
| Impulse | white-orange flare from below, a jolt; stars untouched |
| Fusion | sustained blue-violet torch light breathing with the throttle, heat shimmer; stars untouched |
| Warp | stars crowd toward the vanishing point and stretch into streaks, then a flowing field; streaks contract on disengage |
| Alcubierre | no streaks: a bright compressed cluster ahead, sparse reddened sky behind, lensing arcs at a shimmering bubble wall, a calm centre; formation ripples; a white collapse with a shock ring |
| Jump | lock reticle; stars pulled and swirled into the target point as darkness closes in; flash, black, then the destination sky (the target star blazing) |
| Wormhole | a black disc showing **the far mouth's sky** (Vega blazing through it), an Einstein-ring of local stars around it, a pulsing rim while it opens; crossing is a tunnel of rings; behind you, the exit mouth showing home (the Sun) |

**Previews:** `~/deepwork/drives/preview/preview.png`, 22 moments rendered headless from simulated states (`drives/tests/frames.py` → `preview.html`).

**Native limits, said so** (pending the ncm-sky DLL / NCWE templates on the bare-metal install):
- The layer is not depth-tested, so it also draws over the cabin.
- The game's own J2000 dome is not re-projected for parallax away from the Sun. The layer draws the stars that moved; the dome stays Earth's.
- There are no car-mounted native plume VFX yet.
- Native FOV punch: `Open77.camera.setFov`'s signature is unverified, so it is not used.

## 8. Verification (offline + deploy)

- **Offline drive tests:** `drives/tests/run_drives.py`, 68/68 pass. They run the live core with this work overlaid, under Lua 5.4, from a Hella state 323,000 km out:
  - plumbing
  - warp (continuity, factor change, stop at the real coordinate, gravity-well drop-out at the Sun)
  - Alcubierre (Barnard's Star at 2.1 AU, 5.948 ly carried, velocity unchanged)
  - jump (Proxima, ±error; Vega refused for range)
  - wormhole (Vega and back home through B; the throat closes)
  - NaN → checkpoint restore
  - fusion activation records
  - `frames.translate` to α Cen and the Galactic Centre, exact to the metre
  - unhosted `pilot_lost`
  - cost: 0.1 ms per engaged step
- **Continuity:** both live expeditions propagated by the old and new cores: **bit-identical** over 1 and 2 hours.
- **After the deploy:** the old-core propagation of the pre-deploy records matches the new server's records to 1.1 cm (Hella) and 1.2 mm (Galena).

## 9. Files

**Core:**
- New: `shared/core/space/{drives, drive_warp, drive_alcubierre, drive_jump, drive_wormhole, wormholes, travel, data_navstars}.lua`
- Changed: `space/frames.lua` (`toInertial`, `place`, `translate`), `space/canonical.lua`, `engineering/{flightmodel, installation, systems}.lua`. `installation.lua` and `systems.lua` are copied to every resource that carries them.

**Other files:**

| Area | Files |
|---|---|
| Server | `server/deep_drives.lua` (new), `server/engineering.lua` (kits, ledger, refresh), `server/canonical.lua` (`refreshMachine`, unhosted drive events) |
| Client | `client/drivefx.lua` (new), `client/deep.lua`, `client/deepview.lua` |
| Web | `web/deep.html`, `web/deep/drivefx.js` (new), `web/deep/skystars.js` (generated) |
| League | `ncm_league/server/schema/080_deep_drives.lua` |

**Work tree:** `~/deepwork/drives` (`base_ncm_world_20261012` is the snapshot it was built against). The package is `dist/drives-deploy.tgz`, with backups under `~/drives-backups/` on Lightsail. Merge into the bare-metal tree, not the stale repo.

## 10. Not done yet / next

- **Live tests 1–6** by the owner (§5 workflow). The game-camera roll sign in the native layer is unverified; it's `ROLL_SIGN` in `client/drivefx.lua`.
- **Native depth-tested effects and dome reprojection** (ncm-sky DLL, bare-metal NCWE).
- **Native plume VFX**, pending an Open77 VFX alias probe.
- **The engineering panel** shows the lab parts like any part. They are never sold.
- **Race Week scoring semantics** for discontinuous travel: the owner's choice (§6).
- **Wormholes for F-I-S-H-I-N-G / Nessie:** `space.wormholes` takes `origin = "natural"` records with no lifetime. Nothing places one yet.
