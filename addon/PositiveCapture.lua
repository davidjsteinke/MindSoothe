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

-- Sprint 7a (F3): typo tolerance for the positive-capture keyword sets. Length
-- floor 5 keeps the dense short-word neighbourhoods exact-only: "thanks"(6) and
-- "thank"(5) gain distance-1 tolerance ("thansk"), but "thx"/"ty"/"gg"/"good"/
-- "nice"/"big"/"huge" do not. CALLOUTS (gg/wp/ez) and the multi-word
-- CALLOUT_PHRASES stay exact. Role targets are matched exact-only in detect()
-- below — never fuzzed. Never wired into the classifier / rule engine / lists.
local FUZZY_MINLEN = 5
local THANKS_FUZZY    = ns.Fuzzy and ns.Fuzzy.bucketize(THANKS_TOKENS, FUZZY_MINLEN) or {}
local POS_VERBS_FUZZY = ns.Fuzzy and ns.Fuzzy.bucketize(POS_VERBS, FUZZY_MINLEN) or {}
local POS_PLAYS_FUZZY = ns.Fuzzy and ns.Fuzzy.bucketize(POS_PLAYS, FUZZY_MINLEN) or {}

local function inThanks(t)
    return THANKS_TOKENS[t] or (ns.Fuzzy and ns.Fuzzy.matches(t, THANKS_FUZZY, FUZZY_MINLEN)) or false
end
local function inPosVerb(t)
    return POS_VERBS[t] or (ns.Fuzzy and ns.Fuzzy.matches(t, POS_VERBS_FUZZY, FUZZY_MINLEN)) or false
end
local function inPosPlay(t)
    return POS_PLAYS[t] or (ns.Fuzzy and ns.Fuzzy.matches(t, POS_PLAYS_FUZZY, FUZZY_MINLEN)) or false
end

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

