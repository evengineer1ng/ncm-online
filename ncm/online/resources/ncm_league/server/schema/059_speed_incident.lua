-- Schema 059: speeding is an incident (L301, doc 45 §M).
--
-- Racing Week's Day 1 is "friendly racing": going over the Day's advertised limit in a race costs time, charged
-- through the same self-attributed incident path as a formation fault (011), so it reaches the corrected time, the
-- Paddock's classification ceremony and the machine's history without new plumbing. Widening an ENUM is
-- replay-safe; no row changes.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 59,
    name = "speed_incident",
    statements = {
        [[ALTER TABLE incident MODIFY kind ENUM('car','object','person','offtrack','cut','lane','formation','speed') NOT NULL]],
    },
}
