-- ncm_league schema 028: where an observation happened, and what the machine was (IDEA-329, IDEA-344).
--
-- `28_MACHINE_KNOWLEDGE.md` section 9 is explicit that observations record **world coordinates**, not authored
-- place names, because an observation may occur during a race, during free driving, at a meet, in the Badlands,
-- on an unnamed road, or somewhere that only later becomes part of a course. Sections 9-10 then build the whole
-- research layer on position:
--
--   > "My Index has a MaiMai observed at 116." / "Where?" / "Check the coordinates. Downhill." / "Which
--   > serial?" / "#47." / "That's the modified one."
--
-- None of that works without a position, and **a position cannot be reconstructed afterwards**. At the time of
-- writing, Online holds 14 evidence rows and 14 discovery rows with no coordinates at all -- the same shape as
-- `IDEA-236`, one level over. The rate is low today, which makes this the cheap moment rather than a reason to
-- wait.
--
-- `configuration_ref` is **reserved and unwritten**, exactly as migration 024 reserved it on `session_result`
-- and for the reason the owner gave in section 24:
--
--   > "Asset identity tells us which machine produced the observation. Configuration history may eventually
--   >  tell us what that machine was at the time."
--
-- The same serialised machine may change substantially over its life, so an observation of `#47 doing 128` is
-- only interpretable alongside what `#47` was that day. Nothing writes this until the configuration/component
-- primitive is settled, and section 24 warns against inventing that reference prematurely.
--
-- All four columns are nullable and additive. Nothing is backfilled: rows recorded before this migration have
-- no position and never will, and inventing one would be exactly the fabrication section 12 forbids.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 28,
    name = "observation_provenance",
    statements = {
        [[ALTER TABLE vehicle_knowledge_evidence
            ADD COLUMN IF NOT EXISTS obs_x DOUBLE NULL,
            ADD COLUMN IF NOT EXISTS obs_y DOUBLE NULL,
            ADD COLUMN IF NOT EXISTS obs_z DOUBLE NULL,
            ADD COLUMN IF NOT EXISTS configuration_ref CHAR(36) NULL]],
    },
}
