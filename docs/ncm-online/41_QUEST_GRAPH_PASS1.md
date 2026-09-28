# NCM Online --- Quest Graph Conversation Trees & Triggers

## Authoring Pass 1: Opening Constellation + First Expansion Web

**Status:** Narrative/quest-graph authoring draft\
**Purpose:** Turn the current character research into concrete trigger
logic, message trees, soft-shut/re-entry behavior, persistent character
loops, and first payoffs.\
**Implementation status:** Design only. Thresholds marked `TUNE` are
authoring values, not final balance constants.

> **STATUS: SPEC** - owner authoring intent. Covers: *the quest graph, character conversation trees and their
> triggers*. Authority map: [INDEX.md](INDEX.md).
>
> **PARTLY AUTHORISED, 2026-09-28 (`L183`).** The owner authorised the first slice -- **Dex, Setup Stu and
> Rico** (Appendix A.8) -- and it is built: core `graph.contacts` / `graph.conversation` / `graph.opening`,
> migration 039, `ncm_league/server/graph.lua`, and the Messages surface in the F6 shell. **Everything else in
> this document remains SPEC and is still not authorised to build.** `graph.contacts` carries the reason for each
> of the fifteen unauthored contacts, so the block list is code rather than prose. Where this draft and the shipped
> behaviour differ, Appendix A states the difference and `L183` states the ruling; the draft's text above the
> appendix is still **preserved unchanged**.
>
> **Source:** `NCM_Quest_Graph_Conversation_Trees_Pass1.md`, supplied 2026-09-27 and **preserved unchanged**
> below. Everything from "APPENDIX A" onward was added by reconciliation against the shipped code and the
> platform, and is clearly separated from the authoring draft. Where the two disagree, the appendix states the
> disagreement rather than editing the draft.

------------------------------------------------------------------------

## 0. Core Authoring Rules

### 0.1 The graph reacts to a life, not a level

Characters should usually appear because the player's behavior made them
relevant. A badge may be supporting evidence, but a character should not
normally appear merely because `badge_x = unlocked`.

The core question for every contact is:

1.  **What did the player do that made this person care?**
2.  **Why should the player care that this person appeared?**

### 0.2 Decline is a soft-shut door

A declined introduction closes **that offer in that moment**, not the
entire character.

Re-entry can come from: - the player reopening an old conversation; - a
contextual Dex shelf item; - a new world event that gives the contact a
fresh reason to matter; - another character mentioning the same
person; - physical discovery; - a system milestone that creates a
materially different offer.

### 0.3 Messages are state projections

Conversation choices are not a fixed dialogue tree. The visible choices
should be projected from current player/world state.

### 0.4 Characters have domains

**Dex knows NCM. Specialists know their domains.**

Dex can explain whether weather matters. Stu explains why *this car* is
behaving differently in rain. Dex can explain what a market is. Rico can
tell you who may be moving unusual hardware. Dex redirects instead of
impersonating expertise.

### 0.5 Individual messages stay short

Trees may be deep. Leaves should not be novels.

### 0.6 Not every contact needs a daily loop

Some contacts are persistent systems. Some are occasional narrative
surfaces. Silence is allowed.

### 0.7 Cross-character telemetry is desirable

Characters may react to behavior performed through another character.
This is one of the primary tools for making the social web feel alive.

Example: repeatedly asking Stu about parts can cause Rico to notice and
introduce Needle.

------------------------------------------------------------------------

# 1. Opening Constellation

The legacy seven establish the grammar of the entire graph.

  -----------------------------------------------------------------------
  Contact                 Discovery grammar       Primary role
  ----------------------- ----------------------- -----------------------
  Dex / NCM Dispatch      Unmissable system       Generalist, onboarding,
                          contact                 help, routing

  Setup Stu               Guaranteed Dex handoff  Car/setup/parts
                                                  specialist

  Quickie Quinn + Foreman Optional Stu referral   Player-created race
                                                  tutorial + flavor

  Rico                    Strongly surfaced,      Scout, intelligence,
                          freely deferred Dex     social connector
                          referral                

  Book Queen Billie       Rico                    Wagering relationship /
                          contact-of-a-contact    risk economy

  #1 Fan                  Emergent world-state    Telemetry-reactive
                          intrusion               personal relationship
  -----------------------------------------------------------------------

------------------------------------------------------------------------

# 2. Dex / NCM Dispatch

## 2.1 Unlock

**Trigger:** First NCM session after onboarding eligibility.

**Presentation:** Unmissable, not mandatory. Dex's message should be
surfaced prominently, but the player retains control over how deeply
they engage.

## 2.2 Opening message

**DEX · NCM DISPATCH**

> You're through to NCM. I'm Dex, Dispatch. If you get turned around,
> send it here and I'll point you at the right line.
>
> I put Setup Stu in your contacts. He handles the machine: parts,
> setup, what you've got underneath you. Start there.
>
> One other thing. I know a guy named Rico. Knows who's running, what's
> moving around the city, and usually hears things before I do. Want the
> introduction?

**Player choices** - `Put me through.` - `Not now.`

### Put me through

Set: - `rico_intro_offered = true` - `rico_intro_accepted = true` -
`rico_known = true`

Dex: \> I'll tell him you're expecting the line.

Queue Rico opening.

### Not now

Set: - `rico_intro_offered = true` - `rico_intro_deferred = true`

Dex: \> Your call. If you change your mind, ask.

No nag timer.

------------------------------------------------------------------------

## 2.3 Dex top-level state after Rico deferral

**Visible choices** - `I have a question.` - `Actually, about Rico...`

The second choice remains highly visible until Rico is known. This is
deliberate soft guidance, not a quest requirement.

### Actually, about Rico...

Dex: \> What about him?

Choices: - `Who is this guy?` - `What does he actually do?` -
`Put me through.` - `Never mind.`

**Who is this guy?**

Dex: \> Scout. Fixer when he needs to be. Knows drivers, crews, shops,
people who don't advertise. If he doesn't know somebody, he usually
knows somebody who does.

Choices return to Rico submenu.

**What does he actually do?**

Dex: \> Finds things out. People, cars, hardware, races. Doesn't mean
he's right about everything. Means he usually knows where to start.

**Put me through.**

