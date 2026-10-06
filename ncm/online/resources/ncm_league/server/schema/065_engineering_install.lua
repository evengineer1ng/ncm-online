-- Schema 065: the first engineering loop (L324; core `engineering.installation`, `engineering.controls`).
--
--   * `machine_configuration_item.install_json`: how a component sits on its interface -- for an add-on on a mount,
--     its FACING (where the nozzle points; the thrust axis is the reaction). NULL for every factory-interface part,
--     which has no orientation to choose. Copied forward with the item into every later configuration revision.
--   * `machine_control_binding`: which physical control commands which installed component, per Machine. A binding
--     names a component asset and one of its commands; it is never a capability. A binding to a component that is
--     no longer installed is inert and comes back if the component does (uninstall/reinstall keeps the build).
-- Replay-safe.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 65,
    name = "engineering_install",
    statements = {
        [[ALTER TABLE machine_configuration_item ADD COLUMN IF NOT EXISTS install_json LONGTEXT NULL]],
        [[CREATE TABLE IF NOT EXISTS machine_control_binding (
            machine_asset_id CHAR(36) NOT NULL,
            control_key VARCHAR(48) NOT NULL,
            gesture VARCHAR(12) NOT NULL,
            component_asset_id CHAR(36) NOT NULL,
            command VARCHAR(32) NOT NULL,
            created_by_driver_id CHAR(36) NULL,
            updated_at BIGINT NOT NULL,
            PRIMARY KEY (machine_asset_id, control_key, gesture),
            KEY ix_binding_component (component_asset_id),
            CONSTRAINT fk_binding_machine FOREIGN KEY (machine_asset_id) REFERENCES vehicle_asset(asset_id),
            CONSTRAINT fk_binding_component FOREIGN KEY (component_asset_id) REFERENCES component_asset(asset_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
}
