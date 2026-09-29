-- Schema 041: the Chrome ledger (IDEA-067, IDEA-078).
--
-- One row per decisive chrome outcome: an impact, a block by Self-ICE, a purge, an interruption. It is HISTORY,
-- not a score: the Driver Fingerprint and the skull badge (TOTAL FAILURE landed) are queries over these rows, so
-- nothing about a player's chrome record is ever stored as a number that could drift from what happened.
-- `target_driver_id` is NULL for a vehicle nobody human was driving (AI traffic).
NcmSchema=NcmSchema or {}
NcmSchema[#NcmSchema+1]={version=41,name="chrome_event",statements={
[[CREATE TABLE IF NOT EXISTS chrome_event (
 event_id CHAR(36) NOT NULL, server_id VARCHAR(96) NOT NULL,
 attacker_driver_id CHAR(36) NULL, target_driver_id CHAR(36) NULL,
 hack VARCHAR(32) NOT NULL, outcome VARCHAR(24) NOT NULL, route VARCHAR(16) NOT NULL,
 target_vehicle_id BIGINT NULL, target_record VARCHAR(128) NULL, catastrophic TINYINT(1) NOT NULL DEFAULT 0,
 detail VARCHAR(190) NULL, occurred_at BIGINT NOT NULL,
 PRIMARY KEY(event_id),
 KEY ix_chrome_attacker(server_id,attacker_driver_id,occurred_at),
 KEY ix_chrome_target(server_id,target_driver_id,occurred_at),
 KEY ix_chrome_catastrophic(server_id,catastrophic,attacker_driver_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
}}
