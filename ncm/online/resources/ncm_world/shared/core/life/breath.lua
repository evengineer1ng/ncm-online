-- ncm-core module: life.breath
--
-- Staying alive above the air (L323; doc 54 §S). Snowglobe's compressed atmosphere thins fast (scale height ~1.2 km on
-- a 5 km Earth), so a person needs AIR: breathable outside air, a SEALED cabin with oxygen in it, or a suit. Without
-- any of them, consciousness falls -- in seconds in vacuum, in minutes in thin air -- then blackout, then death. Real
-- breathing rates; named consequences, never a flag.
--   air(rho, ctx)        which source a person is breathing from: "outside" | "cabin" | "suit" | nil
--   step(st, ctx, dt)    one person's oxygen and consciousness; returns an event when their state changes
-- ctx = { rho, cabin = { sealed, o2 = { kg } } | nil, suit = { o2Kg } | nil, exertion = 1..2 }
local Core = NcmCore

Core.define("life.breath", function(C)
    local M = { version = "0.1.0" }

    M.BREATHABLE_RHO = 0.35       -- kg/m^3: below this, outside air no longer sustains a conscious adult
    M.O2_PER_S = 1.0e-5           -- kg/s of O2 at rest (about 0.85 kg a day); exertion multiplies it
    M.VACUUM_TUC_S = 15           -- time of useful consciousness with no air at all
    M.THIN_TUC_S = 300            -- ... just below the breathable line
    M.DEATH_AFTER_S = 120         -- unconscious without air this long: dead
    M.RECOVER_S = 10              -- back to full consciousness on good air

    function M.newState(suitO2Kg) return { suitO2 = suitO2Kg or 0, conscious = 1, outS = 0, status = "ok" } end

    --- Time of useful consciousness at density rho with no supplied oxygen.
    function M.tuc(rho)
        local f = math.max(0, math.min(1, (rho or 0) / M.BREATHABLE_RHO))
        return M.VACUUM_TUC_S + (M.THIN_TUC_S - M.VACUUM_TUC_S) * f * f
    end

    function M.air(rho, ctx)
        ctx = ctx or {}
        if (rho or 0) >= M.BREATHABLE_RHO then return "outside" end
        local cab = ctx.cabin
        if cab and cab.sealed and cab.o2 and cab.o2.kg > 0 then return "cabin" end
        if ctx.suitO2 and ctx.suitO2 > 0 then return "suit" end
        return nil
    end

    function M.step(st, ctx, dt)
        if st.status == "dead" then return nil end
        local rate = M.O2_PER_S * (ctx.exertion or 1)
        local src = M.air(ctx.rho, { cabin = ctx.cabin, suitO2 = (ctx.suit and st.suitO2) or 0 })
        local before = st.status
        st.source = src
        if src then
            if src == "cabin" then ctx.cabin.o2.kg = math.max(0, ctx.cabin.o2.kg - rate * dt)
            elseif src == "suit" then st.suitO2 = math.max(0, st.suitO2 - rate * dt) end
            st.outS = 0
            if st.status ~= "blackout" or st.conscious > 0.2 then
                st.conscious = math.min(1, st.conscious + dt / M.RECOVER_S)
                if st.conscious > 0.2 then st.status = st.conscious >= 0.999 and "ok" or "recovering" end
            else
                st.conscious = math.min(1, st.conscious + dt / M.RECOVER_S)
            end
        else
            st.outS = st.outS + dt
            st.conscious = math.max(0, st.conscious - dt / M.tuc(ctx.rho))
            if st.conscious <= 0 then
                st.status = "blackout"
                if st.outS >= M.tuc(ctx.rho) + M.DEATH_AFTER_S then st.status = "dead" end
            else
                st.status = "hypoxic"
            end
        end
        if st.status ~= before then return { status = st.status, source = src } end
        return nil
    end

    --- Seconds of breathing a supply holds for `people` at `exertion`.
    function M.endurance(o2Kg, people, exertion)
        return (o2Kg or 0) / (M.O2_PER_S * (exertion or 1) * math.max(1, people or 1))
    end

    return M
end)
