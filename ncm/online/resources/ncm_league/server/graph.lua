-- ncm_league / server / graph -- the quest graph's host: Dex, Setup Stu and Rico (§A.8's first slice).
--
-- This file is the boundary between authored conversation (core `graph.*`, which has no clock, no database and
-- no opinion about delivery) and NCM Online's actual message bus. It does four things and deliberately nothing
-- else:
--
--   1. **Persists where a conversation rests** -- `player_contact.node` plus its flags. Not a step, not a
--      quest, not a completion (`L175`, §0.3).
--   2. **Writes the transcript** into the existing `message` table, which needed exactly one widened ENUM to
--      accept a character as a sender (`IDEA-599`, migration 039). Every line a contact says is a row; every
--      reply the player picks is a row from `from_kind = 'driver'`. A conversation the player can scroll back
--      through is the whole point of the Messages surface being a thread rather than a list of notices.
--   3. **Projects the live choices** at read time and never stores them (§0.3). `graph.conversation.pick`
--      re-checks the predicate server-side, so a stale page cannot force a branch it can no longer see.
--   4. **Rations pushes** through `graph.conversation.admit` (§20) and `NcmComms` (`player.communication`,
--      `IDEA-600`), which are two different questions: the budget decides whether the WORLD should speak, and
--      the pacing policy decides whether this particular message should be SHOWN. Wiring the second one to a
--      real producer is what `IDEA-600` asked for, and the graph is a better first consumer than the seat offer
--      because it is the only thing in NCM that speaks unasked.
--
-- **The leak discipline is load-bearing here.** §3.4's hardware-curiosity score *"is not a quest meter shown to
-- the player"*, `player.leads.openCount` is a SERVER number that must never reach a UI as "3 / 8" (`L171`,
-- `L175`), and the Dex shelf is the lead list rendered as *conversation*, not as a checklist. So the payload
-- this file builds carries names and lines and nothing countable.
NcmGraph = {}

local Core = NcmCore
local Conversation = Core.get("graph.conversation")
local Contacts = Core.get("graph.contacts")
local Opening = Core.get("graph.opening")
local Leads = Core.get("player.leads")
local Json = Core.get("vocabulary.json")
local ids = Core.get("vocabulary.ids")

local function log(fmt, ...) print(("[ncm_league/graph] " .. fmt):format(...)) end
local function now() return math.floor(Open77.time.unix()) end
local function sid() return NcmCalendar.serverId() end
local function hostRng() return math.random() end

--- In-process mirror of every durable read, so a conversation stays usable when the database is unavailable.
--- Honest about its scope: it is this process only and it is not a cache with invalidation, it is a fallback.
local memory = {}          -- driverId -> { contacts = {}, counters = {}, budget = {} }

local function bag(driverId)
    memory[driverId] = memory[driverId] or { contacts = {}, counters = {}, budget = {} }
    return memory[driverId]
end

local function tell(pid, text)
    if pid then pcall(Open77.chat.send, pid, "[NCM] " .. text) end
end

-- ---------------------------------------------------------------------------------------------------------
-- Durable state
-- ---------------------------------------------------------------------------------------------------------

--- One contact row. `flags` is decoded JSON; absent is an empty table, never nil, so a script's predicates
--- never have to guard for it.
local function loadContact(driverId, contactId)
    local mem = bag(driverId).contacts
    if mem[contactId] then return mem[contactId] end
    local row
    if MySQL.isReady() then
        local ok, result = pcall(MySQL.single.await,
            [[SELECT state, node, flags, known_at, last_spoke_at, last_heard_at, last_flavour_at
              FROM player_contact WHERE ncm_driver_id = ? AND server_id = ? AND contact_id = ?]],
            { driverId, sid(), contactId })
        if ok then row = result else log("contact read failed %s/%s: %s", driverId:sub(1, 8), contactId, tostring(result)) end
    end
    if not row then return nil end
    local flags = row.flags
    if type(flags) == "string" then flags = Json.decode(flags) end
    mem[contactId] = {
        contactId = contactId, state = row.state or "known", node = row.node,
        flags = type(flags) == "table" and flags or {},
        knownAt = tonumber(row.known_at), lastSpokeAt = tonumber(row.last_spoke_at),
        lastHeardAt = tonumber(row.last_heard_at), lastFlavourAt = tonumber(row.last_flavour_at),
    }
    return mem[contactId]
end

