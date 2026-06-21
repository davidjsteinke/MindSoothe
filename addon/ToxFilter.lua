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
local VERSION = "0.7.0-sprint7a-fix"

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
    -- CHAT_MSG_BATTLEGROUND / _LEADER were REMOVED from the WoW API (verified
    -- against warcraft.wiki.gg). Battleground and other instanced-PvP group chat
    -- now arrives via CHAT_MSG_INSTANCE_CHAT (above). The old names were silently
    -- tolerated by ChatFrame_AddMessageEventFilter (the filter just never fired
    -- for them) but a since-removed RegisterEvent experiment (the N12 in-combat
    -- chat attempt, now deleted) validates event names and threw on them,
    -- aborting OnEnable before the slash-command registration ran — hence
    -- "GUI works, /tox dead". The vestigial
    -- `battleground` channel toggle (db.channels / Options / Commands) is left
    -- in place for now; BG chat is gated under `instance` via INSTANCE_CHAT. 7b
    -- should reconcile or retire that toggle.
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
    -- (CHAT_MSG_BATTLEGROUND* removed from the API — see CHAT_EVENTS note. BG
    -- chat now arrives as CHAT_MSG_INSTANCE_CHAT and is gated under `instance`.)
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

-- Sprint 7a (N12, final): there is no in-combat chat handler. Midnight delivers
-- the chat message text to in-combat event handlers as a SECRET/tainted value —
-- it cannot even be read or compared while execution is tainted in combat
-- (`attempt to compare local 'msg' (a secret string value...)`). So no addon can
-- inspect chat during a boss fight; callouts are out-of-combat-only, via the
-- chat-filter tint path (original Sprint 5 behavior). During the combat pause NO
-- callout code runs at all. The earlier AceEvent OnCombatChat experiment, its
-- role cache, and the RaidWarningFrame in-combat surface have all been removed.

-- ===== Chat filter dispatch =====

