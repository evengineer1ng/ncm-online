-- NCM Los Santos space: tunables. `python tools/fivem-rcon.py restart ncm_ls_space` reloads them.
NcmLsConfig = {
    anchor = "los_santos",

    -- Snowglobe Earth (L320): a deliberately compressed physical radius with about 1 g at the surface; gravity radial
    -- toward the NCM Earth centre once Snowglobe owns you. A world/seed constant, NOT canon: 5 km is the first experiment.
    earthRadius = 5000,
    surfaceG = 9.81,

    -- The doorway: climbing through game z `up` hands you to Snowglobe (NCM integrates your universe position and
    -- velocity from then on). Inside Snowglobe the GTA body is kept in a local band [down, up] by server moves to `mid`
    -- (a floating origin); it never changes the universe state. Leaving Snowglobe: universe altitude below `homeAlt`
    -- while falling, over the Los Santos patch (|x|, |y| < homePatch) -> you are put back at your TRUE local position.
    up = 2500,
    mid = 1700,
    down = 1000,             -- Mount Chiliad is ~800 m: the GTA body stays clear of terrain
    homeAlt = 2000,
    homePatch = 4500,
    recenterXY = 3500,       -- inside Snowglobe, drift past this in x or y re-centres the GTA body to (0, 0)
    rebaseCooldownMs = 2000,

    -- GTA's per-entity speed cap (measured §LS2: 146.7 m/s with SET_ENTITY_MAX_SPEED 2000 -- not lifted). The GTA body
    -- shows at most this; NCM's universe velocity is separate and uncapped.
    presentCap = 140.0,

    -- Thrust INSTRUMENT (`/ncm.machine instrument`): the F0 lift rig's thrust load, from `engineering.fixtures` (36,100 N). Lift = thrust / (m * g).
    rig = "f0_lift_rig",
    maxTwr = 3.0,
    attitudeGain = 6.0,
    attitudeArm = 1.6,
    maxSpeed = 2000.0,

    logEveryMs = 1000,

    -- L321 Engineering II. The machine your car carries (`engineering.fixtures.MACHINES`); "instrument" mode is the dev
    -- lift rig above. torqueGain turns the machine's angular velocity change into RAGE couple forces: UNCALIBRATED
    -- (RAGE's ApplyForceToEntity units at an offset are not measured yet; §SR1 logs commanded vs observed spin).
    machine = "ls_orbiter",
    machineMode = "machine",
    torqueGain = 30.0,

    -- Snowglobe from the seed: every client and the server generate the same stations, venues and NPC field.
    universeSeed = "ncm-los-santos-dev-1",
    orbitEpoch = 1790000000,   -- seconds: station orbits are phased from here on the shared cloud clock
    raceDrawM = 4000,

    -- L322 Snowglobe disciplines. The LSIA Sky Sprint grid stands on this GTA spot (open airport tarmac); you must stop
    -- within gridToleranceM of your lane marker for the lights (fireballGridM of the Fireball grid). Unseen Snowglobe
    -- events run every snowglobeEveryMin minutes of the shared clock (abstract fidelity) and persist in the KVP.
    sprintSpot = { -1336.0, -3044.0, 13.9 },
    lightsS = 5,
    gridToleranceM = 8,
    lightsStragglerS = 30,      -- several players: lights this long after the first is ready, stragglers start where they are
    contactCheckM = 15,         -- a reported contact is believed only if the race has the two cars this close
    fireballGridM = 600,
    snowglobeEveryMin = 10,
    npcModels = { "sultan", "elegy2", "kuruma", "comet2", "banshee", "jester", "feltzer2", "carbonizzare" },
}
