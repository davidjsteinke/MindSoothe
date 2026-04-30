-- Slash command handlers. Tone register is enforced strictly: factual,
-- no exclamation points, no cheerleading, no apologies. New strings should be
-- grepped against !|great|oops|sorry as a CI hygiene check.
--
-- Validates inputs and prints clear usage on bad args. State changes go through
-- ns.Database (account-wide via AceDB-3.0) and ns.UserRules. Returns boolean
-- success only for the few commands the chat-event hook needs to know about
-- (whisper-on triggers a one-shot privacy intro line).

local _, ns = ...

local Commands = {}

-- Channels exposed to the user. Order of `CHANNEL_ORDER` controls list output.
local CHANNEL_ORDER = { "party", "raid", "instance", "battleground", "whisper" }
local CHANNEL_SET   = { party = true, raid = true, instance = true, battleground = true, whisper = true }

-- Categories exposed to /tox handle. Order controls list output.
local CATEGORY_ORDER = {
    "identity_attack", "slur", "role_attack",
    "harassment", "harm_invocation", "general_hostility",
}

-- Real handlings consumed by the resolver. "default" is meta — see HANDLING_INPUT.
local HANDLING_SET = { pass = true, edit = true, del = true, silent = true }
-- Set of values accepted by /tox handle as the <mode> argument. "default" is
-- a meta-handling: it never reaches RuleEngine.classify's resolver because we
-- delete the override before resolution runs. Keeps the resolver contract
-- clean: resolver only ever sees pass/edit/del/silent.
local HANDLING_INPUT = { pass = true, edit = true, del = true, silent = true, default = true }

local ROLE_ORDER = { "auto", "tank", "healer", "dps" }
local ROLE_SET   = { auto = true, tank = true, healer = true, dps = true }

local function out(line) print("[ToxFilter] " .. line) end

local function db()
    return ns.Database and ns.Database:Get()
end

-- ===== Status =====

local function isPaused()
    return ns.ToxFilterState and ns.ToxFilterState.isPaused() or false
end

function Commands.status()
    local g = db()
    if not g then
        out("Status unavailable: settings not loaded.")
        return
    end
    if isPaused() then
        out("Paused — combat window")
        return
    end
    if not g.enabled then
        out("Disabled")
        return
    end
    if ns.Database:AllCategoriesPass() then
        out("Active — every category set to pass; filtering is effectively off")
        return
    end
    out("Active")
end

-- ===== Master toggle =====

function Commands.on()
    local g = db(); if not g then return end
    g.enabled = true
    out("Filtering enabled.")
end

function Commands.off()
    local g = db(); if not g then return end
    g.enabled = false
    out("Filtering disabled.")
end

-- ===== Channel toggles =====

local function channelList()
    local g = db(); if not g then return end
    -- Master-state header is intentional: per-channel toggles are independent
    -- of the master toggle, so showing channels as "on" while filtering is
    -- globally off would be visually misleading without this context.
    local masterTag = g.enabled and "enabled" or "DISABLED"
    out("Channels (master: " .. masterTag .. "):")
    for _, name in ipairs(CHANNEL_ORDER) do
        local state = g.channels[name] and "on" or "off"
        print(string.format("  %-12s %s", name, state))
    end
end

function Commands.channel(rest)
    local arg1, arg2 = rest:match("^(%S+)%s*(%S*)$")
    if not arg1 or arg1 == "" then
        out("Usage: /tox channel <name> on||off || /tox channel list")
        return
    end
    if arg1 == "list" then channelList(); return end

    local name = arg1:lower()
    if not CHANNEL_SET[name] then
        out("Unknown channel '" .. arg1 .. "'. Use party, raid, instance, battleground, or whisper.")
        return
    end
    local g = db(); if not g then return end

    if arg2 == "" then
        local state = g.channels[name] and "on" or "off"
        out("Channel '" .. name .. "' is " .. state .. ".")
        return
    end

    local turn = arg2:lower()
    if turn ~= "on" and turn ~= "off" then
        out("Usage: /tox channel " .. name .. " on||off")
        return
    end

    local newState = (turn == "on")
    g.channels[name] = newState

    if name == "whisper" and newState and ns.Database:NoteWhisperIntroIfNeeded() then
        out("Whisper filtering enabled. Your private 1:1 messages will now be"
            .. " filtered like other channels. This decision is yours alone.")
    else
        out("Channel '" .. name .. "' " .. (newState and "enabled" or "disabled") .. ".")
    end
