-- ncm-core module: graph.opening
--
-- The authored scripts for the first slice of the quest graph: **Dex, Setup Stu, and Rico** (§A.8 item 2).
-- Copy only, plus the state predicates that project it. The engine is `graph.conversation`; the registry is
-- `graph.contacts`; neither knows what anybody says.
--
-- Everything here is quoted from `41_QUEST_GRAPH_PASS1.md` sections 2, 3 and 5. **The draft's copy is preserved
-- word for word and paragraph for paragraph**, with one departure and one addition, both recorded so they are
-- decisions rather than drift:
--
--   1. **No line was shortened, and the §A.5 word-ceiling finding is not applied.** `L176` (LOCKED, owner)
--      struck the single-player harness's per-character word and sentence ceilings -- they encoded the WolvenKit
--      phone's display limit, not a design intent, and holding every character to a 22-word envelope risks
--      making the whole cast sound the same. The appendix's flag against Dex's ~75-word opening is therefore
--      **withdrawn**: it is in voice. Each of the draft's paragraphs becomes one message, because that is how the
--      draft wrote them and how a phone thread reads. What `graph.conversation.audit` still enforces is what
--      `L176` kept: forbidden vocabulary, domain vocabulary, and pairwise distinctiveness.
--
--   2. **Nothing here unlocks a contact who is not authored.** Quinn, Foreman, Billie, Needle, Mara, Zero and
--      Dr. Vale all appear in these trees, because the draft's whole point is that Dex and Stu and Rico are how
--      you hear about them. So hearing about them writes a **Lead** (`player.leads`, `L175`) -- *"a person
--      mentioned but not met"* -- which is exactly the object the leads module was built for and the character
--      reveal producer `IDEA-625` asks for first. A lead is honest; a contact who cannot answer is not.
--
--   3. **The addition is `effect` strings.** A choice names an intention (`lead:person:rico`, `open:stu`) and
--      the host performs it. The engine never performs anything, so an unimplemented effect is a no-op the host
--      logs rather than a silent branch.
--
-- Two constraints from the decision record are load-bearing in the copy below:
--
--   * **`L171` / §A.4.** Dex still does not recite a market count. His authored line -- *"Yes. Most don't
--     advertise to everybody. You'll hear things, find things, meet people"* -- is preserved exactly, because
--     the appendix judged it exactly right. The Market UI discloses the roster's shape; Dex does not.
--   * **`L172` / §A.4.** Rico may introduce Billie as *"a book"*, and nothing here quotes a price on a human or
--     implies a winner board. Billie is self-paper only, permanently, and she is not authored yet anyway.
local Core = NcmCore

