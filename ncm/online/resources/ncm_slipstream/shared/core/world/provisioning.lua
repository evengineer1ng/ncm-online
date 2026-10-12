-- ncm-core module: world.provisioning
-- Vehicle provisioning rules (decision record L13, P3). A ruleset names a provisioning model; this
-- module turns a request into an issue decision. Pure: the host spawns the car and applies effects.
local Core = NcmCore

Core.define("world.provisioning", function(C)
    local M = { version = "0.0.1" }
    local pool = C.get("data.vehicle_pool")
    local ids = C.get("vocabulary.ids")

    M.Model = C.get("vocabulary.provenance").enum("provisioningModel", { "issued", "loaner", "owned", "byo" })

    --- Pick a pool record for an `issued` vehicle.
    --- request: { class = "Sport", maxPrestige = 3?, rng = fn } -> decision { model="issued", record, class, prestige, cost=0 } or nil, reason
    function M.issue(request)
        if type(request) ~= "table" then return nil, "invalid_request" end
        if not pool.isClass(request.class) then return nil, "unknown_class" end
        if type(request.rng) ~= "function" then return nil, "rng_required" end
        local candidates = pool.records(request.class, request.maxPrestige)
        if #candidates == 0 then return nil, "no_eligible_record" end
        local index = math.floor(request.rng() * #candidates) + 1
        if index > #candidates then index = #candidates end
        local pick = candidates[index]
        return {
            issueId = ids.uuid4(request.rng),
            model = "issued",
            class = request.class,
            record = pick.id,
            prestige = pick.prestige,
            tags = pick.tags,
            cost = 0, -- L21: money-free first world; the ledger line exists with amount zero
        }
    end

    --- Candidate records to try when spawning a pool record for a player, best first.
    --- Mod records (pool tag "mod", e.g. the RB15 and its liveries) have no `_player` variant and the
    --- host cannot tell a missing record from a refused one (create succeeds, nothing renders): exact only.
    function M.spawnCandidates(record)
        if type(record) ~= "string" then return {} end
        if record:sub(-7) == "_player" then return { record } end
        if record:find("^Vehicle%.v_sport1_rb15_f1") then return { record } end
        return { record .. "_player", record }
    end

    return M
end)
