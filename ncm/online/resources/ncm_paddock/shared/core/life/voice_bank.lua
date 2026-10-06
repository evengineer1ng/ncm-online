-- ncm-core module: life.voice_bank
-- The line bank `life.voice` draws from, as plain tagged text so the owner can read and edit every line (owner,
-- 2026-09-30: "i want to see the lines before they go out the door no matter how big the bank is").
--
-- A line is  "[tags] text"  (the bracket is optional). Tags say WHO may say it; a voice may say a line only if it
-- has every non-register tag, and at least one of the line's registers if it names any:
--   registers   street plain tech corp          (alternatives)
--   warmth      warm cold      temper   edgy calm      confidence   cocky humble
--   talk        chatty terse   humor    joker dry      age          young old
--   role        driver engineer strategist manager owner
--   knowing     known  (has met you)   heard  (your Spotlight >= 10)   famous  (>= 25)
-- Untagged lines are for anyone. A line is also dropped if any `{slot}` cannot be filled (the truth rule).
-- Slots: {name} {role} {org} {series} {route} {when} {lastRoute} {lastPlace} {lastDriver} {tagLabel} {tagSubject}
-- {place} {district} {player} {champion} {championSeries} {championRun} -- facts; {addr} {good} {bad} {swear} -- the speaker's own words.
--
-- Parts live in `life.voice_bank_greet`, `life.voice_bank_scene`, `life.voice_bank_topics` and `life.voice_bank_more`
-- (which appends to moves the others opened). Line ids are
-- "<move>#<n>" in file order: add at the end of a move, strike by marking, so an id never changes meaning.
local Core = NcmCore

Core.define("life.voice_bank", function(C)
    local M = { version = "0.1.0" }

    local moves, order
    local function parse(line, move, n)
        local tagText, text = line:match("^%s*%[([^%]]*)%]%s*(.+)$")
        if not tagText then text = line end
        local tags = {}
        for t in (tagText or ""):gmatch("[%w_]+") do tags[t] = true end
        return { id = move .. "#" .. n, move = move, tags = tags, text = text }
    end

    local function build()
        moves, order = {}, {}
        -- A later part may add to a move an earlier part opened: its lines append, so every id stays put.
        for _, part in ipairs({ "life.voice_bank_greet", "life.voice_bank_scene", "life.voice_bank_topics",
            "life.voice_bank_more" }) do
            local P = C.get(part)
            for _, mv in ipairs(P.ORDER) do
                local list = moves[mv]
                if not list then list = {}; moves[mv] = list; order[#order + 1] = mv end
                for _, line in ipairs(P.MOVES[mv]) do list[#list + 1] = parse(line, mv, #list + 1) end
            end
        end
    end

    function M.move(name) if not moves then build() end return moves[name] end
    function M.moves() if not moves then build() end return order end

    --- Every line, for review and tests: { id, move, tags, text }.
    function M.all()
        if not moves then build() end
        local out = {}
        for _, mv in ipairs(order) do for _, e in ipairs(moves[mv]) do out[#out + 1] = e end end
        return out
    end

    return M
end)
