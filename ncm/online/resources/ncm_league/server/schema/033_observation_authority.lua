-- ncm_league schema 033: who was at the wheel, and the index the running best is read through
-- (`31_CAPABILITY_AUDIT.md` sections 7 and 9, ruled on 2026-09-26).
--
-- **`ai_driven`.** `Open77.vehicles.owner(id)` returns `driver`, `steward`, `aiDriven`, `epoch` and
-- `reason`, and the audit named the hazard plainly:
--
--   > "An NPC-driven car is not a driver's achievement. `owner().aiDriven` is available and must be
--   >  recorded. Otherwise platform AI traffic contributes observations of machines nobody drove."
--
-- It is `TINYINT(1) NULL` and the NULL is load-bearing: it is a **tri-state**, not a boolean with a
-- default. A build that does not report the flag, or a read that failed, leaves the row saying *unknown*.
-- Defaulting it to `0` would assert that a human drove, which is precisely the fabrication section 12
-- forbids -- and unlike a missing coordinate, a wrong `0` here looks exactly like a real answer.
--
-- **Physics ownership is deliberately NOT a column.** The audit's other hazard is that a parked car reads
-- zero rather than unknown, because the motion half is *"all of it zeroed when the vehicle has no owner,
-- because nobody is simulating it then"*. That is a **precondition for the observation existing**, not a
-- property of it: core refuses an observation kind without a live physics owner
-- (`machine_knowledge.evidence` -> `observation_without_physics_owner`), so a row that exists has already
-- answered the question and a column would only record `1` forever.
--
-- **The index.** The producer holds its running best in memory, but it has to recover that best after a
-- restart, a rejoin, or a second machine -- one lookup per (driver, machine, characteristic). Without this
-- it is a scan of every evidence row that driver has ever generated.
--
-- **Nothing is backfilled.** Every existing row keeps `ai_driven` NULL. There is no way to recover who was
-- driving months ago and no honest reason to guess.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 33,
    name = "observation_authority",
    statements = {
        [[ALTER TABLE vehicle_knowledge_evidence
            ADD COLUMN IF NOT EXISTS ai_driven TINYINT(1) NULL]],

        [[ALTER TABLE vehicle_knowledge_evidence
            ADD INDEX IF NOT EXISTS ix_evidence_running_best
                (ncm_driver_id, asset_id, knowledge_kind, observed_at)]],
    },
}
