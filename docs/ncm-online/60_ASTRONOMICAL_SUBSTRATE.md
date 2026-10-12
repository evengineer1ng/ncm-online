# 60 - NCM Deep: the astronomical substrate

> **STATUS: CURRENT** - authority for: *NCM Deep's universe: catalogue (Solar System + Hipparcos), multi-body gravity, inertial frames, astronomical coordinates, telemetry, the `ncm_universe` reporter* - affirmed 2026-10-12 (L363)
> Decision: [DECISION_RECORD.md](DECISION_RECORD.md) L363. Authority map: [INDEX.md](INDEX.md). Written on the Proxmox VM as doc 57 before the bare-metal numbering was merged: code comments cite it as **doc 57**.


> **STATUS: SPEC + BUILD LOG** — 2026-10-11. Owner brief: "Build the ocean, not the next island."
> Supersedes `space.universe` v0 (L317) as the authority for *where things are*; `space.deep` keeps the
> Earth-fixed flight frame it already flies in.

## 1. OpenSpace audit (what we reuse, and under what terms)

Audited: OpenSpace `master` @ `e059151` (2026-10-11), `data/assets/**` (every `.asset` meta block and every data
file it syncs). OpenSpace *code* is MIT. Its *data* is not one licence — it is whatever each upstream publisher
says, and OpenSpace's own asset metadata records it. Tally (assets per declared licence): MIT 96 (scripts/actions),
**AMNH Digital Universe 44**, NASA / NASA-PDS / JPL 10, CC-BY variants 7, **CC BY-SA 3.0 1 (stars)**, plus single
imagery licences (Esri MLA, NOAA SOS, Hubble, Chandra, "No License").

