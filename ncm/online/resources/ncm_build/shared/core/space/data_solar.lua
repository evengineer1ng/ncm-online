-- ncm-core module: space.data.solar
--
-- The Solar System as catalogue records (doc 57 §2). DATA, not code: adding a body is adding a row.
--
-- Provenance (all public domain, US Government works unless noted):
--   kepler  JPL Solar System Dynamics, "Keplerian Elements for Approximate Positions of the Major Planets", Table 1
--           (E. M. Standish, valid 1800-2050): a [AU], e, I, L, long.peri, long.node [deg] at J2000 and per century,
--           heliocentric, J2000 ecliptic. Accuracy: arc-minutes (inner planets) to ~10 arc-minutes (outer).
--   moon_aa The Astronomical Almanac's low-precision Moon (USNO/HMNAO): ~0.3 deg in longitude, ~0.2 deg latitude.
--   GM      JPL DE440 / NAIF gm_de440.tpc (km^3/s^2, converted to m^3/s^2). Radii: NAIF pck00011.tpc / IAU WGCCRE mean.
--   satellite  circular mean orbits about the parent's pole: a and period from JPL SSD satellite mean elements;
--           the phase at J2000 is APPROXIMATE (a few degrees to tens of degrees) until an SPK provider replaces it.
--   Sgr A*  GRAVITY Collaboration 2019 (distance 8178 pc, mass 4.152e6 Msun); position ICRF RA 266.41683 Dec -29.00781.
local Core = NcmCore

