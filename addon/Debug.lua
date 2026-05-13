-- Sprint 4 fix: developer-only counter manipulation.
--
-- Hidden behind db.debug_enabled (default false). When the flag is off, the
-- top-level /tox debug verb pretends not to exist (prints "Unknown command")
-- so the public surface stays clean. The single exception is /tox debug
-- enable, which always works — otherwise turning the tool on would itself be
-- gated behind being on.
--
-- Counter shape (Sprint 4 fix v4 schema):
--   db.session_buffer.counters.instances[<name>][<bucket>] = {
--       deaths, wipes, completions, last_event,
--   }
-- Field set: deaths, wipes, completions. Buckets: normal, heroic, mythic,
-- M0, M2-5, M6-10, M10+ (locked at run start; the H1 spec).
--
-- Argument parser handles two instance-name forms:
--   "Mists of Tirna Scithe" heroic deaths 12     (quoted)
--   The Stonevault M2-5 wipes 8                  (unquoted; consume tokens
--                                                 until a known bucket token)
-- Bucket tokens are case-insensitive (m2-5 == M2-5).
--
-- Tone: factual confirmations, no exclamation. /tox debug counter reset all
-- requires a literal `confirm` token rather than a popup.

local _, ns = ...

local Debug = {}

local DIFFICULTY_BUCKETS = {
    normal  = "normal",
    heroic  = "heroic",
    mythic  = "mythic",
    m0      = "M0",
    ["m2-5"]  = "M2-5",
    ["m6-10"] = "M6-10",
    ["m10+"]  = "M10+",
}

local FIELD_SET = { deaths = true, wipes = true, completions = true }

local function out(line) print("[ToxFilter] " .. line) end

local function db()
    return ns.Database and ns.Database:Get() or nil
end

local function isEnabled()
    local g = db()
    return g and g.debug_enabled == true
end

local function canonicalBucket(token)
    if type(token) ~= "string" then return nil end
    return DIFFICULTY_BUCKETS[token:lower()]
end

Debug.canonicalBucket = canonicalBucket

