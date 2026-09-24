-- ============================================================
-- Night City Motorsports: modules/onboarding.lua
-- Versioned, idempotent first-journey and contact-unlock state.
-- Gameplay must never depend on this file saving successfully.
-- ============================================================

local Onboarding = {}
local Persist = require("modules/persistence")

local STORE_FILE = "onboarding.json"
local STORE_VERSION = 1

local MILESTONES = {
    introDelivered = true,
    rookieCareerCreated = true,
    signupMappinShown = true,
    signupReached = true,
    signupCompleted = true,
    dexConversationOpened = true,
    tutorialStarted = true,
    tutorialCompleted = true,
    tutorialSkipped = true,
    firstOfferAccepted = true,
    firstRaceStaged = true,
    firstRaceStarted = true,
    firstRaceCompleted = true,
    firstResultsAcknowledged = true,
    nextRacePromptDelivered = true,
}

local CONTACTS = {
    ncm_motorsports = true,
    ncm_quickie = true,
    ncm_control = true,
    ncm_ledger = true,
    ncm_bookie = true,
    ncm_setup_stu = true,
    ncm_scout = true,
}

local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, entry in pairs(value) do
        result[key] = clone(entry)
    end
    return result
end

local function defaultProfile(careerId)
    return {
        careerId = careerId,
        milestones = {},
        prompts = {},
        unlockedContacts = {
            ncm_motorsports = true,
            ncm_quickie = true,
        },
        contactUnlockReasons = {},
        updatedAt = 0,
    }
end

local function defaultStore()
    return {
        version = STORE_VERSION,
        activeCareerId = nil,
        introDelivered = false,
        profiles = {},
    }
end

Onboarding._store = defaultStore()
Onboarding._persistent = true
Onboarding._session = defaultStore()

local function careerIdOf(career)
    if type(career) == "table" and career.id ~= nil then
        return tostring(career.id)
    end
    if type(career) == "string" and career ~= "" then
        return career
    end
    return nil
end

local function careerRaceCount(career)
    if type(career) ~= "table" then return 0 end
    local statsCount = type(career.stats) == "table" and tonumber(career.stats.racesRun) or 0
    local historyCount = type(career.raceHistory) == "table" and #career.raceHistory or 0
    return math.max(tonumber(statsCount) or 0, historyCount)
end

local function careerHasPart(career)
    if type(career) ~= "table" then return false end
    local state = career.parts or career.garage or career.partInventory
    if type(state) ~= "table" then return false end
    return next(state) ~= nil
end

local function normalizeProfile(profile, careerId)
    if type(profile) ~= "table" then profile = defaultProfile(careerId) end
    profile.careerId = careerId
    if type(profile.milestones) ~= "table" then profile.milestones = {} end
    if type(profile.prompts) ~= "table" then profile.prompts = {} end
    if type(profile.unlockedContacts) ~= "table" then profile.unlockedContacts = {} end
    if type(profile.contactUnlockReasons) ~= "table" then profile.contactUnlockReasons = {} end
    profile.unlockedContacts.ncm_motorsports = true
    profile.unlockedContacts.ncm_quickie = true
    profile.updatedAt = tonumber(profile.updatedAt) or 0
    return profile
end

local function normalizeStore(document)
    local store = type(document) == "table" and document or defaultStore()
    store.version = STORE_VERSION
    store.activeCareerId = careerIdOf(store.activeCareerId)
    store.introDelivered = store.introDelivered == true
    if type(store.profiles) ~= "table" then store.profiles = {} end
    for id, profile in pairs(store.profiles) do
        local normalizedId = tostring(id)
        store.profiles[id] = normalizeProfile(profile, normalizedId)
    end
    return store
end

local function save()
    Onboarding._store.version = STORE_VERSION
    local ok = Persist.save(STORE_FILE, Onboarding._store)
    if not ok then
        if Onboarding._persistent then
            print("[NCM/Onboarding] Persistence unavailable; using session state.")
        end
        Onboarding._persistent = false
        Onboarding._session = clone(Onboarding._store)
    end
    return ok == true
end

local function ensureProfile(career, create)
    local careerId = careerIdOf(career)
    if not careerId then return nil end
    local profile = Onboarding._store.profiles[careerId]
    if type(profile) ~= "table" and create ~= false then
        profile = defaultProfile(careerId)
        Onboarding._store.profiles[careerId] = profile
    end
    if type(profile) == "table" then
        profile = normalizeProfile(profile, careerId)
        Onboarding._store.profiles[careerId] = profile
    end
    Onboarding._store.activeCareerId = careerId
    return profile
end

