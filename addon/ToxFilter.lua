-- ToxFilter — Build 1 Sprint 4b.
-- Live path is deterministic only; no LLM, no network, no automation.
-- Display-only modification of the user's own chat frame.
--
-- Sprint 4b layers visual UI on top of Sprint 4a's data layer: chat-line
-- color tint on captured positive moments (when positive_ui is on and not
-- paused), an animated box-breathing frame, and the /tox ready meta-command
-- that chains grounding → breathing → lift in user-configured order.
--
-- chatFilter dispatch order is master → channel → rule engine → positive
-- capture (pass-through only) → highlight tint (when eligible) → fixtures.

local _, ns = ...

local ADDON_NAME = "ToxFilter"
local VERSION = "0.1.2-sprint5-fix2"

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

-- event name -> user-facing channel key in db.channels.
-- Sprint 4 fix Issue 2: WoW retail no longer routes /p as a separate channel
-- from /instance. CHAT_MSG_PARTY* events are folded into the `instance` key;
-- the slash UI accepts `party` only as an input alias.
local EVENT_TO_CHANNEL = {
    CHAT_MSG_PARTY                  = "instance",
    CHAT_MSG_PARTY_LEADER           = "instance",
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

-- Sprint 5 dispatch order:
--   1. master toggle off → pass
--   2. RuleEngine.classify (read-only; always runs)
--   3. Callout.detectMatching (read-only; runs during pause too — time-critical)
--   4. If paused: only callout tint + sound fire (channel-gated for visual);
--      handling, capture, highlight, fixtures all skip because they involve
--      writes or content modification that Midnight's restricted-execution
--      window doesn't permit. Callout reads classifier output and chat-frame
--      return value + PlaySound — both passive.
--   5. Non-paused, channel-on: handling (silent/del/edit) with flagged-event
--      buffer write.
--   6. Non-paused: PositiveCapture.capture on pass verdict. Whisper privacy
--      carve-out lives inside capture.
--   7. Non-paused, channel-on: co-occurrence resolution. Callout match
--      preempts positive Highlight (callout color wins; sound plays once).
--   8. Non-paused, channel-on: Highlight.tintIfEligible only when no callout
--      match.
--   9. Non-paused, channel-on: Sprint 0 fixtures.
--
-- Architectural principle (Sprint 5): passive UI for emotional support pauses
-- during combat (Sprint 4b's Highlight). Time-critical UI stays active during
-- combat (Sprint 5's Callout). Future sprints adding UI choose a category
-- and follow the rule. Documented in CLAUDE.md.
local function chatFilter(_chatFrame, event, msg, ...)
    if type(msg) ~= "string" or msg == "" then return false end

    local channelEnabled = true
    local db = ns.Database and ns.Database:Get()
    -- Sprint 5 fix diagnostic P1: surface every message that reaches the
    -- filter. Confirms the filter is being invoked for messages 2..N and
    -- isn't being silently bypassed by some upstream chain edit.
    if db and db.debug_enabled then
        print(string.format("[ToxFilter Debug] chatFilter received: '%s' on event %s",
            msg, tostring(event)))
    end
    if db then
        if not db.enabled then return false end
        local channel = EVENT_TO_CHANNEL[event]
        if channel and db.channels[channel] == false then
            channelEnabled = false
        end
    end

    local resolver = (ns.Database and function(cat) return ns.Database:ResolveHandling(cat) end) or nil
    local result = ns.RuleEngine.classify(msg, resolver)

    -- Callout detection runs regardless of pause. Match-vs-user is required —
    -- callouts addressed to other roles still pass through unmodified.
    --
    -- Sprint 5 fix diagnostic: detectMatching is inlined as detect + matchesUser
    -- so P2 (detection result) and P3 (match decision + effective role) can be
    -- surfaced separately. The behavior is unchanged — only the visibility is.
    local callout = nil
    if ns.Callout and result.handling == "pass" and db and db.callout_enabled then
        local detection = ns.Callout.detect(msg, result)
        if db.debug_enabled then
            -- P2: detection result. roles list if found, "nil" if not.
            local roles_str = "nil"
            if detection and detection.roles then
                roles_str = "{" .. table.concat(detection.roles, ",") .. "}"
            end
            print("[ToxFilter Debug] Callout.detect: " .. roles_str
                .. " handling=" .. tostring(result.handling))
        end
        if detection then
            local matches = ns.Callout.matchesUser(detection)
            if db.debug_enabled then
                local eff_role = (ns.Database and ns.Database.GetEffectiveRole)
                    and ns.Database:GetEffectiveRole() or nil
                -- P3: match decision + the effective role used. Catches role
                -- drift (auto unresolved at login window, /tox role switch
                -- between messages, etc.).
                print(string.format(
                    "[ToxFilter Debug] Callout.matchesUser: %s (effective role: %s)",
                    tostring(matches), tostring(eff_role)))
            end
            if matches then callout = detection end
        end
    end

    if isPaused then
        if channelEnabled and callout then
            ns.Callout.playSoundIfEligible(callout)
            local tinted = ns.Callout.tintIfEligible(msg, callout)
            if tinted then return false, tinted, ... end
        end
        return false
    end

    if channelEnabled then
        if result.handling == "silent" then
            if ns.Buffer and result.category then ns.Buffer:RecordFlaggedEvent(result.category, result.severity) end
            return true
        elseif result.handling == "del" then
            if ns.Buffer and result.category then ns.Buffer:RecordFlaggedEvent(result.category, result.severity) end
            return false, ns.RuleEngine.buildDeleteLabel(result), ...
        elseif result.handling == "edit" then
            if ns.Buffer and result.category then ns.Buffer:RecordFlaggedEvent(result.category, result.severity) end
            return false, ns.RuleEngine.buildEditMessage(msg, result), ...
        end
    end

    local moment = nil
    if ns.PositiveCapture and result.handling == "pass" then
        moment = ns.PositiveCapture.capture(msg, result, event)
    end

    -- Co-occurrence: callout match preempts positive highlight. Sound plays
    -- once per matched callout regardless of co-occurrence.
    if channelEnabled and callout then
        ns.Callout.playSoundIfEligible(callout)
        local tinted = ns.Callout.tintIfEligible(msg, callout)
        if tinted then return false, tinted, ... end
    end

    if channelEnabled and moment and ns.Highlight and ns.Highlight.tintIfEligible then
        local tinted = ns.Highlight.tintIfEligible(msg, moment)
        if tinted then return false, tinted, ... end
    end

    if channelEnabled then
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
    local known = { raid = true, instance = true, battleground = true, whisper = true }
    for _, ev in ipairs(CHAT_EVENTS) do
        local ch = EVENT_TO_CHANNEL[ev]
        assert(ch and known[ch], "[ToxFilter] EVENT_TO_CHANNEL missing or unknown for " .. ev)
    end
    assert(EVENT_TO_CHANNEL[WHISPER_EVENT] == "whisper",
           "[ToxFilter] EVENT_TO_CHANNEL missing whisper mapping")
end

-- Sprint 4 fix: Counter scope is dungeon and raid only — battleground, arena,
-- and open-world deaths are deliberately not tracked. GetInstanceInfo's
-- instanceType is the gate.
--
-- Returns (name, instanceType, difficultyID). instanceType is one of
-- "party", "raid", "pvp", "arena", "scenario", "none".
local function instanceInfo()
    if type(GetInstanceInfo) ~= "function" then return nil, "none", nil end
    local name, instanceType, difficultyID = GetInstanceInfo()
    return name, instanceType or "none", difficultyID
end

local function isCountedScope(instanceType)
    return instanceType == "party" or instanceType == "raid"
end

-- Difficulty-ID -> bucket. Stable across recent expansions; documented gaps
-- default to "normal" so we still bucket rather than dropping. Mythic Keystone
-- (8) intentionally returns nil — that's the M+ path, bucketed by keystone
-- level via captureKeystoneBucket below.
--   1  Normal dungeon
--   2  Heroic dungeon
--   8  Mythic Keystone           -> nil (handled by keystone level)
--   23 Mythic dungeon (no key)
--   14 Normal raid
--   15 Heroic raid
--   16 Mythic raid
--   17 LFR                       -> normal
--   33 Timewalking               -> normal
--   24 Story                     -> normal
local DIFFICULTY_TO_BUCKET = {
    [1]  = "normal",
    [2]  = "heroic",
    [8]  = nil,
    [14] = "normal",
    [15] = "heroic",
    [16] = "mythic",
    [17] = "normal",
    [23] = "mythic",
    [24] = "normal",
    [33] = "normal",
}

local function bucketForDifficulty(difficultyID)
    if difficultyID == nil then return nil end
    if difficultyID == 8 then return nil end
    return DIFFICULTY_TO_BUCKET[difficultyID] or "normal"
end

local function bucketForKeystoneLevel(level)
    if not level or level <= 0 then return "M0" end
    if level <= 1 then return "M0" end
    if level <= 5 then return "M2-5" end
    if level <= 10 then return "M6-10" end
    return "M10+"
end

-- Run-bucket state. mplus_bucket is sticky across pulls inside a keystone run
-- (set on CHALLENGE_MODE_START, cleared on COMPLETED/RESET). encounter_bucket
-- is per-pull (set on ENCOUNTER_START, cleared on END). M+ takes precedence.
local mplus_bucket     = nil
local encounter_bucket = nil
local active_instance  = nil

local function captureKeystoneBucket()
    if type(C_ChallengeMode) ~= "table" then return "M0" end
    local fn = C_ChallengeMode.GetActiveKeystoneInfo
    if type(fn) ~= "function" then return "M0" end
    local ok, level = pcall(fn)
    if not ok then return "M0" end
    return bucketForKeystoneLevel(tonumber(level))
end

local function effectiveBucket()
    if mplus_bucket then return mplus_bucket end
    if encounter_bucket then return encounter_bucket end
    -- Fallback for PLAYER_DEAD between pulls / outside an active encounter:
    -- read the current difficulty from the API.
    local _, _, difficultyID = instanceInfo()
    return bucketForDifficulty(difficultyID)
end

ns.ToxFilterState.currentBucket = effectiveBucket
ns.ToxFilterState.activeInstance = function() return active_instance end

function ToxFilter:OnInitialize()
    validateChannelMap()
    if ns.Database then ns.Database:Init() end
    if ns.Buffer then ns.Buffer:Init() end
    if ns.PositiveCapture and ns.Highlight and ns.Highlight.OnPositiveMoment then
        ns.PositiveCapture.subscribe(ns.Highlight.OnPositiveMoment)
    end
end

function ToxFilter:OnEnable()
    validateRuleData()

    for _, event in ipairs(CHAT_EVENTS) do
        ChatFrame_AddMessageEventFilter(event, chatFilter)
    end
    ChatFrame_AddMessageEventFilter(WHISPER_EVENT, chatFilter)

    self:RegisterEvent("ENCOUNTER_START",        "OnEncounterStart")
    self:RegisterEvent("ENCOUNTER_END",          "OnEncounterEnd")
    self:RegisterEvent("CHALLENGE_MODE_START",   "OnChallengeModeStart")
    self:RegisterEvent("CHALLENGE_MODE_COMPLETED", "OnChallengeModeCompleted")
    self:RegisterEvent("CHALLENGE_MODE_RESET",   "OnChallengeModeReset")
    self:RegisterEvent("PLAYER_DEAD",            "OnPlayerDead")

    self:RegisterChatCommand("tox", "OnSlashCommand")

    print("[ToxFilter] Loaded — version " .. VERSION)
    if ns.Callout and ns.Callout.GetStateMismatchNote then
        local note = ns.Callout.GetStateMismatchNote()
        if note then print("[ToxFilter] " .. note) end
    end
end

function ToxFilter:OnDisable()
    for _, event in ipairs(CHAT_EVENTS) do
        ChatFrame_RemoveMessageEventFilter(event, chatFilter)
    end
    ChatFrame_RemoveMessageEventFilter(WHISPER_EVENT, chatFilter)
end

function ToxFilter:OnEncounterStart(_event, _encounterID, _name, difficultyID)
    setPaused(true)
    local instance, instanceType = instanceInfo()
    if isCountedScope(instanceType) then
        active_instance = instance or active_instance
        -- M+ keeps its sticky bucket; only set encounter-level bucket when not
        -- inside an active keystone run.
        if not mplus_bucket then
            encounter_bucket = bucketForDifficulty(difficultyID)
        end
        if ns.Stats and active_instance then
            ns.Stats.OnEncounterStart(active_instance, effectiveBucket())
        end
    end
end

function ToxFilter:OnEncounterEnd(_event, _encounterID, _name, _difficultyID, _groupSize, success)
    setPaused(false)
    local instance, instanceType = instanceInfo()
    if isCountedScope(instanceType) and ns.Buffer then
        local bucket = effectiveBucket()
        if instance and bucket then
            local ok = (success == 1) or (success == true)
            ns.Buffer:RecordEncounter(instance, bucket, ok)
        end
    end
    -- Per-pull bucket clears at end. mplus_bucket is sticky until
    -- CHALLENGE_MODE_COMPLETED/RESET.
    encounter_bucket = nil
end

function ToxFilter:OnChallengeModeStart()
    setPaused(true)
    local instance, instanceType = instanceInfo()
    if isCountedScope(instanceType) then
        active_instance = instance or active_instance
        mplus_bucket = captureKeystoneBucket()
        if ns.Stats and active_instance then
            ns.Stats.OnChallengeModeStart(active_instance, mplus_bucket)
        end
    end
end

function ToxFilter:OnChallengeModeCompleted()
    setPaused(false)
    local instance, instanceType = instanceInfo()
    if isCountedScope(instanceType) and ns.Buffer then
        local bucket = mplus_bucket or effectiveBucket()
        if instance and bucket then
            ns.Buffer:RecordChallengeMode(instance, bucket, true)
        end
    end
    mplus_bucket = nil
    encounter_bucket = nil
end

function ToxFilter:OnChallengeModeReset()
    setPaused(false)
    mplus_bucket = nil
    encounter_bucket = nil
end

-- Sprint 4 fix Issue 6: instance-scope filter. Battleground, arena, scenario,
-- open-world deaths are not tracked. Inside dungeons/raids the locked bucket
-- (M+ or encounter-level) is preferred; falls back to current difficulty so a
-- death between pulls still buckets correctly.
function ToxFilter:OnPlayerDead()
    if not ns.Buffer then return end
    local instance, instanceType = instanceInfo()
    if not isCountedScope(instanceType) then return end
    local bucket = effectiveBucket()
    if instance and bucket then
        ns.Buffer:RecordDeath(instance, bucket)
    end
end

function ToxFilter:OnSlashCommand(input)
    if ns.Commands then
        ns.Commands.dispatch(input)
    end
end
