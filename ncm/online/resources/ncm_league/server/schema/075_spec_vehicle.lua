-- Each spec-series entrant borrows one serialized organiser car for the Week.
NcmSchema=NcmSchema or {}
NcmSchema[#NcmSchema+1]={version=75,name="spec_vehicle",statements={
[[CREATE TABLE IF NOT EXISTS paddock_spec_car (
 server_id VARCHAR(96) NOT NULL, series_id VARCHAR(64) NOT NULL, person_id VARCHAR(64) NOT NULL,
 asset_id CHAR(36) NOT NULL, cash BIGINT NOT NULL, created_at BIGINT NOT NULL,
 PRIMARY KEY(server_id,series_id,person_id), UNIQUE KEY ux_paddock_spec_asset(asset_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
[[ALTER TABLE npc_vehicle_work MODIFY principal_kind ENUM('org','person','series') NOT NULL]],
}}
