-- Schema 040: the Exchange's atomic heterogeneous transfer envelope (IDEA-247).
--
-- Drafts are deliberately synchronous and memory-only: no escrow means an offer may not survive a restart.
-- The accepted exact revision is durable. Its envelope, asset legs, money leg, ordinary asset-transfer history
-- and paired ledger rows commit in one transaction, so retry can observe a settlement but cannot repeat it.
NcmSchema=NcmSchema or {}
NcmSchema[#NcmSchema+1]={version=40,name="player_trade",statements={
[[ALTER TABLE vehicle_asset
 MODIFY acquired_via ENUM('grant','progression','prize','purchase','seed','trade') NULL]],
[[CREATE TABLE IF NOT EXISTS economy_balance_lock (
 server_id VARCHAR(96) NOT NULL, ncm_driver_id CHAR(36) NOT NULL, revision BIGINT UNSIGNED NOT NULL DEFAULT 0,
 PRIMARY KEY(server_id,ncm_driver_id),
 CONSTRAINT fk_economy_balance_lock_driver FOREIGN KEY(ncm_driver_id) REFERENCES ncm_driver(ncm_driver_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
[[CREATE TABLE IF NOT EXISTS trade_envelope (
 trade_id CHAR(36) NOT NULL, server_id VARCHAR(96) NOT NULL, request_key VARCHAR(190) NOT NULL,
 party_a_driver_id CHAR(36) NOT NULL, party_b_driver_id CHAR(36) NOT NULL,
 revision INT UNSIGNED NOT NULL, state VARCHAR(24) NOT NULL,
 offer_json LONGTEXT NOT NULL, created_at BIGINT NOT NULL, expires_at BIGINT NOT NULL, settled_at BIGINT NULL,
 PRIMARY KEY(trade_id), UNIQUE KEY ux_trade_request(server_id,request_key),
 KEY ix_trade_a(server_id,party_a_driver_id,created_at), KEY ix_trade_b(server_id,party_b_driver_id,created_at),
 CHECK(JSON_VALID(offer_json)),
 CONSTRAINT fk_trade_a FOREIGN KEY(party_a_driver_id) REFERENCES ncm_driver(ncm_driver_id),
 CONSTRAINT fk_trade_b FOREIGN KEY(party_b_driver_id) REFERENCES ncm_driver(ncm_driver_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
[[CREATE TABLE IF NOT EXISTS trade_asset_leg (
 trade_id CHAR(36) NOT NULL, asset_kind VARCHAR(16) NOT NULL, asset_id CHAR(36) NOT NULL,
 from_driver_id CHAR(36) NOT NULL, to_driver_id CHAR(36) NOT NULL,
 custody_kind VARCHAR(24) NOT NULL, machine_asset_id CHAR(36) NULL,
 PRIMARY KEY(trade_id,asset_kind,asset_id), KEY ix_trade_asset(asset_kind,asset_id),
 CONSTRAINT fk_trade_asset_envelope FOREIGN KEY(trade_id) REFERENCES trade_envelope(trade_id),
 CONSTRAINT fk_trade_asset_from FOREIGN KEY(from_driver_id) REFERENCES ncm_driver(ncm_driver_id),
 CONSTRAINT fk_trade_asset_to FOREIGN KEY(to_driver_id) REFERENCES ncm_driver(ncm_driver_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
[[CREATE TABLE IF NOT EXISTS trade_money_leg (
 trade_id CHAR(36) NOT NULL, from_driver_id CHAR(36) NOT NULL, to_driver_id CHAR(36) NOT NULL,
 amount INT UNSIGNED NOT NULL, currency VARCHAR(16) NOT NULL DEFAULT 'eddies',
 PRIMARY KEY(trade_id),
 CONSTRAINT fk_trade_money_envelope FOREIGN KEY(trade_id) REFERENCES trade_envelope(trade_id),
 CONSTRAINT fk_trade_money_from FOREIGN KEY(from_driver_id) REFERENCES ncm_driver(ncm_driver_id),
 CONSTRAINT fk_trade_money_to FOREIGN KEY(to_driver_id) REFERENCES ncm_driver(ncm_driver_id),
 CHECK(amount>0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
[[ALTER TABLE vehicle_asset_transfer
 ADD COLUMN IF NOT EXISTS trade_id CHAR(36) NULL,
 ADD INDEX IF NOT EXISTS ix_vehicle_transfer_trade(trade_id)]],
[[ALTER TABLE component_asset_transfer
 ADD COLUMN IF NOT EXISTS trade_id CHAR(36) NULL,
 ADD INDEX IF NOT EXISTS ix_component_transfer_trade(trade_id)]],
[[ALTER TABLE ledger
 ADD COLUMN IF NOT EXISTS trade_id CHAR(36) NULL,
 ADD INDEX IF NOT EXISTS ix_ledger_trade(trade_id,ncm_driver_id)]],
}}