Dex: \> I'll tell him you're expecting the line.

Unlock Rico.

------------------------------------------------------------------------

## 2.4 Dex Questions hub

Dex: \> What about?

### Context shelf

This appears **above** generic categories when applicable.

Examples: - `Who's Rico?` - `Stu mentioned Quinn and Foreman.` -
`Who is Book Queen Billie?` - `What's Needle's problem?` -
`Why did I get a message from Glass?` - `Who's Zero?`

The shelf is state-driven and contains unresolved people/things already
legitimately known to the player.

### Generic categories

-   `How do races work?`
-   `Tell me about cars and parts.`
-   `How does money work around here?`
-   `What's the deal with markets?`
-   `What can I do when nobody else is around?`
-   `What are Discovery and the Machine Index?`
-   `Something else.`

### Domain boundary examples

**Player:** `Does weather affect racing?`

Dex: \> Yes. Conditions can change what the road and the car give you.
If you're asking why *your* setup is doing something weird in it, ask
Stu.

**Player:** `Why doesn't this part fit my car?`

Dex: \> That's a Stu question. Want me to open his line?

Action: - `Open Setup Stu` - `Stay here`

**Player:** `What's the Base Market?`

Dex: \> Public starting point. Cars, parts, the stuff NCM can put in
front of anybody. It isn't the only place hardware moves in this city.

**Player:** `Are there other markets?`

Dex: \> Yes. Most don't advertise to everybody. You'll hear things, find
things, meet people.

Do not reveal total market count.

------------------------------------------------------------------------

## 2.5 Dex landmines

Most questions are just questions. A few can reveal social edges when
player state makes the answer more interesting.

### Landmine: Zero

Conditions: - player has meaningful solo practice / ghost activity
(`TUNE`); - Zero not known; - player asks a
practice/time-trial/solo-racing question.

Dex: \> Actually, somebody asked me about your times the other day.

Choices: - `Who?` - `That's weird.` - `Forget it.`

`Who?` opens Zero introduction.

### Landmine: Research specialist

Conditions: - meaningful Machine Index / research / Discovery engagement
(`TUNE`); - research specialist not known; - player asks a sufficiently
deep research question.

Dex: \> You're asking better questions than I can answer. Want somebody
who does this for a living?

Choices: - `Yeah.` - `Who are they?` - `Not right now.`

------------------------------------------------------------------------

# 3. Setup Stu

## 3.1 Unlock

**Trigger:** Dex opening automatically places Setup Stu in Contacts.

Stu is the guaranteed specialist handoff.

## 3.2 First contact

Stu: \> Dispatch says you're driving with us now. I'm Stu. If it bolts
on, changes how the car behaves, or makes you wonder why the hell it
suddenly hates a corner, that's my desk.

Player choices: - `Good to know.` - `Take a look at what I'm driving.` -
`I'm keeping it simple for now.`

### Context response

If meaningful build data exists, Stu may comment on it.

Coherent early build: \> Huh. Somebody thought before they bought parts.
That's rarer than you'd think.

Questionable build: \> You've got an idea there. Not sure you've got the
*right* idea, but you've got one.

Stock/simple: \> Nothing wrong with stock. At least I know what I'm
looking at.

------------------------------------------------------------------------

## 3.3 Second beat: Quinn + Foreman handoff

After the player has replied once to Stu's introduction:

Stu: \> One more thing. If you ever want to put something together
yourself instead of waiting on the board, I know two guys.

Player: - `Put something together?` - `Who?` - `Maybe later.`

### Put something together?

Stu: \> Race. Quick one, serious one, whatever. Quinn and Foreman handle
that circus.

Choices: - `Send me their line.` - `Maybe later.`

Accept: - unlock `Quickie Quinn + Foreman` group chat.

Defer: - set `qf_intro_deferred = true` - Stu may expose
`About those race guys...` later. - Dex may eventually explain
player-created races generally, but should not steal their tutorial.

------------------------------------------------------------------------

## 3.4 Stu persistent conversation model

Potential state-projected choices: - `Take a look at my setup.` -
`What do you think of this part?` - `What's my weakest area?` -
`Why is the car doing this?` - `Tell me about tires.` -
`What should I change next?` - `Where do people find better parts?`

Stu owns specialist explanations. Dex redirects here.

### Telemetry for Needle

Increment a hidden **hardware curiosity** score for substantive Stu
interactions involving: - part evaluation; - upgrade sourcing; -
weakest-axis analysis; - tire/component questions; - repeated build
review; - requests for better/unusual hardware.

This score is not a quest meter shown to the player.

When threshold is reached and Rico is known, Rico may react. See Needle.

------------------------------------------------------------------------

# 4. Quickie Quinn + Foreman

## 4.1 Unlock

Via Stu referral.

## 4.2 Group chat opening

**QUINN** \> okay easiest thing in the world\
\> pick where you're going\
\> pick who's coming\
\> GO

**FOREMAN** \> No.

**QUINN** \> yes

**FOREMAN** \> A race requires a defined course, eligibility, field
configuration, start procedure, session structure and---

**QUINN** \> OR\
\> road\
\> cars\
\> GO

Player choices: - `I'm with Quinn.` - `I'm with Foreman.` -
`You're both describing the same thing, aren't you?`

### I'm with Quinn

Quinn: \> THANK YOU

Foreman: \> Quinn's "quick race" is a configured event with most
parameters left at standard values.

Quinn: \> sounds quick to me

### I'm with Foreman

Foreman: \> Good. Defaults are useful. Understanding them is better.

Quinn: \> counterpoint: race car now

### Same thing?

Foreman: \> Technically, yes.

Quinn: \> emotionally, no

------------------------------------------------------------------------

## 4.3 Tutorial choices

State-projected questions can include: -
`How do I start a quick race?` - `How do I invite somebody?` -
`What can I customize?` - `Can I charge an entry fee?` -
`How do laps work?` - `How do starts work?` - `Can I save this setup?`

Quinn gives the low-friction answer. Foreman adds precision/caveats.

## 4.4 Long-term activity

No heavy persistent gameplay system is required.

Allowed reactivation: - system update affecting race construction; - new
race-creation feature; - new format/default; - occasional low-frequency
flavor argument.

