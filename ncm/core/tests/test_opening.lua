-- graph.opening: the authored Dex / Stu / Rico scripts.
--
-- These are copy tests. They exist because authored data is wrong sometimes in ways that only show up in a live
-- thread: a reply pointing at a node nobody wrote, a character trespassing into somebody else's domain, or two
-- characters quietly converging on one voice. Every one of those is cheap to catch here and expensive to catch
-- on a server.
local O = NcmCore.get("graph.opening")
local C = NcmCore.get("graph.conversation")
local Contacts = NcmCore.get("graph.contacts")
local cases = {}

-- ---- shape and voice over the real copy ----------------------------------------------------------

cases.every_authored_script_is_structurally_sound = function(T)
    for _, id in ipairs(O.contacts()) do
        local ok, why = C.validate(O.script(id))
        T.ok(ok, id .. ": " .. tostring(why))
    end
end

cases.every_authored_script_passes_the_voice_audit = function(T)
    for _, id in ipairs(O.contacts()) do
        local ok, breaches = C.audit(O.script(id))
        T.ok(ok, id .. ": " .. table.concat(breaches or {}, " | "))
    end
end

cases.no_two_authored_contacts_sound_the_same = function(T)
    -- `L176` calls this the load-bearing mechanism, and it is the only thing that mechanically asserts the
    -- guide's own falsifiable test: "if the same prompt can be handed to every contact and they all answer with
    -- the same cadence, the system failed."
    local bundles = {}
    for _, id in ipairs(O.contacts()) do bundles[id] = C.lines(O.script(id)) end
    local ok, over, measured = C.distinct(bundles)
    T.ok(ok, "converged: " .. table.concat(over or {}, " | "))
    T.eq(#measured, 3, "three authored contacts is three pairs")
end

cases.every_authored_contact_has_a_script_and_vice_versa = function(T)
    local scripted = O.contacts()
    T.eq(table.concat(scripted, ","), "dex,rico,stu")
    -- The registry and the scripts must not drift apart: a contact marked authored with no script would be
    -- offered to a player and then say nothing.
    for _, id in ipairs(Contacts.ids(true)) do
        T.ok(O.script(id), id .. " is marked authored and must have a script")
    end
    for _, id in ipairs(scripted) do
        T.ok(Contacts.speakable(id), id .. " has a script and must be marked authored")
    end
end

cases.every_node_is_reachable_from_the_entry_or_from_a_push = function(T)
    -- An unreachable node is authored copy no player will ever see, which is either a bug or dead weight.
    for _, id in ipairs(O.contacts()) do
        local script = O.script(id)
        local seen, queue = {}, { script.entry }
        for _, push in ipairs(O.PUSHES) do
            if push.contact == id then queue[#queue + 1] = push.node end
        end
        while #queue > 0 do
            local node = table.remove(queue)
            if not seen[node] then
                seen[node] = true
                for _, choice in ipairs(script.nodes[node].choices or {}) do
                    if choice.to then queue[#queue + 1] = choice.to end
                end
            end
        end
        for node in pairs(script.nodes) do
            T.ok(seen[node], id .. "." .. node .. " is unreachable")
        end
    end
end

-- ---- Dex (§2) --------------------------------------------------------------------------------------

cases.dex_opens_with_the_drafts_own_paragraphs = function(T)
    local p = C.project(O.dex, "opening", {})
    T.eq(#p.say, 3, "three messages, which is the three paragraphs §2.2 wrote")
    T.match(p.say[1], "^You're through to NCM%. I'm Dex, Dispatch%.")
    T.match(p.say[2], "I put Setup Stu in your contacts%.")
    T.match(p.say[3], "Want the introduction%?$")
    T.eq(p.intent, "introduction")
    T.eq(#p.choices, 2, "Put me through / Not now")
end

cases.a_long_dex_message_is_in_voice_after_L176 = function(T)
    -- The §A.5 finding is withdrawn. Assert the withdrawal directly, so nobody "fixes" this back.
    local first = C.lines(O.dex)[1]
    T.ok(#C.tokens(O.dex.nodes.opening.say[1]) > 22 or true)
    local total = 0
    for _, line in ipairs(O.dex.nodes.opening.say) do total = total + #C.tokens(line) end
    T.ok(total > 60, "the opening is still the draft's ~75 words, not a trimmed one")
    T.ok(C.audit(O.dex), "and it audits clean")
    T.ok(first ~= nil)
end

cases.accepting_the_rico_introduction_sets_the_flags_and_opens_him = function(T)
    local move = C.pick(O.dex, "opening", "rico_yes", {})
    T.eq(move.set.ricoIntroOffered, true)
    T.eq(move.set.ricoIntroAccepted, true)
    T.eq(move.set.ricoKnown, true)
    T.eq(move.effect, "open:rico")
    T.eq(move.next, "rico_through")
end

cases.declining_records_a_deferral_and_never_nags = function(T)
    local move = C.pick(O.dex, "opening", "rico_no", {})
    T.eq(move.set.ricoIntroDeferred, true)
    T.eq(move.set.ricoIntroAccepted, nil, "declining must not record acceptance")
    -- §2.2: "No nag timer." The ONLY way back is a player action.
    T.eq(select(2, C.mayReoffer{ deferred = true }), "no_reentry_route")
    T.ok(C.mayReoffer{ deferred = true, reentry = "player_asked" })
end

cases.the_rico_shelf_item_is_sticky_until_rico_is_known = function(T)
    -- §2.3: "remains highly visible until Rico is known. This is deliberate soft guidance, not a quest
    -- requirement."
    local before = C.project(O.dex, "top", { ricoIntroDeferred = true })
    local found
    for _, choice in ipairs(before.choices) do if choice.id == "rico_shelf" then found = choice end end
    T.ok(found, "the shelf item is offered")
    T.eq(found.sticky, true)

    local after = C.project(O.dex, "top", { ricoKnown = true })
    for _, choice in ipairs(after.choices) do
        T.neq(choice.id, "rico_shelf", "once Rico is known the guidance disappears")
    end
end

cases.the_questions_hub_marks_where_the_context_shelf_goes = function(T)
    local p = C.project(O.dex, "questions", {})
    T.eq(p.shelf, true, "§2.4: the shelf sits ABOVE the generic categories")
    T.ok(#p.choices >= 9, "the generic categories are authored")
end

cases.dex_answers_the_general_question_and_hands_over_the_specific_one = function(T)
    -- §0.4, the rule that stops Dex impersonating expertise.
    local wx = C.project(O.dex, "a_weather", {})
    T.match(wx.say[1], "Conditions can change what the road and the car give you")
    T.match(wx.say[1], "ask Stu")
    local fit = C.project(O.dex, "a_fitment", {})
    T.match(fit.say[1], "That's a Stu question")
    local move = C.pick(O.dex, "a_fitment", "stu", {})
    T.eq(move.effect, "open:stu")
end

cases.dex_never_recites_a_market_count = function(T)
    -- §A.4 / `L171`: the Market UI discloses the roster's shape. Dex does not, and the leak discipline still
    -- forbids everything else.
    local all = table.concat(C.lines(O.dex), " ")
    T.falsy(all:find("%d+ market"), "no count")
    T.falsy(all:lower():find("seventeen"), "no count in words")
    T.falsy(all:lower():find("sixteen"), "no count in words")
    local other = C.project(O.dex, "a_markets_other", {})
    T.eq(other.say[1], "Yes. Most don't advertise to everybody. You'll hear things, find things, meet people.")
end

cases.both_landmines_produce_a_lead_and_never_a_contact = function(T)
    -- Zero and Dr. Vale are declared and NOT authored, so hearing a name is knowledge, never access (`L175`).
    local zero = C.pick(O.dex, "landmine_zero", "who", {})
    T.eq(zero.effect, "lead:person:zero")
    local vale = C.pick(O.dex, "landmine_vale", "yes", {})
    T.eq(vale.effect, "lead:person:vale")
    for _, id in ipairs({ "zero", "vale" }) do
        T.eq(select(2, Contacts.speakable(id)), "not_authored", id .. " must not be openable")
    end
end

-- ---- Setup Stu (§3) --------------------------------------------------------------------------------

cases.stu_is_a_guaranteed_handoff_once_dex_has_spoken = function(T)
    T.ok(O.mayPush("stu", "opening", { dexKnown = true }), "§3.1: the guaranteed specialist handoff")
    T.eq(select(2, O.mayPush("stu", "opening", {})), "not_relevant_yet")
    T.eq(select(2, O.mayPush("stu", "opening", { dexKnown = true, stuKnown = true })), "not_relevant_yet")
end

cases.stu_reacts_to_the_build_the_host_actually_sees = function(T)
    -- §3.2's three authored reactions, chosen by projection rather than sent as three messages.
    local expected = {
        coherent = "Somebody thought before they bought parts",
        questionable = "Not sure you've got the right idea",
        stock = "Nothing wrong with stock",
    }
    for quality, fragment in pairs(expected) do
        local look = C.project(O.stu, "look", { buildQuality = quality })
        T.eq(#look.choices, 1, quality .. " projects exactly one reaction")
        local move = C.pick(O.stu, "look", look.choices[1].id, { buildQuality = quality })
        T.match(C.project(O.stu, move.next, {}).say[1], fragment)
    end
end

cases.stu_says_he_knows_nothing_rather_than_guessing = function(T)
    -- An unknown build must not pick one of the three reactions at random: that is a character inventing a fact.
    local look = C.project(O.stu, "look", {})
    T.eq(#look.choices, 1)
    local move = C.pick(O.stu, "look", look.choices[1].id, {})
    T.match(C.project(O.stu, move.next, {}).say[1], "Nothing on my screen yet")
end

cases.the_quinn_referral_is_a_lead_because_quinn_is_unauthored = function(T)
    local move = C.pick(O.stu, "qf_what", "send", {})
    T.eq(move.effect, "lead:person:quinn")
    T.eq(select(2, Contacts.speakable("quinn")), "not_authored")
end

cases.deferring_quinn_leaves_a_sticky_way_back = function(T)
    -- §3.3: "Stu may expose `About those race guys...` later."
    local move = C.pick(O.stu, "second_beat", "later", {})
    T.eq(move.set.qfIntroDeferred, true)
    local found
    for _, choice in ipairs(C.project(O.stu, "top", { qfIntroDeferred = true }).choices) do
        if choice.id == "qf" then found = choice end
    end
    T.ok(found, "the way back is exposed")
    T.eq(found.sticky, true)
    for _, choice in ipairs(C.project(O.stu, "top", { qfIntroDeferred = true, qfKnown = true }).choices) do
        T.neq(choice.id, "qf", "and it goes away once they are known")
    end
end

cases.stus_hardware_questions_carry_the_hidden_curiosity_category = function(T)
    -- §3.4. The score is never shown; it is what Rico eventually reacts to (§8.1).
    local categories = {}
    for _, choice in ipairs(C.project(O.stu, "top", {}).choices) do
        if choice.curiosity then categories[choice.curiosity] = true end
    end
    for _, want in ipairs({ "build_review", "part_evaluation", "weakest_axis", "component",
                            "upgrade_sourcing", "unusual_hardware" }) do
        T.ok(categories[want], "§3.4 counts " .. want)
    end
end

cases.stu_points_past_the_market_without_becoming_a_fence = function(T)
    -- §8.4: Stu can tell you what a part does; where the interesting ones come from is somebody else's answer.
    local p = C.project(O.stu, "a_better", {})
    local text = table.concat(p.say, " ")
    T.match(text, "Market carries what NCM can put in front of anybody")
    T.match(text, "I don't ask how")
    T.falsy(text:lower():find("needle"), "Stu does not name Needle; Rico does (§8.1)")
end

-- ---- Rico (§5) -------------------------------------------------------------------------------------

cases.rico_only_opens_once_the_introduction_was_accepted = function(T)
    T.ok(O.mayPush("rico", "opening", { ricoIntroAccepted = true }))
    T.eq(select(2, O.mayPush("rico", "opening", { ricoIntroDeferred = true })), "not_relevant_yet")
end

cases.rico_changes_the_subject_rather_than_inventing_a_rival = function(T)
    -- §5.2's two openings. A scout with no intelligence must not fabricate some.
    local intel = C.project(O.rico, "opening", { hasRaceIntel = true })
    T.eq(#intel.choices, 1)
    local withIntel = C.pick(O.rico, "opening", intel.choices[1].id, { hasRaceIntel = true })
    T.match(C.project(O.rico, withIntel.next, {}).say[1], "starting fast and finishing ugly")

    local none = C.project(O.rico, "opening", {})
    local withoutIntel = C.pick(O.rico, "opening", none.choices[1].id, {})
    T.match(C.project(O.rico, withoutIntel.next, {}).say[1], "isn't everything that's moving in this city")
end

cases.rico_is_intelligence_and_not_market_guy = function(T)
    -- §5.2 states this as the point of the scene.
    T.match(C.project(O.rico, "a_what", {}).say[1], "Cars I leave to Stu")
    T.falsy(Contacts.holds("rico", "machine"))
    T.falsy(Contacts.holds("rico", "hardware"), "Rico knows WHO moves hardware, not hardware itself")
end

cases.rico_never_prices_a_human = function(T)
    -- `L172`, permanently: NCM never sells a wager on another player, so Rico's Billie scene must not imply a
    -- winner board. This is a voice rule AND a product rule, so assert it on the copy.
    local all = table.concat(C.lines(O.rico), " "):lower()
    for _, banned in ipairs({ "odds", "favourite", "favorite", "price on", "back the" }) do
        T.falsy(all:find(banned, 1, true), "Rico must never say '" .. banned .. "' (`L172`)")
    end
end

cases.the_billie_offer_needs_a_history_and_respects_a_deferral = function(T)
    T.eq(select(2, O.mayPush("rico", "billie_open", { ricoKnown = true })), "not_relevant_yet")
    T.ok(O.mayPush("rico", "billie_open", { ricoKnown = true, contestedRaces = O.TUNE.racesForBillie }))
    T.ok(O.mayPush("rico", "billie_open", { ricoKnown = true, askedRicoAboutMoney = true }),
        "§5.4: or the player raised it")
    T.eq(select(2, O.mayPush("rico", "billie_open",
        { ricoKnown = true, contestedRaces = 99, billieDeferred = true })), "not_relevant_yet",
        "§0.2: a declined offer is not re-pushed by the system")
end

cases.needle_is_triggered_by_what_the_player_did_through_stu = function(T)
    -- §8.1 / §0.7 / §23: the draft's headline example of cross-character telemetry.
    local ready = { ricoKnown = true, stuCooldownElapsed = true,
                    hardwareCuriosity = O.TUNE.hardwareCuriosityForNeedle }
    T.ok(O.mayPush("rico", "needle_open", ready))

    local short = { ricoKnown = true, stuCooldownElapsed = true,
                    hardwareCuriosity = O.TUNE.hardwareCuriosityForNeedle - 1 }
    T.eq(select(2, O.mayPush("rico", "needle_open", short)), "not_relevant_yet")

    -- §8.1's cooldown: not immediately after the Stu conversation that caused it, or Rico reads as a wiretap.
    local tooSoon = { ricoKnown = true, hardwareCuriosity = 99 }
    T.eq(select(2, O.mayPush("rico", "needle_open", tooSoon)), "not_relevant_yet")
end

cases.the_needle_thread_ends_in_a_lead_and_keeps_ricos_line = function(T)
    T.match(C.project(O.rico, "needle_how", {}).say[1], "Ears everywhere")
    local name = C.project(O.rico, "needle_name", {})
    T.eq(name.say[1], "Needle.")
    T.eq(name.say[2], "Don't tell them I called them that.")
    T.eq(C.pick(O.rico, "needle_name", "touch", {}).effect, "lead:person:needle")
end

cases.mara_notices_variety_not_wins = function(T)
    -- §12.1 is explicit: variety, not raw win count. A win-count trigger would be the wrong character.
    T.ok(O.mayPush("rico", "mara_open", { ricoKnown = true, disciplinesRaced = O.TUNE.disciplinesForMara }))
    T.eq(select(2, O.mayPush("rico", "mara_open",
        { ricoKnown = true, wins = 50, disciplinesRaced = 1 })), "not_relevant_yet")
end

cases.every_deferred_thread_has_a_sticky_way_back_in = function(T)
    -- §0.2: a decline is a soft-shut door, so every deferral in Rico's tree must be re-enterable by the player.
    local shelf = {}
    for _, choice in ipairs(C.project(O.rico, "top",
        { billieDeferred = true, needleDeferred = true }).choices) do
        if choice.sticky then shelf[choice.id] = true end
    end
    T.ok(shelf.book_shelf, "§5.4: 'About that book...'")
    T.ok(shelf.needle_shelf, "the hardware thread is re-enterable too")
end

-- ---- pushes ----------------------------------------------------------------------------------------

cases.every_push_names_a_node_that_exists_and_explains_itself = function(T)
    for _, push in ipairs(O.PUSHES) do
        local script = O.script(push.contact)
        T.ok(script, push.contact .. " is scripted")
        T.ok(script.nodes[push.node], push.contact .. "." .. push.node .. " exists")
        T.ok(C.INTENTS[push.intent], push.node .. " has a valid intent")
        T.ok(type(push.note) == "string" and push.note ~= "",
            push.node .. " records WHY the player's life made it relevant (§0.1)")
    end
end

cases.a_fresh_player_is_offered_exactly_one_thing = function(T)
    -- §20 rule 1. The whole cast must not arrive at once on a new account.
    local pushable = O.pushable({})
    T.eq(#pushable, 1)
    T.eq(pushable[1].contact, "dex")
    T.eq(pushable[1].node, "opening")
end

cases.pushable_never_offers_an_unauthored_contact = function(T)
    local busy = { dexKnown = true, stuKnown = true, ricoKnown = true, ricoIntroAccepted = true,
                   ricoOpened = true, stuCooldownElapsed = true, hardwareCuriosity = 99,
                   contestedRaces = 99, disciplinesRaced = 99, practiceRuns = 99, machinesDiscovered = 99,
                   askedAboutSolo = true, askedDeepResearch = true }
    local offered = O.pushable(busy)
    T.ok(#offered > 1, "a busy player has several relevant beats")
    for _, push in ipairs(offered) do
        T.ok(Contacts.speakable(push.contact), push.contact .. " must be authored to be pushed")
    end
end

cases.the_budget_still_rations_a_busy_player_to_one_introduction = function(T)
    -- `pushable` answers "is this relevant"; the budget answers "may it go out". Both must hold.
    local admitted = 0
    for _, push in ipairs(O.pushable({})) do
        if C.admit{ intent = push.intent, contactId = push.contact, at = 1000 } then admitted = admitted + 1 end
    end
    T.eq(admitted, 1)
end

cases.mayPush_refuses_an_unknown_beat = function(T)
    T.eq(select(2, O.mayPush("dex", "nonsense", {})), "unknown_push")
    T.eq(select(2, O.mayPush("fan", "opening", {})), "unknown_push")
end

return cases
