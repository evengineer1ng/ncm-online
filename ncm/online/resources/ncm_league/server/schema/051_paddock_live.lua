-- Schema 051: the Paddock in the city (doc 44 §11-§12, phases 4-5).
--
-- `paddock_live` is one declared physical-authoritative race: who declared it, which backend drove it (the platform's
-- followRoute or the Pace DLL), and its verdict. `physical` means the physical classification replaced the sealed
-- sim result before the close (provenance on `paddock_race` says so); `fallback` means the sim's result stood, and
-- `reason` says why. `paddock_live_crossing` keeps every timed gate from both witnesses, the server's own samples and
-- the Pace DLL, so a verdict can be re-read later instead of trusted.
--
-- `paddock_meeting` is which Paddock people a Driver has met at their garage, and how often (talk lines vary by it).
-- `paddock_garage_check` is the in-engine look every extracted site needs (a map pin is not a doorway): a site the
-- owner marks `bad` leaves the rental pool. `paddock_org` gains the rented garage and its shift, persisted so a team
-- never moves because another folded. All replay-safe.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 51,
    name = "paddock_live",
    statements = {
        [[CREATE TABLE IF NOT EXISTS paddock_live (
            server_id VARCHAR(96) NOT NULL,
            race_id VARCHAR(64) NOT NULL,
            declared_by CHAR(36) NOT NULL,
            declared_at BIGINT NOT NULL,
            state ENUM('declared','staging','running','finished','cancelled') NOT NULL DEFAULT 'declared',
            backend VARCHAR(16) NULL,
            path_source VARCHAR(16) NULL,
            cars SMALLINT NOT NULL DEFAULT 0,
            verdict ENUM('physical','fallback') NULL,
            reason VARCHAR(160) NULL,
            go_at DOUBLE NULL,
            ended_at BIGINT NULL,
            detail_json MEDIUMTEXT NULL,
            PRIMARY KEY (server_id, race_id),
            KEY ix_paddock_live_state (server_id, state, declared_at),
            KEY ix_paddock_live_driver (declared_by, declared_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
        [[CREATE TABLE IF NOT EXISTS paddock_live_crossing (
            server_id VARCHAR(96) NOT NULL,
            race_id VARCHAR(64) NOT NULL,
            person_id VARCHAR(16) NOT NULL,
            gate SMALLINT NOT NULL,
            source ENUM('server','pace') NOT NULL,
            t_ms INT NOT NULL,
            PRIMARY KEY (server_id, race_id, person_id, gate, source)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
        [[CREATE TABLE IF NOT EXISTS paddock_meeting (
            server_id VARCHAR(96) NOT NULL,
            ncm_driver_id CHAR(36) NOT NULL,
            person_id VARCHAR(16) NOT NULL,
            first_at BIGINT NOT NULL,
            last_at BIGINT NOT NULL,
            met_count INT NOT NULL DEFAULT 1,
            PRIMARY KEY (server_id, ncm_driver_id, person_id),
            KEY ix_paddock_meeting_person (server_id, person_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
        [[CREATE TABLE IF NOT EXISTS paddock_garage_check (
            server_id VARCHAR(96) NOT NULL,
            site_id VARCHAR(8) NOT NULL,
            verdict ENUM('good','bad') NOT NULL,
            note VARCHAR(160) NULL,
            at BIGINT NOT NULL,
            PRIMARY KEY (server_id, site_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
        [[ALTER TABLE paddock_org
            ADD COLUMN IF NOT EXISTS garage_id VARCHAR(8) NULL,
            ADD COLUMN IF NOT EXISTS garage_shift VARCHAR(32) NULL]],
    },
}
