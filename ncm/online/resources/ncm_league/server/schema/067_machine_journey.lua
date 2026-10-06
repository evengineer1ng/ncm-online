-- Schema 067: one physical journey of a Machine (owner, 2026-10-06, "NCM 3.0 post-Laguna" item 9: measure journeys
-- such as Night City -> Laguna Seca as competition later). Recorded by `ncm_world/server/journey.lua` from what NCM
-- already observes: Deep entry, the trajectory (1 Hz), peaks, thermal events, propellant, Guidance, the embodiment
-- (physicalization, touchdown in the host), departure and the outcome. No scores, no XP: the facts a race could be
-- built from later. `summary_json` is the record; `trace_json` the 1 Hz trajectory. Replay-safe.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 67,
    name = "machine_journey",
    statements = {
        [[CREATE TABLE IF NOT EXISTS machine_journey (
            journey_id CHAR(36) NOT NULL,
            server_id VARCHAR(64) NOT NULL,
            driver_id CHAR(36) NULL,
            machine_asset_id CHAR(36) NULL,
            origin VARCHAR(64) NOT NULL,
            destination VARCHAR(64) NULL,
            outcome VARCHAR(48) NOT NULL,
            started_at BIGINT NOT NULL,
            ended_at BIGINT NOT NULL,
            elapsed_s DOUBLE NOT NULL,
            summary_json LONGTEXT NOT NULL,
            trace_json LONGTEXT NULL,
            PRIMARY KEY (journey_id),
            KEY machine_journey_driver (driver_id, started_at),
            KEY machine_journey_destination (destination, started_at)
        )]],
    },
}
