-- NCM 3.0: the front door -- the Tape Deck (L338, doc 55 §6), drawn by CET.
--
-- The deck talks to the simulation through a PORT, never to it directly:
--   remote port (the game): JSON over `NcmHost_Call` to the ncm_host plugin, where the NCM Host and the resources run
--   local port  (tests):    the same calls straight onto an App
-- port interface: deck() -> { tapes = { rows }, doc, mounted }; newTape(); setDoc(k, v); dev(action, arg) -> ok, why;
--   garage() -> { mine, claimable, current, ordinal }; claim(record, appearance) -> ok, why;
--   aero(action, arg) -> { ok, aero = tower snapshot | false, machines, devMode } (L339, ncm_aero)
-- What exists in Cyberpunk, honestly (§6): no hook in the game's own main menu; the deck is a CET window, on screen at
-- the main menu and again when a save loads, BEFORE any NCM world runs. Nothing of NCM runs until a choice.
-- CET's ImGui notes (live 2026-10-07): Selectable returns "is selected" every frame -- rows are Buttons; the cursor is
-- hidden while the pad is the active input -- the pad drives `sel` (init.lua).
local M = {}

local WHY = {
    "NIGHT CITY MOTORSPORTS runs on Race Weeks.",
    "",
    "Race Week follows real time, including while you're away.",
    "Events, competition and Night City change as the Week develops.",
    "",
    "When Race Week ends, competition regenerates around a new seed",
    "and your machines return to Night City.",
    "",
    "Some things you learn and build may persist.",
}
M.WHY = WHY

