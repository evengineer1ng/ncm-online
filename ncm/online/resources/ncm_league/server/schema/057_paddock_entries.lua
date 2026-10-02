-- Schema 057: humans in Paddock races (L250 steps 3-4; reverses L224.1's human-free Paddock grids).
--
-- A Paddock race becomes an ordinary calendar event of class `paddock` in ncm_league (its `event` and `entry` rows are
-- the league's as for any race); these two tables are the Paddock half.
--
--   paddock_quali   each driver's best qualifying run for a race: a solo timed run of the whole route from a standing
--                   start, any number of runs until T-11. Written by ncm_league (the session host times it). A time
--                   ENTERS the driver (owner, 2026-10-01: "quali = entry").
--   paddock_entry   the humans the Paddock grids for a race: who, their key in the Paddock (`person_key`, the 16-char
--                   id their result rows carry), their qualifying time, and -- after the race -- the result the league
--                   timed. Written by ncm_paddock from the league's `ncm:paddock.entry` / `ncm:paddock.human.result`.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 57,
    name = "paddock_entries",
    statements = {
        -- the league's event of a Paddock race has its own class; MODIFY is replay-safe (re-applying changes nothing)
        [[ALTER TABLE event MODIFY class ENUM('calendar','ambient','impromptu','organized','paddock') NOT NULL DEFAULT 'calendar']],
        [[CREATE TABLE IF NOT EXISTS paddock_quali (
            server_id VARCHAR(96) NOT NULL,
            race_id VARCHAR(64) NOT NULL,
            ncm_driver_id CHAR(36) NOT NULL,
            best_ms INT NOT NULL,
            runs INT NOT NULL DEFAULT 1,
            asset_id CHAR(36) NULL,
            last_at BIGINT NOT NULL,
            PRIMARY KEY (server_id, race_id, ncm_driver_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
        [[CREATE TABLE IF NOT EXISTS paddock_entry (
            server_id VARCHAR(96) NOT NULL,
            race_id VARCHAR(64) NOT NULL,
            ncm_driver_id CHAR(36) NOT NULL,
            person_key VARCHAR(16) NOT NULL,
            display VARCHAR(64) NOT NULL,
            series_id VARCHAR(32) NOT NULL,
            state ENUM('entered','withdrawn') NOT NULL DEFAULT 'entered',
            quali_ms INT NULL,
            asset_id CHAR(36) NULL,
            entered_at BIGINT NOT NULL,
            result_state VARCHAR(16) NULL,
            finish_ms INT NULL,
            progress_pct INT NULL,
            PRIMARY KEY (server_id, race_id, ncm_driver_id),
            KEY ix_paddock_entry_key (server_id, person_key),
            KEY ix_paddock_entry_series (server_id, ncm_driver_id, series_id, entered_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
}
