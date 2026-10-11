"""Night City Chronicles invariants. Run: .venv/Scripts/python -m unittest discover -s tests"""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from ncc.editorial import Editor, coalesce_positions          # noqa: E402
from ncc.epistemics import view                              # noqa: E402
from ncc.memory import Chronicle                             # noqa: E402
from ncc.normalize import Normalizer                         # noqa: E402
from ncc.perform import perform                              # noqa: E402
from ncc.realize import validate                             # noqa: E402
from ncc.stations import STATIONS                            # noqa: E402

NOW = 1_800_000_000


def norm():
    n = Normalizer("t", ["drv-v"], week_steps={"opening": "Welcome to Racing Week."})
    n.ingest("paddock_person", [{"person_id": "p-ilo", "display": "Ilona Vasquez"}, {"person_id": "p-sol", "display": "Sol Brandt"},
                                {"person_id": "p-kat", "display": "Kat Morrow"}])
    n.ingest("paddock_entry", [{"race_id": "r1", "ncm_driver_id": "drv-v", "person_key": "h-v", "series_id": "s", "entered_at": NOW}])
    return n


class Epistemics(unittest.TestCase):
    def test_news_never_names_an_unattributed_hacker(self):
        n = norm()
        truth = n.ingest("chrome_event", [{"event_id": "e", "attacker_driver_id": "p-ilo", "target_driver_id": "p-sol",
                                           "hack": "total_failure", "outcome": "landed", "catastrophic": 1, "occurred_at": NOW}])[0]
        fire = n.ingest("paddock_event", [{"event_id": "vd", "at": NOW, "kind": "vehicle_destroyed",
                                           "entities": '[["person","p-sol"]]', "facts": '{"raceId":"r9","x":1}',
                                           "public_summary": "Sol Brandt's car is destroyed during the race.", "salience": 45,
                                           "provenance": "physical"}])[0]
        for st in STATIONS.values():
            v, _ = view(truth, st, {})
            self.assertIsNone(v, f"{st.id} may not voice the truth ledger of a hack V was not part of")
        v, _ = view(fire, STATIONS["news"], {})
        text = " ".join(v.statements)
        self.assertNotIn("Ilona", text)
        self.assertIn("No cause has been announced", text)

    def test_secrets_are_never_statements(self):
        n = norm()
        f = n.ingest("racing_week_event", [{"run_index": 1, "kind": "step", "ref": "opening", "hours": 0.1,
                                            "data_json": '{"tolerance": 0.61}', "at": NOW}])[0]
        for st in STATIONS.values():
            v, _ = view(f, st, {})
            if v:
                self.assertNotIn("0.61", " ".join(v.statements))
        self.assertEqual([], n.ingest("racing_week_event", [{"run_index": 1, "kind": "sample", "ref": "h1", "hours": 1,
                                                             "data_json": "{}", "at": NOW}]))

    def test_player_target_hears_the_hack_but_not_who(self):
        n = norm()
        f = n.ingest("chrome_event", [{"event_id": "e2", "attacker_driver_id": "p-ilo", "target_driver_id": "h-v",
                                       "hack": "overheat", "outcome": "landed", "catastrophic": 0, "occurred_at": NOW}])[0]
        v, _ = view(f, STATIONS["narrator"], {})
        self.assertNotIn("Ilona", " ".join(v.statements))
        v, _ = view(f, STATIONS["narrator"], {"chrome_attribution": True})
        self.assertIn("Ilona", " ".join(v.statements))


class Validator(unittest.TestCase):
    PK = {"facts": [{"id": "a", "statement": "V finished 4th of 6 in the Watson Street Sprint, having started 5th."}],
          "situation": {"racing_week": 3, "day": 1}}

    def test_good_copy_passes(self):
        self.assertEqual([], validate("On day one of Week Three, V started fifth and finished fourth out of six.", self.PK, False, 60))

    def test_swapped_numbers_fail(self):
        self.assertTrue(validate("V started fourth and finished fifth.", self.PK, False, 60))

    def test_invented_name_fails(self):
        self.assertTrue(validate("V finished fourth, just behind Johnny Silverhand.", self.PK, False, 60))

    def test_gendered_pronoun_fails(self):
        self.assertTrue(validate("V finished fourth; his best yet.", self.PK, False, 60))

    def test_loop_word_fails_until_discovered(self):
        self.assertTrue(validate("V finished fourth, again, as the week resets.", self.PK, False, 60))
        self.assertEqual([], validate("V finished fourth as the week resets.", self.PK, True, 60))


class Editorial(unittest.TestCase):
    def test_dedup_and_memory(self):
        with tempfile.TemporaryDirectory() as d:
            chron = Chronicle(d, "t")
            ed = Editor(chron)
            n = norm()
            rows = [{"race_id": "r1", "person_id": p, "position": i, "grid": g, "state": "finished", "at": NOW,
                     "series_id": "s"} for p, i, g in (("p-kat", 1, 2), ("h-v", 2, 5), ("p-sol", 3, 1))]
            f = n.ingest("paddock_result", rows)[0]
            first = ed.judge(f, NOW + 5)
            self.assertTrue(any(c.selected and c.station.id == "narrator" for c in first))
            again = ed.judge(n.ingest("paddock_result", rows)[0], NOW + 10)
            self.assertFalse(any(c.selected for c in again))
            self.assertIn("DEDUP", again[0].reason)
            self.assertIsNotNone(chron.milestone_text("first_podium"))
            chron.db.close()

    def test_stale_is_silence(self):
        with tempfile.TemporaryDirectory() as d:
            chron = Chronicle(d, "t")
            n = norm()
            f = n.ingest("racing_week_moody", [{"run_index": 1, "roll_n": 1, "d20": 3, "face": "x", "hours": 2,
                                                "data_json": '{"name":"CALM","line":"Something settles."}', "at": NOW}])[0]
            cs = Editor(chron).judge(f, NOW + 99999)
            self.assertFalse(any(c.selected for c in cs))
            self.assertTrue(any("stale" in c.reason for c in cs))
            chron.db.close()

    def test_reversal_is_one_beat(self):
        n = norm()
        rows = [{"race_id": "r1", "person_id": p, "gate": g, "t_ms": t, "source": "pace", "at": NOW + g}
                for g, order in ((1, ["p-kat", "p-sol", "h-v"]), (2, ["h-v", "p-kat", "p-sol"]), (3, ["p-kat", "h-v", "p-sol"]))
                for t, p in ((1000 * g + i, p) for i, p in enumerate(order))]
        pos = n.ingest("paddock_live_crossing", rows)
        self.assertEqual(2, len(pos))
        m = coalesce_positions(pos)
        self.assertTrue(m.truth["reversal"])
        self.assertEqual((3, 1, 2), (m.truth["from_position"], m.truth["best_position"], m.truth["to_position"]))


class Performance(unittest.TestCase):
    def test_measured_controls_only(self):
        p = perform("She took third... and lost it -- two corners later!!!", "narrator", {})
        self.assertNotIn("...", p.script)
        self.assertNotIn("--", p.script)
        self.assertNotIn("!!", p.script)
        self.assertIn(". And", p.script)
        self.assertEqual("She took third... and lost it -- two corners later!", p.transcript)


if __name__ == "__main__":
    unittest.main()
