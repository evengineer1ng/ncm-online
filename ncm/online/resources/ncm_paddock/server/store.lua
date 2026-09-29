-- ncm_paddock / server / store -- the world in memory, persisted to schema 045.
--
-- The whole NPC world (about 60 orgs, 300 people, 90 sponsors) is small enough to hold in memory, and holding it
-- is what keeps request handlers cheap under OPEN//77's instruction quota (KB-211): a view reads Lua tables, never
-- rebuilds a world. Writes are dirty-tracked and flushed in chunked transactions as upserts. Results, events and
-- news are NOT held here: they are append-mostly tables the views query with SQL, so the database does the
-- aggregation rather than the metered VM.
PaddockStore = { world = nil }

local U = PaddockUtil
local log = U.logger("store")
local dirty = { person = {}, org = {}, sponsor = {}, series = {}, meta = false }

function PaddockStore.markPerson(id) if id then dirty.person[id] = true end end
function PaddockStore.markOrg(id) if id then dirty.org[id] = true end end
function PaddockStore.markSponsor(id) if id then dirty.sponsor[id] = true end end
function PaddockStore.markMeta() dirty.meta = true end

local function orgRow(sid, o)
    return {
        query = [[INSERT INTO paddock_org (server_id, org_id, tier, series_id, name, short, colour, prestige, cash, facility,
            car_json, owner_person_id, manager_person_id, engineer_person_id, strategist_person_id, sponsor_ids,
            human_manager_driver_id, origin, lifecycle, founded_season, seasons_active, red_days, low_cash_days,
            evidence_json, pending_json, folded_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULLIF(?, ''), NULLIF(?, ''), NULLIF(?, ''), NULLIF(?, ''), ?, NULLIF(?, ''),
                    ?, ?, ?, ?, ?, ?, ?, ?, NULLIF(?, 0))
            ON DUPLICATE KEY UPDATE tier = VALUES(tier), series_id = VALUES(series_id), name = VALUES(name),
                short = VALUES(short), prestige = VALUES(prestige), cash = VALUES(cash), facility = VALUES(facility),
                car_json = VALUES(car_json), owner_person_id = VALUES(owner_person_id),
                manager_person_id = VALUES(manager_person_id), engineer_person_id = VALUES(engineer_person_id),
                strategist_person_id = VALUES(strategist_person_id), sponsor_ids = VALUES(sponsor_ids),
                human_manager_driver_id = VALUES(human_manager_driver_id), lifecycle = VALUES(lifecycle),
                seasons_active = VALUES(seasons_active), red_days = VALUES(red_days),
                low_cash_days = VALUES(low_cash_days), evidence_json = VALUES(evidence_json),
                pending_json = VALUES(pending_json), folded_at = VALUES(folded_at)]],
        values = { sid, o.id, o.tier, o.seriesId, o.name, o.short, o.colour, math.floor(o.prestige or 50),
            math.floor(o.cash or 0), math.floor(o.facility or 50), U.encode(o.car) or "{}", o.ownerId or "",
            o.managerId or "", o.engineerId or "", o.strategistId or "", U.encode(o.sponsorIds or {}) or "[]",
            o.humanManagerDriverId or "", o.origin or "genesis", o.lifecycle or "active", o.foundedSeason or "",
            o.seasonsActive or 1, o.redDays or 0, o.lowCashDays or 0, U.encode(o.evidence or {}) or "{}",
            U.encode(o.pending or {}) or "[]", o.foldedAt or 0 },
    }
end

