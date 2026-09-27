-- ncm_league schema 034: stored lap ghosts (L166).
--
-- A ghost is an IMMUTABLE record of one lap somebody actually drove. Rows are never updated: a faster lap is
-- a new row and "my best" is a query. That is deliberate and load-bearing -- it is what lets telemetry
-- retention be added later without a cleanup silently deleting the laps a leaderboard is built on.
--
-- This is a separate store from `telemetry_chunk` on purpose. That table is the incident/progress stream:
-- sampled from the driver's body rather than the car, carrying no heading, quantised to 10 cm on the way in,
-- gated on a `telemetryPersist` switch, and with no version column to identify what a row's format ever was.
-- A ghost needs the car's own pose, a heading, and a format it can refuse.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 34,
    name = "ghost_lap",
    statements = {
        [[CREATE TABLE IF NOT EXISTS ghost_lap (
            ghost_id CHAR(36) NOT NULL,
            -- replay.pose.FORMAT. A reader that meets a format it does not know refuses by name rather than
            -- decoding a positional array against the wrong field order.
            format SMALLINT NOT NULL,
            server_id VARCHAR(96) NOT NULL,
            ncm_driver_id CHAR(36) NOT NULL,
            session_id CHAR(36) NULL,
            event_id VARCHAR(160) NULL,
            route_id VARCHAR(160) NOT NULL,
            discipline_id VARCHAR(96) NULL,
            ruleset_id VARCHAR(96) NULL,
            class_id VARCHAR(96) NULL,
            laps INT NOT NULL DEFAULT 1,
            -- The interval the lap occupies, on the same server clock telemetry_chunk.t_from/t_to use, so a
            -- ghost can be located against the stream it was driven through.
            run_started_at DOUBLE NOT NULL,
            run_finished_at DOUBLE NOT NULL,
            elapsed_ms INT NOT NULL,
            incident_ms INT NOT NULL DEFAULT 0,
            -- Machine identity, latched when the START line was crossed. `record` is what the ghost wears.
            asset_id CHAR(36) NULL,
            record VARCHAR(256) NULL,
            appearance VARCHAR(128) NULL,
            configuration_ref CHAR(36) NULL,
            pose_count INT NOT NULL,
            pose_hz SMALLINT NOT NULL,
            poses_json MEDIUMTEXT NOT NULL,
            -- 'personal' now; 'session' and 'route' need server corroboration and consent (L166).
            tier VARCHAR(16) NOT NULL DEFAULT 'personal',
            published TINYINT(1) NOT NULL DEFAULT 0,
            server_corroborated TINYINT(1) NOT NULL DEFAULT 0,
            at BIGINT NOT NULL,
            PRIMARY KEY (ghost_id),
            KEY ix_ghost_best (server_id, route_id, ncm_driver_id, elapsed_ms),
            KEY ix_ghost_route (server_id, route_id, tier, published, elapsed_ms),
            KEY ix_ghost_driver_at (ncm_driver_id, at),
            CONSTRAINT ck_ghost_poses_json CHECK (JSON_VALID(poses_json))
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

        -- `IF NOT EXISTS` on every ADD is load-bearing, not decoration (see schema 019): a plain ADD COLUMN is
        -- not replay-safe, MariaDB commits DDL implicitly, and if a later statement here failed the version
        -- row would not be written -- so the next start would replay this list and wedge the runner on a
        -- duplicate-column error.
        --
        -- These three are the boundaries that were missing. `at` is second-granular and `run_ms` already
        -- includes the incident penalty, so no arithmetic over the existing columns can recover the interval
        -- a practice lap occupied.
        [[ALTER TABLE practice_run
            ADD COLUMN IF NOT EXISTS run_started_at DOUBLE NULL AFTER session_id,
            ADD COLUMN IF NOT EXISTS run_finished_at DOUBLE NULL AFTER run_started_at,
            ADD COLUMN IF NOT EXISTS ghost_id CHAR(36) NULL AFTER incident_count]],
    },
}