-- Splits "<instance...> <bucket> <rest...>" into (instance, bucket, rest).
-- Quoted: "Foo Bar" bucket rest...
-- Unquoted: walk tokens until one matches a known bucket; everything before
-- is the instance name.
local function parseInstanceBucket(s)
    s = s and s:match("^%s*(.-)%s*$") or ""
    if s == "" then return nil, nil, nil, "missing instance" end

    if s:sub(1, 1) == '"' then
        local closeAt = s:find('"', 2, true)
        if not closeAt then return nil, nil, nil, "unterminated quote" end
        local instance = s:sub(2, closeAt - 1)
        if instance == "" then return nil, nil, nil, "empty instance" end
        local rest = s:sub(closeAt + 1):match("^%s*(.*)%s*$") or ""
        local bucketTok, after = rest:match("^(%S+)%s*(.*)$")
        local bucket = canonicalBucket(bucketTok or "")
        if not bucket then return nil, nil, nil, "unknown difficulty" end
        return instance, bucket, (after or ""):match("^%s*(.-)%s*$") or "", nil
    end

    local words = {}
    for w in s:gmatch("%S+") do words[#words + 1] = w end
    for i = 1, #words do
        local b = canonicalBucket(words[i])
        if b then
            if i == 1 then return nil, nil, nil, "missing instance" end
            local instance = table.concat(words, " ", 1, i - 1)
            local rest = (i < #words) and table.concat(words, " ", i + 1) or ""
            return instance, b, rest, nil
        end
    end
    return nil, nil, nil, "unknown difficulty"
end

Debug.parseInstanceBucket = parseInstanceBucket

local function ensureInstanceShape(g)
    g.session_buffer = g.session_buffer or {}
    local sb = g.session_buffer
    sb.counters = sb.counters or {}
    sb.counters.instances = sb.counters.instances or {}
    return sb.counters.instances
end

local function setCounter(instance, bucket, field, value)
    local g = db(); if not g then return false, "no_db" end
    local instances = ensureInstanceShape(g)
    instances[instance] = instances[instance] or {}
    instances[instance][bucket] = instances[instance][bucket]
        or { deaths = 0, wipes = 0, completions = 0 }
    instances[instance][bucket][field] = value
    instances[instance][bucket].last_event = (time and time()) or os.time()
    return true
end

-- ===== Subcommand handlers =====

local function cmdEnable()
    local g = db(); if not g then out("Settings not loaded."); return end
    g.debug_enabled = true
    out("Debug mode enabled.")
end

local function cmdDisable()
    local g = db(); if not g then out("Settings not loaded."); return end
    g.debug_enabled = false
    out("Debug mode disabled.")
end

local function cmdVersion()
    local g = db(); if not g then out("Settings not loaded."); return end
    local v = ns.ToxFilterAddon and ns.ToxFilterAddon.VERSION or "unknown"
    out("Debug active. Version " .. v
        .. ", schema_version " .. tostring(g.schema_version or "?") .. ".")
end

local function cmdSessionReset()
    local g = db(); if not g then out("Settings not loaded."); return end
    g.session_buffer = g.session_buffer or {}
    g.session_buffer.counters = g.session_buffer.counters or {}
    g.session_buffer.counters.sessions = g.session_buffer.counters.sessions or {}
    g.session_buffer.counters.sessions.history = g.session_buffer.counters.sessions.history or {}
    local t = (time and time()) or os.time()
    g.session_buffer.counters.sessions.current = {
        started_at           = t,
        last_activity_at     = t,
        encounters_completed = 0,
        encounters_wiped     = 0,
        deaths               = 0,
        thanks_received      = 0,
    }
    out("Session counters reset.")
end

local function listInstance(instances, name)
    local rec = instances[name]
    if not rec then
        out("No counters for '" .. name .. "'.")
        return
    end
    local buckets = {}
    for b in pairs(rec) do buckets[#buckets + 1] = b end
    table.sort(buckets)
    out("Counters for '" .. name .. "':")
    for _, b in ipairs(buckets) do
        local c = rec[b]
        print(string.format("  %-8s deaths=%d wipes=%d completions=%d",
            b, c.deaths or 0, c.wipes or 0, c.completions or 0))
    end
end

local function cmdCounterList(rest)
    local g = db(); if not g then out("Settings not loaded."); return end
    local instances = ensureInstanceShape(g)
    rest = rest:match("^%s*(.-)%s*$") or ""
    if rest ~= "" then
        local name
        if rest:sub(1, 1) == '"' then
            local closeAt = rest:find('"', 2, true)
            if not closeAt then out("Unterminated quote."); return end
            name = rest:sub(2, closeAt - 1)
        else
            name = rest
        end
        listInstance(instances, name)
        return
    end
    local names = {}
    for n in pairs(instances) do names[#names + 1] = n end
    if #names == 0 then out("No instance counters recorded."); return end
    table.sort(names)
    out("Instance counters (" .. #names .. "):")
    for _, n in ipairs(names) do listInstance(instances, n) end
end

-- Module-local guard: /tox debug counter reset all requires a literal confirm
-- token. Avoids a popup; matches the rest of the slash surface.
local function cmdCounterReset(rest)
    local g = db(); if not g then out("Settings not loaded."); return end
    local instances = ensureInstanceShape(g)

    local first = rest:match("^(%S+)") or ""
    if first:lower() == "all" then
        local tail = rest:match("^%S+%s+(.+)$") or ""
        if tail:lower() ~= "confirm" then
            out("Type '/tox debug counter reset all confirm' to reset all instance counters.")
            return
        end
        g.session_buffer.counters.instances = {}
        out("All instance counters reset.")
        return
    end

    local instance, bucket, _extra, err = parseInstanceBucket(rest)
    if err then
        out("Usage: /tox debug counter reset <instance> <difficulty>"
            .. " || /tox debug counter reset all confirm")
        return
    end
    if not instances[instance] or not instances[instance][bucket] then
        out("No counters for '" .. instance .. "' / " .. bucket .. ".")
        return
    end
    instances[instance][bucket] = nil
    if not next(instances[instance]) then instances[instance] = nil end
    out("Counters reset: " .. instance .. " / " .. bucket .. ".")
end

local function cmdCounterSet(rest)
    local instance, bucket, after, err = parseInstanceBucket(rest)
    if err then
        out("Usage: /tox debug counter <instance> <difficulty> <field> <value>")
        return
    end
    local field, valStr = after:match("^(%S+)%s+(%S+)%s*$")
    if not field or not valStr then
        out("Usage: /tox debug counter <instance> <difficulty> <field> <value>")
        return
    end
    field = field:lower()
    if not FIELD_SET[field] then
        out("Unknown field '" .. field .. "'. Use deaths, wipes, or completions.")
        return
    end
    local n = tonumber(valStr)
    if not n or n < 0 or math.floor(n) ~= n then
        out("Value must be a non-negative integer.")
        return
    end
    local ok = setCounter(instance, bucket, field, n)
    if ok then
        out(string.format("Counter set: %s / %s / %s = %d.", instance, bucket, field, n))
    else
        out("Could not set counter.")
    end
end

local function cmdCounter(rest)
    rest = rest or ""
    local first = rest:match("^(%S+)") or ""
    local lower = first:lower()
    if lower == "list" then
        local tail = rest:match("^%S+%s*(.*)$") or ""
        cmdCounterList(tail)
        return
    end
    if lower == "reset" then
        local tail = rest:match("^%S+%s*(.*)$") or ""
        cmdCounterReset(tail)
        return
    end
    cmdCounterSet(rest)
end

local function cmdSession(rest)
    local sub = rest:match("^(%S+)") or ""
    if sub:lower() == "reset" then
        cmdSessionReset()
        return
    end
    out("Usage: /tox debug session reset")
end

local function printHelp()
    out("Debug subcommands:")
    print("  /tox debug enable || disable")
    print("  /tox debug version")
    print("  /tox debug counter <instance> <difficulty> <field> <value>  (count is an alias)")
    print("  /tox debug counter list [<instance>]")
    print("  /tox debug counter reset <instance> <difficulty>")
    print("  /tox debug counter reset all confirm")
    print("  /tox debug session reset")
    print("  Buckets: normal, heroic, mythic, M0, M2-5, M6-10, M10+")
    print("  Fields: deaths, wipes, completions")
end

-- Public dispatch entry. Always callable; gates internally on db.debug_enabled
-- so the surface is hidden from /tox help when disabled.
function Debug.dispatch(rest)
    rest = rest or ""
    local sub, after = rest:match("^(%S*)%s*(.*)$")
    sub = (sub or ""):lower()
    after = after or ""

    -- /tox debug enable always works so the user can flip the flag without a
    -- WoW restart. Everything else is silent when disabled.
    if sub == "enable" then cmdEnable(); return end

    if not isEnabled() then
        out("Unknown command 'debug'. Try /tox help.")
        return
    end

    if sub == ""        then printHelp(); return end
    if sub == "disable" then cmdDisable(); return end
    if sub == "version" then cmdVersion(); return end
    if sub == "counter" or sub == "count" then cmdCounter(after); return end
    if sub == "session" then cmdSession(after); return end
    out("Unknown debug subcommand '" .. sub .. "'. Try /tox debug.")
end

ns.Debug = Debug
