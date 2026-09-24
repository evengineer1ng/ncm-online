-- data.roots / data.nodes: the authored network resolves.
--
-- IDEA-104: a typo in a root's `startNodeId` is not currently caught anywhere early. `calendar.validateSeries`
-- does call `routes.resolve` on every series route, but only when a series is registered, and a bad id there
-- rejects the whole series at boot with one log line. These tests fail loudly instead, at the point the data is
-- edited, which is where the mistake is made.
return {
    every_root_resolves_to_two_real_nodes = function(T)
        local Roots = T.Core.get("data.roots")
        local Routes = T.Core.get("course.routes")
        local Nodes = T.Core.get("data.nodes")
        T.ok(#Roots.LIST >= 10, "the authored roots pack is present")
        for _, r in ipairs(Roots.LIST) do
            local where = r.rootId
            if not r.custom then
                T.ok(Nodes.byId(r.startNodeId) ~= nil, "start node exists for " .. where .. ": " .. tostring(r.startNodeId))
                T.ok(Nodes.byId(r.endNodeId) ~= nil, "end node exists for " .. where .. ": " .. tostring(r.endNodeId))
                T.ok(r.startNodeId ~= r.endNodeId, "a root goes somewhere: " .. where)
                local route = Routes.resolve(r.rootId)
                T.ok(route ~= nil, "resolves: " .. where)
                T.ok(route.distanceM > 0, "has a length: " .. where)
                T.ok(type(route.name) == "string" and route.name ~= "" and route.name ~= r.rootId,
                    "has a display name that is not its id: " .. where)
            end
        end
    end,

    node_ids_are_unique_and_the_curated_bank_is_complete = function(T)
        -- NOTE: `data.nodes.LIST` is a SHARED MUTABLE catalogue and the core test runner uses one Core for every
        -- file, so any test that calls `Nodes.register` leaves its nodes behind for every later test (alphabetical
        -- order). Asserting "every node in LIST has a name and a region" therefore tests whatever ran first, not
        -- the authored network. Assert the two things that are actually true and actually matter: ids are unique
        -- across everything, and the curated bank is intact.
        local Nodes = T.Core.get("data.nodes")
        local seen, curated = {}, 0
        for _, n in ipairs(Nodes.LIST) do
            T.ok(type(n.id) == "string" and n.id ~= "", "every node has an id")
            T.eq(seen[n.id], nil, "node ids are unique: " .. tostring(n.id))
            seen[n.id] = true
            T.ok(type(n.x) == "number" and type(n.y) == "number", "node has coordinates: " .. n.id)
            local complete = type(n.name) == "string" and n.name ~= ""
                and type(n.region) == "string" and n.region ~= ""
                and type(n.heading) == "number"
            if complete then curated = curated + 1 end
        end
        T.ok(curated >= 35, "all 35 curated nodes carry name, region and heading (found " .. curated .. ")")
        -- spot-check the network's corners, so a truncated import cannot pass on count alone
        for _, id in ipairs({ "tip_-1035_3652", "trench_-2899_-2711", "go_smile_5042_-1044", "waterfront_-569_2648" }) do
            local n = Nodes.byId(id)
            T.ok(n ~= nil, "curated node present: " .. id)
            T.ok(type(n.region) == "string" and n.region ~= "", "and carries its region: " .. id)
        end
    end,

    root_ids_are_unique = function(T)
        local Roots = T.Core.get("data.roots")
        local seen = {}
        for _, r in ipairs(Roots.LIST) do
            T.eq(seen[r.rootId], nil, "root ids are unique: " .. tostring(r.rootId))
            seen[r.rootId] = true
        end
    end,

    the_route_name_comes_from_the_roots_pack = function(T)
        -- KB/IDEA-104: `resolve` does `name = label or root.displayName`, so a series-level label silently
        -- renames an authored route. Tip-to-Trench was really Ukulele for months because of one such override.
        local Routes = T.Core.get("course.routes")
        local r = Routes.resolve("root_tip_1035_3652__to__trench_2899_2711")
        T.eq(r.name, "Ukulele", "the roots pack owns the name")
        local overridden = Routes.resolve("root_tip_1035_3652__to__trench_2899_2711", "Tip-to-Trench")
        T.eq(overridden.name, "Tip-to-Trench", "a label still wins, which is exactly why packs must not set one")
    end,

    drag_routes_are_marked_as_such = function(T)
        -- The series builder reads this rather than a human sorting routes by hand (owner, 2026-09-22).
        local Roots = T.Core.get("data.roots")
        local drag = {}
        for _, r in ipairs(Roots.LIST) do if r.recommendedMode == "drag" then drag[#drag + 1] = r.displayName end end
        table.sort(drag)
        T.eq(#drag, 2, "two authored roots are drag routes")
        T.eq(drag[1], "B-line"); T.eq(drag[2], "Hold Your Breath")
    end,

    a_drag_course_builds_from_a_two_node_route = function(T)
        -- drag uses the `lanes` adapter; prove it needs no extra route data before scheduling a drag series.
        local D = T.Core.get("competition.discipline")
        local Routes = T.Core.get("course.routes")
        local route = Routes.resolve("root_vista_del_drag_900_751__to__japantown_crossway_373_0")
        local course, why = D.buildCourse("drag", route, {})
        T.ok(course ~= nil, "drag course builds: " .. tostring(why))
        T.eq(course.adapter, "lanes")
        T.eq(#course.lanes, 4, "four lanes by default")
        T.ok(course.lengthM > 0)
    end,
    every_route_carries_its_authored_description = function(T)
        -- The owner wrote a description for all ten routes and the Guide showed generic text for months:
        -- `guide.rows` generated a line unconditionally and never read `route.description`, so the authored
        -- prose was stored, resolved, and thrown away at render.
        local Roots = T.Core.get("data.roots")
        local Routes = T.Core.get("course.routes")
        for _, r in ipairs(Roots.LIST) do
            if not r.custom then
                T.ok(type(r.description) == "string" and #r.description > 30,
                    "authored description present: " .. r.rootId)
                T.eq(Routes.resolve(r.rootId).description, r.description, "and survives resolve: " .. r.rootId)
            end
        end
    end,

    guide_rows_prefer_the_authored_description_over_the_generated_one = function(T)
        local G = T.Core.get("competition.guide")
        local e = {
            eventId = "e1", seriesName = "NCM City Cup", routeName = "Hook", state = "entry_open",
            routeId = "root_central_highway_1110_342__to__pothole_1354_476", postedAt = 0,
            startsAt = 2000, entryOpensAt = 1000, entryClosesAt = 1900, disciplineId = "street_sprint",
            venue = { name = "Central Highway" }, finish = { name = "Pothole" }, entries = {},
        }
        local row = G.rows({ e }, nil, 1500, {})[1]
        T.match(row.description, "hooks away from Central Highway", "the authored prose reaches the guide")
        T.ok(row.summary and row.summary:find("standing start"), "the generated facts survive as `summary`")
        T.neq(row.description, row.summary, "they are two different things, and both are useful")

        -- a route with no authored description still gets something to show
        local bare = { eventId = "e2", routeId = "nope", state = "entry_open", postedAt = 0, startsAt = 2000,
                       entryOpensAt = 1000, entryClosesAt = 1900, disciplineId = "street_sprint",
                       venue = { name = "A" }, finish = { name = "B" }, entries = {} }
        local row2 = G.rows({ bare }, nil, 1500, {})[1]
        T.eq(row2.description, row2.summary, "with nothing authored, the generated line is the description")
    end,
}
