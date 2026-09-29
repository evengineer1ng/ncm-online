"""Oracle Kingdom's causal social ideas, recast as a standalone racing world.

No NCM imports, server clock, network or disk access. Public racing facts enter
as immutable events; a private per-driver cast interprets them. The copied
Oracle Kingdom module supplies the seeded RNG and indexed causal ledger.
"""

from __future__ import annotations

import hashlib
import json
from dataclasses import asdict, dataclass, field
from typing import Any

from oracle_kingdom import CausalLedger, SeededRNG


DISTRICTS = ("Heywood", "Kabuki", "Badlands", "Northside", "Japantown")
ROLES = ("crew_chief", "scout", "rival", "sponsor", "reporter", "fixer")
EVENT_KINDS = (
    "race_win", "race_podium", "race_loss", "race_dnf", "clean_finish",
    "dirty_drive", "missed_start", "mechanical_failure", "turf_record",
    "turf_record_lost", "rain_mastery", "delivery_completed", "delivery_failed",
    "police_escape", "market_purchase", "helped_contact", "betrayed_contact",
)
PROVENANCE = ("observed", "simulated")
AXES = ("trust", "respect", "grievance")

# Each event has a social meaning before any character interprets it.
# Grievance is its own axis: a negative trust delta does not erase a debt.
IMPULSE = {
    "race_win": (2, 13, 2),
    "race_podium": (2, 8, 0),
    "race_loss": (-1, -7, 0),
    "race_dnf": (-2, -9, 0),
    "clean_finish": (4, 5, -1),
    "dirty_drive": (-6, -10, 3),
    "missed_start": (-4, -12, 0),
    "mechanical_failure": (-1, -6, 0),
    "turf_record": (0, 15, 5),
    "turf_record_lost": (-1, -9, 1),
    "rain_mastery": (2, 9, 0),
    "delivery_completed": (12, 5, -4),
    "delivery_failed": (-10, -5, 3),
    "police_escape": (-5, 10, 2),
    "market_purchase": (2, 2, 0),
    "helped_contact": (19, 5, -10),
    "betrayed_contact": (-28, -7, 25),
}

# The cast does not agree on what a drive means. Signed multipliers make a
# police escape exciting to a scout and a liability to a sponsor, for example.
ROLE_LENS = {
    "crew_chief": {"clean_finish": (1.3, 1.2, 1), "rain_mastery": (1.1, 1.5, 1),
                   "race_dnf": (0.7, 0.9, 0.7), "mechanical_failure": (0.5, 0.4, 0.3),
                   "police_escape": (1.2, 0.4, 1.2)},
    "scout": {"turf_record": (1, 1.6, 1.1), "police_escape": (-0.8, 1.5, 0.2),
              "delivery_completed": (1.4, 1, 1), "race_dnf": (0.5, 0.5, 0.5)},
    "rival": {"race_win": (-1.2, 1.2, 2), "race_podium": (-0.7, 1, 1),
              "turf_record": (-0.7, 1.1, 2), "turf_record_lost": (0.6, 1.1, -1.2),
              "race_dnf": (-0.5, 1.1, -0.5)},
    "sponsor": {"race_win": (1.4, 1.4, 0.4), "clean_finish": (1.5, 1.3, 0.5),
                "police_escape": (2.2, -0.8, 1.8), "delivery_failed": (1.5, 1, 1.4)},
    "reporter": {"turf_record": (0.5, 1.5, 0.3), "police_escape": (0.2, 1.4, 0.2),
                 "rain_mastery": (0.6, 1.3, 0.3), "market_purchase": (0.5, 0.5, 0.2)},
    "fixer": {"delivery_completed": (1.7, 1.2, 1), "delivery_failed": (1.7, 1, 1.5),
              "helped_contact": (1.5, 1, 1), "betrayed_contact": (1.6, 1, 1.6)},
}

SCENE_IMPULSE = {
    "race_win": 7, "race_podium": 4, "race_loss": -3, "race_dnf": -4,
    "clean_finish": 2, "dirty_drive": -8, "missed_start": -7,
    "mechanical_failure": -2, "turf_record": 16, "turf_record_lost": -12,
    "rain_mastery": 4,
    "delivery_completed": 3, "delivery_failed": -6,
    "police_escape": 5, "market_purchase": 0,
    "helped_contact": 2, "betrayed_contact": -8,
}


def _clamp(value: float, low: float = -100, high: float = 100) -> float:
    return max(low, min(high, value))


