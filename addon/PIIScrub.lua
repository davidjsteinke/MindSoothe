-- Conservative PII scrubber for buffer-stored chat content.
-- Strategy: scrub only at name-context positions, not blanket-capitalized
-- tokens. Sentence-initial caps (e.g. "Move out of fire") and proper-noun-
-- shaped tactical tokens are left alone. Sprint 6 will audit comprehensively;
-- this is a pragmatic first pass with the safety direction tilted toward
-- false-positive (over-scrubbing a legitimately ambiguous token to <player>)
-- rather than false-negative (leaking a name).
--
-- Name-context positions handled:
--   1. After thanks-class tokens (thanks/thank/thx/ty/tysm), the next token
--      that looks like a Capword is replaced with <player>.
--   2. Anywhere @<word> appears, the @-suffix is replaced with <player>.
--
-- Allowlists:
--   - The installing user's own name (UnitName("player")) is preserved,
--     because positive-moment matching on direct-thanks-to-user needs it.
--   - A small set of common all-caps tokens (GG, OK, DPS, MVP, ...) are not
--     scrubbed — they aren't names even when they look like them.

local _, ns = ...

local THANKS_TOKENS = { "thanks", "thank", "thx", "ty", "tysm" }
local THANKS_SET = {}
for _, w in ipairs(THANKS_TOKENS) do
    THANKS_SET[w] = true
    THANKS_SET[w:upper()] = true
    THANKS_SET[w:sub(1, 1):upper() .. w:sub(2)] = true
end

local PROTECTED_CAPS = {
    GG = true, WP = true, OK = true, BRB = true, AFK = true, AOE = true,
    DPS = true, MVP = true, OOM = true, FYI = true, LOL = true, IDK = true,
    IIRC = true, TY = true, GLHF = true, EZ = true, GLF = true, LFM = true,
    LFG = true, MDI = true, MM = true, BG = true, KO = true,
}

local function userNameLower()
    if type(UnitName) ~= "function" then return nil end
    local n = UnitName("player")
    return n and n:lower() or nil
end

-- Looks-like-a-name predicate: capitalized first letter + at least one more
-- ASCII letter, after stripping leading/trailing punctuation. Returns the
-- cleaned name on match, nil otherwise.
local function looksLikeName(token)
    if type(token) ~= "string" then return nil end
    local stripped = token:gsub("^[%p]+", ""):gsub("[%p]+$", "")
    if #stripped < 2 then return nil end
    if not stripped:match("^%u%a+$") then return nil end
    return stripped
end

local function shouldScrub(name, userLower)
    if PROTECTED_CAPS[name:upper()] then return false end
    if userLower and name:lower() == userLower then return false end
    return true
end

-- Plain (non-pattern) replacement of the first occurrence of `find` in `s`.
local function plainReplace(s, find, repl)
    local i = s:find(find, 1, true)
    if not i then return s end
    return s:sub(1, i - 1) .. repl .. s:sub(i + #find)
end

local function scrub(text)
    if type(text) ~= "string" or text == "" then return text end
    local userLower = userNameLower()

    text = text:gsub("(@)([%w_]+)", function(at, name)
        if userLower and name:lower() == userLower then return at .. name end
        if PROTECTED_CAPS[name:upper()] then return at .. name end
        return at .. "<player>"
    end)

    local tokens = {}
    for word in text:gmatch("%S+") do tokens[#tokens + 1] = word end
    if #tokens < 2 then return text end

    for i = 1, #tokens - 1 do
        if THANKS_SET[tokens[i]] then
            local nxt = tokens[i + 1]
            local name = looksLikeName(nxt)
            if name and shouldScrub(name, userLower) then
                tokens[i + 1] = plainReplace(nxt, name, "<player>")
            end
        end
    end

    return table.concat(tokens, " ")
end

ns.PIIScrub = { scrub = scrub }
