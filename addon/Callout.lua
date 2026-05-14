-- Sprint 5: tactical role-callout detection + visual/audio prioritization.
--
-- When a message contains a tactical callout addressed to the user's effective
-- role, apply a warm-amber color tint and play a subtle audio cue. Opt-in via
-- /tox callout on; off by default. Visual and audio have independent sub-
-- toggles for users in voice chat who want one but not the other.
--
-- Time-critical UI: unlike Sprint 4b's positive-moment Highlight (which pauses
-- during combat because positive moments can be reviewed later), callouts fire
-- DURING combat too. That's when most callouts happen and when missing them
-- costs the most. Architectural principle (documented in CLAUDE.md): passive
-- UI for emotional support pauses; time-critical UI stays active.
--
-- Color register: |cFFEEBB55 (warm amber). Discriminable from Sprint 4b's
-- positive green |cFF66AA66 under deuteranopia, protanopia, and tritanopia by
-- lightness gap and red-channel difference. Warning register ("look here")
-- rather than celebratory. Subtle enough not to scream. See CLAUDE.md for the
-- full color-choice reasoning; future sprints check this list before picking
-- their tint register.
--
-- Sound: FileDataID 540061 via PlaySound(..., "Master"). One line to swap if
-- in-game testing shows it's too associated with another event. The "Master"
-- channel routes through master volume per spec.
--
-- WoW chat-frame escape sequences |c<AARRGGBB> and |r are functional control
-- codes — single pipe, NOT doubled. The Sprint 3 fix1 pipe-doubling rule
-- applies only to literal display pipes.

local _, ns = ...

local Callout = {}

local TINT_OPEN  = "|cFFEEBB55"
local TINT_CLOSE = "|r"

-- Sound ID. Sprint 5 originally picked 540061 from documentation; in-client
-- testing showed it was silent (`/run PlaySound(540061)` produced no audio,
-- `/run PlaySound(8959)` was audible — confirms client + speakers work).
-- Swapped to 8960 (READY_CHECK) in Sprint 5 fix: semantically "pay attention,
-- please respond" aligns with the role-callout intent, and the sound is known
-- audible. PlaySound's "Master" channel routes through master volume per spec.
-- Lesson: PlaySound IDs from documentation/databases require in-game verification
-- before locking — the silent-vs-audible distinction isn't always documented.
local CALLOUT_SOUND_ID      = 8960
local CALLOUT_SOUND_CHANNEL = "Master"

local ROLE_WINDOW = 3

local function db()
    return ns.Database and ns.Database:Get() or nil
end

-- Callout-local tokenization. Splits on whitespace AND `/` so "tank/healer"
-- parses as two tokens. Doesn't go through Normalize because Callout doesn't
-- need hash-table alignment — it works on the raw message directly.
-- Lowercases each token and strips a small punctuation set so trailing
-- commas / periods don't break role-target matching.
local TRIM_CHARS = { [","] = true, ["."] = true, ["!"] = true, ["?"] = true,
                     [";"] = true, [":"] = true }
local function trim_punct(tok)
    local n = #tok
    while n > 0 and TRIM_CHARS[tok:sub(n, n)] do n = n - 1 end
    local i = 1
    while i <= n and TRIM_CHARS[tok:sub(i, i)] do i = i + 1 end
    return tok:sub(i, n)
end

