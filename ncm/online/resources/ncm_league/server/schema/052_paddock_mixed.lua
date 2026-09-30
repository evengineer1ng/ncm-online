-- Schema 052: a Paddock race can be MIXED (L229): some of it driven physically in a player's bubble, the rest simulated.
--
-- The continuous race model (`paddock.racestate`) owns every car everywhere; near a player a car is physical, and when
-- it leaves, its real position re-anchors the model. A race where every car drove its whole line physically stays
-- `physical`; one where only some stretches were physical is `mixed`, and its detail_json names each car's physical
-- share. MODIFY is replay-safe: re-applying the same column definition changes nothing.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 52,
    name = "paddock_mixed",
    statements = {
        [[ALTER TABLE paddock_race MODIFY provenance ENUM('simulated','physical','mixed') NOT NULL DEFAULT 'simulated']],
    },
}
