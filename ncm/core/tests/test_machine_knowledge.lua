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

    ["a measurement of zero survives and an unreadable one never becomes zero"] = function(T)
        local M = T.Core.get("competition.machine_knowledge")
        -- The whole point: a parked car genuinely reading 0 km/h is real evidence.
        T.eq(M.reading(0), 0)
        T.eq(M.reading(0.0), 0)
        T.eq(M.reading("128.4"), 128.4)
        -- Absence must stay absent. `tonumber(x) or 0` is exactly what this replaces.
        T.eq(M.reading(nil), nil)
        T.eq(M.reading("not a number"), nil)
        T.eq(M.reading({}), nil)
        T.eq(M.reading(0 / 0), nil)
        T.eq(M.reading(math.huge), nil)
        T.eq(M.reading(-math.huge), nil)
    end,

    ["an unreadable field is omitted from a measurement set rather than defaulted"] = function(T)
        local M = T.Core.get("competition.machine_knowledge")
        local out, n = M.measurements({ speed = 0, throttle = nil, brake = "0.5", steering = 0 / 0 })
        T.eq(n, 2)
        T.eq(out.speed, 0)
        T.eq(out.brake, 0.5)
        T.eq(out.throttle, nil)
        T.eq(out.steering, nil)
        -- Nothing readable is a legitimate answer, and means write no numeric observation at all.
        local _, none = M.measurements(nil)
        T.eq(none, 0)
    end,

    ["server measurement and client attestation are different facts"] = function(T)
        local M = T.Core.get("competition.machine_knowledge")
        local base = { driverId = "d", vehicleKey = "k", evidenceKey = "e", kind = "identity_reveal",
            source = "world_encounter", observedAt = 1 }
        local function with(k, v)
            local f = {}; for a, b in pairs(base) do f[a] = b end; f[k] = v
            return M.evidence(f)
        end
        T.eq(with("basis", "server_measured").basis, "server_measured")
        T.eq(with("basis", "client_attested").basis, "client_attested")
        T.eq(with("basis", "derived_mixed").basis, "derived_mixed")
        -- Unknown stays unknown: every row written before BASIS existed has no basis.
        T.eq(M.evidence(base).basis, nil)
        local row, why = with("basis", "trust_me")
        T.eq(row, nil); T.eq(why, "unknown_basis:trust_me")
    end,

    ["a configuration reference is refused until the substrate it names exists"] = function(T)
        local M = T.Core.get("competition.machine_knowledge")
        -- 31_CAPABILITY_AUDIT.md section 6: build 2.31 has no component objects at all, so this can only ever
        -- point at an NCM-authored record -- and that record does not exist yet.
        T.eq(M.configurationRef(nil), nil)
        local _, why = M.configurationRef("cfg-1")
        T.eq(why, "configuration_substrate_absent")
        local row, why2 = M.evidence({ driverId = "d", vehicleKey = "k", evidenceKey = "e",
            kind = "identity_reveal", source = "world_encounter", observedAt = 1,
            configurationRef = "cfg-1" })
        T.eq(row, nil); T.eq(why2, "configuration_substrate_absent")
    end,
}
