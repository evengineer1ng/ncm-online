-- build.attach (IDEA-1282): the Build primitive's catalogue, limits, chains and transforms.
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end
local function nearV(a, b, eps) return near(a[1], b[1], eps) and near(a[2], b[2], eps) and near(a[3], b[3], eps) end

return {
    every_catalogue_item_has_a_stable_id_and_what_physics_will_need = function(T)
        local B = T.Core.get("build.attach")
        T.eq(#B.ORDER, 20)
        for _, id in ipairs(B.ORDER) do
            local it = B.CATALOGUE[id]
            T.ok(it, id .. " is in the catalogue")
            T.ok(id:match("^NCM_[A-Z_]+_%d%d$"), id .. " is a stable id")
            if it.kit then
                T.ok(it.kit:match("^kit_[a-z_]+$") and it.skyKind >= 15 and it.skyKind <= 29, id .. " names a kit mesh and an NCM Sky kind")
                T.eq(it.model, nil, id .. " is not a platform prop")
            else
                T.ok(type(it.model) == "string" and not it.model:find("[\\/]"), id .. " names an approved alias, never a path")
                T.ok(not it.standIn, id .. ": no stand-in in the palette")
            end
            T.ok(it.massKg > 0 and it.areaM2 > 0 and (it.surface == "lifting" or it.surface == "bluff" or it.surface == "structural"))
        end
    end,

    every_kit_piece_has_its_own_sky_kind_and_panels_carry = function(T)
        local B = T.Core.get("build.attach")
        local seen = {}
        for _, id in ipairs(B.KIT_ORDER) do
            local k = B.CATALOGUE[id].skyKind
            T.ok(not seen[k], "kind " .. k .. " used once")
            seen[k] = true
        end
        T.eq(#B.KIT_ORDER, 15)
        T.ok(B.canCarry("NCM_KIT_PANEL_L_01") and B.canCarry("NCM_KIT_WALL_01") and B.canCarry("NCM_KIT_STRUT_01"))
        T.ok(not B.canCarry("NCM_KIT_WING_S_01"), "a wing carries nothing")
    end,

    euler_survives_a_round_trip = function(T)
        local B = T.Core.get("build.attach")
        for _, r in ipairs({ { 0, 0, 0 }, { 10, -20, 30 }, { -45, 12, 170 }, { 5, 80, -90 } }) do
            T.ok(nearV(B.euler(B.matrix(r)), r, 1e-6), ("roll %g pitch %g yaw %g"):format(r[1], r[2], r[3]))
        end
    end,

    a_child_follows_its_parent_through_a_turn = function(T)
        local B = T.Core.get("build.attach")
        -- a beam 1 m forward of the car, turned 90 deg left; a wing 0.5 m along the beam's own forward
        local pos, rot = B.compose({ 0, 1, 0 }, { 0, 0, 90 }, { 0, 0.5, 0 }, { 0, 0, 0 })
        T.ok(nearV(pos, { -0.5, 1, 0 }, 1e-9), "the beam's forward is the car's -x after a 90 deg yaw")
        T.ok(near(rot[3], 90, 1e-9), "and the wing inherits the yaw")
        -- composition is associative with the matrix product (a tilted parent)
        local p2, r2 = B.compose({ 0, 0, 1 }, { 0, 20, 0 }, { 0, 0, 0.3 }, { 0, -20, 0 })
        T.ok(near(r2[2], 0, 1e-9), "a pitched-down wing on a pitched-up member sits level")
        T.ok(near(p2[3], 1 + 0.3 * math.cos(math.rad(20)), 1e-9))
    end,

    chains_resolve_to_the_machine_and_refuse_loops = function(T)
        local B = T.Core.get("build.attach")
        local byId = {
            beam = { id = "beam", assetId = "NCM_BEAM_01", parent = { kind = "machine", id = "M1" }, pos = { 0, -1.8, 0.9 }, rot = { 0, 0, 0 } },
            wing = { id = "wing", assetId = "NCM_WING_SMALL_01", parent = { kind = "attachment", id = "beam" }, pos = { 0, 0, 0.3 }, rot = { 0, 10, 0 } },
        }
        local r = B.resolve(byId, "wing")
        T.eq(r.machineId, "M1"); T.eq(r.depth, 2)
        T.ok(nearV(r.pos, { 0, -1.8, 1.2 }, 1e-9))
        byId.beam.parent = { kind = "attachment", id = "wing" }
        T.eq(select(2, B.resolve(byId, "wing")), "cycle")
        byId.beam.parent = { kind = "attachment", id = "gone" }
        T.eq(select(2, B.resolve(byId, "wing")), "missing_parent")
    end,

    validation_names_every_refusal = function(T)
        local B = T.Core.get("build.attach")
        local ok, plan = B.validate({ assetId = "NCM_WING_SMALL_01", parent = { kind = "machine", id = "M1" }, pos = { 0, -1.9, 1.1 }, rot = { 0, -8, 180 } }, {})
        T.ok(ok); T.eq(plan.root.machineId, "M1"); T.ok(near(plan.rot[3], 180) or near(plan.rot[3], -180))
        local function why(req, ctx) return select(2, B.validate(req, ctx or {})) end
        local base = function() return { assetId = "NCM_WING_SMALL_01", parent = { kind = "machine", id = "M1" }, pos = { 0, 0, 1 }, rot = { 0, 0, 0 } } end
        local r = base(); r.assetId = "../../evil.mesh"; T.eq(why(r), "unknown_asset")
        r = base(); r.parent = { kind = "world", id = "x" }; T.eq(why(r), "bad_parent")
        r = base(); r.pos = { 0 / 0, 0, 0 }; T.eq(why(r), "bad_transform")
        r = base(); r.pos = { 0, 0, 3.5 }; T.eq(why(r), "too_far_from_parent")
        T.eq(why(base(), { onMachine = 12 }), "machine_full")
        T.eq(why(base(), { byPlayer = 60 }), "player_limit")
        T.eq(why(base(), { total = 400 }), "server_limit")
        T.eq(why(base(), { onMachine = 3, limits = { perParent = 3 } }), "machine_full", "limits are configurable")
        -- a wing cannot carry; a beam can
        local byId = { w = { id = "w", assetId = "NCM_WING_SMALL_01", parent = { kind = "machine", id = "M1" }, pos = { 0, 0, 1 }, rot = { 0, 0, 0 } },
            b = { id = "b", assetId = "NCM_BEAM_01", parent = { kind = "machine", id = "M1" }, pos = { 0, 0, 1 }, rot = { 0, 0, 0 } } }
        r = base(); r.parent = { kind = "attachment", id = "w" }; T.eq(why(r, { byId = byId }), "parent_cannot_carry")
        r = base(); r.parent = { kind = "attachment", id = "b" }; r.pos = { 0, 0, 0.5 }
        T.ok(B.validate(r, { byId = byId }), "a member carries")
        -- a chain may not reach beyond the Machine's envelope, even when each link is short
        byId.b.pos = { 0, 2.9, 0 }
        r = base(); r.parent = { kind = "attachment", id = "b" }; r.pos = { 0, 2.0, 0 }
        T.eq(why(r, { byId = byId }), "too_far_from_machine")
        -- depth
        byId.c = { id = "c", assetId = "NCM_BAR_01", parent = { kind = "attachment", id = "b" }, pos = { 0, 0, 0.2 }, rot = { 0, 0, 0 } }
        byId.b.pos = { 0, 0, 0.5 }
        byId.d = { id = "d", assetId = "NCM_BAR_01", parent = { kind = "attachment", id = "c" }, pos = { 0, 0, 0.2 }, rot = { 0, 0, 0 } }
        r = base(); r.parent = { kind = "attachment", id = "d" }; r.pos = { 0, 0, 0.2 }
        T.eq(why(r, { byId = byId }), "too_deep")
    end,

    the_physics_hook_tells_a_backwards_wing_from_a_right_one = function(T)
        local B = T.Core.get("build.attach")
        local byId = {
            a = { id = "a", assetId = "NCM_WING_SMALL_01", parent = { kind = "machine", id = "M" }, pos = { 0, -1.9, 1 }, rot = { 0, 0, 0 } },
            b = { id = "b", assetId = "NCM_WING_SMALL_01", parent = { kind = "machine", id = "M" }, pos = { 0, -1.9, 1 }, rot = { 0, 0, 180 } },
        }
        local ph = B.physical({ byId.a, byId.b }, byId)
        T.eq(ph.massKg, 12)
        T.ok(near(ph.surfaces[1].forward[2], 1, 1e-9) and near(ph.surfaces[2].forward[2], -1, 1e-9),
            "the same id, two different surfaces: one faces forward, one backward")
    end,
}
