-- Schema 068 (L329, "NCM 3.0 - one universe"): where a driver canonically IS, and where host locations are.
--
--   * `ncm_presence`: one row per driver -- `place` = surface (a host location, e.g. Night City) | deep (in NCM Deep:
--     `state_json` is the `space.canonical` record) | host_surface (at a high-fidelity host's place, e.g. Laguna Seca)
--     | landed (came down somewhere while away). Host-independent: quitting in Deep leaves you in Deep; quitting at
--     Laguna Seca leaves you at Laguna Seca. `race_week_run` is the run the row was written in.
--   * `place_registry`: host locations resolved by `space.places` (verified / resolved / unresolved + provenance).
-- Replay-safe.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 68,
    name = "presence_places",
    statements = {
        [[CREATE TABLE IF NOT EXISTS ncm_presence (
            driver_id CHAR(36) NOT NULL,
            server_id VARCHAR(64) NOT NULL,
            place VARCHAR(16) NOT NULL,
            host VARCHAR(32) NULL,
            location_id VARCHAR(96) NULL,
            state_json LONGTEXT NULL,
            race_week_run INT NULL,
            updated_at BIGINT NOT NULL,
            PRIMARY KEY (driver_id, server_id)
        )]],
        [[CREATE TABLE IF NOT EXISTS place_registry (
            place_id VARCHAR(96) NOT NULL,
            host VARCHAR(32) NOT NULL,
            track VARCHAR(96) NULL,
            layout VARCHAR(96) NULL,
            name VARCHAR(160) NULL,
            lat DOUBLE NULL,
            lon DOUBLE NULL,
            alt DOUBLE NULL,
            tz DOUBLE NULL,
            status VARCHAR(16) NOT NULL,
            provenance VARCHAR(96) NOT NULL,
            flags_json LONGTEXT NULL,
            updated_at BIGINT NOT NULL,
            PRIMARY KEY (place_id)
        )]],
    },
}
