-- ncm-core module: graph.conversation
--
-- The engine under the quest graph's conversations. It holds no copy: authored scripts live in `graph.opening`
-- (and, later, one module per expansion wave), and this module decides what a player may currently SEE of one.
--
-- Four jobs, all of them rules rather than effects, which is why they are here and not in a resource:
--
--   1. **PROJECTION (§0.3).** *"Conversation choices are not a fixed dialogue tree. The visible choices should
--      be projected from current player/world state."* So a node does not own its choices; it owns candidate
--      choices, each with a `when` predicate over state. `project()` evaluates them. The identical rule was
--      reached twice already in this codebase -- `ShouldActivateChoiceEntry` in single player, and
--      `competition.venue_options` for venues -- which is the strongest argument it is the right shape.
--
--   2. **THE VOICE AUDIT (`L176`).** Not a word ceiling. `L176` struck those: they were an artifact of single
--      player's restrictive phone surface, and holding every character to a small envelope risks making them all
--      sound the same, which is the opposite of what a voice validator is for. What survives is the part that
--      actually protects variety -- forbidden vocabulary per line, required domain vocabulary per script, and
--      **pairwise token overlap failed at >= 0.55**, which `L176` calls the load-bearing mechanism. A rule
--      nobody runs is a comment, so `audit` and `distinct` run in the offline gate.
--
--   3. **THE TRIGGER BUDGET (§20).** *"Never fire multiple new-character introductions simultaneously"*, a
--      narrative cooldown, flavour losing to gameplay, and no nag timers on a deferral. §A.1 notes that SP's
--      DCES already enforced very nearly these rules with `MAX_ACTIVE_EVENTS = 2`, a two-race cooldown and a
--      permanent sent-key set; this is that, generalised, and deliberately NOT a second pacing system --
--      `player.communication` still governs whether any individual message is shown at all.
--
--   4. **SHAPE VALIDATION.** An authored script is data, and data authored by hand is wrong sometimes. A choice
--      pointing at a node that does not exist is the single most likely authoring mistake and the one that
--      strands a player mid-conversation, so `validate()` refuses it offline rather than in a live thread.
--
-- Deliberately absent: persistence, delivery, clocks, randomness, and any notion of a quest. A conversation has
-- no steps, no objectives and no completion (§0.3, `L175`). What a player has done is `flags`, which the host
-- owns; what a character will say about it is projected here.
local Core = NcmCore

