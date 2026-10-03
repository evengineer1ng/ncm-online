-- Schema 058: NPC race cars are real cars (L298; audit L297, KB-313).
--
--   * `paddock_person.race_car_id` / `last_shop_at`: the vehicle_asset a Paddock driver races (an independent's own,
--     or the team car they are assigned to), and when they last shopped -- persisted, so a server restart no longer
--     sends the same independents back to the shelves (KB-312).
--   * `component_service.by_driver_id` becomes nullable and gains `by_principal_kind/id`: an NPC services its parts
--     through the same append-only history a player's do (`parts.wear` reads it either way).
--   * `npc_money.reason` / `goal`: why the money moved (owner: "goal -> need -> search -> affordability -> purchase").
--   * transfer `principal` / `reason` columns: who an NPC transfer was to or from, and why, on both asset kinds.
-- Replay-safe throughout.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 58,
    name = "npc_garage",
    statements = {
        [[ALTER TABLE paddock_person
            ADD COLUMN IF NOT EXISTS race_car_id CHAR(36) NULL,
            ADD COLUMN IF NOT EXISTS last_shop_at BIGINT NULL]],
        [[ALTER TABLE component_service MODIFY by_driver_id CHAR(36) NULL]],
        [[ALTER TABLE component_service
            ADD COLUMN IF NOT EXISTS by_principal_kind VARCHAR(16) NULL,
            ADD COLUMN IF NOT EXISTS by_principal_id VARCHAR(64) NULL]],
        [[ALTER TABLE npc_money
            ADD COLUMN IF NOT EXISTS reason VARCHAR(48) NULL,
            ADD COLUMN IF NOT EXISTS goal VARCHAR(160) NULL]],
        [[ALTER TABLE component_asset_transfer
            ADD COLUMN IF NOT EXISTS from_principal VARCHAR(80) NULL,
            ADD COLUMN IF NOT EXISTS to_principal VARCHAR(80) NULL,
            ADD COLUMN IF NOT EXISTS reason VARCHAR(48) NULL]],
        [[ALTER TABLE vehicle_asset_transfer
            ADD COLUMN IF NOT EXISTS from_principal VARCHAR(80) NULL,
            ADD COLUMN IF NOT EXISTS to_principal VARCHAR(80) NULL,
            ADD COLUMN IF NOT EXISTS reason VARCHAR(48) NULL]],
    },
}
