-- Schema 054: league driver pools (L249).
--
-- A street league is a POOL of drivers -- its teams' drivers and independents -- and each race draws who turns up
-- (`paddock.attendance`). `league_id` is a driver's street league membership; `car_json` is an independent's own car
-- (a team driver races the team's). Both NULL for everyone else. MariaDB's ADD COLUMN IF NOT EXISTS is replay-safe.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 54,
    name = "paddock_pools",
    statements = {
        [[ALTER TABLE paddock_person ADD COLUMN IF NOT EXISTS league_id VARCHAR(32) NULL]],
        [[ALTER TABLE paddock_person ADD COLUMN IF NOT EXISTS car_json TEXT NULL]],
    },
}
