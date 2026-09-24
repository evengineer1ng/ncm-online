-- NCM Weather Service persistence (L87, IDEA-056/062).
-- Explicit future rows preserve the published plan across restart and generator/policy changes.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 13,
    name = "weather",
    statements = {
        [[CREATE TABLE IF NOT EXISTS weather_plan (
            scope VARCHAR(64) NOT NULL,
            epoch VARCHAR(64) NOT NULL,
            seed INT UNSIGNED NOT NULL,
            random_state INT UNSIGNED NOT NULL,
            policy_version INT UNSIGNED NOT NULL,
            generator_version INT UNSIGNED NOT NULL,
            next_index INT UNSIGNED NOT NULL,
            covered_until_utc BIGINT NOT NULL,
            last_applied_id VARCHAR(96) NULL,
            forecast_revision INT UNSIGNED NOT NULL DEFAULT 1,
            updated_at BIGINT NOT NULL,
            PRIMARY KEY (scope)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
        [[CREATE TABLE IF NOT EXISTS weather_transition (
            transition_id VARCHAR(96) NOT NULL,
            scope VARCHAR(64) NOT NULL,
            starts_at_utc BIGINT NOT NULL,
            weather VARCHAR(32) NOT NULL,
            transition_sec INT UNSIGNED NOT NULL,
            policy_version INT UNSIGNED NOT NULL,
            generator_version INT UNSIGNED NOT NULL,
            PRIMARY KEY (transition_id),
            UNIQUE KEY uq_weather_scope_start (scope, starts_at_utc),
            KEY ix_weather_scope_time (scope, starts_at_utc)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
        [[CREATE TABLE IF NOT EXISTS weather_observation (
            observation_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            observed_at_utc BIGINT NOT NULL,
            scope VARCHAR(64) NOT NULL,
            weather VARCHAR(32) NOT NULL,
            preset VARCHAR(96) NULL,
            transition_sec INT UNSIGNED NOT NULL DEFAULT 0,
            authority_epoch BIGINT NULL,
            authority_revision BIGINT NULL,
            reason VARCHAR(64) NULL,
            plan_transition_id VARCHAR(96) NULL,
            PRIMARY KEY (observation_id),
            KEY ix_weather_observed (scope, observed_at_utc)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
}
