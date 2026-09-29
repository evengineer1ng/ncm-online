-- Schema 042: fuel belongs to the persistent Machine, never its current driver or runtime entity.
NcmSchema=NcmSchema or {}
NcmSchema[#NcmSchema+1]={version=42,name="machine_fuel",statements={
[[CREATE TABLE IF NOT EXISTS machine_fuel (
 asset_id CHAR(36) NOT NULL, fuel_ml INT UNSIGNED NOT NULL, capacity_ml INT UNSIGNED NOT NULL,
 updated_at BIGINT NOT NULL, last_station_id VARCHAR(96) NULL,
 PRIMARY KEY(asset_id), CONSTRAINT fk_machine_fuel_asset FOREIGN KEY(asset_id) REFERENCES vehicle_asset(asset_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
}}