end

-- ===== Category-handling override =====

local function handleList()
    local g = db(); if not g then return end
    out("Category handling:")
    for _, cat in ipairs(CATEGORY_ORDER) do
        local override = g.handling[cat]
        local default  = ns.Categories.HANDLING[cat]
        local shown    = override or (default .. " (default)")
        print(string.format("  %-20s %s", cat, shown))
    end
end

local SILENT_NOTE = "Note: silent drop hides messages without indication."
                 .. " The Tone of Communication design principle keeps silent drop opt-in."

-- Apply a single mode to one category. "default" clears the override (nil ==
-- use Categories.HANDLING default per the schema). Returns the mode actually
-- written so the caller can decide what to print.
local function applyHandling(cat, mode)
    local g = db(); if not g then return end
    if mode == "default" then
        g.handling[cat] = nil
    else
        g.handling[cat] = mode
    end
end

function Commands.handle(rest)
    local arg1, arg2 = rest:match("^(%S+)%s*(%S*)$")
    if not arg1 or arg1 == "" then
        out("Usage: /tox handle <category> <pass||edit||del||silent||default>"
            .. " || /tox handle <category> || /tox handle list"
            .. " || /tox handle all <handling>")
        return
    end
    if arg1 == "list" then handleList(); return end

    local cat = arg1:lower()
    local mode = arg2:lower()

    -- Batch shorthand: /tox handle all <mode> applies <mode> to every category
    -- in CATEGORY_ORDER. Silent-drop note is emitted once after the summary,
    -- not per-category, to avoid spam.
    if cat == "all" then
        if mode == "" then
            out("Usage: /tox handle all <pass||edit||del||silent||default>")
            return
        end
        if not HANDLING_INPUT[mode] then
            out("Unknown handling '" .. arg2 .. "'. Use pass, edit, del, silent, or default.")
            return
        end
        for _, c in ipairs(CATEGORY_ORDER) do applyHandling(c, mode) end
        if mode == "default" then
            out("All categories reset to default.")
        else
            out("All categories set to '" .. mode .. "'.")
        end
        if mode == "silent" then print(SILENT_NOTE) end
        return
    end

    if not ns.Categories.HANDLING[cat] then
        local known = table.concat(CATEGORY_ORDER, ", ")
        out("Unknown category '" .. arg1 .. "'. Known: " .. known .. ", or 'all' for batch.")
        return
    end

    if mode == "" then
        local g = db(); if not g then return end
        local override = g.handling[cat]
        if override then
            out("Category '" .. cat .. "' is set to '" .. override .. "'.")
        else
            out("Category '" .. cat .. "' is at default ('" .. ns.Categories.HANDLING[cat] .. "').")
        end
        return
    end

    if not HANDLING_INPUT[mode] then
        out("Unknown handling '" .. arg2 .. "'. Use pass, edit, del, silent, or default.")
        return
    end

    applyHandling(cat, mode)
    if mode == "default" then
        out("Category '" .. cat .. "' reset to default.")
    else
        out("Category '" .. cat .. "' set to '" .. mode .. "'.")
        if mode == "silent" then print(SILENT_NOTE) end
    end
end

-- ===== Role =====

