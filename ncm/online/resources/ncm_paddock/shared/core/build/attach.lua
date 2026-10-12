-- ncm-core module: build.attach
-- The Build primitive (IDEA-1282): attach an approved physical thing to another physical thing.
--
-- "Build is not a catalogue of things players are allowed to make. Build is a grammar for attaching physical things to
-- physical things. The spoiler is merely our first sentence." (owner brief, 2026-10-10)
--
-- An ATTACHMENT is { id, assetId, parent = { kind = "machine" | "attachment", id }, pos = {x,y,z} (m),
-- rot = {roll, pitch, yaw} (deg) } -- its transform RELATIVE TO ITS PARENT, never a world coordinate. A chain
-- (Machine -> beam -> wing) is stored as it was built; `resolve` walks it to the root and composes the transforms,
-- because the platform binds a prop to a vehicle or a player only (Open77 `props.attach`), never to another prop.
--
-- Rotation convention is the platform's binding convention: x = roll, y = pitch, z = yaw, in degrees, applied as
-- parent * Rz(yaw) * Ry(pitch) * Rx(roll). Positions are in the parent's local frame (x right, y forward, z up for a
-- vehicle root).
--
-- Physics: each catalogue item carries what later models will need (mass, a reference area, a surface kind, its own
-- forward / lift axes). Nothing here applies it. `physical(...)` is the HOOK: it reports what an attachment set WOULD
-- add (mass, and each lifting / bluff surface with its orientation in the root frame) so a later handling contributor
-- can derive drag and downforce from geometry -- a backwards wing is a different surface, not the same id.
-- Pure: no runtime reads.
local Core = NcmCore

