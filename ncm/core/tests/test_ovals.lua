-- data.ovals (L236): four authored points round a roundabout become a lapped race with a grid that stays on the loop.
local ROUNDABOUT = { id = "test_ring", name = "Test Ring", region = "City Center",
    -- a 60 m-radius roundabout centred on (1000, 2000), points given out of order on purpose
    points = { { x = 1060, y = 2000, z = 10 }, { x = 1000, y = 1940, z = 10 }, { x = 940, y = 2000, z = 10 }, { x = 1000, y = 2060, z = 10 } } }

return {
    geometry_orders_the_loop_anticlockwise_from_the_line = function(T)
        local O = T.Core.get("data.ovals")
        local g = assert(O.geometry(ROUNDABOUT))
        T.ok(math.abs(g.radius - 60) < 0.01, "radius from the points")
        T.eq(g.loop[1].x, 1060, "the author's first point is the line")
        T.eq(g.loop[2].y, 2060, "then anticlockwise: north")
        T.eq(g.loop[3].x, 940, "then west")
        T.eq(g.loop[4].y, 1940, "then south")
        T.ok(math.abs(g.tangent.x) < 1e-9 and math.abs(g.tangent.y - 1) < 1e-9, "at the east point the race heads north")
        T.eq(g.laps, 6, "about 2.4 km of racing on a 377 m loop")
        T.eq(g.fieldMax, 16, "a big roundabout grids a full field")
        local small = assert(O.geometry({ id = "small", points = { { x = 20, y = 0 }, { x = 0, y = 20 }, { x = -20, y = 0 }, { x = 0, y = -20 } } }))
        T.ok(small.fieldMax < 16 and small.fieldMax >= 4, "a small one grids fewer (" .. small.fieldMax .. ")")
        T.eq(select(2, O.geometry({ id = "tiny", points = { { x = 3, y = 0 }, { x = 0, y = 3 }, { x = -3, y = 0 } } })) ~= nil, true, "a pole is not a roundabout")
    end,

    an_oval_resolves_as_a_lapped_route = function(T)
        local O = T.Core.get("data.ovals")
        local Routes = T.Core.get("course.routes")
        local L = T.Core.get("paddock.live")
        O.register(ROUNDABOUT)
        local r = Routes.resolve("oval_test_ring")
        T.ok(r ~= nil and r.oval ~= nil, "resolves")
        T.eq(r.start.id, r.finish.id, "starts and finishes on the line")
        T.eq(#r.intermediate, 6 * 3 + 5, "three poles a lap, the line between laps")
        T.ok(math.abs(r.distanceM - 6 * 2 * math.pi * 60) < 0.01, "driven round the circle, not its chords")
        local path = L.path(r, nil)
        T.eq(#path.points, 25, "the drive plan is every point of every lap (under 64)")
        local gates = L.checkpoints(r, path, 6)
        T.eq(#gates, 25, "a gate at every point")
        T.ok(gates[2].captureM <= 27, "gates sized to the roundabout")
        local slots = L.ovalSlots(r.oval, 20)
        T.eq(#slots, 16, "no more cars than it grids")
        for _, s in ipairs(slots) do
            local d = math.sqrt((s.x - 1000) ^ 2 + (s.y - 2000) ^ 2)
            T.ok(math.abs(d - 60) <= 2.3, "every car on the loop (" .. d .. " m from the centre)")
        end
        T.ok(slots[1].y < 2000 and slots[3].y < slots[1].y, "the grid runs back round the loop behind the line (clockwise of it)")
        T.falsy(T.Core.get("course.generator").decode("oval_test_ring"), "never a generated route")
        for _, n in ipairs(T.Core.get("course.generator").pool()) do T.ok(n.id ~= r.start.id, "the line is not a generator node") end
        -- the sim sees an oval at roundabout speed
        local Cal = T.Core.get("paddock.calibration")
        local base = Cal.baseline(1, r.routeId, r.distanceM, "street", r)
        T.ok(base > 120 and base < 170, "about 2.3 km at roundabout pace takes a couple of minutes: " .. base)
        -- tidy up for other suites
        for i, d in ipairs(O.LIST) do if d.id == "test_ring" then table.remove(O.LIST, i) end end
    end,
}
