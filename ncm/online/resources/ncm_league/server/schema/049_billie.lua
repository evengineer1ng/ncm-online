-- Schema 049: Billie's board (doc 44 §9, L224.4, L226).
--
-- A line is one market on one NPC race, VERSIONED: any tape event that touches an entrant suspends it and a new
-- version is priced, and a slip records the version it was written against, so a stale price can never be taken.
-- `refused` lines exist so Billie can say no in her own voice (a human-managed entrant); they carry no price.
-- A slip's stake, payout and refund move through `ledger` with idem keys (`billie:<kind>:<slipId>`), so a
-- settlement retried after a restart pays once.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 49,
    name = "billie",
    statements = {
        [[CREATE TABLE IF NOT EXISTS paddock_line (
            server_id VARCHAR(96) NOT NULL,
            line_id VARCHAR(120) NOT NULL,
            race_id VARCHAR(64) NOT NULL,
            market ENUM('win','podium','h2h') NOT NULL,
            subject_a VARCHAR(16) NOT NULL,
            subject_b VARCHAR(16) NULL,
            prob DECIMAL(7,6) NOT NULL,
            price DECIMAL(7,2) NULL,
            version INT NOT NULL DEFAULT 1,
            refused TINYINT(1) NOT NULL DEFAULT 0,
            state ENUM('open','suspended','closed','settled') NOT NULL DEFAULT 'open',
            PRIMARY KEY (server_id, line_id),
            KEY ix_paddock_line_race (server_id, race_id, state)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
        [[CREATE TABLE IF NOT EXISTS paddock_slip (
            slip_id CHAR(36) NOT NULL,
            idem_key VARCHAR(190) NOT NULL,
            server_id VARCHAR(96) NOT NULL,
            ncm_driver_id CHAR(36) NOT NULL,
            race_id VARCHAR(64) NOT NULL,
            line_id VARCHAR(120) NOT NULL,
            market ENUM('win','podium','h2h') NOT NULL,
            subject_a VARCHAR(16) NOT NULL,
            subject_b VARCHAR(16) NULL,
            line_version INT NOT NULL,
            stake INT NOT NULL,
            price DECIMAL(7,2) NOT NULL,
            potential INT NOT NULL,
            state ENUM('open','won','lost','void') NOT NULL DEFAULT 'open',
            payout INT NOT NULL DEFAULT 0,
            placed_at BIGINT NOT NULL,
            settled_at BIGINT NULL,
            PRIMARY KEY (slip_id),
            UNIQUE KEY ux_paddock_slip_idem (idem_key),
            KEY ix_paddock_slip_driver (server_id, ncm_driver_id, placed_at),
            KEY ix_paddock_slip_race (server_id, race_id, state),
            CONSTRAINT fk_paddock_slip_driver FOREIGN KEY (ncm_driver_id) REFERENCES ncm_driver (ncm_driver_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
}