local function inferEstablishedCareer(career, profile)
    local races = careerRaceCount(career)
    if races <= 0 then return false end

    for _, milestone in ipairs({
        "introDelivered",
        "signupMappinShown",
        "signupReached",
        "signupCompleted",
        "dexConversationOpened",
        "tutorialStarted",
        "tutorialCompleted",
        "firstOfferAccepted",
        "firstRaceStaged",
        "firstRaceStarted",
        "firstRaceCompleted",
        "firstResultsAcknowledged",
        "nextRacePromptDelivered",
    }) do
        profile.milestones[milestone] = true
    end
    profile.unlockedContacts.ncm_control = true
    profile.unlockedContacts.ncm_ledger = true
    if not (career.config and career.config.allowStakes == false) then
        profile.unlockedContacts.ncm_bookie = true
    end
    if races >= 3 or (career.stats and tonumber(career.stats.dnfs or 0) > 0) or careerHasPart(career) then
        profile.unlockedContacts.ncm_setup_stu = true
    end
    if (type(career.bounties) == "table" and next(career.bounties) ~= nil)
       or (type(career.stats) == "table" and tonumber(career.stats.racesRun or 0) > 0) then
        profile.unlockedContacts.ncm_scout = true
    end
    profile.contactUnlockReasons.upgrade_inference = "existing_career"
    return true
end

function Onboarding.init(settings, careers)
    local loaded, createdFresh = Persist.loadVersioned(STORE_FILE, STORE_VERSION, defaultStore(), function(document)
        return normalizeStore(document)
    end)
    Onboarding._store = normalizeStore(loaded)
    Onboarding._persistent = true

    local dirty = createdFresh == true
    local introWasSent = type(settings) == "table" and settings.phoneIntroPingSent == true
    if introWasSent and not Onboarding._store.introDelivered then
        Onboarding._store.introDelivered = true
        dirty = true
    end

    local careerList = {}
    if type(careers) == "table" and type(careers.list) == "function" then
        local ok, result = pcall(careers.list)
        if ok and type(result) == "table" then careerList = result end
    end
    for _, career in ipairs(careerList) do
        local profile = ensureProfile(career, true)
        if inferEstablishedCareer(career, profile) then dirty = true end
    end

    if type(careers) == "table" and type(careers.active) == "function" then
        local ok, activeCareer = pcall(careers.active)
        if ok and activeCareer then ensureProfile(activeCareer, true) end
    end

    if dirty then save() end
    print(string.format("[NCM/Onboarding] Ready. profiles=%d persistent=%s",
        Onboarding.profileCount(), tostring(Onboarding._persistent)))
end

function Onboarding.getState(career)
    local profile = ensureProfile(career, true)
    return profile and clone(profile) or nil
end

function Onboarding.mark(milestone, context)
    milestone = tostring(milestone or "")
    if not MILESTONES[milestone] then return false, "unknown_milestone" end
    context = type(context) == "table" and context or {}

    if milestone == "introDelivered" and not context.career then
        if Onboarding._store.introDelivered then return true, "unchanged" end
        Onboarding._store.introDelivered = true
        save()
        return true, "marked"
    end

    local profile = ensureProfile(context.career, true)
    if not profile then return false, "career_required" end
    if profile.milestones[milestone] == true then return true, "unchanged" end
    profile.milestones[milestone] = true
    profile.updatedAt = os.time()
    if milestone == "introDelivered" then Onboarding._store.introDelivered = true end
    save()
    return true, "marked"
end

function Onboarding.shouldPrompt(promptId, context)
    promptId = tostring(promptId or "")
    if promptId == "" then return false end
    context = type(context) == "table" and context or {}
    local profile = ensureProfile(context.career, context.career ~= nil)
    if profile then return profile.prompts[promptId] ~= true end
    return Onboarding._store.introDelivered ~= true
end

function Onboarding.markPrompt(promptId, context)
    promptId = tostring(promptId or "")
    if promptId == "" then return false, "prompt_required" end
    context = type(context) == "table" and context or {}
    local profile = ensureProfile(context.career, true)
    if not profile then return false, "career_required" end
    if profile.prompts[promptId] == true then return true, "unchanged" end
    profile.prompts[promptId] = true
    profile.updatedAt = os.time()
    save()
    return true, "marked"
end

function Onboarding.unlockContact(contactId, reason, career)
    contactId = tostring(contactId or "")
    if not CONTACTS[contactId] then return false, "unknown_contact" end
    local profile = ensureProfile(career, true)
    if not profile then return false, "career_required" end
    if profile.unlockedContacts[contactId] == true then return true, "unchanged" end
    profile.unlockedContacts[contactId] = true
    profile.contactUnlockReasons[contactId] = tostring(reason or "milestone")
    profile.updatedAt = os.time()
    save()
    return true, "unlocked"
end

function Onboarding.isContactUnlocked(contactId, career)
    local profile = ensureProfile(career, false)
    return profile ~= nil and profile.unlockedContacts[tostring(contactId or "")] == true
end

function Onboarding.reset(careerId)
    local id = careerIdOf(careerId)
    if id then
        Onboarding._store.profiles[id] = nil
        if Onboarding._store.activeCareerId == id then Onboarding._store.activeCareerId = nil end
    else
        Onboarding._store = defaultStore()
    end
    save()
    return true
end

function Onboarding.profileCount()
    local count = 0
    for _ in pairs(Onboarding._store.profiles or {}) do count = count + 1 end
    return count
end

function Onboarding.isPersistent()
    return Onboarding._persistent == true
end

function Onboarding.save()
    return save()
end

return Onboarding
