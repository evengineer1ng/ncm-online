"""Inspect one racing social season and the spread across many seeds."""

import argparse
import statistics
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from racing_world import RacingWorld, make_seeded_season


def run(seed: int, races: int) -> RacingWorld:
    world = RacingWorld(seed, "example_driver")
    for event in make_seeded_season(seed, races):
        world.ingest(event)
    return world


def main() -> None:
    parser = argparse.ArgumentParser(description="Standalone Oracle racing social showcase")
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--events", type=int, default=32)
    parser.add_argument("--sweep", type=int, default=100)
    args = parser.parse_args()

    world = run(args.seed, args.events)
    print(f"Seed {args.seed}: {len(world.events)} simulated racing/social events")
    for contact in world.contacts.values():
        cause = world.explain(contact.contact_id, "respect", 1)
        strongest = (f"{cause[0]['source_id']} ({cause[0]['delta']:+.1f})"
                     if cause else "none")
        print(f"  {contact.name:<16} {contact.role:<11} {contact.tag():<11} "
              f"trust={contact.trust:+6.1f} respect={contact.respect:+6.1f} "
              f"grievance={contact.grievance:+6.1f} "
              f"strongest respect cause={strongest}")
    print("  Scene: " + ", ".join(f"{district} {value:+.0f}"
                                for district, value in world.scene.items()))
    print("  Offers: " + (", ".join(f"{o.kind} from {o.contact_id} via {o.cause_refs[0]}"
                                     for o in world.offers) or "none"))

    if args.sweep:
        means = []
        tags = Counter()
        offerless = 0
        saturated = 0
        for seed in range(1, args.sweep + 1):
            sample = run(seed, args.events)
            values = [contact.respect for contact in sample.contacts.values()]
            means.append(statistics.mean(values))
            tags.update(contact.tag() for contact in sample.contacts.values())
            offerless += not sample.offers
            saturated += sum(abs(value) >= 99 for value in values)
        print(f"Sweep 1-{args.sweep}: mean respect {min(means):+.1f} to "
              f"{max(means):+.1f} (spread {max(means)-min(means):.1f}); "
              f"offerless {offerless}/{args.sweep}; "
              f"saturated contacts {saturated}/{args.sweep*len(world.contacts)}")
        print("  Tags: " + ", ".join(f"{tag}={count}" for tag, count in sorted(tags.items())))


if __name__ == "__main__":
    main()
