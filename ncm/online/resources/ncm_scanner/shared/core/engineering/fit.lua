-- ncm-core module: engineering.fit
--
-- Can these bodies physically and functionally live in this site, connected like this? (doc 50 §5; L314.)
-- Every check answers green / yellow / red WITH REASONS, and the result carries the build's canonical
-- physical state.
--
--   RED      is reserved for geometry and topology: outside the site, a reserved zone, an overlap, too tall
--            for an uncoverable zone, no mount and nowhere to make one, ports of different kinds, a driveline
--            that does not reach the wheels or splits without a selector.
--   YELLOW   is "physically possible through adaptation" (L314 R1): a cut, a raised cover, a fabricated
--            bracket, an adapter, a longer shaft. Each one is an ADAPTATION RECORD with real consequences --
--            mass, time, money, loss -- shaped so it can later become an explicit body (`artifact`). In v1
--            it stays summarised as a consequence, which R1 allows.
--   CAPACITY is never a colour. Over mass, heat, electrical, control or a mount's rating is a named
--            consequence ("it fits"; doc 48 invariant 3). Physics delivers the punchline.
--
-- **Competency improves an adaptation, never erases it** (R1): less time, less waste, a lighter bracket.
-- It never brings mass or time to zero, and it never touches conservation: every kilogram a body has is
-- in `state.massKg`.
--
-- **`state` is the persistent, authoritative physical truth** (L314 R3 and its four-concept boundary). It
-- does not know how today's runtime will express it. `engineering.actuate` derives that, separately.
local Core = NcmCore