local function personRow(sid, p)
    return {
        query = [[INSERT INTO paddock_person (server_id, person_id, role, org_id, seat, first, last, display, region, gender,
            birth_year, attrs_json, personality_json, principal_json, morale, state, wage, contract_ends, evidence_json)
            VALUES (?, ?, ?, NULLIF(?, ''), NULLIF(?, ''), ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE role = VALUES(role), org_id = VALUES(org_id), seat = VALUES(seat),
                attrs_json = VALUES(attrs_json), principal_json = VALUES(principal_json), morale = VALUES(morale),
                state = VALUES(state), wage = VALUES(wage), contract_ends = VALUES(contract_ends),
                evidence_json = VALUES(evidence_json)]],
        values = { sid, p.id, p.role, p.orgId or "", p.seat or "", p.first, p.last, p.display, p.region, p.gender,
            p.birthYear, U.encode(p.attrs) or "null", U.encode(p.personality) or "null", U.encode(p.principal) or "null",
            p.morale or 50, p.state or "active", math.floor(p.wage or 0), p.contractEnds or 0, U.encode(p.evidence or {}) or "{}" },
    }
end

local function sponsorRow(sid, s)
    return {
        query = [[INSERT INTO paddock_sponsor (server_id, sponsor_id, name, short, industry, tier, personality_json, org_id, per_day)
            VALUES (?, ?, ?, ?, ?, ?, ?, NULLIF(?, ''), ?)
            ON DUPLICATE KEY UPDATE org_id = VALUES(org_id), per_day = VALUES(per_day), tier = VALUES(tier)]],
        values = { sid, s.id, s.name, s.short, s.industry, s.tier, U.encode(s.personality) or "{}", s.orgId or "", s.perDay or 0 },
    }
end

local function metaRow(sid, w)
    return {
        query = [[INSERT INTO paddock_world (server_id, seed, genesis_version, genesis_season, season_id, season_ordinal,
            paddock_year, day_index_applied, cup_id, counters_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE season_id = VALUES(season_id), season_ordinal = VALUES(season_ordinal),
                paddock_year = VALUES(paddock_year), day_index_applied = VALUES(day_index_applied),
                cup_id = VALUES(cup_id), counters_json = VALUES(counters_json)]],
        values = { sid, w.seed, w.genesisVersion, w.genesisSeasonId, w.seasonId, w.seasonOrdinal, w.paddockYear,
            w.dayIndexApplied, w.cupId, U.encode({ nextPerson = w.nextPerson, nextOrg = w.nextOrg,
                nextSponsor = w.nextSponsor, recentTemplates = w.recentTemplates }) or "{}", w.createdAt or U.now() },
    }
end

--- Persist a whole world (genesis). Yields between chunks.
function PaddockStore.saveAll(w)
    local sid = U.sid()
    local st = { metaRow(sid, w) }
    for id, s in pairs(w.series) do
        st[#st + 1] = { query = [[INSERT INTO paddock_series (server_id, series_id, tier, division, name) VALUES (?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE name = VALUES(name)]], values = { sid, id, s.tier, s.division, s.name } }
    end
    local y = U.yielder(10)
    for _, oid in ipairs(w.orgOrder) do st[#st + 1] = orgRow(sid, w.orgs[oid]); y() end
    for _, pid in ipairs(w.personOrder) do st[#st + 1] = personRow(sid, w.people[pid]); y() end
    for _, sp in ipairs(w.sponsorOrder) do st[#st + 1] = sponsorRow(sid, w.sponsors[sp]); y() end
    return U.transact(st)
end

--- Flush everything marked dirty. Cheap when nothing is.
function PaddockStore.flush()
    local w = PaddockStore.world
    if not w then return true end
    local sid = U.sid()
    local st = {}
    local snapshot = dirty
    dirty = { person = {}, org = {}, sponsor = {}, series = {}, meta = false }
    -- JSON-encoding a row is the expensive part: yield while building, not only between transactions (KB-211)
    local y = U.yielder(10)
    if snapshot.meta then st[#st + 1] = metaRow(sid, w) end
    for id in pairs(snapshot.org) do if w.orgs[id] then st[#st + 1] = orgRow(sid, w.orgs[id]); y() end end
    for id in pairs(snapshot.person) do if w.people[id] then st[#st + 1] = personRow(sid, w.people[id]); y() end end
    for id in pairs(snapshot.sponsor) do if w.sponsors[id] then st[#st + 1] = sponsorRow(sid, w.sponsors[id]); y() end end
    if #st == 0 then return true end
    local ok, err = U.transact(st)
    if not ok then log("flush FAILED (%d statements): %s", #st, tostring(err)) end
    return ok, err
end

local function num(v, d) return tonumber(v) or d end

--- Load the world for this server, or nil when genesis has not run.
function PaddockStore.load()
    local sid = U.sid()
    local m = MySQL.single.await("SELECT * FROM paddock_world WHERE server_id = ?", { sid })
    if not m then return nil end
    local counters = U.decode(m.counters_json) or {}
    local w = NcmCore.get("paddock.world").shell(num(m.seed), tostring(m.genesis_season))
    w.seasonId, w.seasonOrdinal, w.paddockYear = tostring(m.season_id), num(m.season_ordinal, 0), num(m.paddock_year)
    w.dayIndexApplied, w.cupId, w.createdAt = num(m.day_index_applied), m.cup_id, num(m.created_at)
    w.nextPerson, w.nextOrg, w.nextSponsor = num(counters.nextPerson, 0), num(counters.nextOrg, 0), num(counters.nextSponsor, 0)
    w.recentTemplates = counters.recentTemplates or {}
    for _, r in ipairs(MySQL.query.await("SELECT * FROM paddock_series WHERE server_id = ?", { sid }) or {}) do
        w.series[r.series_id] = { id = r.series_id, tier = r.tier, division = num(r.division, 1), name = r.name }
        w.takenSeriesNames[r.name] = true
    end
    Wait(0)
    for _, r in ipairs(MySQL.query.await("SELECT * FROM paddock_org WHERE server_id = ? ORDER BY org_id", { sid }) or {}) do
        local o = {
            id = r.org_id, tier = r.tier, seriesId = r.series_id, name = r.name, short = r.short, colour = r.colour,
            prestige = num(r.prestige, 50), cash = num(r.cash, 0), facility = num(r.facility, 50),
            car = U.decode(r.car_json) or {}, ownerId = r.owner_person_id, managerId = r.manager_person_id,
            engineerId = r.engineer_person_id, strategistId = r.strategist_person_id,
            sponsorIds = U.decode(r.sponsor_ids) or {}, humanManagerDriverId = r.human_manager_driver_id,
            origin = r.origin, lifecycle = r.lifecycle, foundedSeason = r.founded_season,
            seasonsActive = num(r.seasons_active, 1), redDays = num(r.red_days, 0), lowCashDays = num(r.low_cash_days, 0),
            evidence = U.decode(r.evidence_json) or {}, pending = U.decode(r.pending_json) or {}, foldedAt = num(r.folded_at),
        }
        w.orgs[o.id] = o
        w.orgOrder[#w.orgOrder + 1] = o.id
        w.takenOrgNames[o.name] = true
    end
    Wait(0)
    local rows = MySQL.query.await("SELECT * FROM paddock_person WHERE server_id = ? ORDER BY person_id", { sid }) or {}
    local y = U.yielder(40)
    for _, r in ipairs(rows) do
        local p = {
            id = r.person_id, role = r.role, orgId = r.org_id, seat = r.seat, first = r.first, last = r.last,
            display = r.display, region = r.region, gender = r.gender, birthYear = num(r.birth_year),
            attrs = U.decode(r.attrs_json), personality = U.decode(r.personality_json), principal = U.decode(r.principal_json),
            morale = num(r.morale, 50), state = r.state, wage = num(r.wage, 0), contractEnds = num(r.contract_ends, 0),
            evidence = U.decode(r.evidence_json) or {},
        }
        w.people[p.id] = p
        w.personOrder[#w.personOrder + 1] = p.id
        w.takenNames[p.display] = true
        y()
    end
    for _, r in ipairs(MySQL.query.await("SELECT * FROM paddock_sponsor WHERE server_id = ? ORDER BY sponsor_id", { sid }) or {}) do
        local s = { id = r.sponsor_id, name = r.name, short = r.short, industry = r.industry, tier = r.tier,
            personality = U.decode(r.personality_json) or {}, orgId = r.org_id, perDay = num(r.per_day, 0) }
        w.sponsors[s.id] = s
        w.sponsorOrder[#w.sponsorOrder + 1] = s.id
        w.takenCompanies[s.name] = true
    end
    return w
end
