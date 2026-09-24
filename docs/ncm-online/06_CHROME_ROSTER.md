# NCM Chrome — automotive quickhack roster, design pass v0

> **STATUS: SPEC** - owner intent, captured and **NOT authorised for implementation**. Do not build from it; do not contradict it. Covers: *vehicle cyberware / quickhack roster*
> Authority map: [INDEX.md](INDEX.md) - classified 2026-09-24 (L125)

Date: 2026-09-21. Status: **design capture, NOT implementation.** Owner-authored; agent-verified against
[CAPABILITY_PALETTE.md](../research/open77/CAPABILITY_PALETTE.md) and the evidence captured the same day.
Catalogued as IDEA-076 (parent), IDEA-077 (vertical slice), IDEA-078 (notoriety badge). Cross-refs IDEA-064–075.

**Nothing here is balanced.** Values, progression, prices, cooldowns, upload times and ranges are deliberately open.

---

## The principle

> **Create a driving problem. Do not replace driving with a punishment animation.**

The victim keeps meaningful control and has something interesting to do about it. The platform's constraints are
the design, not obstacles to it: **80 m maximum range, uploads take time, the victim is always warned, uploads are
interruptible, Self-ICE blocks, Purge counters, ally Purge counters, safe-area forbids entirely.**

At 200 km/h you cover 80 m in 1.4 s, so **landing a hack requires racecraft** — holding station, sacrificing an
overtake, matching someone through a corner. And the victim can usually *see* the attacker, because at 80 m they
are in the mirrors. There is no "select distant player → press the ruin-their-day button".

**Confirmed by evidence:** the escape mechanic works. The server issues repeated short-lived challenges during the
upload (`evidenceFreshMs` 100–750, `challengeMs` 250–2000) and "a missing, stale or failed trace blocks the
upload". Opening the gap, breaking line of sight, or interrupting with damage all genuinely stop it mid-flight.

## Categories

**Offense** · **Self-enhancement** · **Defense** · **Recovery** · **Utility/deception** · **Extreme/catastrophic**.
Not every technically possible vehicle API call should become a player ability.

---

## ⚠ Four technical findings that shape implementation

### 1. THE CEILING COLLISION — the most important one

`setPerformance` sets **one profile per vehicle**. It does not stack. NCM already intends to use it for at least
three things: **class ceilings** (E9 / homologation), **wet conditions** (IDEA-057), and now **LIMITER** and
**POWER SURGE**. Four writers, one slot.

Worse: `clearPerformance` "hands a vehicle back its record's rated performance" — so clearing a LIMITER would
**blow straight past the class cap** and hand the victim an illegal car as a reward for being attacked.

**Therefore NCM needs a single ceiling authority** — one module that owns `setPerformance` for a vehicle, holds
the contributing layers (class, conditions, hacks, boosts) and writes the composed result. Nothing else may call
it. This should exist *before* the first Chrome prototype, and it is useful on its own for E9 and wet racing.

### 2. Racing hacks must be `cosmetic` / `nonlethal`

Every hack carries a `damage` field (0–300, "the direct electrical hit of every kind") and the six kinds hit the
*person*. A racing quickhack that electrocutes the driver is not the design. The grade fields
**`cosmetic = true`** (commits no damage) and **`nonlethal = true`** (never kills) exist precisely for this.
**House rule: every NCM automotive hack is `cosmetic`, with `damage = 0`; the car is the target, never the driver.**
The extreme tier may be the single deliberate exception, and even then probably still `nonlethal`.

### 3. The victim sees the KIND, not your name

The native warning reads `INCOMING SHORT CIRCUIT` — the kind, not "LIMITER". Six kinds are all we get, so several
NCM hacks will share one. Fixable: `open77_hacking`'s `server/presentation.lua` is replaceable, and a client
resource may drive the bar itself with `present({actionId, phase, progress, kind})` under `player.hacking.project`.
**Budget for a presentation layer**, or the roster's identity dissolves into six native names.