Core.define("space.data.solar", function()
    local KM3 = 1e9   -- km^3/s^2 -> m^3/s^2
    local KM = 1000
    local NASA = "JPL SSD Standish Table 1 (public domain)"
    local GMSRC = "JPL DE440 gm_de440.tpc; NAIF pck00011 radii (public domain)"
    return {
        -- id, name, kind, parent, gm, radius, ephem, rotation (pole RA/Dec deg, ICRF), provenance
        { id = "sun", name = "Sun", kind = "star", parent = nil, gm = 132712440041.279419 * KM3, radius = 695700 * KM,
          ephem = { kind = "fixed", pos = { 0, 0, 0 } }, pole = { 286.13, 63.87 }, provenance = { GMSRC } },

        { id = "mercury", name = "Mercury", kind = "planet", parent = "sun", gm = 22031.868551 * KM3, radius = 2440.53 * KM,
          ephem = { kind = "kepler", el = { 0.38709927, 0.20563593, 7.00497902, 252.25032350, 77.45779628, 48.33076593 },
                    rate = { 0.00000037, 0.00001906, -0.00594749, 149472.67411175, 0.16047689, -0.12534081 } },
          pole = { 281.01, 61.42 }, provenance = { NASA, GMSRC } },
        { id = "venus", name = "Venus", kind = "planet", parent = "sun", gm = 324858.592000 * KM3, radius = 6051.8 * KM,
          ephem = { kind = "kepler", el = { 0.72333566, 0.00677672, 3.39467605, 181.97909950, 131.60246718, 76.67984255 },
                    rate = { 0.00000390, -0.00004107, -0.00078890, 58517.81538729, 0.00268329, -0.27769418 } },
          pole = { 272.76, 67.16 }, provenance = { NASA, GMSRC } },

        -- Earth and the Moon orbit their barycentre; the barycentre carries the published elements and no gravity of
        -- its own (its members do).
        { id = "emb", name = "Earth-Moon barycentre", kind = "barycentre", parent = "sun", gm = 0, radius = 0, gravity = false,
          ephem = { kind = "kepler", el = { 1.00000261, 0.01671123, -0.00001531, 100.46457166, 102.93768193, 0.0 },
                    rate = { 0.00000562, -0.00004392, -0.01294668, 35999.37244981, 0.32327364, 0.0 } },
          provenance = { NASA } },
        { id = "earth", name = "Earth", kind = "planet", parent = "emb", gm = 398600.435507 * KM3, radius = 6371.0 * KM,
          ephem = { kind = "emb_member", role = "earth" }, pole = { 0.0, 90.0 }, home = true,
          provenance = { GMSRC, "Night City: 35.37 N 120.85 W (space.deep ORIGIN, owner ruling 2026-10-06)" } },
        { id = "moon", name = "Moon", kind = "moon", parent = "emb", gm = 4902.800118 * KM3, radius = 1737.4 * KM,
          ephem = { kind = "emb_member", role = "moon" }, pole = { 270.0, 66.54 },
          provenance = { "Astronomical Almanac low-precision Moon (USNO/HMNAO)", GMSRC } },

        { id = "mars", name = "Mars", kind = "planet", parent = "sun", gm = 42828.375816 * KM3, radius = 3389.5 * KM,
          ephem = { kind = "kepler", el = { 1.52371034, 0.09339410, 1.84969142, -4.55343205, -23.94362959, 49.55953891 },
                    rate = { 0.00001847, 0.00007882, -0.00813131, 19140.30268499, 0.44441088, -0.29257343 } },
          pole = { 317.68, 52.89 }, provenance = { NASA, GMSRC } },
        { id = "jupiter", name = "Jupiter", kind = "planet", parent = "sun", gm = 126686531.900 * KM3, radius = 69911 * KM,
          ephem = { kind = "kepler", el = { 5.20288700, 0.04838624, 1.30439695, 34.39644051, 14.72847983, 100.47390909 },
                    rate = { -0.00011607, -0.00013253, -0.00183714, 3034.74612775, 0.21252668, 0.20469106 } },
          pole = { 268.057, 64.495 }, provenance = { NASA, GMSRC } },
        { id = "saturn", name = "Saturn", kind = "planet", parent = "sun", gm = 37931206.234 * KM3, radius = 58232 * KM,
          ephem = { kind = "kepler", el = { 9.53667594, 0.05386179, 2.48599187, 49.95424423, 92.59887831, 113.66242448 },
                    rate = { -0.00125060, -0.00050991, 0.00193609, 1222.49362201, -0.41897216, -0.28867794 } },
          pole = { 40.589, 83.537 }, provenance = { NASA, GMSRC } },
        { id = "uranus", name = "Uranus", kind = "planet", parent = "sun", gm = 5793951.256 * KM3, radius = 25362 * KM,
          ephem = { kind = "kepler", el = { 19.18916464, 0.04725744, 0.77263783, 313.23810451, 170.95427630, 74.01692503 },
                    rate = { -0.00196176, -0.00004397, -0.00242939, 428.48202785, 0.40805281, 0.04240589 } },
          pole = { 257.311, -15.175 }, provenance = { NASA, GMSRC } },
        { id = "neptune", name = "Neptune", kind = "planet", parent = "sun", gm = 6835103.145 * KM3, radius = 24622 * KM,
          ephem = { kind = "kepler", el = { 30.06992276, 0.00859048, 1.77004347, -55.12002969, 44.96476227, 131.78422574 },
                    rate = { 0.00026291, 0.00005105, 0.00035372, 218.45945325, -0.32241464, -0.00508664 } },
          pole = { 299.36, 43.46 }, provenance = { NASA, GMSRC } },
        { id = "pluto", name = "Pluto", kind = "dwarf_planet", parent = "sun", gm = 869.326 * KM3, radius = 1188.3 * KM,
          ephem = { kind = "kepler", el = { 39.48211675, 0.24882730, 17.14001206, 238.92903833, 224.06891629, 110.30393684 },
                    rate = { -0.00031596, 0.00005170, 0.00004818, 145.20780515, -0.04062942, -0.01183482 } },
          provenance = { NASA, GMSRC } },

        -- major moons: circular about the parent's pole; phase approximate (see header)
        { id = "io", name = "Io", kind = "moon", parent = "jupiter", gm = 5959.916 * KM3, radius = 1821.6 * KM,
          ephem = { kind = "satellite", a = 421800 * KM, periodD = 1.762732, phase0 = 106.1 }, provenance = { "JPL SSD satellite mean elements (phase approx)", GMSRC } },
        { id = "europa", name = "Europa", kind = "moon", parent = "jupiter", gm = 3202.739 * KM3, radius = 1560.8 * KM,
          ephem = { kind = "satellite", a = 671100 * KM, periodD = 3.525463, phase0 = 175.7 }, provenance = { "JPL SSD satellite mean elements (phase approx)", GMSRC } },
        { id = "ganymede", name = "Ganymede", kind = "moon", parent = "jupiter", gm = 9887.834 * KM3, radius = 2631.2 * KM,
          ephem = { kind = "satellite", a = 1070400 * KM, periodD = 7.155588, phase0 = 120.6 }, provenance = { "JPL SSD satellite mean elements (phase approx)", GMSRC } },
        { id = "callisto", name = "Callisto", kind = "moon", parent = "jupiter", gm = 7179.289 * KM3, radius = 2410.3 * KM,
          ephem = { kind = "satellite", a = 1882700 * KM, periodD = 16.690440, phase0 = 84.4 }, provenance = { "JPL SSD satellite mean elements (phase approx)", GMSRC } },
        { id = "titan", name = "Titan", kind = "moon", parent = "saturn", gm = 8978.138 * KM3, radius = 2574.7 * KM,
          ephem = { kind = "satellite", a = 1221900 * KM, periodD = 15.945421, phase0 = 11.7 }, provenance = { "JPL SSD satellite mean elements (phase approx)", GMSRC } },
        { id = "triton", name = "Triton", kind = "moon", parent = "neptune", gm = 1428.495 * KM3, radius = 1353.4 * KM,
          ephem = { kind = "satellite", a = 354759 * KM, periodD = -5.876854, phase0 = 63.0 }, provenance = { "JPL SSD satellite mean elements (phase approx; retrograde)", GMSRC } },

        -- the Milky Way's centre (fixed in the heliocentric root frame: the Sun's 230 Myr orbit is not modelled)
        { id = "sgr_a_star", name = "Sagittarius A*", kind = "black_hole", parent = nil, gm = 4.152e6 * 132712440041.279419 * KM3,
          radius = 1.22e10, ephem = { kind = "fixed_radec", ra = 266.41683, dec = -29.00781, distPc = 8178 },
          provenance = { "GRAVITY Collaboration 2019, A&A 625, L10" } },
    }
end)
