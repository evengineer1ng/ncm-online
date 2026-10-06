-- ncm-core module: onboarding.questionnaire
-- The NCM Driver Profile questionnaire (L48, P29, P31): versioned questions whose answers become an affinity vector
-- over the NCX teams that the sorting hat weighs within the variety rule. Never shown to the player as "teams";
-- no gameplay effect. Content here is PLACEHOLDER copy — the owner authors the real questions and the team
-- personality matrix; only the shape (ids, keys, weights) is load-bearing.
local Core = NcmCore

Core.define("onboarding.questionnaire", function(C)
    local M = { version = "0.0.1" }
    local Teams = C.get("competition.teams")

    M.VERSION = 1

    -- weights: teamId -> points. Keys are the option letters the player answers with.
    M.QUESTIONS = {
        { id = "q1", text = "Night City at 3 a.m. Where are you?",
          options = {
            { key = "a", text = "Corpo Plaza — the towers are the track",            weights = { rayfield = 2, kimiko = 1 } },
            { key = "b", text = "Kabuki — neon, noise, narrow",                      weights = { mizutani = 2, yorinobu = 1 } },
            { key = "c", text = "The Badlands — dust and a straight road",           weights = { thorton = 2, spunky_monkey = 1 } },
            { key = "d", text = "Pacifica — nobody's looking",                       weights = { raven = 2, herrera = 1 } },
          } },
        { id = "q2", text = "Your car is a tool, an heirloom, a weapon, or a statement?",
          options = {
            { key = "a", text = "A tool",       weights = { archer = 2, thorton = 1 } },
            { key = "b", text = "An heirloom",  weights = { herrera = 2, quadra = 1 } },
            { key = "c", text = "A weapon",     weights = { raven = 2, yorinobu = 1 } },
            { key = "d", text = "A statement",  weights = { rayfield = 2, kimiko = 1 } },
          } },
        { id = "q3", text = "The gap closes. You…",
          options = {
            { key = "a", text = "Send it — they'll move",                weights = { spunky_monkey = 2, raven = 1 } },
            { key = "b", text = "Wait for the mistake",                  weights = { mizutani = 2, kimiko = 1 } },
            { key = "c", text = "Take the line they don't expect",       weights = { quadra = 2, archer = 1 } },
            { key = "d", text = "Hold station — the race is long",       weights = { herrera = 2, yorinobu = 1 } },
          } },
        { id = "q4", text = "Music on the grid?",
          options = {
            { key = "a", text = "Silence",                 weights = { yorinobu = 2, mizutani = 1 } },
            { key = "b", text = "Something loud",          weights = { spunky_monkey = 2, thorton = 1 } },
            { key = "c", text = "Whatever the crew plays", weights = { archer = 2, quadra = 1 } },
            { key = "d", text = "The engine",              weights = { herrera = 2, rayfield = 1 } },
          } },
        { id = "q5", text = "Money or fame?",
          options = {
            { key = "a", text = "Money",                    weights = { kimiko = 2, rayfield = 1 } },
            { key = "b", text = "Fame",                     weights = { raven = 2, quadra = 1 } },
            { key = "c", text = "Respect",                  weights = { thorton = 2, herrera = 1 } },
            { key = "d", text = "The next race",            weights = { mizutani = 2, archer = 1 } },
          } },
        { id = "q6", text = "You lose by a car length. First thought?",
          options = {
            { key = "a", text = "Next time.",               weights = { yorinobu = 2, mizutani = 1 } },
            { key = "b", text = "Who saw it?",              weights = { kimiko = 2, raven = 1 } },
            { key = "c", text = "What did the car do?",     weights = { archer = 2, quadra = 1 } },
            { key = "d", text = "Where's the bar?",         weights = { spunky_monkey = 2, thorton = 1 } },
          } },
    }

    --- Validate a submission. answers = array of option keys, one per question, in order.
    function M.validate(version, answers)
        if tonumber(version) ~= M.VERSION then return false, "version_mismatch" end
        if type(answers) ~= "table" or #answers ~= #M.QUESTIONS then return false, "answer_count" end
        for i, q in ipairs(M.QUESTIONS) do
            local found = false
            for _, o in ipairs(q.options) do if o.key == answers[i] then found = true end end
            if not found then return false, "unknown_option:" .. q.id end
        end
        return true
    end

    --- Affinity vector { teamId -> 0..1 } from validated answers (points summed, normalised to the max).
    function M.affinity(answers)
        local score, maxScore = {}, 0
        for _, t in ipairs(Teams.NCX) do score[t.teamId] = 0 end
        for i, q in ipairs(M.QUESTIONS) do
            for _, o in ipairs(q.options) do
                if o.key == answers[i] then
                    for teamId, w in pairs(o.weights) do
                        score[teamId] = (score[teamId] or 0) + w
                        if score[teamId] > maxScore then maxScore = score[teamId] end
                    end
                end
            end
        end
        if maxScore > 0 then for k, v in pairs(score) do score[k] = v / maxScore end end
        return score
    end

    --- The persisted document (P29): version, answers, affinity; the host stamps completedAt.
    function M.document(answers, now)
        return { version = M.VERSION, answers = answers, affinity = M.affinity(answers), completedAt = now }
    end

    --- The team an affinity vector favours most (for logs only; never shown to the player).
    function M.top(affinity)
        local best, bestV
        for teamId, v in pairs(affinity or {}) do
            if not bestV or v > bestV or (v == bestV and teamId < best) then best, bestV = teamId, v end
        end
        return best, bestV
    end

    --- Question n as plain text for chat delivery (the /ncm.q fallback).
    function M.prompt(n)
        local q = M.QUESTIONS[n]
        if not q then return nil end
        local parts = {}
        for _, o in ipairs(q.options) do parts[#parts + 1] = o.key .. ") " .. o.text end
        return ("Q%d/%d %s  %s"):format(n, #M.QUESTIONS, q.text, table.concat(parts, "  "))
    end

    return M
end)
