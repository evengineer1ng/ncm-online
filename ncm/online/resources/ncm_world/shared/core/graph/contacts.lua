-- ncm-core module: graph.contacts
--
-- WHO can speak, and in whose voice. The registry only -- no trees, no triggers, no copy.
-- `41_QUEST_GRAPH_PASS1.md` sections 1 and 19 name eighteen contacts; all eighteen are declared here, because
-- the relationship map is a fact about the design even where the script does not exist yet. What separates a
-- declared contact from a usable one is `authored`, and nothing may speak unless that is true (§A.8: the first
-- slice is Dex, Stu and the Rico offer, and the appendix is explicit that Flashbulb, Auntie, Dave, Zero and
-- Glass are blocked on substrate that does not exist).
--
-- ## The voice model is `L176`, not the single-player harness
--
-- SP's `voice_harness.lua` held six things per character: a sentence pattern, min/max sentences, a word
-- ceiling, `requiredAny` (domain vocabulary that must appear) and `forbiddenAny` (vocabulary that must not).
-- **`L176` (LOCKED, owner) strikes the word and sentence ceilings** and keeps the rest. The reason inverts the
-- usual argument, and it is worth restating because it is easy to re-derive the wrong way round: the ceilings
-- were built against the WolvenKit phone, a highly restrictive display surface, and enforcing a small envelope
-- on *every* character risks making them **all sound the same**. A 22-word ceiling does not make Dex
-- characterful; it makes Dex clipped, and a uniformly clipped cast has lost the variety the harness existed to
-- protect. NCM Online's Messages surface has no such limit.
--
-- So what is mechanical here is **vocabulary and distinctiveness**:
--
--   * `forbidden` -- words belonging to another character's domain. Checked per line, because a single trespass
--     is a trespass. This is what stops Stu quoting odds and Rico pricing risk.
--   * `required` -- the character's own domain vocabulary. Checked over a whole script rather than per line,
--     which is a deliberate departure from SP's per-message check: NCM Online's beats are short enough that
--     "Needle." is a legitimate whole message, and a per-line requirement would forbid it.
--   * pairwise token overlap, failed at >= 0.55 -- **the load-bearing one** (`L176`). It is the direct
--     mechanical expression of *"no two contacts sound the same"*, and it is the only reason seven SP voices
--     stayed distinct. `graph.conversation.distinct` runs it across every authored pair.
--
-- **Dex is recharacterised by the same ruling.** The archaeology called his voice *terseness*; the owner's
-- correction is that it is **neutral guidance** -- the contact who routes without colouring, not the contact
-- who is short. A long Dex message is fine; an *opinionated* one is not. His `forbidden` list already encodes
-- exactly that, because it forbids other characters' domains rather than length.
--
-- `domain` is not decoration either. §0.4 -- *"Dex knows NCM. Specialists know their domains"* -- is the rule
-- that keeps Dex from impersonating expertise, and it is enforced by redirecting a question whose domain this
-- contact does not hold.
local Core = NcmCore

