-- ncm_league schema 027: remove `machine_source` (L123, L124 A2, L126).
--
-- **This column should never have existed.** Q2 offered three answers to "what does `asset_id` hold when the
-- raced car is not an asset": (a) nullable, (b) nullable plus a `machine_source` enum, (c) **require every car
-- to be an asset**. I recommended (b). **The owner chose (c)** -- and I built (b) anyway, one migration later.
--
-- The damage is not the wasted column. It is that `machine_source` carried the value `team_equipment`, which
-- encodes exactly the species distinction the design forbids:
--
--   > A team car is simply a car, owned by a team. Not a special category of car. Every car -- including NCX
--   > cars, including any car -- is serialised like any other from a manufacturer. Exclusivity lives in market
--   > access, not in the object. (owner, 2026-09-24; L124 A2; L126)
--
-- So a schema written the day after L123 banned *"preserving exceptions created by obsolete prototypes as
-- permanent ontology"* quietly preserved one, in an enum, in core vocabulary.
--
-- **What remains is sufficient and says only true things:**
--   * `asset_id`          -- WHICH machine. Eventually NOT NULL, once every car is an asset.
--   * `attribution_basis` -- how well we know it: recorded / derived / unknown.
--   * `attribution_rule`  -- names the derivation when the basis is `derived`.
-- "This was a team car" is not a third fact -- it is `asset_id` pointing at a machine whose owner principal is
-- an organization, which migration 025 made expressible.
--
-- Forward-only rather than amending 024: that migration has already applied on NCM Development, and rewriting
-- an applied migration would make the recorded version and its definition disagree. Removing a nullable column
-- that nothing reads is safe; `DROP COLUMN IF EXISTS` keeps the runner replay-safe.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 27,
    name = "drop_machine_source",
    statements = {
        [[ALTER TABLE session_result DROP COLUMN IF EXISTS machine_source]],
    },
}