-- **Every nullable parameter carries a sentinel.** OPEN//77's bridge measures `#values`, and a Lua array with
-- a nil in it has no dependable length -- `{a,b,c,nil,nil,nil}` is 3 -- so a nil does not become SQL NULL, it
-- makes a hole and the statement is refused outright with `parameter_count_mismatch`. A fresh contact has THREE
-- nil timestamps and usually a nil node, so this table is the worst case for it.
--
-- `market_knowledge.lua` set the precedent with `NULLIF(?, '')` for an absent string; a nullable BIGINT gets
-- `NULLIF(?, 0)`, because 0 is never a valid unix time here. Found on the live server after deploy: the same
-- fault had been silently failing every `player_message_exposure` write since that table shipped.
local function saveContact(driverId, contact)
    bag(driverId).contacts[contact.contactId] = contact
    if not MySQL.isReady() then return end
    local ok, err = pcall(MySQL.insert.await,
        [[INSERT INTO player_contact
            (ncm_driver_id, server_id, contact_id, state, node, flags, known_at, last_spoke_at, last_heard_at, last_flavour_at)
          VALUES (?, ?, ?, ?, NULLIF(?, ''), ?, ?, NULLIF(?, 0), NULLIF(?, 0), NULLIF(?, 0))
          ON DUPLICATE KEY UPDATE state = VALUES(state), node = VALUES(node), flags = VALUES(flags),
            last_spoke_at = VALUES(last_spoke_at), last_heard_at = VALUES(last_heard_at),
            last_flavour_at = VALUES(last_flavour_at)]],
        { driverId, sid(), contact.contactId, contact.state or "known", contact.node or "",
          Json.encode(contact.flags or {}), contact.knownAt or now(),
          contact.lastSpokeAt or 0, contact.lastHeardAt or 0, contact.lastFlavourAt or 0 })
    if not ok then log("contact write failed %s/%s: %s", driverId:sub(1, 8), contact.contactId, tostring(err)) end
end

--- Every flag the scripts may project against, for one driver. Flags live per contact but the graph is one
--- world: Stu must be able to see that Dex has spoken, and Rico's Needle push is driven by what the player did
--- through Stu (§0.7). So the state handed to a projection is the UNION of every contact's flags, plus the
--- counters, plus what the host itself knows.
---
--- Collisions are impossible by convention rather than by accident: a flag is named for its subject
--- (`ricoKnown`, `qfIntroDeferred`), never for its writer.
local function projectionState(driverId, extra)
    local state = {}
    for contactId, contact in pairs(bag(driverId).contacts) do
        for k, v in pairs(contact.flags or {}) do state[k] = v end
        -- "Known" means THE PLAYER HAS HEARD FROM THEM, which is `lastSpokeAt`, not the existence of a row.
        --
        -- A row can exist while the introduction has not landed -- the §20 budget may have rationed it away, and
        -- it is still owed. Keying this to the row instead made a rationed introduction unrecoverable: the push
        -- that would retry it requires `not stuKnown`, so the contact was simultaneously "known" to the trigger
        -- and silent to the player, forever. Found by `tools/test-quest-graph.lua`.
        state[contactId .. "Known"] = state[contactId .. "Known"] or (contact.lastSpokeAt ~= nil)
    end
    for name, value in pairs(bag(driverId).counters) do state[name] = value end
    for k, v in pairs(type(extra) == "table" and extra or {}) do state[k] = v end
    return state
end

-- ---- hidden counters (§3.4) -------------------------------------------------------------------------------
-- Never rendered. `player_behaviour_counter` exists so the draft's *"this score is not a quest meter shown to
-- the player"* is a property of where the number lives, not a promise about who remembers to hide it.

local function loadCounters(driverId)
    local mem = bag(driverId)
    if mem.countersLoaded then return mem.counters end
    mem.countersLoaded = true
    if MySQL.isReady() then
        local ok, rows = pcall(MySQL.query.await,
            "SELECT counter, value FROM player_behaviour_counter WHERE ncm_driver_id = ? AND server_id = ?",
            { driverId, sid() })
        if ok then for _, r in ipairs(rows or {}) do mem.counters[r.counter] = tonumber(r.value) or 0 end end
    end
    return mem.counters
end

local function bumpCounter(driverId, counter, by)
    local counters = loadCounters(driverId)
    counters[counter] = (counters[counter] or 0) + (tonumber(by) or 1)
    if MySQL.isReady() then
        pcall(MySQL.insert.await,
            [[INSERT INTO player_behaviour_counter (ncm_driver_id, server_id, counter, value, last_moved_at)
              VALUES (?, ?, ?, ?, ?)
              ON DUPLICATE KEY UPDATE value = value + VALUES(value), last_moved_at = VALUES(last_moved_at)]],
            { driverId, sid(), counter, tonumber(by) or 1, now() })
    end
    return counters[counter]
end

-- ---- the §20 budget, per driver ---------------------------------------------------------------------------

local function loadBudget(driverId)
    local mem = bag(driverId)
    if mem.budgetLoaded then return mem.budget end
    mem.budgetLoaded = true
    if MySQL.isReady() then
        local ok, row = pcall(MySQL.single.await,
            [[SELECT open_introductions, last_introduction_at, last_flavour_at
              FROM player_graph_budget WHERE ncm_driver_id = ? AND server_id = ?]],
            { driverId, sid() })
        if ok and row then
            mem.budget = { openIntroductions = tonumber(row.open_introductions) or 0,
                           lastIntroductionAt = tonumber(row.last_introduction_at),
                           lastFlavourAt = tonumber(row.last_flavour_at) }
        end
    end
    mem.budget.openIntroductions = mem.budget.openIntroductions or 0
    return mem.budget
end

