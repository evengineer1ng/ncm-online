# NCM Canonical Vehicle Roster — Scoping Report

> **STATUS: SPEC** - owner intent, captured and **NOT authorised for implementation**. Do not build from it; do not contradict it. Covers: *the canonical vehicle roster*
> Authority map: [INDEX.md](INDEX.md) - classified 2026-09-24 (L125)

**Status:** planning only; not an install list or production manifest.  
**Source:** `C:\Users\eveng\Downloads\NCM_Collection_Candidate_Matrix_v9.md`, preserved unchanged. The Matrix itself
estimates roughly 120 named chassis/implementations before its final discoveries.

## Executive summary

The Matrix can support a genuinely unusual shared automotive world: motorsport machinery, cheap cars, tuners,
classics, bikes, trucks and absurd Night City specials living beside Cyberpunk's strong native fleet. Its richest
territories are customizable tuner/club cars, lore-native derivatives and oddballs, classics, rally-adjacent cars,
motorcycles and road exotics. Its hard holes are a second serious Formula chassis, modern LMP/LMH/LMDh prototypes,
literal GT3/GT4 grids and modern touring/DTM cars. NCM must not disguise road cars or body kits as those missing
categories.

Plan around **45–65 modded vehicles** initially, with room to grow toward **80–110** after real footprint and QA data.
This is large enough to feel like a fighting-game roster without exhausting future vehicle drops.

## Architecture: five different things

1. **Shared dependencies:** ArchiveXL/TweakXL/RED4ext/redscript recur broadly; CET/Codeware, Material and Texture
   Override, Vehicle Manufacturers Resource, SDH0 Vehicle Resources/Vehicle Core, Arch V4/Bikes of the Dark Future
   and Whip Wizard form more specific clusters. Frequency is leverage, not proof of distributability.
2. **Vehicle content:** catalogue as `chassis → implementation → variant/appearance → handling profile → integration`.
   A paint pack, insanity tune or traffic JSON is not another car.
3. **Optional systems:** VCD, Vanguard, Garage, Car Modification Shop, NCGT, Manual Transmission, Nova Traffic,
   Factions Evolved, Preem Scoots and EVS are capabilities to test—not NCM authority. VCD and Vanguard conflict;
   NCM Online ownership/economy must remain authoritative.
4. **Development utilities:** Vehicle Physics Config, Car Profile Tuner, Garage Manager preview, livery templates and
   WolvenKit projects help QA/authoring without becoming player requirements.
5. **Risk/research:** DocWorks is conceptually excellent but old beta software awaiting rework; SDH0 spans incompatible
   migration generations; Bike Overhaul can crash the FZR/quad branch; EVS and custom audio are script-heavy; replacers
   and obsolete versions are poor canon foundations.

## Priority by automotive territory

### Foundational / high leverage

- **Tuner/club/livery:** yellingintothevoid R32/R33/R34 family, S15, GT86, Evo IX, 350Z v2, Eclipse, MX-5 NB2,
  Celica Supra A60, plus one primary road Supra. This is the best race-grid authoring ecosystem in the Matrix.
- **Cheap/grassroots:** native MaiMai/Quartz/Galena, Opel Corsa/Vauxhall Nova track car, Honda Beat, Renault 5 Turbo,
  Lada 2105 and Cyber Kart.
- **Road GT/touring-shaped:** Cayman GT4, Porsche 996 GT3, Audi R8, BMW M3 GTR, Mercedes 190E Evo II and Giulia.
- **Muscle/drag:** current Chevelle SS, Challenger Demon, one Camaro and one Mustang lineage.
- **Rally/Badlands:** Stratos rally kit, Manta 400 Group B, Hozuki Widebody, one Evo, 911 Dakar, Trophy Tanishi and
  Arch Dirt Bike.
- **Heritage:** GT40, Stratos, Renault 5, 2000GT-R, Cobra and 190E.
- **Formula:** RB15/NCX remains the only convincing dedicated Formula anchor.
- **Bikes/quads:** a curated Arch V4 subset, one conventional sportbike, Dirt Bike/Byakko and FZR 3000.
- **Heavy/world:** native trucks plus Bratsk Cargo Trucks, Hummer, Tanishi 6x6 and an ordinary van/pickup branch.
- **Lore-native identity:** Quadra Turbo-Z, Hozuki Widebody, Cyber Kart and FZR 3000.
- **Prestige:** native Rayfields/Herreras plus Genesis X, Lamborghini GT Vision and one iconic classic hypercar.

### Strong roster candidates

S2000, historic Skyline, Evo VI, RX-7 Stage5, AE86, Formula Drift Supra/Corolla, Viper ACR, Ford GT, Jaguar F-Type,
C63S, F40 ZEPHYR, Miura, Lotus Esprit, Panam's Warmonster, Byakko, Brennan Quad, Supron, Mahir bus, Necromancer,
Double Calibre and one physically tested Aston/Mercedes/Audi safety car.

### Expansion bench

Wobbler, M9, Tumbler, Mobility Scooter, Baronz Chair, 911 Trike, Thrax Limo, Bratsk Akimbo, Legatus, NCPD Night
Hunter, Spinner, Twin Mill, additional bikes, muscle/classic waves and surplus hypercars. Expansion is not a quality
demotion; it preserves meaningful “new vehicles added” moments and community voting.

