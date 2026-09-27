-- Schema 035: Economy v1 -- typed monetary references, frozen event economics and durable receipts/research.
NcmSchema = NcmSchema or {}
NcmSchema[#NcmSchema + 1] = {
    version = 35,
    name = "economy_v1",
    statements = {
        [[ALTER TABLE event
            ADD COLUMN IF NOT EXISTS economy_id VARCHAR(96) NULL,
            ADD COLUMN IF NOT EXISTS economy_version INT NULL,
            ADD COLUMN IF NOT EXISTS economy_json LONGTEXT NULL]],
        [[ALTER TABLE event
            ADD CHECK (JSON_VALID(economy_json) OR economy_json IS NULL)]],
        [[ALTER TABLE ledger
            ADD COLUMN IF NOT EXISTS event_id VARCHAR(160) NULL,
            ADD COLUMN IF NOT EXISTS session_id CHAR(36) NULL,
            ADD COLUMN IF NOT EXISTS series_id VARCHAR(96) NULL,
            ADD COLUMN IF NOT EXISTS opportunity_id VARCHAR(190) NULL]],
        [[ALTER TABLE ledger
            ADD INDEX IF NOT EXISTS ix_ledger_event (server_id, event_id, created_at),
            ADD INDEX IF NOT EXISTS ix_ledger_session (session_id, ncm_driver_id),
            ADD INDEX IF NOT EXISTS ix_ledger_opportunity (ncm_driver_id, opportunity_id, kind)]],
        [[CREATE TABLE IF NOT EXISTS session_settlement (
            session_id CHAR(36) NOT NULL,
            ncm_driver_id CHAR(36) NOT NULL,
            economy_id VARCHAR(96) NOT NULL,
            economy_version INT NOT NULL,
            time_trial TINYINT(1) NOT NULL DEFAULT 0,
            gross INT NOT NULL DEFAULT 0,
            entry_fee INT NOT NULL DEFAULT 0,
            net INT NOT NULL DEFAULT 0,
            receipt_json LONGTEXT NOT NULL,
            tags_json LONGTEXT NULL,
            settled_at BIGINT NOT NULL,
            PRIMARY KEY (session_id, ncm_driver_id),
            CHECK (JSON_VALID(receipt_json)),
            CHECK (JSON_VALID(tags_json) OR tags_json IS NULL),
            CONSTRAINT fk_settlement_session FOREIGN KEY (session_id) REFERENCES session(session_id),
            CONSTRAINT fk_settlement_driver FOREIGN KEY (ncm_driver_id) REFERENCES ncm_driver(ncm_driver_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
        [[CREATE TABLE IF NOT EXISTS research_submission (
            submission_id CHAR(36) NOT NULL,
            idem_key VARCHAR(190) NOT NULL,
            ncm_driver_id CHAR(36) NOT NULL,
            server_id VARCHAR(96) NOT NULL,
            program_id VARCHAR(96) NOT NULL,
            program_version INT NOT NULL,
            evidence_id CHAR(36) NOT NULL,
            evidence_identity VARCHAR(190) NOT NULL,
            consent_scope VARCHAR(32) NOT NULL DEFAULT 'program_use',
            state ENUM('accepted','rejected') NOT NULL,
            reason VARCHAR(96) NULL,
            amount INT NOT NULL DEFAULT 0,
            submitted_at BIGINT NOT NULL,
            PRIMARY KEY (submission_id),
            UNIQUE KEY ux_research_submission_idem (idem_key),
            UNIQUE KEY ux_research_program_evidence (ncm_driver_id, server_id, program_id, program_version, evidence_identity),
            KEY ix_research_program (program_id, program_version, state, submitted_at),
            CONSTRAINT fk_research_driver FOREIGN KEY (ncm_driver_id) REFERENCES ncm_driver(ncm_driver_id),
            CONSTRAINT fk_research_evidence FOREIGN KEY (evidence_id) REFERENCES vehicle_knowledge_evidence(evidence_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
}
