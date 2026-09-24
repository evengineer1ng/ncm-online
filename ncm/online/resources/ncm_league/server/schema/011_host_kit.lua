-- ncm_league schema 011: the TW1 host kit (Batch 2; L63) — authored routes for every discipline; rolling-start faults.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 11,
    name = "host_kit",
    statements = {
        [[CREATE TABLE IF NOT EXISTS custom_route (
            server_id VARCHAR(96) NOT NULL,
            route_key VARCHAR(48) NOT NULL,
            name VARCHAR(96) NOT NULL,
            discipline_id VARCHAR(32) NULL,
            points_json MEDIUMTEXT NOT NULL,
            laps INT NOT NULL DEFAULT 1,
            is_loop TINYINT NOT NULL DEFAULT 0,
            created_at BIGINT NOT NULL,
            PRIMARY KEY (server_id, route_key)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

        -- rolling start faults (passing before the green, over the formation pace) are incidents of kind 'formation'
        [[ALTER TABLE incident MODIFY kind ENUM('car','object','person','offtrack','cut','lane','formation') NOT NULL]],
    },
}
