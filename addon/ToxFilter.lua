-- ToxFilter — Build 1 Sprint 3.
-- Live path is deterministic only; no LLM, no network, no automation.
-- Display-only modification of the user's own chat frame.
--
-- Sprint 3 layers persistence (AceDB-3.0 in addon/Libs/AceDB-3.0/) plus a
-- master toggle, per-channel toggles, category-handling overrides, role
-- preference, user blacklist/whitelist, and a whisper hook (default OFF).
-- chatFilter dispatch order is master → channel → rule engine → fixtures.

local _, ns = ...

local ADDON_NAME = "ToxFilter"
local VERSION = "0.0.4-sprint3-fix1"

local ToxFilter = LibStub("AceAddon-3.0"):NewAddon(
    ADDON_NAME,
    "AceConsole-3.0",
    "AceEvent-3.0"
)

-- Group/raid/instance/BG channels. CHAT_MSG_WHISPER is registered separately
-- because its visibility is gated by the user's per-channel whisper toggle
-- (default OFF, the user opts in deliberately for private 1:1 messages).
local CHAT_EVENTS = {
    "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT",
    "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_BATTLEGROUND",
    "CHAT_MSG_BATTLEGROUND_LEADER",
}

local WHISPER_EVENT = "CHAT_MSG_WHISPER"
-- Intentionally NOT hooked: CHAT_MSG_WHISPER_INFORM is the user's own outgoing
-- whispers; filtering them would be self-censorship of typed text.

-- event name → user-facing channel key in db.channels.
local EVENT_TO_CHANNEL = {
    CHAT_MSG_PARTY                  = "party",
    CHAT_MSG_PARTY_LEADER           = "party",
    CHAT_MSG_RAID                   = "raid",
    CHAT_MSG_RAID_LEADER            = "raid",
    CHAT_MSG_RAID_WARNING           = "raid",
    CHAT_MSG_INSTANCE_CHAT          = "instance",
    CHAT_MSG_INSTANCE_CHAT_LEADER   = "instance",
    CHAT_MSG_BATTLEGROUND           = "battleground",
    CHAT_MSG_BATTLEGROUND_LEADER    = "battleground",
    CHAT_MSG_WHISPER                = "whisper",
}

-- Sprint 0 hardcoded test triggers, kept as architectural-validation fixtures.
-- The rule engine runs first; these only fire when no rule has matched.
local TRIGGER_SILENT  = "ToxFilterTest:Silent"
local TRIGGER_DELETE  = "ToxFilterTest:Del"
local TRIGGER_EDIT    = "ToxFilterTest:Edit"
local TRIGGER_PASS    = "ToxFilterTest:Pass"

local FIXTURE_DELETE_RENDER = "[ToxDel: TestCategory]"
local FIXTURE_EDIT_PREFIX   = "[ToxEdit] "

local isPaused = false

-- Expose addon-internal state Commands.lua needs without giving it write access.
ns.ToxFilterAddon = { VERSION = VERSION }
ns.ToxFilterState = { isPaused = function() return isPaused end }

-- ===== Sprint 0 fixture handlers (unchanged) =====

local function fixtureSurgicalRewrite(msg)
    local body = msg:gsub(TRIGGER_EDIT, "")
    body = body:gsub("%s+", " ")
    body = body:match("^%s*(.-)%s*$") or ""
    if body == "" then
        return "[ToxEdit]"
    end
    return FIXTURE_EDIT_PREFIX .. body
end

local function fixtureVisibleDeletion()
    return FIXTURE_DELETE_RENDER
end

-- ===== Pause state =====

local function setPaused(paused)
    if paused == isPaused then return end
    isPaused = paused
    if paused then
        print("[ToxFilter] Filtering paused — combat window. Filter resumes after pull.")
    else
        print("[ToxFilter] Filtering resumed.")
    end
end

-- ===== Chat filter dispatch =====

