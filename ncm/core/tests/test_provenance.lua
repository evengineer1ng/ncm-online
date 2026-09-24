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
