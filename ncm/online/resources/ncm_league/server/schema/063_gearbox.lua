-- Schema 063: every machine's gearbox (L306; core `machine.gearbox`).
--
-- Decided at manufacture and never rewritten: `gearbox_kind` automatic | manual, `gearbox_spec` the spec id (`a`, `m5`,
-- `m6o`...), `gearbox_source` factory | pre_gearbox, `gearbox_at` when it was stamped. Owner ruling 3: every car
-- someone already owns -- a driver, a team or an independent -- is an automatic from before gearboxes existed.
-- Unsold shelf stock is rolled from its model's factory mix at the next boot (`NcmGearbox.backfillShelf`, Lua,
-- because the roll is the core's hash), and every car minted from now on is stamped in its own INSERT.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 63,
    name = "gearbox",
    statements = {
        [[ALTER TABLE vehicle_asset
            ADD COLUMN IF NOT EXISTS gearbox_kind VARCHAR(12) NULL,
            ADD COLUMN IF NOT EXISTS gearbox_spec VARCHAR(8) NULL,
            ADD COLUMN IF NOT EXISTS gearbox_source VARCHAR(16) NULL,
            ADD COLUMN IF NOT EXISTS gearbox_at BIGINT NULL]],
        [[UPDATE vehicle_asset
            SET gearbox_kind = 'automatic', gearbox_spec = 'a', gearbox_source = 'pre_gearbox', gearbox_at = UNIX_TIMESTAMP()
            WHERE gearbox_kind IS NULL AND (ncm_driver_id IS NOT NULL OR owner_principal_kind IS NOT NULL)]],
    },
}
