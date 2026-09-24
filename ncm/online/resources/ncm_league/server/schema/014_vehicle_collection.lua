NcmSchema = NcmSchema or {}
NcmSchema[#NcmSchema + 1] = {
    version = 14,
    name = "vehicle_collection",
    statements = {
        [[CREATE TABLE IF NOT EXISTS vehicle_catalogue_generation (
            generation_id INT UNSIGNED NOT NULL,
            vehicle_count INT UNSIGNED NOT NULL,
            published_at BIGINT NOT NULL,
            PRIMARY KEY (generation_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
        [[CREATE TABLE IF NOT EXISTS vehicle_catalogue_member (
            generation_id INT UNSIGNED NOT NULL,
            vehicle_key VARCHAR(96) NOT NULL,
            PRIMARY KEY (generation_id, vehicle_key),
            CONSTRAINT fk_vehicle_catalogue_generation FOREIGN KEY (generation_id)
                REFERENCES vehicle_catalogue_generation(generation_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
        -- Discovery provenance (spec 1 §A/§B; IDEA-135..138) is in this table's FIRST version on purpose.
        -- Nobody can reconstruct who showed you a car: unlike almost everything else, this cannot be
        -- backfilled, so a discovery written before the columns existed would be sourceless forever and the
        -- Discoveries Inspired standings would start life with a hole in them.
        --
        -- The anti-farm rule needs no logic: the PRIMARY KEY is one row per (driver, server, vehicleKey), a
        -- discovery happens exactly once, and source is written on INSERT only -- deliberately NOT in the
        -- ON DUPLICATE KEY UPDATE clause, or circling past someone's car months later would silently rewrite
        -- who gets the credit.
        --
        -- `source_vehicle_key` is intentionally ABSENT. In the proximity model the discovered machine IS the
        -- source's machine, so the column could never differ from `vehicle_key`; a column that can only ever
        -- restate its neighbour is noise that later readers must still learn to distrust.
        [[CREATE TABLE IF NOT EXISTS vehicle_discovery (
            ncm_driver_id CHAR(36) NOT NULL,
            server_id VARCHAR(96) NOT NULL,
            vehicle_key VARCHAR(96) NOT NULL,
            first_discovered_at BIGINT NOT NULL,
            last_encounter_at BIGINT NOT NULL,
            encounter_count INT UNSIGNED NOT NULL DEFAULT 1,
            discovery_method VARCHAR(32) NOT NULL,
            first_runtime_record VARCHAR(160) NULL,
            -- who caused it: NULL is legitimate and means "no Driver did" (a showroom, an authored display)
            source_driver_id CHAR(36) NULL,
            -- how the source held the machine. Recorded, NOT filtered (IDEA-138): whether a freely issued car
            -- should count towards the leaderboard is undecided, and deciding it here would destroy the data
            -- needed to change our mind. `competition.discoveries` applies the policy at query time.
            source_holding ENUM('owned','team','issued','authored','unknown') NULL,
            -- reserved for persistent physical asset identity (spec 2 / IDEA-141). Nullable and unused until
            -- assetId exists: "discoveries caused by this particular car" needs it and cannot be backfilled.
            source_asset_id CHAR(36) NULL,
            PRIMARY KEY (ncm_driver_id, server_id, vehicle_key),
            KEY ix_vehicle_discovery_server_key (server_id, vehicle_key),
            -- the Discoveries Inspired standings read this way round; the window is on first_discovered_at
            -- so all-time and seasonal are the same query with different bounds
            KEY ix_vehicle_discovery_source (server_id, source_driver_id, first_discovered_at),
            CONSTRAINT fk_vehicle_discovery_driver FOREIGN KEY (ncm_driver_id)
                REFERENCES ncm_driver(ncm_driver_id),
            -- no FK on source_driver_id: a source must not be able to delete another Driver's history, and
            -- the row stays true even if that identity is later removed
            CHECK (source_driver_id IS NULL OR source_driver_id <> ncm_driver_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
}
