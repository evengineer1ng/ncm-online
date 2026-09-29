-- graph.contacts + graph.conversation: the engine under the quest graph.
local Contacts = NcmCore.get("graph.contacts")
local C = NcmCore.get("graph.conversation")
local cases = {}

-- A minimal legal script, so shape tests are about the thing they name and not about copy.
local function script(over)
    local s = {
        contact = "dex", entry = "a",
        nodes = {
            a = { say = { "One." }, choices = { { id = "go", label = "Go.", to = "b" } } },
            b = { say = { "Two." } },
        },
    }
    for k, v in pairs(over or {}) do s[k] = v end
    return s
end

-- ---- registry ------------------------------------------------------------------------------------

cases.every_declared_contact_is_well_formed = function(T)
    local ids = Contacts.ids()
    T.eq(#ids, 18, "the relationship map names eighteen contacts")
    for _, id in ipairs(ids) do
        local c = Contacts.get(id)
        T.ok(c, id .. " resolves")
        T.ok(Contacts.GRAMMARS[c.grammar], id .. " has a discovery grammar")
        -- `L176`: no word or sentence ceiling exists any more. What every contact must carry is vocabulary.
        T.eq(c.words, nil, id .. " must not carry a struck word ceiling (`L176`)")
        T.eq(c.sentences, nil, id .. " must not carry a struck sentence ceiling (`L176`)")
        T.ok(#c.forbidden > 0, id .. " declares vocabulary that belongs to somebody else")
        T.ok(#c.required > 0, id .. " declares its own domain vocabulary")
        T.ok(next(c.domains) ~= nil, id .. " holds at least one domain")
        for domain in pairs(c.domains) do
            T.ok(Contacts.DOMAINS[domain], id .. " domain " .. domain .. " is a known domain")
        end
    end
end

cases.only_four_contacts_are_authored_and_the_rest_say_why = function(T)
    local authored = Contacts.ids(true)
    T.eq(#authored, 4)
    T.eq(table.concat(authored, ","), "dex,stu,rico,billie", "§A.8's first slice plus Billie (doc 44 §9), in registry order")
    for _, id in ipairs(Contacts.ids()) do
        local c = Contacts.get(id)
        if not c.authored then
            -- The honesty rule: a declared contact who cannot speak must record the reason, or the next
            -- session re-derives the whole appendix from scratch.
            T.ok(type(c.blocked) == "string" and c.blocked ~= "", id .. " states why it is not authored")
        end
    end
end

cases.an_unauthored_contact_may_not_speak = function(T)
    T.ok(Contacts.speakable("dex"))
    T.eq(select(2, Contacts.speakable("fan")), "not_authored")
    T.eq(select(2, Contacts.speakable("nobody")), "unknown_contact")
end

cases.domains_route_questions_to_the_authored_specialist = function(T)
    -- §0.4: Dex knows NCM; specialists know their domains.
    T.ok(Contacts.holds("dex", "ncm"))
    T.falsy(Contacts.holds("dex", "machine"), "Dex must not hold the machine domain")
    T.eq(Contacts.specialist("machine"), "stu")
    T.eq(Contacts.specialist("intelligence"), "rico")
    T.eq(Contacts.specialist("wagering"), "billie", "the Paddock's book (doc 44 §9)")
    -- A domain whose only holders are unauthored has no specialist, so a redirect can never point at somebody
    -- the player cannot reach.
    T.eq(select(2, Contacts.specialist("creation")), "no_authored_specialist")
    T.eq(select(2, Contacts.specialist("nonsense")), "unknown_domain")
end

-- ---- voice (`L176`) ------------------------------------------------------------------------------

cases.tokens_normalise_so_punctuation_cannot_hide_a_word = function(T)
    T.eq(table.concat(C.tokens("Board's idle, chief!"), "|"), "board|idle|chief")
    T.eq(#C.tokens(""), 0)
    T.eq(table.concat(C.tokens("2:14.8 on the board"), "|"), "on|the|board", "numbers are not vocabulary")
end

cases.forbidden_vocabulary_is_refused_per_line = function(T)
    -- Each of these is another character's domain trespassing (`L176` keeps `forbiddenAny`).
    T.eq(select(2, C.forbidden("dex", "The odds are good.")), "forbidden_word:odds")
    T.eq(select(2, C.forbidden("stu", "Check the board.")), "forbidden_word:board")
    T.eq(select(2, C.forbidden("rico", "Just bolt it on.")), "forbidden_word:bolt")
    T.ok(C.forbidden("dex", "I'll point you at the right line."))
    T.eq(select(2, C.forbidden("dex", "  ")), "empty_line")
    T.eq(select(2, C.forbidden("nobody", "hi")), "unknown_contact")
end

cases.an_apostrophe_does_not_smuggle_a_forbidden_word_through = function(T)
    T.eq(select(2, C.forbidden("stu", "The board's wrong.")), "forbidden_word:board")
end

cases.a_forbidden_phrase_is_matched_as_a_phrase = function(T)
    -- Billie's list holds "route to" and "grid is staged" as phrases, which is how the harness held them.
    T.eq(select(2, C.forbidden("billie", "I'll route to the venue.")), "forbidden_phrase:route to")
    T.ok(C.forbidden("billie", "Take the route."), "the single word alone is not the forbidden phrase")
end

cases.required_vocabulary_is_checked_over_a_script_not_a_line = function(T)
    -- The departure from SP, and its reason: "Needle." is a legitimate whole message.
    T.ok(C.required("dex", { "Nothing here.", "I'll point you at the right line." }))
    T.eq(select(2, C.required("dex", { "Nothing here.", "Nor here." })), "no_domain_vocabulary")
    T.ok(C.required("dex", { "Which route?" }), "any one required token is enough")
end

cases.overlap_is_jaccard_over_distinct_tokens = function(T)
    T.eq(C.overlap({ "one two" }, { "one two" }), 1)
    T.eq(C.overlap({ "one two" }, { "three four" }), 0)
    T.eq(C.overlap({}, {}), 0, "two silent contacts are not identical, they are empty")
    -- {a,b,c} vs {b,c,d}: shared 2, union 4
    T.eq(C.overlap({ "a b c" }, { "b c d" }), 0.5)
end

cases.distinct_fails_a_converged_pair_and_names_it = function(T)
    T.eq(C.OVERLAP_LIMIT, 0.55, "`L176` fixes the limit at 0.55")
    local ok, over = C.distinct({
        a = { "the car is doing something strange on exit" },
        b = { "the car is doing something strange on exit" },
    })
    T.falsy(ok)
    T.eq(#over, 1)
    T.match(over[1], "^a/b: 1%.000 >= 0%.55")

    local fine, none, measured = C.distinct({
        a = { "brakes tyres corner rear" },
        b = { "paper money position risk" },
    })
    T.ok(fine)
    T.eq(#none, 0)
    T.eq(#measured, 1, "every pair is measured, not only the failures")
end

-- ---- shape ---------------------------------------------------------------------------------------

cases.validate_accepts_a_legal_script = function(T)
    T.ok(C.validate(script()))
end

cases.validate_refuses_a_choice_that_strands_the_player = function(T)
    -- The commonest authoring mistake, and the one that leaves a live thread with no way forward.
    local s = script()
    s.nodes.a.choices[1].to = "nowhere"
    T.match(select(2, C.validate(s)), "choice_targets_missing_node:a%.go%->nowhere")

    local t = script()
    t.nodes.a.choices[1].to = nil
    T.match(select(2, C.validate(t)), "choice_goes_nowhere:a%.go")

    -- ...unless it explicitly ends the conversation, which is a different thing from pointing nowhere.
    local u = script()
    u.nodes.a.choices[1].to = nil
    u.nodes.a.choices[1].ends = true
    T.ok(C.validate(u))
end

cases.validate_refuses_the_rest_of_the_shape_mistakes = function(T)
    T.eq(select(2, C.validate(nil)), "script_not_table")
    T.eq(select(2, C.validate(script{ contact = "fan" })), "not_authored")
    T.eq(select(2, C.validate(script{ entry = "missing" })), "entry_node_missing")

    local s = script(); s.nodes.b.say = {}
    T.eq(select(2, C.validate(s)), "node_says_nothing:b")

    local t = script(); t.nodes.a.say = { "ok", "  " }
    T.match(select(2, C.validate(t)), "blank_line:a%[2%]")

    local u = script(); u.nodes.a.intent = "vibes"
    T.eq(select(2, C.validate(u)), "invalid_intent:a")

    local v = script()
    v.nodes.a.choices[2] = { id = "go", label = "Again.", to = "b" }
    T.match(select(2, C.validate(v)), "duplicate_choice_id:a%.go")

    local w = script(); w.nodes.a.choices[1].when = "truthy"
    T.match(select(2, C.validate(w)), "choice_when_not_function:a%.go")

    local x = script(); x.nodes.a.choices[1].label = nil
    T.match(select(2, C.validate(x)), "choice_missing_label:a%.go")
end

cases.audit_reports_every_breach_not_just_the_first = function(T)
    local s = script()
    -- Both lines carry Dex's own vocabulary ("line"), so the only breaches are the two trespasses -- the test
    -- is about reporting all of them, not about tripping a second rule by accident.
    s.nodes.a.say = { "Bad odds on that line.", "Worse chassis on that line." }
    local ok, breaches = C.audit(s)
    T.falsy(ok)
    T.eq(#breaches, 2, "an audit that stops at the first breach makes an author fix one line per run")
end

cases.audit_accepts_a_long_line_because_L176_struck_the_ceilings = function(T)
    local s = script()
    s.nodes.a.say = { "You're through to NCM. I'm Dex, Dispatch. If you get turned around, send it here " ..
        "and I'll point you at the right line, because a long message from Dex is in voice and only an " ..
        "opinionated one would not be." }
    T.ok(C.audit(s), "length is not a voice breach any more")
end

cases.a_vocabulary_exemption_must_say_why = function(T)
    -- The escape hatch exists (the owner's own §3.3 copy needs one), so it must be impossible to use quietly.
    local s = script()
    s.nodes.a.say = { "Bad odds on that line." }
    T.falsy(C.audit(s), "without an exemption it is a breach")

    s.nodes.a.allow = { odds = "because I said so" }
    T.ok(C.audit(s), "with a reason it is allowed")

    local silent = script()
    silent.nodes.a.allow = { odds = "" }
    T.match(select(2, C.validate(silent)), "allow_without_reason:a%.odds")

    local wrong = script()
    wrong.nodes.a.allow = "odds"
    T.eq(select(2, C.validate(wrong)), "allow_not_table:a")
end

cases.an_exemption_is_scoped_to_one_node_not_the_character = function(T)
    local s = script()
    s.nodes.a.allow = { odds = "documented here" }
    s.nodes.a.say = { "Bad odds on that line." }
    s.nodes.b.say = { "Bad odds on that line too." }
    local ok, breaches = C.audit(s)
    T.falsy(ok, "the exemption must not leak to another node")
    T.eq(#breaches, 1)
    T.match(breaches[1], "^b%.say%[1%]: forbidden_word:odds")
end

cases.audit_requires_the_script_to_sound_like_its_character = function(T)
    local s = script()
    s.nodes.a.say = { "Mm." }
    s.nodes.b.say = { "Quite." }
    local ok, breaches = C.audit(s)
    T.falsy(ok)
    T.match(breaches[1], "no_domain_vocabulary")
end

cases.audit_holds_reply_labels_to_a_readable_length_as_layout = function(T)
    -- Not a voice rule: a reply is a button, and `L176` does not govern buttons.
    local s = script()
    s.nodes.a.choices[1].label = "one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen"
    local ok, breaches = C.audit(s)
    T.falsy(ok)
    T.match(breaches[1], "reply label over 14 words %(layout, not voice%)")
end

cases.lines_flattens_a_script_deterministically_and_excludes_the_player = function(T)
    local s = script()
    local first = table.concat(C.lines(s), "|")
    T.eq(first, table.concat(C.lines(s), "|"), "two runs must measure the same overlap")
    T.eq(first, "One.|Two.")
    T.falsy(first:find("Go."), "reply labels are the player's voice, not the contact's")
end

-- ---- projection ----------------------------------------------------------------------------------

cases.projection_filters_choices_by_state = function(T)
    local s = script()
    s.nodes.a.choices[2] = { id = "secret", label = "Only sometimes.", to = "b",
        when = function(st) return st.ready == true end }

    local closed = C.project(s, "a", {})
    T.eq(#closed.choices, 1)
    T.eq(closed.hiddenChoices, 1)

    local open = C.project(s, "a", { ready = true })
    T.eq(#open.choices, 2)
    T.eq(open.hiddenChoices, 0)
end

cases.a_predicate_that_throws_costs_one_choice_not_the_conversation = function(T)
    local s = script()
    s.nodes.a.choices[2] = { id = "bad", label = "Boom.", to = "b",
        when = function() error("authoring bug") end }
    local p = C.project(s, "a", {})
    T.ok(p, "the projection still succeeded")
    T.eq(#p.choices, 1)
    T.eq(p.hiddenChoices, 1)
end

cases.projection_carries_the_rendering_hints_and_defaults_to_the_entry = function(T)
    local s = script()
    s.nodes.a.shelf = true
    s.nodes.a.choices[1].sticky = true
    s.nodes.a.choices[1].curiosity = "component"
    local p = C.project(s, nil, {})
    T.eq(p.node, "a", "a nil node means the entry node")
    T.eq(p.shelf, true)
    T.eq(p.choices[1].sticky, true)
    T.eq(p.choices[1].curiosity, "component")
    T.falsy(p.terminal)
    T.eq(C.project(s, "b", {}).terminal, true, "a node with nothing to pick is a rest, not a break")
    T.eq(select(2, C.project(s, "ghost", {})), "unknown_node")
end

cases.pick_returns_an_intention_and_never_writes = function(T)
    local s = script()
    s.nodes.a.choices[1].set = { ricoKnown = true }
    s.nodes.a.choices[1].effect = "open:rico"
    local state = {}
    local move = C.pick(s, "a", "go", state)
    T.eq(move.next, "b")
    T.falsy(move.ends)
    T.eq(move.set.ricoKnown, true)
    T.eq(move.effect, "open:rico")
    T.eq(move.label, "Go.", "the transcript needs what the player said")
    T.eq(next(state), nil, "pick must not mutate the state it was given")
end

cases.pick_rechecks_visibility_so_a_stale_client_cannot_force_a_branch = function(T)
    local s = script()
    s.nodes.a.choices[1].when = function(st) return st.ready == true end
    T.eq(select(2, C.pick(s, "a", "go", {})), "choice_not_available")
    T.ok(C.pick(s, "a", "go", { ready = true }))
    T.eq(select(2, C.pick(s, "a", "nope", {})), "unknown_choice")
end

cases.a_choice_that_ends_says_so = function(T)
    local s = script()
    s.nodes.a.choices[1].to = nil
    s.nodes.a.choices[1].ends = true
    local move = C.pick(s, "a", "go", {})
    T.eq(move.next, nil)
    T.eq(move.ends, true)
end

-- ---- the trigger budget (§20) --------------------------------------------------------------------

cases.never_two_introductions_at_once = function(T)
    -- §20 rule 1, the rule the draft states most emphatically.
    T.ok(C.admit{ intent = "introduction", contactId = "rico", at = 1000 })
    T.eq(select(2, C.admit{ intent = "introduction", contactId = "rico", openIntroductions = 1, at = 1000 }),
        "introduction_already_open")
end

cases.introductions_respect_a_narrative_cooldown = function(T)
    local base = { intent = "introduction", contactId = "rico", lastIntroductionAt = 1000 }
    base.at = 1000 + C.BUDGET.introductionCooldownSec - 1
    T.eq(select(2, C.admit(base)), "introduction_cooldown")
    base.at = 1000 + C.BUDGET.introductionCooldownSec
    T.ok(C.admit(base))
    -- a host may tune it
    base.at = 1000 + 60
    base.budget = { introductionCooldownSec = 60 }
    T.ok(C.admit(base))
end

cases.a_direct_consequence_is_never_rationed = function(T)
    -- §20 rule 3. A player who acts and is not answered reads that as a bug, not as restraint.
    T.ok(C.admit{ intent = "consequence", contactId = "stu", openIntroductions = 9,
        lastIntroductionAt = 1, lastFlavourAt = 1, at = 2 })
    T.ok(C.admit{ intent = "reply", contactId = "stu", pendingConsequence = true, at = 2 })
end

cases.flavour_loses_to_gameplay_and_has_long_cooldowns = function(T)
    -- §20 rules 4, 6 and 9.
    T.eq(select(2, C.admit{ intent = "flavour", contactId = "dex", pendingConsequence = true, at = 10 }),
        "yields_to_gameplay")
    T.eq(select(2, C.admit{ intent = "flavour", contactId = "dex", lastFlavourAt = 10, at = 20 }),
        "flavour_cooldown")
    T.eq(select(2, C.admit{ intent = "flavour", contactId = "dex",
        lastFlavourAt = 0, lastContactFlavourAt = 10,
        at = 10 + C.BUDGET.flavourCooldownSec }), "contact_flavour_cooldown")
    T.ok(C.admit{ intent = "flavour", contactId = "dex", at = 10 + C.BUDGET.perContactFlavourSec,
        lastFlavourAt = 0, lastContactFlavourAt = 0 })
end

cases.the_budget_refuses_nonsense_and_unauthored_senders = function(T)
    T.eq(select(2, C.admit{ intent = "gossip", contactId = "dex" }), "invalid_intent")
    T.eq(select(2, C.admit{ intent = "introduction", contactId = "glass" }), "not_authored")
    T.eq(select(2, C.admit(nil)), "invalid_intent")
end

cases.an_offer_is_rationed_only_against_introductions = function(T)
    T.ok(C.admit{ intent = "offer", contactId = "rico", openIntroductions = 1, lastFlavourAt = 1, at = 2 })
end

-- ---- deferral and re-entry (§0.2) ----------------------------------------------------------------

cases.a_deferral_never_reoffers_because_time_passed = function(T)
    T.ok(C.mayReoffer{ deferred = false }, "nothing was declined")
    T.eq(select(2, C.mayReoffer{ deferred = true }), "no_reentry_route")
    T.eq(select(2, C.mayReoffer{ deferred = true, reentry = "timer" }), "no_reentry_route",
        "§2.2: no nag timer -- a timer is not a re-entry route")
end

cases.every_authored_reentry_route_works = function(T)
    for route in pairs(C.REENTRY) do
        if route == "milestone" then
            T.eq(select(2, C.mayReoffer{ deferred = true, reentry = route }),
                "offer_not_materially_different", "a milestone must change the offer")
            T.ok(C.mayReoffer{ deferred = true, reentry = route, offerChanged = true })
        else
            T.ok(C.mayReoffer{ deferred = true, reentry = route }, route .. " is a valid way back in")
        end
    end
end

return cases
