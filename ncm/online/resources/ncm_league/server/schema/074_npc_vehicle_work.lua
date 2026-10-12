-- NPC race damage and scheduled chassis work belong to the serialized vehicle, not the race result.
NcmSchema=NcmSchema or {}
NcmSchema[#NcmSchema+1]={version=74,name="npc_vehicle_work",statements={
[[CREATE TABLE IF NOT EXISTS npc_vehicle_incident (
 server_id VARCHAR(96) NOT NULL, race_id VARCHAR(96) NOT NULL, asset_id CHAR(36) NOT NULL,
 provenance ENUM('simulated','physical') NOT NULL, damage_fraction DOUBLE NOT NULL,
 before_json MEDIUMTEXT NOT NULL, after_json MEDIUMTEXT NOT NULL, occurred_at BIGINT NOT NULL,
 PRIMARY KEY(server_id,race_id,asset_id), KEY ix_npc_vehicle_incident_asset(asset_id,occurred_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
[[CREATE TABLE IF NOT EXISTS npc_vehicle_work (
 server_id VARCHAR(96) NOT NULL, asset_id CHAR(36) NOT NULL, work_id CHAR(36) NOT NULL,
 principal_kind ENUM('org','person') NOT NULL, principal_id VARCHAR(96) NOT NULL,
 provider ENUM('self','shop') NOT NULL, state ENUM('queued','complete') NOT NULL,
 amount INT NOT NULL, material_amount INT NOT NULL, labour_amount INT NOT NULL,
 skill INT NOT NULL, start_at BIGINT NOT NULL, ready_at BIGINT NOT NULL, completed_at BIGINT NULL,
 before_json MEDIUMTEXT NOT NULL, after_json MEDIUMTEXT NULL, workmanship_json TEXT NULL,
 PRIMARY KEY(server_id,asset_id), UNIQUE KEY ux_npc_vehicle_work_id(work_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
}}