def _digest(value: Any) -> str:
    body = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(body.encode("utf-8")).hexdigest()


@dataclass(frozen=True)
class RacingEvent:
    event_id: str
    tick: int
    kind: str
    district: str
    stake: int = 2                # 1-5, verified outcome salience
    provenance: str = "observed"  # public result/source claim, never inferred
    subject_id: str = ""          # optional NPC directly helped or betrayed
    cause_ref: str = ""           # accepted response that led to this later event

    def __post_init__(self):
        if not self.event_id or self.tick < 1 or self.kind not in EVENT_KINDS:
            raise ValueError("invalid racing event identity, tick or kind")
        if self.district not in DISTRICTS or self.stake not in range(1, 6):
            raise ValueError("invalid district or stake")
        if self.provenance not in PROVENANCE:
            raise ValueError("invalid provenance")
        if self.kind in ("helped_contact", "betrayed_contact") and not self.subject_id:
            raise ValueError("direct social events need a subject_id")


@dataclass
class Contact:
    contact_id: str
    name: str
    role: str
    home_district: str
    risk: float                 # -1 cautious, +1 risk seeking
    ambition: float             # -1 private, +1 status seeking
    loyalty: float              # -1 transactional, +1 loyal
    trust: float = 0.0
    respect: float = 0.0
    grievance: float = 0.0
    memories: list[dict] = field(default_factory=list)

    def tag(self) -> str:
        if self.grievance >= 45 and self.trust <= -30:
            return "feud"
        if self.trust >= 45 and self.respect >= 25:
            return "ally"
        if self.respect >= 45:
            return "impressed"
        if self.trust <= -40:
            return "closed"
        if self.respect <= -35:
            return "dismissive"
        return "watching"


@dataclass
class Offer:
    offer_id: str
    contact_id: str
    kind: str
    cause_refs: list[str]
    created_tick: int
    status: str = "open"


