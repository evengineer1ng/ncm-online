-- ncm_radio / server / facts -- NCM's persisted world, read-only, as facts the director can air (doc 59 §2).
--
-- The same tables Night City Chronicles reads (doc 57 §2): the Paddock's tape (`paddock_event`), the Week
-- (`racing_week_run/_event/_moody`), the human drivers' results (`paddock_result` + `paddock_entry`), standings, and
-- the calendar for previews. SELECT only. Resources do not share memory, so nothing here calls another resource.
--
-- Knowledge boundary (doc 58, L347): only PUBLIC facts become facts here. The tape's `facts` JSON is what the WIRE may
-- print; settled results air whatever their provenance, and the provenance never reaches a line. The quickhack truth
-- ledger (`chrome_event`), the Week's tolerance, samples and verdict probabilities are never read.
RadioFacts = {}

local SID
local cursors = { tape = 0, moody = 0, step = 0, vibe = 0, result = 0 }
local names = { series = {}, person = {} }
local lexicon = { name = {}, org = {}, series = {}, route = {}, phrase = {} }
local seenRace, seenStart = {}, {}

local function sid() return SID end
local function q(sql, args)
    local ok, rows = pcall(MySQL.query.await, sql, args or {})
    if not ok then print("[ncm_radio/facts] query failed: " .. tostring(rows)) return {} end
    return rows or {}
end
local function dec(v)
    if type(v) == "table" then return v end
    if type(v) ~= "string" or v == "" then return {} end
    local ok, t = pcall(json.decode, v)
    return ok and type(t) == "table" and t or {}
end
local function learn(cls, v)
    if type(v) == "string" and v ~= "" and v ~= "?" then lexicon[cls][v] = true end
end
local function marginSeconds(m)
    if type(m) == "number" then return m end
    local x = tostring(m or ""):match("^(%d+%.?%d*)s$")
    return x and tonumber(x) or nil
end

-- tape kind -> director trigger
local ORG = { founded = true, fold = true, transfer = true, release = true, retirement = true, sponsor_signed = true,
    sponsor_left = true, manager_hired = true, manager_fired = true, callout = true, promotion = true, relegation = true }
local TITLE = { cup_title = true, season_title = true }
local CAUSE_TEXT = { mechanical = "mechanical failure", contact = "contact with another car" }

local function tapeFact(r)
    local kind = r.kind
    local f = dec(r.facts)
    local trigger = kind
    if ORG[kind] then trigger = "org" elseif TITLE[kind] then trigger = "title" end
    local data = {
        kind = kind, tier = f.tier, winner = f.winner, second = f.second, third = f.third, driver = f.driver or f.person,
        org = f.org or f.winnerOrg, series = f.series, route = f.route, fieldSize = tonumber(f.fieldSize),
        marginSeconds = marginSeconds(f.margin), closeFinish = f.closeFinish and true or nil, wet = f.wet and true or nil,
        night = f.night and true or nil, fromGrid = tonumber(f.fromGrid), price = tonumber(f.price), count = tonumber(f.count),
        starts = tonumber(f.starts), cause = f.cause, driverA = f.driverA, driverB = f.driverB, attacker = f.attacker,
        target = f.target, sponsor = f.sponsor, champion = f.champion or f.driver, title = f.title or f.series,
        race = f.raceId,            -- the race thread this result closes (bible §76)
    }
    for _, k in ipairs({ "winner", "second", "third", "driver", "driverA", "driverB", "attacker", "target", "champion" }) do learn("name", data[k]) end
    learn("org", data.org); learn("org", data.sponsor); learn("series", data.series); learn("route", data.route)
    learn("phrase", data.cause)
    return { id = "tape:" .. tostring(r.event_id), kind = kind, trigger = trigger, at = tonumber(r.at) or 0,
        salience = tonumber(r.salience) or 20, data = data }
end

