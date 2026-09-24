-- Content pack #2 (NCX) — v0 for M4-lite: the ten teams (core competition.teams) and the invitational
-- event template. Cars, liveries and the weekend template arrive with M7-lite/M7.
NcmPackNcx = {
    packId = "ncm_pack_ncx",
    version = "0.0.1",
    invitational = {
        seriesId = "ncx_invitational",
        seriesName = "NCX",
        rulesetId = "ncx_invitational_v0",
        entryClosesBeforeSec = 60,     -- advance registration closes when the grid forms
        venueRadiusM = 40,
        disciplineId = "ncx_formula", formatId = "sprint", classId = "ncx_rb15", laps = 1,   -- L53 vocabulary (post opts override)
    },
}