class RacingWorld:
    """A deterministic, player-private social projection of racing facts."""

    def __init__(self, seed: int, player_id: str):
        if not player_id:
            raise ValueError("player_id is required")
        self.seed = seed
        self.player_id = player_id
        self.tick = 0
        self.contacts = self._build_cast(seed)
        self.scene = {district: 0.0 for district in DISTRICTS}
        self.event_hashes: dict[str, str] = {}
        self.events: list[dict] = []
        self.offers: list[Offer] = []
        self.responses: dict[str, dict] = {}
        self.ledger = CausalLedger()

    @staticmethod
    def _build_cast(seed: int) -> dict[str, Contact]:
        names = ("Mika Vale", "Ren Calder", "Sol Reyes", "Tavi Moss", "Inez Cross", "Niko Ward")
        contacts = {}
        rng = SeededRNG(seed).fork("racing_cast_v1")
        for i, role in enumerate(ROLES):
            own = rng.fork(role)
            cid = f"npc_{i+1:02d}"
            contacts[cid] = Contact(
                contact_id=cid, name=names[i], role=role,
                home_district=DISTRICTS[i % len(DISTRICTS)],
                risk=own.uniform(-1, 1), ambition=own.uniform(-1, 1),
                loyalty=own.uniform(-1, 1),
            )
        return contacts

    def ingest(self, event: RacingEvent) -> bool:
        """Apply once, or return False for an identical replay of an event ID."""
        facts = asdict(event)
        fingerprint = _digest(facts)
        prior = self.event_hashes.get(event.event_id)
        if prior:
            if prior != fingerprint:
                raise ValueError("event_id reused with different facts")
            return False
        if event.tick < self.tick:
            raise ValueError("events must be supplied in nondecreasing tick order")
        if event.subject_id and event.subject_id not in self.contacts:
            raise ValueError("unknown subject_id")
        if event.cause_ref and (event.cause_ref not in self.responses or
                                self.responses[event.cause_ref]["action"] != "accept"):
            raise ValueError("later event requires an accepted response cause")

        self.tick = event.tick
        self.event_hashes[event.event_id] = fingerprint
        self.events.append(facts)
        if event.cause_ref:
            self.ledger.record_delta("player_choice", event.cause_ref, "racing_event",
                                     event.event_id, "led_to", 1, event.tick,
                                     {"kind": event.kind, "provenance": event.provenance})
        self._apply_scene(event)
        for contact in self.contacts.values():
            self._react(contact, event)
        self._open_offers(event)
        return True

    def _apply_scene(self, event: RacingEvent) -> None:
        before = self.scene[event.district]
        # Local records and reversals move the district more than routine finishes.
        scale = 0.55 + 0.225 * event.stake
        after = _clamp(before + SCENE_IMPULSE[event.kind] * scale)
        self.scene[event.district] = after
        self.ledger.record_delta("racing_event", event.event_id, "district",
                                 event.district, "scene_standing", after - before,
                                 event.tick, {"kind": event.kind, "provenance": event.provenance})

    def _react(self, contact: Contact, event: RacingEvent) -> None:
        base = IMPULSE[event.kind]
        lens = ROLE_LENS.get(contact.role, {}).get(event.kind, (0.45, 0.65, 0.35))
        exposure = 1.0 if contact.home_district == event.district else 0.45
        if event.subject_id:
            exposure = 1.7 if event.subject_id == contact.contact_id else 0.15
        stake_scale = 0.48 + 0.26 * event.stake
        # Same event, different interpretation. These modifiers are stable
        # personality, not fresh randomness on every tick or an opaque reroll.
        preferences = (
            1 + 0.25 * contact.loyalty - 0.12 * contact.risk,
            1 + 0.30 * contact.ambition + 0.10 * contact.risk,
            1 - 0.20 * contact.loyalty + 0.15 * contact.ambition,
        )
        if event.kind == "police_escape":
            preferences = (preferences[0] - 0.85 * contact.risk,
                           preferences[1] + 0.55 * contact.risk, preferences[2])
        changes = {}
        for axis, impulse, role_mult, preference in zip(AXES, base, lens, preferences):
            before = getattr(contact, axis)
            requested = impulse * role_mult * preference * exposure * stake_scale
            after = _clamp(before + requested)
            actual = after - before
            setattr(contact, axis, after)
            if actual:
                changes[axis] = actual
                self.ledger.record_delta("racing_event", event.event_id, "contact",
                                         contact.contact_id, axis, actual, event.tick,
                                         {"kind": event.kind, "district": event.district,
                                          "provenance": event.provenance, "role": contact.role,
                                          "stake": event.stake})
        if changes:
            contact.memories.append({
                "event_id": event.event_id, "tick": event.tick, "kind": event.kind,
                "provenance": event.provenance, "changes": changes,
                "salience": round(sum(abs(v) for v in changes.values()), 3),
            })
            self._trim_memories(contact)

    @staticmethod
    def _trim_memories(contact: Contact) -> None:
        # Keep a recent window plus the strongest old memories; permanent
        # event IDs and the causal ledger remain available in this prototype.
        if len(contact.memories) > 32:
            recent = contact.memories[-16:]
            older = sorted(contact.memories[:-16], key=lambda m: (-m["salience"], m["tick"]))[:16]
            contact.memories = sorted(older + recent, key=lambda m: (m["tick"], m["event_id"]))

    def _open_offers(self, event: RacingEvent) -> None:
        for contact in self.contacts.values():
            kind = None
            if contact.role == "rival" and contact.grievance >= 25 and contact.respect >= 15:
                kind = "challenge"
            elif contact.role == "sponsor" and contact.trust >= 30 and contact.respect >= 25:
                kind = "sponsor_meeting"
            elif contact.role == "fixer" and contact.trust >= 25:
                kind = "private_run"
            elif contact.role == "reporter" and contact.respect >= 25:
                kind = "interview"
            elif contact.role == "crew_chief" and contact.trust >= 25:
                kind = "garage_invite"
            if not kind or any(o.contact_id == contact.contact_id and o.kind == kind for o in self.offers):
                continue
            offer = Offer(f"offer:{contact.contact_id}:{kind}", contact.contact_id,
                          kind, [event.event_id], event.tick)
            self.offers.append(offer)
            self.ledger.record_delta("racing_event", event.event_id, "offer",
                                     offer.offer_id, "opened", 1, event.tick,
                                     {"contact_id": contact.contact_id, "kind": kind})

    def respond(self, offer_id: str, action: str, tick: int) -> bool:
        """Record one explicit player choice; decline closes only this offer."""
        if action not in ("accept", "decline") or tick < self.tick:
            raise ValueError("invalid or out-of-order response")
        offer = next((o for o in self.offers if o.offer_id == offer_id), None)
        if offer is None:
            raise ValueError("unknown offer")
        if offer.status != "open":
            if offer.status == action:
                return False
            raise ValueError("offer already answered differently")
        response_id = f"response:{offer_id}"
        offer.status = action
        self.tick = tick
        self.responses[response_id] = {"offer_id": offer_id, "action": action, "tick": tick}
        self.ledger.record_delta("offer", offer_id, "player_choice", response_id,
                                 "answered", 1, tick, {"action": action})
        self.ledger.record_delta("player_choice", response_id, "offer", offer_id,
                                 action, 1, tick, {"contact_id": offer.contact_id})
        contact = self.contacts[offer.contact_id]
        choice_changes = {}
        if action == "accept":
            before = contact.trust
            contact.trust = _clamp(before + 5)
            choice_changes["trust"] = contact.trust - before
            self.ledger.record_delta("player_choice", response_id, "contact",
                                     contact.contact_id, "trust", contact.trust - before,
                                     tick, {"offer_kind": offer.kind})
        contact.memories.append({
            "event_id": response_id, "tick": tick, "kind": f"offer_{action}",
            "provenance": "player_choice", "changes": choice_changes,
            "salience": 8 if action == "accept" else 4,
        })
        self._trim_memories(contact)
        return True

    def explain(self, contact_id: str, axis: str, limit: int = 5) -> list[dict]:
        if contact_id not in self.contacts or axis not in AXES:
            raise ValueError("unknown contact or axis")
        edges = [e for e in self.ledger.trace_target(contact_id) if e.variable == axis]
        edges.sort(key=lambda e: abs(e.delta), reverse=True)
        return [e.to_dict() for e in edges[:limit]]

    def snapshot(self) -> dict:
        return {
            "version": 1, "seed": self.seed, "player_id": self.player_id,
            "tick": self.tick,
            "contacts": {cid: asdict(c) for cid, c in self.contacts.items()},
            "scene": dict(self.scene), "event_hashes": dict(self.event_hashes),
            "events": list(self.events), "offers": [asdict(o) for o in self.offers],
            "responses": dict(self.responses),
            "causal_edges": self.ledger.to_list(last_n=max(1, len(self.ledger))),
        }

    @classmethod
    def from_snapshot(cls, data: dict) -> "RacingWorld":
        if data.get("version") != 1:
            raise ValueError("unsupported snapshot version")
        world = cls(data["seed"], data["player_id"])
        world.tick = data["tick"]
        world.contacts = {cid: Contact(**row) for cid, row in data["contacts"].items()}
        world.scene = dict(data["scene"])
        world.event_hashes = dict(data["event_hashes"])
        world.events = list(data["events"])
        world.offers = [Offer(**row) for row in data["offers"]]
        world.responses = dict(data["responses"])
        world.ledger = CausalLedger.from_list(data["causal_edges"])
        return world


