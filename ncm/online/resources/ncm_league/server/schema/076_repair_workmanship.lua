NcmSchema=NcmSchema or {}
NcmSchema[#NcmSchema+1]={version=76,name="repair_workmanship",statements={
[[ALTER TABLE vehicle_week_condition ADD COLUMN IF NOT EXISTS repair_json TEXT NULL]],
[[CREATE TABLE IF NOT EXISTS vehicle_repair_correction (
 repair_id CHAR(36) NOT NULL, server_id VARCHAR(96) NOT NULL, asset_id CHAR(36) NOT NULL,
 old_json MEDIUMTEXT NOT NULL, new_json MEDIUMTEXT NOT NULL, corrected_at BIGINT NOT NULL,
 PRIMARY KEY(repair_id), KEY ix_vehicle_repair_correction_asset(asset_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
}}
