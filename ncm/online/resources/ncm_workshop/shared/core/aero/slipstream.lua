-- ncm-core module: aero.slipstream
-- The Slipstream Module: 2077 technology that DETECTS and actively EXPLOITS another vehicle's wake (L356).
--
--   natural draft (aero.wake) + active vehicle technology = Slipstream
--
-- An Eddywright SL-1 is a physical component (engineering.installation: family "slipstream") bought on the Base
-- Market and installed in a Machine's electronics bay. It is never a race rule, a setting or a mode. Installed and
-- switched on, it:
--   * reads the same wake the physics already has (aero.wake quality q) -- it never invents one;
--   * ACQUIRES it progressively: a lock that builds while the car holds useful air and bleeds away when it does not;
--   * adds active drag relief on top of the natural share, in proportion to wake quality AND lock;
--   * talks to other SL-1s: a unit using a wake tells the wake's owner -- if, and only if, the owner carries one.
-- Switched off or removed: no lock, no assist, no HUD, no network. The natural draft stays (it is aero.wake's).
--
-- One model for humans and NPCs. A human's tow is a force (the client's Machine wrench lease); an NPC's is its AI
-- target speed (the server's `ai.setSpeed`), because a platform-driven car takes a speed, not a force. Both come
-- from `relief()` here.
local Core = NcmCore

Core.define("aero.slipstream", function(C)
    local M = { version = "0.1.0" }
    local Wake = C.get("aero.wake")
    local Hash = C.get("vocabulary.hash")

    local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end

    -- ---- the product ---------------------------------------------------------------------------------------------
    -- Eddywright: an original Night City maker of aero-electronics (eddy + wright, a maker of them). Enough identity
    -- for a maker with other products later; not lore.
    M.MAKER = { key = "eddywright", name = "Eddywright", line = "Aerotronics" }
    M.PRODUCT = { code = "EDW-SL1", name = "Slipstream SL-1", short = "SLIPSTREAM" }
    M.SLOGAN = "Let someone else break the air."
    M.DESIGN_ID = "eng:eddywright:sl1:r1"

    --- The boot ceremony: one line per step, spoken by the unit (audio/<id>.wav, rendered once offline) and drawn
    --- in ink as it speaks. Concise, corporate, sure of itself.
    M.BOOT = {
        { id = "sl1_boot_1", text = "Eddywright Slipstream. Installation verified.", hud = "INSTALLATION VERIFIED" },
        { id = "sl1_boot_2", text = "Wake acquisition is live. Close on a moving vehicle and hold its line. The cleaner your position, the harder this unit works.",
            hud = "WAKE ACQUISITION LIVE" },
        { id = "sl1_boot_3", text = "Slipstream units recognise one another. Take a wake, and its owner will know. When someone takes yours, so will you.",
            hud = "NETWORK PRESENT" },
        { id = "sl1_boot_4", text = "Eddywright. " .. M.SLOGAN, hud = M.SLOGAN:upper() },
    }

    -- ---- tunables ------------------------------------------------------------------------------------------------
    M.CONFIG = {
        moduleReliefMax = 0.30,  -- active relief on top of natural, at q = 1 and full lock (share of drag)
        detectQ = 0.06,          -- the unit reports a wake from here
        acquireQ = 0.20,         -- and builds lock from here
        lockPerS = 0.9,          -- lock gained per second at q = 1 (scaled by how far above acquireQ)
        bleedPerS = 1.4,         -- lock lost per second below acquireQ
        activeLock = 0.95,       -- lock at which the unit calls the wake ACTIVE
        lostHoldS = 1.5,         -- how long "lost" is shown after an active link breaks
        npcSpeedPerRelief = 0.16,-- NPC target speed gain per unit of total relief (0.45 relief -> +7%)
        npcSpeedCap = 1.08,      -- never more than this over the planned leg speed
        npcEquipShare = 0.35,    -- share of Paddock drivers whose teams run an SL-1 (deterministic per driver)
        npcCautiousAggression = 35, -- below this aggression an NPC will not hold a lock closer than...
        npcCautiousGapM = 9,     -- ...this gap
    }
    local function cfg(o) return o or M.CONFIG end

    -- ---- acquisition ---------------------------------------------------------------------------------------------
    M.PHASES = { "searching", "detected", "acquiring", "active", "lost" }

    function M.newState() return { phase = "searching", lock = 0, q = 0, leader = nil, lostLeft = 0, activeFor = 0 } end

    --- Advance one unit by dt seconds. `best` = aero.wake.best(...) result or nil; `enabled` = installed AND on.
    --- `policy` (optional, NPCs) = { refuseCloseM } -- a cautious driver will not hold a lock that close.
    --- Returns the state (mutated): { phase, lock, q, leader, changed (phase changed this step) }.
    function M.step(st, best, dt, enabled, o, policy)
        o = cfg(o)
        local before = st.phase
        if not enabled then
            st.phase, st.lock, st.q, st.leader, st.lostLeft, st.activeFor = "searching", 0, 0, nil, 0, 0
            st.changed = before ~= st.phase
            return st
        end
        local q = best and best.q or 0
        if policy and policy.refuseCloseM and best and best.geometry and best.geometry.ahead < policy.refuseCloseM then q = 0 end
        -- a lock belongs to one leader: changing leaders starts over
        if best and st.leader ~= nil and best.id ~= st.leader and st.lock > 0 then st.lock = 0 end
        if q >= o.acquireQ then
            local drive = (q - o.acquireQ) / (1 - o.acquireQ)
            st.lock = clamp(st.lock + o.lockPerS * (0.35 + 0.65 * drive) * dt, 0, 1)
            st.leader = best.id
        else
            st.lock = clamp(st.lock - o.bleedPerS * dt, 0, 1)
            if st.lock == 0 then st.leader = (q >= o.detectQ and best) and best.id or nil end
        end
        st.q = q
        local phase
        if st.lock >= o.activeLock and q >= o.acquireQ then phase = "active"
        elseif q >= o.acquireQ then phase = "acquiring"
        elseif before == "active" or (before == "lost" and st.lostLeft > 0) then phase = "lost"
        elseif q >= o.detectQ then phase = "detected"
        else phase = "searching" end
        if phase == "lost" then
            if before ~= "lost" then st.lostLeft = o.lostHoldS end
            st.lostLeft = st.lostLeft - dt
            if st.lostLeft <= 0 then phase = q >= o.detectQ and "detected" or "searching" end
        end
        st.activeFor = phase == "active" and (st.activeFor + dt) or 0
        st.phase = phase
        st.changed = before ~= phase
        return st
    end

    -- ---- the effect ----------------------------------------------------------------------------------------------
    --- Total share of drag shed: natural (always, from the wake) + the unit's active share (only when enabled).
    function M.relief(q, st, enabled, o, wo)
        o = cfg(o)
        local natural = Wake.naturalRelief(q, wo)
        local active = 0
        if enabled and st then active = o.moduleReliefMax * clamp(q or 0, 0, 1) * clamp(st.lock or 0, 0, 1) end
        return natural + active, natural, active
    end

    --- The tow as a force (N) along the follower's travel: relief x aerodynamic drag at its speed.
    function M.towN(relief, speed, wo, cdA)
        return clamp(relief or 0, 0, 0.95) * Wake.dragN(speed, wo, cdA)
    end

    --- An NPC's AI target-speed multiplier for a total relief (a platform car takes a speed, not a force).
    function M.npcSpeedFactor(relief, o)
        o = cfg(o)
        return math.min(o.npcSpeedCap, 1 + o.npcSpeedPerRelief * clamp(relief or 0, 0, 1))
    end

    --- Does this Paddock driver's team run an SL-1? Deterministic per (seed, person).
    function M.npcEquipped(seed, personId, o)
        return Hash.stream(seed or "", "slipstream", personId or "")() < cfg(o).npcEquipShare
    end

    --- How an NPC uses its unit. The extension point for driver traits (aggressive drivers holding wakes harder,
    --- teammates towing each other, qualifying tow timing). Today: a cautious driver refuses to hold a lock very
    --- close. `attrs` are paddock.attributes (never sent anywhere).
    function M.npcPolicy(attrs, o)
        o = cfg(o)
        local aggr = tonumber(attrs and attrs.aggression) or 50
        return { refuseCloseM = aggr < o.npcCautiousAggression and o.npcCautiousGapM or nil }
    end

    -- ---- the network ---------------------------------------------------------------------------------------------
    --- Who is told what when a unit holds a link on a leader. Only units see units: a leader without one never hears
    --- of it, and the follower then gets only its own acquisition, not the leader's identity.
    ---   followerActive : the follower's unit is enabled and its phase is "active"
    ---   leaderEquipped : the leader carries an enabled unit
    --- Returns { follower = "peer" | "plain" | nil, leader = "inbound" | nil }.
    function M.notices(followerActive, leaderEquipped)
        if not followerActive then return { follower = nil, leader = nil } end
        if leaderEquipped then return { follower = "peer", leader = "inbound" } end
        return { follower = "plain", leader = nil }
    end

    return M
end)
