# 28 — Machine knowledge, discovery, documentation and observation

> **STATUS: SPEC** - owner intent, captured and **NOT authorised for implementation**. Do not build from it; do not contradict it. Covers: *machine knowledge, fog of war, documentation, empirical observation, estimation envelopes*
> Authority map: [INDEX.md](INDEX.md) - classified 2026-09-24 (L125)

**Captured 2026-09-24. Nothing built, nothing authorised, no deep dive performed.** Queued behind `IDEA-319`
(production ordinal ordering) by owner direction. Spec plus addendum plus postscript, recorded as
`IDEA-320` … `IDEA-339`.

## The governing principle

> **The simulation has authoritative facts. Players have knowledge supported by evidence.**
> Do not expose the simulation's internal truth merely because the server knows it.

This does not replace the machine-asset ontology. Every legitimate physical vehicle remains a persistent
serialised machine asset (L123, L124 A2, L126).

---

## Part 1 — the knowledge model

**1. The Machine Index is a knowledge system, not a catalogue dump.** It represents what *this player* has
legitimately learned. A model existing in the canonical catalogue does not mean any player knows it exists, its
specifications, its performance, its components or what particular examples can do. Behaves like an accumulated
field notebook, not an omniscient wiki.

**2. Fog of war is multidimensional — NOT a ladder.** Explicitly *not*
`UNKNOWN → DISCOVERED → DOCUMENTED → OBSERVED → OWNED`. These are not progressively superior versions of one
another. Establish a basic identity-discovery state, then let channels accumulate **independently and in
parallel**: Identity/Discovery · Documented · Observed · Scanner/Research · Ownership. They overlap. A player
may be heavily documented without ever seeing the machine move, or heavily observed without ever owning one.

**3. Discovery establishes identity only** — *"what is this thing?"* — turning `???` into `Makigai MaiMai`.
Many legitimate sources: physical encounter, a player trade listing, a discovered Market, a scan, acquisition.
**No single universal discovery mechanic.** Different sources may convey different additional knowledge.
**Discovery does not imply documentation.**

**4. Documented knowledge** is what legitimate in-world documentation says. Sources:
- **Professional/manufacturer Market** — a listing may convey documentation, so browsing is an
  information-gathering activity, not only shopping.
- **Ownership** — *always* grants available documentation, automatically, however legitimately acquired. The
  owner's manual, labels and specifications come with the machine; NCM does the bookkeeping.
- **Player trade listing** — discovers identity, but is **not** authoritative documentation. If the trade
  completes, ownership grants it normally.
- **No player-authored Index documentation.** NCM must not ask players to judge whether another player typed
  truthful specifications into an authoritative surface. Social claims stay social.

**5. Documented ≠ omniscient.** Documentation is only what is *designated documentable*. Internal simulation
parameters are not automatically documentation.

**6. Markets are information institutions.** Discovering a Market can grant inventory, distribution channel and
product documentation — so a Market card can legitimately produce a richer discovery than seeing the same model
drive past. Current Development behaviour already establishes basic discovery on card view; deepen it rather
than replace it.

**7. Observation is empirical and answers a different question:** *"what have I actually witnessed machines
doing?"* `Highest speed observed: 108 km/h` is evidence. `MaiMai top speed: 108 km/h` is a specification claim.
**Never silently convert the first into the second.**

**8. Observations carry serialised-machine provenance** — attributable to the exact asset that produced them,
and **agnostic about ownership**. The evidence is about the machine, not the driver. **Not a surveillance
database:** player identity need not appear in the player-facing observation record.

**9. Observations record world coordinates** where technically reasonable — position, timestamp, source asset,
type, value. **Do not manufacture prose like "observed on Recut."** Observations happen during races, free
driving, meets, the Badlands, unnamed roads, places that later become courses. Coordinates are universally
available and considerably more honest.

**10. Coordinates create a research layer.** Several high-speed observations at different coordinates let
players investigate: is A a steep downhill? Is #47 modified? Is one an outlier? Over time this produces
community knowledge about Night City itself — speed-testing locations, acceleration stretches, informal proving
grounds. **A location becomes a testing ground because players discovered it is useful, not because NCM declared
`OFFICIAL TESTING AREA`.**

**11. An observation must never contaminate model documentation.** A modified asset observed at 121 km/h does
not establish the model's documented top speed. It establishes that *that serialised machine* did that, then.
Essential once components exist: an anomaly should create a research question, not corrupt model truth.