--- A port straight onto an App (headless tests).
function M.localPort(app)
    local p = {}
    function p.deck()
        local rows = {}
        for _, r in ipairs(app:tapes()) do
            local t, pr = r.tape, r.present
            rows[#rows + 1] = { id = t.id, ordinal = t.ordinal, label = pr and pr.label or "RW ??",
                remaining = pr and app.Tapes.remaining(pr) or "", place = t.cache and t.cache.place or "surface",
                machine = t.cache and t.cache.machine and t.cache.machine.label or nil, ago = r.ago, devAltered = t.devAltered }
        end
        local d = app.store.doc
        return { tapes = rows, doc = { firstRunSeen = d.firstRunSeen, devMode = d.devMode, recovered = d.recovered,
            devSkewH = (tonumber(d.devSkew) or 0) / 3600 }, mounted = app.tape and app.tape.id or nil }
    end
    function p.newTape() local t = app:newTape(); return { id = t.id, ordinal = t.ordinal } end
    function p.setDoc(k, v) app.store.doc[k] = v; app.store:save() end
    function p.dev(a, arg) return app:dev(a, arg) end
    function p.garage()
        return { mine = app:garage(), claimable = app:claimable(), ordinal = app.tape and app.tape.ordinal,
            current = app.world and app.world.world.player.gameVehicle or nil }
    end
    function p.claim(rec, appearance) return app:claim(rec, appearance) end
    function p.aero(action, arg)
        local snap, why = app:aeroCmd(action, arg)
        if snap == nil then return { ok = false, error = tostring(why) } end
        local mine = {}
        for _, m in ipairs(app:garage()) do if m.vehicleKey then mine[#mine + 1] = { vehicleKey = m.vehicleKey, record = m.record } end end
        return { ok = true, aero = snap, machines = mine, devMode = app.store.doc.devMode }
    end
    return p
end

function M.new(port)
    local d = { port = port, open = true, mode = "deck", sel = 1, choice = nil, status = nil, cache = nil, cacheAt = -1,
        garageCache = nil, garageAt = -1, hud = nil, lastClaim = nil, aeroCache = nil, aeroAt = -1, aeroPick = 1 }

    local function now() return os.clock() end
    function d.refresh(force)
        if force or not d.cache or now() - d.cacheAt > 1.0 then
            local ok, v = pcall(port.deck)
            if ok and type(v) == "table" then d.cache, d.cacheAt = v, now() end
        end
        return d.cache or { tapes = {}, doc = {} }
    end

    --- Rows the deck shows, in order: every tape, then NEW TAPE, then WITHOUT NCM.
    function d.rows()
        local out = {}
        for _, t in ipairs(d.refresh().tapes or {}) do
            out[#out + 1] = { kind = "tape", tape = t,
                text = string.format("TAPE %02d   %s   %s", t.ordinal or 0, t.label or "RW ??", t.place == "deep" and "DEEP" or "NIGHT CITY"),
                sub = string.format("%s%sLast active: %s%s", t.machine and (t.machine .. "  ·  ") or "",
                    (t.remaining and t.remaining ~= "") and (t.remaining .. "  ·  ") or "", t.ago or "?", t.devAltered and "  ·  DEV" or "") }
        end
        out[#out + 1] = { kind = "new", text = "+ NEW TAPE", sub = "A new, independent continuity. Begins at RW 01 · D1." }
        out[#out + 1] = { kind = "without", text = "CYBERPUNK WITHOUT NCM", sub = "Play this session with NCM dormant. Nothing of NCM runs." }
        return out
    end

    function d.move(delta)
        local n = #d.rows()
        d.sel = ((d.sel - 1 + delta) % n) + 1
    end

    --- Choose the selected row (pad A / click). Returns the action taken.
    function d.choose(row)
        row = row or d.rows()[d.sel]
        if not row then return end
        if d.mode == "intro" then
            local t = port.newTape()
            port.setDoc("firstRunSeen", true)
            d.refresh(true)
            d.choice = { kind = "tape", id = t.id }
            d.mode = "deck"
            d.status = string.format("TAPE %02d created: BEGIN RW 01 · D1", t.ordinal or 0)
            return "new"
        end
        if row.kind == "tape" then d.choice = { kind = "tape", id = row.tape.id }
        elseif row.kind == "without" then d.choice = { kind = "without" }
        elseif row.kind == "new" then
            if not d.refresh().doc.firstRunSeen then d.mode = "intro"; return "intro" end
            local t = port.newTape()
            d.refresh(true)
            d.choice = { kind = "tape", id = t.id }
        end
        return d.choice and d.choice.kind
    end

    function d.claim(record, appearance)
        local ok, why = port.claim(record, appearance)
        d.status = ok and ("claiming " .. tostring(why or record) .. " ...") or ("claim: " .. tostring(why))
        d.garageAt = -1
        return ok, why
    end

    local function text(s) ImGui.Text(tostring(s or "")) end
    local function dim(s) ImGui.TextDisabled(tostring(s or "")) end

    function d.draw(interactive, inSession, mounted)
        if not d.open then return end
        ImGui.SetNextWindowSize(640, 0, ImGuiCond.Always)
        ImGui.SetNextWindowPos(80, 120, ImGuiCond.FirstUseEver)
        local flags = ImGuiWindowFlags.NoCollapse + ImGuiWindowFlags.AlwaysAutoResize
        if ImGui.Begin("NIGHT CITY MOTORSPORTS##ncm_deck", flags) then
            if d.mode == "intro" then
                for _, l in ipairs(WHY) do if l == "" then ImGui.Spacing() else text(l) end end
                ImGui.Spacing(); ImGui.Separator(); ImGui.Spacing()
                if ImGui.Button("BEGIN RW 01 · D1", 260, 34) then d.choose() end
                ImGui.SameLine()
                if ImGui.Button("Back", 90, 34) then d.mode = "deck" end
                if not interactive then dim("A to begin  ·  B to go back") end
            else
                if mounted then
                    d.drawGarage(); ImGui.Spacing(); ImGui.Separator(); ImGui.Spacing()
                    if port.aero then d.drawAero(); ImGui.Spacing(); ImGui.Separator(); ImGui.Spacing() end
                end
                if not inSession then dim("Choose the continuity you will enter. It mounts when your save finishes loading.") end
                if inSession and not mounted and not d.choice then dim("NCM is waiting. Nothing of NCM runs until you choose.") end
                ImGui.Spacing()
                for i, row in ipairs(d.rows()) do
                    local selected = (i == d.sel)
                    if row.kind ~= "tape" and i > 1 then ImGui.Spacing() end
                    if ImGui.Button(((selected and "> " or "   ") .. row.text) .. "##row" .. i, 600, 0) then d.sel = i; d.choose(row) end
                    dim("    " .. row.sub)
                end
                local doc = d.refresh().doc or {}
                if doc.recovered then ImGui.Spacing(); dim("Tape index " .. tostring(doc.recovered)) end
                if d.status then ImGui.Spacing(); text(d.status) end
                if not interactive then ImGui.Spacing(); dim("D-pad to choose  ·  A to enter  ·  (or open the CET overlay and use the mouse)") end
                ImGui.Spacing(); ImGui.Separator()
                local nv, changed = ImGui.Checkbox("Developer mode (Time Lab)", doc.devMode and true or false)
                if changed then port.setDoc("devMode", nv); d.refresh(true) end
                if doc.devMode then d.drawLab(doc) end
            end
        end
        ImGui.End()
    end

    --- GARAGE (L338): claim a car into THIS tape -- the one you are sitting in, or any registered livery.
    function d.drawGarage()
        if not d.garageCache or now() - d.garageAt > 1.0 then
            local ok, g = pcall(port.garage)
            if ok and type(g) == "table" then d.garageCache, d.garageAt = g, now() end
        end
        local g = d.garageCache or {}
        text(("GARAGE  ·  TAPE %02d"):format(tonumber(g.ordinal) or 0))
        local byRecord = {}
        for _, m in ipairs(g.mine or {}) do byRecord[m.record] = m end
        local cur = g.current
        if type(cur) == "table" and cur.record then
            local mine = byRecord[cur.record]
            dim(("You are in: %s%s"):format(cur.record, cur.appearance and ("  [" .. cur.appearance .. "]") or ""))
            if mine then dim("    yours" .. (mine.serial and ("  ·  " .. mine.serial) or "  (no serial: not a catalogue model)"))
            elseif ImGui.Button("CLAIM THIS CAR") then d.claim(cur.record, cur.appearance) end
        else
            dim("Get in any car to claim it -- or claim a livery below.")
        end
        ImGui.Spacing()
        for i, c in ipairs(g.claimable or {}) do
            local mine = byRecord[c.record]
            if mine then dim(("  %-28s yours  %s"):format(c.label, mine.serial or ""))
            elseif ImGui.Button(("Claim %s##claim%d"):format(c.label, i)) then d.claim(c.record) end
        end
        local lc = d.lastClaim
        if type(lc) == "table" and lc.state and lc.state ~= "pending" then
            text(lc.assetId and (("Claimed %s%s -- call it from the vehicle menu."):format(lc.record, lc.serial and ("  " .. lc.serial) or ""))
                or ("Claim failed: " .. tostring(lc.state)))
        end
    end

    --- AEROSPACE RACE (L339, ncm_aero): a field of one of YOUR machines, Night City -> Deep -> Hill Abode, and its tower.
    function d.aero(action, arg)
        local ok, r = pcall(port.aero, action, arg)
        if ok and type(r) == "table" then
            if r.ok then d.aeroCache, d.aeroAt = r, now() elseif action then d.status = "aerospace: " .. tostring(r.error) end
        end
        return d.aeroCache
    end

    function d.drawAero()
        if not d.aeroCache or now() - d.aeroAt > 0.5 then d.aero() end
        local r = d.aeroCache or {}
        local a = type(r.aero) == "table" and r.aero or nil
        text("AEROSPACE RACE  ·  experimental")
        if a and a.tower then
            dim(("%s -> %s -> Deep -> %s  ·  %.0f km  ·  %s  ·  t %s%s"):format(tostring(a.names and a.names.start), tostring(a.names and a.names.via),
                tostring(a.names and a.names.finish), tonumber(a.lengthKm) or 0, tostring(a.machine),
                a.t and ("%d:%02d"):format(math.floor(math.max(0, a.t) / 60), math.floor(math.max(0, a.t) % 60)) or "-",
                a.dev and ("  ·  DEV x" .. tostring(a.rate)) or ""))
            for _, o in ipairs(a.tower) do
                local gap = o.position == 1 and "LEADER" or (o.raceS and o.gapS and ("+%.1fs"):format(o.gapS))
                    or (o.gapKm and ("+%.1fkm"):format(o.gapKm)) or ""
                local state = o.status == "finished" and (o.raceS and ("%.1fs"):format(o.raceS) or "FIN")
                    or (o.status == "racing" and o.leg or ("DNF " .. tostring(o.reason or "")))
                text(("P%-2d %-10s %-13s %-14s %-10s %7.1f km %6.0f m/s"):format(o.position, tostring(o.name), tostring(o.livery or ""),
                    tostring(state), gap, tonumber(o.altKm) or 0, tonumber(o.speed) or 0))
            end
            for _, f in ipairs(a.facts or {}) do
                dim(("Race Week heard it: %s  (%s, %s)"):format(tostring(f.kind), table.concat(f.ids or {}, ", "), tostring(f.leg)))
            end
            if a.running then
                if ImGui.Button("Stop the race") then d.aero("stop") end
                if r.devMode then
                    for _, x in ipairs({ 1, 10, 60 }) do
                        ImGui.SameLine()
                        if ImGui.Button(("x%d##aerorate%d"):format(x, x)) then d.aero("rate", x) end
                    end
                    ImGui.SameLine(); dim("(DEV: race time faster than wall time)")
                end
                return
            end
            if a.done then dim("Race over.") end
        end
        local ms = r.machines or {}
        if #ms == 0 then dim("Claim a machine into this tape first: the field is built from one of your own."); return end
        if d.aeroPick > #ms then d.aeroPick = 1 end
        local m = ms[d.aeroPick]
        if ImGui.Button(("Machine: %s##aeropick"):format(tostring(m.vehicleKey))) then d.aeroPick = d.aeroPick % #ms + 1 end
        ImGui.SameLine()
        if ImGui.Button("Start an aerospace race (12, Deep turn at 120 km)") then
            d.aero("start", { vehicleKey = m.vehicleKey, size = 12, turnAltM = 120000 })
        end
        dim("A field of your machine, flown by NPCs on its real physics. The tower follows them all the way.")
    end

    function d.drawLab(doc)
        ImGui.Spacing()
        dim("TIME LAB -- tests the temporal system without waiting for it. Every use marks the tape DEV.")
        local function btn(label, action, arg)
            if ImGui.Button(label) then
                local ok, why = port.dev(action, arg)
                d.status = ok and ("dev: " .. label) or ("dev " .. label .. ": " .. tostring(why))
                d.refresh(true)
            end
        end
        btn("+1 hour", "hour"); ImGui.SameLine(); btn("+1 day", "day"); ImGui.SameLine()
        btn("To 60 s before the end", "near_end"); ImGui.SameLine(); btn("Cross the rollover", "cross")
        btn("Skip 1 Week", "skip_weeks", 1); ImGui.SameLine(); btn("Skip 4 Weeks", "skip_weeks", 4); ImGui.SameLine()
        btn("Age tape 30 days", "age_tape", 30)
        btn("Strand machine in Deep (tape at rest)", "strand_deep"); ImGui.SameLine(); btn("Reset dev clock", "reset_skew")
        dim(("dev clock skew: %.0f h"):format(tonumber(doc.devSkewH) or 0))
    end

    --- The always-on Race Week line (top right) while a tape is mounted, from the last tick's `hud`.
    function d.drawHud()
        local h = d.hud
        if type(h) ~= "table" or not h.label then return end
        local okR, sw = pcall(function() return GetDisplayResolution() end)
        ImGui.SetNextWindowPos((okR and tonumber(sw)) and (sw - 470) or 1400, 18, ImGuiCond.Always)
        ImGui.SetNextWindowBgAlpha(0.35)
        local flags = ImGuiWindowFlags.NoDecoration + ImGuiWindowFlags.AlwaysAutoResize + ImGuiWindowFlags.NoInputs +
            ImGuiWindowFlags.NoSavedSettings + ImGuiWindowFlags.NoFocusOnAppearing + ImGuiWindowFlags.NoNav
        if ImGui.Begin("##ncm_rw_line", flags) then
            text(("TAPE %02d  ·  %s"):format(tonumber(h.ordinal) or 0, h.label))
            dim(h.remaining or "")
            if type(h.lastReturn) == "table" and d.returnShownUntil and now() < d.returnShownUntil then
                text(("While you were away: %d Race Week rollover(s). Your machines are in Night City."):format(tonumber(h.lastReturn.rolled) or 0))
            end
        end
        ImGui.End()
    end

    return d
end

return M