-- Dispatch order (authoritative version in CLAUDE.md; updated for Sprint 7a + N12):
--   1. master toggle off → pass
--   2. RuleEngine.classify (read-only; always runs)
--   3. Callout.detect + matchesUser (read-only). NOTE (N12): the paused branch
--      below is never invoked in combat, so callouts are out-of-combat-only.
--   4. If paused: callout tint + sound, else the F1 CombatDrop silent-drop
--      carve-out, else pass. NOTE (N12): in real combat the filter is not
--      invoked, so this whole paused branch is dead code — retained only for the
--      pause-dispatch guard. F1 is paused-branch-only, hence inert (see
--      CombatDrop.lua).
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
-- Architectural principle (Sprint 5; amended by N12): passive UI for emotional
-- support pauses during combat (Sprint 4b's Highlight). Time-critical callouts
-- were intended to stay active in combat, but N12 proved that is impossible on
-- Midnight (the filter is not invoked and chat text is tainted), so callouts are
-- out-of-combat-only too. The only UI that works in combat is pull-boundary,
-- pre-registered surfaces (TacticReminders). Documented in CLAUDE.md.
local function chatFilter(_chatFrame, event, msg, ...)
    if type(msg) ~= "string" or msg == "" then return false end

    local channelEnabled = true
    local db = ns.Database and ns.Database:Get()
    -- Sprint 5 fix diagnostic P1: surface every message that reaches the
    -- filter. Confirms the filter is being invoked for messages 2..N and
    -- isn't being silently bypassed by some upstream chain edit. The isPaused
    -- value is included (Sprint 7a N12 trace): if a callout fails to fire during
    -- combat, this line answers the first question — is chatFilter even invoked
    -- during the Midnight restricted window, and does it know it is paused? If
    -- this line does NOT print while paused, the suppression is upstream of the
    -- filter (Blizzard's restricted execution), not in the dispatch below.
    if db and db.debug_enabled then
        print(string.format("[ToxFilter Debug] chatFilter received: '%s' on event %s (isPaused=%s)",
            msg, tostring(event), tostring(isPaused)))
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
    -- Sprint 5d: callouts are an Uplifter feature. Gating detection here keeps
    -- callout nil when the category (or the addon master) is off, so both the
    -- paused and non-paused branches below skip tint+sound with no further check.
    local callout = nil
    if ns.Callout and result.handling == "pass" and db and db.callout_enabled
        and ns.Category and ns.Category.gate("uplifter") then
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
        -- Sprint 7a (F1) / 7b (N12): this would silent-drop high-confidence pure
        -- hostility, but the paused branch is never invoked in combat (N12), so it
        -- is dead code — kept for the pause-dispatch guard. CombatDrop.shouldDrop
        -- folds in the toggle + ToxFilter category (+ master); channelEnabled keeps
        -- it consistent with the non-combat handling path. The flagged-event write
        -- (were it ever reached) would store classification metadata only (category,
        -- combat flag), never the body — combat drops are pure third-party hostility.
        if channelEnabled and ns.CombatDrop and ns.CombatDrop.shouldDrop(result) then
            if ns.Buffer and result.category then
                ns.Buffer:RecordFlaggedEvent(result.category, result.severity, true)
            end
            return true
        end
        -- Sprint 7a (F1) / 7b (N12): this combat-path ToxFilterTest:Silent branch
        -- is also dead in combat (paused branch not invoked). The working in-game
        -- silent test runs through the non-paused Sprint 0 fixture (step 9). Gated
        -- by the same toggle + ToxFilter category. No flagged-event write (it's a
        -- test trigger).
        if channelEnabled and db and db.combat_silent_drop
           and ns.Category and ns.Category.gate("toxfilter")
           and msg:find(TRIGGER_SILENT, 1, true) then
            return true
        end
        return false
    end

    -- Sprint 5d: rule-engine handling (silent/del/edit) and the flagged-event
    -- writes it drives are the ToxFilter family. Category off → no chat
    -- modification; the message passes through unmodified. Channel-off retains
    -- its existing meaning (Sprint 4 fix2) and is checked alongside.
    if channelEnabled and ns.Category and ns.Category.gate("toxfilter") then
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
    local sender = nil
    if ns.PositiveCapture and result.handling == "pass" then
        -- Sprint 6: the CHAT_MSG_* author (event arg2, first of ...) is the
        -- authoritative source for the sender's name; thread it to the scrubber
        -- so it can strip the sender's name from the stored body. Reading the
        -- vararg does not consume it — the ... pass-through below is unaffected.
        sender = ...
        moment = ns.PositiveCapture.capture(msg, result, event, sender)
    end

    -- Co-occurrence: callout match preempts positive highlight. Sound plays
    -- once per matched callout regardless of co-occurrence.
    if channelEnabled and callout then
        ns.Callout.playSoundIfEligible(callout)
        local tinted = ns.Callout.tintIfEligible(msg, callout)
        if tinted then return false, tinted, ... end
    end

    -- Sprint 7b bugfix: tint and record are SEPARATE decisions. capture() above
    -- records only praise directed at the user from someone else (returns the
    -- recorded moment or nil). The green tint stays BROAD — it fires on any
    -- detected group positivity (direct, bare thanks, third-party) so chat keeps
    -- emphasizing the room's positivity — EXCEPT the user's own outgoing praise,
    -- which isSelfSender excludes from both record and tint. So: tint when there
    -- is a tint target (the recorded moment, else a broad detect()) AND the line
    -- is not the user's own. Still Uplifter-gated, channel-gated, and pass-only
    -- (a del/edit message that passed through with the ToxFilter category off
    -- must never be tinted). detect() is cheap and re-run only on the no-record path.
    if channelEnabled and result.handling == "pass"
        and ns.Category and ns.Category.gate("uplifter")
        and ns.Highlight and ns.Highlight.tintIfEligible
        and ns.PositiveCapture
        and not (ns.PositiveCapture.isSelfSender and ns.PositiveCapture.isSelfSender(sender)) then
        local tintMoment = moment
        if not tintMoment and ns.PositiveCapture.detect then
            tintMoment = ns.PositiveCapture.detect(result.normalized_tokens, result.signals)
        end
        if tintMoment then
            local tinted = ns.Highlight.tintIfEligible(msg, tintMoment)
            if tinted then return false, tinted, ... end
        end
    end

    -- Sprint 5d: Sprint 0 fixtures perform chat modification, so they ride with
    -- the ToxFilter category — category off → fixtures inert.
    if channelEnabled and ns.Category and ns.Category.gate("toxfilter") then
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

-- Test-only hooks: expose the live chatFilter and a paused setter so the corpus
-- harness can drive the REAL dispatch through the combat-pause state. Not
-- referenced by any production path; pure visibility.
ns.ToxFilterDispatch = {
    chatFilter       = chatFilter,
    setPausedForTest = function(v) isPaused = v and true or false end,
}

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
    -- Sprint 5b: tactic_reminders_seen is session-scoped. Clearing in
    -- OnInitialize (which runs on every /reload) re-arms reminders each
    -- session despite the db storage of the map.
    if ns.TacticReminders then ns.TacticReminders.ResetSession() end
    -- Sprint 5c: predungeon_warnings_seen is session-scoped, same as the
    -- reminders seen-map. Clear on every /reload to re-arm per-key warnings.
    if ns.PreDungeon then ns.PreDungeon.ResetSession() end
    -- Sprint 6b: register the AceConfig options panel into the Blizzard AddOns
    -- menu. Runs after Database:Init so the panel's get/set see a live db.
    if ns.Options then ns.Options.Register() end
end

function ToxFilter:OnEnable()
    -- Hardening (Sprint 7a N12 fix): register the slash command FIRST, before any
    -- RegisterEvent. RegisterEvent throws on an event name the client doesn't
    -- know (this is exactly how the removed CHAT_MSG_BATTLEGROUND aborted OnEnable
    -- and took /tox down with it). Registering slash up front means no later
    -- event-registration failure can ever skip it again — the addon stays
    -- controllable even if a future client patch invalidates an event name.
    self:RegisterChatCommand("tox", "OnSlashCommand")

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
    -- Sprint 7a (F4): emote-directed positive capture. Not a chat-frame filter
    -- (we don't modify emotes); a plain event subscription that feeds capture.
    self:RegisterEvent("CHAT_MSG_TEXT_EMOTE",    "OnTextEmote")
    -- Sprint 7a (N12, final): NO AceEvent subscription on the group CHAT_MSG_*
    -- channels. In-combat chat is uninspectable — Midnight delivers `msg` as a
    -- secret/tainted value to in-combat handlers — so there is no in-combat
    -- callout handler. Callouts ride the out-of-combat chat-filter tint path only.

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

function ToxFilter:OnEncounterStart(_event, _encounterID, encounterName, difficultyID)
    local instance, instanceType = instanceInfo()
    if isCountedScope(instanceType) then
        active_instance = instance or active_instance
        -- M+ keeps its sticky bucket; only set encounter-level bucket when not
        -- inside an active keystone run.
        if not mplus_bucket then
            encounter_bucket = bucketForDifficulty(difficultyID)
        end
        -- Sprint 5b: surface tactical reminders BEFORE setPaused(true).
        -- TacticReminders.Surface has a defensive isPaused() guard for any
        -- future caller; the natural path here pre-pause keeps the gate
        -- consistent with "pre-pull" semantics. effectiveBucket() picks up
        -- the just-set encounter_bucket / sticky mplus_bucket.
        if ns.TacticReminders and active_instance and encounterName then
            ns.TacticReminders.Surface(active_instance, encounterName, effectiveBucket())
        end
        if ns.Stats and active_instance then
            ns.Stats.OnEncounterStart(active_instance, effectiveBucket())
        end
    end
    setPaused(true)
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
    -- Sprint 5c: surface per-key pre-dungeon warnings BEFORE setPaused(true).
    -- PreDungeon.Surface has a defensive isPaused() guard for any future
    -- caller; firing here pre-pause keeps the gate consistent with the
    -- "during the countdown" semantics and avoids the guard blocking the
    -- natural path (same trap as Sprint 5b's TacticReminders at ENCOUNTER_START).
    local instance, instanceType = instanceInfo()
    if isCountedScope(instanceType) then
        active_instance = instance or active_instance
        mplus_bucket = captureKeystoneBucket()
        if ns.PreDungeon and active_instance then
            ns.PreDungeon.Surface(active_instance)
        end
        if ns.Stats and active_instance then
            ns.Stats.OnChallengeModeStart(active_instance, mplus_bucket)
        end
    end
    setPaused(true)
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

-- Sprint 7a (F4): CHAT_MSG_TEXT_EMOTE → positive capture. arg1 is the rendered
-- emote text ("<Name> thanks you."), arg2 the sender. Self-gates on the Uplifter
-- category inside captureEmote; enUS-only detection (documented limitation).
function ToxFilter:OnTextEmote(_event, text, sender, ...)
    if not (ns.PositiveCapture and ns.PositiveCapture.captureEmote) then return end
    -- CHAT_MSG_TEXT_EMOTE also fires for NPC / system / boss emotes (a Delve
    -- completion, a vendor closing), not just player /emotes. The event delivers
    -- the source unit's GUID among its trailing args (arg12 in the documented
    -- layout). Scan for it defensively rather than trust a fixed position, so a
    -- future arg-layout shift can't silently misclassify a player as an NPC.
    -- captureEmote uses the GUID to drop non-player emotes BEFORE touching the
    -- emote text — which also keeps us off any secret/tainted text an NPC /
    -- restricted-window emote may deliver (the same secret-value class as N12;
    -- captureEmote 337's `text == ""` compare threw on a Delve-end / vendor-close
    -- emote whose text was tainted).
    local guid
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "string" and v:match("^%a+%-%d") then guid = v; break end
    end
    ns.PositiveCapture.captureEmote(text, sender, guid)
end

function ToxFilter:OnSlashCommand(input)
    if ns.Commands then
        ns.Commands.dispatch(input)
    end
end
