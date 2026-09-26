# NOW - the single next-action index

> **STATUS: LEDGER** - living session memory, rewritten at the end of every working session.
> Authority map: [INDEX.md](INDEX.md) - classified 2026-09-24 (L125).

Last rewritten: **2026-09-26 - `L152`: Parts reach a car. The instance channel now carries a driver's fitted
components from the server to a live force, per player, and Carrier 0.1.20 is on Production awaiting §AY.**

> **Claim before writing:** decisions through **L152**; MASTER_TEST through **§AY**; next QA letter **§AZ**.
> BACKLOG next free **IDEA-519**; known issues through **KB-145** plus pre-existing duplicate labels noted by
> `KB-114`. Read the ledger tails before allocating an ID.

## One next action

**Drive §AY.** Eight numbered operations in `wp/MASTER_TEST.md`, all through `/ncm.setup`. Everything below
is built, deployed and green; none of it is *done* until a live PASS sits beside it (`L69`).

```
/ncm.setup                      what can be felt at all
/ncm.setup power_unit 1.5       then drive     -- acceleration
/ncm.setup brakes 0.5           then brake     -- stopping distance
/ncm.setup tires 1.3            then corner    -- grip
/ncm.setup suspension 1.2       expect a NAMED REFUSAL, not silence
/ncm.setup power_unit 9.0       expect clamp to 2.00, logged as CLAMPED
/ncm.setup clear                back to standard
```

## What changed today, and why it is the thing that was missing

Three force levers were proven live yesterday and this morning. **Nothing connected them to Parts.** They
were readable only from `ncm_carrier.json` -- a file on one person's disk -- so a proven capability was
reachable by the owner with a text editor and by nobody else.

`L152` built the path end to end:

```
fitted parts -> parts.handling.compose -> player state bag -> client -> WebSocket -> applyHandling -> force
```

| lever | family | status |
|---|---|---|
| `gripScale` | tires | PROVEN §AU5, now reachable from a fitted part |
| `driveScale` | power_unit | PROVEN §AW1 (owner's March anti-crawl hook is prior art) |
| `brakeScale` | brakes | PROVEN §AW2 |

**This is the per-player channel, and that answers the standing question** -- *"do we care about machine
flats if it affects every car in the server?"* The record channel is keyed by RECORD, so one client cannot
hold two setups for one model. The instance channel scales force on ONE BODY, the latched player vehicle,
so two drivers in the same Galena with different engines feel different. Per-player by construction.

**Nine families are refused rather than approximated.** Suspension, steering, aerodynamics and mass have no
live quantity: moments need a torque channel and §AW3 refuted the per-corner load entries with a mechanism.
A part naming one of them fails the whole compose with a named reason. `parts.ontology.INSTANCE_QUANTITIES`
was corrected from one family to three, and `parts.handling` asserts at load that the two agree.

## What does NOT exist, said plainly

**There is no parts inventory.** Ownership, acquisition, fitting, wear and the garage UI are Parts layer 4
and are not authorised. `server/handling.lua` holds an in-memory table and exposes `NcmHandling.setParts`
for whatever eventually owns that truth; nothing persists across a restart (`IDEA-518`, recorded as
deliberate). `/ncm.setup` fits synthetic components through **the same call the inventory will make**, so a
§AY PASS is a PASS of the real mechanism rather than of a shortcut around it.

Parts is not a game system yet. What exists is the half that was hardest and least certain: the one where a
component changes how a car feels.

## Live state

- Carrier **0.1.20** on Production, manifest digest `b3e0f520...`, `requiredMods` enabled.
- `ncm_world` deployed; `[ncm_world/handling] ready -- 3 live famil(ies) on the instance channel`.
- `KB-138` chown run and verified: `find /opt/ncm/server ! -user ubuntu` is empty.
- Gate green: 380 core tests, 183 resource files, docs authority OK.

## Next after §AY

1. **§AY itself.** A lever that moves in the log but not in the car is the failure this design is most
   exposed to, and it is a different failure from §AW3's. Check both claims separately (`KB-142`).
2. **`IDEA-516`** -- make the carrier log an unknown `cmd`. Three lines. The relay page whitelists event
   names and `ncm:machine.handling` was nearly lost to it; the next message will hit the same wall silently.
3. **`KB-145`** -- seven `machine.flats` entries do not resolve. Lower priority than it looked this morning
   now that the instance channel carries Parts, but `parts.ontology` still derives its record channel from
   that table, so wrong entries mean the ontology overstates what the record channel can do.
4. **`IDEA-511`** -- build-script guard against overwriting a published dist version. Two collisions in one
   day; a third is a matter of time.
