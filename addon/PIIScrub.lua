-- PII scrubber for buffer-stored chat content (Sprint 6 broadening).
--
-- Policy weighting (locked Sprint 6): the "no third-party name at rest" rule is
-- a courtesy, not a compliance requirement. The scrub therefore errs toward
-- PRECISION over recall — better to let an occasional name survive than to
-- mangle a legitimate positive moment. We strip only KNOWN names (the sender of
-- the message, plus the installing user's own characters), never names GUESSED
-- from token shape. A class word that is also a name (Hunter, Priest, Monk) is
-- never stripped unless it is a known name, and even then a protect-list spares
-- it so the moment stays readable (the class-name-collision decision, B1).
--
-- Sources of known names:
--   1. Sender — the CHAT_MSG_* author arg, threaded in from the chat filter.
--      Realm suffix stripped. This is the authoritative source for the name
--      that would actually appear in a praise body.
--   2. The installing user's current character — UnitName("player").
--   3. The installing user's alt roster — parsed from AceDB's profileKeys
--      ("Char - Realm"). All own data; safe to scrub, built once and cached.
--
-- Matching is case-insensitive, connected-realm-suffix-aware (Name-Realm strips
-- whole, suffix and all), and position-independent (a known name anywhere in
-- the body is scrubbed, not only right after a "thanks" token). Whole-token
-- match only: "ash" never matches inside "smash"/"Ashbringer".
--
-- @mentions keep the prior unconditional scrub (explicit addressing syntax,
-- negligible false-positive risk): any @word becomes @<player> unless it is a
-- protected acronym (GG, DPS, ...).

local _, ns = ...

-- Acronyms that look name-shaped but never are. Stored uppercase; also folded
-- into PROTECT (lowercase) for the known-name collision spare.
local PROTECTED_CAPS = {
    GG = true, WP = true, OK = true, BRB = true, AFK = true, AOE = true,
    DPS = true, MVP = true, OOM = true, FYI = true, LOL = true, IDK = true,
    IIRC = true, TY = true, GLHF = true, EZ = true, GLF = true, LFM = true,
    LFG = true, MDI = true, MM = true, BG = true, KO = true,
}

-- Class names and role words a player might legitimately be named after. A
-- KNOWN name on this list is NOT scrubbed (B1: preserve "thanks Hunter" intact;
-- accept the rare leak when a player is literally named Hunter). This list only
-- ever bites on a known-name collision — an unknown class word is never in the
-- known set to begin with, so it survives regardless.
local PROTECT = {
    hunter = true, mage = true, priest = true, monk = true, warrior = true,
    warlock = true, rogue = true, druid = true, shaman = true, paladin = true,
    evoker = true, deathknight = true, demonhunter = true,
    tank = true, healer = true, heals = true, dps = true,
}
for k in pairs(PROTECTED_CAPS) do PROTECT[k:lower()] = true end

local function dbg(fmt, ...)
    local g = ns.Database and ns.Database.Get and ns.Database:Get() or nil
    if not g or not g.debug_enabled then return end
    print("[ToxFilter Debug] " .. fmt:format(...))
end

-- "Name-Realm" / "Name" -> lowercased "name". Used for both known names and
-- body tokens so the two sides compare on the same realm-stripped basis.
local function nameKey(s)
    if type(s) ~= "string" or s == "" then return nil end
    local core = s:match("^([^-]+)") or s
    if core == "" then return nil end
    return core:lower()
end

-- Owned-name set (current character + alt roster), built once per session. The
-- sender is unioned in per call, not cached. Roster comes from AceDB's raw
-- SavedVariables profileKeys; absent in the corpus harness, which is fine.
local ownedCache = nil

local function buildOwnedSet()
    local s = {}
    if type(UnitName) == "function" then
        local key = nameKey(UnitName("player"))
        if key then s[key] = true end
    end
    local svRoot = rawget(_G, "ToxFilterDB")
    if type(svRoot) == "table" and type(svRoot.profileKeys) == "table" then
        for charKey in pairs(svRoot.profileKeys) do
            -- profileKeys is "Char - Realm"; take the character name.
            local charName = charKey:match("^(.-)%s*%-%s*") or charKey
            local key = nameKey(charName)
            if key then s[key] = true end
        end
    end
    return s
end

local function ownedSet()
    if not ownedCache then ownedCache = buildOwnedSet() end
    return ownedCache
end

-- Test seam: the corpus harness re-seeds owned names without a live UnitName.
local function _resetOwnedCache() ownedCache = nil end

local function isKnown(lower, sender_lower)
    if not lower then return false end
    if sender_lower and lower == sender_lower then return true end
    return ownedSet()[lower] == true
end

-- Strip a single token to its name core, keeping surrounding punctuation so it
-- can be re-attached around <player>. Returns scrubbed token (or original).
local function scrubToken(tok, sender_lower)
    local pre  = tok:match("^(%p*)") or ""
    local post = tok:match("(%p*)$") or ""
    if #pre + #post >= #tok then return tok end       -- all-punctuation token
    local core = tok:sub(#pre + 1, #tok - #post)
    local lower = nameKey(core)                        -- realm-stripped, lowered
    if not lower then return tok end
    if PROTECT[lower] then return tok end              -- B1 collision spare
    if isKnown(lower, sender_lower) then
        dbg("PIIScrub: stripped %q (known name)", tok)
        return pre .. "<player>" .. post
    end
    return tok
end

local function scrub(text, sender)
    if type(text) ~= "string" or text == "" then return text end

    local sender_lower = nameKey(sender)

    -- @mention scrub: unconditional (explicit addressing), acronyms spared.
    text = text:gsub("(@)([%w_]+)", function(at, name)
        if PROTECTED_CAPS[name:upper()] then return at .. name end
        return at .. "<player>"
    end)

    local out = {}
    for tok in text:gmatch("%S+") do
        out[#out + 1] = scrubToken(tok, sender_lower)
    end
    if #out == 0 then return text end
    return table.concat(out, " ")
end

ns.PIIScrub = {
    scrub = scrub,
    -- Exposed for the corpus harness only; no production caller.
    _resetOwnedCache = _resetOwnedCache,
}
