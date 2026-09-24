local Archetypes = {}

Archetypes.MAX_ACTIVE_EVENTS = 2
Archetypes.COOLDOWN_RACE_GAP = 2
Archetypes.INTEL_EXPIRY_RACES = 3
Archetypes.DEFAULT_OFFER_EXPIRY_RACES = 3

Archetypes.ACTOR_POOLS = {
    rival_mechanic = {
        "Jax",
        "Leda",
        "Timo",
        "Iris",
        "Vale",
    },
    independent_tuner = {
        "Hex",
        "Morrow",
        "Taji",
        "Rin",
        "Kells",
    },
    scavenger = {
        "Scrap",
        "Lockjaw",
        "Mica",
        "Spindle",
    },
    fan = {
        "Glow",
        "Sparx",
        "Meli",
    },
    crew_member = {
        "Stu",
        "Marrow",
        "Kade",
    },
}

Archetypes.LIST = {
    rival_mechanic_leak = {
        id = "rival_mechanic_leak",
        archetype = "intel_leak",
        triggerTypes = { "post_race", "rivalry_proximity" },
        sourceActor = {
            type = "rival_mechanic",
            relationship = "hostile",
        },
        intent = {
            type = "revenge",
            description = "A rival-side mechanic wants payback through a clean leak.",
        },
        offer = { type = "intel" },
        riskProfile = { level = "low", visibility = "explicit" },
        systemImpact = { type = "information_advantage" },
        legibility = { level = "clear" },
        deliveryContactId = "ncm_scout",
    },
    tuner_counter_build = {
        id = "tuner_counter_build",
        archetype = "counter_build_offer",
        triggerTypes = { "post_race", "losing_streak" },
        sourceActor = {
            type = "independent_tuner",
            relationship = "opportunistic",
        },
        intent = {
            type = "profit",
            description = "An independent tuner sees a weakness and wants to sell the correction.",
        },
        offer = { type = "part" },
        riskProfile = { level = "medium", visibility = "explicit" },
        systemImpact = { type = "performance_modifier" },
        legibility = { level = "clear" },
        deliveryContactId = "ncm_setup_stu",
    },
    scavenger_experimental_deal = {
        id = "scavenger_experimental_deal",
        archetype = "risky_part_deal",
        triggerTypes = { "post_race", "random_low_prob" },
        sourceActor = {
            type = "scavenger",
            relationship = "opportunistic",
        },
        intent = {
            type = "desperation",
            description = "A scavenger has unstable hardware and wants it gone fast.",
        },
        offer = { type = "part" },
        riskProfile = { level = "high", visibility = "implied" },
        systemImpact = { type = "volatility_injection" },
        legibility = { level = "readable" },
        requiresTradeoff = true,
        deliveryContactId = "ncm_scout",
    },
    fan_build_reflection = {
        id = "fan_build_reflection",
        archetype = "build_reflection",
        triggerTypes = { "winning_streak", "post_race" },
        sourceActor = {
            type = "fan",
            relationship = "supportive",
        },
        intent = {
            type = "admiration",
            description = "A fan reflects the player's current build identity back at them.",
        },
        offer = { type = "nothing" },
        riskProfile = { level = "low", visibility = "explicit" },
        systemImpact = { type = "relationship_shift" },
        legibility = { level = "clear" },
        deliveryContactId = "ncm_ledger",
    },
    crew_warning = {
        id = "crew_warning",
        archetype = "crew_warning",
        triggerTypes = { "losing_streak", "post_race" },
        sourceActor = {
            type = "crew_member",
            relationship = "supportive",
        },
        intent = {
            type = "alliance",
            description = "A crew-side warning pushes the player to stop leaning on the wrong axis.",
        },
        offer = { type = "nothing" },
        riskProfile = { level = "low", visibility = "explicit" },
        systemImpact = { type = "information_advantage" },
        legibility = { level = "clear" },
        deliveryContactId = "ncm_setup_stu",
    },
    tuner_setup_contract = {
        id = "tuner_setup_contract",
        archetype = "setup_contract",
        triggerTypes = { "losing_streak", "prestige_up" },
        sourceActor = {
            type = "independent_tuner",
            relationship = "supportive",
        },
        intent = {
            type = "profit",
            description = "A tuner offers a focused two-piece package, but waits for the player to sign off.",
        },
        offer = { type = "contract" },
        riskProfile = { level = "medium", visibility = "explicit" },
        systemImpact = { type = "performance_modifier" },
        legibility = { level = "clear" },
        deliveryContactId = "ncm_setup_stu",
    },
    rival_heat_warning = {
        id = "rival_heat_warning",
        archetype = "rival_heat_warning",
        triggerTypes = { "rivalry_proximity", "season_pressure" },
        sourceActor = {
            type = "rival_mechanic",
            relationship = "hostile",
        },
        intent = {
            type = "pressure",
            description = "A rival-side source warns that a specific rival is already adapting to the player's rise.",
        },
        offer = { type = "intel" },
        riskProfile = { level = "medium", visibility = "explicit" },
        systemImpact = { type = "information_advantage" },
        legibility = { level = "clear" },
        deliveryContactId = "ncm_scout",
    },
    tier_streetkid_promotion_contract = {
        id = "tier_streetkid_promotion_contract",
        archetype = "tier_promotion_contract",
        triggerTypes = { "prestige_up" },
        sourceActor = {
            type = "crew_member",
            relationship = "supportive",
        },
        intent = {
            type = "alliance",
            description = "A Streetkid-tier step unlocks a more focused setup contact pitch.",
        },
        offer = { type = "contract" },
        riskProfile = { level = "low", visibility = "explicit" },
        systemImpact = { type = "performance_modifier" },
        legibility = { level = "clear" },
        deliveryContactId = "ncm_setup_stu",
    },
    tier_solo_promotion_contract = {
        id = "tier_solo_promotion_contract",
        archetype = "tier_promotion_contract",
        triggerTypes = { "prestige_up" },
        sourceActor = {
            type = "independent_tuner",
            relationship = "opportunistic",
        },
        intent = {
            type = "profit",
            description = "Solo-tier promotion attracts harder, more focused hardware contracts.",
        },
        offer = { type = "contract" },
        riskProfile = { level = "medium", visibility = "explicit" },
        systemImpact = { type = "performance_modifier" },
        legibility = { level = "clear" },
        deliveryContactId = "ncm_setup_stu",
    },
    tier_fixer_promotion_contract = {
        id = "tier_fixer_promotion_contract",
        archetype = "tier_promotion_contract",
        triggerTypes = { "prestige_up" },
        sourceActor = {
            type = "crew_member",
            relationship = "supportive",
        },
        intent = {
            type = "alliance",
            description = "Fixer-tier promotion opens cleaner backchannel deals around stability and control.",
        },
        offer = { type = "contract" },
        riskProfile = { level = "medium", visibility = "explicit" },
        systemImpact = { type = "performance_modifier" },
        legibility = { level = "clear" },
        deliveryContactId = "ncm_setup_stu",
    },
    tier_edgerunner_promotion_contract = {
        id = "tier_edgerunner_promotion_contract",
        archetype = "tier_promotion_contract",
        triggerTypes = { "prestige_up" },
        sourceActor = {
            type = "independent_tuner",
            relationship = "opportunistic",
        },
        intent = {
            type = "ambition",
            description = "Edgerunner-tier promotion unlocks volatile, high-end contract packs.",
        },
        offer = { type = "contract" },
        riskProfile = { level = "high", visibility = "explicit" },
        systemImpact = { type = "volatility_injection" },
        legibility = { level = "clear" },
        deliveryContactId = "ncm_setup_stu",
    },
}

function Archetypes.get(id)
    return Archetypes.LIST[id]
end

function Archetypes.actorPool(actorType)
    return Archetypes.ACTOR_POOLS[tostring(actorType or "")] or {}
end

return Archetypes