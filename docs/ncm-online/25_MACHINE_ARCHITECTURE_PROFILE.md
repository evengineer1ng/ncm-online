# 25 — Machine architecture profile: the proposed representation

> **STATUS: PROPOSAL** - a recommendation with **no authority until ruled on**. Covers: *machine architecture profile - awaiting Q18/Q19; section 10 undecided*
> Authority map: [INDEX.md](INDEX.md) - classified 2026-09-24 (L125)

**Status: PROPOSAL. Nothing implemented, nothing authorised.** Answers **Q18/Q19**, which the owner held back
pending a concrete representation. Builds on `18_PARTS_ECOSYSTEM.md` ("compatibility is derived, not listed")
rather than inventing a parallel scheme.

---

## 1. What problem this solves, restated

> "When NCM adds vehicle model #83, nobody should have to edit thousands of historical component definitions."

So the direction of declaration must be: **the machine says what it is; the component says what it needs; a
resolver relates them.** Neither side ever enumerates the other.

The spec also requires an escape hatch — *"exact model-specific fitment must remain possible"* — which the design
below provides without weakening the general case.

---

## 2. The proposal in one paragraph

A machine declares a **platform** (its chassis identity, the root of the tree) and a **sparse map of
interfaces**, one per mechanical family it actually has. Each interface carries exactly **three** values:
a `mount` (what it bolts to), a `size` (how big a part the machine can physically take), and a `demand` (how much
of that family's job this machine needs done). A component design declares which `mounts` it fits, the `size`
range it comes in, and the `capability` it delivers. A part fits when the mount matches, the machine's size is in
the component's range, and the component's capability meets the machine's demand.

---

## 3. The three dimensions, and why exactly three

Each answers a different question a player would actually ask, and none can answer another's.

| Dimension | The question | Type | Match rule |
|---|---|---|---|
| **`mount`** | "Does it physically bolt on?" | closed enum, exact match | `component.mounts` contains `machine.mount` |
| **`size`** | "Does it fit in the space?" | ordinal 1–5 | `machine.size` within `component.size` range |
| **`demand`** → `capability` | "Is it enough part for this machine?" | ordinal 1–5 | `component.capability >= machine.demand` |

**Why `mount` alone is not enough:** two machines can share a mounting standard and still not share parts — a
brake caliper that bolts to a 240 mm carrier is not the right caliper for a 1,900 kg van. `size` catches the
physical case; `demand` catches the *sufficiency* case.

**Why `demand` is not just `size`:** a formula car is small and demands enormously. Collapsing them would make
"tiny" mean "undemanding", which is exactly backwards for the most interesting machine on the grid.

**Why not a fourth:** every additional dimension multiplies the authoring cost across 27 machines and every
future design, and must be enforced by tests forever. If a fourth is needed later it can be added with a default,
because absence is already meaningful (§5). I would rather start at three and be proven short.

---

## 4. Representation

Authored data, beside the vehicle catalogue, in `ncm/core/data/machine_architecture.lua` — pure, testable, and
versioned with the code, exactly as `MAKER_KEY` is.

```lua
ARCHITECTURE["makigai_maimai"] = {
    platform = "kei_fwd_transverse",          -- chassis identity: the ROOT, not an interface (§6)
    facets   = { drive = "fwd", axles = 2, driven = "front", layout = "transverse_front" },
    interfaces = {
        power_unit   = { mount = "kei_transverse",    size = 1, demand = 1 },
        cooling      = { mount = "compact_circuit",   size = 1, demand = 1 },
        transmission = { mount = "kei_transaxle",     size = 1, demand = 1 },
        drivetrain   = { mount = "fwd_shaft_compact", size = 1, demand = 1 },
        brakes       = { mount = "single_piston_240", size = 1, demand = 1 },
        suspension   = { mount = "macpherson_compact",size = 1, demand = 1 },
        steering     = { mount = "rack_electric_sm",  size = 1, demand = 1 },
        tires        = { mount = "13in_narrow",       size = 1, demand = 1 },
        electrical   = { mount = "basic_12v",         size = 1, demand = 1 },
        structure    = { mount = "unibody_kei",       size = 1, demand = 1 },
        -- aerodynamics: ABSENT. A MaiMai has no aero interface. This is correct, not incomplete.
    },
}
```

A component design declares constraints *against* that, never a list of vehicles:

```lua
DESIGN["makigai_kx17_pump"] = {
    family = "cooling",
    fits   = { mounts = { "compact_circuit" }, size = { 1, 2 }, capability = 2 },
}
```

And the resolver is small enough to read in one sitting:

```lua
function fits(design, vehicleKey)
    local a = ARCHITECTURE[vehicleKey]
    if not a then return false, "no_architecture" end
    local i = a.interfaces[design.family]
    if not i then return false, "no_interface" end            -- sparse: legitimate refusal
    if design.fits.onlyModels and not contains(design.fits.onlyModels, vehicleKey) then
        return false, "model_restricted"                       -- the escape hatch (§7)
    end
    if not contains(design.fits.mounts, i.mount) then return false, "mount" end
    if i.size < design.fits.size[1] or i.size > design.fits.size[2] then return false, "size" end
    if design.fits.capability < i.demand then return false, "underspecified" end
    return true
end
```

**Every refusal names a reason.** "This part does not fit" is useless to a player; "this pump is not rated for
this car" is a shopping instruction.

---

## 5. How sparse profiles work (Q19)

**Absence of a family means the machine has no serviceable interface of that family.** It does not mean unknown,
and it does not inherit a default.

- A MaiMai has no `aerodynamics` → no aero component can ever be installed on one. Correct.
- A bike has no `differential`-bearing `drivetrain` interface of the car kind → car drivetrain parts refuse.
- A machine with no `electrical` interface simply has nothing to install there.

The resolver returns `no_interface`, which is a *legitimate answer*, not an error. Nothing is forced to declare
twelve interfaces to satisfy an ontology, which is what the owner's "not-applicable is legitimate" requires.

**The one thing I would enforce:** a profile must exist for every catalogue entry, even if it declares only a
platform and two interfaces. A *missing profile* is an authoring gap; an *empty interface map* is a statement.
A core test asserting "every catalogue entry has an architecture profile" makes that distinction real.

---

## 6. Chassis is the root, not an interface

Per `18_PARTS_ECOSYSTEM.md`: *"Chassis is partly a family and partly the root of the compatibility tree… 'replace
chassis' cannot become equivalent to replacing brake pads."*

So **there is no `interfaces.chassis`.** The `platform` field *is* the chassis identity, and it is not
installable, removable or tradeable. Chassis-adjacent assemblies that genuinely are serviceable (subframes,
crash structures) live under the `structure` family.

This also keeps Q9's invariant clean: a machine's identity survives replacing every component, precisely because
the thing that would make it a different machine is not a component.

**Emergent benefit worth noting:** because `platform` is a shared string, two models on one platform can share
parts without either knowing about the other — which is how real motorsport parts bins work, and it falls out of
the design rather than being built.

---

## 7. The escape hatch

`fits.onlyModels = { "ncx_rb15" }` restricts a design to named machines, checked *in addition to* mount/size/
demand rather than instead of them. This is for genuinely bespoke parts — a formula front wing is not a generic
aero component that happens to fit one car.

**It must stay rare, and I would make that measurable**: a test that reports what fraction of designs use
`onlyModels`. If it climbs, compatibility has quietly become a per-model list again and the whole point is lost.

---

## 8. Worked examples across materially different machines

Four machines, one component each, showing the dimensions doing distinct work.

| | **Makigai MaiMai** | **Thorton Galena** | **Quadra Turbo-R** | **NCX RB15** |
|---|---|---|---|---|
| platform | `kei_fwd_transverse` | `utility_rwd_ladder` | `sports_rwd_mid` | `formula_carbon_tub` |
| brakes | `single_piston_240` · size 1 · demand 1 | `dual_piston_300` · size 3 · demand 4 | `four_piston_330` · size 3 · demand 4 | `carbon_ceramic_f` · size 2 · demand 5 |
| aerodynamics | *absent* | *absent* | `bolt_on_ducktail` · size 2 · demand 2 | `formula_wing_mount` · size 2 · demand 5 |
| tires | `13in_narrow` | `16in_load` | `18in_perf` | `13in_slick_f` |

Now resolve one part against all four:

**`makigai_kx17_pump`** — `cooling`, mounts `{compact_circuit}`, size `[1,2]`, capability 2

- **MaiMai** → mount ✓, size 1 ∈ [1,2] ✓, capability 2 ≥ demand 1 ✓ → **fits**
- **Galena** → mount `heavy_circuit` ✗ → refused, reason `mount`
- **Quadra** → mount `perf_circuit` ✗ → refused, reason `mount`
- **RB15** → mount `formula_circuit` ✗ → refused, reason `mount`

And a part that *nearly* fits, to show `demand` earning its place:

**`generic_240_caliper`** — `brakes`, mounts `{single_piston_240, dual_piston_300}`, size `[1,3]`, capability 2

- **MaiMai** → ✓ ✓ 2 ≥ 1 ✓ → **fits**
- **Galena** → mount ✓, size 3 ∈ [1,3] ✓, but capability 2 < demand 4 → refused, **`underspecified`**

That last refusal is the one that could not be expressed by mount and size alone, and it is the single most
useful thing this model does: *"it bolts on, and it is not enough brake for this van."*

---

## 9. Authoring cost, and who does it

27 catalogue entries × roughly 8–11 populated interfaces × 3 values ≈ **250 interface declarations**.

**I propose them; you review.** Concretely: I would author the closed `mount` vocabulary first (perhaps 40–60
standards across 12 families), then the 27 profiles against it, and present them as a single reviewable table
rather than a code diff. Mount names are permanent identity of a sort — a typo creates a silent incompatibility
— so a core test must assert every `mount` string is in the closed list, the same protection `MAKER_KEY` gets.

---

## 10. What I need ruled before authoring

1. **`size` and `demand` as 1–5 ordinals** — or continuous numbers? Ordinals are legible, authorable by hand and
   comparable; numbers are more expressive and much harder to author consistently across 27 machines. ▸ *ordinals.*
2. **Shared platforms** — should any of the current 27 share a `platform` string? That makes them share parts
   automatically. I would author platforms as genuinely distinct until a real case appears.
3. **Tires** — `18_PARTS_ECOSYSTEM.md` explicitly leaves the abstraction open (set? axle pair? specification?).
   The profile above treats tires as one interface; if tires are a *set* rather than a serialised component, that
   is a component-model question, not an architecture-profile one, and can be answered later without changing
   this representation.
4. **Does `facets` earn its place?** `drive`, `axles`, `driven`, `layout` are descriptive and no rule above reads
   them. They are useful for *display* and for future rules. ▸ *Keep, but mark explicitly as non-binding metadata
   so nobody writes a compatibility rule against them by accident.*
