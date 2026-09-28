-- ncm_league schema 039: the quest graph's first slice -- Dex, Setup Stu and Rico.
--
-- Three changes, and the first of them is the one the whole Messages story was waiting on.
--
-- **1. `message.from_kind` is widened (`IDEA-599`).** It was `ENUM('team','system','race_control')`, which is
-- why no character in NCM could speak: there was no value to put in the column. The archaeology called this
-- *"the ONLY schema blocker in the whole Messages story"*, and it was right -- CRUD, net events, actionable
-- `actions` JSON, `ref_kind`/`ref_id`, `expires_at`, unread state, the panel mode and the chat twins are all
-- already deployed. `character` is the value this slice needs; the rest are added now because widening an ENUM
-- twice costs two migrations and the senders are already named in `06_CHROME_ROSTER.md` and `17_MARKET_NETWORK.md`.
--
-- `driver` is deliberately in the list. A conversation is a transcript, and a transcript without the player's own
-- replies is a monologue -- the Messages surface has to be able to show what the player said. This is NOT
-- player-to-player messaging: `to_driver_id` and `from_id` are the same driver on those rows, and OPEN//77 owns
-- human communication (`IDEA-614`).
--
-- **2. `thread_id` (`IDEA-614`), nullable and used lazily.** A standing thread per contact, so Messages can be a
-- sidebar of conversations rather than one undifferentiated pile. Nullable because every existing row predates
-- it and none of them needs backfilling: a seat offer with no thread is a loose notice, which is what it is.
-- It is also what makes Quinn and Foreman's group chat free later -- two `from_id`s interleaved in one thread,
-- which is just two rows with adjacent `created_at`.
--
-- **3. `player_contact` -- where a conversation IS.** One row per driver per contact: the node the conversation
-- rests on, the flags the scripts project against, and the hidden counters.
--
-- Deliberately NOT here:
--
--   * **No quest, step, objective or completion column.** `L175` and §0.3 both forbid it. A conversation rests on
--     a node; it does not progress through a ladder. `node` is where the player is, not how far they have got.
--   * **No authored copy.** Every line lives in `graph.opening`, so a wording change is a code change and never
--     a data migration. The `message` rows hold what was SAID, which is history and must not be rewritten.
--   * **No choice rows.** Choices are projected from state at read time (§0.3), never stored. Storing them would
--     make a stale row into a legal move, which is exactly what `graph.conversation.pick` re-checks against.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 39,
    name = "quest_graph",
    statements = {
        -- IDEA-599. The only schema blocker in the Messages story.
        [[ALTER TABLE message
            MODIFY COLUMN from_kind ENUM(
                'team','system','race_control',
                'character','dispatch','driver',
                'market','manufacturer','championship','organizer'
            ) NOT NULL]],

        -- IDEA-614. Nullable and lazy: nothing is backfilled and nothing requires it. The index is the inbox's
        -- hot path once conversations exist -- one thread, oldest first.
        [[ALTER TABLE message
            ADD COLUMN IF NOT EXISTS thread_id VARCHAR(96) NULL,
            ADD INDEX IF NOT EXISTS ix_message_thread (server_id, to_driver_id, thread_id, created_at)]],

        -- Where each conversation rests, and what the scripts project against.
        [[CREATE TABLE IF NOT EXISTS player_contact (
            ncm_driver_id CHAR(36) NOT NULL,
            server_id VARCHAR(96) NOT NULL,
            contact_id VARCHAR(32) NOT NULL,
            -- `known` is access; a lead is knowledge without it (`L175`). A contact only ever reaches this
            -- table once it is known, so there is no `unknown` state to store.
            state ENUM('known','muted') NOT NULL DEFAULT 'known',
            -- The node the conversation is resting on. NOT a step: there is no ordering and no completion.
            node VARCHAR(64) NULL,
            -- Script-projected flags (§0.3). JSON because the set is authored and changes with the copy; a
            -- column per flag would make every new line of dialogue a migration.
            flags JSON NULL,
            known_at BIGINT NOT NULL,
            last_spoke_at BIGINT NULL,          -- the contact said something
            last_heard_at BIGINT NULL,          -- the player replied
            last_flavour_at BIGINT NULL,        -- §20 rule 9: per-contact flavour sparseness
            PRIMARY KEY (ncm_driver_id, server_id, contact_id),
            CONSTRAINT fk_player_contact_driver FOREIGN KEY (ncm_driver_id)
                REFERENCES ncm_driver (ncm_driver_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

        -- Hidden behavioural counters. §3.4's hardware-curiosity score is the first, and the draft is explicit
        -- that it *"is not a quest meter shown to the player"* -- so it lives in its own table, away from
        -- anything a player-facing payload is built from, and nothing here may be rendered.
        --
        -- Generalised rather than a `hardware_curiosity INT` column, because §21's telemetry list is long and
        -- every one of those counters has the same shape: a driver, a name, a number, and when it last moved.
        [[CREATE TABLE IF NOT EXISTS player_behaviour_counter (
            ncm_driver_id CHAR(36) NOT NULL,
            server_id VARCHAR(96) NOT NULL,
            counter VARCHAR(48) NOT NULL,
            value INT NOT NULL DEFAULT 0,
            last_moved_at BIGINT NULL,
            PRIMARY KEY (ncm_driver_id, server_id, counter),
            CONSTRAINT fk_behaviour_counter_driver FOREIGN KEY (ncm_driver_id)
                REFERENCES ncm_driver (ncm_driver_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

        -- §20 rules 1 and 2 are per DRIVER, not per contact: "never fire multiple new-character introductions
        -- simultaneously" cannot be enforced from a per-contact row. One row per driver holds the budget.
        [[CREATE TABLE IF NOT EXISTS player_graph_budget (
            ncm_driver_id CHAR(36) NOT NULL,
            server_id VARCHAR(96) NOT NULL,
            open_introductions INT NOT NULL DEFAULT 0,
            last_introduction_at BIGINT NULL,
            last_flavour_at BIGINT NULL,
            PRIMARY KEY (ncm_driver_id, server_id),
            CONSTRAINT fk_graph_budget_driver FOREIGN KEY (ncm_driver_id)
                REFERENCES ncm_driver (ncm_driver_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
}
