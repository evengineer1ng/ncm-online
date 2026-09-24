-- ncm-core module: player.help
--
-- The player-facing Help surface's content model and the rules around a submitted problem report.
--
-- **The governing idea (owner, 2026-09-23): the server is the support channel.** A player should not need the
-- owner's Discord, a GitHub account or an email address to tell NCM that NCM is broken. If the game is working
-- well enough to open Help, it is working well enough to take a report.
--
-- Two things live here because both are rules rather than effects, and both are worth testing offline:
--
--   1. WHAT HELP SAYS. The controls section is DERIVED from a single catalogue, so there is exactly one place
--      that knows what a player can do. §14's failure mode is "code says one thing, Help says another", and the
--      only durable defence is to stop keeping two lists.
--   2. WHAT A REPORT IS. Validation, trimming and bounds, so a host never persists something unbounded and a
--      player never sees "submitted" for something that was refused.
--
-- **Authored content is deliberately optional.** Known issues and recent changes cannot be derived, and the
-- owner's warning was exact: *"authorship sounds small until it isnt."* So those sections take whatever a host
-- hands them and **render nothing at all when empty** -- the same rule the weather ribbon follows. No empty
-- panel, no stale promise, no standing obligation to write release notes.
local Core = NcmCore

Core.define("player.help", function(C)
    local M = { version = "0.0.1" }

    --- Everything a player can actually do, in one place.
    ---
    --- `key` is a registered binding, `cmd` a chat command; an entry may carry either or both. Nothing
    --- operator-only appears here and nothing speculative does either: §11 forbids documenting hypothetical
    --- features, and a Help page that lists a command which refuses you is worse than one that omits it.
    ---
    --- `needs` names a capability the host must confirm is live before the row is shown, so a surface that is
    --- not running is simply absent rather than advertised. That is how the Market stays out of Help until the
    --- Market exists.
    local CATALOGUE = {
        { id = "guide",      key = "F6",  cmd = "/ncm.guidepage",  title = "Race Guide",
          text = "Tonight's races: what is running, where, the weather, the regulations and whether you can enter." },
        { id = "market",     cmd = "/ncm.market", title = "Market", needs = "market",
          text = "Buy a vehicle. What you own is yours and can be entered in races." },
        { id = "collection", key = "F6 / F10", cmd = "/ncm.collectionpage", title = "Machine Index",
          text = "Discover machines and select a specific owned asset to CALL VEHICLE in a clear nearby space." },
        { id = "messages",   key = "F9",  cmd = "/ncm.msgs",       title = "Messages",
          text = "Invitations and notices addressed to you." },
        { id = "profile",    cmd = "/ncm.profile", title = "Your driver",
          text = "Licence, safety rating, reputation and what you have achieved." },
        { id = "garage",     cmd = "/ncm garage",  title = "Your garage",
          text = "The vehicles you own." },
        { id = "gps",        cmd = "/ncm.gps",     title = "Route there",
          text = "Points your map at your next race, or at the course once you have entered one. NCM does this " ..
                 "for you; use it if you want the route set again." },
        { id = "forfeit",    cmd = "/ncm.forfeit", title = "Retire from a race", needs = "racing",
          text = "Leaves a race you have already started, recorded as a DNF. Ask twice to confirm. To leave a " ..
                 "race you entered but have not started, use Withdraw at the venue instead." },
        { id = "nodes",      cmd = "/ncm.nodes",   title = "Location names on the map",
          text = "NCM's named places -- Pothole, Deep Dive, Japantown Crossway -- are marked on your world map " ..
                 "so you can set your own waypoint on one. Toggles them off and on." },
        { id = "help",       cmd = "/ncm help",    title = "This page",
          text = "Orientation, what works today, and how to report a problem. Also /ncm lost and /ncm docs." },
    }

    --- The controls a given server can honestly advertise.
    --- `live` is a set of capability names the host has confirmed; an entry with `needs` is dropped unless its
    --- capability is present. Order is authored, not alphabetical: it is a reading order, not an index.
    function M.controls(live)
        live = type(live) == "table" and live or {}
        local out = {}
        for _, e in ipairs(CATALOGUE) do
            if (not e.needs) or live[e.needs] == true then
                out[#out + 1] = { id = e.id, key = e.key, cmd = e.cmd, title = e.title, text = e.text }
            end
        end
        return out
    end

    --- Every catalogue id, for a host that wants to assert its capability names line up. Diagnostics only.
    function M.catalogueIds()
        local out = {}
        for i, e in ipairs(CATALOGUE) do out[i] = e.id end
        return out
    end

    M.TEXT_MAX = 1200      -- long enough for a real description, bounded enough to store without thinking
    M.TEXT_MIN = 4         -- "car" is not a report; "car wont spawn" is

    --- Clean a player's description into something safe to persist, or refuse it with a reason.
    --- Returns text, or nil + reason ("empty" | "too_short" | "invalid").
    ---
    --- Control characters are stripped rather than escaped: this string is read by a human in a log or a
    --- console, and a report that can move the cursor is a report that can lie about what it says.
    function M.cleanReport(text)
        if type(text) ~= "string" then return nil, "invalid" end
        local s = text:gsub("[%z\1-\8\11\12\14-\31\127]", " ")   -- keep \t (9) and \n (10)
        s = s:gsub("\r\n", "\n"):gsub("\r", "\n")
        s = s:gsub("[ \t]+", " ")
        s = s:gsub("\n[ \t]*", "\n"):gsub("\n\n\n+", "\n\n")
        s = s:gsub("^%s+", ""):gsub("%s+$", "")
        if s == "" then return nil, "empty" end
        if #s < M.TEXT_MIN then return nil, "too_short" end
        if #s > M.TEXT_MAX then s = s:sub(1, M.TEXT_MAX) end
        return s
    end

    --- What the player is told will be sent with their report (§10). Derived from the context the host
    --- actually assembled, so the disclosure cannot drift away from the payload: if a field is not in the
    --- snapshot, it is not in the sentence.
    function M.disclosure(context)
        local has = {}
        local c = type(context) == "table" and context or {}
        if c.driverId or c.playerName then has[#has + 1] = "who you are on this server" end
        if c.position then has[#has + 1] = "where you were standing" end
        if c.readiness then has[#has + 1] = "whether your character had finished loading" end
        if c.garage then has[#has + 1] = "what you own" end
        if c.eligibility or c.event then has[#has + 1] = "the race you were looking at" end
        if c.panel then has[#has + 1] = "which NCM screen was open" end
        if #has == 0 then return "Your report is sent with the server's build version and the time." end
        return "Sent with your report: " .. table.concat(has, ", ") ..
               ", plus the server's build version and the time. Nothing else."
    end

    --- Assemble the payload the Help page renders. Pure: every input is supplied by the host.
    ---
    --- `notices` and `changes` are authored and OPTIONAL. Absent means the section does not exist on the page,
    --- which is the point -- see the note at the top of this file.
    function M.page(input)
        input = type(input) == "table" and input or {}
        local function list(v)
            if type(v) ~= "table" then return nil end
            local out = {}
            for _, item in ipairs(v) do
                if type(item) == "table" and type(item.title) == "string" and item.title ~= "" then
                    out[#out + 1] = { title = item.title, text = item.text, workaround = item.workaround, at = item.at }
                end
            end
            if #out == 0 then return nil end
            return out
        end
        return {
            build = input.build,
            serverName = input.serverName or "Night City Motorsports",
            controls = M.controls(input.live),
            notices = list(input.notices),     -- known player-affecting issues; nil renders nothing
            changes = list(input.changes),     -- recent meaningful changes; nil renders nothing
            canReport = input.canReport ~= false,
            textMax = M.TEXT_MAX,
        }
    end

    return M
end)
