return {
    ["identity evidence preserves model and optional asset identity"] = function(T)
        local M = T.Core.get("competition.machine_knowledge")
        local row = M.evidence({ driverId = "driver", vehicleKey = "rayfield_caliburn",
            assetId = "asset", evidenceKey = "identity:rayfield_caliburn", kind = "identity_reveal",
            source = "world_encounter", epistemic = "observed", observedAt = 123 })
        T.eq(row.vehicleKey, "rayfield_caliburn")
        T.eq(row.assetId, "asset")
        T.eq(row.observedAt, 123)
    end,

    ["market identity reveal is legitimate knowledge but never human credit"] = function(T)
        local M = T.Core.get("competition.machine_knowledge")
        for _, source in ipairs({ "primary_market", "secondary_listing" }) do
            local row, why = M.evidence({ driverId = "driver", vehicleKey = "makigai_maimai",
                evidenceKey = "identity:makigai_maimai", kind = "identity_reveal",
                source = source, epistemic = "published", observedAt = 123 })
            T.eq(row ~= nil, true, why)
            T.eq(M.allowsHumanDiscoveryCredit(source), false)
        end
        T.eq(M.allowsHumanDiscoveryCredit("world_encounter"), true)
    end,

    ["unknown and fake precision remain absent rather than fabricated"] = function(T)
        local M = T.Core.get("competition.machine_knowledge")
        local row, why = M.evidence({ driverId = "driver", vehicleKey = "unknown",
            evidenceKey = "x", kind = "estimated_top_speed", source = "world_encounter", observedAt = 123 })
        T.eq(row, nil)
        T.eq(why, "unknown_kind:estimated_top_speed")
    end,

    ["retry identity is mandatory and bounded"] = function(T)
        local M = T.Core.get("competition.machine_knowledge")
        local base = { driverId = "driver", vehicleKey = "k", kind = "identity_reveal",
            source = "primary_market", observedAt = 1 }
        local row, why = M.evidence(base)
        T.eq(row, nil); T.eq(why, "bad_evidence_key")
        base.evidenceKey = string.rep("x", 191)
        row, why = M.evidence(base)
        T.eq(row, nil); T.eq(why, "bad_evidence_key")
    end,
}
