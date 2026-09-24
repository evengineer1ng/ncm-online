-- ncm_league schema 026: an entry names a machine and carries a number (IDEA-312).
--
-- **Before this, entry checked only that a driver OWNED an eligible model.** `NcmCompetition.carRefusal` asked
-- `Eligibility.check` whether the spec admitted any record the driver owned, then **threw the answer away** --
-- `decision.record` was never stored, `entry` had no vehicle column, and nothing at grid, green or during the
-- race ever looked at what the driver was actually sitting in. So a driver could enter on the strength of
-- owning one car and go racing in another, and nothing noticed.
--
-- That is not how motorsport entry works. **You enter a car, and it carries a number.**
--
-- `asset_id` binds the entry to one physical machine -- not a model, an example. `car_number` already existed
-- from migration 006 but was written only for NCX team seats; a privateer entry left it NULL. Now every entry
-- gets one.
--
-- The number is unique WITHIN AN EVENT, not globally: two drivers may both prefer 44 and only one of them can
-- have it on a given grid. A permanent per-driver racing number is a larger identity feature and is
-- deliberately not decided here -- this stores what was used, which is what a later permanent number would be
-- derived from anyway.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 26,
    name = "entry_machine",
    statements = {
        [[ALTER TABLE entry
            ADD COLUMN IF NOT EXISTS asset_id CHAR(36) NULL]],

        -- "Which entries has this machine ever been fielded in" -- the same question IDEA-236 answers for
        -- results, one step earlier in the sporting record.
        [[ALTER TABLE entry
            ADD INDEX IF NOT EXISTS ix_entry_asset (asset_id)]],

        -- Numbers are per event. Existing team rows already carry one and are left exactly as they are.
        [[ALTER TABLE entry
            ADD INDEX IF NOT EXISTS ix_entry_event_number (event_id, car_number)]],
    },
}
