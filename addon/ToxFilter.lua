-- ToxFilter — Sprint 2.
-- Live path is deterministic only; no LLM, no network, no automation.
-- Display-only modification of the user's own chat frame.

local _, ns = ...

local ADDON_NAME = "ToxFilter"
local VERSION = "0.0.3-sprint2"

local ToxFilter = LibStub("AceAddon-3.0"):NewAddon(
    ADDON_NAME,
    "AceConsole-3.0",
    "AceEvent-3.0"
)

-- Incoming group/raid/instance/BG channels. Whisper deferred to Sprint 3.
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

-- Sprint 0 hardcoded test triggers, kept as architectural-validation fixtures.
-- The rule engine runs first; these only fire when no rule has matched.
local TRIGGER_SILENT  = "ToxFilterTest:Silent"
local TRIGGER_DELETE  = "ToxFilterTest:Del"
local TRIGGER_EDIT    = "ToxFilterTest:Edit"
local TRIGGER_PASS    = "ToxFilterTest:Pass"

local FIXTURE_DELETE_RENDER = "[ToxDel: TestCategory]"
local FIXTURE_EDIT_PREFIX   = "[ToxEdit] "

local isPaused = false

-- ===== Sprint 0 fixture handlers (unchanged from Sprint 0) =====

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

-- Order: rule engine → Sprint 0 fixtures → pass-through. Rule engine wins on
-- collision so a real rule hit is never overridden by a fixture trigger.
-- Returns per ChatFrame_AddMessageEventFilter contract:
--   true                       -> suppress entirely
--   false                      -> display unchanged
--   false, newMsg, ...         -> display with rewritten msg, other args preserved
local function chatFilter(_chatFrame, _event, msg, ...)
    if isPaused then
        return false
    end
    if type(msg) ~= "string" or msg == "" then
        return false
    end

    local result = ns.RuleEngine.classify(msg)
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

function ToxFilter:OnEnable()
    validateRuleData()

    for _, event in ipairs(CHAT_EVENTS) do
        ChatFrame_AddMessageEventFilter(event, chatFilter)
    end

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
end

function ToxFilter:OnPauseEvent()
    setPaused(true)
end

function ToxFilter:OnResumeEvent()
    setPaused(false)
end

-- ===== Slash command =====

local function printRules()
    if not ns.RuleData then
        print("[ToxFilter] Rule data not loaded")
        return
    end
    print("[ToxFilter] Rule data: " .. ns.RuleData.hash_version
          .. " / " .. ns.RuleData.normalization_version)
    print("[ToxFilter] Generated: " .. (ns.RuleData.generated_at or "unknown"))
    print("[ToxFilter] Words: " .. ns.RuleData.stats.word_count
          .. ", Phrases: " .. ns.RuleData.stats.phrase_count)

    local counts = {}
    for _, entry in pairs(ns.RuleData.words) do
        counts[entry.category] = (counts[entry.category] or 0) + 1
    end
    local parts = {}
    for cat, n in pairs(counts) do
        parts[#parts + 1] = cat .. "=" .. n
    end
    table.sort(parts)
    if #parts > 0 then
        print("[ToxFilter] By category: " .. table.concat(parts, ", "))
    end
end

local function printTest(rest)
    if not rest or rest == "" then
        print("[ToxFilter] Usage: /tox test <message>")
        return
    end
    local result = ns.RuleEngine.classify(rest)
    local line = "[ToxFilter] Test result: '" .. rest .. "' → " .. result.handling
    if result.category then
        local extra = ""
        local others = (result.hits or 1) - 1
        if others == 1 then
            extra = ", +1 other hit"
        elseif others > 1 then
            extra = ", +" .. others .. " other hits"
        end
        line = line .. " (" .. result.category .. extra .. ")"
    end
    print(line)
end

local function spanByLabel(raw_tokens, labels, target)
    if not raw_tokens or not labels then return "" end
    local out = {}
    for i = 1, #raw_tokens do
        if (labels[i] or "neutral") == target then
            out[#out + 1] = raw_tokens[i]
        end
    end
    return table.concat(out, " ")
end

local function signalsList(signals)
    local list = {}
    if signals then
        for k, v in pairs(signals) do
            if v then list[#list + 1] = k end
        end
    end
    table.sort(list)
    return list
end

local function printClassify(rest)
    if not rest or rest == "" then
        print("[ToxFilter] Usage: /tox classify <message>")
        return
    end
    local result = ns.RuleEngine.classify(rest)
    local cat = result.category or "pass"
    local attack   = spanByLabel(result.raw_tokens, result.labels, "attack")
    local tactical = spanByLabel(result.raw_tokens, result.labels, "tactical")
    local sigs = signalsList(result.signals)
    local sig_str = (#sigs == 0) and "(none)" or table.concat(sigs, ", ")
    print("[ToxFilter] Classify: '" .. rest .. "' → " .. cat
          .. " | attack: '" .. attack .. "'"
          .. " | tactical: '" .. tactical .. "'"
          .. " | signals: " .. sig_str)
end

local function printRewrite(rest)
    if not rest or rest == "" then
        print("[ToxFilter] Usage: /tox rewrite <message>")
        return
    end
    local result = ns.RuleEngine.classify(rest)
    local rendered
    if result.handling == "silent" then
        rendered = "(silent — line would not render)"
    elseif result.handling == "del" then
        rendered = ns.RuleEngine.buildDeleteLabel(result)
    elseif result.handling == "edit" then
        rendered = ns.Rewrite.rewrite(rest, result)
    else
        rendered = "(pass-through) " .. rest
    end
    print("[ToxFilter] Rewrite: '" .. rest .. "' → '" .. rendered .. "'")
end

function ToxFilter:OnSlashCommand(input)
    input = input and input:match("^%s*(.-)%s*$") or ""
    local sub, rest = input:match("^(%S+)%s*(.*)$")
    sub = sub or ""
    rest = rest or ""

    if sub == "status" then
        if isPaused then
            print("[ToxFilter] Paused — combat window")
        else
            print("[ToxFilter] Active")
        end
    elseif sub == "version" then
        print("[ToxFilter] Version " .. VERSION)
    elseif sub == "rules" then
        printRules()
    elseif sub == "test" then
        printTest(rest)
    elseif sub == "classify" then
        printClassify(rest)
    elseif sub == "rewrite" then
        printRewrite(rest)
    else
        print("[ToxFilter] Commands: /tox status | /tox version | /tox rules"
              .. " | /tox test <message> | /tox classify <message> | /tox rewrite <message>")
    end
end