| Need | What OpenSpace uses | Provenance / licence | NCM decision |
|---|---|---|---|
| Planet / Sun / Moon positions | SPICE SPK `de43x(s).bsp` via `SpiceTranslation` (target/observer chains: SSB → EMB → Earth) | NASA/JPL NAIF — US Government work, public domain | **Reuse the source, not the binary (v1).** v1 uses JPL SSD's published Keplerian elements (Standish, 1800–2050) + the Astronomical Almanac low-precision Moon — same publisher, Lua-sized. An SPK (type 2 Chebyshev) reader is a drop-in `ephemeris` provider later (de440s ≈ 32 MB, server side). |
| GM, radii, rotation | SPICE PCK `pck0001x.tpc`, `gm_de43x.tpc` | NASA/JPL NAIF — public domain | **Reuse values** (cited per record in `data/solar_system.lua`). |
| Reference frames | SPICE frames: J2000/ICRF, ECLIPJ2000, IAU_EARTH, GALACTIC | JPL definitions | **Reuse definitions**: ICRF axes, J2000 obliquity 23.439 281°, IAU galactic pole (RA 192.859 48°, Dec 27.128 25°, ℓ_NCP 122.932°). |
| Scene hierarchy | parent/child scene-graph nodes (SSB → barycentres → bodies) | MIT code | **Reuse the idea**: every record carries `parent`; positions compose up the tree. |
| Large-distance precision | Camera-relative rendering + dynamic scene-graph root (OpenSpace's "dynamic camera origin"); double precision positions | MIT code | **Reuse the idea**: NCM uses sector + offset (2⁴⁰ m cells) for the authority and a floating bubble for REDengine. |
| Nearby stars | `digitaluniverse/stars.asset` (`stars.speck`) | **AMNH Digital Universe** terms — not MIT, not cleared for redistribution in a commercial-adjacent mod | **Do not ship AMNH speck files.** Ingest **Hipparcos** (ESA, van Leeuwen 2007, CDS I/311) with `tools/build-star-catalogue.py` — free use with acknowledgement. Gaia DR3 (ESA, CC BY-SA 3.0 IGO) is a later, share-alike option. |
| Milky Way stars (`milkyway/stars`) | — | **CC BY-SA 3.0** (share-alike) | Not ingested. |
| Exoplanets | `modules/exoplanets` built from the NASA Exoplanet Archive | NASA Exoplanet Archive (public; acknowledgement requested) | **Ingest later** with the same catalogue schema (host star → planets with a, e, P, mass). |
| Galaxies / DSOs (2MASS, Tully, Abell, 6dF…) | Digital Universe speck files | AMNH terms | Not ingested. v1 seeds the Galactic Centre (Sgr A*) only; extragalactic catalogues come from public NED/HyperLEDA ingests later. |
| Imagery (globes, textures) | many | mixed (Esri MLA, NOAA, PDS, CC BY-SA IGO…) | Unchanged: Deep's Earth stays NASA Blue Marble (public domain). |

**What remains NCM:** the authority (records, frames, time), multi-body gravity and its relevance rules, the vehicle
integrators and their frames, telemetry, persistence, and every gameplay rule. OpenSpace stays a renderer/reference
we may *talk to* (prototypes/ncm_openspace), never the source of truth.

## 2. Architecture (core modules, all pure — hosts inject time)

| Module | Job |
|---|---|
| `space.astro` | Units, time (UTC → JD/TT), frames (ICRF ⇄ ecliptic ⇄ galactic, ICRF ⇄ Earth-fixed by GMST), **hierarchical positions** `{cell = {i,j,k}, off = {x,y,z}}` with 2⁴⁰ m cells (~7.35 AU; exact integers to 10²⁸ m), add/sub/distance without ever forming a galactic-magnitude double. |
| `space.catalogue` | Body records as data: `id, name, kind, parent, gm, radius, rotation, ephem, provenance, tier`. Registry + spatial grid (1 ly cells) for stars. Queries: `get`, `stateAt(id, t)`, `near(pos, r)`, `nearest`, `system(pos)`. |
| `space.ephemeris` | Providers keyed by record `ephem.kind`: `fixed`, `kepler` (heliocentric elements + rates), `moon_aa` (Almanac Moon), `satellite` (mean elements about a parent). Returns state in the parent frame; the catalogue composes to the root. |
| `space.gravity` | `a = Σ GMᵢ (Rᵢ − r)/|Rᵢ − r|³ − a_frame` over **relevant** bodies. Relevance = distance pruning at `d = √(GM/ε)` (exactly where the body's pull falls below ε), so pruning never cuts a body that matters; a C¹ weight between ε and 2ε removes the last step. Hierarchical candidates (root system bodies, children only near their parent, stars from the grid). No Earth-to-Sun switch exists anywhere. |
| `space.telemetry` | Per vehicle: astronomical position/velocity, frame, nearest + relevant bodies, distances, relative + radial velocity, dominant contributors with accelerations, bound/unbound and conic elements about the dominant body, distance travelled, max distance from Earth, propulsion. |

Tiers: **catalogued** (a record) → **navigational** (queried, in telemetry) → **gravitational** (passes ε at the
vehicle) → **rendered** (sent to a client) → **local** (instantiated). Promotion is a query result, not a flag set by
hand.

## 3. Build log

- 2026-10-11 — audit (§1); core modules `space.astro`, `space.ephemeris`, `space.catalogue`, `space.gravity`,
  `space.telemetry`; data `space.data.solar` (19 records) and `space.data.stars` (60,777 Hipparcos stars in 31
  chunks, `tools/build-star-catalogue.py`); resource `ncm_universe` (shadow mode). Built against the LIVE core
  (pulled from Online 2026-10-11) because this repo checkout is behind the server — merge with the bare-metal tree.

## 4. Evidence (offline, Lua 5.4, live NcmCore loader) — `tests/run.py`: 24/24, `tests/resource_smoke.py`

- Ephemerides @ 2026-10-11 21:56 UTC: Earth 0.99824 AU, heliocentric longitude 18.23° (Sun seen at ~198.2°);
  Moon 392,005 km; Earth 29.85 km/s; Jupiter 5.308 AU; Io 421,800 km from Jupiter.
- Stars: Proxima 4.2464 ly (Gaia DR3 parallax); Alpha Cen A–B 25.7 AU (Hipparcos's own parallaxes put them 0.23 ly
  apart — overridden with Kervella 2016, recorded in the data header).
- Coordinates: 1 m exact and 1 mm to 0.1 mm at 1 AU, 4.37 ly, 26,700 ly, 2.5 Mly and 1e26 m; one light-year out and
  back in 1000 steps returns to 0.000000 m.
- Continuity: field magnitude along a ray from Earth to 3000 AU (ratio steps 1.002) never steps more than the smooth
  inverse-square bound, while the contributor set changed 34 times.
- Interstellar: 1 AU from Alpha Cen A the system is Alpha Cen A, pulls are A and B (the Sun at 8e-14 and Proxima at
  5e-12 m/s² are correctly below ε); one day of RK4 orbit at 4.37 ly conserves energy to 9.7e-16.
- Live expeditions (read-only snapshot 21:56 UTC): Galena 218,387 km from Earth, bound, coasting out to ~1.72 million
  km then falling back; Hella 29,276 km, unbound about Earth (v∞ 11.95 km/s). Pulled by Earth, Sun, Moon, Jupiter,
  Venus, Saturn, Mercury, Mars. To noon ET 2026-10-12 the full multi-body field moves the Galena 62 km and the Hella
  119 km relative to the Earth-only prediction.

## 4b. Integration built 2026-10-11 (owner: "yes switch the physics, yes change frame, yes make deep view draw … from
## this catalogue") — `patched/ncm_world`, packaged as `dist/substrate-deploy.tgz`

- **Physics** (`engineering.flightmodel`): with a UTC on the state, `env.g` = the frame's own body exact every step +
  every other relevant body from a cache (`space.frames.accel`; refresh ≤ 120 s, ≤ 2 % of the time to the nearest
  perturber). No UTC → byte-for-byte the old path. Hosts pass UTC: `space.canonical.propagate` (server), `client/deep.lua`.
- **Frames** (`space.frames`): Earth-fixed near home; inertial centred on the sphere-of-influence body beyond 1e9 m
  or on leaving home's sphere (the Moon's ~66,000 km, Earth's ~925,000 km); anchored between the stars (> 1e13 m from a
  root body). Exact conversions; records keep Earth-fixed `p/vel/basis` (mirror) for every old reader and add `frame`,
  `ip/iv/ibasis`, `futc`. Guidance and the KSA border hold force Earth-fixed.
- **Deep view**: the WebGL page's 9,000 random stars → 4,541 Hipparcos naked-eye stars turned by GMST; its Sun from the
  catalogue (was `sunAt`, 4.03° off today: no equation of time); the Sun, Moon, planets, Sagittarius A* drawn at true
  direction and angular size with labels. The native view (`space.sky` → `ncm_sky`): its Moon from the catalogue; its
  star dome was already J2000 by the same GMST. Native Sun/planet bodies need new `ncm-sky` templates (bare-metal build).
- **Server**: `server/universe.lua` loads the 31 star chunks one per tick; `SLICE` 400 → 300 so an unhosted call stays
  below the instruction count it replaced (measured: 1,509 → 1,819 instructions per step; 586k → ~555k per call).
- **Evidence** (real code, `tests/regression.py`, `tests/frames_check.py`): patched vs live `Canon.propagate` moves the
  Hella 119.4 km and the Galena 62.6 km by noon ET — the independent RK4 multi-body prediction was 119 / 62 km. Over 48 h:
  1,817 / 511 km. **The Hella leaves Earth's sphere of influence ~20.6 h after the 21:56 UTC snapshot (~18:30 UTC 2026-10-12) and continues in the
  Sun's inertial frame.** Frame round trips exact (1e-5 m, 8e-10 m/s, attitude 1e-16); record JSON round trip 3.7 mm
  (the record's %.14g); re-anchoring at 4.37 ly exact; every patched file parses.
- **Not updated**: Assetto Corsa's adapter (bare metal), and resources that vendor older core copies but do not fly Deep
  on Online (ncm_aero …). Both keep the old path because they pass no UTC.

## 5. Integration — in this order, each one an owner decision

1. **Shadow mode (built, `resources/ncm_universe`)** — server-only, read-only: loads the universe one chunk per
   tick, reads `ncm_presence` (SELECT), logs `ASTRO …` lines every 60 s, answers `ncm.astro.where | pulls | near |
   body | test | status` (console, and players in chat). Writes nothing; no expedition changes.
2. **Physics seam** — `engineering.flightmodel` `env()`: `g = D.gravity(p) + Grav.ecefPerturbation(p, utc) +
   D.fictitious(p, v)`. One line, every host (Cyberpunk, AC, server) at once; needs `utc` passed into `env` and the
   core modules vendored into each resource that flies (ncm_world, ncm_aero…). Changes every Deep trajectory from
   that moment by the real third-body terms (tens to hundreds of km per day for today's two) — the owner's call.
3. **Frame generalisation** — the Earth-fixed rotating frame is fine near Earth but its fictitious terms grow with
   distance (ωr ≈ 58 km/s at 800,000 km, ≈ 11,000 km/s at 1 AU). Before anyone flies to another planet: records
   carry `frame = { kind = body_fixed | inertial, body | anchor }` and switch exactly (same physical state) to an
   inertial frame centred on the dominant body beyond ~1–2 million km; positions become astro positions. The Hella
   will cross that range tomorrow — this is the next step after (2), not a someday.
4. **Deep view agreement** — `deep.html` takes its Sun, Moon, planets and bright stars from `ncm:deep.bodies`
   (catalogue `near` + `stateAt` relative to the car, nearest/brightest N) instead of its own sun model; Deep's
   `sunAt` becomes `stateAt("sun")`. One universe for seeing and for flying.
5. **Persistence** — telemetry accumulators (`travelledM`, `maxFromHomeM`) into a separate table keyed by driver
   (not into the vehicle's state), so the record of a journey survives restarts without touching the vehicle.
6. **More catalogue** — SPK provider (de440s) for precise planets/moons; NASA Exoplanet Archive ingest (host star →
   planets); proper motions; extragalactic objects from public catalogues. Each is data/provider, no core change.