-- Sprint 3 dispatch order:
--   1. Paused (Midnight combat window) → pass through
--   2. Master toggle off                → pass through
--   3. Per-channel toggle off            → pass through (covers fixtures too)
--   4. RuleEngine.classify with handling override resolver
--      ├─ user whitelist suppresses rule hits during lookup
--      └─ user blacklist synthesizes general_hostility hits during lookup
--   5. Sprint 0 fixtures (fallback when rule engine returns pass)
local function chatFilter(_chatFrame, event, msg, ...)
    if isPaused then return false end
    if type(msg) ~= "string" or msg == "" then return false end

    local db = ns.Database and ns.Database:Get()
    if db then
        if not db.enabled then return false end
        local channel = EVENT_TO_CHANNEL[event]
        if channel and db.channels[channel] == false then
            return false
        end
    end

    local resolver = (ns.Database and function(cat) return ns.Database:ResolveHandling(cat) end) or nil
    local result = ns.RuleEngine.classify(msg, resolver)
    if result.handling == "silent" then
        return true
    elseif result.handling == "del" then
        return false, ns.RuleEngine.buildDeleteLabel(result), ...
    elseif result.handling == "edit" then
        return false, ns.RuleEngine.buildEditMessage(msg, result), ...
    end

    if msg:find(TRIGGER_SILENT, 1, true) then
        return true
    end
    if msg:find(TRIGGER_DELETE, 1, true) then
        return false, fixtureVisibleDeletion(), ...
    end
    if msg:find(TRIGGER_EDIT, 1, true) then
        return false, fixtureSurgicalRewrite(msg), ...
    end
    if msg:find(TRIGGER_PASS, 1, true) then
        return false
    end
    return false
end

-- ===== Lifecycle =====

local function validateRuleData()
    if not ns.RuleData then
        print("[ToxFilter] Rule data missing — running with no rules. Rebuild with ./scripts/build-rules.sh")
        return
    end
    if ns.RuleData.hash_version ~= ns.Hash.HASH_VERSION then
        print("[ToxFilter] Rule data hash version mismatch (" .. tostring(ns.RuleData.hash_version)
              .. " vs " .. ns.Hash.HASH_VERSION .. ") — rules disabled until rebuild")
        ns.RuleData = nil
        return
    end
    if ns.RuleData.normalization_version ~= ns.Normalize.NORMALIZATION_VERSION then
        print("[ToxFilter] Rule data normalization version mismatch (" .. tostring(ns.RuleData.normalization_version)
              .. " vs " .. ns.Normalize.NORMALIZATION_VERSION .. ") — rules disabled until rebuild")
        ns.RuleData = nil
        return
    end
end

-- Sanity check: every event in CHAT_EVENTS / WHISPER_EVENT must map to a known
-- channel key. Catches typos at load instead of when a user runs /tox channel.
local function validateChannelMap()
    local known = { party = true, raid = true, instance = true, battleground = true, whisper = true }
    for _, ev in ipairs(CHAT_EVENTS) do
        local ch = EVENT_TO_CHANNEL[ev]
        assert(ch and known[ch], "[ToxFilter] EVENT_TO_CHANNEL missing or unknown for " .. ev)
    end
    assert(EVENT_TO_CHANNEL[WHISPER_EVENT] == "whisper",
           "[ToxFilter] EVENT_TO_CHANNEL missing whisper mapping")
end

function ToxFilter:OnInitialize()
    validateChannelMap()
    if ns.Database then ns.Database:Init() end
end

function ToxFilter:OnEnable()
    validateRuleData()

    for _, event in ipairs(CHAT_EVENTS) do
        ChatFrame_AddMessageEventFilter(event, chatFilter)
    end
    ChatFrame_AddMessageEventFilter(WHISPER_EVENT, chatFilter)

    self:RegisterEvent("ENCOUNTER_START", "OnPauseEvent")
    self:RegisterEvent("ENCOUNTER_END", "OnResumeEvent")
    self:RegisterEvent("CHALLENGE_MODE_START", "OnPauseEvent")
    self:RegisterEvent("CHALLENGE_MODE_COMPLETED", "OnResumeEvent")
    self:RegisterEvent("CHALLENGE_MODE_RESET", "OnResumeEvent")

    self:RegisterChatCommand("tox", "OnSlashCommand")

    print("[ToxFilter] Loaded — version " .. VERSION)
end

function ToxFilter:OnDisable()
    for _, event in ipairs(CHAT_EVENTS) do
        ChatFrame_RemoveMessageEventFilter(event, chatFilter)
    end
    ChatFrame_RemoveMessageEventFilter(WHISPER_EVENT, chatFilter)
end

function ToxFilter:OnPauseEvent()
    setPaused(true)
end

function ToxFilter:OnResumeEvent()
    setPaused(false)
end

function ToxFilter:OnSlashCommand(input)
    if ns.Commands then
        ns.Commands.dispatch(input)
    end
end
