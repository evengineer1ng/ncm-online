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
        -- Sponsor-funded invitational: no participant entry debit, marquee purses.
        economy = {
            id="ncx_invitational_v1",version=1,scale=250,purseTier="premier",entryFee=0,timeTrialCompletion=25000,raceCompletion=50000,
            repeatWindowSec=604800,fullRateCompletions=1,repeatFloor=5000,
            placement={[1]=100000,[2]=50000,[3]=25000},fieldBonus={perEntrant=10000,max=100000},targets={},
            tagBounties={clean_run=10000,clean_race=15000},maxTagBounty=20000,
        },
        disciplineId = "ncx_formula", formatId = "sprint", classId = "ncx_rb15", laps = 1,   -- L53 vocabulary (post opts override)
    },
}