### Redundant / difficult choices

- Pick one primary R34 implementation, one ordinary Mk4 Supra, one principal RX-7 and one F40.
- Treat a Formula Drift Supra as distinct from a road Supra; do not treat three similar road Supras as breadth.
- Three NSX body kits are appearances/implementations competing for one early role.
- Choose distinct Porsche identities (club GT, Dakar, heritage), not every 911 variant.
- Admit the safety-car winner first, not the entire shortlist.
- Do not call the road-going 996 GT3 or Ferrari race-look kit an FIA GT3 car.
- Do not stack NCGT, modular physics and local tunes without one declared handling authority.

## High-leverage creators

- **yellingintothevoid:** strongest sporting family; current tuning and documented livery/template ecosystem.
- **Oranje3:** strongest Night City breadth; karts, quads, bikes, trucks, limos, widebodies and experimental machinery.
- **SDH0:** ~30-car classic/exotic ecosystem and shared customization, but highest migration/script/rights risk.
- **Cornmilf:** current standalone classics, muscle, compact rally and road-performance breadth.
- **ctxrlsec:** strong identity vehicles; M3 GTR's separately editable livery archive is especially valuable.
- **Okrasha:** useful standalone classics and oddballs.
- **DocWorks:** outstanding fiction, currently research-only due age, beta status and permissions.

Same author or dependency never proves two releases are compatible.

## Major gaps

- second Formula/open-wheel chassis; junior and historic Formula;
- modern LMP/LMH/LMDh;
- literal GT3/GT4 race field;
- modern touring/DTM;
- modern WRC/rallycross, Subaru depth, Baja/Dakar;
- ordinary pickups, vans, semis and service vehicles (the Matrix has more weaponized heavies);
- normalized compact/kei/shitbox depth;
- verified Cyberpunk-native creator families beyond the strongest Oranje3 material.

## Storage envelopes

The Matrix contains almost no consistent archive sizes, so these are planning ranges—not measured totals. Known
examples around 22–60 MB are not representative of every high-resolution car; optional packs and shared assets can
change both compressed and installed size substantially.

| Shape | Modded vehicles | Download | Installed | Shared dependencies | Use |
|---|---:|---:|---:|---:|---|
| Lean/core | 20–30 | 4–12 GB | 7–20 GB | ~1–4 GB | One strong example per territory; native-heavy. |
| Strong recommended | 45–65 | 10–30 GB | 18–55 GB | ~2–6 GB | Broad canon plus several real competition families. |
| Expansive | 80–110 | 20–55 GB | 35–100 GB | ~3–8 GB | Controlled absurdity without most duplicates. |
| Everything seriously liked | 120–170 implementations | 35–90+ GB | 60–160+ GB | ~4–12 GB | Includes alternates/legacy/novelty; likely too unstable and redundant today. |

Measure download and installed size for the first QA cohort, then extrapolate using median, 75th percentile and
worst case. Do not set a hard cap before that evidence.

## Proposed initial canon shape

Target 45–65 modded vehicles: 8–12 tuner/club/drift; 5–7 cheap/compact; 5–7 sports/road-GT; 4–6 muscle/drag;
4–6 rally/Badlands; 4–6 heritage; RB15; 4–7 bikes/quads; 4–6 heavy/utility; 4–6 lore-native oddballs; 2–4 imported
prestige cars; one safety/course car. These are overlapping roles, not quotas. The economy should contain cheap
entry points, attainable enthusiast cars, specialists, race machinery and irresponsible trophy purchases.

## First local QA cohort

Maximize information, not coolness:

1. RB15 control.
2. yellingintothevoid R34 V-Spec II — livery/custom record and deep tuning.
3. Opel Corsa/Vauxhall Nova — grassroots track build.
4. Oranje3 Hozuki Widebody — current lore-native/rally derivative.
5. SDH0 Porsche 996 GT3 — Vehicle Resources/pre-Core stack and livery claim.
6. SDH0 Lancia Stratos rally kit — legacy generation and variant behavior.
7. yellingintothevoid Formula Drift Supra — purpose-built drift physics.
8. Oranje3 FZR 3000 — quad architecture, Arch V4 and conflict boundary.
9. One current conventional Arch V4/Oranje3 motorcycle — two-wheel replication without installing all 52 bikes.

Follow with ctxrlsec BMW M3 GTR specifically to test its unusually clean livery-authoring permission model.

For each: exact file/version/hash, dependency closure, real sizes, clean install/uninstall, NCM spawn/adopt, two-client
visibility, two different appearances, cameras/cockpit, handling/braking, transmission, damage, audio, persistence,
parity controls, inert/executable split, secured eligibility and rights. A local spawn is not production readiness.

## Implementation gates

Before a production roster or manifest: solve OPEN//77 hosting/review and size behavior; verify every dependency's
eligibility; audit Collection reference versus bundling/rehosting rights; prove stable records and two-client assets;
pin handling authority; test migrations/conflicts; and define eventual retirement semantics for owned vehicles and
immutable race history. Until then, no bulk download, installer, tester dependency stack or manifest conversion.
