-- Schema 064: the seven-day week history rarely allows, and Moody (doc 47, L309-L310).
--
--   * `racing_week_run` learns its own length. `start_utc` / `end_utc` / `end_kind`: a run ends where its verdict says
--     (collapse | complete | unwitnessed), not at fixed hour 72. `survived`: the highest Day boundary it has lived
--     through (2 = none yet; 3 = it saw Day 4). `seed`: the run seed Moody and the verdicts draw from.
--     Every resource derives what day it is from these rows (week.clock.locate).
--   * `racing_week_verdict`: one row per possible end judged -- p, z, the draw, the state that produced them. Written
--     INSERT IGNORE: a run is judged once per boundary, ever.
--   * `racing_week_moody`: one row per roll (the n-th roll of a run is the same face from the same seed) -- d20,
--     face, what it touched, and the public line. The archive's "what kind of Racing Week was this?" reads these.
-- Replay-safe throughout.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 64,
    name = "racing_week_moody",
    statements = {
        [[ALTER TABLE racing_week_run
            ADD COLUMN IF NOT EXISTS start_utc BIGINT NULL,
            ADD COLUMN IF NOT EXISTS end_utc BIGINT NULL,
            ADD COLUMN IF NOT EXISTS end_kind VARCHAR(16) NULL,
            ADD COLUMN IF NOT EXISTS survived INT NOT NULL DEFAULT 2,
            ADD COLUMN IF NOT EXISTS seed VARCHAR(64) NULL]],
        [[CREATE TABLE IF NOT EXISTS racing_week_verdict (
            server_id VARCHAR(96) NOT NULL,
            run_index INT NOT NULL,
            boundary_h INT NOT NULL,
            kind VARCHAR(16) NOT NULL,
            p DOUBLE NOT NULL,
            z DOUBLE NOT NULL,
            u DOUBLE NOT NULL,
            state_json TEXT NOT NULL,
            at BIGINT NOT NULL,
            PRIMARY KEY (server_id, run_index, boundary_h)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
        [[CREATE TABLE IF NOT EXISTS racing_week_moody (
            server_id VARCHAR(96) NOT NULL,
            run_index INT NOT NULL,
            roll_n INT NOT NULL,
            d20 INT NOT NULL,
            face VARCHAR(32) NOT NULL,
            hours DOUBLE NOT NULL,
            data_json TEXT NOT NULL,
            at BIGINT NOT NULL,
            PRIMARY KEY (server_id, run_index, roll_n)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
}