### 4. Tyre sabotage is the only handling lever that exists

Steering, grip, traction and friction are settled negatives. `breakTire` changes how a car behaves through the
engine's own tyre model — **it is the sole mechanism NCM has that touches handling rather than power.** That makes
TIRE SABOTAGE uniquely valuable *and* uniquely dangerous, and justifies the owner's instinct to gate it hard.

---

## OFFENSE

### LIMITER — the foundational hack
Temporarily reduce the target's performance envelope (top speed ceiling, acceleration scale) through the composed
ceiling authority. Victim keeps steering, braking, everything — they simply lose straight-line capability for a
while. **This is the reference implementation for the whole system**: it changes the racing problem without
removing the race. Grades vary severity and duration.

### ENGINE CUT
`setEngine(false)` then restore. Short, dramatic loss of propulsion; the car keeps its momentum. Costs a corner
exit, a hill, an overtake defence. The engine audibly dying and restarting is free feedback if the native behaves.
**Unknown, needs a probe:** whether `setEngine(false)` at speed coasts cleanly or does something ugly. Prove on
one car before designing grades around it.

### LIMP / SYSTEM FAILURE — concept only
`setUndriveable` / `setDrivable` exist. **Prefer severe performance degradation over removing control.** Do not
casually use `undrivable` as an ordinary attack.

### TIRE SABOTAGE — persistent, not temporary
`breakTire(index)`. Qualitatively different from LIMITER: a **mechanical consequence that outlives the hack**, and
(per finding 4) the only handling-domain attack available. Should be higher progression, costlier, longer upload
and/or cooldown, more ruleset-restricted, and more significant on the Driver Fingerprint. Recoverable via
`repairTire` (see SYSTEM RESTORE).

## SELF-ENHANCEMENT

### POWER SURGE
Temporarily raise the player's own permitted envelope. Uses: overtaking, escaping, opening a gap — and
**breaking an incoming hack's range**, which is the interaction the owner correctly identified as the best thing
in the design: 76 m, 77 m, 78 m … *surge* … 81 m, **UPLOAD INTERRUPTED**. A self-enhancement becomes an emergent
defensive tool without being labelled a shield. Systemic overlap of this kind is the goal, not a side effect.
**Constraint from finding 1:** in a class-capped session a surge must be expressed *within* the homologated
envelope, or be explicitly ruleset-gated — otherwise a boost is a homologation breach.

### OVERCLOCK
A more committed relative of POWER SURGE: greater benefit, greater cost/risk. **Design slot captured, no
fictional downside invented.** The trade-off gets decided later from systems NCM actually owns.

## DEFENSE

### SELF-ICE — shipped
`charges` + `rechargeMs`; a victim holding a charge **blocks the upload and spends it**. Guaranteed, not a roll.
Finite defence creates the decision the owner names: *spend my last charge on this mild LIMITER, or save it in case
they have something worse?* **No RNG anywhere near this.**

### PURGE — shipped
Active intervention: `cancelUploads`, `removeStatuses`. Distinct from ICE (passive, finite). Keep both.

### ALLY PURGE — shipped, and the best team mechanic available
A team-mate moves within purge range (1–40 m) and clears the attack. Real positioning, real sacrifice — a car
compromises its own race to save another. **Gated on IDEA-075:** requires both players on the same *positive
combat team*, so NCM teams must map onto platform combat scopes.

## RECOVERY

### SYSTEM RESTORE
The repair primitives are scoped (`repairTire`, `repairGlass`, `repairBodyZone`, `repair(scope)`), so restoration
can be surgical rather than a universal undo. Unresolved: whether it works while moving, its cost, and whether it
is self-only. **Do not let it become an undo button.**

## UTILITY / DECEPTION