Core.define("graph.contacts", function()
    local M = { version = "0.2.0" }

    --- Where a contact came from. §1's three grammars, plus the two the first expansion adds.
    M.GRAMMARS = {
        system = true,        -- unmissable; NCM itself (Dex)
        handoff = true,       -- guaranteed introduction from another contact (Stu)
        referral = true,      -- offered introduction the player may freely defer (Rico, Billie, Needle, Mara)
        emergent = true,      -- the world noticed the player (the Fan, Knuckles, Sunday, Patch, Glass, Zero)
        physical = true,      -- met by being somewhere (Auntie, Dave)
    }

    --- What a contact is allowed to be authoritative about (§0.4). A question outside every domain a contact
    --- holds is redirected, never answered.
    M.DOMAINS = {
        ncm = true,           -- how NCM itself works: races, money, surfaces, routing
        machine = true,       -- the car: parts, setup, why it behaves as it does
        creation = true,      -- building a race
        intelligence = true,  -- who is running, what is moving, who to know
        wagering = true,
        hardware = true,      -- where unusual parts come from
        research = true,
        collection = true,    -- provenance, history, preservation
        salvage = true,
        laps = true,          -- time, routes, corners
        spotting = true,      -- identifying machines in the world
        events = true,        -- curated fields and seats
        personal = true,      -- no expertise at all; a relationship (the Fan)
    }

    local function set(list)
        local out = {}
        for _, v in ipairs(list or {}) do out[v] = true end
        return out
    end

    --- One row per contact.
    ---
    --- `required` / `forbidden` are the surviving halves of the voice harness (`L176`). Where a row is marked
    --- RECOVERED the lists are exactly as `voice_harness.lua` held them, quoted through
    --- `CHARACTER_ARCHAEOLOGY_AND_PVE_SUBSTRATE.md` §I.9; where it is marked INFERRED they were written here
    --- from the character's domain, and Pass 2 should expect to revise them. Keeping the two apart matters:
    --- a recovered list is evidence, an inferred one is a guess, and this repository does not blur that.
    local ROSTER = {
        -- ---- the opening constellation, authored (§A.8) ------------------------------------------------
        { id = "dex", name = "Dex", label = "NCM DISPATCH", grammar = "system", authored = true,
          domains = { "ncm" },
          -- RECOVERED. `L176`: his register is neutral guidance, not brevity.
          required = { "route", "looking", "line", "board", "through" },
          forbidden = { "odds", "chassis", "podium", "favorite", "chalk", "heater" },
          note = "Routes and explains NCM without colouring it. Redirects rather than impersonating a specialist (§0.4)." },

        { id = "stu", name = "Setup Stu", label = "SETUP STU", grammar = "handoff", authored = true,
          domains = { "machine" },
          -- RECOVERED forbidden; INFERRED required, from "mechanical/analog vocabulary, advisory".
          required = { "car", "part", "tyre", "tire", "setup", "bolt", "corner", "rear", "front" },
          forbidden = { "odds", "board", "favorite", "claim", "poster" },
          note = "The machine: parts, setup, why this car behaves differently. Feeds Needle's counter (§3.4)." },

        { id = "rico", name = "Rico", label = "RICO", grammar = "referral", authored = true,
          domains = { "intelligence" },
          -- RECOVERED forbidden; INFERRED required, from "analytical + street, interpretive".
          required = { "know", "people", "moving", "hear", "quick", "somebody", "asking" },
          forbidden = { "odds", "chassis", "bolt", "poster", "shrine" },
          note = "Motorsport intelligence and the social connector. NOT Market Guy (§5.2). He may mention risk; `L172` means he never prices it." },

        -- ---- declared, not authored -------------------------------------------------------------------
        { id = "quinn", name = "Quickie Quinn", label = "QUINN", grammar = "referral", authored = false,
          domains = { "creation" },
          required = { "race", "road", "cars", "go", "one" },
          forbidden = { "because", "analysis", "odds", "chassis", "rep", "claim" },   -- RECOVERED
          blocked = "needs the final race-creation controls to teach against (§22); the pair is one group thread, which needs thread_id" },
        { id = "foreman", name = "Foreman", label = "FOREMAN", grammar = "referral", authored = false,
          domains = { "creation" },
          required = { "course", "field", "procedure", "configuration", "session", "start" },
          forbidden = { "lucky", "obsessed", "chassis", "favorite", "myth" },         -- RECOVERED
          blocked = "as Quinn: the pair is one group thread" },
        { id = "billie", name = "Book Queen Billie", label = "BOOK QUEEN BILLIE", grammar = "referral", authored = false,
          domains = { "wagering" },
          required = { "paper", "position", "money", "book", "risk" },
          forbidden = { "chassis", "route to", "poster", "grid is staged" },          -- RECOVERED
          blocked = "no wagering exists in Online; `L172` narrows it to self-paper only, permanently -- she may never quote a price on another player" },
        { id = "fan", name = "#1 Fan", label = "#1 FAN", grammar = "emergent", authored = false,
          domains = { "personal" },
          required = { "that", "you", "saw", "eyes" },
          forbidden = { "odds", "route", "chassis", "confirm", "discipline" },        -- RECOVERED
          blocked = "next in line (§A.8 item 3): keyed to Race Tags, never to overtakes, which Online does not count" },
        { id = "needle", name = "Needle", label = "NEEDLE", grammar = "referral", authored = false,
          domains = { "hardware" },
          required = { "questions", "answer", "where", "come from" },
          forbidden = { "odds", "board", "podium" },
          blocked = "the trust test needs thread STEPS, which nothing in Online has (§A.7)" },
        { id = "glass", name = "Glass", label = "GLASS", grammar = "emergent", authored = false,
          domains = { "intelligence" },
          required = { "know", "someone", "tell" },
          forbidden = { "odds", "chassis", "bolt" },
          blocked = "eligibility IS 'multiple unresolved Leads'; leads exist but nothing writes them yet (IDEA-625)" },
        { id = "knuckles", name = "Knuckles", label = "KNUCKLES", grammar = "emergent", authored = false,
          domains = { "laps" },
          required = { "beat", "quicker", "time", "turn" },
          forbidden = { "odds", "chassis", "poster" },
          blocked = "a claim must be stored where it cannot be mistaken for a result (§A.7); that store is unbuilt" },
        { id = "flashbulb", name = "Flashbulb", label = "FLASHBULB", grammar = "emergent", authored = false,
          domains = { "spotting" },
          required = { "seen", "scan", "eyes", "unusual" },
          forbidden = { "odds", "paper", "podium" },
          blocked = "gated on the Scanner, which the authority documents explicitly do not authorise (§A.3)" },
        { id = "mara", name = "Mara Velez", label = "MARA VELEZ", grammar = "referral", authored = false,
          domains = { "events" },
          required = { "field", "book", "drive", "rules" },
          forbidden = { "odds", "chassis", "poster" },
          blocked = "needs curated/invite-only event authoring beyond the current calendar" },
        { id = "sunday", name = "Sunday", label = "SUNDAY", grammar = "emergent", authored = false,
          domains = { "collection" },
          required = { "been", "history", "keep", "machine" },
          forbidden = { "odds", "board", "poster" },
          blocked = "provenance exists; per-chassis retention and mileage history are derivable but unstored (§A.2)" },
        { id = "patch", name = "Patch", label = "PATCH", grammar = "emergent", authored = false,
          domains = { "salvage" },
          required = { "parts", "moving", "cheap", "work" },
          forbidden = { "odds", "podium", "poster" },
          blocked = "needs a salvage market; parts economy v1 has no used/odd tier" },
        { id = "zero", name = "Zero", label = "ZERO", grammar = "emergent", authored = false,
          domains = { "laps" },
          required = { "corner", "braking", "lap", "watched" },
          forbidden = { "odds", "board", "paper" },
          blocked = "rests on ghost/practice telemetry that is deployed but has no live PASS (`L166`, MASTER_TEST BI)" },
        { id = "vale", name = "Dr. Vale", label = "DR. VALE", grammar = "referral", authored = false,
          domains = { "research" },
          required = { "catalogue", "record", "unknown", "configuration" },
          forbidden = { "odds", "poster", "chalk" },
          blocked = "name is provisional (§16); needs research submissions as a surface" },
        { id = "auntie", name = "Auntie", label = "AUNTIE", grammar = "physical", authored = false,
          domains = { "salvage", "machine" },
          required = { "looking", "hands", "parts" },
          forbidden = { "odds", "board", "podium" },
          blocked = "pure physical discovery: needs the NPC interaction prompt, whose status is UNKNOWN and CEF-budget-bound (§A.3)" },
        { id = "dave", name = "Dave", label = "DAVE", grammar = "physical", authored = false,
          domains = { "intelligence" },
          required = { "ramp", "here", "came through", "parked" },
          -- Dave must never call his gossip "intel" (§18.3). That is a voice rule, so it lives in the voice row.
          forbidden = { "intel", "odds", "chassis", "asset" },
          blocked = "as Auntie. Deliberately mundane: a parking attendant with gossip, not another cyber-noir broker" },
    }

    local byId = {}
    for _, row in ipairs(ROSTER) do
        byId[row.id] = {
            id = row.id, name = row.name, label = row.label, grammar = row.grammar,
            authored = row.authored and true or false,
            domains = set(row.domains), domainList = row.domains,
            required = row.required or {}, requiredSet = set(row.required),
            forbidden = row.forbidden or {}, forbiddenSet = set(row.forbidden),
            note = row.note, blocked = row.blocked,
        }
    end

    function M.get(id) return byId[tostring(id or "")] end

    function M.exists(id) return byId[tostring(id or "")] ~= nil end

    --- Only an authored contact may speak. A declared-but-blocked contact is a design fact, not a sender.
    function M.speakable(id)
        local c = byId[tostring(id or "")]
        if not c then return false, "unknown_contact" end
        if not c.authored then return false, "not_authored" end
        return true
    end

    --- Ids in registry order, optionally only the authored ones.
    function M.ids(authoredOnly)
        local out = {}
        for _, row in ipairs(ROSTER) do
            if not authoredOnly or byId[row.id].authored then out[#out + 1] = row.id end
        end
        return out
    end

    --- Does this contact hold that domain (§0.4)?
    function M.holds(id, domain)
        local c = byId[tostring(id or "")]
        if not c then return false end
        return c.domains[tostring(domain or "")] == true
    end

    --- Who should answer a question in this domain? Returns the first AUTHORED holder, so a redirect never
    --- points at somebody the player cannot reach. Dex is skipped as a target because Dex is the generalist
    --- doing the redirecting, not a specialist.
    function M.specialist(domain)
        domain = tostring(domain or "")
        if not M.DOMAINS[domain] then return nil, "unknown_domain" end
        for _, row in ipairs(ROSTER) do
            local c = byId[row.id]
            if c.authored and c.id ~= "dex" and c.domains[domain] then return c.id end
        end
        return nil, "no_authored_specialist"
    end

    return M
end)