function Commands.role(rest)
    local arg = rest:match("^(%S+)") or ""
    if arg == "" then
        local g = db(); if not g then return end
        local effective = ns.Database:GetEffectiveRole() or "unknown"
        out("Role: " .. g.role .. " (effective: " .. effective .. ").")
        return
    end
    arg = arg:lower()
    if not ROLE_SET[arg] then
        out("Unknown role '" .. rest:match("^(%S+)") .. "'. Use auto, tank, healer, or dps.")
        return
    end
    local g = db(); if not g then return end
    g.role = arg
    if arg == "auto" then
        local effective = ns.Database:GetEffectiveRole() or "unknown"
        out("Role set to auto-detect (effective: " .. effective .. ").")
    else
        out("Role set to '" .. arg .. "'.")
    end
end

-- ===== Blacklist / whitelist =====

local function listSubcommand(listName, displayName, rest)
    local sub, word = rest:match("^(%S+)%s*(.*)$")
    sub = sub or ""
    word = (word or ""):match("^%s*(.-)%s*$") or ""

    if sub == "" then
        out("Usage: /tox " .. listName .. " add||remove||list <word>")
        return
    end

    if sub == "list" then
        local entries = ns.UserRules.list(listName)
        if #entries == 0 then
            out(displayName .. " is empty.")
            return
        end
        out(displayName .. " (" .. #entries .. "):")
        for _, plaintext in ipairs(entries) do
            print("  " .. plaintext)
        end
        return
    end

    if sub ~= "add" and sub ~= "remove" then
        out("Usage: /tox " .. listName .. " add||remove||list <word>")
        return
    end

    if word == "" then
        out("Usage: /tox " .. listName .. " " .. sub .. " <word>")
        return
    end

    if sub == "add" then
        local ok, err, normalized = ns.UserRules.add(listName, word)
        if ok then
            out(displayName:sub(1, 1):upper() .. displayName:sub(2) .. ": added '" .. normalized .. "'.")
        elseif err == "empty" then
            out("Cannot add: '" .. word .. "' normalizes to empty.")
        elseif err == "duplicate" then
            out("'" .. (normalized or word) .. "' is already in " .. displayName:lower() .. ".")
        else
            out("Could not add '" .. word .. "': " .. tostring(err))
        end
    else
        local ok, err, normalized = ns.UserRules.remove(listName, word)
        if ok then
            out(displayName:sub(1, 1):upper() .. displayName:sub(2) .. ": removed '" .. normalized .. "'.")
        elseif err == "empty" then
            out("Cannot remove: '" .. word .. "' normalizes to empty.")
        elseif err == "absent" then
            out("'" .. (normalized or word) .. "' is not in " .. displayName:lower() .. ".")
        else
            out("Could not remove '" .. word .. "': " .. tostring(err))
        end
    end
end

function Commands.blacklist(rest) listSubcommand("blacklist", "blacklist", rest) end
function Commands.whitelist(rest) listSubcommand("whitelist", "whitelist", rest) end

-- ===== Comprehensive list =====

function Commands.list()
    local g = db(); if not g then out("Settings not loaded."); return end
    out("Settings:")
    print(string.format("  master:           %s", g.enabled and "on" or "off"))
    if isPaused() then
        print("  state:            paused (combat window)")
    elseif ns.Database:AllCategoriesPass() then
        print("  state:            soft-disabled (every category set to pass)")
    end
    print("  channels:")
    for _, name in ipairs(CHANNEL_ORDER) do
        print(string.format("    %-12s %s", name, g.channels[name] and "on" or "off"))
    end
    print("  handling:")
    for _, cat in ipairs(CATEGORY_ORDER) do
        local override = g.handling[cat]
        local default  = ns.Categories.HANDLING[cat]
        local shown    = override or (default .. " (default)")
        print(string.format("    %-20s %s", cat, shown))
    end
    local effectiveRole = ns.Database:GetEffectiveRole() or "unknown"
    print(string.format("  role:             %s (effective: %s)", g.role, effectiveRole))
    print(string.format("  blacklist:        %d entries", ns.UserRules.count("blacklist")))
    print(string.format("  whitelist:        %d entries", ns.UserRules.count("whitelist")))
end

-- ===== Help =====

-- Pipes are doubled to "||" so WoW's chat-frame escape parser doesn't consume
-- them as color-reset (|r) or other escapes. The user sees a single pipe.
local HELP_GROUPS = {
    { "Filtering", "/tox on || /tox off || /tox status" },
    { "Channels",  "/tox channel <name> on||off || /tox channel list" },
    { "Handling",  "/tox handle <category> <pass||edit||del||silent||default>"
                .. " || /tox handle all <handling> || /tox handle list" },
    { "Lists",     "/tox blacklist <add||remove||list> [word]"
                .. " || /tox whitelist <add||remove||list> [word]" },
    { "Role",      "/tox role <auto||tank||healer||dps>" },
    { "Inspect",   "/tox version || /tox rules || /tox list"
                .. " || /tox test <msg> || /tox classify <msg> || /tox rewrite <msg>" },
    { "Help",      "/tox help || /tox help <command>" },
}

local HELP_COMMANDS = {
    on        = "/tox on — enable filtering globally.",
    off       = "/tox off — disable filtering globally."
             .. " Rule engine still runs for /tox test/classify/rewrite.",
    status    = "/tox status — Active, Disabled, or Paused (combat window).",
    channel   = "/tox channel <name> on||off — toggle a channel."
             .. " /tox channel list — show all (with master state)."
             .. " Channels: party, raid, instance, battleground, whisper."
             .. " Whisper defaults to off — private 1:1 messages are not filtered unless you opt in.",
    handle    = "/tox handle <category> <mode> — override default handling."
             .. " Modes: pass, edit, del, silent, default (default clears the override)."
             .. " Categories: identity_attack, slur, role_attack, harassment,"
             .. " harm_invocation, general_hostility."
             .. " /tox handle all <mode> — apply a mode to every category at once."
             .. " /tox handle list — show current map.",
    role      = "/tox role <auto||tank||healer||dps> — set or override role."
             .. " 'auto' uses spec detection.",
    blacklist = "/tox blacklist add <word> — add a user-defined word,"
             .. " treated as general_hostility severity 5. remove / list also supported.",
    whitelist = "/tox whitelist add <word> — exempt a word from rule-engine matching."
             .. " remove / list also supported.",
    list      = "/tox list — comprehensive snapshot of every setting.",
    version   = "/tox version — print the addon version.",
    rules     = "/tox rules — print rule-data version, generation timestamp, counts.",
    test      = "/tox test <message> — show what handling/category the rule engine assigns.",
    classify  = "/tox classify <message> — print attack/tactical span breakdown plus signals.",
    rewrite   = "/tox rewrite <message> — show the rendered output the user would see.",
    help      = "/tox help — show grouped command summary. /tox help <command> — details for one command.",
}

function Commands.help(rest)
    local arg = rest:match("^(%S+)") or ""
    if arg == "" then
        out("Commands:")
        for _, grp in ipairs(HELP_GROUPS) do
            print(string.format("  %-10s %s", grp[1] .. ":", grp[2]))
        end
        return
    end
    arg = arg:lower()
    local detail = HELP_COMMANDS[arg]
    if not detail then
        out("No help for '" .. arg .. "'. Try /tox help.")
        return
    end
    out(detail)
end

function Commands.summary()
    out("Commands: /tox on || /tox off || /tox status || /tox channel ... || /tox handle ..."
        .. " || /tox role ... || /tox blacklist ... || /tox whitelist ... || /tox list"
        .. " || /tox version || /tox rules || /tox test <msg> || /tox classify <msg>"
        .. " || /tox rewrite <msg> || /tox help")
end

-- ===== Inspect commands (carried forward from Sprints 1 & 2) =====

function Commands.version()
    local v = ns.ToxFilterAddon and ns.ToxFilterAddon.VERSION or "unknown"
    out("Version " .. v)
end

function Commands.rules()
    if not ns.RuleData then
        out("Rule data not loaded")
        return
    end
    out("Rule data: " .. ns.RuleData.hash_version
        .. " / " .. ns.RuleData.normalization_version)
    out("Generated: " .. (ns.RuleData.generated_at or "unknown"))
    out("Words: " .. ns.RuleData.stats.word_count
        .. ", Phrases: " .. ns.RuleData.stats.phrase_count)
    local counts = {}
    for _, entry in pairs(ns.RuleData.words) do
        counts[entry.category] = (counts[entry.category] or 0) + 1
    end
    local parts = {}
    for cat, n in pairs(counts) do parts[#parts + 1] = cat .. "=" .. n end
    table.sort(parts)
    if #parts > 0 then out("By category: " .. table.concat(parts, ", ")) end
end

function Commands.test(rest)
    if not rest or rest == "" then
        out("Usage: /tox test <message>")
        return
    end
    local result = ns.RuleEngine.classify(rest, function(cat) return ns.Database:ResolveHandling(cat) end)
    local line = "Test result: '" .. rest .. "' → " .. result.handling
    if result.category then
        local extra = ""
        local others = (result.hits or 1) - 1
        if others == 1 then extra = ", +1 other hit"
        elseif others > 1 then extra = ", +" .. others .. " other hits" end
        line = line .. " (" .. result.category .. extra .. ")"
    end
    out(line)
end

local function spanByLabel(raw_tokens, labels, target)
    if not raw_tokens or not labels then return "" end
    local out_tokens = {}
    for i = 1, #raw_tokens do
        if (labels[i] or "neutral") == target then
            out_tokens[#out_tokens + 1] = raw_tokens[i]
        end
    end
    return table.concat(out_tokens, " ")
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

function Commands.classify(rest)
    if not rest or rest == "" then
        out("Usage: /tox classify <message>")
        return
    end
    local result = ns.RuleEngine.classify(rest, function(cat) return ns.Database:ResolveHandling(cat) end)
    local cat = result.category or "pass"
    local attack   = spanByLabel(result.raw_tokens, result.labels, "attack")
    local tactical = spanByLabel(result.raw_tokens, result.labels, "tactical")
    local sigs = signalsList(result.signals)
    local sig_str = (#sigs == 0) and "(none)" or table.concat(sigs, ", ")
    out("Classify: '" .. rest .. "' → " .. cat
        .. " | attack: '" .. attack .. "'"
        .. " | tactical: '" .. tactical .. "'"
        .. " | signals: " .. sig_str)
end

function Commands.rewrite(rest)
    if not rest or rest == "" then
        out("Usage: /tox rewrite <message>")
        return
    end
    local result = ns.RuleEngine.classify(rest, function(cat) return ns.Database:ResolveHandling(cat) end)
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
    out("Rewrite: '" .. rest .. "' → '" .. rendered .. "'")
end

-- ===== Top-level dispatch =====

local DISPATCH = {
    on        = function(_)    Commands.on()        end,
    off       = function(_)    Commands.off()       end,
    status    = function(_)    Commands.status()    end,
    channel   = function(rest) Commands.channel(rest) end,
    handle    = function(rest) Commands.handle(rest)  end,
    role      = function(rest) Commands.role(rest)    end,
    blacklist = function(rest) Commands.blacklist(rest) end,
    whitelist = function(rest) Commands.whitelist(rest) end,
    list      = function(_)    Commands.list()      end,
    version   = function(_)    Commands.version()   end,
    rules     = function(_)    Commands.rules()     end,
    test      = function(rest) Commands.test(rest)  end,
    classify  = function(rest) Commands.classify(rest) end,
    rewrite   = function(rest) Commands.rewrite(rest)  end,
    help      = function(rest) Commands.help(rest)  end,
}

function Commands.dispatch(input)
    input = input and input:match("^%s*(.-)%s*$") or ""
    if input == "" then
        Commands.summary()
        return
    end
    local sub, rest = input:match("^(%S+)%s*(.*)$")
    sub  = sub or ""
    rest = rest or ""
    local fn = DISPATCH[sub:lower()]
    if fn then
        fn(rest)
    else
        out("Unknown command '" .. sub .. "'. Try /tox help.")
    end
end

ns.Commands = Commands
