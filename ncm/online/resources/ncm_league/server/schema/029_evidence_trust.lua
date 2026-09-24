-- ncm_league schema 029: how an observation reached us, and where a discovery happened
-- (IDEA-360, IDEA-361, IDEA-362; `31_CAPABILITY_AUDIT.md` sections 3, 4 and 7).
--
-- Two additive facts, both irrecoverable once rows exist without them.
--
-- **`observation_basis`.** The capability audit established that the observation surface is split and the
-- halves do not overlap: the authoritative server snapshot carries `velocity` and `angularVelocity` and no
-- drivetrain, while the client snapshot carries `rpm`/`throttle`/`brake`/`steering` and no velocity vectors.
-- There is no `getThrottle` among the 138 server natives -- a complete enumeration, not a failed search.
--
--   > "Every characteristic that depends on driver input is observable only from a client, and a client is
--   >  not an authority."
--
-- So a permanent class of future evidence can only ever be attested rather than measured, and
-- `epistemic_kind = 'observed'` spans both today. Recording them under one word would make a measurement and
-- a claim indistinguishable forever. Core validates the three values (`competition.machine_knowledge.BASIS`).
--
-- **Discovery coordinates.** `vehicle_knowledge_evidence` gained a position in migration 028;
-- `vehicle_discovery` did not, and it is the row that holds *where you first met this model*. Section 9 of
-- `28_MACHINE_KNOWLEDGE.md` builds its whole research layer on position, and a position cannot be
-- reconstructed afterwards. Written on INSERT only -- never in an `ON DUPLICATE KEY UPDATE` clause -- for the
-- same reason `source_driver_id` is: driving past the same model again months later must not rewrite where
-- you first saw it.
--
-- **Nothing is backfilled.** Rows written before this migration have an unknown basis and no discovery
-- position, and they keep both. Inventing either is exactly the fabrication section 12 forbids, and `NULL`
-- already says "unknown" precisely.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 29,
    name = "evidence_trust",
    statements = {
        [[ALTER TABLE vehicle_knowledge_evidence
            ADD COLUMN IF NOT EXISTS observation_basis VARCHAR(24) NULL]],

        [[ALTER TABLE vehicle_discovery
            ADD COLUMN IF NOT EXISTS first_obs_x DOUBLE NULL,
            ADD COLUMN IF NOT EXISTS first_obs_y DOUBLE NULL,
            ADD COLUMN IF NOT EXISTS first_obs_z DOUBLE NULL]],
    },
}
