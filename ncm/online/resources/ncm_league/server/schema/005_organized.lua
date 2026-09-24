-- ncm_league schema 005: teams, seats, organized/invitation events, race-control audit (M4-lite; L18, L19, L45, P21).
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 5,
    name = "organized",
    statements = {
        [[CREATE TABLE IF NOT EXISTS team (
            server_id VARCHAR(96) NOT NULL,
            team_id VARCHAR(64) NOT NULL,
            pack_id VARCHAR(64) NOT NULL,
            name VARCHAR(64) NOT NULL,
            short VARCHAR(8) NOT NULL,
            colour CHAR(7) NULL,
            livery VARCHAR(64) NULL,
            seats INT NOT NULL DEFAULT 2,
            PRIMARY KEY (server_id, team_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

        [[CREATE TABLE IF NOT EXISTS seat (
            event_id VARCHAR(160) NOT NULL,
            team_id VARCHAR(64) NOT NULL,
            seat_index INT NOT NULL,
            ncm_driver_id CHAR(36) NULL,
            entry_id CHAR(36) NULL,
            offered_at BIGINT NULL,
            accepted_at BIGINT NULL,
            PRIMARY KEY (event_id, team_id, seat_index),
            KEY ix_seat_driver (ncm_driver_id),
            CONSTRAINT fk_seat_event FOREIGN KEY (event_id) REFERENCES event (event_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

        [[CREATE TABLE IF NOT EXISTS rc_audit (
            audit_id BIGINT NOT NULL AUTO_INCREMENT,
            event_id VARCHAR(160) NULL,
            session_id CHAR(36) NULL,
            actor VARCHAR(96) NOT NULL,
            action VARCHAR(32) NOT NULL,
            target_driver CHAR(36) NULL,
            value VARCHAR(64) NULL,
            reason VARCHAR(160) NULL,
            at DOUBLE NOT NULL,
            PRIMARY KEY (audit_id),
            KEY ix_audit_session (session_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

        -- Organized events: invitation-only entry, advance registration, a formation deadline.
        [[ALTER TABLE event
            ADD COLUMN invitation TINYINT(1) NOT NULL DEFAULT 0,
            ADD COLUMN registration ENUM('venue','advance') NOT NULL DEFAULT 'venue',
            ADD COLUMN seats_total INT NOT NULL DEFAULT 0,
            ADD COLUMN pack_id VARCHAR(64) NULL]],

        [[ALTER TABLE session_result MODIFY state ENUM('finished','dnf','dns','dsq') NOT NULL]],

        [[ALTER TABLE entry
            ADD COLUMN team_id VARCHAR(64) NULL,
            ADD COLUMN seat_index INT NULL,
            ADD COLUMN registered_at BIGINT NULL]],
    },
}