**12. Observations are proof-bearing.** No unsupported player-entered observations. Behind any displayed claim:
type, measured value, serialised source, timestamp, coordinates. **Do not fabricate contextual prose from
insufficient evidence.**

**13. Retain evidence more richly than the UI displays it.** Early UI may show only value + source. The
database should preserve enough provenance that later presentation need not invent history.

**14. Self-observation uses the same machinery.** Driving your own machine produces observations from that
machine. In a low-population world players will populate much of their evidence themselves; that is expected.

**15. The scanner is a deliberate research mechanism.** Passive encounter establishes identity and naturally
observable evidence; an active scan investigates. Candidate future distinctions: moving vs parked inspection,
externally identifiable configuration, component-family recognition, deviation from documented factory
configuration. ~~**Do not promise scanner telemetry before engine capability is validated.**~~ **AMENDED 2026-09-27 by `L174`: the Scanner is authorised.** The engineering caution survives the deferral being lifted — a scan may establish `identity_reveal` and `observed_configuration`, and may not invent capability it did not measure. Section 7's floor-not-maximum rule is unaffected.

**16. Engineering knowledge gates interpretation.** A novice sees *"this is a Hella"*; a knowledgeable player
sees *"this differs from factory configuration"*; an engineer sees *"aftermarket cooling component"*. The
scanner becomes the bridge between machine identity, component identity, design knowledge, engineering
progression and empirical observation.

**17. Ownership ≠ universal knowledge.** Ownership grants documentation and owner-level inspection — not every
hidden variable, and not knowledge the owner has no means to interpret. *Having* the machine and *understanding*
it are different.

**18. Previously-owned knowledge persists.** Selling must not erase documentation, observations or research.
Ownership history and current ownership are separate facts.

**19. No canonical stat bars for now.** `Speed 7/10 · Handling 4/10` would prematurely answer what the systems
can let players investigate. Evidence from Development: Hold Your Breath ~27.7 MaiMai vs ~27.4 Hella; Ukulele
~5:30 vs ~5:05; handling impressions differ strongly despite close times. One canonical HANDLING number would
flatten that into a fake universal answer.

**20. There is no player-facing "Fact" channel.** The player-facing epistemology is **Documented · Observed ·
Researched/Scanned · Owned**. Internal truth stays internal unless a system legitimately exposes it.

**21. Architectural separation** to preserve, even when one page displays them together: canonical machine
definition · serialised asset · player model knowledge · player asset observations · Market knowledge/access ·
documented product knowledge · engineering/design knowledge.

**22. Data-retention principle.** Capture cheap irrecoverable context at event time: knowledge owner, world,
source asset id, observation type, measured value, coordinates, timestamp. **Configuration reference** should be
considered once the configuration/component architecture is authoritative — *asset identity says which machine
produced the observation; configuration history may eventually say what that machine was at the time.* Do not
invent that reference prematurely; do not lose sight of it.

---

## Part 2 — addendum: observational envelopes and confidence

> **Observation produces evidence. Repeated evidence produces estimates. Documentation produces documented
> knowledge.** These must remain distinct.

**23. Overworld discovery creates an estimate, not merely a receipt.** The Index should build observational
performance envelopes — e.g. `Estimated top speed 101–126 km/h · Confidence: Low`. That is the player's current
approximate understanding, not revealed mechanical truth and not a claim about the midpoint.

**24. Estimated and Documented occupy parallel UI territory**, with provenance unmistakable through wording,
presentation and confidence treatment. A player must never confuse *"NCM thinks I have enough observations to
estimate this"* with *"I possess documentation stating this."*

**25. Envelopes narrow with familiarity — to a designed floor.** Few encounters → wide/low confidence; many →
narrow/high. **Observation alone should not converge to exact documented knowledge.** Fifty Hellas might yield
`110–115 km/h · High` and still not hand over the specification.

**26. Do not equate observed speed with estimated top speed.** Seeing a Hella at 60 km/h in traffic does not
imply a 60 km/h limit. The envelope is an inference system, not `max(observed)` with error bars.

**27. The server may use hidden canonical values internally** to construct an uncertain envelope, refined by
legitimate familiarity. This is simulated player inference, not deception — the UI labels it an estimate and
states confidence.

