NcmSchema=NcmSchema or {}
-- L361: the Workshop. (An engineer's competency is driver_engineering, schema 073, shared with self repair.) What
-- they KNOW of each design (the deepest teardown stage reached and the facts it revealed), and their bench projects
-- (teardown / fabricate / promote / run): materials committed and the clock started at the same moment, a claim
-- nonce so exactly one scheduler resolves each, and the result kept. Prototypes and player designs are ordinary
-- component_design / component_asset rows (origin_kind 'prototype' / 'player_design'); a nonfunctional result is an
-- asset whose lifecycle is 'junk' (L134: it persists, it cannot do the job). An asset consumed by a teardown keeps
-- its row with lifecycle 'torn_down'.
NcmSchema[#NcmSchema+1]={version=79,name="workshop",statements={
[[CREATE TABLE IF NOT EXISTS engineering_knowledge (
 server_id VARCHAR(96) NOT NULL, ncm_driver_id CHAR(36) NOT NULL, design_id VARCHAR(128) NOT NULL,
 stage INT NOT NULL DEFAULT 0, facts_json MEDIUMTEXT NOT NULL, updated_at BIGINT NOT NULL,
 PRIMARY KEY(server_id, ncm_driver_id, design_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
[[CREATE TABLE IF NOT EXISTS engineering_project (
 project_id CHAR(36) NOT NULL, idem_key VARCHAR(190) NOT NULL, server_id VARCHAR(96) NOT NULL,
 ncm_driver_id CHAR(36) NOT NULL, kind VARCHAR(16) NOT NULL, slot INT NOT NULL,
 input_json MEDIUMTEXT NOT NULL, cost INT NOT NULL, started_at BIGINT NOT NULL, due_at BIGINT NOT NULL,
 state VARCHAR(16) NOT NULL DEFAULT 'running', claim_nonce CHAR(36) NULL, outcome VARCHAR(16) NULL,
 result_json MEDIUMTEXT NULL, resolved_at BIGINT NULL, collected_at BIGINT NULL,
 PRIMARY KEY(project_id), UNIQUE KEY ux_engineering_project_idem(idem_key),
 KEY ix_engineering_project_bench(server_id, ncm_driver_id, state),
 KEY ix_engineering_project_due(server_id, state, due_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
-- a unit an engineer lists on a market names its seller; the sale pays them (component purchase, L361)
[[ALTER TABLE component_market_inventory ADD COLUMN seller_driver_id CHAR(36) NULL]],
}}
