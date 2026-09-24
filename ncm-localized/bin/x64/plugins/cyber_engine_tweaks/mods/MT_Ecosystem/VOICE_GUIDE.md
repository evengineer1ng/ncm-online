# NCM Voice Guide

This file turns character vibe into hard constraints.

The rule is simple:

- Seven writers sharing one world.
- No two contacts solve the same player problem in the same way.

## Cast Matrix

| Character | Sentence Pattern | Vocabulary Domain | Info Priority | Relationship | Initiative | Owns | Must Avoid |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Dex | short, clean, neutral | routing, dispatch | routing | dispatcher | entry point | menus, handoff, first-contact clarity | hype, deep analysis, betting seduction, garage talk |
| Quickie Quinn | ultra short, bursty | street, minimal | actionable only | hookup | reactive loop | off-calendar race offers | long setup copy, driver analysis, mechanical advice |
| Foreman | structured, directive | operational | procedural | authority | responsive + state-aware | staging, routing, board state, custom race flow | jokes, rambling, emotional commentary |
| Setup Stu | medium, think-aloud | mechanical, analog | advisory | builder | reactive | car feel, faults, parts, tune direction | betting language, command-board language, ladder analysis |
| Rico | medium-long, composed | analytical + street | interpretive | insider analyst | proactive pushes | field reads, rivals, ladder movement, pressure points | garage fixes, betting seduction, pure hype |
| BookQueen Billie | medium, rhythmic | bookmaker, predatory | risk framing | tempter | opportunistic | odds, slips, contracts, temptation | neutral system phrasing, mechanical jargon |
| #1 Fan | short-medium, punchy | emotional, celebratory | milestone + hype | obsessed supporter | milestone-triggered | celebration, myth-making, audience framing | analysis, procedure, cautionary risk talk |

## Current Read

### Strongest Matches

- Foreman is already the clearest voice. He speaks in state, action, and consequence.
- Rico owns interpretation instead of procedure.
- The #1 Fan relationship is correct when the fallback lines are active.

### Biggest Remaining Risks

- Quinn still drifts into medium-density system copy once an offer is generated.
- Stu can become too clipped and diagnostic if his language starts sounding like Foreman with car nouns.
- Billie still needs rhythm and temptation, not just betting vocabulary.
- Rico should not overuse the same framing device for every read.

## Hard Filters

Run every line through these checks before it lands:

1. Is the sentence shape valid for this character?
2. Is the vocabulary domain valid for this character?
3. Is the information type valid for this character?
4. Is the relationship stance valid for this character?
5. Is the initiative level valid for this character?
6. Is this character solving a problem another contact should own instead?

If any answer is no, rewrite.

## Ownership Rules

- If the player asks what the race feels like, Rico interprets, Foreman structures, Quinn rerolls, Stu deflects.
- If the player asks what the car needs, Stu advises, Rico does not cross lanes, Billie does not pretend to care.
- If the player wants a fast race now, Quinn offers, Foreman stages only once a board exists.
- If the player wants risk, Billie tempts. Rico can mention danger, but he does not price it.
- If the player wins big, the Fan hypes. Rico interprets later. Billie settles paper. Foreman says nothing unless the board changed.

## Test Harness

The CET module exposes a voice harness through the mod table.

Examples:

```lua
GetMod("MT_Ecosystem").VoiceMatrix()
GetMod("MT_Ecosystem").VoiceScenario("need_race")
GetMod("MT_Ecosystem").VoiceExample("need_race")
```

The harness does three things:

- prints the current constraint matrix
- shows scenario ownership expectations
- validates an example bundle for sentence shape, vocabulary leakage, and cross-character similarity

## Target Outcome

Personality should come from constraint, not ornament.

If the same prompt can be handed to every contact and they all answer with the same cadence, the system failed.