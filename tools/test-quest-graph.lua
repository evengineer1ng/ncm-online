-- Host-adapter regression for `ncm_league/server/graph.lua` -- the quest graph's first slice.
--
-- The core modules are covered offline by `test_conversation` and `test_opening`. What those cannot reach is the
-- half where the bugs actually live: the adapter that turns an authored conversation into database rows, decides
-- what the panel is allowed to see, and spends the §20 budget. Four things in particular are worth pinning:
--
--   1. **`message.from_kind` really is widened.** Migration 039 exists so a character can be a sender; if the
--      ENUM and the INSERT ever disagree, every line silently fails to write and the conversation is empty. The
--      only honest test is to assert the value the adapter actually sends.
--   2. **The payload leaks nothing countable.** `L171`/`L175` and §3.4 forbid a lead count, a completion
--      fraction or the hidden curiosity score reaching a player-facing surface. This walks the whole payload and
--      asserts it.
--   3. **The projection state is the UNION across contacts.** Rico's Needle push is driven by what the player did
--      through Stu (§0.7), which only works if one contact's flags are visible to another's script.
--   4. **Only an authored contact can be opened.** A script may mention anybody; `Contacts.speakable` is what
--      stops a mention becoming a contact who then cannot answer.
local root = arg[1] or "."
local unpack = table.unpack or unpack

-- ---- host doubles ----------------------------------------------------------------------------------------
local clock = 1000000
local rows = { message = {}, player_contact = {}, counters = {}, budget = {}, lead = {} }
local chat, notices, streams, events = {}, {}, {}, {}

