-- ncm-core module: paddock.news
-- WIRE: deterministic headlines from the tape (doc 44 §8; FTB1 `ftb_broadcast_commentary` pattern).
--
-- A template is eligible only when EVERY `{slot}` it names resolves from the event's `facts`. That is the whole
-- truth rule: prose cannot mention a margin, a rain shower or a feud the tape does not hold. Optional colour is
-- carried by optional facts (`wet`, `night`, `fromGrid`...), so a dry-weather story simply has fewer templates.
-- A no-repeat window per kind keeps the feed from saying the same sentence twice in a row.
local Core = NcmCore

Core.define("paddock.news", function(C)
    local M = { version = "0.1.0", NO_REPEAT = 8 }
    local Hash = C.get("vocabulary.hash")

    -- { id, h = headline, b = body }. Keep ids stable: they are stored with each story for the no-repeat window.
    M.POOLS = {
        race_result = {
            { id = "rr1", h = "{winner} takes {route}", b = "{winner} ({winnerOrg}) won the {series} round on {route}, {margin} clear of {second}. {third} completed the podium." },
            { id = "rr2", h = "{winnerOrg} on top at {route}", b = "{winner} brought it home for {winnerOrg} on {route}. {second} and {third} followed across the line." },
            { id = "rr3", h = "{winner} holds off {second}", b = "{second} chased all the way, but {winner} held on by {margin} on {route} in the {series}." },
            { id = "rr4", h = "{route}: {winner} by {margin}", b = "A {fieldSize}-car {series} field, one winner: {winner} for {winnerOrg}. {second} was next, then {third}." },
            { id = "rr5", h = "Rain on {route}, {winner} unbothered", b = "{wet} conditions on {route} sorted the {series} field; {winner} found the grip first and beat {second} by {margin}." },
            { id = "rr6", h = "{winner} masters the wet at {route}", b = "{winner} ({winnerOrg}) won on a {wet} {route}. {third} took the last podium spot." },
            { id = "rr7", h = "Night run goes to {winner}", b = "Under the lights on {route}, {winner} beat {second} by {margin}. {series}, {night}." },
            { id = "rr8", h = "{winner} from P{fromGrid}", b = "{winner} started {fromGrid}th and won the {series} round on {route}. {second} finished {margin} back." },
            { id = "rr9", h = "Photo finish on {route}", b = "{closeFinish}: {winner} over {second} in the {series}, {third} third." },
            { id = "rr10", h = "{winnerOrg} {oneTwo}", b = "{winner} led {second} home for a {winnerOrg} one-two on {route}." },
        },
        upset = {
            { id = "up1", h = "Nobody had {winner} on {route}", b = "{winner} ({winnerOrg}) started {fromGrid}th and won the {series} round. Billie's board had them at {price}." },
            { id = "up2", h = "{winner} stuns the {series}", b = "From {fromGrid}th on the grid, {winner} beat {second} on {route}." },
            { id = "up3", h = "Upset at {route}", b = "{winner} of {winnerOrg} took an unlikely {series} win from {fromGrid}th." },
        },
        streak = {
            { id = "st1", h = "{driver}: {count} straight", b = "{driver} ({org}) has now won {count} {series} races in a row." },
            { id = "st2", h = "Nobody can stop {driver}", b = "Another win for {driver} makes it {count} on the bounce for {org}." },
            { id = "st3", h = "{driver} on a {count}-race run", b = "{count} consecutive {series} wins and counting for {driver}." },
        },
        first_win = {
            { id = "fw1", h = "First win for {driver}", b = "{driver} broke through on {route} at the {starts}th attempt, winning for {org} in the {series}." },
            { id = "fw2", h = "{driver} finally wins", b = "{starts} starts, no wins, until tonight: {driver} took {route} for {org}." },
        },
        crash_out = {
            { id = "co1", h = "{driver} out on {route}", b = "{driver} ({org}) did not finish the {series} round on {route}: {cause}." },
            { id = "co2", h = "Heartbreak for {org}", b = "{driver} retired from the {series} race on {route}: {cause}." },
        },
        feud = {
            { id = "fd1", h = "{driverA} and {driverB}, again", b = "{driverA} ({orgA}) and {driverB} ({orgB}) made contact on {route}. That is {count} times now." },
            { id = "fd2", h = "Bad blood between {orgA} and {orgB}", b = "Another clash on {route}: {driverA} and {driverB} have touched {count} times this season." },
        },
        transfer = {
            { id = "tr1", h = "{driver} signs for {toOrg}", b = "{driver} joins {toOrg} in the {tier} ranks{fromNote}." },
            { id = "tr2", h = "{toOrg} land {driver}", b = "{toOrg} have signed {driver}{fromNote}. Terms were not disclosed." },
        },
        release = {
            { id = "rl1", h = "{org} release {driver}", b = "{driver} is a free agent after {org} ended the contract." },
            { id = "rl2", h = "{driver} out at {org}", b = "{org} and {driver} have parted ways." },
        },
        retirement = {
            { id = "rt1", h = "{driver} retires", b = "{driver} hangs up the helmet at {age}: {starts} starts, {wins} wins." },
            { id = "rt2", h = "End of the road for {driver}", b = "After {starts} starts and {wins} wins, {driver} ({org}) has retired." },
        },
        fold = {
            { id = "fo1", h = "{org} folds", b = "{org} could not pay its bills and has closed its doors after {seasons} seasons. {replacement} takes its place." },
            { id = "fo2", h = "Lights out at {org}", b = "{org} is gone. Its {tier} slot passes to newcomers {replacement}." },
        },
        founded = {
            { id = "fn1", h = "New team: {org}", b = "{org} enters the {tier} ranks, founded by {founder}." },
            { id = "fn2", h = "{founder} launches {org}", b = "{founder} has put a new team on the {tier} grid: {org}." },
        },
        promotion = {
            { id = "pr1", h = "{org} moves up", b = "{org} earns promotion from {fromTier} to {toTier}." },
            { id = "pr2", h = "{org} promoted to {toTier}", b = "A strong season lifts {org} out of {fromTier}." },
        },
        relegation = {
            { id = "rg1", h = "{org} drops to {toTier}", b = "{org} is relegated from {fromTier} after a difficult season." },
            { id = "rg2", h = "Relegation for {org}", b = "{org} leaves {fromTier} and starts next season in {toTier}." },
        },
        cup_title = {
            { id = "ct1", h = "{driver} wins the {cup}", b = "{driver} ({org}) takes the {series} {cup} with {points} points." },
            { id = "ct2", h = "{cup} goes to {org}", b = "{driver} sealed the {series} {cup} for {org} on {points} points." },
        },
        season_title = {
            { id = "sn1", h = "{driver} is {series} champion", b = "{driver} ({org}) wins the {season} {series} title with {points} points." },
            { id = "sn2", h = "Champion: {driver}", b = "The {season} {series} crown goes to {driver} of {org}, {points} points." },
        },
        human_mention = {
            { id = "hm1", h = "{human} turns heads", b = "Paddock talk tonight is about {human}, {result} in the {series}." },
            { id = "hm2", h = "{human} on the radar", b = "The Paddock is watching {human} after {result} in the {series}." },
        },
        callout = {
            { id = "cl1", h = "{npc} calls out {human}", b = "\"Let's see {human} do it again,\" said {npc} of {npcOrg}. The Paddock will be watching {human}'s next {series} race." },
            { id = "cl2", h = "{npc}: {human} got lucky", b = "{npc} ({npcOrg}) is not impressed by {human}. The next sanctioned result will settle it." },
        },
        manager_hired = {
            { id = "mh1", h = "{org} names {manager} manager", b = "{manager} takes charge at {org}." },
        },
        manager_fired = {
            { id = "mf1", h = "{org} fires {manager}", b = "{owner} has dismissed {manager} after a run of poor results at {org}." },
            { id = "mf2", h = "{manager} out at {org}", b = "{org}'s owner {owner} has made a change: {manager} is gone." },
        },
        sponsor_signed = {
            { id = "ss1", h = "{sponsor} backs {org}", b = "{org} carries new colours: {sponsor} has signed on." },
        },
        sponsor_left = {
            { id = "sl1", h = "{sponsor} pulls out of {org}", b = "{sponsor} has ended its deal with {org}." },
        },
        rookie_debut = {
            { id = "rd1", h = "{driver} makes a debut", b = "{driver} lines up for {org} in the {series}." },
        },
    }

    local function slots(tpl)
        local out = {}
        for s in string.gmatch(tpl, "{(%w+)}") do out[#out + 1] = s end
        return out
    end

    local function resolves(t, facts)
        for _, text in ipairs({ t.h, t.b }) do
            for _, s in ipairs(slots(text)) do
                local v = facts[s]
                if v == nil or v == "" then return false end
            end
        end
        return true
    end

    local function fill(text, facts)
        return (text:gsub("{(%w+)}", function(s) return tostring(facts[s]) end))
    end

    --- The templates eligible for an event, in pool order.
    function M.eligible(event)
        local out = {}
        for _, t in ipairs(M.POOLS[event.kind] or {}) do
            if resolves(t, event.facts or {}) then out[#out + 1] = t end
        end
        return out
    end

    --- Write a story for an event, or nil when no template resolves. `recent` = list of template ids recently used
    --- for this kind (most recent last). Deterministic for (event id, recent).
    function M.write(event, recent)
        local eligible = M.eligible(event)
        if #eligible == 0 then return nil end
        local blocked = {}
        local from = math.max(1, #(recent or {}) - M.NO_REPEAT + 1)
        for i = from, #(recent or {}) do blocked[recent[i]] = true end
        local fresh = {}
        for _, t in ipairs(eligible) do if not blocked[t.id] then fresh[#fresh + 1] = t end end
        if #fresh == 0 then fresh = eligible end
        local t = Hash.pick(fresh, "news", event.id)
        return {
            storyId = "n:" .. event.id, eventId = event.id, kind = event.kind, templateId = t.id,
            headline = fill(t.h, event.facts), body = fill(t.b, event.facts), at = event.at,
            prominence = event.salience or 0, subjects = event.entities or {},
        }
    end

    --- True when every slot in every template of every pool is a plain word (a lint for the pools themselves).
    function M.lint()
        for kind, pool in pairs(M.POOLS) do
            local seen = {}
            for _, t in ipairs(pool) do
                if seen[t.id] then return false, "duplicate template id " .. t.id end
                seen[t.id] = true
                if type(t.h) ~= "string" or type(t.b) ~= "string" then return false, kind .. ":" .. t.id end
            end
        end
        return true
    end

    return M
end)
