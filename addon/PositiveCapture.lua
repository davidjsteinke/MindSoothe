-- Pattern-based positive-moment detection. Pure data + a small detection
-- function; mirrors Classifier.lua's shape (no LLM, no I/O, false-positive-
-- tolerant). Runs on every chat-frame message that the rule engine returns
-- as pass-through.
--
-- Sarcasm de-flagging: if the classifier surfaced any sarcasm signal on this
-- message (antonymic_praise, passive_thanks, slash_s, maybe_try), the message
-- is NOT captured. Sarcasm-flagged thanks is not thanks.
--
-- Tone-grep note: POS_VERBS contains "great" as a positive-pattern key, not
-- as a user-output string. Same for "good" elsewhere. The grep against
-- !|great|oops|sorry catches user-output drift, not pattern-data; this match
-- is the same kind of self-reference the Sprint 3 grep documentation uses.

local _, ns = ...

local function set(list)
    local s = {}
    for i = 1, #list do s[list[i]] = true end
    return s
end

local THANKS_TOKENS = set({ "thanks", "thank", "thx", "ty", "tysm" })

local POS_VERBS = set({ "good", "great", "nice", "clutch", "solid", "huge", "big" })

local POS_PLAYS = set({
    "pull", "pulls", "tank", "tanking", "heal", "heals", "healing",
    "dispel", "dispels", "interrupt", "interrupts", "kick", "kicks",
    "save", "saves", "saved", "cd", "cds", "cc", "stun", "stuns",
    "dps", "run", "runs", "execute", "swap", "swaps",
})

local CALLOUTS = set({ "gg", "wp", "ggwp", "ez" })

local CALLOUT_PHRASES = {
    { "well", "played" },
    { "good", "game" },
    { "good", "run" },
}

-- Sprint 5 refactor: role-target lookup lives in Patterns.lua so Callout.lua
-- and PositiveCapture.lua share the same definition. Local accessors below
-- preserve the previous direct-membership / per-role-set call shape so the
-- rest of this module is unchanged.
local function roleTargetMatches(token)
    return ns.Patterns.ROLE_TARGETS[token] == true
end

local function roleTargetMatchesUser(token, role)
    if not role then return false end
    return ns.Patterns.ROLE_TARGET_TO_ROLE[token] == role
end

local function userNameLower()
    if type(UnitName) ~= "function" then return nil end
    local n = UnitName("player")
    if not n then return nil end
    -- Connected-realm clients can return "Name-Server"; strip the suffix so
    -- "ty edvins" matches when UnitName is "Edvins-Stormrage".
    n = n:match("^([^-]+)") or n
    return n:lower()
end

local function userRole()
    if not (ns.Database and ns.Database.GetEffectiveRole) then return nil end
    return ns.Database:GetEffectiveRole()
end

local subscribers = {}

local function subscribe(fn)
    if type(fn) == "function" then subscribers[#subscribers + 1] = fn end
end

local function notify(moment)
    for i = 1, #subscribers do
        local ok, err = pcall(subscribers[i], moment)
        if not ok then
            print("[ToxFilter] Positive subscriber error: " .. tostring(err))
        end
    end
end

local function hasSarcasmFlag(signals)
    if not signals then return false end
    return signals.sarcasm_antonymic_praise
        or signals.sarcasm_passive_thanks
        or signals.sarcasm_slash_s
        or signals.sarcasm_maybe_try
end

local function detect(normalized_tokens, signals)
    if hasSarcasmFlag(signals) then return nil end
    local n = #normalized_tokens
    if n == 0 then return nil end

    local userL = userNameLower()
    local role  = userRole()

    for i = 1, n - 1 do
        if THANKS_TOKENS[normalized_tokens[i]] then
            local nxt = normalized_tokens[i + 1]
            if roleTargetMatches(nxt) then
                local direct = roleTargetMatchesUser(nxt, role)
                return { pattern = "thanks_role", direct = direct }
            end
            if userL and nxt == userL then
                return { pattern = "thanks_user", direct = true }
            end
        end
    end

    for i = 1, n - 1 do
        if POS_VERBS[normalized_tokens[i]] and POS_PLAYS[normalized_tokens[i + 1]] then
            return { pattern = "compliment_play", direct = false }
        end
    end

    for i = 1, n do
        if CALLOUTS[normalized_tokens[i]] then
            return { pattern = "positive_callout", direct = false }
        end
    end

    for _, phrase in ipairs(CALLOUT_PHRASES) do
        local plen = #phrase
        if plen <= n then
            for i = 1, n - plen + 1 do
                local match_ok = true
                for k = 1, plen do
                    if normalized_tokens[i + k - 1] ~= phrase[k] then
                        match_ok = false
                        break
                    end
                end
                if match_ok then
                    return { pattern = "positive_callout", direct = false }
                end
            end
        end
    end

    return nil
end

-- Whisper privacy carve-out (Sprint 4 fix2 H8b): when whisper channel
-- filtering is off, the user has explicitly opted out of having ToxFilter
-- read their private 1:1 messages. Capturing positive moments from those
-- messages would contradict that opt-out, so capture is suppressed entirely
-- on whisper events when the channel is off. Other channels (instance, raid,
-- etc.) capture regardless of channel-toggle state.
local function whisperOptOut(event)
    if event ~= "CHAT_MSG_WHISPER" then return false end
    local g = ns.Database and ns.Database:Get() or nil
    if not g or not g.channels then return false end
    return g.channels.whisper == false
end

local function capture(msg, classifier_result, event)
    if type(msg) ~= "string" or msg == "" then return nil end
    if not classifier_result or not classifier_result.normalized_tokens then return nil end
    if whisperOptOut(event) then return nil end

    local match = detect(classifier_result.normalized_tokens, classifier_result.signals)
    if not match then return nil end

    if not (ns.Buffer and ns.Buffer.RecordPositiveMoment) then return nil end
    local moment = ns.Buffer:RecordPositiveMoment(msg, { pattern = match.pattern }, match.direct)
    if moment then notify(moment) end
    return moment
end

ns.PositiveCapture = {
    capture   = capture,
    subscribe = subscribe,
    detect    = detect,
}