Core.define("graph.opening", function()
    local Conversation = Core.get("graph.conversation")

    local M = { version = "0.1.0" }

    -- ---- state predicates ----------------------------------------------------------------------------
    -- Small named readers over the host's state table, so the scripts below stay legible and so "what does
    -- this flag mean" has exactly one answer. §0.3: the choices are projected from these, not fixed.

    local function flag(name)
        return function(s) return type(s) == "table" and s[name] == true end
    end

    local function notFlag(name)
        return function(s) return not (type(s) == "table" and s[name] == true) end
    end

    local function both(a, b)
        return function(s) return a(s) and b(s) end
    end

    local function build(kind)
        return function(s) return type(s) == "table" and tostring(s.buildQuality or "") == kind end
    end

    --- A counter at or past a threshold. The thresholds are the draft's `TUNE` values made concrete as first
    --- numbers; §21 is explicit that these are authoring values and not final balance.
    local function atLeast(name, n)
        return function(s) return (tonumber(type(s) == "table" and s[name]) or 0) >= n end
    end

    M.TUNE = {
        hardwareCuriosityForNeedle = 5,   -- §8.1: substantive Stu hardware interactions before Rico notices
        racesForBillie = 4,               -- §5.4: "several eligible contested races"
        disciplinesForMara = 3,           -- §12.1: Mara notices VARIETY, not win count
    }

    -- ==================================================================================================
    -- DEX / NCM DISPATCH (§2)
    -- ==================================================================================================
    M.dex = {
        contact = "dex",
        entry = "opening",
        nodes = {
            -- §2.2, VERBATIM, as three messages -- which is exactly the three paragraphs the draft wrote. Its
            -- ~75-word length was flagged by §A.5 and the flag was **withdrawn by `L176`**: the 22-word ceiling
            -- was a single-player phone artifact, and Dex's register is neutral guidance rather than terseness.
            -- A long Dex message is in voice; an opinionated one would not be.
            opening = {
                intent = "introduction",
                say = {
                    "You're through to NCM. I'm Dex, Dispatch. If you get turned around, send it here and I'll point you at the right line.",
                    "I put Setup Stu in your contacts. He handles the machine: parts, setup, what you've got underneath you. Start there.",
                    "One other thing. I know a guy named Rico. Knows who's running, what's moving around the city, and usually hears things before I do. Want the introduction?",
                },
                choices = {
                    { id = "rico_yes", label = "Put me through.", to = "rico_through",
                      set = { ricoIntroOffered = true, ricoIntroAccepted = true, ricoKnown = true },
                      effect = "open:rico" },
                    { id = "rico_no", label = "Not now.", to = "rico_declined",
                      set = { ricoIntroOffered = true, ricoIntroDeferred = true } },
                },
            },
            rico_through = {
                intent = "reply",
                say = { "I'll tell him you're expecting the line." },
                choices = {
                    { id = "to_top", label = "Thanks.", to = "top" },
                },
            },
            -- §2.2: "No nag timer." The deferral is recorded and never re-offered by the clock; the way back in
            -- is the sticky shelf choice on `top`, which is a player action (§0.2 / `mayReoffer`).
            rico_declined = {
                intent = "reply",
                say = { "Your call. If you change your mind, ask." },
                choices = {
                    { id = "to_top", label = "Understood.", to = "top" },
                },
            },

            -- §2.3. The Rico item stays highly visible until Rico is known: soft guidance, not a requirement.
            top = {
                say = { "NCM Dispatch. What do you need?" },
                choices = {
                    { id = "questions", label = "I have a question.", to = "questions" },
                    { id = "rico_shelf", label = "Actually, about Rico...", to = "rico_about",
                      when = notFlag("ricoKnown"), sticky = true },
                },
            },
            rico_about = {
                say = { "What about him?" },
                choices = {
                    { id = "who", label = "Who is this guy?", to = "rico_who" },
                    { id = "does", label = "What does he actually do?", to = "rico_does" },
                    { id = "through", label = "Put me through.", to = "rico_through",
                      set = { ricoIntroAccepted = true, ricoKnown = true }, effect = "open:rico" },
                    { id = "never", label = "Never mind.", to = "top" },
                },
            },
            rico_who = {
                -- §2.3 verbatim, one message, as authored.
                say = {
                    "Scout. Fixer when he needs to be. Knows drivers, crews, shops, people who don't advertise. If he doesn't know somebody, he usually knows somebody who does.",
                },
                choices = {
                    { id = "back", label = "Alright.", to = "rico_about" },
                },
            },
            rico_does = {
                say = {
                    "Finds things out. People, cars, hardware, races. Doesn't mean he's right about everything. Means he usually knows where to start.",
                },
                choices = {
                    { id = "back", label = "Alright.", to = "rico_about" },
                },
            },

            -- §2.4. The shelf sits ABOVE these generic categories and is spliced in by the host from the
            -- player's open leads -- unresolved people and things they already legitimately know about.
            questions = {
                shelf = true,
                say = { "What about?" },
                choices = {
                    { id = "races", label = "How do races work?", to = "a_races" },
                    { id = "cars", label = "Tell me about cars and parts.", to = "a_cars" },
                    { id = "money", label = "How does money work around here?", to = "a_money" },
                    { id = "markets", label = "What's the deal with markets?", to = "a_markets" },
                    { id = "alone", label = "What can I do when nobody else is around?", to = "a_alone" },
                    { id = "index", label = "What are Discovery and the Machine Index?", to = "a_index" },
                    { id = "weather", label = "Does weather affect racing?", to = "a_weather" },
                    { id = "fitment", label = "Why doesn't this part fit my car?", to = "a_fitment" },
                    { id = "else", label = "Something else.", to = "a_else" },
                },
            },
            a_races = {
                say = {
                    "Races post to the board.",
                    "Enter one, be on your mark when the lights go, and drive.",
                    "Race Guide is F6. Everything running tonight is in it.",
                },
                choices = { { id = "back", label = "Got it.", to = "questions" } },
            },
            a_cars = {
                say = {
                    "You buy a Machine in Market. Parts bolt to it and change how it behaves.",
                    "Past that, ask Stu. He does this for a living.",
                },
                choices = {
                    { id = "stu", label = "Open his line.", to = "handoff_stu", effect = "open:stu" },
                    { id = "back", label = "Later.", to = "questions" },
                },
            },
            a_money = {
                say = {
                    "Entry fees go out. Finishing pays, placing pays better.",
                    "A bigger field means a bigger purse.",
                },
                choices = { { id = "back", label = "Got it.", to = "questions" } },
            },
            -- §2.4 verbatim, and §A.4: the count is disclosed by the Market UI, never recited by Dex (`L171`).
            a_markets = {
                say = {
                    "Public starting point. Cars, parts, the stuff NCM can put in front of anybody. It isn't the only place hardware moves in this city.",
                },
                choices = {
                    { id = "others", label = "Are there other markets?", to = "a_markets_other" },
                    { id = "back", label = "Understood.", to = "questions" },
                },
            },
            a_markets_other = {
                -- §A.4: the Market UI discloses the roster's shape (`L171`); Dex still recites no number.
                say = {
                    "Yes. Most don't advertise to everybody. You'll hear things, find things, meet people.",
                },
                choices = { { id = "back", label = "Right.", to = "questions" } },
            },
            a_alone = {
                say = {
                    "Practice. Run a route alone, chase your own time, learn a corner properly.",
                    "Nothing here needs a full grid to be worth doing.",
                },
                choices = { { id = "back", label = "Good to know.", to = "questions" } },
            },
            a_index = {
                say = {
                    "The Index is what you've learned about machines. Discovery is how you learn it.",
                    "F6 opens it, or F10 goes straight there.",
                },
                choices = { { id = "back", label = "Got it.", to = "questions" } },
            },
            -- §0.4 / §2.4's domain boundary, authored as the draft wrote it: Dex answers the general question
            -- and hands the specific one to the specialist rather than impersonating expertise.
            a_weather = {
                say = {
                    "Yes. Conditions can change what the road and the car give you. If you're asking why your setup is doing something weird in it, ask Stu.",
                },
                choices = {
                    { id = "stu", label = "Open his line.", to = "handoff_stu", effect = "open:stu" },
                    { id = "back", label = "Just asking.", to = "questions" },
                },
            },
            a_fitment = {
                say = { "That's a Stu question. Want me to open his line?" },
                choices = {
                    { id = "stu", label = "Open Setup Stu.", to = "handoff_stu", effect = "open:stu" },
                    { id = "stay", label = "Stay here.", to = "questions" },
                },
            },
            a_else = {
                say = {
                    "Then it's somebody else's desk.",
                    "If it's the car, that's Stu. If it's who's running, that's Rico.",
                },
                choices = { { id = "back", label = "Fair.", to = "questions" } },
            },
            handoff_stu = {
                intent = "reply",
                say = { "His line's open. He'll talk your ear off about tyres." },
                choices = { { id = "back", label = "Thanks.", to = "top" } },
            },

            -- §2.5 landmines. Both are gated on state the host sets, and BOTH produce a lead rather than a
            -- contact, because neither Zero nor Dr. Vale is authored (§A.3, and Zero's telemetry has no live
            -- PASS). Hearing a name is knowledge; meeting somebody is access. `L175` is the whole distinction.
            landmine_zero = {
                intent = "flavour",
                say = { "Actually, somebody asked me about your times the other day." },
                choices = {
                    { id = "who", label = "Who?", to = "zero_who", effect = "lead:person:zero" },
                    { id = "weird", label = "That's weird.", to = "zero_weird" },
                    { id = "drop", label = "Forget it.", to = "top" },
                },
            },
            zero_who = {
                say = {
                    "Calls themselves Zero. Watches laps, not races.",
                    "Didn't leave a line. They'll turn up if they want to.",
                },
                choices = { { id = "back", label = "Right.", to = "top" } },
            },
            zero_weird = {
                say = { "It is. I'd say forget it, but you won't." },
                choices = { { id = "back", label = "No.", to = "top" } },
            },
            landmine_vale = {
                intent = "flavour",
                say = {
                    "You're asking better questions than I can answer.",
                    "Want somebody who does this for a living?",
                },
                choices = {
                    { id = "yes", label = "Yeah.", to = "vale_yes", effect = "lead:person:vale" },
                    { id = "who", label = "Who are they?", to = "vale_who", effect = "lead:person:vale" },
                    { id = "no", label = "Not right now.", to = "top" },
                },
            },
            vale_who = {
                say = { "Researcher. Catalogues machines for a living." },
                choices = { { id = "back", label = "Noted.", to = "top" } },
            },
            vale_yes = {
                say = { "I'll pass your name along. They're particular about who they talk to." },
                choices = { { id = "back", label = "Fine.", to = "top" } },
            },
        },
    }

    -- ==================================================================================================
    -- SETUP STU (§3)
    -- ==================================================================================================
    M.stu = {
        contact = "stu",
        entry = "opening",
        nodes = {
            opening = {
                intent = "introduction",
                -- §3.2 verbatim, one message.
                say = {
                    "Dispatch says you're driving with us now. I'm Stu. If it bolts on, changes how the car behaves, or makes you wonder why the hell it suddenly hates a corner, that's my desk.",
                },
                choices = {
                    { id = "ack", label = "Good to know.", to = "second_beat" },
                    { id = "look", label = "Take a look at what I'm driving.", to = "look",
                      curiosity = "build_review" },
                    { id = "simple", label = "I'm keeping it simple for now.", to = "simple" },
                },
            },
            -- §3.2's context response, projected from the build the host actually sees. Three authored
            -- reactions, one of which is chosen by state -- not three messages sent.
            look = {
                intent = "reply",
                say = { "Let's see." },
                choices = {
                    { id = "coherent", label = "...", to = "look_coherent", when = build("coherent") },
                    { id = "questionable", label = "...", to = "look_questionable", when = build("questionable") },
                    { id = "stock", label = "...", to = "look_stock", when = build("stock") },
                    -- Nothing known about the build yet: say so rather than picking a reaction at random.
                    { id = "unknown", label = "...", to = "look_unknown",
                      when = function(s)
                          local q = tostring(type(s) == "table" and s.buildQuality or "")
                          return q ~= "coherent" and q ~= "questionable" and q ~= "stock"
                      end },
                },
            },
            look_coherent = {
                say = { "Huh. Somebody thought before they bought parts. That's rarer than you'd think." },
                choices = { { id = "on", label = "Noted.", to = "second_beat" } },
            },
            look_questionable = {
                say = { "You've got an idea there. Not sure you've got the right idea, but you've got one." },
                choices = { { id = "on", label = "Noted.", to = "second_beat" } },
            },
            look_stock = {
                say = { "Nothing wrong with stock. At least I know what I'm looking at." },
                choices = { { id = "on", label = "Noted.", to = "second_beat" } },
            },
            look_unknown = {
                say = { "Nothing on my screen yet. Put some runs on it and ask me again." },
                choices = { { id = "on", label = "Will do.", to = "second_beat" } },
            },
            simple = {
                intent = "reply",
                say = { "Smart. Simple and working beats clever and broken." },
                choices = { { id = "on", label = "Right.", to = "second_beat" } },
            },

            -- §3.3. Fires after the player has replied once to the introduction, which is what every path above
            -- routes into.
            second_beat = {
                intent = "reply",
                -- §3.3 verbatim. **A recorded conflict, not an oversight.** `board` is on Stu's RECOVERED
                -- forbidden list (`voice_harness.lua`, kept by `L176`), because board STATE -- what is staged,
                -- what is running -- belongs to Foreman and to Dex. This line does not claim board state; it
                -- points AWAY from the board to contrast it with a race the player builds themselves, which is
                -- Stu handing the player to Quinn rather than Stu talking shop he does not own. The owner's copy
                -- is preserved and the rule is preserved; the exemption is one word on one node, written down.
                allow = { board = "§3.3 owner copy: Stu points away from the board, he does not read its state" },
                say = { "One more thing. If you ever want to put something together yourself instead of waiting on the board, I know two guys." },
                choices = {
                    { id = "what", label = "Put something together?", to = "qf_what" },
                    { id = "who", label = "Who?", to = "qf_what" },
                    { id = "later", label = "Maybe later.", to = "qf_deferred",
                      set = { qfIntroDeferred = true } },
                },
            },
            qf_what = {
                say = { "Race. Quick one, serious one, whatever. Quinn and Foreman handle that circus." },
                choices = {
                    -- Quinn and Foreman are declared and NOT authored (their tutorial must teach against the
                    -- final race-creation controls, §22). So this is a lead, not a line.
                    { id = "send", label = "Send me their line.", to = "qf_sent", effect = "lead:person:quinn" },
                    { id = "later", label = "Maybe later.", to = "qf_deferred",
                      set = { qfIntroDeferred = true } },
                },
            },
            qf_sent = {
                say = {
                    "I'll mention you. Quinn will answer in about four seconds.",
                    "Foreman will answer properly.",
                },
                choices = { { id = "on", label = "Thanks.", to = "top" } },
            },
            qf_deferred = {
                say = { "Suit yourself. They're not going anywhere." },
                choices = { { id = "on", label = "Right.", to = "top" } },
            },

            -- §3.4. The persistent model. `curiosity` names what each substantive interaction counts toward;
            -- the host increments a hidden score and Rico eventually reacts (§8.1). Nothing here is shown to
            -- the player as a meter.
            top = {
                say = { "Stu. What's it doing?" },
                choices = {
                    { id = "setup", label = "Take a look at my setup.", to = "look", curiosity = "build_review" },
                    { id = "part", label = "What do you think of this part?", to = "a_part", curiosity = "part_evaluation" },
                    { id = "weakest", label = "What's my weakest area?", to = "a_weakest", curiosity = "weakest_axis" },
                    { id = "why", label = "Why is the car doing this?", to = "a_why" },
                    { id = "tyres", label = "Tell me about tires.", to = "a_tyres", curiosity = "component" },
                    { id = "next", label = "What should I change next?", to = "a_next", curiosity = "upgrade_sourcing" },
                    { id = "better", label = "Where do people find better parts?", to = "a_better", curiosity = "unusual_hardware" },
                    { id = "qf", label = "About those race guys...", to = "qf_what",
                      when = both(flag("qfIntroDeferred"), notFlag("qfKnown")), sticky = true },
                },
            },
            a_part = {
                say = {
                    "Depends what it's bolted to.",
                    "A part that helps one car ruins another. That's most of my job.",
                },
                choices = { { id = "back", label = "Fair.", to = "top" } },
            },
            a_weakest = {
                say = {
                    "Depends what the last few runs said.",
                    "Usually it's the thing you stopped noticing.",
                },
                choices = { { id = "back", label = "Hm.", to = "top" } },
            },
            a_why = {
                say = {
                    "Narrow it down for me. Corner, brakes, or straight line?",
                    "Because those are three different conversations.",
                },
                choices = { { id = "back", label = "I'll pay attention and come back.", to = "top" } },
            },
            a_tyres = {
                say = {
                    "Tyres decide what the car can do.",
                    "Everything else just changes how you ask.",
                },
                choices = { { id = "back", label = "Right.", to = "top" } },
            },
            a_next = {
                say = {
                    "Whatever's costing you the most and annoying you the loudest.",
                    "Usually the same thing.",
                },
                choices = { { id = "back", label = "Noted.", to = "top" } },
            },
            -- The line that plants the hardware thread without Stu becoming a fence. §8.4: Stu can tell you
            -- what a part does; where the interesting ones come from is somebody else's answer.
            a_better = {
                say = {
                    "Market carries what NCM can put in front of anybody.",
                    "Past that, people find things. I don't ask how.",
                },
                choices = { { id = "back", label = "Huh.", to = "top" } },
            },
        },
    }

    -- ==================================================================================================
    -- RICO (§5)
    -- ==================================================================================================
    M.rico = {
        contact = "rico",
        entry = "opening",
        nodes = {
            -- §5.2. The second beat is projected: live race intelligence when there is any, and an honest
            -- substitute when there is not. A scout who invents a rival is worse than one who changes subject.
            opening = {
                intent = "introduction",
                say = { "Dispatch says you're new to the board. Fine. First one's free." },
                choices = {
                    { id = "intel", label = "...", to = "opening_intel", when = flag("hasRaceIntel") },
                    { id = "no_intel", label = "...", to = "opening_general", when = notFlag("hasRaceIntel") },
                },
            },
            opening_intel = {
                say = { "Guy two rows up has been starting fast and finishing ugly. Don't get boxed behind him." },
                choices = {
                    { id = "what", label = "What exactly do you do?", to = "a_what" },
                    { id = "moving", label = "What else is moving?", to = "a_moving" },
                    { id = "thanks", label = "Thanks, I guess.", to = "top" },
                },
            },
            opening_general = {
                say = { "First thing to know: what's on the board isn't everything that's moving in this city." },
                choices = {
                    { id = "what", label = "What exactly do you do?", to = "a_what" },
                    { id = "moving", label = "What else is moving?", to = "a_moving" },
                    { id = "thanks", label = "Thanks, I guess.", to = "top" },
                },
            },
            -- §5.2: Rico establishes himself as motorsport intelligence, NOT Market Guy. The second beat is
            -- there to keep him out of Stu's domain (§0.4).
            a_what = {
                say = {
                    "I find out who's quick, who's lying about it, and who's about to be a problem. Cars I leave to Stu.",
                },
                choices = { { id = "back", label = "Useful.", to = "top" } },
            },
            a_moving = {
                say = {
                    "Hardware. People. Races that never touch the board.",
                    "Ask me again when you've got a reason to care.",
                },
                choices = { { id = "back", label = "I will.", to = "top" } },
            },

            -- §5.3. The persistent model, plus every deferred thread's way back in as a sticky item.
            top = {
                shelf = true,
                say = { "Rico. Talk." },
                choices = {
                    { id = "heard", label = "Heard anything interesting?", to = "a_heard" },
                    { id = "next_race", label = "Anything about my next race?", to = "a_next_race" },
                    { id = "anybody", label = "Know anybody I should know?", to = "a_anybody" },
                    { id = "book_shelf", label = "About that book...", to = "billie_book",
                      when = both(flag("billieDeferred"), notFlag("billieKnown")), sticky = true },
                    { id = "needle_shelf", label = "About that hardware guy...", to = "needle_name",
                      when = both(flag("needleDeferred"), notFlag("needleKnown")), sticky = true },
                },
            },
            a_heard = {
                say = { "Always. Whether it's worth anything to you is a different question." },
                choices = { { id = "back", label = "Try me later.", to = "top" } },
            },
            a_next_race = {
                say = {
                    "Depends who enters. People decide late.",
                    "Ask me once there's a field to talk about.",
                },
                choices = { { id = "back", label = "Alright.", to = "top" } },
            },
            a_anybody = {
                say = { "Plenty. None of them want to meet somebody who hasn't done anything yet." },
                choices = { { id = "back", label = "Charming.", to = "top" } },
            },

            -- §5.4 -> Billie. Eligibility is race and money history, which the host evaluates; `L172` means
            -- nothing here promises a market on other drivers, and Billie is a lead until she is authored.
            billie_open = {
                intent = "offer",
                say = { "You ever bet on yourself?" },
                choices = {
                    { id = "cute", label = "Isn't racing on yourself already betting on yourself?",
                      to = "billie_cute" },
                    { id = "who", label = "With who?", to = "billie_book" },
                    { id = "no", label = "No.", to = "billie_declined",
                      set = { billieDeferred = true } },
                },
            },
            billie_cute = {
                say = { "Cute. I mean money." },
                choices = { { id = "on", label = "Go on.", to = "billie_book" } },
            },
            billie_book = {
                say = { "I know a book." },
                choices = {
                    { id = "who", label = "Who's running it?", to = "billie_who" },
                    { id = "touch", label = "Put me in touch.", to = "billie_sent",
                      effect = "lead:person:billie" },
                    { id = "no", label = "Not interested.", to = "billie_declined",
                      set = { billieDeferred = true } },
                },
            },
            billie_who = {
                -- §5.4 verbatim.
                say = {
                    "Billie. If she likes you, Book Queen Billie. If she doesn't, probably still Book Queen Billie.",
                },
                choices = {
                    { id = "touch", label = "Put me in touch.", to = "billie_sent",
                      effect = "lead:person:billie" },
                    { id = "no", label = "Not interested.", to = "billie_declined",
                      set = { billieDeferred = true } },
                },
            },
            billie_sent = {
                say = { "I'll say your name. She'll decide what it's worth." },
                choices = { { id = "on", label = "Fine.", to = "top" } },
            },
            -- §0.2: the door is soft-shut. The offer closed; the character did not.
            billie_declined = {
                say = { "Suit yourself." },
                choices = { { id = "on", label = "...", to = "top" } },
            },

            -- §8.1 -> Needle. **Cross-character telemetry**: the trigger is what the player did through STU.
            -- This is the draft's own headline example of the social web being alive (§0.7, §23).
            needle_open = {
                intent = "offer",
                say = { "You ask a lot of questions about hardware." },
                choices = {
                    { id = "how", label = "How do you know that?", to = "needle_how" },
                    { id = "buying", label = "I like knowing what I'm buying.", to = "needle_anyway" },
                    { id = "and", label = "And?", to = "needle_anyway" },
                },
            },
            needle_how = {
                say = { "Ears everywhere. Don't worry about it." },
                choices = { { id = "on", label = "...", to = "needle_anyway" } },
            },
            needle_anyway = {
                -- §8.1 verbatim.
                say = {
                    "Anyway. Stu can tell you what a part does. I know somebody who can tell you where the interesting ones come from.",
                },
                choices = {
                    { id = "who", label = "Who?", to = "needle_name" },
                    { id = "listening", label = "I'm listening.", to = "needle_name" },
                    { id = "no", label = "Not right now.", to = "needle_declined",
                      set = { needleDeferred = true } },
                },
            },
            needle_name = {
                say = {
                    "Needle.",
                    "Don't tell them I called them that.",
                },
                choices = {
                    { id = "touch", label = "Put me in touch.", to = "needle_sent",
                      effect = "lead:person:needle" },
                    { id = "no", label = "Not right now.", to = "needle_declined",
                      set = { needleDeferred = true } },
                },
            },
            needle_sent = {
                say = { "They'll find you. That's usually how it goes." },
                choices = { { id = "on", label = "Great.", to = "top" } },
            },
            needle_declined = {
                say = { "Your call." },
                choices = { { id = "on", label = "...", to = "top" } },
            },

            -- §12.1 -> Mara Velez. Variety, not win count. Also a lead: curated events are unbuilt.
            mara_open = {
                intent = "offer",
                say = { "Somebody's been asking who's driving everything lately." },
                choices = {
                    { id = "who", label = "Who?", to = "mara_who" },
                    { id = "ominous", label = "That sounds ominous.", to = "mara_who" },
                    { id = "no", label = "Not yet.", to = "mara_declined",
                      set = { maraDeferred = true } },
                },
            },
            mara_who = {
                say = { "Mara Velez. She puts fields together when the normal board isn't interesting enough." },
                choices = {
                    { id = "touch", label = "Put us together.", to = "mara_sent",
                      effect = "lead:person:mara" },
                    { id = "what", label = "What kind of fields?", to = "mara_fields" },
                    { id = "no", label = "Not yet.", to = "mara_declined",
                      set = { maraDeferred = true } },
                },
            },
            mara_fields = {
                say = { "One-make. Invite-only. Whatever she thinks is worth watching that week." },
                choices = {
                    { id = "touch", label = "Put us together.", to = "mara_sent",
                      effect = "lead:person:mara" },
                    { id = "no", label = "Not yet.", to = "mara_declined",
                      set = { maraDeferred = true } },
                },
            },
            mara_sent = {
                say = { "Done. She books people, not friends. Be worth booking." },
                choices = { { id = "on", label = "Noted.", to = "top" } },
            },
            mara_declined = {
                say = { "Fine." },
                choices = { { id = "on", label = "...", to = "top" } },
            },
        },
    }

    -- ---- registry ------------------------------------------------------------------------------------

    local SCRIPTS = { dex = M.dex, stu = M.stu, rico = M.rico }

    function M.script(contactId) return SCRIPTS[tostring(contactId or "")] end

    function M.contacts()
        local out = {}
        for id in pairs(SCRIPTS) do out[#out + 1] = id end
        table.sort(out)
        return out
    end

    --- Where an unprompted beat begins. These are the nodes a host may PUSH, as opposed to the nodes a player
    --- reaches by replying. Naming them here keeps the trigger conditions in the host (where the telemetry is)
    --- and the entry points in the script (where the copy is).
    ---
    --- `requires` is the state a host must have satisfied. It is checked by `graph.opening.mayPush`, so a host
    --- cannot push Rico's Needle beat without the curiosity score that justifies it -- which is the difference
    --- between cross-character telemetry and a character who guesses.
    M.PUSHES = {
        { contact = "dex", node = "opening", intent = "introduction",
          requires = notFlag("dexKnown"), note = "§2.1: first NCM session after onboarding eligibility." },
        -- SOLICITED, because Dex's opening message says out loud *"I put Setup Stu in your contacts"*. §3.1 calls
        -- this the guaranteed specialist handoff, so holding it behind the world's introduction cooldown would
        -- make Dispatch's own message a lie for half an hour.
        { contact = "stu", node = "opening", intent = "introduction", solicited = true,
          requires = both(flag("dexKnown"), notFlag("stuKnown")),
          note = "§3.1: the guaranteed handoff. Dex's opening places Stu in Contacts." },
        -- SOLICITED by definition: this push only becomes relevant because the player picked "Put me through".
        { contact = "rico", node = "opening", intent = "introduction", solicited = true,
          requires = both(flag("ricoIntroAccepted"), notFlag("ricoOpened")),
          note = "§5.1: only once the player accepted the introduction." },
        { contact = "rico", node = "billie_open", intent = "offer",
          requires = function(s)
              s = type(s) == "table" and s or {}
              if s.ricoKnown ~= true or s.billieKnown == true then return false end
              if s.billieDeferred == true then return false end        -- §0.2: no nag timer
              return atLeast("contestedRaces", M.TUNE.racesForBillie)(s) or s.askedRicoAboutMoney == true
          end,
          note = "§5.4: several contested races, meaningful race money, or the player raised it." },
        { contact = "rico", node = "needle_open", intent = "offer",
          requires = function(s)
              s = type(s) == "table" and s or {}
              if s.ricoKnown ~= true or s.needleKnown == true then return false end
              if s.needleDeferred == true then return false end
              -- §8.1's cooldown: not immediately after the Stu conversation that caused it, or Rico reads as
              -- a wiretap rather than as a man with ears.
              if s.stuCooldownElapsed ~= true then return false end
              return atLeast("hardwareCuriosity", M.TUNE.hardwareCuriosityForNeedle)(s)
          end,
          note = "§8.1: CROSS-CHARACTER -- the trigger is hardware curiosity spent on Stu." },
        { contact = "rico", node = "mara_open", intent = "offer",
          requires = function(s)
              s = type(s) == "table" and s or {}
              if s.ricoKnown ~= true or s.maraKnown == true or s.maraDeferred == true then return false end
              return atLeast("disciplinesRaced", M.TUNE.disciplinesForMara)(s)
          end,
          note = "§12.1: VARIETY -- disciplines, classes and regions, never win count." },
        { contact = "dex", node = "landmine_zero", intent = "flavour",
          requires = function(s)
              s = type(s) == "table" and s or {}
              return s.dexKnown == true and s.zeroHeardOf ~= true and s.askedAboutSolo == true
                  and atLeast("practiceRuns", 3)(s)
          end,
          note = "§2.5: only when the player has real solo/ghost history AND asked a solo question." },
        { contact = "dex", node = "landmine_vale", intent = "flavour",
          requires = function(s)
              s = type(s) == "table" and s or {}
              return s.dexKnown == true and s.valeHeardOf ~= true and s.askedDeepResearch == true
                  and atLeast("machinesDiscovered", 6)(s)
          end,
          note = "§2.5 / §16.1: a research question that exceeds Dex's generalist domain." },
    }

    --- May the host push this beat, given what it knows? Returns the push row, or false plus why.
    --- The budget (§20) is a SEPARATE question, answered by `graph.conversation.admit` -- this one is only
    --- "has the player's life made this relevant" (§0.1).
    function M.mayPush(contact, node, state)
        state = type(state) == "table" and state or {}
        for _, push in ipairs(M.PUSHES) do
            if push.contact == contact and push.node == node then
                local ok, result = pcall(push.requires, state)
                if not ok then return false, "requires_failed" end
                if not result then return false, "not_relevant_yet" end
                return push
            end
        end
        return false, "unknown_push"
    end

    --- Every beat the host could push right now, in registry order. The host still asks the budget about each
    --- one and, per §20 rule 1, will send at most one introduction.
    function M.pushable(state)
        local out = {}
        for _, push in ipairs(M.PUSHES) do
            local ok, result = pcall(push.requires, type(state) == "table" and state or {})
            if ok and result then out[#out + 1] = push end
        end
        return out
    end

    return M
end)