Example flavor event after meaningful account age (`TUNE`), no gameplay
consequence:

Quinn: \> foreman says a race needs a finish line

Foreman: \> It does.

Quinn: \> coward

Do not spam. Months of silence are acceptable.

------------------------------------------------------------------------

# 5. Rico

## 5.1 Unlock

Primary route: Dex introduction.

Secondary re-entry routes can appear later if deferred, but Rico remains
the strongest item on Dex's unresolved shelf until known.

## 5.2 Opening

Rico: \> Dispatch says you're new to the board. Fine. First one's free.

If current/upcoming race intelligence exists: \> Guy two rows up has
been starting fast and finishing ugly. Don't get boxed behind him.

If no useful live race context: \> First thing to know: what's on the
board isn't everything that's moving in this city.

Player choices: - `What exactly do you do?` - `What else is moving?` -
`Thanks, I guess.`

Rico establishes himself as motorsport intelligence, **not Market Guy**.

------------------------------------------------------------------------

## 5.3 Rico persistent model

Potential choices: - `Heard anything interesting?` -
`Anything about my next race?` - `Know anybody I should know?` -
`What are people saying about [known lead/person]?` - contextual
unresolved leads.

Rico can also push information based on telemetry.

------------------------------------------------------------------------

## 5.4 Billie introduction

### Eligibility

Any one or combination of (`TUNE`): - player has completed several
eligible contested races; - meaningful race-money activity; -
streak/upset/interesting competitive pattern; - player asks Rico about
making money/risk/underground race business.

Rico: \> You ever bet on yourself?

Player: - `Isn't racing on yourself already betting on yourself?` -
`With who?` - `No.`

If first: Rico: \> Cute. I mean money.

Then: \> I know a book.

Player: - `Who's running it?` - `Put me in touch.` - `Not interested.`

Who's running it: \> Billie. If she likes you, Book Queen Billie. If she
doesn't, probably still Book Queen Billie.

Accept unlocks Billie.

Defer leaves a Rico shelf item: - `About that book...`

------------------------------------------------------------------------

# 6. Book Queen Billie

## 6.1 Unlock

Canonical route: Rico introduction.

Billie is a **persistent wagering relationship**, not a conventional
quest chain.

## 6.2 Opening

Billie: \> Rico says you can drive.

Player: - `Rico says a lot.` - `He says you take bets.` -
`Depends who's asking.`

Billie: \> I take positions. Sometimes they're yours.

Then the wagering surface becomes available according to the final
multiplayer economics model.

------------------------------------------------------------------------

## 6.3 Relationship variables

Track, at minimum: - total settled wagers; - total amount wagered; -
total won; - total lost; - net; - largest win; - largest loss; - streak
behavior; - accepted/declined Billie offers; - settlement
integrity/provenance.

Relationship depth should be driven primarily by **money moved through
Billie**, not total player wealth.

## 6.4 Message behavior

Billie can react to: - a large win; - catastrophic loss; - repeated
conservative play; - repeated aggressive play; - unusual upset; - long
absence after heavy betting; - reaching private-client thresholds.

Examples:

Large win: \> Don't spend it all in one garage.

Large loss: \> You paid for information. Expensive information, but
still.

Repeated caution: \> You know the point is to risk some of it, right?

## 6.5 Payoff branch: private money circle / market

At a sufficiently deep relationship (`TUNE`):

Billie: \> You've pushed enough paper through my book that people have
started asking who you are.

Player: - `Who?` - `Good things?` - `What did you tell them?`

Billie: \> I said maybe.

This creates a Lead toward a private/high-money automotive market or
social circle. Billie does not simply hand over a shop URL.

------------------------------------------------------------------------

# 7. #1 Fan

## 7.1 Unlock

Nobody introduces #1 Fan.

Eligibility begins only after the player has enough history for the
contact to plausibly care (`TUNE`).

Qualifying events can include: - notable win; - deep-grid recovery; -
many overtakes; - unusual clean performance; - record; - repeated use of
one car; - spectacular failure; - another telemetry event worth reacting
to.

Avoid a fixed "Race 5 = Fan" rule.

## 7.2 First intrusion

#1 FAN: \> HOLY SHIT

Player: - `...who is this?` - `Yeah?` - `Wrong number.`

Fan response should reference the actual qualifying event.

Example: \> P8. Seven passes. P1. Don't "wrong number" me, I HAVE EYES.

If player asks: \> How did you get this number?

Fan: \> anyway

Never fully answer.

------------------------------------------------------------------------

## 7.3 Tone progression

1.  enthusiastic stranger;
2.  alarmingly attentive racing fan;
3.  remembers obscure details;
4.  weirdly personal but benign;
5.  eventually trusted/affectionate oddball.

The character is creepy **in behavior**, not secretly malicious.

If rebuffed strongly: - suppress for a substantial interval (`TUNE`); -
allow an exceptional future telemetry event to break silence.

Fan: \> okay I KNOW you told me to stop messaging you BUT WHAT THE FUCK
WAS THAT

------------------------------------------------------------------------

## 7.4 Persistent reactions

Possible hooks: - new car; - return to old favorite car; - milestone
mileage; - dramatic race; - repeated qualifying pattern; - unusual
win; - long absence; - rare vehicle acquisition.

Example:

Fan: \> NEW CAR?????

Player: \> How do you know that already?