local function saveBudget(driverId)
    local budget = bag(driverId).budget
    if not MySQL.isReady() then return end
    pcall(MySQL.insert.await,
        [[INSERT INTO player_graph_budget (ncm_driver_id, server_id, open_introductions, last_introduction_at, last_flavour_at)
          VALUES (?, ?, ?, NULLIF(?, 0), NULLIF(?, 0))
          ON DUPLICATE KEY UPDATE open_introductions = VALUES(open_introductions),
            last_introduction_at = VALUES(last_introduction_at), last_flavour_at = VALUES(last_flavour_at)]],
        { driverId, sid(), budget.openIntroductions or 0,
          budget.lastIntroductionAt or 0, budget.lastFlavourAt or 0 })
end

-- ---------------------------------------------------------------------------------------------------------
-- The transcript
-- ---------------------------------------------------------------------------------------------------------

local function threadId(contactId) return "contact:" .. tostring(contactId) end

--- One row per line. `state` is `read` for the contact's own lines because a conversation the player is looking
--- at is not an unread notice -- unread is reserved for a beat that arrived while they were elsewhere.
local function writeLine(driverId, contactId, text, opts)
    opts = type(opts) == "table" and opts or {}
    local id = ids.uuid4(hostRng)
    local contact = Contacts.get(contactId)
    if not MySQL.isReady() then return id end
    local ok, err = pcall(MySQL.insert.await,
        [[INSERT INTO message (message_id, server_id, to_driver_id, thread_id, from_kind, from_id, kind,
            subject, body, state, ref_kind, ref_id, created_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULLIF(?, ''), NULLIF(?, ''), ?)]],
        { id, sid(), driverId, threadId(contactId),
          opts.fromDriver and "driver" or "character",
          opts.fromDriver and driverId or contactId,
          opts.kind or "conversation",
          opts.subject or (contact and contact.label) or contactId,
          text, opts.state or "read", opts.refKind or "", opts.refId or "", now() })
    if not ok then log("line write failed %s/%s: %s", driverId:sub(1, 8), contactId, tostring(err)) end
    return id
end

--- One thread, oldest first -- which is how a conversation reads and the opposite of how the notice inbox was
--- ordered. Bounded: a transcript is unbounded in principle and `IDEA-595` applies to every payload.
local THREAD_LIMIT = 60

local function threadLines(driverId, contactId)
    if not MySQL.isReady() then return {} end
    local ok, rows = pcall(MySQL.query.await,
        [[SELECT message_id, from_kind, from_id, body, state, created_at FROM message
          WHERE server_id = ? AND to_driver_id = ? AND thread_id = ?
          ORDER BY created_at DESC, message_id DESC LIMIT ]] .. THREAD_LIMIT,
        { sid(), driverId, threadId(contactId) })
    if not ok then return {} end
    local out = {}
    for i = #(rows or {}), 1, -1 do                      -- newest-first query, oldest-first render
        local r = rows[i]
        out[#out + 1] = { id = r.message_id, mine = r.from_kind == "driver", body = r.body,
                          state = r.state, at = tonumber(r.created_at) }
    end
    return out
end

-- ---------------------------------------------------------------------------------------------------------
-- Effects
-- ---------------------------------------------------------------------------------------------------------

--- A choice names an intention; this performs it. Unknown effects are LOGGED and ignored rather than silently
--- dropped, because an authored effect nobody implemented is the one bug a player experiences as "the
--- conversation did nothing".
---
--- `lead:<subjectKind>:<ref>` is the important one. A character mentioning somebody who is not authored yet
--- grants a **lead**, never a contact (`L175`): knowledge without access. This is the first producer
--- `IDEA-625` asked for -- character reveals.
local function runEffect(pid, driverId, contactId, effect)
    if type(effect) ~= "string" or effect == "" then return end
    local kind, a, b = effect:match("^(%a+):([%w_]+):?([%w_]*)$")
    if kind == "open" then
        -- Always solicited: an `open:` effect exists only on a choice the player just picked.
        NcmGraph.meet(pid, driverId, a, { via = contactId, solicited = true })
    elseif kind == "lead" then
        NcmGraph.lead(driverId, { subjectKind = a, subjectRef = b ~= "" and b or a,
                                  sourceKind = "character", sourceRef = contactId })
    else
        log("unimplemented effect '%s' from %s", effect, contactId)
    end
end