**28. The canonical value must NOT be the midpoint.** `truth ± shrinking uncertainty` would let players read the
hidden specification off the centre. The envelope needs **asymmetry**, varying legitimately across
players/models/histories.

**29. Hard observations bound the estimate.** An estimate must not contradict authoritative observations that
logically bound the quantity. An observed 114 km/h makes `90–105` nonsensical. A lower bound on demonstrated
capability is not an upper bound on maximum.

**30. Encounter count and evidence are different variables.** Familiarity vs actual witnessed events. Fifty
ordinary encounters and three encounters including one downhill run produce *different* knowledge. Desirable.

**31. Estimation must be deterministic and auditable.** No fresh range per panel open. Derive controlled
uncertainty from stable seeds: world, knowledge owner, model/design identity, knowledge/encounter state,
observation history. **No UI rerolling for a better estimate.**

**32. Confidence is first-class** and explicitly communicated. Confidence describes the *estimate*, not machine
quality — do not accidentally create a second performance-rating system through its visualisation.

**33. Documentation does not erase observational history.** A player may hold `Documented: X` and
`Highest observed: Y` simultaneously, provenance intact. Divergence is not an error — **it is the beginning of
an investigation.**

**34. Estimates are model-level; observations keep asset provenance.** Do not discard the serialised source when
rolling observations into model-level estimates.

**35. Modified machines make this deliberately interesting.** Anomalous observations stay attributable to the
specific asset; future scanner/engineering knowledge may later explain *"#47 wasn't stock."* One reason
estimates must never silently become documentation.

---

## Part 3 — postscript: the vocabulary must be extensible

**36. This is not a top-speed system.** Top speed is merely the clearest first example. **Perform a capability
audit before freezing any vocabulary**, classifying each candidate as **DIRECTLY OBSERVABLE · DERIVABLE ·
DOCUMENTABLE/AUTHORABLE · SCANNER/ENGINEERING CANDIDATE · UNSUPPORTED**. A characteristic may occupy several.
**The audit's job is to discover what falls into our lap.** Investigation space includes acceleration (launch
and interval), braking and braking distance, cornering, lateral acceleration, steering and yaw behaviour,
stability, understeer↔oversteer tendency, traction, speed retention through corners, power delivery,
uphill/downhill performance — plus non-performance observations: identifiable configuration, visible
modifications, component families, exact component recognition where knowledge permits, deviation from factory
configuration, externally detectable condition/wear symptoms.

**37. Three legitimate information sources.** *Directly observed* (runtime exposes it) · *defensibly derived*
(NCM computes it from authoritative measurements — acceleration from velocity over time; **test, do not assume**;
legitimate only if inputs and methodology support the meaning presented) · *authored/documented* (not measurable
but legitimately documentable). **Authored knowledge must remain visibly distinct from observation and
estimation. It must never masquerade as something the player observed.**

**38. No structural dependency on external documentation.** Wikis and community databases may enrich; they
cannot be substrate. NCM must support modded machines with no external documentation, representable from
identity, serialised instances, observable runtime behaviour and whatever NCM itself authored.

**39. Different characteristics may have different epistemologies.** Do not force everything through the
top-speed pipeline. Configuration may be scanner knowledge rather than an envelope; condition may manifest as
symptoms rather than ratings. Keep observation types **explicitly defined, semantically meaningful, typed,
provenance-bearing, auditable and deliberately introduced** — extensible, but not key/value soup.

**40. Meters are not forbidden.** An understeer↔oversteer continuum could be excellent UI. **The objection is to
false omniscience, not to meters.** A meter should communicate its epistemic source, and a low-confidence
envelope might legitimately render as a fuzzy wide region that narrows with familiarity.

---

## Implementation warning (owner's, preserved)

**AMENDED 2026-09-27 by `L174`: it now is, for the scanner itself.** ~~This is not authorisation to build the scanner~~, component recognition, configuration history or engineering
knowledge.** The near-term task is to determine what discovery/Market/Machine Index primitives already exist,
what current schemas record, and **what minimal additive changes preserve the irrecoverable evidence this design
will eventually need** — specifically that any newly persisted observation can retain world + serialised machine
+ coordinates + timestamp rather than a naked number.

**Do not destroy or rewrite existing knowledge history.** Preserve what is known, explicitly represent what is
not, migrate additively.
