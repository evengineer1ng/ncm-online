-- ncm_league schema 024: machine attribution (IDEA-236, L124 A4).
--
-- **This migration exists because history was being lost every race.** Measured against production on
-- 2026-09-24: 29 completed results, none attributable to a machine, and NOT reconstructible -- `session_result`,
-- `entry` and `seat` all lacked any vehicle reference, so the car actually fielded was written down nowhere.
-- It cannot be inferred from ownership afterwards, because a driver may own several machines and NCX team cars
-- are not assets at all. Every race run before this column existed is a permanently anonymous result.
--
-- All columns are additive and nullable. Nothing is backfilled here: stamping the existing rows is a separate,
-- reviewable step, because "unknown historical truth stays unknown" (L123) and a migration is the wrong place
-- to decide what we believe about the past.
--
-- `attribution_basis` carries the EPISTEMIC status of the attribution, which L124 (A4) requires to survive
-- permanently:
--   * `recorded` -- captured contemporaneously, at green, from the driver's actual seat context
--   * `derived`  -- established afterward from preserved evidence under an explicit, NAMED rule
--   * `unknown`  -- insufficient evidence
-- A derived attribution must stay distinguishable from a recorded one forever, which is why the basis is a
-- column and not a convention, and why `attribution_rule` names the rule rather than storing a bare flag.
--
-- `configuration_ref` is RESERVED and nothing writes it yet (Q8). Once components exist, "which machine raced"
-- stops being the whole truth and "which machine, in which configuration" becomes the question. The lesson of
-- this very migration is that "we will add it later" is how 29 results became anonymous, so the column is cut
-- now while it costs one nullable field.
--
-- VARCHAR rather than ENUM throughout, following `origin`'s precedent: the vocabularies are validated in core
-- (`vocabulary.provenance`), where a change is a test rather than an ALTER. Migration 017 already had to MODIFY
-- an ENUM once to make it nullable.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 24,
    name = "machine_attribution",
    statements = {
        [[ALTER TABLE session_result
            ADD COLUMN IF NOT EXISTS asset_id CHAR(36) NULL,
            ADD COLUMN IF NOT EXISTS machine_source VARCHAR(32) NULL,
            ADD COLUMN IF NOT EXISTS attribution_basis VARCHAR(16) NULL,
            ADD COLUMN IF NOT EXISTS attribution_rule VARCHAR(64) NULL,
            ADD COLUMN IF NOT EXISTS configuration_ref CHAR(36) NULL]],

        -- The point of the whole exercise: "486 starts, 37 wins" for ONE machine, which the Machine Profile
        -- (IDEA-237) cannot answer at all today.
        [[ALTER TABLE session_result
            ADD INDEX IF NOT EXISTS ix_result_asset (asset_id)]],

        -- Incidents are driver-attributed only, so a machine's biography cannot say what it was involved in.
        [[ALTER TABLE incident
            ADD COLUMN IF NOT EXISTS asset_id CHAR(36) NULL,
            ADD COLUMN IF NOT EXISTS other_asset_id CHAR(36) NULL]],

        [[ALTER TABLE incident
            ADD INDEX IF NOT EXISTS ix_incident_asset (asset_id)]],
    },
}