--- Record a lead. Refusals are distinct on purpose (`player.leads.admit`): "you can already use this" and "you
--- were already told" are different facts, and a character should be able to react differently to each.
function NcmGraph.lead(driverId, def)
    local existing
    if MySQL.isReady() then
        local ok, row = pcall(MySQL.single.await,
            [[SELECT state FROM lead WHERE ncm_driver_id = ? AND server_id = ? AND subject_kind = ? AND subject_ref = ?]],
            { driverId, sid(), tostring(def.subjectKind), tostring(def.subjectRef) })
        if ok and row then existing = { state = row.state } end
    end
    -- A person is "already accessible" exactly when we have met them. That is the contact row, not the lead.
    local accessible = def.subjectKind == "person" and loadContact(driverId, tostring(def.subjectRef)) ~= nil
    local admit, why, lead = Leads.admit(def, { existing = existing, subjectAlreadyAccessible = accessible })
    if not admit then
        log("lead refused %s:%s for %s -- %s", tostring(def.subjectKind), tostring(def.subjectRef),
            driverId:sub(1, 8), tostring(why))
        return false, why
    end
    if MySQL.isReady() then
        pcall(MySQL.insert.await,
            [[INSERT INTO lead (ncm_driver_id, server_id, subject_kind, subject_ref, source_kind, source_ref, note, state, created_at)
              VALUES (?, ?, ?, ?, ?, NULLIF(?, ''), NULLIF(?, ''), 'open', ?)
              ON DUPLICATE KEY UPDATE note = COALESCE(lead.note, VALUES(note))]],
            { driverId, sid(), lead.subjectKind, lead.subjectRef, lead.sourceKind, lead.sourceRef or "",
              lead.note or "", now() })
    end
    log("LEAD %s:%s via %s for %s", lead.subjectKind, lead.subjectRef, tostring(lead.sourceRef), driverId:sub(1, 8))
    return true
end

--- The open shelf (§2.4), as names rather than as a count. `Leads.shelf` bounds the display; the COUNT stays on
--- the server, because `L171` and `L175` both forbid a completion number reaching a player-facing surface.
local function openLeads(driverId)
    if not MySQL.isReady() then return {} end
    local ok, rows = pcall(MySQL.query.await,
        [[SELECT subject_kind, subject_ref, source_kind, source_ref, note, state, created_at FROM lead
          WHERE server_id = ? AND ncm_driver_id = ? AND state = 'open' ORDER BY created_at DESC LIMIT 24]],
        { sid(), driverId })
    if not ok then return {} end
    local leads = {}
    for _, r in ipairs(rows or {}) do
        leads[#leads + 1] = { subjectKind = r.subject_kind, subjectRef = r.subject_ref,
                              sourceKind = r.source_kind, sourceRef = r.source_ref,
                              note = r.note, state = r.state, at = tonumber(r.created_at),
                              key = r.subject_kind .. ":" .. r.subject_ref }
    end
    return Leads.shelf(leads, 6)
end

--- A shelf item's label. A lead about a person NCM knows about uses their name; anything else states its
--- subject plainly. No "unresolved", no counter, no progress -- it is a thing to ask about, not a task.
local function shelfLabel(lead)
    if lead.subjectKind == "person" then
        local c = Contacts.get(lead.subjectRef)
        local name = c and c.name or lead.subjectRef
        return ("Who is %s?"):format(name)
    end
    return ("About that %s..."):format(lead.subjectKind)
end

-- ---------------------------------------------------------------------------------------------------------
-- Meeting somebody, and speaking
-- ---------------------------------------------------------------------------------------------------------

