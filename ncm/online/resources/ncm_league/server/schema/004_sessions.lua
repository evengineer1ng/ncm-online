-- ncm_league schema 004: race sessions, results and the ledger (M3.2; L21 ledger built now, money later).
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 4,
    name = "sessions",
    statements = {
        -- Entries can now end as DNS (absent at the grid) as well as DNF/finished.
        [[ALTER TABLE entry MODIFY state ENUM('registered','checked_in','provisioned','gridded','racing','suspended','substituted','finished','dnf','dns','dsq','withdrawn') NOT NULL DEFAULT 'checked_in']],

        [[CREATE TABLE IF NOT EXISTS session (
            session_id CHAR(36) NOT NULL,
            event_id VARCHAR(160) NOT NULL,
            kind ENUM('race','qualifying','practice') NOT NULL DEFAULT 'race',
            state ENUM('forming','gridded','countdown','running','finishing','complete','cancelled') NOT NULL DEFAULT 'forming',
            starts_at BIGINT NOT NULL,
            formed_at BIGINT NULL,
            green_at DOUBLE NULL,
            completed_at DOUBLE NULL,
            complete_reason VARCHAR(48) NULL,
            entrants INT NOT NULL DEFAULT 0,
            gates INT NOT NULL DEFAULT 2,
            created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (session_id),
            KEY ix_session_event (event_id),
            CONSTRAINT fk_session_event FOREIGN KEY (event_id) REFERENCES event (event_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

        [[CREATE TABLE IF NOT EXISTS session_result (
            session_id CHAR(36) NOT NULL,
            ncm_driver_id CHAR(36) NOT NULL,
            entry_id CHAR(36) NULL,
            position INT NOT NULL,
            state ENUM('finished','dnf','dns') NOT NULL,
            total_ms INT NULL,
            penalty_ms INT NOT NULL DEFAULT 0,
            gap_ms INT NULL,
            gates_done INT NOT NULL DEFAULT 0,
            gates_total INT NOT NULL DEFAULT 2,
            jump_start TINYINT(1) NOT NULL DEFAULT 0,
            dnf_reason VARCHAR(48) NULL,
            PRIMARY KEY (session_id, ncm_driver_id),
            CONSTRAINT fk_result_session FOREIGN KEY (session_id) REFERENCES session (session_id),
            CONSTRAINT fk_result_driver FOREIGN KEY (ncm_driver_id) REFERENCES ncm_driver (ncm_driver_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

        [[CREATE TABLE IF NOT EXISTS ledger (
            ledger_id BIGINT NOT NULL AUTO_INCREMENT,
            ncm_driver_id CHAR(36) NOT NULL,
            server_id VARCHAR(96) NOT NULL,
            kind VARCHAR(48) NOT NULL,
            amount INT NOT NULL DEFAULT 0,
            currency VARCHAR(16) NOT NULL DEFAULT 'eddies',
            ref VARCHAR(160) NULL,
            note VARCHAR(160) NULL,
            created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (ledger_id),
            KEY ix_ledger_driver (ncm_driver_id, created_at),
            CONSTRAINT fk_ledger_driver FOREIGN KEY (ncm_driver_id) REFERENCES ncm_driver (ncm_driver_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
}
