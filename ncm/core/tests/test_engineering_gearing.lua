-- engineering.gearing (stacked gearboxes, owner 2026-10-08): where a box sits decides what it does. The owner's own
-- examples are the cases: 12 sequential gears between box 1 and 2; two discrete boxes side by side; two stacked and one
-- discrete. Nothing names a configuration -- each follows from mounts and box data.
local function I(T) return T.Core.get("engineering.installation") end
local function G(T) return T.Core.get("engineering.gearing") end
local OD6, CR2, CS5, RP = "eng:thorton:od6:r1", "eng:archer:cr2:r1", "eng:thorton:cs5:r1", "eng:zetatech:rp16:r1"

local function resolved(T, items)
    local devices, refused = I(T).resolve(items, "archer_hella")
    T.eq(#refused, 0, "every item resolves: " .. ((refused[1] and refused[1].reason) or ""))
    return devices
end
local function box(id, design, mount) return { componentId = id, designId = design, mountId = mount, facing = "fore" } end

return {
    a_gearbox_goes_in_the_driveline_and_only_there = function(T)
        local M = I(T)
        T.ok(M.check(M.design(OD6), "archer_hella", "mount.driveline.inline.1", "fore").ok, "a box mates inline")
        T.falsy(M.check(M.design(OD6), "archer_hella", "mount.rear", "aft").ok, "not on a hardpoint")
        T.falsy(M.check(M.design(RP), "archer_hella", "mount.driveline.side.1", "fore").ok, "a propulsor is not a gearbox")
        T.falsy(M.check(M.design(OD6), "archer_hella", "mount.driveline.side.1", "aft").ok, "a driveline box faces fore")
        local d = resolved(T, { box("od", OD6, "mount.driveline.inline.1") })
        T.eq(d[1].commands.engage, "event", "a gearbox can be told to engage")
        T.eq(d[1].axis[1] + d[1].axis[2] + d[1].axis[3], 0, "and pushes nothing")
    end,

    no_driveline_boxes_is_the_cars_own_box = function(T)
        local c = G(T).compose({})
        T.falsy(c.stacked, "nothing stacked")
        T.eq(G(T).encode(c), "", "empty wire text: NCM Gearbox drives the car's box as before")
    end,

    an_inline_gearbox_continues_the_ladder_twelve_sequential_gears = function(T)
        local c = G(T).compose(resolved(T, { box("od", OD6, "mount.driveline.inline.1") }))
        T.eq(#c.paths, 1, "one path")
        local e = c.paths[1].entries
        T.eq(#e, 7, "the car's box (A) and six continuing gears")
        T.eq(e[1].base, "A", "the car's own gears first")
        for k = 2, 7 do T.eq(e[k].base, "T", "then gears off the car's top gear") end
        T.ok(e[2].m < 1 and e[7].m < e[2].m, "each taller than the car's top gear, in order")
        local text = G(T).encode(c)
        T.ok(text:match("^v1;P,any,280,") ~= nil, "slowest box's shift time: " .. text)
    end,

    a_range_box_inline_multiplies_every_gear_and_keeps_its_procedure = function(T)
        local c = G(T).compose(resolved(T, { box("cr", CR2, "mount.driveline.inline.1") }))
        local p = c.paths[1]
        T.eq(#p.entries, 2, "the car's box in each of two ranges")
        T.eq(p.rangeWhen, "stationary", "range changes only at a stop")
        T.eq(p.rangeMs, 900, "taking the range box's own time")
        T.ok(p.entries[1].group ~= p.entries[2].group, "two ranges, two groups")
        T.ok(math.abs(p.efficiency - 0.95) < 1e-9, "and its loss")
    end,

    two_discrete_boxes_side_by_side_are_two_paths_never_merged = function(T)
        local c = G(T).compose(resolved(T, { box("a", CS5, "mount.driveline.side.1"), box("b", CS5, "mount.driveline.side.2") }))
        T.eq(#c.paths, 3, "the car's box and two side paths")
        T.eq(c.pathOf.a, 2, "box a engages path 2")
        T.eq(c.pathOf.b, 3, "box b engages path 3")
        T.eq(#c.paths[2].entries, #c.paths[3].entries, "identical boxes keep identical ratios (R4.3: not de-duplicated)")
    end,

    two_stacked_and_one_discrete = function(T)
        local c = G(T).compose(resolved(T, {
            box("od", OD6, "mount.driveline.inline.1"), box("cr", CR2, "mount.driveline.inline.2"), box("cs", CS5, "mount.driveline.side.1") }))
        T.eq(#c.paths, 2, "a stacked main path and one discrete path")
        T.eq(#c.paths[1].entries, 14, "(car + 6 overdrive) in each of two ranges")
        T.eq(c.paths[2].when, "any", "the discrete box is always available")
        T.eq(c.pathOf.cs, 2, "and answers its own engage")
        local text = G(T).encode(c)
        local paths = 0
        for _ in text:gmatch(";P,") do paths = paths + 1 end
        T.eq(paths, 2, "both paths on the wire")
        T.ok(not text:find("[^%w%.%*@|;,+_-]"), "wire text is plain: " .. text)
    end,
}