--- Make a contact known and push their entry beat. Idempotent: meeting somebody twice is a no-op, which
--- matters because several routes legitimately arrive at the same introduction (§0.2's re-entry list).
function NcmGraph.meet(pid, driverId, contactId, opts)
    opts = type(opts) == "table" and opts or {}
    local speakable, why = Contacts.speakable(contactId)
    if not speakable then
        -- This is the guard that keeps the graph honest: a script may MENTION anybody, but only an authored
        -- contact can be opened. Everything else is a lead.
        log("refusing to open '%s': %s", tostring(contactId), tostring(why))
        return false, why
    end
    if loadContact(driverId, contactId) then return true, "already_known" end

    local script = Opening.script(contactId)
    if not script then return false, "no_script" end
    local contact = { contactId = contactId, state = "known", node = nil, flags = {}, knownAt = now() }
    saveContact(driverId, contact)

    -- A lead about this person has done its job (`player.leads.resolve`). Leads close from several directions at
    -- once and the second arrival is normal, not a fault.
    if MySQL.isReady() then
        pcall(MySQL.update.await,
            [[UPDATE lead SET state = 'closed', resolved_at = ?, resolved_reason = ?
              WHERE ncm_driver_id = ? AND server_id = ? AND subject_kind = 'person' AND subject_ref = ? AND state = 'open']],
            { now(), "met", driverId, sid(), contactId })
    end

    log("MET %s by %s (via %s)%s", contactId, driverId:sub(1, 8), tostring(opts.via or "system"),
        opts.solicited and " [solicited]" or "")
    NcmGraph.speak(pid, driverId, contactId, script.entry,
        { intent = "introduction", unread = true, solicited = opts.solicited })
    return true
end

--- Say a node's lines, move the conversation to it, and pace the notification.
---
--- The two-gate structure is deliberate and is the answer to §20 plus `IDEA-600`: `Conversation.admit` decides
--- whether the WORLD should speak right now, and `NcmComms.send` decides whether this particular message should
--- be SHOWN. They are different questions and conflating them is how a world becomes either silent or a group
--- chat that drank six energy drinks.
function NcmGraph.speak(pid, driverId, contactId, nodeId, opts)
    opts = type(opts) == "table" and opts or {}
    local script = Opening.script(contactId)
    if not script then return false, "no_script" end
    local contact = loadContact(driverId, contactId)
    if not contact then return false, "not_known" end

    local projection, why = Conversation.project(script, nodeId, projectionState(driverId))
    if not projection then log("projection failed %s.%s: %s", contactId, tostring(nodeId), tostring(why)); return false, why end

    local intent = opts.intent or projection.intent or "reply"
    local budget = loadBudget(driverId)
    local admitted, refusal = Conversation.admit{
        intent = intent, contactId = contactId, at = now(),
        openIntroductions = budget.openIntroductions,
        lastIntroductionAt = budget.lastIntroductionAt,
        lastFlavourAt = budget.lastFlavourAt,
        lastContactFlavourAt = contact.lastFlavourAt,
        pendingConsequence = opts.pendingConsequence,
        -- The player asked for this one (a picked `open:` choice, or a handoff a delivered message named).
        solicited = opts.solicited == true,
    }
    if not admitted then
        log("budget refused %s.%s (%s): %s", contactId, projection.node, intent, tostring(refusal))
        return false, refusal
    end

    -- A node whose choices are all hidden still says its lines; a node that projects nothing at all does not,
    -- because that is a beat this player's state made irrelevant rather than a silent one.
    for _, line in ipairs(projection.say) do
        writeLine(driverId, contactId, line, { state = opts.unread and "unread" or "read" })
    end

    contact.node = projection.node
    contact.lastSpokeAt = now()
    if intent == "flavour" then contact.lastFlavourAt = now() end
    -- Remember that the WORLD said this one, so it is never pushed again (see the guard in `tick`). A node the
    -- player reached by replying is not marked, because re-entering a conversation is not a push.
    if opts.pushed then contact.flags["pushed:" .. projection.node] = true end
    saveContact(driverId, contact)

    if intent == "introduction" then
        budget.openIntroductions = (budget.openIntroductions or 0) + 1
        budget.lastIntroductionAt = now()
    end
    if intent == "flavour" then budget.lastFlavourAt = now() end
    saveBudget(driverId)

    -- The notification. `player.communication` owns priority, repeat policy and durable exposure; the graph owns
    -- none of it. The key is per contact and node, so re-entering a conversation does not re-toast an old beat.
    if pid and type(NcmComms) == "table" then
        local c = Contacts.get(contactId)
        local priority = (intent == "introduction" and "actionable")
            or (intent == "offer" and "actionable")
            or (intent == "flavour" and "ambient" or "informative")
        pcall(NcmComms.send, pid, {
            id = ("graph.%s.%s"):format(contactId, projection.node),
            category = "messages", priority = priority,
            title = ("NEW MESSAGE - %s"):format(c and c.label or contactId),
            message = projection.say[1] or "",
            actionHint = "F6 -> MESSAGES",
            repeatPolicy = { mode = "once" },
        })
    end
    return true, projection
end

-- ---------------------------------------------------------------------------------------------------------
-- The player replies
-- ---------------------------------------------------------------------------------------------------------

function NcmGraph.reply(pid, driverId, contactId, choiceId)
    local script = Opening.script(contactId)
    local contact = script and loadContact(driverId, contactId)
    if not contact then return false, "not_known" end

    local state = projectionState(driverId)
    local move, why = Conversation.pick(script, contact.node or script.entry, choiceId, state)
    if not move then
        -- The page offered something the server will not honour: almost always a stale panel, occasionally a
        -- flag that moved underneath it. Either way the server's answer is authoritative (§0.3).
        log("reply refused %s.%s/%s: %s", contactId, tostring(contact.node), tostring(choiceId), tostring(why))
        return false, why
    end

    -- The transcript records what the player said BEFORE anything it caused, so the thread reads in order.
    writeLine(driverId, contactId, move.label, { fromDriver = true })

    for key, value in pairs(move.set or {}) do contact.flags[key] = value end
    contact.lastHeardAt = now()
    saveContact(driverId, contact)

    -- §3.4: a substantive interaction moves the hidden counter. This is the mechanism behind §0.7 -- Rico
    -- reacting to what the player did through Stu.
    local chosen
    for _, choice in ipairs(script.nodes[contact.node or script.entry].choices or {}) do
        if choice.id == choiceId then chosen = choice end
    end
    if chosen and chosen.curiosity then
        local score = bumpCounter(driverId, "hardwareCuriosity", 1)
        log("curiosity %s -> %d (%s)", driverId:sub(1, 8), score, chosen.curiosity)
        -- Arms §8.1's cooldown. Rico's reaction is not scheduled here -- the handler only makes
        -- `stuCooldownElapsed` true later, and the push still has to satisfy the threshold and the budget.
        TriggerEvent("ncm:graph.curiosity", pid, driverId)
    end

    -- Replying to an introduction closes it out of the budget: §20 rule 1 counts introductions the player has
    -- not yet engaged with, not introductions that ever happened.
    --
    -- **This must happen BEFORE the effects.** Accepting Dex's introduction opens Rico, and if Dex's own slot were
    -- still occupied at that moment the §20 budget would refuse Rico's opening -- silently rationing away the beat
    -- the player just asked for. Answering a contact frees the slot; what the answer then causes is separate.
    local budget = loadBudget(driverId)
    if (budget.openIntroductions or 0) > 0 and contact.node == script.entry then
        budget.openIntroductions = budget.openIntroductions - 1
        saveBudget(driverId)
    end

    if move.effect then runEffect(pid, driverId, contactId, move.effect) end

    if move.next then
        NcmGraph.speak(pid, driverId, contactId, move.next, { intent = "reply" })
    else
        contact.node = nil
        saveContact(driverId, contact)
    end
    return true
end

-- ---------------------------------------------------------------------------------------------------------
-- What the panel reads
-- ---------------------------------------------------------------------------------------------------------

--- The Messages payload: one entry per known thread, plus the live projection for the selected one.
---
--- Carries names and lines and nothing countable. No lead count, no curiosity score, no completion.
function NcmGraph.threads(driverId, selected)
    local out, state = {}, projectionState(driverId)
    for _, contactId in ipairs(Contacts.ids(true)) do
        local contact = loadContact(driverId, contactId)
        if contact then
            local c = Contacts.get(contactId)
            local lines = threadLines(driverId, contactId)
            local unread = 0
            for _, line in ipairs(lines) do if line.state == "unread" then unread = unread + 1 end end
            local preview = lines[#lines]
            out[#out + 1] = {
                contactId = contactId, name = c.name, label = c.label,
                unread = unread, at = contact.lastSpokeAt or contact.knownAt,
                preview = preview and preview.body or nil,
                previewMine = preview and preview.mine or nil,
            }
        end
    end
    table.sort(out, function(a, b) return (a.at or 0) > (b.at or 0) end)

    -- Default to whichever conversation spoke most recently, so opening Messages lands somewhere rather than
    -- on an empty pane.
    local pick = selected
    if not pick or not loadContact(driverId, pick) then pick = out[1] and out[1].contactId or nil end

    local thread, lines
    if pick then
        local contact = loadContact(driverId, pick)
        local script = Opening.script(pick)
        local c = Contacts.get(pick)
        local projection = script and Conversation.project(script, contact.node or script.entry, state) or nil
        local choices = {}
        for _, choice in ipairs((projection or {}).choices or {}) do
            -- `curiosity` is deliberately NOT sent: the page must not be able to show, or infer, a hidden score.
            choices[#choices + 1] = { id = choice.id, label = choice.label, sticky = choice.sticky }
        end
        -- §2.4's context shelf: unresolved people and things the player already knows about, spliced in ABOVE
        -- the generic categories, as conversation rather than as a list of objectives.
        local shelf = {}
        if projection and projection.shelf then
            for _, lead in ipairs(openLeads(driverId)) do
                shelf[#shelf + 1] = { key = lead.key, label = shelfLabel(lead), subjectKind = lead.subjectKind }
            end
        end
        thread = {
            contactId = pick, name = c.name, label = c.label,
            domain = c.domainList and c.domainList[1] or nil,
            choices = choices, shelf = shelf,
            resting = projection == nil or projection.terminal or false,
        }
        lines = threadLines(driverId, pick)
    end
    -- `lines` is TOP LEVEL rather than inside `thread` because it is the one unbounded part of this payload and
    -- `NcmStream` splits exactly one list. The sidebar and the choices ride in the head, which is bounded by the
    -- authored roster; a transcript is not. `KB-86` was precisely a growing list sitting in a head.
    return { threads = out, thread = thread, lines = lines or {}, at = now() }
end

local function pushThreads(pid, driverId, selected)
    if not pid then return end
    local payload = NcmGraph.threads(driverId, selected)
    -- KB-97: message BODIES may never travel on a `player(id)` bag, which every client in the routing bucket
    -- can read. `NcmStream` is the targeted, chunked transport the inbox was deliberately moved onto.
    pcall(function() NcmStream.send(pid, "ncm:graph", payload, "lines") end)
    return payload
end
NcmGraph.pushThreads = pushThreads

--- Mark a thread read. A conversation the player is looking at is not an unread notice.
local function markRead(driverId, contactId)
    if not MySQL.isReady() then return end
    pcall(MySQL.update.await,
        [[UPDATE message SET state = 'read'
          WHERE server_id = ? AND to_driver_id = ? AND thread_id = ? AND state = 'unread']],
        { sid(), driverId, threadId(contactId) })
end

-- ---------------------------------------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------------------------------------

--- Offer at most ONE thing (§20 rule 1). `Opening.pushable` answers "has this player's life made it relevant"
--- (§0.1); the budget answers "may it go out now". Both must hold, and the first that does wins -- the rest
--- stay relevant and will be offered on a later tick, which is what makes silence a normal state rather than a
--- lost beat.
function NcmGraph.tick(pid, driverId, extra)
    loadCounters(driverId)
    loadBudget(driverId)
    local state = projectionState(driverId, extra)
    for _, push in ipairs(Opening.pushable(state)) do
        local contact = loadContact(driverId, push.contact)
        local script = Opening.script(push.contact) or {}
        if not contact then
            -- Not met yet: meeting somebody is what says their opening.
            if push.node == script.entry
                and NcmGraph.meet(pid, driverId, push.contact, { via = "tick", solicited = push.solicited }) then
                return push
            end
        elseif contact.node == push.node then
            -- Already resting exactly there, waiting for the player. Saying it again is not a reminder, it is a
            -- duplicate -- and §20 rule 5 is explicit that a deferred beat must not nag on a timer.
            log("push %s.%s skipped: the conversation is already resting there", push.contact, push.node)
        elseif push.node == script.entry and contact.lastSpokeAt then
            -- The entry beat has already been delivered once. A contact does not reintroduce themselves.
            log("push %s.%s skipped: already introduced", push.contact, push.node)
        elseif contact.flags["pushed:" .. push.node] == true then
            -- **A world-initiated beat is said ONCE.** Found by `tools/test-quest-graph.lua`: after the player
            -- walked Rico's Needle thread to its end, the trigger for its FIRST beat was still satisfied -- the
            -- authored condition watches `needleKnown` and `needleDeferred`, and asking for an introduction to
            -- somebody unauthored sets neither. So Rico opened the same conversation again on the next tick.
            --
            -- Fixing it per character would mean one bookkeeping flag per offer and a new one for every beat Pass
            -- 2 adds -- which is the same omission waiting to happen. This is the general rule instead, and it is
            -- the one the draft already states: re-entry comes from a PLAYER ACTION (§0.2), never from the clock,
            -- so the world gets one push per beat and the sticky shelf items are how a player comes back.
            log("push %s.%s skipped: already pushed once", push.contact, push.node)
        else
            -- Includes the retry case that made this guard necessary: a beat the budget rationed away is still
            -- relevant, and `lastSpokeAt` being nil is exactly how we know it never actually landed.
            if NcmGraph.speak(pid, driverId, push.contact, push.node,
                { intent = push.intent, unread = true, solicited = push.solicited, pushed = true }) then
                return push
            end
        end
    end
    return nil
end

--- Session entry (§2.1: "first NCM session after onboarding eligibility").
---
--- Deliberately delayed and deliberately independent of every other boot step. A player who joins should meet
--- Dispatch, not race a loading screen against him.
local ENTRY_DELAY_MS = 20000

function NcmGraph.onSessionEntry(pid)
    pid = tonumber(pid) or 0
    if pid <= 0 then return end
    CreateThread(function()
        Wait(ENTRY_DELAY_MS)
        local driver = NcmCalendar.resolveDriver(pid)
        if not driver then return end
        -- Stu's handoff and Dex's opening are two beats, and §20 rule 1 forbids them arriving together. Dex
        -- lands now; Stu lands on a later tick, after the player has had a moment with Dispatch.
        local ok, err = pcall(NcmGraph.tick, pid, driver.ncmDriverId, { sessionEntry = true })
        if not ok then log("session entry failed for %d: %s", pid, tostring(err)) end
    end)
end

AddEventHandler("onPlayerReady", function(playerId) NcmGraph.onSessionEntry(playerId) end)

--- The in-process fallback is per process AND per driver; a disconnect must not leave a stale conversation
--- behind for whoever takes that player id next.
AddEventHandler("onPlayerDisconnected", function(playerId)
    local driver = NcmCalendar.resolveDriver(tonumber(playerId) or 0)
    if driver then memory[driver.ncmDriverId] = nil end
end)

--- A slow heartbeat, because most of the graph's triggers are things that become true while the player is
--- driving rather than things that happen at a call site. Deliberately slow: the budget is measured in tens of
--- minutes, so polling faster would only burn queries to be refused.
local TICK_SEC = 300

CreateThread(function()
    Wait(45000)
    while true do
        local okAll, players = pcall(Open77.players.all)
        for _, pid in ipairs(okAll and players or {}) do
            local driver = NcmCalendar.resolveDriver(pid)
            if driver then
                local ok, err = pcall(NcmGraph.tick, pid, driver.ncmDriverId, {})
                if not ok then log("tick failed for %d: %s", pid, tostring(err)) end
            end
        end
        Wait(TICK_SEC * 1000)
    end
end)

--- §8.1's cooldown, as a fact rather than a timer. Rico may not react to hardware curiosity in the same breath
--- as the Stu conversation that caused it, or he reads as a wiretap instead of as a man with ears.
local STU_COOLDOWN_SEC = 20 * 60

AddEventHandler("ncm:graph.curiosity", function(pid, driverId)
    local contact = loadContact(driverId, "stu")
    if not contact then return end
    CreateThread(function()
        Wait(STU_COOLDOWN_SEC * 1000)
        local driver = NcmCalendar.resolveDriver(pid)
        if not driver or driver.ncmDriverId ~= driverId then return end
        NcmGraph.tick(pid, driverId, { stuCooldownElapsed = true })
    end)
end)

-- ---------------------------------------------------------------------------------------------------------
-- Net events and chat twins
-- ---------------------------------------------------------------------------------------------------------

local function caller()
    local pid = tonumber(source) or 0
    if pid <= 0 then return nil end
    local driver = NcmCalendar.resolveDriver(pid)
    if not driver then return nil end
    return pid, driver.ncmDriverId
end

RegisterNetEvent("ncm:graph.threads", function(selected)
    local pid, driverId = caller()
    if not pid then return end
    pushThreads(pid, driverId, type(selected) == "string" and selected or nil)
end)

RegisterNetEvent("ncm:graph.open", function(contactId)
    local pid, driverId = caller()
    if not pid or type(contactId) ~= "string" then return end
    markRead(driverId, contactId)
    pushThreads(pid, driverId, contactId)
end)

RegisterNetEvent("ncm:graph.reply", function(contactId, choiceId)
    local pid, driverId = caller()
    if not pid or type(contactId) ~= "string" or type(choiceId) ~= "string" then return end
    local ok, why = NcmGraph.reply(pid, driverId, contactId, choiceId)
    if not ok then tell(pid, "That reply is no longer available (" .. tostring(why) .. ").") end
    pushThreads(pid, driverId, contactId)
end)

--- The context shelf is a question about somebody, so asking it is a reply like any other -- except that the
--- shelf item is generated from a lead rather than authored, so it routes to the contact's own question about
--- that subject. Pass 1 answers it honestly: Dex says what he knows of the name and no more.
RegisterNetEvent("ncm:graph.shelf", function(contactId, key)
    local pid, driverId = caller()
    if not pid or type(contactId) ~= "string" or type(key) ~= "string" then return end
    local subjectKind, subjectRef = key:match("^(%a+):(.+)$")
    if subjectKind ~= "person" then tell(pid, "Nothing to ask about that yet."); return end
    local c = Contacts.get(subjectRef)
    local name = c and c.name or subjectRef
    writeLine(driverId, contactId, ("Who is %s?"):format(name), { fromDriver = true })
    -- Honest: NCM has not authored these people yet, and saying so in character beats a dead end.
    local answer = c and c.note
        and ("%s. Past that you'd have to meet them."):format(c.note:gsub("%s*%(.-%)%s*$", ""))
        or ("Name I've heard. Not somebody I can put you through to.")
    writeLine(driverId, contactId, answer, {})
    pushThreads(pid, driverId, contactId)
end)

--- Chat twins (§14's rule, and the one this repository keeps: essential information must never be reachable
--- through exactly one graphical path).
RegisterCommand("ncm.msgs.list", function(src)
    local pid = tonumber(src) or 0
    local driver = pid > 0 and NcmCalendar.resolveDriver(pid)
    if not driver then return end
    local payload = NcmGraph.threads(driver.ncmDriverId)
    if #payload.threads == 0 then tell(pid, "No conversations yet."); return end
    for _, t in ipairs(payload.threads) do
        tell(pid, ("%s%s - %s"):format(t.label, t.unread > 0 and (" (" .. t.unread .. " new)") or "",
            tostring(t.preview or ""):sub(1, 90)))
    end
    tell(pid, "Open Messages with F6. /ncm.say <contact> <n> to reply from chat.")
end, false)

RegisterCommand("ncm.say", function(src, args)
    local pid = tonumber(src) or 0
    local driver = pid > 0 and NcmCalendar.resolveDriver(pid)
    if not driver then return end
    local contactId = tostring((args or {})[1] or ""):lower()
    local n = tonumber((args or {})[2])
    local payload = NcmGraph.threads(driver.ncmDriverId, contactId)
    local thread = payload.thread
    if not thread then tell(pid, "No such conversation."); return end
    if not n then
        for i, choice in ipairs(thread.choices) do tell(pid, ("%d. %s"):format(i, choice.label)) end
        if #thread.choices == 0 then tell(pid, "Nothing to say right now.") end
        return
    end
    local choice = thread.choices[n]
    if not choice then tell(pid, "No reply " .. n .. "."); return end
    NcmGraph.reply(pid, driver.ncmDriverId, thread.contactId, choice.id)
end, false)

--- Console only. The graph's triggers are behavioural and most of them take real play to satisfy, which makes
--- the first slice nearly untestable without a way to say "pretend this player has done that".
RegisterCommand("ncm.graph.push", function(src, args)
    if (tonumber(src) or 0) > 0 then return end             -- console only
    local pid = tonumber((args or {})[1])
    local contactId = tostring((args or {})[2] or "")
    local nodeId = tostring((args or {})[3] or "")
    local driver = pid and NcmCalendar.resolveDriver(pid)
    if not driver then log("usage: ncm.graph.push <playerId> <contact> [node]"); return end
    if nodeId == "" then
        local ok, why = NcmGraph.meet(pid, driver.ncmDriverId, contactId, { via = "console" })
        log("meet %s -> %s (%s)", contactId, tostring(ok), tostring(why))
    else
        local ok, why = NcmGraph.speak(pid, driver.ncmDriverId, contactId, nodeId, { intent = "offer", unread = true })
        log("speak %s.%s -> %s (%s)", contactId, nodeId, tostring(ok), tostring(why))
    end
    pushThreads(pid, driver.ncmDriverId, contactId)
end, true)

log("quest graph ready: %d authored contact(s), %d push(es)", #Contacts.ids(true), #Opening.PUSHES)
