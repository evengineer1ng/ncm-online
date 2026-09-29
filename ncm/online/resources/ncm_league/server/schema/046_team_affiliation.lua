-- Schema 046: the One-Team Rule, for both circuits (doc 14 §2-3, doc 44 §10, L224.8).
--
-- One identity holds at most ONE active formal affiliation: Owner, Manager or Team Driver of a sanctioned
-- organization, or Manager of an NPC-circuit org. Enforced as a constraint, not as code three call sites must
-- remember: a generated flag is 1 while the row is open and NULL once it ends, and a unique index over
-- (server, driver, flag) makes a second active affiliation impossible to write (NULLs are distinct, so ended rows
-- never collide). The flag reads only `effective_to`: MariaDB 10.11 refuses a generated column over a CHAR column
-- (SQL 1901, its value depends on sql_mode padding), and `ncm_driver_id` is CHAR(36). The CHECK ties each
-- circuit to its own org table and allows only the Manager role on the NPC circuit. Street activity and
-- privateering are not affiliations and never appear here.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 46,
    name = "team_affiliation",
    statements = {
        [[CREATE TABLE IF NOT EXISTS team_affiliation (
            affiliation_id CHAR(36) NOT NULL,
            server_id VARCHAR(96) NOT NULL,
            ncm_driver_id CHAR(36) NOT NULL,
            circuit ENUM('sanctioned','npc') NOT NULL,
            organization_id CHAR(36) NULL,
            paddock_org_id VARCHAR(16) NULL,
            role ENUM('owner','manager','driver') NOT NULL,
            effective_from BIGINT NOT NULL,
            effective_to BIGINT NULL,
            end_reason VARCHAR(32) NULL,
            active_flag TINYINT AS (IF(effective_to IS NULL, 1, NULL)) PERSISTENT,
            PRIMARY KEY (affiliation_id),
            UNIQUE KEY ux_one_team (server_id, ncm_driver_id, active_flag),
            KEY ix_affiliation_driver (server_id, ncm_driver_id, effective_from),
            KEY ix_affiliation_paddock_org (server_id, paddock_org_id),
            CONSTRAINT fk_affiliation_driver FOREIGN KEY (ncm_driver_id) REFERENCES ncm_driver (ncm_driver_id),
            CONSTRAINT ck_affiliation_circuit CHECK (
                (circuit = 'sanctioned' AND organization_id IS NOT NULL AND paddock_org_id IS NULL)
                OR (circuit = 'npc' AND paddock_org_id IS NOT NULL AND organization_id IS NULL AND role = 'manager'))
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
}
