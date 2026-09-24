-- ncm_league schema 003: posted events and entries (M3.1). Sessions/results/settlement come with M3.2/M3.3.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 3,
    name = "events",
    statements = {
        [[CREATE TABLE IF NOT EXISTS event (
            event_id VARCHAR(160) NOT NULL,
            server_id VARCHAR(96) NOT NULL,
            class ENUM('calendar','ambient','impromptu','organized') NOT NULL DEFAULT 'calendar',
            series_id VARCHAR(96) NULL,
            series_name VARCHAR(96) NULL,
            ruleset_id VARCHAR(96) NOT NULL,
            route_id VARCHAR(160) NOT NULL,
            route_name VARCHAR(96) NULL,
            starts_at BIGINT NOT NULL,
            entry_opens_at BIGINT NOT NULL,
            entry_closes_at BIGINT NOT NULL,
            venue_x DOUBLE NOT NULL, venue_y DOUBLE NOT NULL, venue_z DOUBLE NOT NULL,
            venue_name VARCHAR(96) NULL,
            state ENUM('posted','entry_open','closed','cancelled') NOT NULL DEFAULT 'posted',
            created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (event_id),
            KEY ix_event_server_start (server_id, starts_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

        [[CREATE TABLE IF NOT EXISTS entry (
            entry_id CHAR(36) NOT NULL,
            event_id VARCHAR(160) NOT NULL,
            ncm_driver_id CHAR(36) NOT NULL,
            state ENUM('registered','checked_in','provisioned','gridded','racing','suspended','substituted','finished','dnf','dsq','withdrawn') NOT NULL DEFAULT 'checked_in',
            fee INT NOT NULL DEFAULT 0,
            checked_in_at BIGINT NULL,
            updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (entry_id),
            UNIQUE KEY ux_entry_event_driver (event_id, ncm_driver_id),
            CONSTRAINT fk_entry_event FOREIGN KEY (event_id) REFERENCES event (event_id),
            CONSTRAINT fk_entry_driver FOREIGN KEY (ncm_driver_id) REFERENCES ncm_driver (ncm_driver_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
}
