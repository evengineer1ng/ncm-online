-- Schema 023: production provenance, authoritative odometer, and a place for a death certificate.
--
-- Nothing here changes an existing identity. `asset_id` remains canonical and untouched; every column added is
-- new provenance ALONGSIDE it (addendum section 1).
--
-- ---------------------------------------------------------------------------------------------
-- The three unique indexes are the real guarantee
-- ---------------------------------------------------------------------------------------------
--
-- Ordinal allocation is done in Lua against `production_sequence` with an optimistic claim, but the thing
-- that makes "two cars can never both be Ferrari #13" TRUE rather than merely intended is the database
-- refusing it. If the allocator is ever wrong, the insert fails loudly instead of quietly duplicating
-- history. `ux_asset_*_ordinal` are per `server_id` because two worlds have separate histories.
--
-- Ordinals are NULL for assets that are not manufactured machines (admin grants, progression prizes): a
-- number must not be burned by a debugging session (addendum section 8). NULLs are distinct under a MariaDB
-- unique index, so any number of un-serialled assets coexist happily.
--
-- ---------------------------------------------------------------------------------------------
-- Backfill
-- ---------------------------------------------------------------------------------------------
--
-- Deliberately NOT done here. The ordering evidence is a join, and the assignment has to be reported asset by
-- asset -- so `NcmProvenance.backfill()` does it once at boot, in Lua, where it can log what it decided and
-- refuse if the evidence is ambiguous. A migration that silently invented history would be the worst possible
-- outcome of this release (addendum section 7).
NcmSchema = NcmSchema or {}
NcmSchema[#NcmSchema + 1] = {
    version = 23,
    name = "vehicle_identity",
    statements = {
        [[ALTER TABLE vehicle_asset
            ADD COLUMN IF NOT EXISTS origin VARCHAR(32) NOT NULL DEFAULT 'production',
            ADD COLUMN IF NOT EXISTS manufacturer_key VARCHAR(64) NULL,
            ADD COLUMN IF NOT EXISTS production_ordinal BIGINT NULL,
            ADD COLUMN IF NOT EXISTS maker_ordinal BIGINT NULL,
            ADD COLUMN IF NOT EXISTS model_ordinal BIGINT NULL,
            ADD COLUMN IF NOT EXISTS produced_at BIGINT NULL,
            ADD COLUMN IF NOT EXISTS lifecycle VARCHAR(32) NOT NULL DEFAULT 'active',
            ADD COLUMN IF NOT EXISTS lifecycle_at BIGINT NULL,
            ADD COLUMN IF NOT EXISTS lifecycle_cause VARCHAR(64) NULL,
            ADD COLUMN IF NOT EXISTS odometer_m BIGINT NOT NULL DEFAULT 0,
            ADD COLUMN IF NOT EXISTS odometer_at BIGINT NULL]],

        [[ALTER TABLE vehicle_asset
            ADD UNIQUE KEY IF NOT EXISTS ux_asset_production_ordinal (server_id, production_ordinal),
            ADD UNIQUE KEY IF NOT EXISTS ux_asset_maker_ordinal (server_id, manufacturer_key, maker_ordinal),
            ADD UNIQUE KEY IF NOT EXISTS ux_asset_model_ordinal (server_id, vehicle_key, model_ordinal)]],

        -- One row per sequence. `holder` is how a claimant learns whether it won the range it asked for,
        -- without trusting an affected-rows count -- the same pattern the production tick claim uses, for the
        -- same reason.
        [[CREATE TABLE IF NOT EXISTS production_sequence (
            server_id VARCHAR(96) NOT NULL,
            scope VARCHAR(16) NOT NULL,
            scope_key VARCHAR(96) NOT NULL,
            next_value BIGINT NOT NULL DEFAULT 1,
            holder CHAR(36) NULL,
            updated_at BIGINT NOT NULL DEFAULT 0,
            PRIMARY KEY (server_id, scope, scope_key)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
}