Open77 = {
    time = { unix = function() return clock end },
    chat = { send = function(pid, text) chat[#chat + 1] = { pid = pid, text = text } end },
    notifications = { send = function(pid, def) notices[#notices + 1] = def end },
    players = { all = function() return {} end },
}

NcmCalendar = {
    serverId = function() return "test-world" end,
    resolveDriver = function(pid) return pid == 7 and { ncmDriverId = "driver-0001", display = "Tester" } or nil end,
}

--- A deliberately dumb SQL double: it recognises the handful of statements this adapter issues and records them.
--- Anything it does not recognise is a FAILURE rather than a silent success, because a query the double ignores
--- is a query nobody is testing.
local unknownQueries = {}

local function normalise(q) return (q:gsub("%s+", " "):gsub("^%s", "")) end

--- **The bridge's parameter check, modelled rather than assumed.**
---
--- OPEN//77's runtime counts `?` placeholders against `#values` and raises `parameter_count_mismatch`. That
--- matters here because a Lua array with a nil in it has no dependable length: `{a,b,c,nil,nil,nil}` is 3. So a
--- nil parameter is NOT SQL NULL -- it shortens the array and the whole statement is refused.
---
--- The first version of this double took `values` on trust, and four statements in `server/graph.lua` went to the
--- live server with nullable tails before the log said so. A double that is more forgiving than the thing it
--- stands in for is worse than no double: it converts a deployable bug into a passing test.
local function countPlaceholders(q)
    -- Deliberately crude, exactly as the runtime's own message warns: a `?` inside a string or comment would be
    -- miscounted. None of NCM's statements contain one, and a false alarm here is cheap.
    local n = 0
    for _ in q:gmatch("%?") do n = n + 1 end
    return n
end

local bridgeFaults = {}

local function run(query, values)
    local q = normalise(query)
    values = values or {}
    local want, got = countPlaceholders(q), #values
    if want ~= got then
        bridgeFaults[#bridgeFaults + 1] =
            ("found %d placeholders but %d values were supplied: %s"):format(want, got, q:sub(1, 70))
        -- The runtime raises; so does this, so a caller that ignores the return value still cannot pass.
        error("parameter_count_mismatch: found " .. want .. " placeholders but " .. got .. " values", 0)
    end
    for i = 1, want do
        if values[i] == nil then
            bridgeFaults[#bridgeFaults + 1] = ("nil parameter at position %d: %s"):format(i, q:sub(1, 70))
        end
    end
    if q:find("INSERT INTO message") then
        rows.message[#rows.message + 1] = {
            id = values[1], serverId = values[2], toDriver = values[3], threadId = values[4],
            fromKind = values[5], fromId = values[6], kind = values[7], subject = values[8],
            body = values[9], state = values[10], createdAt = values[13],
        }
        return 1
    elseif q:find("SELECT message_id, from_kind") then
        local out = {}
        for i = #rows.message, 1, -1 do
            local m = rows.message[i]
            if m.threadId == values[3] then
                out[#out + 1] = { message_id = m.id, from_kind = m.fromKind, from_id = m.fromId,
                                  body = m.body, state = m.state, created_at = m.createdAt }
            end
        end
        return out
    elseif q:find("UPDATE message SET state = 'read'") then
        for _, m in ipairs(rows.message) do
            if m.threadId == values[3] and m.state == "unread" then m.state = "read" end
        end
        return 1
    elseif q:find("INSERT INTO player_contact") then
        rows.player_contact[values[3]] = { state = values[4], node = values[5], flags = values[6],
                                           knownAt = values[7], lastSpokeAt = values[8], lastHeardAt = values[9] }
        return 1
    elseif q:find("SELECT state, node, flags") then
        local c = rows.player_contact[values[3]]
        if not c then return nil end
        return { state = c.state, node = c.node, flags = c.flags, known_at = c.knownAt,
                 last_spoke_at = c.lastSpokeAt, last_heard_at = c.lastHeardAt }
    elseif q:find("INSERT INTO player_behaviour_counter") then
        rows.counters[values[3]] = (rows.counters[values[3]] or 0) + (values[4] or 0)
        return 1
    elseif q:find("SELECT counter, value") then
        local out = {}
        for name, value in pairs(rows.counters) do out[#out + 1] = { counter = name, value = value } end
        return out
    elseif q:find("INSERT INTO player_graph_budget") then
        rows.budget = { open = values[3], lastIntroductionAt = values[4], lastFlavourAt = values[5] }
        return 1
    elseif q:find("SELECT open_introductions") then
        if not rows.budget.open then return nil end
        return { open_introductions = rows.budget.open, last_introduction_at = rows.budget.lastIntroductionAt,
                 last_flavour_at = rows.budget.lastFlavourAt }
    elseif q:find("INSERT INTO lead") then
        rows.lead[values[3] .. ":" .. values[4]] = { sourceKind = values[5], sourceRef = values[6], state = "open" }
        return 1
    elseif q:find("SELECT state FROM lead") then
        local l = rows.lead[values[3] .. ":" .. values[4]]
        return l and { state = l.state } or nil
    elseif q:find("SELECT subject_kind, subject_ref") then
        local out = {}
        for key, l in pairs(rows.lead) do
            local kind, ref = key:match("^(%a+):(.+)$")
            if l.state == "open" then
                out[#out + 1] = { subject_kind = kind, subject_ref = ref, source_kind = l.sourceKind,
                                  source_ref = l.sourceRef, state = "open", created_at = clock }
            end
        end
        return out
    elseif q:find("UPDATE lead SET state = 'closed'") then
        local l = rows.lead["person:" .. values[5]]
        if l then l.state = "closed" end
        return 1
    end
    unknownQueries[#unknownQueries + 1] = q:sub(1, 90)
    return nil
end

MySQL = {
    isReady = function() return true end,
    insert = { await = run },
    update = { await = run },
    query = { await = function(q, v) local r = run(q, v); return type(r) == "table" and r or {} end },
    single = { await = function(q, v) local r = run(q, v); return type(r) == "table" and r or nil end },
}

NcmStream = { send = function(pid, channel, payload, listKey)
    streams[#streams + 1] = { pid = pid, channel = channel, payload = payload, listKey = listKey }
end }

NcmComms = { send = function(pid, def) notices[#notices + 1] = def; return true end }

-- OPEN//77 resource shims the adapter reaches for.
local threads = {}
function CreateThread(fn) threads[#threads + 1] = fn end
function Wait(_) end
function RegisterNetEvent(name, fn) events[name] = fn end
function RegisterCommand(name, fn) events["cmd:" .. name] = fn end
function AddEventHandler(name, fn) events["evt:" .. name] = fn end
function TriggerEvent(name, ...) local h = events["evt:" .. name]; if h then h(...) end end
function TriggerClientEvent() end
function GetPlayerIdentifier() return "user-1" end

-- ---- core ------------------------------------------------------------------------------------------------
local Core = dofile(root .. "/ncm/core/init.lua")
for _, file in ipairs(dofile(root .. "/ncm/core/MANIFEST.lua")) do dofile(root .. "/ncm/core/" .. file) end
Core.warm()

dofile(root .. "/ncm/online/resources/ncm_league/server/graph.lua")

-- ---- harness ---------------------------------------------------------------------------------------------
local checks, bad = 0, 0
local function ok(cond, why)
    checks = checks + 1
    if not cond then bad = bad + 1; print("  FAIL " .. tostring(why)) end
end

local D = "driver-0001"
local PID = 7

--- Walk a payload and hand every string and number to `fn`, so a leak assertion cannot be defeated by nesting.
local function walk(value, fn, path)
    path = path or "payload"
    if type(value) == "table" then
        for k, v in pairs(value) do walk(v, fn, path .. "." .. tostring(k)) end
    else
        fn(value, path)
    end
end

-- ==========================================================================================================
-- 1. Meeting Dex writes the transcript as a CHARACTER, which is the whole point of migration 039.
-- ==========================================================================================================
NcmGraph.meet(PID, D, "dex", { via = "test" })

ok(#rows.message == 3, "Dex's opening is three messages, got " .. #rows.message)
for _, m in ipairs(rows.message) do
    ok(m.fromKind == "character", "a contact must send as `character`, got " .. tostring(m.fromKind))
    ok(m.fromId == "dex", "the sender must be the contact id, got " .. tostring(m.fromId))
    ok(m.threadId == "contact:dex", "every line joins the contact's standing thread")
    ok(m.state == "unread", "an introduction arrives unread")
end
ok(rows.message[1].body:find("You're through to NCM", 1, true) ~= nil,
    "the first line is the draft's own opening")
ok(rows.player_contact.dex ~= nil and rows.player_contact.dex.node == "opening",
    "the conversation rests on the node it just spoke")
ok(rows.budget.open == 1, "an introduction is counted against the §20 budget")

-- An unauthored contact must be refusable even though the scripts mention several.
ok(NcmGraph.meet(PID, D, "billie", {}) == false, "an unauthored contact must not be openable")
ok(NcmGraph.meet(PID, D, "nobody", {}) == false, "an unknown contact must not be openable")
ok(select(2, NcmGraph.meet(PID, D, "billie", {})) == "not_authored", "and must say why")

-- ==========================================================================================================
-- 2. §20 rule 1: a second introduction cannot land while the first is unanswered.
-- ==========================================================================================================
local before = #rows.message
ok(NcmGraph.meet(PID, D, "stu", {}) == true, "Stu is authored and may be met")
ok(#rows.message == before, "but §20 rule 1 forbids his beat while Dex's introduction is open")
ok(rows.player_contact.stu ~= nil, "the contact still exists; only the message was rationed")

-- ==========================================================================================================
-- 3. Replying: the player's own line is a row, the flags persist, and the effect runs.
--
-- This section is also the regression for the ordering bug this harness found: accepting Dex's introduction
-- opens Rico, and Rico's opening was being rationed away by the reply that asked for it, because the budget slot
-- was released only after the effects ran.
-- ==========================================================================================================
local okReply, whyReply = NcmGraph.reply(PID, D, "dex", "rico_yes")
ok(okReply == true, "accepting the Rico introduction must succeed: " .. tostring(whyReply))

local mine
for _, m in ipairs(rows.message) do if m.fromKind == "driver" then mine = m end end
ok(mine ~= nil, "the player's reply is written into the transcript")
ok(mine and mine.body == "Put me through.", "and it records what they actually said")
ok(mine and mine.fromId == D, "a driver line is from the driver, to the driver -- not player-to-player messaging")

ok(rows.player_contact.dex.flags:find("ricoKnown") ~= nil, "the choice's flags persist")
ok(rows.player_contact.rico ~= nil, "`open:rico` opened Rico")
ok(rows.player_contact.rico.node ~= nil,
    "and Rico ACTUALLY SPOKE: answering Dex frees the introduction slot before the effect runs")

local ricoSaid = false
for _, m in ipairs(rows.message) do
    if m.fromId == "rico" and m.body:find("First one's free", 1, true) then ricoSaid = true end
end
ok(ricoSaid, "Rico's opening reached the transcript rather than being rationed away")

-- A choice the script no longer offers must be refused server-side even if a stale page asks for it (§0.3).
ok(NcmGraph.reply(PID, D, "dex", "rico_yes") == false,
    "a stale choice must be refused after the conversation moved")

-- ==========================================================================================================
-- 4. Cross-character telemetry (§0.7 / §3.4): a Stu hardware question moves a HIDDEN counter.
--
-- Driven through the real tree, because poking the database behind the adapter's cache tests nothing.
-- ==========================================================================================================
-- Stu's beat was rationed above, so a tick delivers it now that Dex's slot is free.
NcmGraph.tick(PID, D, { dexKnown = true })
ok(rows.player_contact.stu.node == "opening", "a rationed introduction is retried, not lost")

ok(NcmGraph.reply(PID, D, "stu", "ack") == true, "acknowledge the introduction")
ok(rows.player_contact.stu.node == "second_beat", "which moves him to the Quinn/Foreman handoff (§3.3)")
ok(NcmGraph.reply(PID, D, "stu", "later") == true, "defer it")
ok(rows.player_contact.stu.flags:find("qfIntroDeferred") ~= nil, "the deferral is recorded (§0.2)")
ok(NcmGraph.reply(PID, D, "stu", "on") == true, "and the conversation settles on his persistent hub")
ok(rows.player_contact.stu.node == "top", "got " .. tostring(rows.player_contact.stu.node))

ok(NcmGraph.reply(PID, D, "stu", "better") == true, "ask where better parts come from")
ok(rows.counters.hardwareCuriosity == 1,
    "a hardware question increments the hidden score, got " .. tostring(rows.counters.hardwareCuriosity))

-- The counter is the ONLY thing that moved. §8.1's cooldown means Rico must not react in the same breath.
ok(rows.player_contact.needle == nil, "Rico must not react to hardware curiosity instantly (§8.1 cooldown)")

-- ==========================================================================================================
-- 5. A mention of an unauthored person becomes a LEAD, never a contact (`L175`).
-- ==========================================================================================================
-- Reach Rico's Needle beat the way the world would: enough curiosity, and the Stu cooldown elapsed. Each
-- question has to be asked FROM the hub, so the loop walks back each time -- exactly as a player would.
for _ = 1, 6 do
    ok(NcmGraph.reply(PID, D, "stu", "back") == true, "return to Stu's hub")
    ok(NcmGraph.reply(PID, D, "stu", "better") == true, "ask again")
end
ok(rows.counters.hardwareCuriosity == 7,
    "seven substantive hardware questions, got " .. tostring(rows.counters.hardwareCuriosity))
clock = clock + 3600
local pushed = NcmGraph.tick(PID, D, { stuCooldownElapsed = true })
ok(pushed ~= nil and pushed.node == "needle_open",
    "cross-character telemetry pushes Rico's hardware beat, got " .. tostring(pushed and pushed.node))
ok(rows.player_contact.rico.node == "needle_open", "and the conversation rests there")

-- §8.1's tree, walked as authored: how do you know / ears everywhere / anyway... / who / put me in touch.
ok(NcmGraph.reply(PID, D, "rico", "how") == true, "ask how he knows")
ok(rows.player_contact.rico.node == "needle_how", "got " .. tostring(rows.player_contact.rico.node))
local ears = false
for _, m in ipairs(rows.message) do if m.body == "Ears everywhere. Don't worry about it." then ears = true end end
ok(ears, "and he answers exactly as §8.1 wrote it")
ok(NcmGraph.reply(PID, D, "rico", "on") == true, "let him continue")
ok(rows.player_contact.rico.node == "needle_anyway", "got " .. tostring(rows.player_contact.rico.node))
ok(NcmGraph.reply(PID, D, "rico", "who") == true, "ask who")
ok(rows.player_contact.rico.node == "needle_name", "Rico names them")
ok(NcmGraph.reply(PID, D, "rico", "touch") == true, "ask for the introduction")

ok(rows.lead["person:needle"] ~= nil, "Needle is recorded as a lead")
ok(rows.lead["person:needle"].sourceKind == "character", "with its source kind")
ok(rows.lead["person:needle"].sourceRef == "rico", "and the character who said it -- attribution is the point")
ok(rows.player_contact.needle == nil, "and Needle is NOT a contact, because nothing authored can answer as them")

-- A push must not repeat a beat the conversation is already resting on, or the world nags (§20 rule 5).
local saidBefore = #rows.message
NcmGraph.tick(PID, D, { stuCooldownElapsed = true })
NcmGraph.tick(PID, D, { stuCooldownElapsed = true })
ok(#rows.message == saidBefore, "a delivered beat is never re-said by a later tick")

-- Nobody reintroduces themselves, either.
ok(NcmGraph.meet(PID, D, "dex", {}) == true, "meeting an already-known contact succeeds")
ok(select(2, NcmGraph.meet(PID, D, "dex", {})) == "already_known", "and is a no-op that says so")

-- ==========================================================================================================
-- 6. The payload: what the panel is allowed to see.
-- ==========================================================================================================
local payload = NcmGraph.threads(D, "dex")
ok(type(payload.threads) == "table" and #payload.threads == 3,
    "every known conversation is listed, got " .. #payload.threads)
ok(payload.thread ~= nil and payload.thread.contactId == "dex", "the selected conversation is returned")
ok(type(payload.lines) == "table" and #payload.lines > 0, "with its transcript")
ok(payload.thread.name == "Dex", "and a display name the panel can render")

-- `lines` must be TOP LEVEL, because it is the one unbounded list and `NcmStream` splits exactly one (KB-86).
ok(payload.thread.lines == nil, "the transcript must not be nested inside `thread` -- the stream splits one list")

-- The projected replies must carry no hidden field. §3.4's score is not for the player, and the page must not
-- be able to infer it from which replies are "special".
for _, choice in ipairs(payload.thread.choices or {}) do
    ok(choice.curiosity == nil, "a projected reply must not carry its curiosity category to the page")
    ok(choice.id ~= nil and choice.label ~= nil, "a reply needs an id and a label")
end

-- THE LEAK DISCIPLINE. No count of anything the player is progressing through (`L171`, `L175`, §3.4).
local leaked = {}
walk(payload, function(value, path)
    local lower = tostring(path):lower()
    if lower:find("curiosity") or lower:find("opencount") or lower:find("progress")
        or lower:find("percent") or lower:find("completion") or lower:find("score") then
        leaked[#leaked + 1] = path
    end
end)
ok(#leaked == 0, "payload leaks a progress-shaped field: " .. table.concat(leaked, ", "))

-- The shelf is names, never a tally. Dex rests on `top` after the Rico handoff, so ask him a question the way
-- the player would.
ok(NcmGraph.reply(PID, D, "dex", "to_top") == true, "return to Dispatch's hub")
ok(NcmGraph.reply(PID, D, "dex", "questions") == true, "and open the questions hub")
ok(rows.player_contact.dex.node == "questions", "got " .. tostring(rows.player_contact.dex.node))
local shelved = NcmGraph.threads(D, "dex")
local shelf = shelved.thread.shelf or {}
ok(#shelf > 0, "the questions hub carries the context shelf")
local labelled = false
for _, item in ipairs(shelf) do
    -- The lead this run actually created, through Rico, exactly as the draft's cross-character example does.
    if item.label == "Who is Needle?" then labelled = true end
    ok(item.label:match("%d+%s*/%s*%d+") == nil, "a shelf item must not render a fraction")
    ok(item.key ~= nil, "and carries the subject key the panel sends back")
end
ok(labelled, "a person lead reads as a question about them, got " .. tostring((shelf[1] or {}).label))

-- A node with no shelf must not carry one: the shelf belongs where the script says it does (§2.4).
ok(NcmGraph.reply(PID, D, "dex", "races") == true, "ask a generic question")
ok(#((NcmGraph.threads(D, "dex").thread or {}).shelf or {}) == 0,
    "the shelf appears only on a node that declares it")

-- ==========================================================================================================
-- 7. Transport. The payload goes out on the targeted stream, never a state bag (KB-97).
-- ==========================================================================================================
streams = {}
NcmGraph.pushThreads(PID, D, "dex")
ok(#streams == 1, "one stream per push")
ok(streams[1].channel == "ncm:graph", "on the graph channel")
ok(streams[1].listKey == "lines", "splitting the transcript, which is the unbounded part")
ok(streams[1].pid == PID, "addressed to one player -- message bodies may never ride a player bag (KB-97)")

-- ==========================================================================================================
-- 8. Every statement the adapter issues must be one this double recognises.
-- ==========================================================================================================
ok(#unknownQueries == 0, "unrecognised SQL reached the double: " .. table.concat(unknownQueries, " | "))

-- ==========================================================================================================
-- 9. Every parameter array must be DENSE. This is the assertion that was missing when four statements with
--    nullable tails reached the live server (`KB-168`).
-- ==========================================================================================================
ok(#bridgeFaults == 0, "OPEN//77 would refuse a statement: " .. table.concat(bridgeFaults, " | "))

-- And prove the check itself can fail, so it cannot rot into a no-op that always passes.
do
    local before = #bridgeFaults
    pcall(run, "INSERT INTO nothing (a, b) VALUES (?, ?)", { "only-one" })
    ok(#bridgeFaults > before, "the bridge double must REFUSE a short parameter array")
    for i = #bridgeFaults, before + 1, -1 do table.remove(bridgeFaults, i) end   -- deliberate probe, not a fault
end

print(("quest-graph: %d assertion(s), %d bad"):format(checks, bad))
if bad > 0 then os.exit(1) end
