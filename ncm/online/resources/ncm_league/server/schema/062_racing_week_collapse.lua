-- Schema 062: the collapse -- what survives a Racing Week, and the record of each reset (L303, doc 45 §P).
--
--   * `racing_week_anchor`: the cars a driver saves from a run (W-4: start with one; a second after finishing a
--     Day-3 race, a third after a Premier start). `source`: chosen by the driver, or the default (their most-raced
--     car) when they chose nothing -- which is also the founding anchor every existing garage gets (W-6).
--   * `racing_week_collapse`: one row per run end -- dry run or live, its full plan and what was done. A collapse is
--     a state machine (planned -> executing -> done | failed) and never runs twice for a run.
--   * `racing_week_genesis`: the historical seed (W-1). Every run's Paddock is born from it: the same cast, the
--     same opening standings, the same Day 1.
-- Replay-safe throughout. Nothing a collapse moves is deleted: run-local rows are re-keyed to `<server>#R<run>`.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 62,
    name = "racing_week_collapse",
    statements = {
        [[CREATE TABLE IF NOT EXISTS racing_week_anchor (
            server_id VARCHAR(96) NOT NULL,
            run_index INT NOT NULL,
            ncm_driver_id CHAR(36) NOT NULL,
            asset_id CHAR(36) NOT NULL,
            source ENUM('chosen','default') NOT NULL,
            chosen_at BIGINT NOT NULL,
            PRIMARY KEY (server_id, run_index, ncm_driver_id, asset_id),
            KEY ix_rwa_asset (asset_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
        [[CREATE TABLE IF NOT EXISTS racing_week_collapse (
            server_id VARCHAR(96) NOT NULL,
            run_index INT NOT NULL,
            mode ENUM('dryrun','live') NOT NULL,
            state ENUM('planned','executing','done','failed') NOT NULL,
            plan_json MEDIUMTEXT NOT NULL,
            result_json MEDIUMTEXT NULL,
            started_at BIGINT NOT NULL,
            finished_at BIGINT NULL,
            PRIMARY KEY (server_id, run_index, mode)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
        [[CREATE TABLE IF NOT EXISTS racing_week_genesis (
            server_id VARCHAR(96) NOT NULL,
            seed BIGINT NOT NULL,
            recorded_at BIGINT NOT NULL,
            PRIMARY KEY (server_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
}