-- Sprint 5b fix: connected-realm Tab-completion expands "<your-name>" into
-- "<your-name>-<realm>" on the wire, and Normalize keeps hyphens intact (they
-- aren't in PUNCT_SET because hashing relies on the raw token shape). userL is
-- pre-stripped; the incoming token must be stripped at the comparison site for
-- the match to succeed. Strip-then-compare is local to thanks_user — classifier
-- and rule paths continue to see the full token.
local function stripRealmSuffix(token)
    if not token then return token end
    return token:match("^([^-]+)") or token
end

-- Sprint 7b bugfix: a positive moment is something someone ELSE directed at the
-- user. The user's own outgoing praise ("thanks dingles"), echoed back through
-- the group CHAT_MSG_* events, must never be recorded — and, per the tint
-- decision in chatFilter, must not be tinted either. isSelfSender compares the
-- CHAT_MSG_* author against UnitName("player"), realm-suffix-stripped and
-- case-insensitive. Shared by the typed-praise path (capture) and the emote path
-- (captureEmote); also exported so chatFilter can apply the same skip to tint.
local function isSelfSender(sender)
    if not sender or type(UnitName) ~= "function" then return false end
    local me = UnitName("player")
    if not me then return false end
    me = (me:match("^([^-]+)") or me):lower()
    local s = (sender:match("^([^-]+)") or sender):lower()
    return me == s
end

local function dbg(fmt, ...)
    local g = ns.Database and ns.Database:Get() or nil
    if not g or not g.debug_enabled then return end
    print(ns.Const.DEBUG_PREFIX .. fmt:format(...))
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
            print(ns.Const.PREFIX .. "Positive subscriber error: " .. tostring(err))
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
        if inThanks(normalized_tokens[i]) then
            local nxt = normalized_tokens[i + 1]
            if roleTargetMatches(nxt) then
                local direct = roleTargetMatchesUser(nxt, role)
                dbg("PositiveCapture.detect: thanks_role nxt=%q role=%s direct=%s",
                    nxt, tostring(role), tostring(direct))
                return { pattern = "thanks_role", direct = direct }
            end
            if userL then
                local nxt_short = stripRealmSuffix(nxt)
                dbg("PositiveCapture.detect: thanks_user check nxt=%q nxt_short=%q userL=%q match=%s",
                    nxt, nxt_short, userL, tostring(nxt_short == userL))
                if nxt_short == userL then
                    return { pattern = "thanks_user", direct = true }
                end
            end
        end
    end

    -- Bare thanks with no role/user target ("ty", "thanks all") is still a
    -- positive moment in the room — just not direct-to-user, so it does NOT bump
    -- the thanks counters (direct=false, same as a "gg" callout). Lower
    -- precedence than the targeted thanks_role/thanks_user above. Scans all n
    -- tokens because the targeted loop stops at n-1 and so misses a lone or
    -- trailing thanks token (the single-token "ty" that prompted this).
    for i = 1, n do
        if inThanks(normalized_tokens[i]) then
            return { pattern = "thanks", direct = false }
        end
    end

    for i = 1, n - 1 do
        if inPosVerb(normalized_tokens[i]) and inPosPlay(normalized_tokens[i + 1]) then
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

local function capture(msg, classifier_result, event, sender)
    if type(msg) ~= "string" or msg == "" then return nil end
    if not classifier_result or not classifier_result.normalized_tokens then return nil end
    -- Sprint 5d: positive capture is an Uplifter feature. Category (or the addon
    -- master) off → no capture. Self-gated here (not just at the chatFilter call
    -- site) so the corpus harness exercises the suppression directly.
    if not (ns.Category and ns.Category.gate("uplifter")) then
        dbg("PositiveCapture.capture: uplifter category off, skipping")
        return nil
    end
    if whisperOptOut(event) then
        dbg("PositiveCapture.capture: whisper opt-out, skipping (event=%s)", tostring(event))
        return nil
    end

    dbg("PositiveCapture.capture entry: msg=%q event=%s tokens=%d",
        msg, tostring(event), #classifier_result.normalized_tokens)

    local match = detect(classifier_result.normalized_tokens, classifier_result.signals)
    if not match then
        dbg("PositiveCapture.capture: detect returned nil — no moment recorded")
        return nil
    end

    -- Record narrowing (Sprint 7b bugfix). detect() is intentionally broad — it
    -- also fires on bare room-positivity ("ty", "gg") and praise aimed at other
    -- roles/players (direct=false) — so the chat-line tint can stay broad. The
    -- RECORD decision narrows here, mirroring the emote path's two guards:
    --   * directed-at-user — match.direct (a role match for the user's own role,
    --     or the user's own name as the target). Bare thanks / compliment /
    --     callout and praise aimed elsewhere are direct=false → not recorded.
    --   * not-own-message — isSelfSender skips the user's echoed outgoing praise
    --     (the "thanks dingles" leak), even when it role-matches the user.
    -- Precision over recall: when unsure, do not record. The tint stays broad in
    -- chatFilter, which keeps a separate (detect-based) decision.
    if not match.direct or isSelfSender(sender) then
        dbg("PositiveCapture.capture: detected but not direct-to-user/own message — not recorded (direct=%s self=%s)",
            tostring(match.direct), tostring(isSelfSender(sender)))
        return nil
    end

    if not (ns.Buffer and ns.Buffer.RecordPositiveMoment) then return nil end
    -- Sprint 6: sender (CHAT_MSG_* author) flows to the scrubber for best-effort
    -- name stripping of the stored body.
    local moment = ns.Buffer:RecordPositiveMoment(msg, { pattern = match.pattern }, match.direct, sender)
    dbg("PositiveCapture.capture: recorded pattern=%s direct=%s", match.pattern, tostring(match.direct))
    if moment then notify(moment) end
    return moment
end

-- ===== Sprint 7a (F4): emote capture =====
--
-- enUS-ONLY BY CONSTRUCTION. Detection keys on English emote verbs and the
-- self-target token "you"/"your" that enUS renders for an emote aimed at the
-- player ("<Name> thanks you."). Other locales render different strings and will
-- not match — a documented limitation, surfaced in the README, not a silent gap.
-- A future locale pass would table-drive these tokens (and ideally read the
-- GlobalStrings emote templates) rather than hardcode English.
local EMOTE_VERBS = set({ "thank", "thanks", "cheer", "cheers", "salute", "salutes" })
local EMOTE_SELF  = set({ "you", "your" })

-- Lowercase + split on non-letters. "Bob thanks you." -> {bob, thanks, you}.
local function emoteTokenize(text)
    local out = {}
    for tok in text:lower():gmatch("%a+") do
        out[#out + 1] = tok
    end
    return out
end

-- Returns a match table only when the rendered emote text is aimed at the
-- player: an EMOTE_VERBS verb AND a self-target token ("you"/"your"). Covers
-- "Bob thanks you.", "Carol salutes you.", "Dave cheers at you.".
--
-- Sprint 7a in-game pass (N22): untargeted emotes do NOT capture. "Bob cheers."
-- and "Bob thanks everyone." carry no self-target token, so they are ignored —
-- a positive moment is something another player directed AT you, and an
-- untargeted emote is ambient, not directed praise. (An earlier 7a draft also
-- captured untargeted /thanks and /cheer via a "broadcast verb" rule; that rule
-- is removed.) Third-party emotes ("Bob cheers at Carol.", N23) likewise lack a
-- self-target token and stay uncaptured. Pure function; exported for the harness.
local function emoteDetect(text)
    if type(text) ~= "string" or text == "" then return nil end
    local toks = emoteTokenize(text)
    local verb, selfref = false, false
    for i = 1, #toks do
        if EMOTE_VERBS[toks[i]] then verb = true end
        if EMOTE_SELF[toks[i]]  then selfref = true end
    end
    if verb and selfref then return { pattern = "emote" } end
    return nil
end

-- Your own outgoing emote ("You thank Bob.") also fires CHAT_MSG_TEXT_EMOTE and
-- contains both a verb and "you" (as subject, not target). isSelfSender (hoisted
-- above, shared with the typed-praise path) skips it: a moment is something
-- someone ELSE directed at you.

-- Capture a targeted positive emote as a positive moment. Respects the Uplifter
-- category gate + addon master exactly like typed-thanks capture. The rendered
-- text passes through PIIScrub (sender threaded) like any capture, so the
-- sender's name in "<Name> thanks you." is scrubbed. direct_to_user = true so it
-- increments the same thanks/positive counters as typed praise.
--
-- Post-7a taint fix. CHAT_MSG_TEXT_EMOTE also fires for NPC / system / boss
-- emotes (seen in-game on a Delve completion and on closing a vendor) — never
-- praise directed at the user, and whose rendered text can arrive as a
-- secret/tainted value in a restricted-execution window. Reading/comparing that
-- text while tainted threw `attempt to compare execution tainted by 'ToxFilter'`
-- at the old line 337 (`text == ""`) — the same secret-value class as N12. Two
-- guards, in order, so we never touch `text` for an emote we shouldn't capture:
--   1. Source-GUID guard: only player-sourced emotes are candidates. Bails
--      before touching `text`, which both fixes the spurious NPC/system capture
--      and keeps us off the tainted text those emotes can carry.
--   2. pcall firewall: even for a player emote, treat `text` as if it could be
--      tainted — swallow any throw from the read/compare and skip rather than
--      surface an error.
local function captureEmote(text, sender, guid)
    -- Guard 1 — player-source only, BEFORE touching `text`.
    if type(guid) ~= "string" or not guid:find("^Player%-") then
        dbg("PositiveCapture.captureEmote: non-player emote, skipping (guid=%s)", tostring(guid))
        return nil
    end
    if not (ns.Category and ns.Category.gate("uplifter")) then
        dbg("PositiveCapture.captureEmote: uplifter category off, skipping")
        return nil
    end
    if isSelfSender(sender) then
        dbg("PositiveCapture.captureEmote: own emote, skipping (sender=%s)", tostring(sender))
        return nil
    end
    -- Guard 2 — pcall firewall around the only `text`-touching detection. A
    -- successful read here proves `text` is not tainted in this context, so the
    -- later RecordPositiveMoment/PIIScrub reads are safe too.
    local ok, detected = pcall(function()
        if type(text) ~= "string" or text == "" then return nil end
        return emoteDetect(text)
    end)
    if not ok then
        dbg("PositiveCapture.captureEmote: emote text unreadable (tainted?), skipping")
        return nil
    end
    if not detected then return nil end
    if not (ns.Buffer and ns.Buffer.RecordPositiveMoment) then return nil end
    local moment = ns.Buffer:RecordPositiveMoment(text, { pattern = "emote", emote = true }, true, sender)
    dbg("PositiveCapture.captureEmote: recorded emote moment")
    if moment then notify(moment) end
    return moment
end

ns.PositiveCapture = {
    capture      = capture,
    captureEmote = captureEmote,
    emoteDetect  = emoteDetect,
    subscribe    = subscribe,
    detect       = detect,
    -- Exported for chatFilter's tint gate (Sprint 7b bugfix): tint stays broad
    -- for others' positivity but never fires on the user's own outgoing lines.
    isSelfSender = isSelfSender,
}
