-- Schema 053: the life sim (L237 M1, L240).
--
-- `paddock_climate` is the one live district climate (`life.climate`): every district's baseline, scars and axes,
-- plus the facts tallied since the last daily step, so a restart mid-day loses nothing. `paddock_climate_event` keeps
-- every regime transition with the axes and the causes that tipped it: the city's history, and WIRE's source later.
-- `paddock_trajectory` is each Driver's hidden trajectory (`life.trajectory`); it never reaches a client.
-- `paddock_place_check` is the in-engine look for every `world.places` place, like `paddock_garage_check` for
-- garages (a map pin is not a doorway): a place the owner marks `bad` leaves every person's day. All replay-safe.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 53,
    name = "paddock_life",
    statements = {
        [[CREATE TABLE IF NOT EXISTS paddock_climate (
            server_id VARCHAR(96) NOT NULL,
            day_index INT NOT NULL,
            season_id VARCHAR(16) NOT NULL,
            state_json MEDIUMTEXT NOT NULL,
            facts_json MEDIUMTEXT NOT NULL,
            updated_at BIGINT NOT NULL,
            PRIMARY KEY (server_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
        [[CREATE TABLE IF NOT EXISTS paddock_climate_event (
            server_id VARCHAR(96) NOT NULL,
            day_index INT NOT NULL,
            district VARCHAR(32) NOT NULL,
            from_regime VARCHAR(24) NOT NULL,
            to_regime VARCHAR(24) NOT NULL,
            axes_json TEXT NOT NULL,
            causes_json TEXT NOT NULL,
            scar VARCHAR(16) NOT NULL DEFAULT '',
            at BIGINT NOT NULL,
            PRIMARY KEY (server_id, day_index, district)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
        [[CREATE TABLE IF NOT EXISTS paddock_trajectory (
            server_id VARCHAR(96) NOT NULL,
            ncm_driver_id CHAR(36) NOT NULL,
            bucket VARCHAR(24) NOT NULL,
            profile_json MEDIUMTEXT NOT NULL,
            updated_at BIGINT NOT NULL,
            PRIMARY KEY (server_id, ncm_driver_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
        [[CREATE TABLE IF NOT EXISTS paddock_place_check (
            server_id VARCHAR(96) NOT NULL,
            place_id VARCHAR(48) NOT NULL,
            verdict ENUM('good','bad') NOT NULL,
            note VARCHAR(160) NOT NULL DEFAULT '',
            at BIGINT NOT NULL,
            PRIMARY KEY (server_id, place_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
}
