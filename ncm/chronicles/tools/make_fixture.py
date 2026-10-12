"""Write fixtures/race_week_demo.jsonl: one compressed Racing Week in NCM's real table shapes.

FIXTURE DATA -- invented people and races, replayed through the same normalizer as the canonical tables; every fact
it yields is sourced 'fixture:<table>'. Times are "@<seconds>" relative to the replay start.

Story it exercises (the brief's live test):
  Week 3 opens (V has lived two before) -> opening PA -> Moody roll -> V enters a Street race ->
  in-race V climbs 5th->3rd then Kat Morrow takes 3rd back (one coalesced beat) -> V classified 4th ->
  elsewhere Sol Brandt's car is destroyed; the truth ledger says Ilona Vasquez uploaded Total Failure, the public
  record does not (News must not name her) -> a WIRE upset -> officials attribute the hack (Race Control) ->
  "we hear you" PA -> an R&D release (Garage) -> V's second race: 2nd behind Kat again (rival memory, first podium)
  -> duplicate rows (dedup) -> noon verdict Day 3 -> the Week collapses (obituary).
"""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SID = "fixture-demo"
out = []


def add(t, table, row):
    row = dict(row)
    row.setdefault("server_id", SID)
    out.append({"t": t, "table": table, "row": row})


PEOPLE = {"p-ama": "Ama Reyes", "p-kat": "Kat Morrow", "p-jun": "Jun Okafor", "p-ilo": "Ilona Vasquez",
          "p-dex": "Dex Hale", "p-sol": "Sol Brandt", "p-mir": "Miro Tanaka"}
for pid, name in PEOPLE.items():
    add(0, "paddock_person", {"person_id": pid, "display": name})
add(0, "paddock_series", {"series_id": "st-watson", "name": "Watson Street Sprint", "tier": "street", "division": 1})
add(0, "paddock_series", {"series_id": "pr-heywood", "name": "Heywood Pro Series", "tier": "pro", "division": 1})
add(0, "paddock_series", {"series_id": "pm-cup", "name": "Night City Premier Cup", "tier": "premier", "division": 1})

add(1, "racing_week_run", {"run_index": 3, "opened_at": "@-20", "start_utc": "@-20", "state_json": {}, "updated_at": "@0"})
add(3, "racing_week_event", {"run_index": 3, "kind": "step", "ref": "opening", "hours": 0.05, "data_json": {}, "at": "@3"})
add(10, "racing_week_moody", {"run_index": 3, "roll_n": 1, "d20": 11, "face": "business_as_usual", "hours": 4.0,
                              "data_json": {"name": "BUSINESS AS USUAL", "kind": "neutral", "line": "No change. The schedule stands."},
                              "at": "@10"})
add(18, "paddock_entry", {"race_id": "pr-st-301", "ncm_driver_id": "drv-v", "person_key": "h-v", "display": "V",
                          "series_id": "st-watson", "state": "entered", "entered_at": "@18"})

# race 301: gate crossings (t_ms from the green). V: 5th at gate 1, 3rd at gate 2, 4th at gate 3.
G = {
    1: [("p-ama", 30000), ("p-ilo", 30400), ("p-jun", 30900), ("p-dex", 31200), ("h-v", 31500), ("p-kat", 31800)],
    2: [("p-ama", 61000), ("p-ilo", 61500), ("h-v", 62000), ("p-kat", 62200), ("p-jun", 62600), ("p-dex", 63100)],
    3: [("p-ama", 90500), ("p-ilo", 91200), ("p-kat", 91900), ("h-v", 92100), ("p-jun", 92600), ("p-dex", 93300)],
}
for g, t0 in ((1, 40), (2, 52), (3, 60)):
    for who, ms in G[g]:
        add(t0, "paddock_live_crossing", {"race_id": "pr-st-301", "person_id": who, "gate": g, "source": "pace",
                                          "t_ms": ms, "at": f"@{t0}"})

RES301 = [("p-ama", 1, 2, "finished"), ("p-ilo", 2, 1, "finished"), ("p-kat", 3, 6, "finished"),
          ("h-v", 4, 5, "finished"), ("p-jun", 5, 3, "finished"), ("p-dex", 6, 4, "finished")]


def results(t, race, rows):
    for pid, pos, grid, state in rows:
        add(t, "paddock_result", {"race_id": race, "person_id": pid, "org_id": "o-x", "series_id": "st-watson",
                                  "season_id": "s1", "cup_id": "c1", "position": pos, "grid": grid, "state": state,
                                  "points": max(0, 10 - pos * 2), "purse": 0, "at": f"@{t}"})


results(100, "pr-st-301", RES301)

# elsewhere: a Pro race car destroyed. Canonical truth: Ilona Vasquez uploaded Total Failure. Public: only the fire.
add(120, "chrome_event", {"event_id": "ce-0001", "attacker_driver_id": "p-ilo", "target_driver_id": "p-sol",
                          "hack": "total_failure", "outcome": "landed", "route": "upload", "catastrophic": 1,
                          "occurred_at": "@119"})