local function tokenize(msg)
    local out = {}
    -- Replace `/` with space so "tank/healer" splits. Other word-internal
    -- punctuation (comma, period) handled by trim_punct per token.
    local replaced = msg:gsub("/", " ")
    for raw in replaced:gmatch("%S+") do
        local trimmed = trim_punct(raw):lower()
        if trimmed ~= "" then out[#out + 1] = trimmed end
    end
    return out
end

Callout.tokenize = tokenize

local function classifierSarcasm(classifier_result)
    local s = classifier_result and classifier_result.signals
    if not s then return false end
    return s.sarcasm_antonymic_praise
        or s.sarcasm_passive_thanks
        or s.sarcasm_slash_s
        or s.sarcasm_maybe_try
end

local function classifierAttackPresent(classifier_result)
    local labels = classifier_result and classifier_result.labels
    if not labels then return false end
    for i = 1, #labels do
        if labels[i] == "attack" then return true end
    end
    return false
end

-- Pure detection. Returns { roles = {...}, span = "..." } or nil. No DB
-- access; safe to call from the corpus harness without any database stub.
function Callout.detect(msg, classifier_result)
    if type(msg) ~= "string" or msg == "" then return nil end
    if classifierSarcasm(classifier_result) then return nil end
    if classifierAttackPresent(classifier_result) then return nil end

    local Patterns = ns.Patterns
    if not Patterns or not Patterns.ROLE_TARGETS then return nil end

    local tokens = tokenize(msg)
    local n = #tokens
    if n == 0 then return nil end

    -- Pass 1: collect every role-target position.
    local role_positions = {}
    for i = 1, n do
        if Patterns.ROLE_TARGETS[tokens[i]] then
            role_positions[#role_positions + 1] = i
        end
    end
    if #role_positions == 0 then return nil end

    -- Pass 2: for each role position, look for a callout verb in ±window.
    -- If at least one verb is in range, the callout fires for that role.
    local roles_set = {}
    local hit_positions = {}
    for _, ridx in ipairs(role_positions) do
        local lo = math.max(1, ridx - ROLE_WINDOW)
        local hi = math.min(n, ridx + ROLE_WINDOW)
        local verb_found = false
        for j = lo, hi do
            if j ~= ridx and Patterns.CALLOUT_VERBS[tokens[j]] then
                verb_found = true; break
            end
        end
        if verb_found then
            local role = Patterns.ROLE_TARGET_TO_ROLE[tokens[ridx]]
            if role and not roles_set[role] then
                roles_set[role] = true
                hit_positions[#hit_positions + 1] = ridx
            end
        end
    end

    -- Pass 3: multi-role join. "tank and healer cooldowns" — the trailing
    -- verb anchors the first role via window; the second role gets pulled in
    -- by adjacency to an already-hit role via a join token (and/&/+) or
    -- direct token adjacency.
    if #hit_positions > 0 then
        for _, ridx in ipairs(role_positions) do
            local role = Patterns.ROLE_TARGET_TO_ROLE[tokens[ridx]]
            if role and not roles_set[role] then
                -- Adjacent or join-separated from another role position?
                for _, hidx in ipairs(role_positions) do
                    if hidx ~= ridx then
                        local gap = math.abs(ridx - hidx)
                        local adjacent = gap == 1
                        local join_between = false
                        if gap == 2 then
                            local mid = (ridx + hidx) / 2
                            join_between = Patterns.CALLOUT_JOINS[tokens[mid]] == true
                        end
                        if (adjacent or join_between)
                           and roles_set[Patterns.ROLE_TARGET_TO_ROLE[tokens[hidx]] or ""] then
                            roles_set[role] = true
                            break
                        end
                    end
                end
            end
        end
    end

    -- Build ordered role list (stable: tank, healer, dps).
    local roles = {}
    if roles_set.tank   then roles[#roles + 1] = "tank"   end
    if roles_set.healer then roles[#roles + 1] = "healer" end
    if roles_set.dps    then roles[#roles + 1] = "dps"    end

    if #roles == 0 then return nil end

    return { roles = roles, span = msg }
end

-- Returns true when the user's effective role is in detection.roles.
-- Defensive on auto-unresolved role (returns false rather than spuriously
-- matching everything).
function Callout.matchesUser(detection)
    if not detection or not detection.roles then return false end
    local g = db(); if not g then return false end
    if not (ns.Database and ns.Database.GetEffectiveRole) then return false end
    local role = ns.Database:GetEffectiveRole()
    if not role then return false end
    for i = 1, #detection.roles do
        if detection.roles[i] == role then return true end
    end
    return false
end

-- Convenience: detect + matchesUser in one call. Returns the detection (with
-- roles) only when the user is a named target. Used by the chat-filter to
-- decide whether to tint and sound.
function Callout.detectMatching(msg, classifier_result)
    local d = Callout.detect(msg, classifier_result)
    if not d then return nil end
    if not Callout.matchesUser(d) then return nil end
    return d
end

function Callout.tintIfEligible(msg, detection)
    local g = db()
    if g and g.debug_enabled then
        -- P4: entry state. Surfaces every flag the function gates on, plus
        -- whether a detection was even passed in (so we can see whether the
        -- caller had a callout to tint at all).
        print(string.format(
            "[ToxFilter Debug] tintIfEligible entry: enabled=%s, ui=%s, has_detection=%s",
            tostring(g.callout_enabled),
            tostring(g.callout_ui),
            tostring(detection ~= nil)))
    end
    local function dret(label, value)
        if g and g.debug_enabled then
            print("[ToxFilter Debug] tintIfEligible returning: " .. label)
        end
        return value
    end
    if not detection then return dret("nil (no_detection)", nil) end
    if type(msg) ~= "string" or msg == "" then return dret("nil (bad_msg)", nil) end
    if not g then return dret("nil (no_db)", nil) end
    if not g.callout_enabled then return dret("nil (master_off)", nil) end
    if g.callout_ui == false then return dret("nil (ui_off)", nil) end
    return dret("tinted", TINT_OPEN .. msg .. TINT_CLOSE)
end

function Callout.playSoundIfEligible(detection)
    local g = db()
    if g and g.debug_enabled then
        -- P6: entry state for the audio path. Mirrors P4 so we can see
        -- whether the visual and audio paths agree on the gate state.
        print(string.format(
            "[ToxFilter Debug] playSoundIfEligible entry: enabled=%s, sound=%s, has_detection=%s",
            tostring(g.callout_enabled),
            tostring(g.callout_sound),
            tostring(detection ~= nil)))
    end
    if not detection then return end
    if not g then return end
    if not g.callout_enabled then return end
    if g.callout_sound == false then return end
    if type(PlaySound) == "function" then
        pcall(PlaySound, CALLOUT_SOUND_ID, CALLOUT_SOUND_CHANNEL)
    end
end

Callout.SOUND_ID      = CALLOUT_SOUND_ID
Callout.SOUND_CHANNEL = CALLOUT_SOUND_CHANNEL

ns.Callout = Callout
