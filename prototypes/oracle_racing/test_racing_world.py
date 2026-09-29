"""Behavioral checks for the standalone racing social fork."""

import json
import statistics
import unittest

from racing_world import RacingEvent, RacingWorld, make_seeded_season


class RacingWorldTests(unittest.TestCase):
    def test_replay_idempotency_and_snapshot_continuation(self):
        events = make_seeded_season(17, 33)
        first = RacingWorld(17, "driver_a")
        for event in events[:32]:
            self.assertTrue(first.ingest(event))
        self.assertFalse(first.ingest(events[0]))
        with self.assertRaisesRegex(ValueError, "different facts"):
            first.ingest(RacingEvent(events[0].event_id, events[0].tick,
                                     "race_dnf", events[0].district))

        restored = RacingWorld.from_snapshot(json.loads(json.dumps(first.snapshot())))
        self.assertEqual(first.snapshot(), restored.snapshot())
        self.assertTrue(first.ingest(events[32]))
        self.assertTrue(restored.ingest(events[32]))
        self.assertEqual(first.snapshot(), restored.snapshot())

    def test_every_social_delta_has_an_event_cause(self):
        for seed in range(1, 21):
            world = RacingWorld(seed, "driver_a")
            events = make_seeded_season(seed)
            for event in events:
                world.ingest(event)
            source_ids = {e.event_id for e in events}
            self.assertTrue(all(e["provenance"] == "simulated" for e in world.events))
            for contact_id, contact in world.contacts.items():
                for axis in ("trust", "respect", "grievance"):
                    trace = [edge for edge in world.ledger.trace_target(contact_id)
                             if edge.variable == axis]
                    self.assertAlmostEqual(sum(edge.delta for edge in trace),
                                           getattr(contact, axis), places=7)
                    self.assertTrue(all(edge.source_id in source_ids for edge in trace))
            for district, value in world.scene.items():
                trace = [edge for edge in world.ledger.trace_target(district)
                         if edge.variable == "scene_standing"]
                self.assertAlmostEqual(sum(edge.delta for edge in trace), value, places=7)
            for offer in world.offers:
                self.assertTrue(all(ref in source_ids for ref in offer.cause_refs))
                self.assertEqual(len(world.ledger.trace_target(offer.offer_id)), 1)

    def test_shared_cast_reacts_by_role_then_private_history_diverges(self):
        events = [RacingEvent(f"result:{i}", i, "race_win", "Heywood", 4,
                              "observed") for i in range(1, 5)]
        a = RacingWorld(5, "driver_a")
        b = RacingWorld(5, "driver_b")
        for event in events:
            a.ingest(event)
            b.ingest(event)
        self.assertEqual(a.events, b.events)
        self.assertEqual(a.scene, b.scene)
        self.assertEqual(a.contacts["npc_03"].trust, b.contacts["npc_03"].trust)
        self.assertLess(a.contacts["npc_03"].trust, 0)  # rival
        self.assertGreater(a.contacts["npc_03"].respect, 0)
        a.ingest(RacingEvent("favor:a", 5, "helped_contact", "Heywood", 4,
                             "observed", "npc_03"))
        self.assertNotEqual(a.contacts["npc_03"].trust, b.contacts["npc_03"].trust)
        self.assertEqual(b.tick, 4)

    def test_direct_help_opens_traceable_offer_and_betrayal_can_reverse_trust(self):
        world = RacingWorld(2, "driver_a")
        fixer = world.contacts["npc_06"]
        home = fixer.home_district
        world.ingest(RacingEvent("help:1", 1, "helped_contact", home, 5,
                                 "observed", fixer.contact_id))
        self.assertGreater(fixer.trust, 25)
        self.assertTrue(any(o.kind == "private_run" and o.cause_refs == ["help:1"]
                            for o in world.offers))
        world.ingest(RacingEvent("betray:1", 2, "betrayed_contact", home, 5,
                                 "observed", fixer.contact_id))
        self.assertLess(fixer.trust, 0)
        self.assertGreater(fixer.grievance, 0)
        self.assertEqual(world.explain(fixer.contact_id, "trust")[0]["source_id"],
                         "betray:1")

    def test_offer_choice_later_result_has_a_causal_path(self):
        world = RacingWorld(2, "driver_a")
        fixer = world.contacts["npc_06"]
        world.ingest(RacingEvent("favor:1", 1, "helped_contact",
                                 fixer.home_district, 5, "observed", fixer.contact_id))
        offer = next(o for o in world.offers if o.kind == "private_run")
        self.assertTrue(world.respond(offer.offer_id, "accept", 2))
        self.assertFalse(world.respond(offer.offer_id, "accept", 2))
        with self.assertRaisesRegex(ValueError, "answered differently"):
            world.respond(offer.offer_id, "decline", 2)
        response_id = f"response:{offer.offer_id}"
        result = RacingEvent("delivery:1", 3, "delivery_completed",
                             fixer.home_district, 4, "simulated",
                             cause_ref=response_id)
        self.assertTrue(world.ingest(result))
        chain = world.ledger.causal_chain("favor:1")
        self.assertTrue(any(e.source_id == response_id and e.target_id == "delivery:1"
                            for e in chain))
        self.assertTrue(any(e.source_id == "delivery:1" and e.variable == "trust"
                            for e in chain))
        restored = RacingWorld.from_snapshot(json.loads(json.dumps(world.snapshot())))
        self.assertEqual(restored.snapshot(), world.snapshot())

        declined = RacingWorld(2, "driver_b")
        declined.ingest(RacingEvent("favor:1", 1, "helped_contact",
                                    fixer.home_district, 5, "observed", fixer.contact_id))
        self.assertTrue(declined.respond(offer.offer_id, "decline", 2))
        with self.assertRaisesRegex(ValueError, "accepted response"):
            declined.ingest(result)

    def test_seed_sweep_has_range_without_mass_saturation(self):
        mean_respect = []
        tags = set()
        saturated = 0
        offerless = 0
        for seed in range(1, 101):
            world = RacingWorld(seed, "driver_a")
            for event in make_seeded_season(seed):
                world.ingest(event)
            values = [c.respect for c in world.contacts.values()]
            mean_respect.append(statistics.mean(values))
            tags.update(c.tag() for c in world.contacts.values())
            saturated += sum(abs(value) >= 99 for value in values)
            offerless += not world.offers
        self.assertGreater(max(mean_respect) - min(mean_respect), 80)
        self.assertLess(saturated, 60)  # below 10% of 600 contact outcomes
        self.assertGreaterEqual(len(tags), 5)
        self.assertLess(offerless, 30)


if __name__ == "__main__":
    unittest.main()
