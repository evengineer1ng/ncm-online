-- Schema 066: one control may command SEVERAL components (L326; the L324 brief: "another build may have several
-- propulsors controlled together"). 065 keyed a binding by (machine, control, gesture), so binding a second propulsor to
-- "triangle hold" replaced the first. The key now includes the component; the command stays a column.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 66,
    name = "binding_many",
    statements = {
        [[ALTER TABLE machine_control_binding DROP PRIMARY KEY,
            ADD PRIMARY KEY (machine_asset_id, control_key, gesture, component_asset_id)]],
    },
}