Core.define("build.attach", function(C)
    local M = { version = "0.1.0" }

    -- ---------------------------------------------------------------------------------------------------- catalogue
    -- Server-approved Build assets. Every client already has them (Open77's curated prop aliases ship with the
    -- platform); nothing here is a path or a client file. `model` is the alias the server mints; `standIn` marks an
    -- item whose real art does not exist yet (KB-431: the catalogue has no wing, splitter or spoiler mesh).
    --   surface: "lifting" (a wing: lift along its local +z, chord along local +y), "bluff" (a panel / box: drag only),
    --            "structural" (a member: carries children, little drag)
    M.CATALOGUE = {
        NCM_WING_SMALL_01  = { category = "wing",      label = "Small wing (plate stand-in)",  model = "sign.rect.blank",
            massKg = 6,  surface = "lifting", areaM2 = 0.35, standIn = true },
        NCM_WING_LARGE_01  = { category = "wing",      label = "Large wing (sheet stand-in)",  model = "debris.corrugated_sheet",
            massKg = 14, surface = "lifting", areaM2 = 0.9, standIn = true },
        NCM_SPOILER_01     = { category = "spoiler",   label = "Spoiler (frame stand-in)",     model = "sign.kiosk_frame",
            massKg = 5,  surface = "bluff", areaM2 = 0.25, standIn = true },
        NCM_SPLITTER_01    = { category = "splitter",  label = "Splitter (plate stand-in)",    model = "sign.street",
            massKg = 5,  surface = "lifting", areaM2 = 0.3, standIn = true },
        NCM_AERO_PANEL_01  = { category = "aero_panel", label = "Aero panel",                  model = "debris.corrugated_sheet",
            massKg = 8,  surface = "bluff", areaM2 = 0.6 },
        NCM_BAR_01         = { category = "structural", label = "Structural bar",              model = "pipe.small",
            massKg = 4,  surface = "structural", areaM2 = 0.05 },
        NCM_BEAM_01        = { category = "structural", label = "Structural beam",             model = "pipe.medium",
            massKg = 12, surface = "structural", areaM2 = 0.1 },
        NCM_PANEL_FLAT_01  = { category = "panel",     label = "Flat panel",                   model = "sign.rect.blank",
            massKg = 4,  surface = "bluff", areaM2 = 0.35 },
        NCM_BOX_SMALL_01   = { category = "equipment", label = "Equipment box",                model = "container.toolbox",
            massKg = 10, surface = "bluff", areaM2 = 0.12 },
        NCM_BOX_CASE_01    = { category = "equipment", label = "Equipment case",               model = "container.ammo_case",
            massKg = 9,  surface = "bluff", areaM2 = 0.15 },
    }
    M.ORDER = { "NCM_WING_SMALL_01", "NCM_WING_LARGE_01", "NCM_SPOILER_01", "NCM_SPLITTER_01", "NCM_AERO_PANEL_01",
        "NCM_BAR_01", "NCM_BEAM_01", "NCM_PANEL_FLAT_01", "NCM_BOX_SMALL_01", "NCM_BOX_CASE_01" }
    -- What may carry what. Every item may sit on a Machine; members (structural) may carry anything.
    M.PARENTS = { machine = true, attachment = true }
    function M.canCarry(parentAsset)
        return parentAsset == nil or (M.CATALOGUE[parentAsset] and M.CATALOGUE[parentAsset].surface == "structural") or false
    end

    -- ------------------------------------------------------------------------------------------------------- limits
    -- Defaults only: the server reads its tunables and passes them in. Platform ceilings are separate and fixed.
    M.LIMITS = {
        perParent = 12,      -- attachments on one Machine (Open77: 32 bindings per parent, shared across resources)
        perPlayer = 60,      -- live attachments one player has built
        totalActive = 400,   -- Build props alive on the server
        maxDepth = 3,        -- Machine -> member -> member -> thing
        maxReachM = 4.0,     -- how far from the root Machine's origin anything may sit (composed)
        maxLocalM = 3.0,     -- how far from its own parent a link may sit
    }
    M.PLATFORM_OFFSET_M = 20   -- Open77 binding offsets are |x|, |y|, |z| <= 20

    -- ---------------------------------------------------------------------------------------------------- transforms
    local rad, deg = math.pi / 180, 180 / math.pi
    local atan2 = math.atan2 or math.atan

    --- 3x3 rotation for roll (x), pitch (y), yaw (z), composed Rz * Ry * Rx.
    function M.matrix(rot)
        local r, p, y = (rot[1] or 0) * rad, (rot[2] or 0) * rad, (rot[3] or 0) * rad
        local cr, sr, cp, sp, cy, sy = math.cos(r), math.sin(r), math.cos(p), math.sin(p), math.cos(y), math.sin(y)
        return {
            { cy * cp, cy * sp * sr - sy * cr, cy * sp * cr + sy * sr },
            { sy * cp, sy * sp * sr + cy * cr, sy * sp * cr - cy * sr },
            { -sp,     cp * sr,                cp * cr },
        }
    end

    --- Back to roll, pitch, yaw (degrees) from an Rz * Ry * Rx matrix.
    function M.euler(m)
        local sp = -m[3][1]
        if sp > 1 then sp = 1 elseif sp < -1 then sp = -1 end
        local pitch = math.asin(sp)
        local roll, yaw
        if math.abs(sp) < 0.999999 then
            roll = atan2(m[3][2], m[3][3])
            yaw = atan2(m[2][1], m[1][1])
        else                                   -- gimbal lock: put it all in yaw
            roll = 0
            yaw = atan2(-m[1][2], m[2][2])
        end
        return { roll * deg, pitch * deg, yaw * deg }
    end

    local function mul(a, b)
        local o = {}
        for i = 1, 3 do
            o[i] = {}
            for j = 1, 3 do o[i][j] = a[i][1] * b[1][j] + a[i][2] * b[2][j] + a[i][3] * b[3][j] end
        end
        return o
    end
    local function apply(m, v)
        return { m[1][1] * v[1] + m[1][2] * v[2] + m[1][3] * v[3], m[2][1] * v[1] + m[2][2] * v[2] + m[2][3] * v[3],
            m[3][1] * v[1] + m[3][2] * v[2] + m[3][3] * v[3] }
    end
    M.apply = apply

    --- A child's transform in its grandparent's frame: parent (pos, rot) then child (pos, rot) relative to it.
    function M.compose(parentPos, parentRot, childPos, childRot)
        local pm = M.matrix(parentRot)
        local d = apply(pm, childPos)
        return { parentPos[1] + d[1], parentPos[2] + d[2], parentPos[3] + d[3] }, M.euler(mul(pm, M.matrix(childRot)))
    end

    local function finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end
    local function vec3(t)
        if type(t) ~= "table" then return nil end
        local a, b, c = t[1] or t.x, t[2] or t.y, t[3] or t.z
        if not (finite(a) and finite(b) and finite(c)) then return nil end
        return { a, b, c }
    end
    local function rot3(t)
        if type(t) ~= "table" then return nil end
        local a, b, c = t[1] or t.roll or t.x, t[2] or t.pitch or t.y, t[3] or t.yaw or t.z
        if not (finite(a) and finite(b) and finite(c)) then return nil end
        local function wrap(d) d = d % 360; if d > 180 then d = d - 360 end; return d end
        return { wrap(a), wrap(b), wrap(c) }
    end
    M.vec3, M.rot3 = vec3, rot3

    -- ------------------------------------------------------------------------------------------------------- chains
    --- Walk an attachment to its root. `byId` = { [id] = attachment }. Returns { machineId, depth, pos, rot } in the
    --- root Machine's frame, or nil, reason ("missing_parent", "cycle", "too_deep").
    function M.resolve(byId, id, maxDepth)
        maxDepth = maxDepth or M.LIMITS.maxDepth
        local chain, seen = {}, {}
        local cur = byId[id]
        while cur do
            if seen[cur.id] then return nil, "cycle" end
            seen[cur.id] = true
            table.insert(chain, 1, cur)
            if #chain > maxDepth then return nil, "too_deep" end
            local p = cur.parent or {}
            if p.kind == "machine" then
                local pos, rot = { 0, 0, 0 }, { 0, 0, 0 }
                for _, link in ipairs(chain) do pos, rot = M.compose(pos, rot, link.pos, link.rot) end
                return { machineId = p.id, depth = #chain, pos = pos, rot = rot }
            elseif p.kind == "attachment" then
                cur = byId[p.id]
                if not cur then return nil, "missing_parent" end
            else
                return nil, "bad_parent"
            end
        end
        return nil, "missing"
    end

    -- ----------------------------------------------------------------------------------------------------- validate
    --- Validate a proposed attachment against the catalogue, the parent, the limits and what already exists.
    --- `req` = { assetId, parent = { kind, id }, pos, rot }; `ctx` = { byId (live attachments, by id),
    --- onMachine (count on the root Machine), byPlayer (count this player has live), total (live on the server),
    --- limits }. Returns true, { pos, rot, root } or false, reason.
    function M.validate(req, ctx)
        ctx = ctx or {}
        local L = {}
        for k, v in pairs(M.LIMITS) do L[k] = (ctx.limits and ctx.limits[k]) or v end
        local item = M.CATALOGUE[req.assetId or ""]
        if not item then return false, "unknown_asset" end
        local p = req.parent or {}
        if not M.PARENTS[p.kind or ""] or type(p.id) ~= "string" or p.id == "" then return false, "bad_parent" end
        local pos, rot = vec3(req.pos), rot3(req.rot)
        if not pos or not rot then return false, "bad_transform" end
        if math.sqrt(pos[1] ^ 2 + pos[2] ^ 2 + pos[3] ^ 2) > L.maxLocalM then return false, "too_far_from_parent" end
        local byId = ctx.byId or {}
        if p.kind == "attachment" then
            local parent = byId[p.id]
            if not parent then return false, "missing_parent" end
            if not M.canCarry(parent.assetId) then return false, "parent_cannot_carry" end
        end
        local probe = { id = "\0probe", assetId = req.assetId, parent = p, pos = pos, rot = rot }
        local view = setmetatable({ ["\0probe"] = probe }, { __index = byId })
        local root, why = M.resolve(view, "\0probe", L.maxDepth)
        if not root then return false, why end
        for i = 1, 3 do
            if math.abs(root.pos[i]) > M.PLATFORM_OFFSET_M then return false, "outside_platform_reach" end
        end
        if math.sqrt(root.pos[1] ^ 2 + root.pos[2] ^ 2 + root.pos[3] ^ 2) > L.maxReachM then return false, "too_far_from_machine" end
        if (ctx.onMachine or 0) >= L.perParent then return false, "machine_full" end
        if (ctx.byPlayer or 0) >= L.perPlayer then return false, "player_limit" end
        if (ctx.total or 0) >= L.totalActive then return false, "server_limit" end
        return true, { pos = pos, rot = rot, root = root }
    end

    -- ------------------------------------------------------------------------------------------------- physics hook
    --- What a Machine's attachments WOULD contribute (not applied in 0.1.0): total mass, and every surface with its
    --- area and its axes in the root Machine's frame, so drag and lift can later be derived from geometry. `list` =
    --- attachments on one Machine; `byId` resolves chains.
    function M.physical(list, byId)
        local out = { massKg = 0, surfaces = {} }
        for _, a in ipairs(list) do
            local item = M.CATALOGUE[a.assetId]
            local root = item and M.resolve(byId, a.id)
            if root then
                out.massKg = out.massKg + item.massKg
                local m = M.matrix(root.rot)
                out.surfaces[#out.surfaces + 1] = { id = a.id, surface = item.surface, areaM2 = item.areaM2, at = root.pos,
                    forward = apply(m, { 0, 1, 0 }), up = apply(m, { 0, 0, 1 }) }
            end
        end
        return out
    end

    return M
end)