Core.define("engineering.fit", function(C)
    local M = { version = "0.1.0" }

    local Body = C.get("engineering.body")
    local Envelope = C.get("engineering.envelope")
    local Drivetrain = C.get("engineering.drivetrain")

    M.RANK = { green = 1, yellow = 2, red = 3 }

    -- Balance placeholders (named, not scattered). Every number needs play data.
    M.ADAPT = {
        cut     = { minutesPerCell = 30, costPerCell = 40, massKg = 0, artifact = "none" },
        cover   = { minutesPerCell = 20, costPerCell = 30, kgPerCell = 1.5, artifact = "structure" },
        bracket = { minutes = 90, cost = 150, baseKg = 1.0, kgPerBodyKg = 0.06, artifact = "structure" },
        adapter = { minutes = 60, cost = 200, massKg = 3.0, efficiency = 0.98, artifact = "drivetrain" },
        shaft   = { minutesPerM = 45, costPerM = 120, kgPerM = 4.0, lossPerM = 0.005, artifact = "drivetrain" },
    }
    -- What competency (0..1) can take off: at most half the time, a third of the money and the mass.
    M.SKILL = { minutes = 0.5, cost = 0.3, massKg = 0.3 }

    local function worse(a, b) return M.RANK[a] >= M.RANK[b] and a or b end
    local function key(i, j) return i .. "," .. j end

    function M.check(site, layout, designs, opts)
        opts = opts or {}
        local skill = math.max(0, math.min(1, opts.competency or 0))
        local res = { verdict = "green", placements = {}, connections = {}, adaptations = {},
                      consequences = {}, state = {}, drivetrain = nil }

        local function mark(entry, colour, code, text)
            entry.colour = worse(entry.colour, colour)
            entry.reasons[#entry.reasons + 1] = { colour = colour, code = code, text = text }
            res.verdict = worse(res.verdict, colour)
        end
        local function adapt(kind, at, a, reason)
            a.kind, a.at, a.reason = kind, at, reason
            a.minutes = (a.minutes or 0) * (1 - M.SKILL.minutes * skill)
            a.cost = (a.cost or 0) * (1 - M.SKILL.cost * skill)
            a.massKg = (a.massKg or 0) * (1 - M.SKILL.massKg * skill)
            a.artifact = M.ADAPT[kind].artifact
            res.adaptations[#res.adaptations + 1] = a
            return a
        end

        if not Envelope.surveyed(site) then
            res.verdict = "red"
            res.reasons = { { colour = "red", code = "not_surveyed", text = "this site's geometry is not yet surveyed" } }
            return res
        end

        local cs = site.grid.cell
        local occupancy = {}
        local projected = {}
        local mountLoad = {}

        for _, p in ipairs(layout.placements or {}) do
            local entry = { colour = "green", reasons = {} }
            res.placements[p.key] = entry
            local d = designs[p.design]
            local okBody, why = d ~= nil, { "no such design: " .. tostring(p.design) }
            if d then okBody, why = Body.validate(d) end
            if not okBody then
                mark(entry, "red", "invalid_body", table.concat(why, "; "))
            else
                local proj = Body.place(d, p, cs)
                projected[p.key] = proj
                local cutCells, coverCells = 0, 0
                local fabricable = false
                for _, c in ipairs(proj.cells) do
                    local info = Envelope.cellAt(site, c[1], c[2])
                    if not info then
                        mark(entry, "red", "outside", ("cell %d,%d is outside the %s"):format(c[1], c[2], site.kind))
                    elseif info.zone.reserved then
                        mark(entry, "red", "reserved", ("cell %d,%d is the %s, which is reserved"):format(c[1], c[2], info.zone.name))
                    else
                        if info.zone.fabricable then fabricable = true end
                        if info.adaptable then cutCells = cutCells + 1 end
                        if proj.heightClass > (info.zone.height or Body.HEIGHT_CLASSES) then
                            if info.zone.coverable then coverCells = coverCells + 1
                            else
                                mark(entry, "red", "too_tall", ("height class %d does not fit under the %s (%d)")
                                    :format(proj.heightClass, info.zone.name, info.zone.height))
                            end
                        end
                    end
                    local k = key(c[1], c[2])
                    if occupancy[k] and occupancy[k] ~= p.key then
                        mark(entry, "red", "overlap", ("overlaps %s at %s"):format(occupancy[k], k))
                        local other = res.placements[occupancy[k]]
                        mark(other, "red", "overlap", ("overlaps %s at %s"):format(p.key, k))
                    else
                        occupancy[k] = p.key
                    end
                end
                if cutCells > 0 then
                    local A = M.ADAPT.cut
                    adapt("cut", p.key, { minutes = A.minutesPerCell * cutCells, cost = A.costPerCell * cutCells,
                        massKg = 0 }, ("cut into %d cell(s) to clear %s"):format(cutCells, p.key))
                    mark(entry, "yellow", "cut", ("needs %d cell(s) cut away"):format(cutCells))
                end
                if coverCells > 0 then
                    local A = M.ADAPT.cover
                    adapt("cover", p.key, { minutes = A.minutesPerCell * coverCells, cost = A.costPerCell * coverCells,
                        massKg = A.kgPerCell * coverCells }, ("raised cover over %d cell(s) (adds drag)"):format(coverCells))
                    mark(entry, "yellow", "cover", "sits proud; needs a raised cover")
                end
                -- mounting: each of the body's mounts needs a site mount of its kind under the footprint
                for _, m in ipairs(proj.mounts) do
                    local found = nil
                    for _, c in ipairs(proj.cells) do
                        local ms = Envelope.mountsAt(site, c[1], c[2], m.kind)
                        if ms[1] then found = ms[1]; break end
                    end
                    if found then
                        mountLoad[found.id] = (mountLoad[found.id] or 0) + (m.loadKg or d.massKg)
                    elseif fabricable then
                        local A = M.ADAPT.bracket
                        adapt("bracket", p.key, { minutes = A.minutes, cost = A.cost,
                            massKg = A.baseKg + A.kgPerBodyKg * d.massKg }, ("fabricated %s mount for %s"):format(m.kind, p.key))
                        mark(entry, "yellow", "bracket", ("no %s mount under it; one can be fabricated"):format(m.kind))
                    else
                        mark(entry, "red", "no_mount", ("no %s mount under it and nowhere to fabricate one"):format(m.kind))
                    end
                end
            end
        end

        -- connections
        local edgeEff = {}
        local function endpoint(ep)
            if ep[1] == "site" then
                local sp = Envelope.port(site, ep[2])
                return sp, sp and sp.cell
            end
            local proj = projected[ep[1]]
            if not proj then return nil end
            for _, pp in ipairs(proj.ports) do if pp.id == ep[2] then return pp, pp.cell end end
            return nil
        end
        for idx, c in ipairs(layout.connections or {}) do
            local entry = { colour = "green", reasons = {} }
            res.connections[idx] = entry
            local pa, ca = endpoint(c.a)
            local pb, cb = endpoint(c.b)
            if not pa or not pb then
                mark(entry, "red", "missing_port", ("%s.%s to %s.%s: a port does not exist")
                    :format(c.a[1], c.a[2], c.b[1], c.b[2]))
            elseif pa.kind ~= pb.kind then
                mark(entry, "red", "kind_mismatch", ("%s cannot connect to %s"):format(pa.kind, pb.kind))
            else
                local eff = 1
                if pa.spec and pb.spec and pa.spec ~= pb.spec then
                    local A = M.ADAPT.adapter
                    adapt("adapter", idx, { minutes = A.minutes, cost = A.cost, massKg = A.massKg },
                        ("%s to %s adapter"):format(pa.spec, pb.spec))
                    eff = eff * A.efficiency
                    mark(entry, "yellow", "adapter", ("%s meets %s: an adapter makes them connect"):format(pa.spec, pb.spec))
                end
                -- `reach`: how far a site port's own fitting runs (the stock propshaft), free of charge
                local d = math.abs(ca[1] - cb[1]) + math.abs(ca[2] - cb[2]) - (pa.reach or 0) - (pb.reach or 0)
                if d > 1 then
                    local A = M.ADAPT.shaft
                    local len = (d - 1) * cs
                    adapt("shaft", idx, { minutes = A.minutesPerM * len, cost = A.costPerM * len, massKg = A.kgPerM * len },
                        ("%.1f m shaft"):format(len))
                    eff = eff * (1 - A.lossPerM * len)
                    mark(entry, "yellow", "shaft", ("ports %.1f m apart: a longer shaft"):format(len))
                end
                edgeEff[idx] = eff
            end
        end

        -- the driveline, when this site has one
        if Envelope.port(site, Drivetrain.SOURCE) then
            local dt = Drivetrain.compose(site, layout, designs, { edgeEfficiency = edgeEff })
            res.drivetrain = dt
            res.driveline = { colour = "green", reasons = {} }
            for _, e in ipairs(dt.errors) do mark(res.driveline, "red", e.code, e.text) end
        end

        -- the canonical physical state
        local stock = site.stock or {}
        local stockKg = stock.massKg or 0
        local stockBodiesKg = 0
        for _, p in ipairs((stock.layout and stock.layout.placements) or {}) do
            local d = designs[p.design] or (stock.designs and stock.designs[p.design])
            stockBodiesKg = stockBodiesKg + ((d and d.massKg) or 0)
        end
        local bodiesKg, adaptKg, heat, power, control = 0, 0, 0, 0, 0
        for _, p in ipairs(layout.placements or {}) do
            local d = designs[p.design]
            if d then
                bodiesKg = bodiesKg + d.massKg
                heat = heat + (d.heatKw or 0)
                power = power + (d.powerKw or 0)
                control = control + (d.controlChannels or 0)
            end
        end
        for _, a in ipairs(res.adaptations) do adaptKg = adaptKg + a.massKg end
        local s = res.state
        s.stockMassKg = stockKg
        s.rollingMassKg = stockKg - stockBodiesKg
        s.bodiesKg = bodiesKg
        s.adaptationKg = adaptKg
        s.massKg = s.rollingMassKg + bodiesKg + adaptKg
        s.deltaKg = s.massKg - stockKg
        s.heatKw, s.powerKw, s.controlChannels = heat, power, control
        s.mountLoadKg = mountLoad
        s.drivetrain = res.drivetrain and res.drivetrain.ok and res.drivetrain.paths or nil

        -- capacities: consequences, never refusals
        local cap = site.capacity or {}
        local function over(name, used, limit, text)
            if limit and used > limit then
                res.consequences[#res.consequences + 1] = { capacity = name, used = used, limit = limit, text = text }
            end
        end
        over("massKg", s.massKg, cap.massKg, ("%.0f kg against a %.0f kg design mass: heavier, slower, longer to stop")
            :format(s.massKg, cap.massKg or 0))
        over("coolingKw", heat, cap.coolingKw, ("%.1f kW of heat against %.1f kW of cooling: it will run hot and derate")
            :format(heat, cap.coolingKw or 0))
        over("electricalKw", power, cap.electricalKw, ("%.1f kW drawn against %.1f kW: control features brown out")
            :format(power, cap.electricalKw or 0))
        over("controlChannels", control, cap.controlChannels, ("%d control channels against %d")
            :format(control, cap.controlChannels or 0))
        for _, m in ipairs(site.mounts or {}) do
            if m.ratedKg then
                over("mount:" .. m.id, mountLoad[m.id] or 0, m.ratedKg, ("%s carries %.0f kg against %.0f kg: it will wear")
                    :format(m.id, mountLoad[m.id] or 0, m.ratedKg))
            end
        end
        return res
    end

    return M
end)
