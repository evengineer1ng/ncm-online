-- Schema 069: a component's own consumable state (L334). The Propellant Tank PT-500 carries the Fusion Drive's
-- propellant itself -- not the car's fuel -- so its fill belongs to the tank (the serialized component), and goes with it
-- if it is moved to another Machine or sold. One row per component that has such state; a tank with no row is full.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 69,
    name = "component_state",
    statements = {
        [[CREATE TABLE IF NOT EXISTS component_state (
            asset_id CHAR(36) NOT NULL,
            propellant_kg DOUBLE NOT NULL,
            updated_at BIGINT NOT NULL,
            PRIMARY KEY (asset_id),
            CONSTRAINT fk_component_state_asset FOREIGN KEY (asset_id) REFERENCES component_asset(asset_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
}
