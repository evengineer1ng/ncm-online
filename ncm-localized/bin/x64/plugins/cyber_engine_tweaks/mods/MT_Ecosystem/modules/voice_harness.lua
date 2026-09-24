local Harness = {}

local order = { "dex", "quickie", "foreman", "stu", "rico", "billie", "fan" }

local personas = {
    dex = {
        label = "Dex",
        sentencePattern = "short-clean",
        minSentences = 1,
        maxSentences = 2,
        maxWords = 22,
        infoPriority = "routing",
        relationship = "dispatcher",
        initiative = "entry",
        requiredAny = { "route", "looking", "line", "board", "through" },
        forbiddenAny = { "odds", "chassis", "podium", "favorite", "chalk", "heater" },
    },
    quickie = {
        label = "Quickie Quinn",
        sentencePattern = "ultra-short",
        minSentences = 2,
        maxSentences = 5,
        maxWords = 26,
        infoPriority = "actionable",
        relationship = "hookup",
        initiative = "reactive",
        requiredAny = { "in", "got", "race", "drag", "sprint", "km", "lap" },
        forbiddenAny = { "because", "analysis", "odds", "chassis", "rep", "claim" },
    },
    foreman = {
        label = "Foreman",
        sentencePattern = "directive",
        minSentences = 1,
        maxSentences = 3,
        maxWords = 28,
        infoPriority = "procedural",
        relationship = "authority",
        initiative = "state-aware",
        requiredAny = { "stage", "board", "route", "confirm", "cancel", "grid", "select" },
        forbiddenAny = { "lucky", "obsessed", "chassis", "favorite", "myth" },
    },
    stu = {
        label = "Setup Stu",
        sentencePattern = "medium-think-aloud",
        minSentences = 2,
        maxSentences = 4,
        maxWords = 50,
        infoPriority = "advisory",
        relationship = "builder",
        initiative = "reactive",
        requiredAny = { "lift", "chassis", "map", "bolt", "brake", "rear", "exit", "build" },
        forbiddenAny = { "odds", "board", "favorite", "claim", "poster" },
    },
    rico = {
        label = "Rico",
        sentencePattern = "medium-long",
        minSentences = 2,
        maxSentences = 4,
        maxWords = 56,
        infoPriority = "interpretive",
        relationship = "analyst",
        initiative = "proactive",
        requiredAny = { "read", "pace", "field", "lane", "pressure", "claim", "form" },
        forbiddenAny = { "odds", "chassis", "bolt", "poster", "shrine" },
    },
    billie = {
        label = "BookQueen Billie",
        sentencePattern = "rhythmic",
        minSentences = 2,
        maxSentences = 4,
        maxWords = 42,
        infoPriority = "risk",
        relationship = "tempter",
        initiative = "opportunistic",
        requiredAny = { "sheet", "paper", "odds", "ink", "risk", "pay", "chalk" },
        forbiddenAny = { "chassis", "route to", "poster", "grid is staged" },
    },
    fan = {
        label = "#1 Fan",
        sentencePattern = "punchy",
        minSentences = 1,
        maxSentences = 3,
        maxWords = 30,
        infoPriority = "hype",
        relationship = "obsessed supporter",
        initiative = "milestone-triggered",
        requiredAny = { "city", "obsessed", "poster", "myth", "fire", "unreal", "heater" },
        forbiddenAny = { "odds", "route", "chassis", "confirm", "discipline" },
    },
}

