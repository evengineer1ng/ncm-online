-- ncm_league schema 025: the owner principal (IDEA-297, IDEA-168, IDEA-162; L92/L93, L124 A2).
--
-- **The single highest-leverage column in the ledger**, because one generalisation unblocks a dozen things
-- that are already designed and stuck on the same wall:
--
--   * a TEAM cannot own a car          -- `vehicle_asset.ncm_driver_id NOT NULL` -> `ncm_driver` (IDEA-168)
--   * a TEAM cannot hold money         -- `ledger.ncm_driver_id NOT NULL` -> `ncm_driver`      (IDEA-162)
--   * L92/L93's whole player-ownable NCX organisation model waits on both
--   * so do the Q4/Q6/Q15/Q45/Q50 answers of the 2026-09-24 pass (L123)
--
-- Migration 015 named this exact ALTER in a comment and did not spend it:
--   "`owner_principal_kind/id` (IDEA-168, team-owned cars). It is a cheap later ALTER *precisely because* the
--    primary key is the asset rather than the owner."
-- This is that ALTER. The foresight was correct; the primary key never needed to change.
--
-- **Title moves; it does not fork.** A principal is `(kind, id)` -- today `('driver', ncm_driver_id)`, and in
-- future `('organization', team_id)`. There is no second ownership table, no parallel "team asset" species, and
-- no exception for league equipment: L123 forbids exactly that, and L124 A2 settled that a team machine is an
-- ordinary machine whose exclusivity lives in market access rather than in its ontology.
--
-- **The old columns stay.** `ncm_driver_id` is kept on both tables and kept in step, so every existing query
-- keeps working and this migration is reversible by ignoring the new columns. They are dropped only once the
-- principal path has a live PASS -- the precedent is IDEA-188, where migration 015 deliberately left
-- `owned_vehicle` in place rather than renaming it.
--
-- Replay-safe: `ADD COLUMN IF NOT EXISTS` throughout (MariaDB DDL is not transactional, so a half-applied run
-- must not wedge the forward-only runner), and every backfill is guarded on `owner_principal_id IS NULL` so a
-- second run writes nothing.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 25,
    name = "owner_principal",
    statements = {
        [[ALTER TABLE vehicle_asset
            ADD COLUMN IF NOT EXISTS owner_principal_kind VARCHAR(16) NULL,
            ADD COLUMN IF NOT EXISTS owner_principal_id   VARCHAR(64) NULL]],

        -- Every existing owner is a driver. Unsold market stock has no owner at all and must stay that way:
        -- `ncm_driver_id IS NULL` means "nobody has acquired this", which migration 017 made expressible on
        -- purpose, and turning that into a principal would invent an owner for a car on a shelf.
        [[UPDATE vehicle_asset
             SET owner_principal_kind = 'driver', owner_principal_id = ncm_driver_id
           WHERE ncm_driver_id IS NOT NULL AND owner_principal_id IS NULL]],

        [[ALTER TABLE vehicle_asset
            ADD INDEX IF NOT EXISTS ix_vehicle_asset_principal (owner_principal_kind, owner_principal_id)]],

        [[ALTER TABLE ledger
            ADD COLUMN IF NOT EXISTS owner_principal_kind VARCHAR(16) NULL,
            ADD COLUMN IF NOT EXISTS owner_principal_id   VARCHAR(64) NULL]],

        -- `ledger.ncm_driver_id` is NOT NULL, so every row backfills. A team treasury (IDEA-162) becomes a
        -- matter of writing a different principal to the same table rather than a second wallet.
        [[UPDATE ledger
             SET owner_principal_kind = 'driver', owner_principal_id = ncm_driver_id
           WHERE owner_principal_id IS NULL]],

        [[ALTER TABLE ledger
            ADD INDEX IF NOT EXISTS ix_ledger_principal (owner_principal_kind, owner_principal_id, created_at)]],
    },
}