### BLACKOUT
`setLights` / `setHighBeams` on the car, optionally paired with the native **`reboot_optics`** kind on the driver
(static, scanner off, accuracy ×0.01). Situational by design — night, tunnels, weather, underground formats — and
that is fine. **Integrity note:** `reboot_optics` "has no server half at all", so a modified client can ignore it;
the vehicle-lights half is server-authoritative and cannot be.

## EXTREME / CATASTROPHIC

The primitives exist: severe damage, engine damage, body damage, detachable parts, destruction, `explode`.
**Do not pretend otherwise; do not make them ordinary street attacks.**

A catastrophic tier should require high entitlement, long upload, severe cost, substantial cooldown, an explicitly
permissive ruleset, obvious warning, available counterplay and strong behavioural consequences. The long warned
upload plus the 80 m envelope turns even destruction into **a driving situation**: the victim must get outside
80 m, the attacker must stay with them, and the victim may surge, ICE, purge, call a team-mate, change line — or,
in a ruleset with incidents, decide that causing contact and eating a penalty beats letting it land.

**The tension comes from preventing the upload, never from exploding without warning.**

## Explicitly NOT ordinary attacks

- **`setFrozen`** — valuable infrastructure, terrible quickhack. Turning a 250 km/h car into a static object
  removes agency and invites physics artifacts. It reads as an admin command, not gameplay.
- **`undrivable`** — same caution.
- **`effects.freezeMs` / `knockdown`** freeze the *person*, not the car. Avoid in a moving vehicle.

> **BREAK OR DEGRADE THE MACHINE. DO NOT STEAL THE STEERING WHEEL.**
> (Conveniently, steering manipulation is a settled technical negative anyway.)

## Settled technical negatives — do not design around these

Forced steering · grip modification · traction · friction · tyre-pressure simulation. Not exposed. Wet handling
remains a separate ceilings approximation (IDEA-057).

## Ruleset intent (IDEA-068 — capability ≠ permission)

| Tier | Chrome | Mechanism |
|---|---|---|
| **Sanctioned** | prohibited | `configureProtection{safeArea=true}` at grid formation, cleared at retire |
| **Clean street** | prohibited or heavily restricted | `resistance` scaling, or safe-area; model TBD |
| **Chrome street** | automotive quickhacks permitted, counterplay live | no protection; weapons still likely barred |
| **Extreme / underground** | catastrophic possibly legal | existence and rules unresolved |

Protection scopes **union** across providers and resistance takes the **maximum**, so no other resource can clear
NCM's sanctioned safe area. Remember it is scoped to the *current body* — a respawn needs a fresh call.

## Driver Fingerprint relationship

Chrome usage feeds the immutable fingerprint (IDEA-069/070). It records **history, not competence**: a large Chrome
axis means "this player uses Chrome a lot", never "this player is good at it". Same for aggression and catastrophic
behaviour — factual history, not a morality score. That is what makes the streetlight inspection (IDEA-063) a real
decision: *absolutely not*, or *let's go*.

## Proposed first vertical slice — four mechanics (IDEA-077)

**LIMITER · POWER SURGE · SELF-ICE · PURGE.**

That set alone produces: attack → chase → escape attempt → range management → boost → ICE block → purge →
cooldown → re-engagement. **If that is fun between two humans, expand. If it is not, the roster does not matter.**

Prerequisites before this slice: the **ceiling authority** (finding 1), `open77_hacking` loaded (IDEA-074), the
**key-map collision** settled (IDEA-074 — hacking defaults to hold-F8, NCM uses F8 for the race graph), and a
presentation decision (finding 3).

Next candidates after: Engine Cut · Ally Purge · persistent sabotage · tyre effects · System Restore · Blackout ·
eventually the extreme tier.

## North star

> A quickhack should **change the race the players are having** — never win it for them.

Positioning, speed, proximity, timing, resource management, counterplay, reading another human, and driving the
car. The Chrome layer is what makes Night City street racing impossible to reproduce in an ordinary racing game.
That is the signature.