Core.define("graph.conversation", function()
    local Contacts = Core.get("graph.contacts")

    local M = { version = "0.1.0" }

    --- Why a message is being sent. The budget treats these differently (§20 rules 1-4): an introduction is
    --- rationed hardest, a consequence of something the player just did is never delayed, and flavour is the
    --- first thing to lose.
    M.INTENTS = {
        introduction = true,   -- a new contact appears
        consequence = true,    -- a direct result of a player action; bypasses flavour cooldowns (§20 rule 3)
        offer = true,          -- an actionable proposition with a deadline
        reply = true,          -- this contact answering something the player just said
        flavour = true,        -- colour, no gameplay consequence; loses to everything (§20 rule 4)
    }

    --- §20 recommended authoring rules, as numbers in one place. `TUNE` in the draft; these are first values,
    --- not balance, and the host may override every one of them.
    M.BUDGET = {
        introductionCooldownSec = 30 * 60,   -- §20 rule 2: a narrative introduction cooldown
        flavourCooldownSec = 6 * 60 * 60,    -- §20 rule 6: character flavour has LONG cooldowns
        maxOpenIntroductions = 1,            -- §20 rule 1: never two new characters at once
        perContactFlavourSec = 24 * 60 * 60, -- §20 rule 9: group-chat/flavour sparseness, per contact
    }

    local function nonempty(v)
        return type(v) == "string" and v:match("%S") ~= nil
    end

    local function posNum(v)
        local n = tonumber(v)
        if n == nil or n ~= n then return nil end
        return n
    end

    -- ---- voice (`L176`) -------------------------------------------------------------------------------

    --- Lowercase word tokens, punctuation stripped. Used by every voice check and by the overlap test, so that
    --- "Board's" and "board" are the same token and a contact cannot dodge a forbidden word with an apostrophe.
    function M.tokens(text)
        local out = {}
        for word in tostring(text or ""):lower():gmatch("[%a][%a']*") do
            out[#out + 1] = (word:gsub("'s$", ""))
        end
        return out
    end

    --- Forbidden vocabulary, checked on ONE line. A single trespass is a trespass: this is the rule that stops
    --- Stu quoting odds, Rico pricing risk (`L172`) and Dave calling his gossip "intel" (§18.3).
    ---
    --- Multi-word entries ("route to", "grid is staged") are matched as phrases against the normalised line,
    --- because that is how `voice_harness.lua` held them.
    --- `allow` is a per-node exemption map, { [word] = "why" }. It exists because the first thing this check
    --- caught was a trespass in the owner's own authored copy (§3.3: Stu says *"instead of waiting on the
    --- board"*, and `board` is on Stu's RECOVERED forbidden list). Neither silently editing owner copy nor
    --- silently deleting a recovered rule is acceptable, so the third option is an exemption that has to be
    --- written down, is greppable, and is scoped to one node instead of one character.
    ---
    --- `validate` requires every exemption to carry a non-empty reason, so this can never become a quiet escape
    --- hatch -- which is the only way a vocabulary rule survives contact with real authoring.
    function M.forbidden(contactId, text, allow)
        local c = Contacts.get(contactId)
        if not c then return false, "unknown_contact" end
        if not nonempty(text) then return false, "empty_line" end
        allow = type(allow) == "table" and allow or {}
        local words = M.tokens(text)
        local present = {}
        for _, w in ipairs(words) do present[w] = true end
        local flat = " " .. table.concat(words, " ") .. " "
        for _, bad in ipairs(c.forbidden) do
            local needle = tostring(bad):lower()
            if allow[needle] == nil then
                if needle:find("%s") then
                    if flat:find(" " .. needle .. " ", 1, true) then return false, "forbidden_phrase:" .. needle end
                elseif present[needle] then
                    return false, "forbidden_word:" .. needle
                end
            end
        end
        return true
    end

    --- Required domain vocabulary, checked over a WHOLE script rather than per line.
    ---
    --- A deliberate departure from SP's per-message check, and the reason is the surface: NCM Online's beats are
    --- short enough that "Needle." is a legitimate whole message, and requiring domain vocabulary in every one
    --- of them would forbid the character's own rhythm. `requiredAny` is a statement about a voice, and a voice
    --- is a body of lines.
    function M.required(contactId, lines)
        local c = Contacts.get(contactId)
        if not c then return false, "unknown_contact" end
        if #c.required == 0 then return true end
        local present = {}
        for _, line in ipairs(type(lines) == "table" and lines or {}) do
            local flat = " " .. table.concat(M.tokens(line), " ") .. " "
            for _, w in ipairs(M.tokens(line)) do present[w] = true end
            for _, want in ipairs(c.required) do
                local needle = tostring(want):lower()
                if needle:find("%s") and flat:find(" " .. needle .. " ", 1, true) then present[needle] = true end
            end
        end
        for _, want in ipairs(c.required) do
            if present[tostring(want):lower()] then return true end
        end
        return false, "no_domain_vocabulary"
    end

    --- Jaccard token overlap between two bodies of lines: |A n B| / |A u B| over the distinct token sets.
    function M.overlap(linesA, linesB)
        local a, b = {}, {}
        for _, line in ipairs(type(linesA) == "table" and linesA or {}) do
            for _, w in ipairs(M.tokens(line)) do a[w] = true end
        end
        for _, line in ipairs(type(linesB) == "table" and linesB or {}) do
            for _, w in ipairs(M.tokens(line)) do b[w] = true end
        end
        local shared, union = 0, 0
        for w in pairs(a) do union = union + 1; if b[w] then shared = shared + 1 end end
        for w in pairs(b) do if not a[w] then union = union + 1 end end
        if union == 0 then return 0 end
        return shared / union
    end

    --- The load-bearing test (`L176`): no two contacts may sound the same.
    ---
    --- `bundles` = { [contactId] = { line, ... } }. Fails at or above `M.OVERLAP_LIMIT` for any pair, and
    --- reports EVERY offending pair with its measured value, because "two of your characters converged" is
    --- useless without saying which two and by how much.
    M.OVERLAP_LIMIT = 0.55

    function M.distinct(bundles, limit)
        limit = tonumber(limit) or M.OVERLAP_LIMIT
        local ids = {}
        for id in pairs(type(bundles) == "table" and bundles or {}) do ids[#ids + 1] = id end
        table.sort(ids)
        local pairsOver, measured = {}, {}
        for i = 1, #ids do
            for j = i + 1, #ids do
                local value = M.overlap(bundles[ids[i]], bundles[ids[j]])
                measured[#measured + 1] = { a = ids[i], b = ids[j], overlap = value }
                if value >= limit then
                    pairsOver[#pairsOver + 1] = ("%s/%s: %.3f >= %.2f"):format(ids[i], ids[j], value, limit)
                end
            end
        end
        if #pairsOver > 0 then return false, pairsOver, measured end
        return true, {}, measured
    end

    -- ---- script shape --------------------------------------------------------------------------------

    --- A script is { contact = id, entry = nodeId, nodes = { [id] = node } }.
    --- A node is { say = { line, ... }, choices = { choice, ... }, intent = intent? }.
    --- A choice is { id, label, to = nodeId?, when = fn(state)?, set = { flag = value }?, effect = string?,
    ---               ends = true? }.
    ---
    --- `to` and `ends` are alternatives: a choice either moves the conversation or closes it. A choice with
    --- neither is an authoring error and the commonest way to strand a player, so it is refused here.
    function M.validate(script)
        if type(script) ~= "table" then return false, "script_not_table" end
        local ok, why = Contacts.speakable(script.contact)
        if not ok then return false, why end
        if type(script.nodes) ~= "table" then return false, "nodes_not_table" end
        if not nonempty(script.entry) or type(script.nodes[script.entry]) ~= "table" then
            return false, "entry_node_missing"
        end
        for id, node in pairs(script.nodes) do
            if type(id) ~= "string" then return false, "node_id_not_string" end
            if type(node) ~= "table" then return false, "node_not_table:" .. tostring(id) end
            if type(node.say) ~= "table" or #node.say == 0 then return false, "node_says_nothing:" .. id end
            for i, line in ipairs(node.say) do
                if not nonempty(line) then return false, ("blank_line:%s[%d]"):format(id, i) end
            end
            if node.intent ~= nil and not M.INTENTS[tostring(node.intent)] then
                return false, "invalid_intent:" .. id
            end
            -- An exemption from a vocabulary rule must say why, or the rule has no teeth.
            if node.allow ~= nil then
                if type(node.allow) ~= "table" then return false, "allow_not_table:" .. id end
                for word, reason in pairs(node.allow) do
                    if type(word) ~= "string" then return false, "allow_word_not_string:" .. id end
                    if not nonempty(reason) then
                        return false, ("allow_without_reason:%s.%s"):format(id, tostring(word))
                    end
                end
            end
            local seen = {}
            for i, choice in ipairs(type(node.choices) == "table" and node.choices or {}) do
                if type(choice) ~= "table" then return false, ("choice_not_table:%s[%d]"):format(id, i) end
                if not nonempty(choice.id) then return false, ("choice_missing_id:%s[%d]"):format(id, i) end
                if seen[choice.id] then return false, ("duplicate_choice_id:%s.%s"):format(id, choice.id) end
                seen[choice.id] = true
                if not nonempty(choice.label) then return false, ("choice_missing_label:%s.%s"):format(id, choice.id) end
                if choice.when ~= nil and type(choice.when) ~= "function" then
                    return false, ("choice_when_not_function:%s.%s"):format(id, choice.id)
                end
                if choice.to == nil and choice.ends ~= true then
                    return false, ("choice_goes_nowhere:%s.%s"):format(id, choice.id)
                end
                if choice.to ~= nil then
                    if not nonempty(choice.to) then return false, ("choice_to_not_string:%s.%s"):format(id, choice.id) end
                    if type(script.nodes[choice.to]) ~= "table" then
                        return false, ("choice_targets_missing_node:%s.%s->%s"):format(id, choice.id, tostring(choice.to))
                    end
                end
                if choice.set ~= nil and type(choice.set) ~= "table" then
                    return false, ("choice_set_not_table:%s.%s"):format(id, choice.id)
                end
            end
        end
        return true
    end

    --- Audit one script's voice (`L176`). Returns true, or false plus EVERY breach -- an audit that stops at
    --- the first one makes an author fix a script one line per run.
    ---
    --- Three checks, and deliberately no fourth: forbidden vocabulary per line, the character's own domain
    --- vocabulary somewhere in the script, and a **layout** bound on reply labels. That last one is not a voice
    --- ceiling and `L176` does not touch it: a reply is a button in a list, and a button holding a paragraph is
    --- a rendering problem, not a characterisation one.
    function M.audit(script)
        local shapeOk, why = M.validate(script)
        if not shapeOk then return false, { why } end
        local breaches, lines = {}, M.lines(script)
        for id, node in pairs(script.nodes) do
            for i, line in ipairs(node.say) do
                local lineOk, lineWhy = M.forbidden(script.contact, line, node.allow)
                if not lineOk then breaches[#breaches + 1] = ("%s.say[%d]: %s"):format(id, i, lineWhy) end
            end
            for _, choice in ipairs(type(node.choices) == "table" and node.choices or {}) do
                if #M.tokens(choice.label) > 14 then
                    breaches[#breaches + 1] = ("%s.%s: reply label over 14 words (layout, not voice)"):format(id, choice.id)
                end
            end
        end
        local hasVocabulary, vocabWhy = M.required(script.contact, lines)
        if not hasVocabulary then breaches[#breaches + 1] = "script: " .. tostring(vocabWhy) end
        table.sort(breaches)
        if #breaches > 0 then return false, breaches end
        return true, {}
    end

    --- Every line a contact says in a script, flattened. This is the bundle the overlap test compares, and it is
    --- deliberately the CHARACTER's lines only -- reply labels are the player's voice, and folding them in would
    --- measure how alike the player sounds to themselves across two threads.
    function M.lines(script)
        local out = {}
        if type(script) ~= "table" or type(script.nodes) ~= "table" then return out end
        local ids = {}
        for id in pairs(script.nodes) do ids[#ids + 1] = id end
        table.sort(ids)                      -- deterministic: two runs must measure the same overlap
        for _, id in ipairs(ids) do
            for _, line in ipairs(type(script.nodes[id].say) == "table" and script.nodes[id].say or {}) do
                out[#out + 1] = line
            end
        end
        return out
    end

    -- ---- projection ----------------------------------------------------------------------------------

    --- What the player can see of `nodeId` right now (§0.3).
    ---
    --- `state` is whatever the host knows: flags, counters, world facts. It is passed to each `when` predicate
    --- untouched and never interpreted here, because the moment this module starts knowing what a flag MEANS it
    --- has become the game.
    ---
    --- A predicate that throws is treated as "not visible" rather than allowed to take the whole projection
    --- down: one bad `when` should cost one choice, not the conversation.
    function M.project(script, nodeId, state)
        if type(script) ~= "table" or type(script.nodes) ~= "table" then return nil, "script_not_table" end
        local id = nonempty(nodeId) and nodeId or script.entry
        local node = script.nodes[id]
        if type(node) ~= "table" then return nil, "unknown_node" end
        state = type(state) == "table" and state or {}

        local say = {}
        for i, line in ipairs(node.say) do say[i] = line end

        local choices, hidden = {}, 0
        for _, choice in ipairs(type(node.choices) == "table" and node.choices or {}) do
            local visible = true
            if type(choice.when) == "function" then
                local ok, result = pcall(choice.when, state)
                visible = ok and result and true or false
            end
            if visible then
                choices[#choices + 1] = {
                    id = choice.id, label = choice.label, to = choice.to,
                    ends = choice.ends == true or nil, effect = choice.effect,
                    -- `sticky` is §2.3's "remains highly visible until Rico is known": deliberate soft guidance,
                    -- surfaced as a rendering hint rather than as a quest marker.
                    sticky = choice.sticky == true or nil,
                    -- §3.4's hidden hardware-curiosity score. Named here and counted by the host; never shown,
                    -- because the draft is explicit that this *"is not a quest meter shown to the player."*
                    curiosity = choice.curiosity,
                }
            else
                hidden = hidden + 1
            end
        end

        return {
            contact = script.contact, node = id, say = say, choices = choices,
            intent = node.intent and tostring(node.intent) or nil,
            hiddenChoices = hidden,
            -- §2.4's context shelf. The shelf is unresolved things the player ALREADY legitimately knows, which
            -- is `player.leads.shelf` -- so this module marks where those items belong and does not invent them.
            -- The host splices them in ABOVE the generic categories, as the draft specifies.
            shelf = node.shelf == true or nil,
            -- A node with nothing to pick is where a conversation rests, not where it breaks. §0.2's
            -- soft-shut door depends on this being a normal state.
            terminal = #choices == 0,
        }
    end

    --- Apply one picked choice. Returns the next node id (or nil when the conversation closes) plus the flag
    --- writes the host should persist and the named effect it should run.
    ---
    --- **This function does not write anything.** It returns an intention. The host owns persistence, and a
    --- choice that was projected from stale state must be re-checked against fresh state by the host, which is
    --- why `pick` re-evaluates `when` rather than trusting that the client saw a legal option.
    function M.pick(script, nodeId, choiceId, state)
        local projection, why = M.project(script, nodeId, state)
        if not projection then return nil, why end
        local node = script.nodes[projection.node]
        for _, choice in ipairs(type(node.choices) == "table" and node.choices or {}) do
            if choice.id == choiceId then
                local visible = true
                if type(choice.when) == "function" then
                    local ok, result = pcall(choice.when, type(state) == "table" and state or {})
                    visible = ok and result and true or false
                end
                if not visible then return nil, "choice_not_available" end
                local writes = {}
                for k, v in pairs(type(choice.set) == "table" and choice.set or {}) do writes[k] = v end
                return {
                    next = choice.to, ends = choice.to == nil,
                    set = writes, effect = choice.effect,
                    label = choice.label,           -- what the player said, for the transcript
                }
            end
        end
        return nil, "unknown_choice"
    end

    -- ---- the trigger budget (§20) ---------------------------------------------------------------------

    --- May this message go out now?
    ---
    --- `facts` = {
    ---   intent, contactId,
    ---   lastIntroductionAt, openIntroductions,     -- across all contacts
    ---   lastFlavourAt, lastContactFlavourAt,       -- global, and for this contact
    ---   pendingConsequence = true,                 -- gameplay traffic is queued: flavour yields to it
    ---   at,
    ---   budget = { ... }                           -- optional per-host overrides
    --- }
    ---
    --- Returns true, or false plus the rule that refused it. The reasons are distinct on purpose: a suppressed
    --- introduction should be retried later, and a suppressed piece of flavour should usually be dropped
    --- forever (§20 rule 7: *"Allow silence"*).
    function M.admit(facts)
        facts = type(facts) == "table" and facts or {}
        local intent = tostring(facts.intent or "")
        if not M.INTENTS[intent] then return false, "invalid_intent" end
        local ok, why = Contacts.speakable(facts.contactId)
        if not ok then return false, why end

        local budget = {}
        for k, v in pairs(M.BUDGET) do budget[k] = v end
        for k, v in pairs(type(facts.budget) == "table" and facts.budget or {}) do
            if posNum(v) then budget[k] = posNum(v) end
        end

        local at = posNum(facts.at) or 0

        -- §20 rule 3. A direct consequence of something the player just did is never rationed: the alternative
        -- is a player who acts and is not answered, which reads as a bug rather than as restraint.
        if intent == "consequence" or intent == "reply" then return true end

        if intent == "introduction" then
            -- **A SOLICITED introduction is not rationed at all**, and getting this wrong is worse than having no
            -- budget. §20's rules exist to stop the WORLD crowding the player; they were never meant to stop the
            -- player opening a door they just asked to have opened. A driver who picks *"Put me through"* and then
            -- waits half an hour for Rico to say hello has been ignored, not paced -- and §20 rule 3 already says
            -- a direct consequence may bypass a cooldown. `solicited` is true when the player picked a choice that
            -- opens this contact, or when a message they have already read named them (§3.1's guaranteed handoff).
            --
            -- It still COUNTS: the host increments the open tally either way, so an unsolicited introduction
            -- cannot pile on top of one the player is in the middle of.
            if facts.solicited == true then return true end
            -- Rule 1: never two at once. This is the rule the draft states most emphatically and the one whose
            -- absence turns a living world into a group chat that drank six energy drinks.
            local open = math.max(0, math.floor(posNum(facts.openIntroductions) or 0))
            if open >= budget.maxOpenIntroductions then return false, "introduction_already_open" end
            local last = posNum(facts.lastIntroductionAt)
            if last and at - last < budget.introductionCooldownSec then return false, "introduction_cooldown" end
            return true
        end

        if intent == "flavour" then
            -- Rule 4: flavour loses to meaningful gameplay messages.
            if facts.pendingConsequence == true then return false, "yields_to_gameplay" end
            local last = posNum(facts.lastFlavourAt)
            if last and at - last < budget.flavourCooldownSec then return false, "flavour_cooldown" end
            local mine = posNum(facts.lastContactFlavourAt)
            if mine and at - mine < budget.perContactFlavourSec then return false, "contact_flavour_cooldown" end
            return true
        end

        -- An offer carries its own deadline and is the reason the player is here; it is rationed only against
        -- introductions, which it is not one of.
        return true
    end

    --- §0.2: a decline closes THAT OFFER IN THAT MOMENT, not the character. And §2.2: *"No nag timer."*
    ---
    --- So a deferral is recorded as a fact the script can project against -- never as a timer that re-offers.
    --- Re-entry must come from one of §0.2's routes, each of which is a player action or a materially new
    --- world fact, and `reentry` names which one applies. A caller that cannot name one gets `false`, which is
    --- the whole point: nothing re-offers just because time passed.
    M.REENTRY = {
        player_asked = true,        -- the player reopened the conversation or picked the shelf item
        shelf = true,               -- a contextual Dex shelf item
        world_event = true,         -- a new event gives the contact a fresh reason to matter
        third_party = true,         -- another character mentioned the same person
        physical = true,            -- the player found them
        milestone = true,           -- a system milestone creating a MATERIALLY DIFFERENT offer
    }

    function M.mayReoffer(facts)
        facts = type(facts) == "table" and facts or {}
        if facts.deferred ~= true then return true end                      -- never declined; nothing to re-enter
        local reason = tostring(facts.reentry or "")
        if not M.REENTRY[reason] then return false, "no_reentry_route" end
        -- A milestone must actually differ. §0.2 says "a materially different offer", so an identical offer
        -- dressed as progress is refused.
        if reason == "milestone" and facts.offerChanged ~= true then return false, "offer_not_materially_different" end
        return true
    end

    return M
end)
