-- Schema 043: the conditions a human result was driven in (doc 44 §7, L226).
--
-- The Paddock calibrates its NPC pace against the server's human median for the same route, machinery band and
-- conditions. None of that was recorded: a result said who and how fast, never in what weather, on what road, at
-- what hour or in which championship's machinery. Nullable and forward-only -- history is not backfilled, because
-- a guessed condition is worse than none (L222: provenance never pretends). `conditions_source` says where the
-- stamp came from (`plan` = the persisted weather plan through `world.conditions`).
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 43,
    name = "result_conditions",
    statements = {
        [[ALTER TABLE session_result
            ADD COLUMN IF NOT EXISTS weather VARCHAR(32) NULL,
            ADD COLUMN IF NOT EXISTS road_wetness DECIMAL(4,3) NULL,
            ADD COLUMN IF NOT EXISTS seconds_of_day INT NULL,
            ADD COLUMN IF NOT EXISTS light VARCHAR(8) NULL,
            ADD COLUMN IF NOT EXISTS series_id VARCHAR(96) NULL,
            ADD COLUMN IF NOT EXISTS class_id VARCHAR(96) NULL,
            ADD COLUMN IF NOT EXISTS vehicle_class VARCHAR(32) NULL,
            ADD COLUMN IF NOT EXISTS conditions_source VARCHAR(16) NULL]],
        [[ALTER TABLE practice_run
            ADD COLUMN IF NOT EXISTS weather VARCHAR(32) NULL,
            ADD COLUMN IF NOT EXISTS road_wetness DECIMAL(4,3) NULL,
            ADD COLUMN IF NOT EXISTS seconds_of_day INT NULL,
            ADD COLUMN IF NOT EXISTS light VARCHAR(8) NULL,
            ADD COLUMN IF NOT EXISTS series_id VARCHAR(96) NULL,
            ADD COLUMN IF NOT EXISTS class_id VARCHAR(96) NULL,
            ADD COLUMN IF NOT EXISTS vehicle_class VARCHAR(32) NULL,
            ADD COLUMN IF NOT EXISTS conditions_source VARCHAR(16) NULL,
            ADD INDEX IF NOT EXISTS ix_practice_route_cond (server_id, route_id, series_id, weather)]],
        [[ALTER TABLE ghost_lap
            ADD COLUMN IF NOT EXISTS weather VARCHAR(32) NULL,
            ADD COLUMN IF NOT EXISTS road_wetness DECIMAL(4,3) NULL,
            ADD COLUMN IF NOT EXISTS seconds_of_day INT NULL,
            ADD COLUMN IF NOT EXISTS light VARCHAR(8) NULL,
            ADD COLUMN IF NOT EXISTS series_id VARCHAR(96) NULL,
            ADD COLUMN IF NOT EXISTS class_id VARCHAR(96) NULL,
            ADD COLUMN IF NOT EXISTS vehicle_class VARCHAR(32) NULL,
            ADD COLUMN IF NOT EXISTS conditions_source VARCHAR(16) NULL]],
    },
}
