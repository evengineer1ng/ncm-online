-- Schema 031: immutable component Designs, physical assets, custody and Machine configuration snapshots.
NcmSchema=NcmSchema or {}
NcmSchema[#NcmSchema+1]={version=31,name="component_assets",statements={
[[CREATE TABLE IF NOT EXISTS component_design (
 design_id VARCHAR(128) NOT NULL, lineage_id VARCHAR(128) NOT NULL, revision INT NOT NULL,
 manufacturer_key VARCHAR(64) NOT NULL, display_manufacturer VARCHAR(96) NOT NULL,
 code VARCHAR(96) NOT NULL, subtitle VARCHAR(128) NOT NULL, family VARCHAR(48) NOT NULL,
 tier VARCHAR(32) NOT NULL, effect DECIMAL(6,3) NOT NULL, price INT UNSIGNED NOT NULL,
 fidelity VARCHAR(24) NOT NULL, distribution VARCHAR(32) NOT NULL, origin_kind VARCHAR(32) NOT NULL,
 positions_json LONGTEXT NOT NULL, fitment_json LONGTEXT NOT NULL, created_at BIGINT NOT NULL,
 PRIMARY KEY(design_id), UNIQUE KEY ux_component_code(code),
 CHECK(effect>0), CHECK(JSON_VALID(positions_json)), CHECK(JSON_VALID(fitment_json))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
[[CREATE TABLE IF NOT EXISTS component_manufacturing_run (
 run_id CHAR(36) NOT NULL, server_id VARCHAR(96) NOT NULL, design_id VARCHAR(128) NOT NULL,
 allocation_key VARCHAR(190) NOT NULL, quantity INT UNSIGNED NOT NULL, produced_at BIGINT NOT NULL,
 PRIMARY KEY(run_id), UNIQUE KEY ux_component_run_allocation(server_id,allocation_key),
 CONSTRAINT fk_component_run_design FOREIGN KEY(design_id) REFERENCES component_design(design_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
[[CREATE TABLE IF NOT EXISTS component_asset (
 asset_id CHAR(36) NOT NULL, server_id VARCHAR(96) NOT NULL, design_id VARCHAR(128) NOT NULL,
 run_id CHAR(36) NULL, ncm_driver_id CHAR(36) NULL, manufacturer_key VARCHAR(64) NOT NULL,
 location_kind VARCHAR(24) NOT NULL,
 machine_asset_id CHAR(36) NULL, global_ordinal BIGINT NULL, maker_ordinal BIGINT NULL,
 design_ordinal BIGINT NULL, factory_original TINYINT(1) NOT NULL DEFAULT 0,
 acquired_via VARCHAR(32) NULL, acquired_at BIGINT NULL, exposure_m BIGINT NOT NULL DEFAULT 0,
 created_at BIGINT NOT NULL, lifecycle VARCHAR(24) NOT NULL DEFAULT 'active',
 PRIMARY KEY(asset_id), KEY ix_component_owner(server_id,ncm_driver_id,location_kind),
 KEY ix_component_machine(machine_asset_id,location_kind),
 UNIQUE KEY ux_component_global(server_id,global_ordinal),
 UNIQUE KEY ux_component_maker(server_id,manufacturer_key,maker_ordinal),
 UNIQUE KEY ux_component_design(server_id,design_id,design_ordinal),
 CONSTRAINT fk_component_asset_design FOREIGN KEY(design_id) REFERENCES component_design(design_id),
 CONSTRAINT fk_component_asset_run FOREIGN KEY(run_id) REFERENCES component_manufacturing_run(run_id),
 CONSTRAINT fk_component_asset_driver FOREIGN KEY(ncm_driver_id) REFERENCES ncm_driver(ncm_driver_id),
 CONSTRAINT fk_component_asset_machine FOREIGN KEY(machine_asset_id) REFERENCES vehicle_asset(asset_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
[[CREATE TABLE IF NOT EXISTS component_market_inventory (
 market_id VARCHAR(96) NOT NULL, asset_id CHAR(36) NOT NULL, price INT UNSIGNED NOT NULL,
 state VARCHAR(24) NOT NULL, listed_at BIGINT NOT NULL, sold_at BIGINT NULL, sold_to_driver_id CHAR(36) NULL,
 PRIMARY KEY(market_id,asset_id), KEY ix_component_market_state(market_id,state,listed_at),
 CONSTRAINT fk_component_market_market FOREIGN KEY(market_id) REFERENCES market(market_id),
 CONSTRAINT fk_component_market_asset FOREIGN KEY(asset_id) REFERENCES component_asset(asset_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
[[CREATE TABLE IF NOT EXISTS component_asset_transfer (
 transfer_id CHAR(36) NOT NULL, idem_key VARCHAR(190) NOT NULL, server_id VARCHAR(96) NOT NULL,
 asset_id CHAR(36) NOT NULL, from_driver_id CHAR(36) NULL, to_driver_id CHAR(36) NULL,
 kind VARCHAR(32) NOT NULL, market_id VARCHAR(96) NULL, amount INT NULL, occurred_at BIGINT NOT NULL,
 PRIMARY KEY(transfer_id), UNIQUE KEY ux_component_transfer_idem(idem_key),
 KEY ix_component_transfer_asset(asset_id,occurred_at),
 CONSTRAINT fk_component_transfer_asset FOREIGN KEY(asset_id) REFERENCES component_asset(asset_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
[[CREATE TABLE IF NOT EXISTS machine_configuration (
 configuration_id CHAR(36) NOT NULL, machine_asset_id CHAR(36) NOT NULL, revision INT UNSIGNED NOT NULL,
 operation_id CHAR(36) NULL, created_at BIGINT NOT NULL, created_by_driver_id CHAR(36) NULL,
 PRIMARY KEY(configuration_id), UNIQUE KEY ux_machine_configuration_revision(machine_asset_id,revision),
 CONSTRAINT fk_machine_configuration_asset FOREIGN KEY(machine_asset_id) REFERENCES vehicle_asset(asset_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
[[CREATE TABLE IF NOT EXISTS machine_configuration_item (
 configuration_id CHAR(36) NOT NULL, interface_id VARCHAR(96) NOT NULL, component_asset_id CHAR(36) NOT NULL,
 PRIMARY KEY(configuration_id,interface_id), KEY ix_configuration_component(component_asset_id),
 CONSTRAINT fk_configuration_item_config FOREIGN KEY(configuration_id) REFERENCES machine_configuration(configuration_id),
 CONSTRAINT fk_configuration_item_component FOREIGN KEY(component_asset_id) REFERENCES component_asset(asset_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
[[CREATE TABLE IF NOT EXISTS machine_configuration_current (
 machine_asset_id CHAR(36) NOT NULL, configuration_id CHAR(36) NOT NULL,
 PRIMARY KEY(machine_asset_id), UNIQUE KEY ux_current_configuration(configuration_id),
 CONSTRAINT fk_current_machine FOREIGN KEY(machine_asset_id) REFERENCES vehicle_asset(asset_id),
 CONSTRAINT fk_current_configuration FOREIGN KEY(configuration_id) REFERENCES machine_configuration(configuration_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
[[CREATE TABLE IF NOT EXISTS component_operation (
 operation_id CHAR(36) NOT NULL, idem_key VARCHAR(190) NOT NULL, server_id VARCHAR(96) NOT NULL,
 ncm_driver_id CHAR(36) NOT NULL, machine_asset_id CHAR(36) NOT NULL, component_asset_id CHAR(36) NOT NULL,
 old_configuration_id CHAR(36) NOT NULL, new_configuration_id CHAR(36) NOT NULL,
 kind VARCHAR(32) NOT NULL, occurred_at BIGINT NOT NULL,
 PRIMARY KEY(operation_id), UNIQUE KEY ux_component_operation_idem(idem_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
[[CREATE TABLE IF NOT EXISTS component_sequence (
 server_id VARCHAR(96) NOT NULL, scope VARCHAR(16) NOT NULL, scope_key VARCHAR(128) NOT NULL,
 next_value BIGINT NOT NULL DEFAULT 1, holder CHAR(36) NULL, updated_at BIGINT NOT NULL,
 PRIMARY KEY(server_id,scope,scope_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
}}
