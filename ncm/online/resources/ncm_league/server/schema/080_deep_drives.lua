NcmSchema=NcmSchema or {}
-- Doc 58: NCM Deep's experimental propulsion stable.
--   owner_grant_ledger     every owner grant spec ever applied (a spec is applied once: the 2026-10-11 persistence fix)
--   deep_lab_log           every developer test-drive override applied to a Machine (the propulsion laboratory)
--   deep_drive_activation  one row per drive activation (impulse, fusion, warp, alcubierre, jump, wormhole)
--   deep_dev_checkpoint    the Machine's state before each exotic activation (developer-only restore)
--   deep_travel            per Machine: path travelled vs discontinuous displacement vs Earth distance (Race Week)
--   deep_wormhole          wormholes (both mouths, identity, life): reusable for F-I-S-H-I-N-G / Nessie
NcmSchema[#NcmSchema+1]={version=80,name="deep_drives",statements={
[[CREATE TABLE IF NOT EXISTS owner_grant_ledger (
 spec VARCHAR(190) NOT NULL, server_id VARCHAR(96) NOT NULL, driver_id CHAR(36) NULL, asset_id CHAR(36) NULL,
 kit VARCHAR(64) NOT NULL, applied_at BIGINT NOT NULL, result_json MEDIUMTEXT NULL,
 PRIMARY KEY(spec)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
[[CREATE TABLE IF NOT EXISTS deep_lab_log (
 id BIGINT NOT NULL AUTO_INCREMENT, server_id VARCHAR(96) NOT NULL, driver_id CHAR(36) NOT NULL, asset_id CHAR(36) NOT NULL,
 drive VARCHAR(32) NOT NULL, spec VARCHAR(190) NOT NULL, applied_at BIGINT NOT NULL, detail_json MEDIUMTEXT NULL,
 PRIMARY KEY(id), KEY ix_deep_lab_asset(asset_id, applied_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
[[CREATE TABLE IF NOT EXISTS deep_drive_activation (
 activation_id VARCHAR(96) NOT NULL, server_id VARCHAR(96) NOT NULL, driver_id CHAR(36) NOT NULL, asset_id CHAR(36) NOT NULL,
 player_id INT NULL, host VARCHAR(32) NOT NULL, drive VARCHAR(32) NOT NULL, code VARCHAR(32) NULL,
 started_utc DOUBLE NOT NULL, ended_utc DOUBLE NULL, start_pos_json TEXT NULL, end_pos_json TEXT NULL,
 start_vel_json TEXT NULL, end_vel_json TEXT NULL, start_earth_m DOUBLE NULL, end_earth_m DOUBLE NULL,
 path_m DOUBLE NULL, endpoint_m DOUBLE NULL, sim_s DOUBLE NULL, real_s DOUBLE NULL,
 target VARCHAR(64) NULL, charge_start DOUBLE NULL, charge_used DOUBLE NULL, fuel_used_kg DOUBLE NULL, fusion_used_kg DOUBLE NULL,
 frame_start VARCHAR(190) NULL, frame_end VARCHAR(190) NULL, soi_end VARCHAR(64) NULL,
 ok TINYINT NULL, reason VARCHAR(190) NULL, detail_json MEDIUMTEXT NULL, stream_count INT NOT NULL DEFAULT 0,
 last_stream_json TEXT NULL, updated_at BIGINT NOT NULL,
 PRIMARY KEY(activation_id), KEY ix_deep_drive_asset(asset_id, started_utc), KEY ix_deep_drive_kind(drive, started_utc)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
[[CREATE TABLE IF NOT EXISTS deep_dev_checkpoint (
 activation_id VARCHAR(96) NOT NULL, server_id VARCHAR(96) NOT NULL, driver_id CHAR(36) NOT NULL, asset_id CHAR(36) NOT NULL,
 created_at BIGINT NOT NULL, presence_json MEDIUMTEXT NULL, dynamics_json MEDIUMTEXT NULL, components_json MEDIUMTEXT NULL,
 restored_at BIGINT NULL, restored_by VARCHAR(190) NULL,
 PRIMARY KEY(activation_id), KEY ix_deep_ckpt_asset(asset_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
[[CREATE TABLE IF NOT EXISTS deep_travel (
 asset_id CHAR(36) NOT NULL, server_id VARCHAR(96) NOT NULL, driver_id CHAR(36) NOT NULL,
 path_m DOUBLE NOT NULL DEFAULT 0, discontinuous_m DOUBLE NOT NULL DEFAULT 0, max_earth_m DOUBLE NOT NULL DEFAULT 0,
 current_earth_m DOUBLE NOT NULL DEFAULT 0, ledger_json MEDIUMTEXT NULL, updated_at BIGINT NOT NULL,
 PRIMARY KEY(asset_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
[[CREATE TABLE IF NOT EXISTS deep_wormhole (
 wormhole_id VARCHAR(96) NOT NULL, server_id VARCHAR(96) NOT NULL, owner_asset_id CHAR(36) NULL, origin VARCHAR(16) NOT NULL,
 state VARCHAR(64) NOT NULL, opened_utc DOUBLE NOT NULL, lifetime_s DOUBLE NULL, record_json MEDIUMTEXT NULL, updated_at BIGINT NOT NULL,
 PRIMARY KEY(wormhole_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
}}
