-- Schema 055: NPCs in the markets (L249 step 4, IDEA-730; owner: "all markets need buyers").
--
-- Paddock people and teams buy the SAME serialized parts and machines players do -- never minted, never a copy -- and
-- pay real money for them.
--
--   * `component_asset.owner_principal_kind/id`: who owns a part when it is not a player. A player's part is still
--     `ncm_driver_id` (unchanged, so every existing query keeps working); a team's is ('org', org_id), a person's
--     ('person', person_id). The vehicle twin has existed since 025.
--   * `component_market_inventory.sold_to_principal` / `market_inventory.sold_to_principal`: an NPC sale's buyer
--     ('org:o012', 'person:p01234'), so the guarded claim and the money move can find each other in one transaction.
--   * `paddock_person.cash`: an independent's own money (purses in, parts and cars out). A team's is `paddock_org.cash`.
--   * `npc_money`: every NPC money movement in the markets and on the Exchange, append-only and idempotent -- the
--     NPC side's ledger. The balance itself is the Paddock's (`paddock_org.cash` / `paddock_person.cash`), moved in
--     the same transaction as the asset.
-- Replay-safe throughout.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 55,
    name = "npc_economy",
    statements = {
        [[ALTER TABLE component_asset
            ADD COLUMN IF NOT EXISTS owner_principal_kind VARCHAR(16) NULL,
            ADD COLUMN IF NOT EXISTS owner_principal_id VARCHAR(64) NULL]],
        [[ALTER TABLE component_asset ADD INDEX IF NOT EXISTS ix_component_principal (server_id, owner_principal_kind, owner_principal_id)]],
        [[ALTER TABLE component_market_inventory ADD COLUMN IF NOT EXISTS sold_to_principal VARCHAR(80) NULL]],
        [[ALTER TABLE market_inventory ADD COLUMN IF NOT EXISTS sold_to_principal VARCHAR(80) NULL]],
        [[ALTER TABLE paddock_person ADD COLUMN IF NOT EXISTS cash BIGINT NOT NULL DEFAULT 0]],
        [[CREATE TABLE IF NOT EXISTS npc_money (
            entry_id CHAR(36) NOT NULL,
            server_id VARCHAR(96) NOT NULL,
            principal_kind VARCHAR(16) NOT NULL,
            principal_id VARCHAR(64) NOT NULL,
            amount BIGINT NOT NULL,
            kind VARCHAR(32) NOT NULL,
            ref VARCHAR(128) NULL,
            idem_key VARCHAR(190) NOT NULL,
            created_at BIGINT NOT NULL,
            PRIMARY KEY (entry_id),
            UNIQUE KEY ux_npc_money_idem (idem_key),
            KEY ix_npc_money_principal (server_id, principal_kind, principal_id, created_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
}
