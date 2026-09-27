-- Schema 032: component production and manufacturer R&D claims/state.
NcmSchema=NcmSchema or {}
NcmSchema[#NcmSchema+1]={version=32,name="component_supply_rnd",statements={
[[CREATE TABLE IF NOT EXISTS component_supply_state (
 server_id VARCHAR(96) NOT NULL, market_id VARCHAR(96) NOT NULL, design_id VARCHAR(128) NOT NULL,
 next_tick_index BIGINT NOT NULL, next_tick_at BIGINT NOT NULL, batch INT NOT NULL,
 interval_sec INT NOT NULL, initial_done TINYINT(1) NOT NULL DEFAULT 0, updated_at BIGINT NOT NULL,
 PRIMARY KEY(server_id,market_id,design_id),
 CONSTRAINT fk_component_supply_design FOREIGN KEY(design_id) REFERENCES component_design(design_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
[[CREATE TABLE IF NOT EXISTS component_production_run (
 server_id VARCHAR(96) NOT NULL, market_id VARCHAR(96) NOT NULL, design_id VARCHAR(128) NOT NULL,
 tick_index BIGINT NOT NULL, tick_at BIGINT NOT NULL, claim_nonce CHAR(36) NOT NULL,
 available_before INT NOT NULL, ceiling INT NOT NULL, requested INT NOT NULL, minted INT NOT NULL DEFAULT 0,
 run_id CHAR(36) NULL, PRIMARY KEY(server_id,market_id,design_id,tick_index)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
[[CREATE TABLE IF NOT EXISTS component_rnd_state (
 server_id VARCHAR(96) NOT NULL, maker_key VARCHAR(64) NOT NULL, release_epoch BIGINT NOT NULL,
 next_run_index BIGINT NOT NULL, next_run_at BIGINT NOT NULL, logic_version INT NOT NULL, updated_at BIGINT NOT NULL,
 PRIMARY KEY(server_id,maker_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
[[CREATE TABLE IF NOT EXISTS component_rnd_run (
 server_id VARCHAR(96) NOT NULL, maker_key VARCHAR(64) NOT NULL, run_index BIGINT NOT NULL,
 evaluated_at BIGINT NOT NULL, claim_nonce CHAR(36) NOT NULL, logic_version INT NOT NULL,
 outcome VARCHAR(32) NOT NULL, reason VARCHAR(96) NOT NULL, design_id VARCHAR(128) NULL, result_json LONGTEXT NULL,
 PRIMARY KEY(server_id,maker_key,run_index), CHECK(JSON_VALID(result_json) OR result_json IS NULL)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
}}
