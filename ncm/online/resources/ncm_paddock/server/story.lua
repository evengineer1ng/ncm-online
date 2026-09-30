-- ncm_paddock / server / story -- the tape, WIRE and the few messages that reach a player (doc 44 §8).
--
-- Every consequential thing is recorded as a tape event (INSERT IGNORE: an event id is stable, so recording the
-- same fact twice is a no-op), and each event with a resolvable template becomes a WIRE story. Salience decides
-- prominence; WIRE shows the prominent ones and RESULTS keeps everything.
--
-- Messages are rare by rule (L226): at most `pushPerDay` UNSOLICITED Paddock messages per player per Eastern day,
-- counted in `paddock_push` so the budget survives a restart. Solicited items (the player's own slip, their own
-- org) are exempt. Paddock messages are informational (`actions = NULL`): `ncm:inbox.act` belongs to
-- organized.lua, so any decision is taken in PADDOCK > MY ORG, never from the inbox.
PaddockStory = {}

local U = PaddockUtil
local log = U.logger("story")
local Tape = NcmCore.get("paddock.tape")
local News = NcmCore.get("paddock.news")
local Clock = NcmCore.get("world.clock")

local function recentFor(kind)
    local w = PaddockStore.world
    w.recentTemplates = w.recentTemplates or {}
    w.recentTemplates[kind] = w.recentTemplates[kind] or {}
    return w.recentTemplates[kind]
end

--- Record events (from `paddock.tape.event`) and write their stories. Returns the stories written.
function PaddockStory.record(events)
    if not events or #events == 0 then return {} end
    local sid = U.sid()
    local st, stories = {}, {}
    for i, e in ipairs(events) do
        if i % 10 == 0 then Wait(0) end               -- a Cup boundary at ~3x the cast (L236) writes a lot of news
        local ok = Tape.validate(e)
        if ok then
            e.day = e.day or Clock.eastern(e.at).dayIndex
            st[#st + 1] = { query = [[INSERT IGNORE INTO paddock_event (server_id, event_id, at, day_index, kind, entities,
                cause_refs, effect_refs, facts, public_summary, salience, retain, provenance)
                VALUES (?, ?, ?, NULLIF(?, -1), ?, ?, ?, ?, ?, NULLIF(?, ''), ?, ?, ?)]],
                -- Optional fields travel as sentinels: a nil would leave a hole the host refuses (U.checkStatement).
                values = { sid, e.id, e.at, e.day or -1, e.kind, U.encode(e.entities) or "[]", U.encode(e.causeRefs) or "[]",
                    U.encode(e.effectRefs) or "[]", U.encode(e.facts) or "{}", e.publicSummary or "", e.salience or 0,
                    e.retain and 1 or 0, e.provenance or "simulated" } }
            local recent = recentFor(e.kind)
            local story = News.write(e, recent)
            if story then
                recent[#recent + 1] = story.templateId
                while #recent > News.NO_REPEAT do table.remove(recent, 1) end
                st[#st + 1] = { query = [[INSERT IGNORE INTO paddock_news (server_id, story_id, event_id, at, kind, template_id,
                    headline, body, prominence, subjects) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]],
                    values = { sid, story.storyId:sub(1, 170), e.id, story.at, story.kind, story.templateId,
                        story.headline:sub(1, 200), story.body:sub(1, 800), story.prominence, U.encode(story.subjects) or "[]" } }
                stories[#stories + 1] = story
            end
        end
    end
    PaddockStore.markMeta()
    local ok, err = U.transact(st)
    if not ok then log("record FAILED: %s", tostring(err)) end
    return stories
end

--- Deliver a message to a driver. `opts.solicited` bypasses the daily budget. Returns true when sent.
function PaddockStory.push(driverId, subject, body, opts)
    opts = opts or {}
    if not driverId or not MySQL.isReady() then return false end
    local sid = U.sid()
    local day = Clock.eastern(U.now()).dayIndex
    if not opts.solicited then
        local cap = PaddockSettings.get("pushPerDay", 3)
        local count = tonumber(MySQL.scalar.await("SELECT count FROM paddock_push WHERE server_id=? AND ncm_driver_id=? AND day_index=?",
            { sid, driverId, day })) or 0
        if count >= cap then return false end
        MySQL.update.await([[INSERT INTO paddock_push (server_id, ncm_driver_id, day_index, count) VALUES (?, ?, ?, 1)
            ON DUPLICATE KEY UPDATE count = count + 1]], { sid, driverId, day })
    end
    local ok, err = pcall(MySQL.insert.await,
        [[INSERT INTO message (message_id, server_id, to_driver_id, thread_id, from_kind, from_id, kind, subject, body,
            actions, state, ref_kind, ref_id, created_at) VALUES (?, ?, ?, ?, 'championship', ?, 'paddock', ?, ?, NULL, 'unread',
            NULLIF(?, ''), NULLIF(?, ''), ?)]],
        { U.uuid(), sid, driverId, opts.thread or "paddock", opts.fromId or "paddock", subject:sub(1, 120), body,
          opts.refKind or "", opts.refId or "", U.now() })
    if not ok then log("push FAILED %s: %s", tostring(driverId):sub(1, 8), tostring(err)); return false end
    local pid = PaddockPlayers.pidOf(driverId)
    if pid then
        pcall(Open77.notifications.send, pid, { type = "info", title = "THE PADDOCK", message = subject, icon = "NCM", durationMs = 6000 })
    end
    return true
end
