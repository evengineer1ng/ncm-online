-- Schema 044: human sanctioned organizations (doc 14 §3 FOUNDATION step 3-5; doc 44 phase 2).
--
-- Identity only, no economics: an organization can be founded, branded, owned and hold a charter, and its entries
-- snapshot it. Ownership and branding are DATED relationships, never columns (doc 14 §16, L94), and nothing is
-- deleted (§18). The One-Team Rule lives in `team_affiliation` (schema 046), shared with the NPC circuit. There is
-- no team-management UI (doc 14 DO-NOT-BUILD still holds for sanctioned team management); the Paddock DIRECTORY
-- lists these read-only.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 44,
    name = "organizations",
    statements = {
        [[CREATE TABLE IF NOT EXISTS organization (
            organization_id CHAR(36) NOT NULL,
            server_id VARCHAR(96) NOT NULL,
            lifecycle_state ENUM('active','inactive','dormant','folded') NOT NULL DEFAULT 'active',
            founded_at BIGINT NOT NULL,
            PRIMARY KEY (organization_id),
            KEY ix_organization_server (server_id, lifecycle_state)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
        [[CREATE TABLE IF NOT EXISTS organization_branding (
            organization_id CHAR(36) NOT NULL,
            name VARCHAR(64) NOT NULL,
            short VARCHAR(8) NOT NULL,
            colour VARCHAR(16) NULL,
            livery VARCHAR(128) NULL,
            effective_from BIGINT NOT NULL,
            effective_to BIGINT NULL,
            approved_by VARCHAR(96) NULL,
            approval_ref VARCHAR(96) NULL,
            PRIMARY KEY (organization_id, effective_from),
            CONSTRAINT fk_org_branding_org FOREIGN KEY (organization_id) REFERENCES organization (organization_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
        [[CREATE TABLE IF NOT EXISTS organization_ownership (
            organization_id CHAR(36) NOT NULL,
            owner_principal_kind VARCHAR(16) NOT NULL,
            owner_principal_id VARCHAR(96) NOT NULL,
            effective_from BIGINT NOT NULL,
            effective_to BIGINT NULL,
            acquired_via ENUM('founded','purchased','transferred','governance_reallocation') NOT NULL,
            PRIMARY KEY (organization_id, effective_from),
            CONSTRAINT fk_org_ownership_org FOREIGN KEY (organization_id) REFERENCES organization (organization_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
        [[CREATE TABLE IF NOT EXISTS sporting_charter (
            charter_id CHAR(36) NOT NULL,
            server_id VARCHAR(96) NOT NULL,
            series_id VARCHAR(96) NOT NULL,
            held_by_organization_id CHAR(36) NULL,
            effective_from BIGINT NOT NULL,
            effective_to BIGINT NULL,
            PRIMARY KEY (charter_id),
            KEY ix_charter_series (server_id, series_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
        [[CREATE TABLE IF NOT EXISTS settlement (
            settlement_id CHAR(36) NOT NULL,
            server_id VARCHAR(96) NOT NULL,
            event_id VARCHAR(160) NOT NULL,
            organization_id CHAR(36) NULL,
            inputs_json JSON NULL,
            status VARCHAR(16) NOT NULL,
            idem_key VARCHAR(190) NOT NULL,
            created_at BIGINT NOT NULL,
            PRIMARY KEY (settlement_id),
            UNIQUE KEY ux_settlement_idem (idem_key)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
        [[ALTER TABLE entry
            ADD COLUMN IF NOT EXISTS entry_type ENUM('team','privateer') NOT NULL DEFAULT 'privateer',
            ADD COLUMN IF NOT EXISTS organization_id CHAR(36) NULL,
            ADD COLUMN IF NOT EXISTS assigned_asset_id CHAR(36) NULL]],
    },
}