def make_seeded_season(seed: int, races: int = 32) -> list[RacingEvent]:
    """A reproducible fixture generator, not the future Paddock race sim."""
    rng = SeededRNG(seed).fork("season_v1")
    style = rng.fork("driver_style")
    pace = style.uniform(-1, 1)
    discipline = style.uniform(-1, 1)
    kinds = ("race_win", "race_podium", "race_loss", "race_dnf", "clean_finish",
             "dirty_drive", "missed_start", "mechanical_failure", "turf_record",
             "turf_record_lost", "rain_mastery", "delivery_completed",
             "delivery_failed", "police_escape", "helped_contact", "betrayed_contact")
    weights = (2.5 + 1.8 * pace, 2.5 + pace, 2.5 - 1.4 * pace,
               1.8 - 0.8 * discipline, 2 + discipline, 1.8 - 0.9 * discipline,
               1.2 - 0.4 * discipline, 1.4, 1.6 + pace,
               1.6 - 0.5 * pace, 1.2, 1.7 + 0.5 * discipline,
               1.5 - 0.5 * discipline, 1.4 - 0.3 * discipline,
               0.8 + 0.3 * discipline, 0.35 - 0.15 * discipline)
    events = []
    for i in range(races):
        kind = rng.choices(kinds, weights=weights)[0]
        subject_id = f"npc_{rng.randint(1, len(ROLES)):02d}" if kind in (
            "helped_contact", "betrayed_contact") else ""
        events.append(RacingEvent(
            event_id=f"season:{seed}:{i+1}", tick=i+1, kind=kind,
            district=rng.choice(DISTRICTS), stake=rng.randint(1, 5),
            provenance="simulated",  # fixture outcomes were never observed in game
            subject_id=subject_id,
        ))
    return events
