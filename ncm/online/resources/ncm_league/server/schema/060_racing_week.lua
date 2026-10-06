-- Schema 060: Racing Week's curve has a memory and a provenance (L302, doc 45 §N).
--
--   * `racing_week_run`: one row per reconstruction -- the live signal (deviation, latched steps) as of its last step,
--     so a restart resumes the run instead of forgetting how it has gone.
--   * `racing_week_event`: what happened, append-only, written INSERT IGNORE on a natural key -- an announcement
--     fires once per run (`step`/<id>), and the curve is sampled once per run hour (`sample`/<hour>): carrier,
--     tolerance, deviation and the facts that moved it. The archive's "what kind of Racing Week was this?" reads these.
-- Replay-safe throughout.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 60,
    name = "racing_week",
    statements = {
        [[CREATE TABLE IF NOT EXISTS racing_week_run (
            server_id VARCHAR(96) NOT NULL,
            run_index INT NOT NULL,
            opened_at BIGINT NOT NULL,
            state_json MEDIUMTEXT NOT NULL,
            updated_at BIGINT NOT NULL,
            PRIMARY KEY (server_id, run_index)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
        [[CREATE TABLE IF NOT EXISTS racing_week_event (
            server_id VARCHAR(96) NOT NULL,
            run_index INT NOT NULL,
            kind ENUM('step','sample') NOT NULL,
            ref VARCHAR(48) NOT NULL,
            hours DOUBLE NOT NULL,
            data_json TEXT NOT NULL,
            at BIGINT NOT NULL,
            PRIMARY KEY (server_id, run_index, kind, ref)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
}
