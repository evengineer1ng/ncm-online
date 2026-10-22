return {
    enums_are_closed = function(T)
        local P = T.Core.get("vocabulary.provenance")
        T.ok(P.Provenance.is("physical")); T.ok(P.Provenance.is("disconnected"))
        T.ok(not P.Provenance.is("ghost"), "unknown provenance rejected")
        T.eq(P.Provenance.PHYSICAL, "physical", "constant")
        T.eq(#P.Topology.values, 3)
        T.ok(P.Topology.is("controlled_world"))
        T.ok(P.Backend.is("simulatedAI") and P.Backend.SIMULATEDAI == "simulatedAI")
        T.ok(P.EventClass.is("impromptu"))
        T.ok(P.SessionKind.is("qualifying_shared") and P.SessionKind.is("leg"))
        T.ok(P.EntryState.is("suspended") and P.EntryState.is("substituted"), "continuity states exist (L20)")
        T.ok(P.EntryState.is("checked_in"), "venue check-in state exists (L35, P21)")
        T.errors(function() P.EntryState.assert("parked") end, "entryState: invalid value")
    end,

    context_online_requires_server = function(T)
        local P = T.Core.get("vocabulary.provenance")
        local ok, why = P.validateContext({ origin = "online", sessionKind = "race", sanctioned = false })
        T.eq(ok, false); T.eq(why, "online_context_requires_server_id")
        ok = P.validateContext({ origin = "online", serverId = "ncm-ref", sessionKind = "race", sanctioned = true })
        T.eq(ok, true)
    end,

    context_sp_must_not_name_server = function(T)
        local P = T.Core.get("vocabulary.provenance")
        local ok, why = P.validateContext({ origin = "sp", serverId = "ncm-ref", sessionKind = "race", sanctioned = false })
        T.eq(ok, false); T.eq(why, "sp_context_must_not_name_server")
        ok = P.validateContext({ origin = "sp", sessionKind = "qualifying_solo", sanctioned = false, category = "quick_race" })
        T.eq(ok, true)
    end,

    context_rejects_shape_errors = function(T)
        local P = T.Core.get("vocabulary.provenance")
        local _, why = P.validateContext(nil); T.eq(why, "context_not_a_table")
        _, why = P.validateContext({ origin = "lan", sessionKind = "race", sanctioned = false }); T.eq(why, "invalid_origin")
        _, why = P.validateContext({ origin = "sp", sessionKind = "warmup", sanctioned = false }); T.eq(why, "invalid_session_kind")
        _, why = P.validateContext({ origin = "sp", sessionKind = "race", sanctioned = "yes" }); T.eq(why, "sanctioned_not_boolean")
        _, why = P.validateContext({ origin = "sp", sessionKind = "race", sanctioned = true, category = "Bad Cat" }); T.eq(why, "invalid_category")
    end,

    owner_principal = function(T)
        local P = T.Core.get("vocabulary.provenance")
        T.eq(P.PrincipalKind.is("driver"), true)
        T.eq(P.PrincipalKind.is("organization"), true)
        T.eq(P.PrincipalKind.is("team"), false, "the vocabulary is closed; 'organization' is the word")

        -- Unowned is legitimate: unsold market stock has no owner, and that must stay expressible.
        T.eq(P.validatePrincipal(nil), true, "nil means unowned")
        T.eq(P.validatePrincipal({}), true, "empty means unowned")

        T.eq(P.validatePrincipal({ kind = "driver", id = "11111111-1111-4111-8111-111111111111" }), true)
        T.eq(P.validatePrincipal({ kind = "organization", id = "ncx_rayfield" }), true,
             "a team holds title the same way a driver does -- one model, not two")

        local ok, why = P.validatePrincipal({ kind = "driver" })
        T.eq(ok, false); T.eq(why, "principal_without_id")
        ok, why = P.validatePrincipal({ kind = "syndicate", id = "x" })
        T.eq(ok, false); T.eq(why, "invalid_principal_kind")
    end,

    machine_attribution = function(T)
        local P = T.Core.get("vocabulary.provenance")
        local id = "10000000-0000-4000-8000-000000000001"

        T.eq(P.AttributionBasis.is("recorded"), true)
        T.eq(P.AttributionBasis.is("guessed"), false, "the vocabulary is closed")

        -- A recorded attribution claims we wrote it down at the time. Without an asset that is a lie.
        local ok, why = P.validateAttribution({ basis = "recorded" })
        T.eq(ok, false); T.eq(why, "recorded_without_asset")
        T.eq(P.validateAttribution({ basis = "recorded", assetId = id }), true)

        -- A derived attribution must name the rule that produced it, so a later standard of evidence can
        -- supersede it without rewriting what this one concluded (L124 A4).
        ok, why = P.validateAttribution({ basis = "derived", assetId = id })
        T.eq(ok, false); T.eq(why, "derived_without_rule")
        T.eq(P.validateAttribution({ basis = "derived", assetId = id, rule = "exclusive_ownership_v1" }), true)

        -- Unknown means unknown. Carrying an assetId alongside it is incoherent.
        ok, why = P.validateAttribution({ basis = "unknown", assetId = id })
        T.eq(ok, false); T.eq(why, "unknown_with_asset")
        T.eq(P.validateAttribution({ basis = "unknown" }), true)

        -- There is no machine-source vocabulary: a team car is a car (L126). Only WHICH and HOW-WELL-KNOWN.
        T.eq(P.MachineSource, nil, "classifying machines by who uses them is the species distinction L123 forbids")
    end,

    registry_behaviour = function(T)
        local Core = T.Core
        T.ok(Core.has("vocabulary.ids") and Core.has("vocabulary.provenance"))
        T.errors(function() Core.get("nope.missing") end, "unknown module")
        T.errors(function() Core.define("vocabulary.ids", function() return {} end) end, "already defined")
        local same = Core.get("vocabulary.ids")
        T.eq(same, Core.get("vocabulary.ids"), "singleton per registry")
        T.eq(same.__name, "vocabulary.ids")
    end,
}