local scenarios = {
    need_race = {
        label = "Need A Race",
        owner = "quickie",
        prompt = "Need a race.",
        notes = "Quickie offers. Foreman routes only if a board already exists. Everyone else deflects or redirects.",
        example = {
            dex = "You're through to NCM. Want Quickie, Foreman, or the garage line?",
            quickie = "Got one. 5.2km sprint. Watson to Japantown. Sport only. You in?",
            foreman = "No board staged. If you want control, open the race board.",
            stu = "Not my lane. Bring me the car once you've got a run worth tuning for.",
            rico = "I can tell you who's dangerous once there's a field. I don't line the races up.",
            billie = "No board, no paper. Bring me a field and then we can flirt with risk.",
            fan = "Go get one and then call me back when the city has something to scream about!",
        },
    },
    race_shape = {
        label = "What Is This Race Like",
        owner = "rico",
        prompt = "What's this race like?",
        notes = "Rico interprets the people in it. Foreman only states structure. Quinn should not suddenly become an analyst.",
        example = {
            dex = "You want structure or a field read? Foreman handles one. Rico handles the other.",
            quickie = "Fast one. Tight streets. That's the sell.",
            foreman = "Grid staged. Six cars. Standing start. Street pressure.",
            stu = "Ask Rico about the people in it. I care what the car will do when they lean on you.",
            rico = "Sharp field. One clean runner up front, one chaos piece behind them. If the launch gets ugly, that's your window.",
            billie = "Looks live enough for a sheet. That's all I need until the prices breathe.",
            fan = "It's the kind people remember if you win it clean.",
        },
    },
    car_feel = {
        label = "What Does The Car Need",
        owner = "stu",
        prompt = "What does the car need?",
        notes = "Stu advises and thinks out loud. Everyone else should redirect.",
        example = {
            dex = "Garage line. Setup Stu.",
            quickie = "Not my problem. I line races up.",
            foreman = "Vehicle state is not a board function.",
            stu = "All right... it's not dead, but the rear's arguing with you on exit. I'd calm the map down first, then talk about hardware.",
            rico = "I read rivals, not dampers. Stu owns that lane.",
            billie = "If it finishes, I'll price it. If it rattles, that's Stu's romance.",
            fan = "If Stu says it needs help, let him cook. I need the hero version of this story.",
        },
    },
    bet_pick = {
        label = "Should I Bet This",
        owner = "billie",
        prompt = "Should I bet this?",
        notes = "Billie frames temptation and risk. Rico can warn, but he does not price.",
        example = {
            dex = "Book line. Billie.",
            quickie = "I bring races, not paper.",
            foreman = "Board state only. Betting decision is external to control.",
            stu = "If the car's wrong, don't get cute with money.",
            rico = "The favorite's real, but the messy driver behind them is the swing factor. That's the read, not the price.",
            billie = "Mmm. It's playable. Chalk is short, value's mean, and the board still has room to hurt you. You feeling sharp or noisy?",
            fan = "Bet if you want. I'm here for the part where you make it look inevitable.",
        },
    },
    big_win = {
        label = "Player Won Big",
        owner = "fan",
        prompt = "We just won big.",
        notes = "The Fan turns results into myth. Rico interprets after. Billie settles. Foreman stays dry.",
        example = {
            dex = "Result logged. Want the board, the books, or the victory lap?",
            quickie = "Knew that one had teeth. Nice work.",
            foreman = "Result posted. Board ready for next action.",
            stu = "Good. Now let's make sure the car can do it again without complaining.",
            rico = "That result moves the room. People stop treating you like traffic after a win like that.",
            billie = "Paper landed. Clean. I do enjoy it when confidence cashes.",
            fan = "THAT is the one. Big lights, clean finish, whole city watching. You're a problem now!",
        },
    },
}