add(121, "paddock_event", {"event_id": "vehicle_destroyed:pr-pro-118:p-sol", "at": "@121", "kind": "vehicle_destroyed",
                           "entities": [["person", "p-sol"]], "cause_refs": [], "effect_refs": [],
                           "facts": {"raceId": "pr-pro-118", "x": -1180.2, "y": 410.7, "z": 18.0},
                           "public_summary": "Sol Brandt's car is destroyed during the race.", "salience": 45,
                           "retain": 0, "provenance": "physical"})
# a WIRE upset in the Premier Cup
add(140, "paddock_event", {"event_id": "upset:pm-cup-77", "at": "@140", "kind": "upset", "entities": [["person", "p-mir"]],
                           "cause_refs": ["race_result:pm-cup-77"], "effect_refs": [],
                           "facts": {"tier": "premier", "winner": "Miro Tanaka", "series": "Night City Premier Cup",
                                     "route": "Corpo Plaza Loop", "fromGrid": 9, "fieldSize": 14, "price": "11.50"},
                           "salience": 85, "retain": 0, "provenance": "simulated"})
add(140, "paddock_news", {"story_id": "upset:pm-cup-77:s", "event_id": "upset:pm-cup-77", "at": "@140", "kind": "upset",
                          "template_id": "upset_v1", "headline": "Miro Tanaka wins the Premier Cup from ninth",
                          "body": "Miro Tanaka took the Night City Premier Cup on the Corpo Plaza Loop from ninth on the grid, at odds of 11.50.",
                          "prominence": 4, "subjects": ["p-mir"]})
# officials attribute the hack
add(165, "paddock_event", {"event_id": "chrome_attack:pr-pro-118:p-ilo:total_failure", "at": "@165", "kind": "chrome_attack",
                           "entities": [["person", "p-ilo"]], "cause_refs": [], "effect_refs": [],
                           "facts": {"hack": "total_failure", "penalty": "dsq", "rules": "pro_strict", "raceId": "pr-pro-118"},
                           "public_summary": "Officials attribute a Total Failure quickhack to Ilona Vasquez.", "salience": 47,
                           "retain": 0, "provenance": "physical"})
add(185, "racing_week_event", {"run_index": 3, "kind": "step", "ref": "we_hear_you", "hours": 22.4,
                               "data_json": {"tolerance": 0.61, "early": False}, "at": "@185"})
add(205, "paddock_event", {"event_id": "rnd-release:zt-ac7", "at": "@205", "kind": "rnd_release", "entities": [],
                           "cause_refs": [], "effect_refs": [], "facts": {"designId": "zt-ac7", "makerKey": "zetatech"},
                           "public_summary": "Zetatech AC-7: 410 N m torque. Base Market price: €$18400.",
                           "salience": 4, "retain": 0, "provenance": "simulated"})

# race 305: V finishes 2nd behind Kat Morrow (second meeting -> rival memory; first podium)
add(225, "paddock_entry", {"race_id": "pr-st-305", "ncm_driver_id": "drv-v", "person_key": "h-v", "display": "V",
                           "series_id": "st-watson", "state": "entered", "entered_at": "@225"})
results(290, "pr-st-305", [("p-kat", 1, 3, "finished"), ("h-v", 2, 4, "finished"), ("p-jun", 3, 1, "finished"),
                           ("p-dex", 4, 2, "finished"), ("p-ama", 5, 6, "finished")])
# duplicates: a re-poll returns race 301's rows and the destroyed-car event again
results(300, "pr-st-301", RES301)
add(301, "paddock_event", {"event_id": "vehicle_destroyed:pr-pro-118:p-sol", "at": "@121", "kind": "vehicle_destroyed",
                           "entities": [["person", "p-sol"]], "cause_refs": [], "effect_refs": [], "facts": {},
                           "public_summary": "Sol Brandt's car is destroyed during the race.", "salience": 45,
                           "retain": 0, "provenance": "physical"})
add(330, "racing_week_event", {"run_index": 3, "kind": "step", "ref": "back_to_sane", "hours": 47.0,
                               "data_json": {"tolerance": 0.22, "early": True}, "at": "@330"})
add(360, "racing_week_verdict", {"run_index": 3, "boundary_h": 72, "kind": "continue", "p": 0.31, "z": -0.4, "u": 0.58,
                                 "state_json": {}, "at": "@360"})
add(400, "racing_week_run", {"run_index": 3, "opened_at": "@-20", "start_utc": "@-20", "state_json": {"deviation": -0.18},
                             "updated_at": "@400", "end_utc": "@400", "end_kind": "collapse", "survived": 4})

os.makedirs(os.path.join(ROOT, "fixtures"), exist_ok=True)
with open(os.path.join(ROOT, "fixtures", "race_week_demo.jsonl"), "w", encoding="utf-8", newline="") as f:
    f.write("// FIXTURE: invented people and races in NCM's table shapes (tools/make_fixture.py)\n")
    for o in sorted(out, key=lambda d: d["t"]):
        f.write(json.dumps(o, ensure_ascii=False) + "\n")
print(len(out), "rows")
