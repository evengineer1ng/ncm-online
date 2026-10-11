-- ncm-core module: world.places
-- Every place a simulated person can be, as NCM's own registry (L237 M1, IDEA-764, L240).
--
-- Four sources, one shape. `world.places_data` (service points and street-race meets, generated from the game's own
-- pins), `paddock.garages_data` (rented workplaces), `data.fuel_locations` (pumps, clustered into stations) and the
-- Autofixer terminals in `economy.markets`. Nothing is duplicated: the registry is merged once and cached.
--
--   place { id, kind, district, area, x, y, z, name? }   (`name` only where the map itself names the place)
--
-- What a kind MEANS is authored here as rules (L237: rules and vocabulary are authored, situations are not):
--   hours       Eastern opening hours { open, close }; close < open runs past midnight; nil is always open
--   visibility  how public anything that happens here is, 0..1 (Oracle Court's LocationProfile.visibility):
--               a witness is likelier at a food stall than in a back-room netrunner den
--   crowd       how many strangers are usually about, 0..1 -- feeds Social and how a body blends in
-- The host marks places good or bad in play; a bad place leaves every choice (`bad` sets are passed in).
local Core = NcmCore

Core.define("world.places", function(C)
    local M = { version = "0.1.0" }
    local Clock = C.get("world.clock")

    M.DISTRICTS = { "Watson", "Westbrook", "City Center", "Heywood", "Santo Domingo", "Pacifica", "Dogtown", "Badlands" }

    local H = 3600
    M.KINDS = {
        food      = { label = "food stall",     hours = { 7 * H, 2 * H },  visibility = 0.9, crowd = 0.9 },
        clinic    = { label = "clinic",         hours = nil,               visibility = 0.6, crowd = 0.5 },
        ripperdoc = { label = "ripperdoc",      hours = { 10 * H, 23 * H }, visibility = 0.3, crowd = 0.2 },
        weapons   = { label = "weapon shop",    hours = { 10 * H, 22 * H }, visibility = 0.5, crowd = 0.3 },
        clothing  = { label = "clothing store", hours = { 10 * H, 21 * H }, visibility = 0.7, crowd = 0.6 },
        junk      = { label = "junk shop",      hours = { 9 * H, 21 * H },  visibility = 0.5, crowd = 0.3 },
        tech      = { label = "tech shop",      hours = { 10 * H, 22 * H }, visibility = 0.5, crowd = 0.3 },
        netrunner = { label = "netrunner den",  hours = { 12 * H, 3 * H },  visibility = 0.2, crowd = 0.2 },
        fixer     = { label = "fixer's spot",   hours = { 12 * H, 4 * H },  visibility = 0.3, crowd = 0.3 },
        meet      = { label = "street meet",    hours = { 20 * H, 5 * H },  visibility = 0.8, crowd = 0.8 },
        garage    = { label = "garage",         hours = nil,               visibility = 0.4, crowd = 0.3 },
        workshop  = { label = "workshop",       hours = nil,               visibility = 0.4, crowd = 0.3 },
        parking   = { label = "parking garage", hours = nil,               visibility = 0.5, crowd = 0.3 },
        fuel      = { label = "fuel station",   hours = nil,               visibility = 0.8, crowd = 0.5 },
        autofixer = { label = "Autofixer",      hours = nil,               visibility = 0.5, crowd = 0.3 },
    }

    local function dist2(a, x, y) local dx, dy = a.x - x, a.y - y; return dx * dx + dy * dy end

    local list, byId, byDistrict
    local function build()
        list, byId, byDistrict = {}, {}, {}
        local function add(p)
            if byId[p.id] or not M.KINDS[p.kind] then return end
            list[#list + 1] = p
            byId[p.id] = p
        end
        for _, p in ipairs(C.get("world.places_data").PLACES) do
            add({ id = p.id, kind = p.kind, district = p.district, area = p.area, x = p.x, y = p.y, z = p.z })
        end
        local okG, G = pcall(C.get, "paddock.garages_data")
        if okG and G then
            for _, s in ipairs(G.SITES) do
                add({ id = s.id, kind = s.kind, district = s.district, area = s.district, x = s.x, y = s.y, z = s.z })
            end
        end
        -- Nearest already-known place's district, for sources that carry none (pumps).
        local function districtAt(x, y)
            local best, bd = nil, math.huge
            for _, p in ipairs(list) do
                local d = dist2(p, x, y)
                if d < bd then best, bd = p, d end
            end
            return best and best.district or "Badlands"
        end
        local isDistrict = {}
        for _, d in ipairs(M.DISTRICTS) do isDistrict[d] = true end
        local okM, Markets = pcall(C.get, "economy.markets")
        if okM and Markets then
            for _, m in ipairs(Markets.MARKETS or {}) do
                if m.kind == "autofixer" and m.x and m.y then
                    -- Market districts read "Heywood / The Glen": the district, then the area.
                    local d, area = tostring(m.district or ""):match("^(.-)%s*/%s*(.+)$")
                    d = d or m.district
                    if not isDistrict[d or ""] then area, d = area or d, districtAt(m.x, m.y) end   -- "Morro Rock"
                    add({ id = m.marketId, kind = "autofixer", district = d, area = area or d,
                        x = m.x, y = m.y, z = m.z or 0 })
                end
            end
        end
        -- Fuel: the stations exactly as the map pins them (`data.fuel_locations.sites`, the same list
        -- ncm_world's blips and /ncm.fuel use), under their own ids -- so `fuel_station_19` here IS "Fuel
        -- Station 19" on the player's map. Never re-clustered from pumps: that produced ids nobody could find.
        local okF, Fuel = pcall(C.get, "data.fuel_locations")
        if okF and Fuel and Fuel.sites then
            for _, st in ipairs(Fuel.sites) do
                local d = districtAt(st.x, st.y)
                add({ id = st.id, kind = "fuel", district = d, area = d, name = st.name, x = st.x, y = st.y, z = st.z })
            end
        end
        for _, p in ipairs(list) do
            byDistrict[p.district] = byDistrict[p.district] or {}
            table.insert(byDistrict[p.district], p)
        end
    end

    function M.all() if not list then build() end return list end
    function M.get(id) if not list then build() end return byId[id or ""] end

    --- Places in a district, optionally of one kind (or a set of kinds), skipping `bad` ids. A fresh list.
    function M.inDistrict(district, kinds, bad)
        if not list then build() end
        local want = kinds
        if type(kinds) == "string" then want = { [kinds] = true } end
        local out = {}
        for _, p in ipairs(byDistrict[district] or {}) do
            if (not want or want[p.kind]) and not (bad and bad[p.id]) then out[#out + 1] = p end
        end
        return out
    end

    --- Places within `radius` metres of `pos` in the plane, nearest first.
    function M.near(pos, radius, kinds, bad)
        if not list then build() end
        local r2 = radius * radius
        local out = {}
        for _, p in ipairs(list) do
            if (not kinds or kinds[p.kind]) and not (bad and bad[p.id]) then
                local d = dist2(p, pos.x or 0, pos.y or 0)
                if d <= r2 then out[#out + 1] = { place = p, d2 = d } end
            end
        end
        table.sort(out, function(a, b) if a.d2 ~= b.d2 then return a.d2 < b.d2 end return a.place.id < b.place.id end)
        for i, e in ipairs(out) do out[i] = e.place end
        return out
    end

    --- Is the place open at Eastern seconds-of-day `sod`?
    function M.openAt(place, sod)
        local k = M.KINDS[place and place.kind or ""]
        if not k then return false end
        local h = k.hours
        if not h then return true end
        if h[1] < h[2] then return sod >= h[1] and sod < h[2] end
        return sod >= h[1] or sod < h[2]
    end

    function M.isOpen(place, utc) return M.openAt(place, Clock.eastern(utc).secondsOfDay) end

    --- "a Kabuki food stall" -- a place named for a player. Never an id or a coordinate.
    function M.label(place)
        if not place then return "somewhere in Night City" end
        local k = M.KINDS[place.kind]
        local area = (place.area or place.district or "Night City"):gsub("^the ", "")
        return ("a %s %s"):format(area, k and k.label or "spot")
    end

    function M.distance(a, b)
        if not a or not b then return math.huge end
        local dx, dy = (a.x or 0) - (b.x or 0), (a.y or 0) - (b.y or 0)
        return math.sqrt(dx * dx + dy * dy)
    end

    return M
end)
