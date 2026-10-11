-- One-car Online loop: record the last actual drive and the vehicle's canonical damage for this week.
NcmSchema=NcmSchema or {}
NcmSchema[#NcmSchema+1]={version=73,name="week_vehicle",statements={
[[ALTER TABLE vehicle_asset ADD COLUMN IF NOT EXISTS last_driven_at BIGINT NULL]],
[[CREATE TABLE IF NOT EXISTS vehicle_week_condition (
 asset_id CHAR(36) NOT NULL, server_id VARCHAR(96) NOT NULL,
 damage_json MEDIUMTEXT NULL, recorded_at BIGINT NULL,
 PRIMARY KEY(asset_id), KEY ix_vehicle_week_condition_server(server_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
[[ALTER TABLE racing_week_anchor MODIFY source ENUM('chosen','default','last_driven') NOT NULL]],
[[CREATE TABLE IF NOT EXISTS vehicle_repair (
 repair_id CHAR(36) NOT NULL, idem_key VARCHAR(190) NOT NULL,
 server_id VARCHAR(96) NOT NULL, asset_id CHAR(36) NOT NULL, ncm_driver_id CHAR(36) NOT NULL,
 provider ENUM('self','shop') NOT NULL, before_json MEDIUMTEXT NOT NULL, after_json MEDIUMTEXT NOT NULL,
 workmanship_json TEXT NOT NULL, amount INT NOT NULL, occurred_at BIGINT NOT NULL,
 PRIMARY KEY(repair_id), UNIQUE KEY ux_vehicle_repair_idem(idem_key),
 KEY ix_vehicle_repair_asset(asset_id,occurred_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
[[CREATE TABLE IF NOT EXISTS driver_engineering (
 server_id VARCHAR(96) NOT NULL, ncm_driver_id CHAR(36) NOT NULL,
 state_json MEDIUMTEXT NOT NULL, updated_at BIGINT NOT NULL,
 PRIMARY KEY(server_id,ncm_driver_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
}}
