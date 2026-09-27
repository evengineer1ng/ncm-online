local C = NcmCore.get("player.communication")

return {
    ["normalizes the five attention levels"] = function(T)
        for name in pairs(C.PRIORITY) do
            local d = assert(C.normalize({ id="x", title="X", message="Y", priority=name }))
            T.eq(d.priority, name)
        end
    end,
    ["rejects a message with no player meaning"] = function(T)
        local d, why = C.normalize({ id="x", title="X" })
        T.eq(d, nil); T.eq(why, "missing_message")
    end,
    ["once delivers once"] = function(T)
        local d = { id="first", title="FIRST", message="Hello", repeatPolicy={mode="once"} }
        T.ok(C.decide(d, {}, 10).deliver)
        local no = C.decide(d, {shownCount=1,lastShownAt=10}, 20)
        T.falsy(no.deliver); T.eq(no.reason, "already_seen")
    end,
    ["cooldown prevents a noisy repeat"] = function(T)
        local d = { id="hint", title="HINT", message="Do it", repeatPolicy={mode="cooldown",cooldownSec=30} }
        T.falsy(C.decide(d, {shownCount=1,lastShownAt=10}, 39).deliver)
        T.ok(C.decide(d, {shownCount=1,lastShownAt=10}, 40).deliver)
    end,
    ["adaptive teaching becomes a compact confirmation"] = function(T)
        local d = { id="interest", title="ON THE LIST", firstMessage="Interest is not entry.", repeatMessage="Route set.", repeatPolicy={mode="adaptive"} }
        T.eq(C.decide(d, {}, 10).presentation.message, "Interest is not entry.")
        T.eq(C.decide(d, {shownCount=1}, 20).presentation.message, "Route set.")
    end,
    ["unacknowledged repetition can escalate one level"] = function(T)
        local d = { id="stuck", title="NEXT", message="Go", priority="actionable", repeatPolicy={mode="until_ack",escalateAfter=2} }
        T.eq(C.decide(d, {shownCount=2}, 20).presentation.priority, "time_sensitive")
        T.falsy(C.decide(d, {shownCount=2,acknowledgedAt=19}, 20).deliver)
    end,
    ["record and acknowledge preserve the exposure row"] = function(T)
        local x = C.record({shownCount=2, extra="keep"}, 44)
        T.eq(x.shownCount, 3); T.eq(x.lastShownAt, 44); T.eq(x.extra, "keep")
        local y = C.acknowledge(x, 50); T.eq(y.acknowledgedAt, 50); T.eq(y.shownCount, 3)
    end,
}
