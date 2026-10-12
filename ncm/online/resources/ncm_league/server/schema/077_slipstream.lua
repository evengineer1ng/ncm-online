NcmSchema=NcmSchema or {}
-- L356: a Slipstream unit's own runtime state per installation (component on a Machine). Not configuration: switching
-- a unit off is not a fit, so it never makes a configuration revision. The boot ceremony plays once per installation:
-- the same unit moved to another Machine boots again there.
NcmSchema[#NcmSchema+1]={version=77,name="slipstream_unit",statements={
[[CREATE TABLE IF NOT EXISTS slipstream_unit (
 server_id VARCHAR(96) NOT NULL, component_asset_id CHAR(36) NOT NULL, machine_asset_id CHAR(36) NOT NULL,
 enabled TINYINT NOT NULL DEFAULT 1, booted_at BIGINT NULL, updated_at BIGINT NOT NULL,
 PRIMARY KEY(component_asset_id, machine_asset_id), KEY ix_slipstream_unit_machine(machine_asset_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
}}
