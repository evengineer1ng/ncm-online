-- ncm_league schema 020: QA evidence accumulated during ordinary play.
--
-- See `wp/QA_INSTRUMENTATION.md`. The QA corpus (`wp/OFFLINE_TEST_QUEUE.md`) had **102 of 133 items NOT RUN**
-- when this was written -- not failing, unrun, because 133 manual items need an operator present and there is
-- one operator. This table exists so that ordinary play moves items out of NOT RUN while nobody is awake.
--
-- **One row per (QA item, verdict, server). Never one row per event.**
--
-- That single decision is what makes this affordable and what makes it useful:
--
--   * **Bounded by construction.** The maximum row count is items x verdicts x servers -- a few hundred, ever.
--     It cannot become a firehose no matter how long the server runs or how many players join.
--   * **Repeatability is the evidence.** An invariant that has held four hundred times is far stronger evidence
--     than one that held once, and a one-in-fifty failure is only ever visible through repetition. A count is
--     the right shape for both; a log line is not.
--
-- `last_detail` keeps the most recent occurrence's specifics for diagnosis. Older occurrences are deliberately
-- not retained: the count says how often, the detail says what it looks like, and the server log carries the
-- narrative. Keeping every instance would trade the bounded property away for very little.
--
-- `qa_id` is a corpus identifier (`G1`, `P4`, `T3`) and never an invented name, so a row points straight back
-- at a numbered item with a stated Pass condition. There is no foreign key: QA items live in Markdown.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 20,
    name = "qa_observation",
    statements = {
        [[CREATE TABLE IF NOT EXISTS qa_observation (
            qa_id VARCHAR(16) NOT NULL,
            server_id VARCHAR(96) NOT NULL,
            verdict ENUM('pass','fail','review') NOT NULL,
            occurrences INT UNSIGNED NOT NULL DEFAULT 1,
            first_seen BIGINT NOT NULL,
            last_seen BIGINT NOT NULL,
            last_detail VARCHAR(500) NULL,
            last_driver_id CHAR(36) NULL,
            build VARCHAR(64) NULL,
            PRIMARY KEY (qa_id, server_id, verdict),
            -- the morning read: "what failed while I was away", newest first
            KEY ix_qa_verdict_seen (server_id, verdict, last_seen)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
}
