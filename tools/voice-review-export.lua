-- Export the Paddock voice bank and sample conversations for the owner's review page (owner, 2026-09-30: "i want to
-- see the lines before they go out the door no matter how big the bank is").
--
-- Usage:  lua tools/voice-review-export.lua <dev_paddock.json> <out.json>
--   dev_paddock.json: the dev world exported by the review workflow (orgs, people with personality, seed); without
--   it, a genesis world stands in. Output: { lines = [...], samples = [...], generatedAt }.
local here = arg[0]:match("^(.*)[/\\]") or "."
local root = here .. "/../ncm/core"
local Core = dofile(root .. "/init.lua")
local manifest = dofile(root .. "/MANIFEST.lua")
for i = 1, #manifest do dofile(root .. "/" .. manifest[i]) end
Core.warm()
local Json = Core.get("vocabulary.json")
local Bank, Voice = Core.get("life.voice_bank"), Core.get("life.voice")

local inPath, outPath = arg[1], arg[2] or "voice_review.json"

-- ------------------------------------------------------------------------------------------------ the bank
local lines = {}
for _, e in ipairs(Bank.all()) do
    local tags = {}
    for t in pairs(e.tags) do tags[#tags + 1] = t end
    table.sort(tags)
    lines[#lines + 1] = { id = e.id, move = e.move, tags = tags, text = e.text }
end

-- ------------------------------------------------------------------------------------------------ the cast
local seed, cast = 4242, {}
local f = inPath and io.open(inPath, "rb")
if f then
    local d = Json.decode(f:read("a")); f:close()
    seed = tonumber(d.world.seed) or d.world.seed
    local orgs = {}
    for _, o in ipairs(d.orgs) do orgs[o.org_id] = o end
    for _, r in ipairs(d.people) do
        local o = r.org_id ~= "NULL" and orgs[r.org_id]
        if o and o.lifecycle ~= "folded" and r.state == "active" then
            cast[#cast + 1] = { p = { id = r.person_id, role = r.role, display = r.display,
                personality = Json.decode(r.personality_json or "{}") or {} }, tier = o.tier, org = o.name or o.org_id }
        end
    end
else
    local w = Core.get("paddock.world").genesis(seed, "2026-S4")
    for _, id in ipairs(w.personOrder) do
        local p = w.people[id]
        local o = p.orgId and w.orgs[p.orgId]
        if o and p.state == "active" then cast[#cast + 1] = { p = p, tier = o.tier, org = o.name } end
    end
end

-- a spread: every tier x role, then fill
local picked, seen = {}, {}
for _, tier in ipairs({ "street", "regional", "pro", "premier" }) do
    for _, role in ipairs({ "driver", "engineer", "strategist", "manager", "owner" }) do
        local n = 0
        for _, x in ipairs(cast) do
            if x.tier == tier and x.p.role == role and not seen[x.p.id] then
                picked[#picked + 1] = x; seen[x.p.id] = true; n = n + 1
                if n >= ((role == "driver") and 3 or 2) then break end
            end
        end
    end
end

local SCENES = {
    { activity = "fuel", place = "Fuel Station 19", district = "Heywood", regime = "scene_town", weather = "rain", hour = 20 },
    { activity = "eat", place = "a Kabuki food stall", district = "Watson", regime = "balance", crisis = true, weather = "clear", hour = 13 },
    { activity = "loiter", place = "a Glen food stall", district = "Heywood", regime = "scene_town", weather = "fog", hour = 2 },
    { activity = "hang", place = "the Arroyo street meet", district = "Santo Domingo", regime = "scene_town", weather = "grey", hour = 22 },
    { activity = "work", place = "their garage", district = "City Center", regime = "lockdown", weather = "smog", hour = 10 },
    { activity = "errand", place = "a Japantown clothing store", district = "Westbrook", regime = "balance", weather = "sunny", hour = 16 },
    { activity = "hustle", place = "a Pacifica fixer's spot", district = "Pacifica", regime = "gang_rule", crisis = true, weather = "rain", hour = 23 },
    { activity = "fuel", place = "Fuel Station 42", district = "Dogtown", regime = "open_war", crisis = true, weather = "pollution", hour = 19 },
    { activity = "eat", place = "a Badlands food stall", district = "Badlands", regime = "scene_town", weather = "sandstorm", hour = 7 },
}
local FAMILIARITY = {
    { label = "stranger", metCount = 0, fame = 0 },
    { label = "stranger, but heard of you", metCount = 0, fame = 15 },
    { label = "met once before", metCount = 1, fame = 0 },
    { label = "a regular", metCount = 5, fame = 0 },
    { label = "stranger, you are famous", metCount = 0, fame = 40 },
}
local ROUTES = { "Hanford Overpass", "Vista Del Drag", "Kabuki Bridge", "Gold Niwaki Plaza", "Checkerboard" }
local RESULTS = { { "win", "1st" }, { "podium", "2nd" }, { "finish", "7th" }, { "dnf", "out early" }, { "podium", "3rd" } }
local SERIES = { street = "Heywood Street League", regional = "Regional Cup", pro = "Pro Series", premier = "Premier Championship" }

local samples = {}
for i, x in ipairs(picked) do
    local scene = SCENES[1 + (i - 1) % #SCENES]
    local fam = FAMILIARITY[1 + math.floor((i - 1) / 2) % #FAMILIARITY]
    local res = RESULTS[1 + (i - 1) % #RESULTS]
    local facts = {
        name = x.p.display, role = Core.get("paddock.talk").ROLE_LABEL[x.p.role] or x.p.role, org = x.org,
        series = SERIES[x.tier],
        route = ROUTES[1 + i % #ROUTES], when = ("%02d:%02d"):format(20 + i % 4, (i * 10) % 60),
        lastRoute = ROUTES[1 + (i + 2) % #ROUTES], lastPlace = res[2], lastResult = res[1], lastDriver = "Mika Sato",
    }
    local ctx = { seed = seed, person = x.p, tier = x.tier, year = 2077, metCount = fam.metCount, dayIndex = 20727,
        facts = facts, activity = scene.activity, place = scene.place, district = scene.district,
        regime = scene.regime, crisis = scene.crisis, weather = scene.weather, hour = scene.hour,
        fame = fam.fame, playerName = "easporks" }
    local out = Voice.say(ctx)
    local v = out.voice
    samples[#samples + 1] = {
        name = x.p.display, role = x.p.role, tier = x.tier, org = x.org,
        voice = { reg = v.reg, warm = v.warm, temper = v.temper, conf = v.conf, talk = v.talk, humor = v.humor,
            addr = v.addr ~= "" and v.addr or nil, tic = v.tic, good = v.good, bad = v.bad, swear = v.swear,
            young = v.young or nil, old = v.old or nil },
        scene = { activity = scene.activity, place = scene.place, district = scene.district, regime = scene.regime,
            crisis = scene.crisis or false, weather = scene.weather, hour = scene.hour },
        familiarity = fam.label, text = out.text, lines = out.lines, moves = out.moves,
    }
end

local o = assert(io.open(outPath, "wb"))
o:write(Json.encode({ lines = lines, samples = samples, generatedAt = os.date("!%Y-%m-%dT%H:%M:%SZ") }))
o:close()
print(("exported %d lines and %d sample conversations to %s"):format(#lines, #samples, outPath))
