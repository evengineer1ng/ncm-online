-- ncm_world / client / landing_content -- the Session Landing Panel's authored content.
--
-- **Data, not layout.** `core/player/landing.lua` validates this and the page renders whatever comes back, so
-- adding a release or flipping a capability never touches markup. That was the explicit requirement.
--
-- **Only advertise what a player can actually use.** `state` is the gate and it is enforced:
--   live     offered plainly
--   partial  offered WITH its limit stated -- `landing.normalizeCapability` refuses a partial with no limit
--   soon     carried so the roadmap can live in one file, never counted as something to go and do today
--
-- Every claim below was checked against `docs/ncm-online/NOW.md` on 2026-09-27. Where a system is deployed but
-- its live proof is still owed, it is `partial` and says so. Do not promote a row to `live` because it exists
-- in the code; promote it when a player can finish the loop.
NcmLandingContent = {
    -- No hero art exists yet. Left nil deliberately: the panel is designed to look intentional without one,
    -- and a placeholder rectangle is worse than a composed type-only header.
    hero = nil,

    capabilities = {
        { id = "machine", label = "Get a machine", state = "live", reference = "market",
          detail = "The Market holds serialized cars. Each listing is one real machine -- when it sells, it is gone." },
        { id = "money", label = "Earn prize money", state = "live", reference = "guide",
          detail = "Scheduled events pay on completion and placement. Every payment leaves an itemised receipt." },
        { id = "race", label = "Enter races", state = "live", reference = "guide",
          detail = "The Race Guide carries the live calendar. Looking costs nothing; entry is a separate, paid step." },
        { id = "timetrial", label = "Run time trials", state = "live", reference = "guide",
          detail = "A field of one against the clock. Free practice and qualifying mint nothing." },
        { id = "parts", label = "Buy and fit parts", state = "live", reference = "market",
          detail = "Serialized components with real fitment rules. A part that does not fit says so before you buy." },
        { id = "index", label = "Build a Machine Index", state = "live", reference = "collection",
          detail = "What you have seen, what you own, and the evidence behind each claim." },
        { id = "wheel", label = "Drive with a wheel", state = "live", reference = "wheel",
          detail = "Multi-vendor wheel, pedal and custom-rig support with force feedback, through NCM Rig Bridge." },
        { id = "ghost", label = "Race your own ghost", state = "partial",
          limit = "Personal best only, in practice and time trials -- never in a contested race.",
          reference = "guide",
          detail = "A lap you actually drove, replayed beside you as a car that cannot be hit." },
        { id = "knowledge", label = "Record machine knowledge", state = "partial",
          limit = "Observations are recorded; there is no estimator or confidence rating yet.",
          reference = "collection",
          detail = "Measured facts about machines accumulate as you drive them." },
        { id = "weather", label = "Race the weather", state = "partial",
          limit = "Weather is synchronised and affects performance ceilings, not grip.",
          detail = "The session's sky is the same for everyone in it." },
        { id = "fuel", label = "Fuel and pit strategy", state = "soon" },
        { id = "trade", label = "Trade with other drivers", state = "partial",
          limit = "Direct synchronous Exchange only -- both Drivers must be online. Persistent listings and escrow come later.",
          reference = "trade",
          detail = "Compose one exact offer from Machines, stored Parts and eddies; both sides confirm before anything moves." },
    },

    -- Newest first is computed, not authored: `landing.payload` sorts by date then `seq`. A redeploy is not a
    -- release. If an entry would read "restarted the server", it does not belong here.
    releases = {
        {
            date = "2026-09-28", title = "Player Exchange", build = "0.5.0",
            items = {
                { heading = "Exchange", text = "F6 now carries direct Driver-to-Driver trade in the shell." },
                { heading = "Exact assets", text = "Machines, their fitted Parts, loose serialized Parts and eddies are shown by identity on both sides." },
                { heading = "Dual consent", text = "Every edit creates a new revision. Both Drivers must confirm that same revision, and the whole exchange settles together or not at all." },
                { text = "This first form is synchronous: both Drivers stay online. Persistent listings and escrow are later." },
            },
        },
        {
            date = "2026-09-27", title = "Economy v1", build = "0.5.0",
            items = {
                { heading = "Money", text = "Scheduled events now charge entry and pay out. Solo completion, contested placement and field bonuses are separate, authored figures." },
                { heading = "Receipts", text = "Every settlement writes an itemised statement you can read back. Nothing is paid twice, and an aborted event refunds." },
                { heading = "Clean driving", text = "Race Tags are awarded on the facts of your run, and clean driving carries a capped bounty." },
                { heading = "Research", text = "You can submit first-hand findings about machines you have driven." },
                { text = "Starting balance is granted once. Free practice and qualifying mint nothing." },
            },
        },
        {
            date = "2026-09-26", title = "Lap ghosts", build = "0.4.9",
            items = {
                { heading = "Practice", text = "Your personal best lap replays beside you as a car that cannot be hit, in practice and time trials." },
                { heading = "Your car", text = "The ghost wears the machine you actually set the lap in." },
                { text = "Ghosts never appear in a contested race, where another car on the road would be a lie." },
            },
        },
        {
            date = "2026-09-25", title = "Parts and the Machine Index", build = "0.4.7",
            items = {
                { heading = "Parts", text = "Serialized components with real fitment rules, bought from Market stock and fitted to a machine you own." },
                { heading = "Machine Index", text = "A record of what you have seen and owned, with the evidence behind each entry." },
                { heading = "Knowledge", text = "Driving a machine begins to record measured facts about it." },
            },
        },
        {
            date = "2026-09-22", title = "Weather, wheels and the world", build = "0.4.2",
            items = {
                { heading = "Weather", text = "The session's sky is synchronised for everyone in it, and affects what a machine can do." },
                { heading = "Rigs", text = "Multi-vendor wheel, pedal and custom-rig support with force feedback, through NCM Rig Bridge." },
                { heading = "The city", text = "NCM's named locations are on your map, and the race route draws a real GPS line." },
            },
        },
    },
}