Fan: \> :(

Player: \> That wasn't an answer.

Fan: \> CONGRATS ON THE CAR

------------------------------------------------------------------------

## 7.5 Physical payoff

After a long relationship (`TUNE`):

Fan: \> okay\
\> don't freak out

Then: \> i found something you're going to lose your mind over\
\> meet me?

Player: - `Fine. Where?` - `This sounds like how people get murdered.` -
`Not yet.`

The meeting is deliberately player-initiated.

### Preferred visual gag, capability-dependent

If technically possible, #1 Fan appears wearing the player's current
clothing/appearance set as closely as the NPC appearance APIs allow.

Player: \> Why are you dressed like me?

Possible Fan response: \> Wait. Is this weird?

This is a preferred authoring beat, **not assumed technically
available**.

#1 Fan remains primarily a one-to-one relationship. Do not turn them
into a generic social router.

------------------------------------------------------------------------

# 8. Needle

## 8.1 Why Needle cares

Needle is triggered by **the player's excessive interest in parts
through Setup Stu**.

This is cross-character telemetry.

Eligibility: - Rico known; - Needle unknown; - hardware-curiosity score
through Stu exceeds `TUNE`; - cooldown prevents immediate trigger after
Stu conversation.

Rico pushes:

> You ask a lot of questions about hardware.

Player: - `How do you know that?` - `I like knowing what I'm buying.` -
`And?`

### How do you know that?

Rico: \> Ears everywhere. Don't worry about it.

Then: \> Anyway. Stu can tell you what a part does. I know somebody who
can tell you where the interesting ones come from.

Player: - `Who?` - `I'm listening.` - `Not right now.`

Rico: \> Needle.

Optional: \> Don't tell them I called them that.

------------------------------------------------------------------------

## 8.2 Needle opening

Needle should not immediately become a menu vendor.

Initial message: \> Rico says you ask questions.

Player: - `Apparently everybody knows that.` - `About parts, yeah.` -
`Depends who's asking.`

Needle: \> Questions are cheap. Knowing what to do with the answer
isn't.

Needle arranges a physical meeting when supported.

------------------------------------------------------------------------

## 8.3 Trust test

Needle can set a condition that occurs through normal NCM play rather
than spawning a conventional quest instance.

Example: \> Run your next three. Put one on the podium. Don't turn the
car into scrap. Then maybe I tell you something useful.

Exact condition should be selected from supported telemetry and can
vary.

No quest-marker spam. The system silently watches.

On success: \> Fine. Rico wasn't completely full of shit.

On failure: Needle need not instantly fail the thread. They can react:
\> Not exactly the demonstration I had in mind.

Then offer another chance after cooldown or a modified condition.

## 8.4 Payoff

Needle eventually creates: - a Lead to a parts-oriented hidden market; -
access to unusual sourcing; - a future relationship with a parts
supplier/operator.

Needle is **not necessarily the market operator**.

### Stu cross-reaction

After Needle becomes known:

Stu: \> Needle?

Player: - `You know them?` - `Rico sent me.`

Stu: \> Rico sent you to *Needle?*

This should lead to professional opinion, not a new unlock by default.

------------------------------------------------------------------------

# 9. Glass

## 9.1 Unlock

Glass is not normally introduced.

Eligibility: - multiple unresolved Leads (`TUNE`); - meaningful Rico
activity and/or information-seeking behavior; - Glass unknown.

Glass: \> Rico gives away too much.

Player: - `Who is this?` - `You listening to my messages?` -
`Then why are you talking to me?`

### Who is this?

Glass: \> Someone who doesn't.

### Listening?

Glass: \> If I were, you wouldn't need to ask.

Keep Glass opaque.

## 9.2 System

Glass trades **information advancement**, not direct access.

Possible transactions: - money for a clue; - clue for clue; - confirm
provenance; - identify district; - identify manufacturer; -
validate/deny rumor; - exchange a discovered fact for another.

Example state: `Unknown supplier in Santo Domingo`

Glass can advance to: `Supplier activity reported near Arroyo`

Glass should rarely collapse a mystery directly into access.

## 9.3 Relationships

-   Rico distrusts Glass.
-   Billie knows Glass.
-   Glass's information can occasionally be correct but incomplete;
    avoid arbitrary lying unless authored and recoverable.

## 9.4 Payoff

Information routes unavailable through friendly networks, faster lead
resolution, unusual provenance, and access to deeper graph edges.

------------------------------------------------------------------------

# 10. Knuckles

## 10.1 Role

Knuckles is the missing PvE rival personality in a world without a
physically simulated AI rival.

Knuckles competes **asynchronously** through measurable accomplishments.

## 10.2 Unlock

Eligibility from player performance patterns (`TUNE`), not merely a
Rival badge.

Potential triggers: - strong time on a known course; - repeated
wins/podiums; - impressive recovery; - exceptional clean/fast
performance; - enough career history to support meaningful challenges.

Knuckles: \> Heard you were getting quick.

Player: - `Who is this?` - `Heard right.` -
`Whoever told you that lied.`

Who is this: \> Somebody quicker.

## 10.3 Challenge loop

Knuckles claims an authored/simulated accomplishment. Player telemetry
determines whether it is beaten.

Examples:

> Just put down a 2:14.8 on \[course\]. Beat it.

> Three wins this week. Your turn.

> Won from P8 yesterday. You ever done better than that?

> Rain. \[course\]. 2:31. Don't bother replying until you beat it.

On player success:

> ...

Then: \> track was faster today

Or: \> Fine. Do it in a Galena.

Knuckles moves the goalposts, but not so aggressively that success feels
meaningless.

## 10.4 Challenge families

-   lap/time;
-   wins in window;
-   podiums;
-   clean result;
-   overtakes;
-   class/car constraint;
-   weather;
-   start-to-finish gain;
-   distance/endurance;
-   build/economic constraint.

## 10.5 Payoff

-   persistent rival relationship;
-   challenge rewards;
-   eventual access to a competitive circle/event/market;
-   possible physical meeting later.

Knuckles does not require an AI car to pretend a live race occurred.

------------------------------------------------------------------------

# 11. Flashbulb

## 11.1 Role

Flashbulb belongs to the **Scanner / Machine Index / automotive
spotting** side of NCM, not photo mode.

## 11.2 Unlock

Eligibility from scanning behavior (`TUNE`): - many vehicle scans; -
unusual/rare scan; - meaningful Machine Index discovery; - repeated
scanning across regions/types.

Flashbulb: \> You scan everything?

Player: - `Who is this?` - `Pretty much.` -
`Only the interesting stuff.`

Who is this: \> Somebody who appreciates thoroughness.

## 11.3 Persistent loop

Flashbulb supplies **vehicle spotting leads**.

Example: \> Heard something unusual has been showing up around
Northside. Haven't gotten eyes on it yet.

No exact waypoint by default.

Player explores and scans.

On correct identification: \> That's it. Send me what you got.

## 11.4 Payoff

-   Machine Index intelligence;
-   vehicle/location clues;
-   rare configuration leads;
-   manufacturer information;
-   eventual vehicle-oriented market/contact;
-   automotive scene/world knowledge.

## 11.5 Sunday relationship

Flashbulb documents machines. Sunday preserves their histories.

Flashbulb: \> Cars are meant to be seen.

Sunday: \> Cars are meant to survive people like Flashbulb.

------------------------------------------------------------------------

# 12. Mara Velez

## 12.1 Unlock

Mara notices **variety**, not raw win count.

Eligibility (`TUNE`): - multiple disciplines/formats; - multiple
cars/classes; - multiple regions; - enough race history to establish a
pattern.

Rico: \> Somebody's been asking who's driving everything lately.

Player: - `Who?` - `That sounds ominous.`

Rico: \> Mara Velez. She puts fields together when the normal board
isn't interesting enough.

Player: - `Put us together.` - `What kind of fields?` - `Not yet.`

## 12.2 Mara opening

Mara: \> Rico says you'll drive anything.

Player: - `If it has wheels.` - `Depends who's paying.` -
`He exaggerates.`

Mara: \> Good. Specialists are easy to book. I need people who don't
panic when the rules change.

## 12.3 System

Mara offers authored/special events: - one-make races; - unusual
eligibility; - manufacturer showcases; - experimental formats; -
last-minute seat/fill-in; - invite-only events.

## 12.4 Payoff

-   special event pipeline;
-   organizer/team/manufacturer introductions;
-   unusual race opportunities.

Mara does **not** replace Quinn/Foreman. They teach creation. Mara
supplies curated opportunities.

------------------------------------------------------------------------

# 13. Sunday

## 13.1 Unlock

Sunday cares about **the story of a machine**, not player skill.

Eligibility (`TUNE`) can derive from: - very high mileage on one
chassis; - long retention of starter/early car; - rare variant; - traded
vehicle with meaningful provenance; - unusual ownership history; -
restored/preserved machine if such systems exist.

Sunday may contact directly once provenance is sufficient:

> Don't sell that car.

Player: - `Wasn't planning to.` - `Why?` - `Make me an offer.`

### Why?

> Because most people see the model. I see where it's been.

### Make me an offer

Sunday may make one only if the economy supports it; otherwise: \>
That's not why I called.

## 13.2 System

Sunday can care about: - mileage; - owner history; - provenance; - rare
configurations; - preservation; - unusual vehicles; - long-term
attachment.

## 13.3 Payoff

-   collector market/circle;
-   rare vehicle leads;
-   provenance-focused opportunities;
-   restoration/history threads;
-   tempting purchase offers where supported.

Sunday should not become another performance NPC.

------------------------------------------------------------------------

# 14. Patch

## 14.1 Unlock

Patch is discovered through **mechanical adversity / making do**, not
simply poverty.

Possible triggers (`TUNE`): - repeated DNFs; - repeated low-cost
builds; - salvage-like ownership behavior; - poor financial state
combined with car needs; - persistent use of compromised/low-tier
hardware.

Potential Stu route: \> I know somebody who can keep that thing moving.
You're not going to like where the parts come from.

Potential direct route: Patch: \> Heard you've been killing cars.

Player: - `Who told you?` - `That's exaggerated.` - `Can you help?`

Patch: \> Cars talk.

## 14.2 Philosophy

> New parts are for people who enjoy paying for packaging.

Patch should be practical, not pitying.

## 14.3 Payoff

-   salvage-oriented market;
-   used/odd hardware;
-   cheap parts with meaningful tradeoffs;
-   unusual provenance;
-   junkyard engineering branch.

A wealthy player may discover Patch through another route. Adversity is
a door, not a class restriction.

------------------------------------------------------------------------

# 15. Zero

## 15.1 Unlock

Zero cares about **laps**, not race results.

Eligibility (`TUNE`): - repeated solo practice; - ghost chasing; -
repeated route attempts; - meaningful time improvement; - enough
activity on a course for Zero's comment to be credible.

Primary discovery can be a Dex landmine.

Zero: \> Turn 6. You're braking too early.

Player: - `Who the fuck are you?` - `No I'm not.` -
`How much too early?`

Who are you: \> Somebody who's watched that corner longer than you have.

## 15.2 System

-   time challenges;
-   obscure route knowledge;
-   alternate configurations;
-   ghost-oriented challenges;
-   route mastery;
-   solo-driver content.

## 15.3 Payoff

-   obscure courses;
-   alternate layouts;
-   time-attack world;
-   location knowledge outside the obvious race network.

------------------------------------------------------------------------

# 16. Research Specialist --- Working Name: Dr. Vale

**Name is provisional.**

## 16.1 Unlock

Triggered by research/Machine Index/Discovery behavior and optionally
surfaced through Dex when the player's question exceeds Dex's generalist
domain.

Dex: \> You're asking better questions than I can answer. Want somebody
who does this for a living?

Accept unlocks Dr. Vale.

## 16.2 Opening

Vale: \> Dex says you've been cataloguing things instead of just driving
past them. Good habit.

Player: - `I like knowing what I'm looking at.` -
`I'm looking for something specific.` - `Mostly curiosity.`

## 16.3 System

Vale is interested in: - unknown parts; - unusual vehicles; - incomplete
Machine Index knowledge; - provenance; - research submissions; -
unexplained configurations.

Avoid generic fetch-quest structure. Prefer: \> Bring me / tell me about
things the simulation already says the player encountered.

## 16.4 Payoff

-   deeper research tools;
-   specialized knowledge;
-   manufacturer contacts;
-   engineering opportunities;
-   unusual leads.

------------------------------------------------------------------------

# 17. Auntie

## 17.1 Unlock

Physical exploration.

No Dex. No Rico. No milestone popup.

Player enters/approaches an authored location and meets Auntie.

Auntie: \> You lost?

Player: - `Looking for parts.` - `Just looking around.` - `Probably.`

## 17.2 Branch tone

### Looking for parts

> Depends what kind. If you say "fast" I'm charging you extra.

### Just looking around

> Then look with your eyes and keep your hands where I can see them.

### Probably

> Honest. That's a start.

## 17.3 Payoff

-   neighborhood automotive network;
-   local mechanics;
-   practical parts;
-   everyday vehicles;
-   market access/lead.

Auntie proves the graph exists in geography, not only Messages.

------------------------------------------------------------------------

# 18. Dave

## 18.1 Role

Dave runs a parking structure.

No secret title. No legendary reputation. Dave has gossip because cars
and people pass through.

## 18.2 Unlock

Incidental physical encounter: - vehicle storage/retrieval; - another
character chooses the garage as a meeting point; - exploration; -
mundane service interaction.

Dave: \> You leaving that here or just blocking my ramp?

Player: - `Leaving it.` - `Five minutes.` - `You Dave?`

## 18.3 System

Dave gradually becomes useful through ordinary observations: - mechanics
who come through; - delivery drivers; - collectors; - stored vehicles; -
odd-hour visitors; - abandoned machines; - neighborhood gossip.

Dave should not call this "intel."

## 18.4 Payoff

A mundane social connector capable of creating surprising graph edges
without becoming another cyber-noir information broker.

------------------------------------------------------------------------

# 19. First Expansion Relationship Map

``` text
Dex
├── Setup Stu
│   └── Quickie Quinn + Foreman
├── Rico
│   ├── Book Queen Billie
│   │   └── private-money / market lead
│   ├── Needle  ← triggered by excessive Stu hardware curiosity
│   │   └── parts-market lead
│   └── Mara Velez
│       └── special events / organizers / teams
├── Zero        ← contextual Dex landmine
└── Dr. Vale    ← contextual Dex landmine

World-state emergence
├── #1 Fan      ← memorable player history
├── Glass       ← unresolved leads / information behavior
├── Knuckles    ← competitive performance
├── Flashbulb   ← Scanner / Machine Index behavior
├── Sunday      ← vehicle history / provenance
└── Patch       ← adversity / salvage behavior

Physical discovery
├── Auntie
└── Dave
```

Cross-links: - Rico distrusts Glass. - Billie knows Glass. - Needle
thinks Rico talks too much. - Stu knows Needle professionally. - Stu
dislikes at least some of Patch's sourcing but respects capability. -
Sunday thinks Patch destroys history. - Patch thinks Sunday hoards
usable machinery. - Flashbulb and Sunday disagree about
documentation/display versus preservation. - #1 Fan remains
intentionally personal and does not become a generic router.

------------------------------------------------------------------------

# 20. Trigger Budget / Anti-Spam Rules

The world should feel alive without becoming a group chat that drank six
energy drinks.

Recommended authoring rules:

1.  **Never fire multiple new-character introductions simultaneously.**
2.  Maintain a narrative introduction cooldown (`TUNE`).
3.  High-priority direct consequences may bypass flavor cooldowns.
4.  Flavor messages should lose to meaningful gameplay messages.
5.  Deferred contacts should not nag on timers. Re-surface through
    player action or materially new context.
6.  Character flavor should have long cooldowns and permanent/long-lived
    dedup keys.
7.  Allow silence.
8.  A character with a persistent system can speak frequently only when
    the player is actively using that system.
9.  Group-chat flavor from Quinn/Foreman should be especially sparse.
10. #1 Fan may occasionally violate normal decorum, but not notification
    budgets.

------------------------------------------------------------------------

# 21. Authoring Variables to Formalize Later

This draft intentionally uses `TUNE` rather than inventing balance
constants. A later pass should map triggers onto actual NCM telemetry
and badge definitions.

Needed telemetry map: - race count / eligible contested race count; -
wins / podiums / starting and finishing positions; - overtakes /
incidents / clean flags; - route and discipline variety; - weather and
time-of-day participation; - solo practice count / ghost activity / lap
improvements; - vehicle ownership duration / mileage / provenance; -
parts installed / build review / Stu question categories; - Scanner
activity / Machine Index discoveries; - research submissions / Discovery
state; - balance/economic adversity where appropriate; - Billie wagering
ledger; - unresolved Leads; - market knowledge/access; -
character-contact history; - message decline/defer state; - physical
location discovery.

------------------------------------------------------------------------

# 22. Pass 2 Targets

This first pass establishes the cast, triggers, first trees, re-entry
rules, and primary payoffs.

**Pass 2 should deepen rather than widen.** Recommended targets:

-   complete Dex FAQ tree with short authored answers;
-   full Setup Stu state-projected question tree;
-   full Rico intelligence tree and first 3--5 reactive pushes;
-   Book Queen Billie wagering conversation states once multiplayer
    economics are pinned;
-   complete Quinn/Foreman race-creation tutorial against the actual
    final race-creation controls;
-   #1 Fan reaction library;
-   Needle trust-test variants;
-   Knuckles challenge library and simulated-result provenance rules;
-   Flashbulb Scanner hunt library;
-   exact first hidden-market thread from trigger through access;
-   badge/telemetry crosswalk to prevent duplicate rewards;
-   message priority/cooldown/dedup table;
-   exact physical-meeting beats for Needle, #1 Fan, Auntie, and Dave.

------------------------------------------------------------------------

# 23. Current North Star

The quest graph should make two players with the same hours and money
capable of having very different inboxes.

One player will not stop asking Stu about hardware, so Rico eventually
says:

> You ask a lot of questions about hardware.

Another lives in the Scanner and Flashbulb appears.

Another pounds ghosts alone and Zero starts critiquing corners.

Another becomes fast enough for Knuckles to start talking shit.

Another survives on ugly machinery and finds Patch.

Another collects unanswered Leads and attracts Glass.

The system is not asking, **"What quest number are you on?"**

It is asking:

**"What kind of automotive life have you been living?"**


------------------------------------------------------------------------

# APPENDIX A --- Reconciliation against shipped code and platform

Added 2026-09-27. **Nothing above this line was edited.** This appendix checks the draft's triggers against
what NCM Online can actually observe, what the platform can actually do, and what the decision record has
already locked. It is written to be useful to Pass 2, which is why it answers section 21's telemetry ask
directly rather than commenting on it.

Sources: `ncm/core/**` as shipped; `docs/research/open77/CHARACTER_ARCHAEOLOGY_AND_PVE_SUBSTRATE.md`;
build-pinned platform cards (index `op77.78`, staging `.102` --- see `KB-162` on that skew).

## A.1 The draft is structurally right, and one line of it is the whole design

> *"The quest graph should make two players with the same hours and money capable of having very different
> inboxes."*

That is the correct north star, and it is **already how the single-player system worked**, which is the
strongest evidence it is buildable. SP's Dynamic Contact Event System (`contact_events.lua`) generated
different contacts for different players from real state, budgeted them to `MAX_ACTIVE_EVENTS = 2` with a
two-race cooldown and a permanent sent-key set, and delivered them through named contacts as routing channels.
Section 20's anti-spam rules are, almost line for line, the rules DCES already enforces. **Pass 2 should read
`contact_events.lua` before inventing a trigger budget**, because a working one exists.

Section 0.3 --- *"Messages are state projections"* --- is likewise not a new idea to this codebase. It is
exactly what `ShouldActivateChoiceEntry` did in SP, and what `competition.venue_options` independently ruled
for venues. The draft is consistent with both.

## A.2 Telemetry crosswalk --- section 21, answered against real code

Section 21 asks for a map from triggers onto actual NCM telemetry. Here it is, in three honest buckets.

### Observable today

| Draft trigger | What actually provides it |
|---|---|
| clean performance, contact, penalties | **Race Tags**, 16 authored: `clean_race`, `clean_run`, `close_finish`, `clear_win`, `gained_positions`, `lost_positions`, `good_start`, `led_every_gate`, `came_through`, `heavy_contact`, `tough_one`, `jump_start`, `penalised`, `did_not_finish`, `personal_best`, `route_record` |
| deep-grid recovery | `gained_positions` + `came_through` |
| notable win | `clear_win`, `led_every_gate` |
| record / fast time | `personal_best`, `route_record` |
| car-to-car contact, graded | `competition.incidents` --- symmetric per-pair records with delta-v bands (2 / 6 / 12 m/s to x1 / x2 / x4) |
| DNF | `did_not_finish` |
| race count, wins, podiums, start and finish positions | results + `session.standings` |
| money, entry fees, purses, settlement | Economy v1 (`L168`, `L169`) --- itemised, idempotent, typed ledger rows |
| vehicle ownership, provenance, custody history | ownership/provenance records; immutable transfer history |
| mileage | odometer, read at 1 Hz (`competition.observation`) |
| weather participation | `world.weather` + race records |
| route and discipline variety | race history; `competition.discipline`, `competition.class` |
| parts owned and installed | Parts economy v1 (`L162`-`L163`) |
| Machine Index discovery | `competition.machine_knowledge`, migration 033 |
| socially-caused discovery | `competition.discoveries` --- "Discoveries Inspired", already anti-farmed |
| message decline / defer state | `message.state` ENUM already has `declined`, plus `resolved_at` |

### Derivable, but not stored

- **head-to-head history and rivalry** (Knuckles, Rico) --- computable from shared race results; nothing persists it.
- **consistency** --- finish-position variance.
- **"repeated use of one car"** (#1 Fan, Sunday) --- derivable from race records plus ownership.
- **streak behaviour** --- derivable; SP persisted it per career, Online does not.

### Does not exist

| Draft assumption | Reality |
|---|---|
| **`overtakes` as a counter** | **NCM Online does not count overtakes.** SP's `fan_engine` had them from `race_telemetry`; the Online tree has no overtake counter anywhere. `gained_positions` and `came_through` cover the *narrative* territory and should be what Pass 2 writes against. The draft's `#1 Fan` example --- *"P8. Seven passes. P1."* --- **cannot currently be written truthfully.** Either add the counter or change the line. |
| **Scanner activity** (Flashbulb's entire trigger) | **The Scanner does not exist and is explicitly not authorised.** `28_MACHINE_KNOWLEDGE.md`: *"Do not promise scanner telemetry before engine capability is validated"* and *"This is not authorisation to build the scanner."* `16_MACHINE_INDEX.md` allows only *"a bounded Scanner experiment."* `machine_knowledge.lua` still calls it *"a future Scanner adapter."* See A.3. |
| **Unresolved Leads** (Glass's trigger; the Lead state everywhere) | Not built. This is the substrate gap the recon names: objectives/leads as a first-class row (`IDEA-608`). Glass cannot trigger until Leads exist, because Glass's eligibility *is* "multiple unresolved Leads". |
| **Market knowledge / access** | SPEC only (`17_MARKET_NETWORK.md`), now amended by `L171`. Persistent `player_market_knowledge` rows are unbuilt. |
| **Billie wagering ledger** | SP only. Online has no wagering at all yet. |
| **hardware-curiosity score** (Needle's trigger) | New. Nothing counts question categories. Needs a small durable counter store, not a schema change. |
| **character-contact history** | Partially --- `message` rows exist per driver, but nothing aggregates per-character relationship depth (which Billie 6.3 needs in full). |
| **physical location discovery** | Not built. Auntie and Dave are entirely gated on it. |
| **solo practice / ghost activity** (Zero) | Ghosts are **deployed but unproven** --- PERSONAL BEST only under `L166`, and `MASTER_TEST` **BI** is still owed. Zero's trigger rests on something with no live PASS. |

## A.3 Three characters are harder-blocked than the draft suggests

1. **Flashbulb** is gated on a system the authority documents forbid building. Not a tuning problem --- a
   governance one. Either the Scanner experiment runs and is reviewed first, or Flashbulb waits. **Suggestion:**
   Flashbulb's loop works almost unchanged on *Machine Index discovery* alone (encounter-based identity reveal,
   which does exist), with scanning added later when it exists. That preserves the character without
   pre-authorising the Scanner.
2. **Auntie and Dave** are pure physical-discovery characters, which is the point of them --- section 17.3 says
   so: *"Auntie proves the graph exists in geography, not only Messages."* They therefore depend on the NPC
   dialogue primitive, whose status is: authored standing NPCs **AVAILABLE** (36 server natives, `world.npcs`
   already declared by `ncm_world`), but the **interaction prompt and dialogue surface is UNKNOWN and budget-
   bound** --- eight CEF surfaces per resource, NCM holds seven, one spare. These two characters are the
   strongest argument for prototyping that surface early.
3. **Zero** rests on ghost/practice telemetry that is deployed but has never been validated live.

## A.4 Two places the draft collides with decisions taken 2026-09-27

Both were ruled *after* this draft's assumptions were formed, so these are reconciliations, not criticisms.

**Section 2.4 --- "Do not reveal total market count."** `L171` (owner ruling) **supersedes**
`17_MARKET_NETWORK.md`'s prohibition: the Market surface now deliberately shows a roster of sixteen unknown
slots against a working target of 17. The count is disclosed *by the UI*. The draft's instruction is therefore
stale as a global rule --- but it remains **good dialogue writing**, and the leak condition attached to `L171`
still forbids everything else. Recommended reading for Pass 2: the UI discloses the shape, **Dex still does not
recite a number**, and Dex's actual line --- *"Yes. Most don't advertise to everybody. You'll hear things, find
things, meet people"* --- is exactly right and needs no change.

**Section 6.2 --- "the wagering surface becomes available according to the final multiplayer economics model."**
That model is now pinned by `L172`: **self-paper only, permanently.** Billie may write paper on the player's own
finish and own streak legs; she will **never quote odds on another player**. So Pass 2 must not author
winner-board dialogue --- no *"Back the favorite"*, no *"Where's the value?"*, no prices on humans. Opponent
strength enters as a *risk-model input* to the player's own multiplier, never as a market. The draft's Billie
voice is unaffected and excellent; only the product surface narrows.

## A.5 One constraint the draft should know about: the voice harness

> **WITHDRAWN IN PART by `L176` (LOCKED, owner, 2026-09-27).** The per-character **word and sentence ceilings
> below are struck**: they encoded single player's restrictive phone surface rather than a design intent, and
> holding every character to a small envelope risks making the whole cast sound the same. The violation this
> section flags against Dex's opening (§2.2) is therefore **withdrawn -- that message is in voice**, and Dex's
> register is *neutral guidance*, not terseness. What survives, and is now enforced in the offline gate by
> `graph.conversation`, is the rest of the harness: `requiredAny`, `forbiddenAny`, and the pairwise token-overlap
> failure at >= 0.55, which `L176` names the load-bearing mechanism. Read the ceilings below as history.

SP shipped a **mechanical voice validator** (`voice_harness.lua`) that Pass 2 should probably inherit: per
character it fixes sentence shape, a word ceiling, required domain vocabulary and forbidden vocabulary, and it
fails a bundle when any two characters' token overlap reaches 0.55.

Checked against the draft, the new and returning voices hold up well. Quinn (ceiling 26 words, ultra-short) is
perfect --- *"okay easiest thing in the world / pick where you're going / GO"*. Billie (42, rhythmic, bookmaker
vocabulary) is on voice --- *"I take positions. Sometimes they're yours."* The Fan (30, punchy) is exact.
Foreman and Stu both sit inside their ceilings.

**The one violation is Dex's opening message** (section 2.2), which runs roughly 75 words over six sentences
against a persona ceiling of **22 words and two sentences**. That is not necessarily wrong --- a first-contact
onboarding message is a reasonable exception --- but it should be a *decision* rather than an accident, because
Dex's whole characterisation is terseness. Two options: declare onboarding exempt, or split it into three short
beats (greeting / Stu handoff / Rico offer), which would also read more like a phone conversation.

## A.6 Things the draft treats as uncertain that are actually reachable

**The #1 Fan appearance gag (section 7.5) is better than "not assumed technically available."** The pieces
exist and compose:

- `Open77.clothing.requestSnapshot(playerId)` --- server-side, *"asks a player's client for its current clothing
  state"* (op77.45);
- `Open77.npcs.setEquipment(id, { slot = "Items.*" })` and `getEquipment` (op77.73);
- `Open77.npcs.setAppearance(id, appearance)`.

So: snapshot the player's wardrobe, set it slot-for-slot on the Fan's NPC. Still **PLAUSIBLE rather than
PROVEN** --- the card for `setEquipment` warns that *"whether a rig renders it is the client's answer, not this
call's"* --- but it is a concrete path, not a wish. Worth prototyping alongside the NPC dialogue surface,
because it is the single most memorable beat in the document.

**Group chat (Quinn + Foreman) needs no new concept.** The deployed `message` table plus the proposed nullable
`thread_id` (`IDEA-614`) handles it: two `from_id`s interleaved in one thread. The comic timing the draft wants
--- Quinn and Foreman talking over each other --- is just two rows with adjacent `created_at`.

## A.7 Two things Pass 2 will hit immediately

**Needle's trust test is the substrate gap in miniature.** *"Run your next three. Put one on the podium. Don't
turn the car into scrap"* is a thread with a step, a completion condition evaluated from telemetry, a failure
branch that does not terminate the thread, and a cooldown before a modified retry. DCES has no step concept ---
one `status` field --- and nothing in Online has objectives. This one conversation justifies building the thread
substrate properly, and it is a good test case precisely because it uses **only** telemetry that already exists.

**Knuckles raises a provenance question the repository already cares about.** `AGENTS.md` requires preserving
observed-versus-simulated result provenance, and Knuckles works by *claiming* accomplishments --- *"Just put down
a 2:14.8 on [course]"* --- that nobody drove. That is fine as fiction and dangerous as data. The rule to write
into Pass 2: **a Knuckles claim is authored flavour and must never enter route records, personal bests,
leaderboards, Machine Knowledge or anything settlement-authoritative**, and must be stored somewhere that cannot
be mistaken for a result. The draft's own instinct --- *"Knuckles does not require an AI car to pretend a live
race occurred"* --- is right; it just needs to be a storage rule as well as a design one.

## A.8 Smallest honest first slice

If any of this is built, the cheapest path that proves the whole shape uses **only** what exists today:

1. Widen `message.from_kind` --- one `ALTER TABLE`, the only schema blocker (`IDEA-599`).
2. **Dex, Stu, and the Rico offer** --- section 2.2 through 5.2. All three need nothing but messages and the
   existing contact/thread model.
3. **#1 Fan's first intrusion**, keyed to Race Tags rather than to overtakes. This is the proof that the graph
   reacts to a life rather than a level, and the Fan is the character whose trigger data most completely exists.
4. Pace all of it through `player.communication`, which is written, tested and undeployed (`IDEA-600`).

That slice contains a guaranteed handoff, an optional deferral with re-entry, and one emergent world-state
intrusion --- the three grammars section 1 defines --- without needing Leads, markets, wagering, the Scanner,
physical NPCs or a thread engine.
