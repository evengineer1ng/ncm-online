-- Schema 022: dynamic manufacturer supply.
--
-- Two things become persistent, and for two different reasons.
--
-- `market_supply_state` is the LIVE PLAN: the committed next production event, the schedule chosen for it,
-- and the small profile memory (direction run, cooldown) that stops a manufacturer thrashing. It exists so a
-- restart resumes the plan instead of re-rolling it. Nothing here may be regenerated from defaults on boot --
-- that would let anyone reset every manufacturer to its starting cadence by bouncing the server, which the
-- addendum names explicitly as a hazard (section 17).
--
-- The ALTER uses ADD COLUMN IF NOT EXISTS throughout: MariaDB DDL is not transactional, so a run
-- interrupted halfway would otherwise wedge the forward-only runner on replay. Migration 019 set
-- that precedent for exactly this reason.
--
-- The columns added to `market_production_run` are the FORENSIC RECORD (section 26). A player may one day say
-- "Archer's production changed unfairly", possibly weeks later, and the answer has to be a fact rather than a
-- shrug: this profile, at this version, saw these observations, held these parameters, and chose these. The
-- signals are stored as JSON because they are evidence to read, never something to query or aggregate on.
NcmSchema = NcmSchema or {}
NcmSchema[#NcmSchema + 1] = {
    version = 22,
    name = "supply_dynamics",
    statements = {
        [[CREATE TABLE IF NOT EXISTS market_supply_state (
            server_id VARCHAR(96) NOT NULL,
            market_id VARCHAR(96) NOT NULL,
            vehicle_key VARCHAR(96) NOT NULL,
            next_tick_index BIGINT NOT NULL,
            next_tick_at BIGINT NOT NULL,
            batch INT NOT NULL,
            interval_sec INT NOT NULL,
            profile_id VARCHAR(48) NOT NULL,
            logic_version INT NOT NULL DEFAULT 0,
            sign_runs INT NOT NULL DEFAULT 0,
            last_sign INT NOT NULL DEFAULT 0,
            cycles_since_change INT NOT NULL DEFAULT 0,
            initial_done TINYINT(1) NOT NULL DEFAULT 0,
            updated_at BIGINT NOT NULL,
            PRIMARY KEY (server_id, market_id, vehicle_key)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

        [[ALTER TABLE market_production_run
            ADD COLUMN IF NOT EXISTS sold_in_cycle INT NOT NULL DEFAULT 0,
            ADD COLUMN IF NOT EXISTS was_initial TINYINT(1) NOT NULL DEFAULT 0,
            ADD COLUMN IF NOT EXISTS profile_id VARCHAR(48) NULL,
            ADD COLUMN IF NOT EXISTS logic_version INT NULL,
            ADD COLUMN IF NOT EXISTS signals_json LONGTEXT NULL,
            ADD COLUMN IF NOT EXISTS decision VARCHAR(32) NULL,
            ADD COLUMN IF NOT EXISTS next_batch INT NULL,
            ADD COLUMN IF NOT EXISTS next_interval_sec INT NULL,
            ADD COLUMN IF NOT EXISTS clamped TINYINT(1) NOT NULL DEFAULT 0]],
    },
}
