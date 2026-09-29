-- Schema 048: the Paddock's tape, WIRE and spotlight (doc 44 §8).
--
-- `paddock_event` is the causal fact tape (FTB2 `event_tape`): every news story names the event it was written
-- from, and every event names its causes, so "why did this happen" is a walk, not a guess. `retain` marks what
-- pruning must never touch (titles, folds, retirements). `paddock_push` counts the unsolicited Paddock messages
-- each driver received per Eastern day, so the push budget (L226: 3 a day) is enforced across restarts.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 48,
    name = "paddock_story",
    statements = {
        [[CREATE TABLE IF NOT EXISTS paddock_event (
            server_id VARCHAR(96) NOT NULL,
            event_id VARCHAR(160) NOT NULL,
            at BIGINT NOT NULL,
            day_index INT NULL,
            kind VARCHAR(24) NOT NULL,
            entities JSON NULL,
            cause_refs JSON NULL,
            effect_refs JSON NULL,
            facts JSON NOT NULL,
            public_summary VARCHAR(255) NULL,
            salience TINYINT UNSIGNED NOT NULL,
            retain TINYINT(1) NOT NULL DEFAULT 0,
            provenance ENUM('simulated','physical','reported') NOT NULL DEFAULT 'simulated',
            PRIMARY KEY (server_id, event_id),
            KEY ix_paddock_event_at (server_id, at),
            KEY ix_paddock_event_kind (server_id, kind, at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
        [[CREATE TABLE IF NOT EXISTS paddock_news (
            server_id VARCHAR(96) NOT NULL,
            story_id VARCHAR(170) NOT NULL,
            event_id VARCHAR(160) NOT NULL,
            at BIGINT NOT NULL,
            kind VARCHAR(24) NOT NULL,
            template_id VARCHAR(16) NOT NULL,
            headline VARCHAR(200) NOT NULL,
            body VARCHAR(800) NOT NULL,
            prominence TINYINT UNSIGNED NOT NULL,
            subjects JSON NULL,
            PRIMARY KEY (server_id, story_id),
            KEY ix_paddock_news_at (server_id, at),
            KEY ix_paddock_news_prominence (server_id, prominence, at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
        [[CREATE TABLE IF NOT EXISTS paddock_arc (
            server_id VARCHAR(96) NOT NULL,
            arc_id VARCHAR(64) NOT NULL,
            kind ENUM('callout','rivalry','feud') NOT NULL,
            state ENUM('open','won','lost','expired') NOT NULL DEFAULT 'open',
            npc_person_id VARCHAR(16) NOT NULL,
            human_kind ENUM('driver','organization') NOT NULL DEFAULT 'driver',
            human_id CHAR(36) NOT NULL,
            opened_event_id VARCHAR(160) NULL,
            opened_at BIGINT NOT NULL,
            resolves_by BIGINT NOT NULL,
            resolved_at BIGINT NULL,
            resolved_by_session CHAR(36) NULL,
            PRIMARY KEY (server_id, arc_id),
            KEY ix_paddock_arc_open (server_id, state, human_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
        [[CREATE TABLE IF NOT EXISTS paddock_spotlight (
            server_id VARCHAR(96) NOT NULL,
            subject_kind ENUM('driver','organization') NOT NULL,
            subject_id CHAR(36) NOT NULL,
            score DECIMAL(9,3) NOT NULL DEFAULT 0,
            streak INT NOT NULL DEFAULT 0,
            last_session_id CHAR(36) NULL,
            updated_at BIGINT NOT NULL,
            PRIMARY KEY (server_id, subject_kind, subject_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
        [[CREATE TABLE IF NOT EXISTS paddock_cursor (
            server_id VARCHAR(96) NOT NULL,
            name VARCHAR(48) NOT NULL,
            value VARCHAR(190) NULL,
            PRIMARY KEY (server_id, name)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
        [[CREATE TABLE IF NOT EXISTS paddock_push (
            server_id VARCHAR(96) NOT NULL,
            ncm_driver_id CHAR(36) NOT NULL,
            day_index INT NOT NULL,
            count SMALLINT NOT NULL DEFAULT 0,
            PRIMARY KEY (server_id, ncm_driver_id, day_index)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
}
