-- ncm_league schema 010: the Race Guide (Batch 2; P47 interest as the ordinary entry, P48 on-demand practice).
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 10,
    name = "guide",
    statements = {
        -- interest: a soft entry from the Guide; it upgrades to checked_in at the venue (same entry_id, L48)
        [[ALTER TABLE entry
            MODIFY state ENUM('interested','registered','checked_in','provisioned','gridded','racing','suspended','substituted','finished','dnf','dns','dsq','withdrawn') NOT NULL DEFAULT 'checked_in',
            ADD COLUMN interested_at BIGINT NULL AFTER checked_in_at]],

        -- every completed practice run (per event); bests roll up into the Guide's leaderboard and route records
        [[CREATE TABLE IF NOT EXISTS practice_run (
            id BIGINT NOT NULL AUTO_INCREMENT,
            server_id VARCHAR(96) NOT NULL,
            event_id VARCHAR(160) NOT NULL,
            route_id VARCHAR(160) NOT NULL,
            ncm_driver_id CHAR(36) NOT NULL,
            session_id CHAR(36) NULL,
            run_ms INT NOT NULL,
            incident_ms INT NOT NULL DEFAULT 0,
            incident_count INT NOT NULL DEFAULT 0,
            at BIGINT NOT NULL,
            PRIMARY KEY (id),
            KEY ix_practice_event_driver (event_id, ncm_driver_id, run_ms),
            KEY ix_practice_route (server_id, route_id, run_ms)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
}