local function copyValue(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for key, inner in pairs(value) do
        out[key] = copyValue(inner)
    end
    return out
end

local function trim(text)
    return tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function wordCount(text)
    local count = 0
    for _ in trim(text):gmatch("[%w']+") do
        count = count + 1
    end
    return count
end

local function sentenceCount(text)
    local count = 0
    for _ in trim(text):gmatch("[%.%!%?]") do
        count = count + 1
    end
    if count == 0 and trim(text) ~= "" then
        return 1
    end
    return count
end

local function containsAny(text, terms)
    local lower = trim(text):lower()
    for _, term in ipairs(terms or {}) do
        if lower:find(tostring(term):lower(), 1, true) then
            return true, term
        end
    end
    return false, nil
end

local function tokenSet(text)
    local set = {}
    for token in trim(text):lower():gmatch("[%a']+") do
        set[token] = true
    end
    return set
end

local function overlapScore(left, right)
    local a = tokenSet(left)
    local b = tokenSet(right)
    local union = 0
    local same = 0
    for token in pairs(a) do
        union = union + 1
        if b[token] then
            same = same + 1
        end
    end
    for token in pairs(b) do
        if not a[token] then
            union = union + 1
        end
    end
    if union <= 0 then
        return 0
    end
    return same / union
end

function Harness.personaTable()
    return copyValue(personas)
end

function Harness.scenarioTable()
    return copyValue(scenarios)
end

function Harness.exampleBundle(id)
    local scenario = scenarios[id]
    if not scenario then
        return nil, "unknown_scenario"
    end
    return copyValue(scenario.example)
end

function Harness.validateCharacter(id, text)
    local persona = personas[id]
    if not persona then
        return nil, "unknown_persona"
    end

    local issues = {}
    local value = trim(text)
    local words = wordCount(value)
    local sentences = sentenceCount(value)

    if value == "" then
        issues[#issues + 1] = "empty response"
    end
    if words > persona.maxWords then
        issues[#issues + 1] = string.format("too many words (%d > %d)", words, persona.maxWords)
    end
    if sentences < persona.minSentences then
        issues[#issues + 1] = string.format("too few sentences (%d < %d)", sentences, persona.minSentences)
    end
    if sentences > persona.maxSentences then
        issues[#issues + 1] = string.format("too many sentences (%d > %d)", sentences, persona.maxSentences)
    end

    local hasRequired, requiredTerm = containsAny(value, persona.requiredAny)
    if not hasRequired then
        issues[#issues + 1] = "missing domain vocabulary"
    end

    local hasForbidden, forbiddenTerm = containsAny(value, persona.forbiddenAny)
    if hasForbidden then
        issues[#issues + 1] = string.format("contains forbidden term '%s'", tostring(forbiddenTerm))
    end

    return {
        id = id,
        label = persona.label,
        ok = #issues == 0,
        issues = issues,
        metrics = {
            words = words,
            sentences = sentences,
            requiredHit = requiredTerm,
            text = value,
        },
    }
end

function Harness.validateBundle(id, bundle)
    local scenario = scenarios[id]
    if not scenario then
        return nil, "unknown_scenario"
    end

    local payload = bundle or scenario.example
    local report = {
        id = id,
        label = scenario.label,
        prompt = scenario.prompt,
        owner = scenario.owner,
        notes = scenario.notes,
        results = {},
        pairIssues = {},
        ok = true,
    }

    for _, personaId in ipairs(order) do
        local result = Harness.validateCharacter(personaId, payload[personaId] or "")
        report.results[personaId] = result
        if not result.ok then
            report.ok = false
        end
    end

    for leftIndex = 1, #order do
        for rightIndex = leftIndex + 1, #order do
            local leftId = order[leftIndex]
            local rightId = order[rightIndex]
            local leftText = trim(payload[leftId] or "")
            local rightText = trim(payload[rightId] or "")
            if leftText ~= "" and rightText ~= "" then
                local score = overlapScore(leftText, rightText)
                if score >= 0.55 then
                    report.ok = false
                    report.pairIssues[#report.pairIssues + 1] = string.format(
                        "%s vs %s overlap too much (%.2f)",
                        personas[leftId].label,
                        personas[rightId].label,
                        score)
                end
            end
        end
    end

    return report
end

function Harness.matrixText()
    local lines = { "NCM voice matrix" }
    for _, id in ipairs(order) do
        local persona = personas[id]
        lines[#lines + 1] = string.format(
            "%s | %s | %s | %s | %s | %s",
            persona.label,
            persona.sentencePattern,
            persona.infoPriority,
            persona.relationship,
            persona.initiative,
            table.concat(persona.requiredAny, ", "))
    end
    return table.concat(lines, "\n")
end

function Harness.scenarioText(id)
    local scenario = scenarios[id]
    if not scenario then
        return "Unknown scenario."
    end
    local lines = {
        string.format("%s", scenario.label),
        string.format("Prompt: %s", scenario.prompt),
        string.format("Owner: %s", personas[scenario.owner].label),
        string.format("Notes: %s", scenario.notes),
    }
    return table.concat(lines, "\n")
end

function Harness.reportText(report)
    if not report then
        return "No report."
    end

    local lines = {
        string.format("Voice scenario: %s", report.label),
        string.format("Prompt: %s", report.prompt),
        string.format("Owner: %s", personas[report.owner].label),
        string.format("Overall: %s", report.ok and "PASS" or "FAIL"),
    }

    for _, id in ipairs(order) do
        local result = report.results[id]
        lines[#lines + 1] = string.format(
            "%s | %d words | %d sentences | %s",
            result.label,
            tonumber(result.metrics.words or 0),
            tonumber(result.metrics.sentences or 0),
            result.ok and "OK" or "CHECK")
        if not result.ok then
            for _, issue in ipairs(result.issues or {}) do
                lines[#lines + 1] = "  - " .. tostring(issue)
            end
        end
    end

    for _, issue in ipairs(report.pairIssues or {}) do
        lines[#lines + 1] = "Pair issue: " .. tostring(issue)
    end

    return table.concat(lines, "\n")
end

function Harness.runExample(id)
    local report, err = Harness.validateBundle(id)
    if not report then
        return err or "unknown_error"
    end
    return Harness.reportText(report)
end

return Harness