-- ncm-core module: competition.affiliation
-- Doc 14's affiliation rules, for both circuits (doc 44 §10, migration 046).
--
-- One identity holds at most ONE active formal affiliation: Owner, Manager or Team Driver of a sanctioned
-- organization, or Manager of an NPC-circuit org (L224.8). Privateering and street activity are not affiliations
-- and stay free for everyone. An Owner cannot drive for any team (`owner_cannot_drive`) and cannot appoint
-- themselves Manager (`self_appointment`). On the NPC circuit the only human role is Manager.
-- The database enforces the one-active rule with a unique index; this module gives the reason a human reads.
local Core = NcmCore

Core.define("competition.affiliation", function()
    local M = { version = "0.1.0" }
    M.ROLES = { owner = true, manager = true, driver = true }
    M.CIRCUITS = { sanctioned = true, npc = true }

    --- Shape check for a proposed affiliation row.
    function M.validate(row)
        if type(row) ~= "table" then return false, "not_a_table" end
        if not M.CIRCUITS[row.circuit] then return false, "invalid_circuit" end
        if not M.ROLES[row.role] then return false, "invalid_role" end
        if type(row.driverId) ~= "string" or row.driverId == "" then return false, "driver_required" end
        if row.circuit == "sanctioned" then
            if not row.organizationId or row.paddockOrgId then return false, "sanctioned_needs_organization" end
        else
            if not row.paddockOrgId or row.organizationId then return false, "npc_needs_paddock_org" end
            if row.role ~= "manager" then return false, "npc_circuit_manager_only" end
        end
        return true
    end

    --- Can `driverId` take `proposed` given their current active affiliation (or nil)?
    function M.canAffiliate(active, proposed)
        local ok, why = M.validate(proposed)
        if not ok then return false, why end
        if active then return false, "one_team_rule" end
        return true
    end

    --- May this affiliation occupy a driver seat? Owners never drive (doc 14 IDEA-161).
    function M.canDrive(active)
        if active and active.role == "owner" then return false, "owner_cannot_drive" end
        if active and active.role == "manager" then return false, "role_exclusive" end
        return true
    end

    --- May `owner` appoint `targetDriverId` as Manager of their sanctioned organization?
    function M.canAppointManager(owner, targetDriverId, targetActive)
        if not owner or owner.role ~= "owner" then return false, "not_owner" end
        if owner.driverId == targetDriverId then return false, "self_appointment" end
        if targetActive then return false, "one_team_rule" end
        return true
    end

    return M
end)