--- Read everything new since the last poll. Returns facts oldest-first.
function RadioFacts.poll(now)
    local out = {}
    -- the Week: open, end, published steps, Moody's public rolls, and the radio mood samples (public lines)
    for _, r in ipairs(q([[SELECT run_index, COALESCE(start_utc, opened_at) AS t0, end_utc, end_kind FROM racing_week_run
        WHERE server_id = ? ORDER BY run_index DESC LIMIT 1]], { sid() })) do
        local run = tonumber(r.run_index)
        if run and run ~= RadioFacts.run then
            RadioFacts.run = run
            out[#out + 1] = { id = "week:" .. run .. ":open", kind = "week_open", at = tonumber(r.t0) or now, salience = 70, data = { run = run } }
        end
        if r.end_utc and not RadioFacts.ended then
            RadioFacts.ended = true
            out[#out + 1] = { id = "week:" .. run .. ":end", kind = "week_end", at = tonumber(r.end_utc) or now, salience = 90,
                data = { run = run, endKind = r.end_kind } }
        end
    end
    local run = RadioFacts.run
    if run then
        for _, r in ipairs(q([[SELECT ref, data_json, at FROM racing_week_event WHERE server_id = ? AND run_index = ?
            AND kind = 'step' AND at > ? ORDER BY at]], { sid(), run, cursors.step })) do
            cursors.step = math.max(cursors.step, tonumber(r.at) or 0)
            local text = NcmRadioCorpus.steps[r.ref]
            if text and r.ref ~= "opening" then
                learn("phrase", text)
                out[#out + 1] = { id = "step:" .. run .. ":" .. r.ref, kind = "policy", at = tonumber(r.at), salience = 65,
                    data = { step = r.ref, announcement = text } }
            end
        end
        for _, r in ipairs(q([[SELECT ref, data_json, at FROM racing_week_event WHERE server_id = ? AND run_index = ?
            AND kind = 'sample' AND ref LIKE 'radio:%' AND at > ? ORDER BY at]], { sid(), run, cursors.vibe })) do
            cursors.vibe = math.max(cursors.vibe, tonumber(r.at) or 0)
            local d = dec(r.data_json)
            out[#out + 1] = { id = "vibe:" .. run .. ":" .. r.ref, kind = "week_vibe", at = tonumber(r.at), data = { mood = d.mood } }
        end
        for _, r in ipairs(q([[SELECT roll_n, face, at FROM racing_week_moody WHERE server_id = ? AND run_index = ? AND at > ?
            ORDER BY at]], { sid(), run, cursors.moody })) do
            cursors.moody = math.max(cursors.moody, tonumber(r.at) or 0)
            local face = NcmRadioCorpus.moody[r.face]
            if face then
                learn("phrase", face.line)
                out[#out + 1] = { id = "moody:" .. run .. ":" .. r.roll_n, kind = "moody", at = tonumber(r.at), salience = 50,
                    data = { face = r.face, line = face.line, effect = face.tone } }
            end
        end
    end
    -- the Paddock's tape: results, upsets, streaks, first wins, crash-outs, feuds, destroyed cars, attributed attacks,
    -- organisations, titles, R&D releases
    for _, r in ipairs(q([[SELECT event_id, at, kind, facts, salience FROM paddock_event WHERE server_id = ? AND at > ?
        ORDER BY at LIMIT 400]], { sid(), cursors.tape })) do
        cursors.tape = math.max(cursors.tape, tonumber(r.at) or 0)
        out[#out + 1] = tapeFact(r)
    end
    -- human drivers' results (the listener's own races): position, field, winner, DNF
    for _, r in ipairs(q([[SELECT e.ncm_driver_id, e.display, r.race_id, r.position, r.grid, r.state, r.dnf_reason, r.at,
        r.series_id FROM paddock_result r JOIN paddock_entry e ON e.server_id = r.server_id AND e.race_id = r.race_id
        AND e.person_key = r.person_id WHERE r.server_id = ? AND r.at > ? ORDER BY r.at]], { sid(), cursors.result })) do
        cursors.result = math.max(cursors.result, tonumber(r.at) or 0)
        local pos, dnf = tonumber(r.position), r.state ~= "finished"
        local kind = dnf and "player_dnf" or (pos == 1 and "player_win" or ((pos or 99) <= 3 and "player_podium" or "player_result"))
        out[#out + 1] = { id = "result:" .. r.race_id .. ":" .. r.ncm_driver_id, kind = kind, at = tonumber(r.at),
            salience = 45 + (pos == 1 and 25 or ((pos or 99) <= 3 and 15 or 0)), driverId = r.ncm_driver_id,
            data = { position = not dnf and pos or nil, grid = tonumber(r.grid), series = names.series[r.series_id],
                cause = CAUSE_TEXT[r.dnf_reason or ""] or (dnf and "a crash" or nil) } }
        learn("name", r.display)
    end
    -- previews: a race whose window opens in the next ten minutes (once per race)
    for _, r in ipairs(q([[SELECT race_id, series_id, window_opens_at FROM paddock_race WHERE server_id = ?
        AND state IN ('scheduled','priced') AND window_opens_at BETWEEN ? AND ? ORDER BY window_opens_at LIMIT 8]],
        { sid(), now + 60, now + 600 })) do
        if not seenRace[r.race_id] then
            seenRace[r.race_id] = true
            local opens = tonumber(r.window_opens_at) or now
            local hh, mm = RadioFacts.clockOf(opens)
            out[#out + 1] = { id = "preview:" .. r.race_id, kind = "race_preview", at = now, salience = 30,
                data = { race = r.race_id, series = names.series[r.series_id], opensAt = opens, opensHour = hh, opensMinute = mm } }
        end
    end
    -- starts: a race that went live in the last ten minutes (once per race) -- Tommy's grid call, and the moment a
    -- preview's handoff ("Tommy?") has someone to answer it
    for _, r in ipairs(q([[SELECT race_id, series_id, window_opens_at FROM paddock_race WHERE server_id = ?
        AND state = 'running' AND window_opens_at BETWEEN ? AND ? ORDER BY window_opens_at LIMIT 8]],
        { sid(), now - 600, now })) do
        if not seenStart[r.race_id] then
            seenStart[r.race_id] = true
            out[#out + 1] = { id = "start:" .. r.race_id, kind = "race_start", at = tonumber(r.window_opens_at) or now,
                salience = 40, data = { race = r.race_id, series = names.series[r.series_id] } }
        end
    end
    return out
end

--- Names that never change during a session (series), and the lexicon the render needs.
function RadioFacts.loadNames()
    for _, r in ipairs(q("SELECT series_id, name FROM paddock_series WHERE server_id = ?", { sid() })) do
        names.series[r.series_id] = r.name
        learn("series", r.name)
    end
    for _, r in ipairs(q("SELECT display FROM paddock_person WHERE server_id = ? AND role = 'driver'", { sid() })) do learn("name", r.display) end
    for _, r in ipairs(q("SELECT name FROM paddock_org WHERE server_id = ?", { sid() })) do learn("org", r.name) end
    for _, r in ipairs(q("SELECT DISTINCT display FROM paddock_entry WHERE server_id = ?", { sid() })) do learn("name", r.display) end
    for _, f in pairs(NcmRadioCorpus.moody) do learn("phrase", f.line) end
    for _, t in pairs(NcmRadioCorpus.steps) do learn("phrase", t) end
    for _, t in pairs(CAUSE_TEXT) do learn("phrase", t) end
    learn("phrase", "a crash")
end

--- The leader of the most prominent series with results, for the standings segment.
function RadioFacts.standings(now)
    local rows = q([[SELECT s.series_id, s.points, p.display FROM paddock_standing s
        JOIN paddock_person p ON p.server_id = s.server_id AND p.person_id = s.entity_id
        JOIN paddock_series r ON r.server_id = s.server_id AND r.series_id = s.series_id
        WHERE s.server_id = ? AND s.entity_kind = 'driver' AND s.pos = 1 AND s.starts > 0
        ORDER BY FIELD(r.tier, 'premier', 'pro', 'regional', 'street'), s.points DESC LIMIT 1]], { sid() })
    local r = rows[1]
    if not r then return nil end
    return { id = "standings:" .. tostring(math.floor(now / 3600)), kind = "standings", at = now, salience = 35,
        data = { leader = r.display, series = names.series[r.series_id], points = tonumber(r.points) } }
end

--- Everything a host might ever have to say by name: written to the resource's data directory for the voice render.
function RadioFacts.writeLexicon()
    local out = {}
    for cls, set in pairs(lexicon) do
        local list = {}
        for v in pairs(set) do list[#list + 1] = v end
        table.sort(list)
        out[cls] = list
    end
    -- plain write (4 MiB) rather than writeJson (48 KiB codec cap): the lexicon grows with the world
    local okE, text = pcall(json.encode, out)
    if not okE then print("[ncm_radio/facts] lexicon not encoded: " .. tostring(text)) return out end
    local ok, written, why = pcall(Open77.io.write, "lexicon.json", text)
    if not ok or written == false then
        print("[ncm_radio/facts] lexicon not written: " .. tostring(ok and why or written))
    end
    return out
end

function RadioFacts.init(serverId, clockOf)
    SID = serverId
    RadioFacts.clockOf = clockOf
end
