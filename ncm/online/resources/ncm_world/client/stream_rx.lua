-- ncm_world / client / stream_rx -- the receiving half of `ncm_league/server/stream.lua`, shared.
--
-- WHY THIS FILE EXISTS. `client/panel.lua` has carried a private `receiveStream` since `IDEA-595`, and it works.
-- But it is a local in a file that loads LAST, so the Street Call builder -- which loads before it and needs the
-- same transport for the same reason -- could not reach it. The choice was to duplicate thirty lines or to lift
-- them. `stream.lua`'s own header argues the point already: the fix for a payload that vanishes at an unmeasured
-- ceiling is **one bounded transport**, not a per-payload workaround, and one transport with two receivers is
-- half a transport.
--
-- `panel.lua` is deliberately NOT converted in the same change (`IDEA-668`). It is the busiest surface in NCM and
-- it has live PASSes against its current code; converging it is a refactor that deserves its own gate run, not a
-- passenger on a bug fix. This file is written so that conversion is a deletion.
--
-- A PARTIAL STREAM IS NEVER HANDED ON. `onComplete` fires once, with every row present. A form drawn with rows
-- missing and no way to tell is worse than one that has not drawn yet -- and for the builder specifically, a
-- node list with holes in it is a list of places the server will then refuse.
NcmStreamRx = {}

local Chunks = NcmCore.get("vocabulary.chunks")

local function log(fmt, ...) print(("[ncm_world/stream] " .. fmt):format(...)) end

--- Listen on `channel` for the head/part pair `NcmStream.send` emits, and call `onComplete(value)` once the
--- whole list has arrived. `value` is the head with `[listKey]` filled in and `loading` cleared.
---
--- Registers its two net events immediately, so callers must call this at file scope rather than on demand:
--- a stream that begins before its receiver exists is a stream that is silently lost.
function NcmStreamRx.receive(channel, listKey, onComplete)
    local wire = nil

    local function finish()
        if not wire or not Chunks.complete(wire.rx) then return end
        local rows, why = Chunks.collect(wire.rx)
        if not rows then
            log("%s stream %s refused at assembly: %s", channel, tostring(wire.id), tostring(why))
            wire = nil
            return
        end
        local value = wire.head
        value[listKey] = rows
        value.loading = false
        log("%s stream complete id=%s %s=%d", channel, tostring(wire.id), listKey, #rows)
        wire = nil
        onComplete(value)
    end

    RegisterNetEvent(channel .. ".stream.begin", function(meta)
        if type(meta) ~= "table" or type(meta.id) ~= "string" then return end
        local head = type(meta.head) == "table" and meta.head or {}
        head[listKey] = {}
        head.loading = true
        wire = { id = meta.id, head = head, rx = Chunks.receiver(tonumber(meta.parts) or 0) }
        log("%s stream begin id=%s packets=%d %s=%s", channel, meta.id, wire.rx.expected, listKey,
            tostring(meta.count))
        finish()   -- an empty list has no part events at all
    end)

    RegisterNetEvent(channel .. ".stream.part", function(part)
        if not wire or type(part) ~= "table" or tostring(part.id or "") ~= wire.id then return end
        local accepted, why = Chunks.accept(wire.rx, part.index, part.items)
        if accepted == nil then
            log("%s stream %s bad part %s: %s", channel, wire.id, tostring(part.index), tostring(why))
        end
        finish()
    end)
end
