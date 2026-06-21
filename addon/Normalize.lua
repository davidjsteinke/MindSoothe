-- Token normalization pipeline. Pure functions; shared between runtime and
-- (mirrored in Python) the build script. Any change here is also a change to
-- the rule-data format and must bump NORMALIZATION_VERSION.

local _, ns = ...

local NORMALIZATION_VERSION = "v1"

-- Punctuation removed during normalization. Whitespace handled separately.
local PUNCT_SET = {
    ["."]=true, [","]=true, ["!"]=true, ["?"]=true, [";"]=true, [":"]=true,
    ["'"]=true, ['"']=true, ["("]=true, [")"]=true, ["["]=true, ["]"]=true,
    ["{"]=true, ["}"]=true, ["<"]=true, [">"]=true, ["/"]=true, ["\\"]=true,
    ["|"]=true,
}

-- 1 → i is more common in obfuscation than 1 → l.
local LEET = {
    ["0"] = "o",
    ["1"] = "i",
    ["3"] = "e",
    ["4"] = "a",
    ["5"] = "s",
    ["7"] = "t",
    ["8"] = "b",
    ["@"] = "a",
    ["$"] = "s",
}

local function strip_punct(s)
    local out = {}
    for i = 1, #s do
        local c = s:sub(i, i)
        if not PUNCT_SET[c] then
            out[#out + 1] = c
        end
    end
    return table.concat(out)
end

-- 3+ identical consecutive chars collapse to 1; 2 stay (book → book, boook → bok).
local function collapse_repetition(s)
    local out = {}
    local i = 1
    local n = #s
    while i <= n do
        local c = s:sub(i, i)
        local j = i
        while j <= n and s:sub(j, j) == c do
            j = j + 1
        end
        local run = j - i
        if run >= 3 then
            out[#out + 1] = c
        else
            for _ = 1, run do
                out[#out + 1] = c
            end
        end
        i = j
    end
    return table.concat(out)
end

local function leet(s)
    local out = {}
    for i = 1, #s do
        local c = s:sub(i, i)
        out[#out + 1] = LEET[c] or c
    end
    return table.concat(out)
end

local function strip_whitespace(s)
    return (s:gsub("%s", ""))
end

local function normalize(token)
    token = string.lower(token)
    token = strip_punct(token)
    token = collapse_repetition(token)
    token = leet(token)
    token = strip_whitespace(token)
    return token
end

-- WoW chat delivers player names wrapped in display escapes — most commonly a
-- class-color sequence (|cAARRGGBB...|r) and/or a player hyperlink
-- (|Hplayer:Name-Realm...|h<label>|h). tokenize() splits on whitespace, so the
-- whole escape becomes one token; normalize()'s strip_punct only drops the bare
-- '|', leaving the color hex and the 'r' from '|r' fused onto the name
-- ("|cFFFF7C0A[Manehealer]|r" -> "cftcoamanehealerr") so name comparison fails.
-- Flatten escapes to plain text BEFORE tokenizing: color codes are pure
-- formatting (dropped); hyperlinks collapse to their visible label. This is NOT
-- part of the hashed normalization (normalize()/tokenize() are unchanged), so it
-- does not affect NORMALIZATION_VERSION or the rule-data format — it only cleans
-- the input. Single source of truth; PIIScrub.lua delegates here.
local function strip_escapes(text)
    if type(text) ~= "string" then return text end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")  -- color start
    text = text:gsub("|H.-|h(.-)|h", "%1")      -- hyperlink -> visible label
    text = text:gsub("|T.-|t", "")              -- inline texture
    text = text:gsub("|r", "")                  -- color reset (incl. orphans)
    return text
end

local function tokenize(msg)
    local tokens = {}
    for word in msg:gmatch("%S+") do
        tokens[#tokens + 1] = word
    end
    return tokens
end

ns.Normalize = {
    normalize = normalize,
    tokenize = tokenize,
    strip_escapes = strip_escapes,
    NORMALIZATION_VERSION = NORMALIZATION_VERSION,
}
