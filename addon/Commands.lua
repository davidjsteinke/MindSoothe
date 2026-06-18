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

-- Channels exposed to the user. CHANNEL_ORDER lists the canonical keys in the
-- order they appear in /tox channel list. `party` is a backward-compatible
-- input alias for `instance` (Sprint 4 fix Issue 2): WoW retail no longer
-- routes /p separately, so the canonical key is `instance` and the list view
-- annotates it with "(also: party)" so old habits keep working.
local CHANNEL_ORDER   = { "raid", "instance", "battleground", "whisper" }
local CHANNEL_SET     = { raid = true, instance = true, battleground = true, whisper = true, party = true }
local CHANNEL_CANONICAL = { party = "instance" }
local function canonicalChannel(name)
    return CHANNEL_CANONICAL[name] or name
end

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
        -- Sprint 7a (F1): note the silent-drop carve-out when it's active, so the
        -- pause line doesn't read as "everything passes through".
        if g.combat_silent_drop and ns.Category and ns.Category.gate("toxfilter") then
            out("Paused — combat window (silent-drop active)")
        else
            out("Paused — combat window")
        end
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
    -- Sprint 5d: surface a category master that is off so the user isn't left
    -- wondering why a family went quiet. Silent when both are on (default).
    if ns.Category then
        if not ns.Category.isEnabled("toxfilter") then out("ToxFilter category: off") end
        if not ns.Category.isEnabled("uplifter") then out("Uplifter category: off") end
    end
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

-- Sprint 7a (F1): in-combat silent-drop toggle. No-arg shows state (mirrors
-- /tox callout / /tox reminders). The wording is scoped to match the GUI label
-- so "combat: on" can't be read as a general combat-window switch — it only
-- silent-drops pure hostility (slurs, harm) during boss combat; everything else
-- passes through untouched while paused.
local COMBAT_SILENT_NOTE = "Note: matching messages vanish with no indication."
function Commands.combat(rest)
    local g = db(); if not g then return end
    local sub = (rest:match("^(%S*)") or ""):lower()

    if sub == "" then
        out("Combat silent-drop: " .. (g.combat_silent_drop and "on" or "off")
            .. ". Silent-drops pure hostility (slurs, harm) during boss combat;"
            .. " nothing else is touched while paused.")
        if g.combat_silent_drop then out(COMBAT_SILENT_NOTE) end
        return
    end
    if sub == "on" then
        g.combat_silent_drop = true
        out("Combat silent-drop enabled.")
        out(COMBAT_SILENT_NOTE)
        return
    end
    if sub == "off" then
        g.combat_silent_drop = false
        out("Combat silent-drop disabled.")
        return
    end
    out("Usage: /tox combat || /tox combat on||off")
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
        if name == "instance" then
            print(string.format("  %-12s %s (also: party)", name, state))
        else
            print(string.format("  %-12s %s", name, state))
        end
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
        out("Unknown channel '" .. arg1 .. "'. Use raid, instance, battleground, or whisper"
            .. " (party is an alias for instance).")
        return
    end
    local canonical = canonicalChannel(name)
    local g = db(); if not g then return end

    if arg2 == "" then
        local state = g.channels[canonical] and "on" or "off"
        if canonical ~= name then
            out("Channel '" .. name .. "' (alias for instance) is " .. state .. ".")
        else
            out("Channel '" .. name .. "' is " .. state .. ".")
        end
        return
    end

    local turn = arg2:lower()
    if turn ~= "on" and turn ~= "off" then
        out("Usage: /tox channel " .. name .. " on||off")
        return
    end

    local newState = (turn == "on")
    g.channels[canonical] = newState

    if canonical == "whisper" and newState and ns.Database:NoteWhisperIntroIfNeeded() then
        out("Whisper filtering enabled. Note: this reads private messages sent to you."
            .. " Filtered output is shown only to you. Disable with /tox channel whisper off.")
    else
        local label = (canonical ~= name)
            and ("Channel '" .. canonical .. "' (" .. name .. " alias)")
            or  ("Channel '" .. canonical .. "'")
        out(label .. " " .. (newState and "enabled" or "disabled") .. ".")
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
        local resolved = ns.Categories.HANDLING[cat] or "pass"
        out("Category '" .. cat .. "' reset to default (" .. resolved .. ").")
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
    print("  categories:")
    print(string.format("    %-12s %s", "toxfilter",
        ns.Category and ns.Category.isEnabled("toxfilter") and "on" or "off"))
    print(string.format("    %-12s %s", "uplifter",
        ns.Category and ns.Category.isEnabled("uplifter") and "on" or "off"))
    if isPaused() then
        local suffix = (g.combat_silent_drop and ns.Category and ns.Category.gate("toxfilter"))
            and " (silent-drop active)" or ""
        print("  state:            paused (combat window)" .. suffix)
    elseif ns.Database:AllCategoriesPass() then
        print("  state:            soft-disabled (every category set to pass)")
    end
    print("  channels:")
    for _, name in ipairs(CHANNEL_ORDER) do
        local state = g.channels[name] and "on" or "off"
        if name == "instance" then
            print(string.format("    %-12s %s (also: party)", name, state))
        else
            print(string.format("    %-12s %s", name, state))
        end
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
    print(string.format("  callout:          master %s, ui %s, sound %s (%s)",
        g.callout_enabled and "on" or "off",
        g.callout_ui      and "on" or "off",
        g.callout_sound   and "on" or "off",
        ns.Callout and ns.Callout.CurrentSoundName() or "readycheck"))
    print(string.format("  combat-drop:      %s", g.combat_silent_drop and "on" or "off"))
    local enc_count, seen_count = 0, 0
    if ns.TacticReminders then
        local _, ec = ns.TacticReminders.CountEncounters()
        enc_count  = ec
        seen_count = ns.TacticReminders.CountSeen()
    end
    print(string.format("  reminders:        master %s (%d encounters in journal, %d seen this session)",
        g.tactic_reminders_enabled and "on" or "off", enc_count, seen_count))
    local inst_count, w_seen = 0, 0
    if ns.PreDungeon then
        inst_count = ns.PreDungeon.CountInstances()
        w_seen     = ns.PreDungeon.CountSeen()
    end
    print(string.format("  warnings:         master %s (%d instances with warning data, %d seen this session)",
        g.predungeon_warnings_enabled and "on" or "off", inst_count, w_seen))
end

-- ===== Sprint 6b: consolidated state readout =====

-- Dense, single-block view of every toggle layer (master, both category masters,
-- per-feature toggles, channels, role). Companion to the GUI for fast in-combat
-- text checks. Separators are spaces only — no literal pipes — so the chat-frame
-- escape parser has nothing to consume (A6 pipe-doubling audit stays clean).
function Commands.state()
    local g = db()
    if not g then out("Settings not loaded."); return end
    local function onoff(v) return v and "on" or "off" end
    out("State:")
    print(string.format("  master      %s    paused %s",
        onoff(g.enabled), isPaused() and "yes" or "no"))
    print(string.format("  category    toxfilter %s    uplifter %s",
        onoff(ns.Category and ns.Category.isEnabled("toxfilter")),
        onoff(ns.Category and ns.Category.isEnabled("uplifter"))))
    local overridden = 0
    for _, cat in ipairs(CATEGORY_ORDER) do
        if g.handling[cat] then overridden = overridden + 1 end
    end
    print(string.format("  toxfilter   handling %d/%d overridden    blacklist %d    whitelist %d    combat-drop %s",
        overridden, #CATEGORY_ORDER,
        ns.UserRules.count("blacklist"), ns.UserRules.count("whitelist"),
        onoff(g.combat_silent_drop)))
    print(string.format(
        "  uplifter    positive-ui %s    callout %s (ui %s sound %s [%s])"
        .. "    reminders %s    warnings %s    stats-surface %s",
        onoff(g.positive_ui),
        onoff(g.callout_enabled), onoff(g.callout_ui), onoff(g.callout_sound),
        ns.Callout and ns.Callout.CurrentSoundName() or "readycheck",
        onoff(g.tactic_reminders_enabled), onoff(g.predungeon_warnings_enabled),
        onoff(g.stats_surface)))
    print(string.format("  channels    raid %s    instance %s    bg %s    whisper %s",
        onoff(g.channels.raid), onoff(g.channels.instance),
        onoff(g.channels.battleground), onoff(g.channels.whisper)))
    local effectiveRole = ns.Database:GetEffectiveRole() or "unknown"
    print(string.format("  role        %s (effective %s)", g.role, effectiveRole))
end

-- Opens the AceConfig options panel. The panel is a view over the same db state
-- these slash commands read and write — no separate GUI state store.
function Commands.config()
    if ns.Options and ns.Options.Open then
        ns.Options.Open()
    else
        out("Options panel unavailable: AceConfig libraries not loaded.")
    end
end

-- ===== Help =====

-- Pipes are doubled to "||" so WoW's chat-frame escape parser doesn't consume
-- them as color-reset (|r) or other escapes. The user sees a single pipe.
local HELP_GROUPS = {
    { "Filtering", "/tox on || /tox off || /tox status || /tox combat on||off" },
    { "Category",  "/tox category || /tox category toxfilter on||off || /tox category uplifter on||off" },
    { "Channels",  "/tox channel <name> on||off || /tox channel list" },
    { "Handling",  "/tox handle <category> <pass||edit||del||silent||default>"
                .. " || /tox handle all <handling> || /tox handle list" },
    { "Lists",     "/tox blacklist <add||remove||list> [word]"
                .. " || /tox whitelist <add||remove||list> [word]" },
    { "Role",      "/tox role <auto||tank||healer||dps>" },
    { "Surface",   "/tox lift || /tox positive [ui [on||off]] || /tox session" },
    { "Stats",     "/tox stats [<dungeon>||threshold <N>||surface on||off] || /tox week" },
    { "Pinned",    "/tox star <id> || /tox unstar <id> || /tox starred" },
    { "Ritual",    "/tox check [add||remove||list||y||n||cancel] [item]" },
    { "Callout",   "/tox callout || /tox callout on||off"
                .. " || /tox callout ui on||off"
                .. " || /tox callout sound on||off||set <name>||list||preview <name>" },
    { "Reminders", "/tox reminders || /tox reminders on||off || /tox reminders reset" },
    { "Warnings",  "/tox warnings || /tox warnings on||off || /tox warnings reset" },
    { "Breathe",   "/tox breathe || /tox breathe cycles <N>"
                .. " || /tox breathe count <N> || /tox breathe position <x> <y>" },
    { "Ready",     "/tox ready || /tox ready list || /tox ready cancel"
                .. " || /tox ready include <step> on||off"
                .. " || /tox ready order <step> <step> <step>" },
    { "Buffer",    "/tox retention <days>" },
    { "Config",    "/tox config || /tox state" },
    { "Inspect",   "/tox version || /tox rules || /tox list"
                .. " || /tox test <msg> || /tox classify <msg> || /tox rewrite <msg>" },
    { "Help",      "/tox help || /tox help <command>" },
}

local HELP_COMMANDS = {
    on        = "/tox on — enable filtering globally.",
    off       = "/tox off — disable filtering globally."
             .. " Rule engine still runs for /tox test/classify/rewrite.",
    status    = "/tox status — Active, Disabled, or Paused (combat window)."
             .. " Notes the in-combat silent-drop carve-out when active,"
             .. " and a category master that is off.",
    combat    = "/tox combat — show the in-combat silent-drop state."
             .. " /tox combat on||off toggles it (default on)."
             .. " When on, high-confidence pure hostility (slurs, harm) is"
             .. " silent-dropped during boss combat; everything else passes"
             .. " through untouched while paused. Matching messages vanish with"
             .. " no indication. Gated by the ToxFilter category and the master.",
    category  = "/tox category — show both category master states."
             .. " /tox category toxfilter on||off gates the chat-hygiene family"
             .. " (filtering, handling, blacklist, rewrite, test fixtures)."
             .. " /tox category uplifter on||off gates the confidence family"
             .. " (capture, highlight, callouts, reminders, warnings, stats surfacing)."
             .. " Per-feature toggles are preserved across category off then on."
             .. " User-invoked commands (/tox lift, /tox stats, /tox breathe, etc.)"
             .. " still work when a category is off; only passive surfacing stops."
             .. " /tox off remains the addon-wide master above both categories.",
    channel   = "/tox channel <name> on||off — toggle a channel."
             .. " /tox channel list — show all (with master state)."
             .. " Channels: raid, instance, battleground, whisper. 'party' is an"
             .. " alias for instance (WoW retail folds /p into instance chat)."
             .. " Whisper defaults to off — private 1:1 messages are not filtered unless you opt in.",
    handle    = "/tox handle <category> <mode> — override default handling."
             .. " Modes: pass, edit, del, silent, default (default clears the override)."
             .. " Categories: identity_attack, slur, role_attack, harassment,"
             .. " harm_invocation, general_hostility."
             .. " /tox handle all <mode> — apply a mode to every category at once."
             .. " /tox handle list — show current map.",
    role      = "/tox role <auto||tank||healer||dps> — set or override role."
             .. " 'auto' uses spec detection.",
    blacklist = "/tox blacklist add <word> — add a user-defined word."
             .. " Hits route to edit handling regardless of category default."
             .. " remove / list also supported.",
    whitelist = "/tox whitelist add <word> — exempt a word from rule-engine matching."
             .. " remove / list also supported.",
    list      = "/tox list — comprehensive snapshot of every setting.",
    state     = "/tox state — dense one-block readout of every toggle layer"
             .. " (master, both category masters, per-feature toggles, channels, role)."
             .. " Faster than /tox list for an in-combat check.",
    config    = "/tox config — open the graphical options panel"
             .. " (also under Esc, Options, AddOns). The panel is a view over the"
             .. " same state these slash commands use; changes stay in sync.",
    version   = "/tox version — print the addon version.",
    rules     = "/tox rules — print rule-data version, generation timestamp, counts.",
    test      = "/tox test <message> — show what handling/category the rule engine assigns.",
    classify  = "/tox classify <message> — print attack/tactical span breakdown plus signals.",
    rewrite   = "/tox rewrite <message> — show the rendered output the user would see.",
    lift      = "/tox lift — print the most recent positive moment captured. Works during"
             .. " combat-pause windows; it's user-invoked, not live filtering.",
    positive  = "/tox positive — print the 10 most recent positive moments."
             .. " /tox positive ui — toggle the in-line highlight (or pass on||off to set explicitly).",
    session   = "/tox session — current play-session detail (start time, encounters, deaths, thanks)."
             .. " For lifetime aggregates use /tox stats.",
    stats     = "/tox stats — lifetime aggregate counters across every instance."
             .. " For the current play session only, use /tox session."
             .. " /tox stats <instance> — per-bucket record (substring match on instance name)."
             .. " /tox stats threshold <0-100> — wipe-rate threshold for live surfacing."
             .. " /tox stats surface on||off — toggle live encounter/dungeon stat surfacing.",
    week      = "/tox week — last 7 days summary computed from the activity log.",
    star      = "/tox star <id> — pin a positive moment by its pm_NNN id."
             .. " Pinned moments survive retention pruning. Cap 100; oldest unpins on overflow.",
    unstar    = "/tox unstar <id> — unpin a moment.",
    starred   = "/tox starred — list all pinned moments (chronological).",
    check     = "/tox check — start the grounding ritual."
             .. " /tox check add <item> / /tox check remove <item> / /tox check list manage items."
             .. " /tox check y / /tox check n advance the ritual."
             .. " /tox check cancel aborts. Default item list is empty.",
    callout   = "/tox callout — show current callout state."
             .. " /tox callout on||off toggles the master switch (off by default)."
             .. " /tox callout ui on||off — visual amber tint when a callout addresses your role."
             .. " /tox callout sound on||off — audio cue at the same moment."
             .. " /tox callout sound set <name> picks the cue; list shows the"
             .. " choices; preview <name> plays one once. Callouts fire during"
             .. " combat too (time-critical).",
    reminders = "/tox reminders — show current reminders state and journal coverage."
             .. " /tox reminders on||off toggles pre-encounter tactical reminders (off by default)."
             .. " /tox reminders reset clears the session's seen-encounter map so reminders re-surface."
             .. " Reminders fire once per (instance, encounter, difficulty) per session;"
             .. " the seen-map clears automatically on /reload.",
    warnings  = "/tox warnings — show current warnings state and instance coverage."
             .. " /tox warnings on||off toggles per-key pre-dungeon warnings (off by default)."
             .. " /tox warnings reset clears the session's seen-instance map so warnings re-surface."
             .. " Warnings fire once per dungeon per session at the Mythic+ countdown"
             .. " (interrupts, dispels, tips for your role); the seen-map clears on /reload.",
    breathe   = "/tox breathe — run the box-breathing animation."
             .. " /tox breathe cycles <1-20> sets cycle count (default 4)."
             .. " /tox breathe count <1-20> sets seconds per phase (default 4)."
             .. " /tox breathe position <x> <y> sets frame offset; reset to recenter."
             .. " Esc closes the frame.",
    ready     = "/tox ready — chain grounding then breathing then lift in user-configured order."
             .. " /tox ready list shows the current chain."
             .. " /tox ready cancel aborts the active chain regardless of step."
             .. " /tox ready include <step> on||off toggles a step."
             .. " /tox ready order <step> <step> <step> reorders."
             .. " /tox check cancel or Esc on the breathing frame also aborts the chain.",
    retention = "/tox retention <days> — set windowed-event retention (7-365). Default 30."
             .. " Pinned moments are exempt from pruning.",
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
        .. " || /tox role ... || /tox blacklist ... || /tox whitelist ..."
        .. " || /tox lift || /tox positive ... || /tox session"
        .. " || /tox stats ... || /tox week || /tox star ... || /tox starred"
        .. " || /tox check ... || /tox breathe ... || /tox ready ..."
        .. " || /tox callout ..."
        .. " || /tox reminders ..."
        .. " || /tox warnings ..."
        .. " || /tox category ..."
        .. " || /tox config || /tox state"
        .. " || /tox retention ... || /tox list"
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
    local line = "Test result: '" .. rest .. "' -> " .. result.handling
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
    out("Classify: '" .. rest .. "' -> " .. cat
        .. " || attack: '" .. attack .. "'"
        .. " || tactical: '" .. tactical .. "'"
        .. " || signals: " .. sig_str)
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
    out("Rewrite: '" .. rest .. "' -> '" .. rendered .. "'")
end

-- ===== Sprint 4a: surfacing, stats, pinned moments, ritual, retention =====

local function fmtStamp(ts)
    if not ts then return "?" end
    if type(date) == "function" then return date("%a %H:%M", ts) end
    return tostring(ts)
end

-- Sprint 7a (F4): a captured emote ("Bob thanks you.") reads in third person,
-- unlike typed praise. Mark it so the moment's provenance is honest; the flag is
-- already stored on the moment's signals, so the marker is near-free.
local function emoteTag(m)
    return (m and m.signals and m.signals.emote) and " (emote)" or ""
end

function Commands.lift()
    if not (ns.Buffer and ns.Buffer.GetMostRecentPositiveMoment) then
        out("Buffer not loaded.")
        return
    end
    local m = ns.Buffer:GetMostRecentPositiveMoment()
    if not m then
        out("No recent positive moments captured.")
        return
    end
    out(fmtStamp(m.ts) .. " — " .. m.id .. " — '" .. (m.text or "") .. "'" .. emoteTag(m))
end

function Commands.positive(rest)
    local sub, after = rest:match("^(%S*)%s*(%S*)$")
    sub = sub or ""
    after = after or ""
    if sub == "ui" then
        local g = db(); if not g then return end
        if after == "" then
            -- No-arg form toggles. Explicit on/off below sets the value.
            g.positive_ui = not g.positive_ui
            out("Positive-moment highlight " .. (g.positive_ui and "enabled" or "disabled") .. ".")
            return
        end
        if after ~= "on" and after ~= "off" then
            out("Usage: /tox positive ui [on||off]")
            return
        end
        g.positive_ui = (after == "on")
        out("Positive-moment highlight " .. (g.positive_ui and "enabled" or "disabled") .. ".")
        return
    end
    if sub ~= "" then
        out("Usage: /tox positive [ui [on||off]]")
        return
    end
    if not (ns.Buffer and ns.Buffer.GetPositiveMoments) then
        out("Buffer not loaded.")
        return
    end
    local moments = ns.Buffer:GetPositiveMoments(10)
    if #moments == 0 then
        out("No positive moments captured.")
        return
    end
    out(string.format("Positive moments (%d most recent):", #moments))
    for _, m in ipairs(moments) do
        print(string.format("  %s  %s  '%s'%s", fmtStamp(m.ts), m.id, m.text or "", emoteTag(m)))
    end
end

function Commands.session()
    if not (ns.Buffer and ns.Buffer.GetSessionCurrent) then
        out("Buffer not loaded.")
        return
    end
    local sess = ns.Buffer:GetSessionCurrent()
    if not sess then out("No active session."); return end
    out("Current session:")
    print(string.format("  started:           %s", fmtStamp(sess.started_at)))
    print(string.format("  encounters won:    %d", sess.encounters_completed or 0))
    print(string.format("  encounters wiped:  %d", sess.encounters_wiped or 0))
    print(string.format("  deaths:            %d", sess.deaths or 0))
    print(string.format("  thanks received:   %d", sess.thanks_received or 0))
end

-- Sprint 4 fix Issue 6: instance scope only. Battleground/arena/world deaths
-- aren't tracked at all, so /tox stats is purely a dungeon-and-raid summary.
-- The no-arg form aggregates across all (instance, bucket) pairs into a
-- single line and points at /tox stats <instance> for the per-bucket
-- breakdown.
local function statsAggregate()
    local g = db(); if not g then return end
    local sb = g.session_buffer or {}
    local counters = sb.counters or {}
    local instances = counters.instances or {}

    local total_deaths, total_wipes, total_completions = 0, 0, 0
    local instance_count = 0
    for _, buckets in pairs(instances) do
        instance_count = instance_count + 1
        for _, rec in pairs(buckets) do
            total_deaths      = total_deaths      + (rec.deaths      or 0)
            total_wipes       = total_wipes       + (rec.wipes       or 0)
            total_completions = total_completions + (rec.completions or 0)
        end
    end

    out("Stats:")
    print(string.format("  lifetime thanks:    %d", counters.thanks_total or 0))
    if instance_count == 0 then
        print("  no instance activity recorded")
    else
        print(string.format("  instance deaths:    %d", total_deaths))
        print(string.format("  instance attempts:  %d (%d completed, %d wiped)",
            total_completions + total_wipes, total_completions, total_wipes))
        print(string.format("  instances tracked:  %d (use /tox stats <name> for breakdown)",
            instance_count))
    end
    print(string.format("  threshold:          %d%%, surface: %s",
        g.stats_threshold or 30, g.stats_surface and "on" or "off"))
end

local function statsByInstance(query)
    local g = db(); if not g then return end
    local q = query:lower()
    local instances = g.session_buffer.counters.instances or {}
    local matches = {}
    for name, buckets in pairs(instances) do
        if name:lower():find(q, 1, true) then
            matches[#matches + 1] = { name = name, buckets = buckets }
        end
    end
    if #matches == 0 then
        out("No instance named '" .. query .. "' found."
            .. " Use /tox session for current-session stats.")
        return
    end
    table.sort(matches, function(a, b) return a.name < b.name end)
    out("Instance stats:")
    for _, m in ipairs(matches) do
        for _, line in ipairs(ns.Stats.formatInstanceBlock(m.name, m.buckets)) do
            print("  " .. line)
        end
    end
end

function Commands.stats(rest)
    rest = rest or ""
    local arg1, arg2 = rest:match("^(%S*)%s*(%S*)$")
    arg1 = arg1 or ""
    arg2 = arg2 or ""

    if arg1 == "threshold" then
        if arg2 == "" then
            local g = db(); if not g then return end
            out("Stats threshold: " .. tostring(g.stats_threshold or 30) .. "% wipe rate.")
            return
        end
        local n = tonumber(arg2)
        if not n or n < 0 or n > 100 then
            out("Usage: /tox stats threshold <0-100>")
            return
        end
        local g = db(); if not g then return end
        g.stats_threshold = math.floor(n)
        out("Stats threshold set to " .. g.stats_threshold .. "% wipe rate.")
        return
    end

    if arg1 == "surface" then
        if arg2 == "" then
            local g = db(); if not g then return end
            out("Stats surfacing: " .. (g.stats_surface and "on" or "off") .. ".")
            return
        end
        if arg2 ~= "on" and arg2 ~= "off" then
            out("Usage: /tox stats surface on||off")
            return
        end
        local g = db(); if not g then return end
        g.stats_surface = (arg2 == "on")
        out("Stats surfacing " .. (g.stats_surface and "enabled" or "disabled") .. ".")
        return
    end

    if arg1 == "" then
        statsAggregate()
        return
    end

    statsByInstance(rest)
end

function Commands.week()
    if not ns.Stats then out("Stats not loaded."); return end
    local s = ns.Stats.WeekSummary()
    if not s then out("No data."); return end
    out("Last 7 days:")
    print(string.format("  encounters won:    %d", s.completions))
    print(string.format("  encounters wiped:  %d", s.wipes))
    print(string.format("  deaths:            %d", s.deaths))
    print(string.format("  thanks received:   %d", s.thanks))
end

function Commands.star(rest)
    local id = rest:match("^(%S+)") or ""
    if id == "" then out("Usage: /tox star <id>"); return end
    if not (ns.Buffer and ns.Buffer.Pin) then out("Buffer not loaded."); return end
    local pinned, err, evicted_id = ns.Buffer:Pin(id)
    if pinned then
        if evicted_id then
            out("Pinned " .. id .. ". Cap reached; oldest pin (" .. evicted_id .. ") removed.")
        else
            out("Pinned " .. id .. ".")
        end
    elseif err == "not_found" then
        out("No moment with id '" .. id .. "'.")
    elseif err == "already_pinned" then
        out("Moment '" .. id .. "' is already pinned.")
    else
        out("Could not pin: " .. tostring(err))
    end
end

function Commands.unstar(rest)
    local id = rest:match("^(%S+)") or ""
    if id == "" then out("Usage: /tox unstar <id>"); return end
    if not (ns.Buffer and ns.Buffer.Unpin) then out("Buffer not loaded."); return end
    local ok, err = ns.Buffer:Unpin(id)
    if ok then
        out("Unpinned " .. id .. ".")
    elseif err == "not_found" then
        out("Moment '" .. id .. "' is not pinned.")
    else
        out("Could not unpin: " .. tostring(err))
    end
end

function Commands.starred()
    if not (ns.Buffer and ns.Buffer.GetPinned) then out("Buffer not loaded."); return end
    local list = ns.Buffer:GetPinned()
    if #list == 0 then out("No pinned moments."); return end
    out(string.format("Pinned moments (%d):", #list))
    for _, m in ipairs(list) do
        print(string.format("  %s  %s  '%s'%s", fmtStamp(m.ts), m.id, m.text or "", emoteTag(m)))
    end
end

function Commands.check(rest)
    rest = rest or ""
    local sub, after = rest:match("^(%S*)%s*(.-)$")
    sub = sub or ""
    after = (after or ""):match("^%s*(.-)%s*$") or ""

    if sub == "" then
        ns.Grounding.Start()
        return
    end
    if sub == "y" or sub == "n" then
        ns.Grounding.Respond(sub)
        return
    end
    if sub == "cancel" then
        if ns.Grounding.Cancel() then
            out("Grounding ritual cancelled.")
        else
            out("No grounding ritual in progress.")
        end
        return
    end
    if sub == "list" then
        local items = ns.Grounding.ListItems()
        if #items == 0 then
            out("No grounding items configured. Add items via /tox check add <item>.")
            return
        end
        out(string.format("Grounding items (%d):", #items))
        for i, it in ipairs(items) do print(string.format("  %d. %s", i, it)) end
        return
    end
    if sub == "add" then
        if after == "" then out("Usage: /tox check add <item>"); return end
        local ok, err = ns.Grounding.AddItem(after)
        if ok then out("Grounding item added: " .. after)
        elseif err == "duplicate" then out("Grounding item already exists: " .. after)
        elseif err == "empty" then out("Item is empty.")
        else out("Could not add item: " .. tostring(err)) end
        return
    end
    if sub == "remove" then
        if after == "" then out("Usage: /tox check remove <item>"); return end
        local ok, err = ns.Grounding.RemoveItem(after)
        if ok then out("Grounding item removed: " .. after)
        elseif err == "absent" then out("Grounding item not found: " .. after)
        elseif err == "empty" then out("Item is empty.")
        else out("Could not remove item: " .. tostring(err)) end
        return
    end

    out("Usage: /tox check [add||remove||list||y||n||cancel] [item]")
end

-- ===== Sprint 4b: breathing + ready orchestration =====

local READY_STEP_SET = { grounding = true, breathing = true, lift = true }

function Commands.breathe(rest)
    rest = rest or ""
    local sub, arg1, arg2 = rest:match("^(%S*)%s*(%S*)%s*(%S*)$")
    sub  = sub  or ""
    arg1 = arg1 or ""
    arg2 = arg2 or ""

    if sub == "" then
        if not (ns.Breathing and ns.Breathing.Run) then
            out("Box breathing not loaded.")
            return
        end
        ns.Breathing.Run()
        return
    end

    if sub == "cycles" then
        local g = db(); if not g then return end
        if arg1 == "" then
            out("Box breathing cycles: " .. tostring(g.breathe_cycles or 4) .. ".")
            return
        end
        local n = tonumber(arg1)
        if not n or n < 1 or n > 20 then
            out("Usage: /tox breathe cycles <1-20>")
            return
        end
        g.breathe_cycles = math.floor(n)
        out("Box breathing cycles set to " .. g.breathe_cycles .. ".")
        return
    end

    if sub == "count" then
        local g = db(); if not g then return end
        if arg1 == "" then
            out("Box breathing count: " .. tostring(g.breathe_count or 4) .. " seconds per phase.")
            return
        end
        local n = tonumber(arg1)
        if not n or n < 1 or n > 20 then
            out("Usage: /tox breathe count <1-20>")
            return
        end
        g.breathe_count = math.floor(n)
        out("Box breathing count set to " .. g.breathe_count .. " seconds per phase.")
        return
    end

    if sub == "position" then
        local g = db(); if not g then return end
        if arg1 == "reset" then
            g.breathe_position = nil
            out("Box breathing position reset to center.")
            return
        end
        local x = tonumber(arg1)
        local y = tonumber(arg2)
        if not x or not y then
            out("Usage: /tox breathe position <x> <y> || /tox breathe position reset")
            return
        end
        g.breathe_position = { x = x, y = y }
        out(string.format("Box breathing position set to %d, %d.",
            math.floor(x + 0.5), math.floor(y + 0.5)))
        return
    end

    out("Usage: /tox breathe || /tox breathe cycles <N> || /tox breathe count <N>"
        .. " || /tox breathe position <x> <y>")
end

local function readyConfigList()
    local cfg = ns.Ready and ns.Ready.GetConfig() or nil
    if not cfg then out("Ready not loaded."); return end
    local order   = cfg.order   or { "grounding", "breathing", "lift" }
    local include = cfg.include or {}
    out("Ready chain (in order):")
    for i, step in ipairs(order) do
        local on = include[step] and "on" or "off"
        print(string.format("  %d. %-10s %s", i, step, on))
    end
end

function Commands.ready(rest)
    rest = rest or ""
    if rest == "" then
        if not (ns.Ready and ns.Ready.Start) then
            out("Ready not loaded.")
            return
        end
        ns.Ready.Start()
        return
    end

    local sub, after = rest:match("^(%S+)%s*(.*)$")
    sub = sub or ""
    after = after or ""

    if sub == "list" then
        readyConfigList()
        return
    end

    if sub == "cancel" then
        if not (ns.Ready and ns.Ready.Cancel) then
            out("Ready not loaded.")
            return
        end
        if ns.Ready.Cancel() then
            out("Ready chain cancelled.")
        else
            out("No ready chain in progress.")
        end
        return
    end

    if sub == "include" then
        local step, mode = after:match("^(%S+)%s*(%S*)$")
        step = (step or ""):lower()
        mode = (mode or ""):lower()
        if step == "" then
            out("Usage: /tox ready include <grounding||breathing||lift> on||off")
            return
        end
        if not READY_STEP_SET[step] then
            out("Unknown step '" .. step .. "'. Use grounding, breathing, or lift.")
            return
        end
        if mode ~= "on" and mode ~= "off" then
            out("Usage: /tox ready include " .. step .. " on||off")
            return
        end
        local ok = ns.Ready.SetInclude(step, mode == "on")
        if ok then
            out("Ready step '" .. step .. "' " .. (mode == "on" and "enabled" or "disabled") .. ".")
        else
            out("Could not set include for '" .. step .. "'.")
        end
        return
    end

    if sub == "order" then
        local a, b, c = after:match("^(%S+)%s+(%S+)%s+(%S+)$")
        if not (a and b and c) then
            out("Usage: /tox ready order <step> <step> <step>"
                .. " (grounding, breathing, lift)")
            return
        end
        local ok, err = ns.Ready.SetOrder({ a:lower(), b:lower(), c:lower() })
        if ok then
            out("Ready order set: " .. a:lower() .. " " .. b:lower() .. " " .. c:lower() .. ".")
        elseif err and err:sub(1, 8) == "unknown:" then
            out("Unknown step '" .. err:sub(9) .. "'. Use grounding, breathing, lift.")
        elseif err and err:sub(1, 10) == "duplicate:" then
            out("Step '" .. err:sub(11) .. "' listed twice. Each step appears once.")
        elseif err == "bad_count" then
            out("Specify exactly three step names.")
        else
            out("Could not set order: " .. tostring(err))
        end
        return
    end

    out("Usage: /tox ready || /tox ready list || /tox ready cancel"
        .. " || /tox ready include <step> on||off"
        .. " || /tox ready order <step> <step> <step>")
end

-- Sprint 5: /tox callout. Master toggle + UI/sound sub-toggles. No-arg form
-- prints state for all three (matches the user spec; differs from /tox
-- positive's no-arg-toggles behavior). Sub-toggles only apply meaningfully
-- while the master is enabled; the printed state surfaces both regardless.
-- Sprint 7a (F2): `sound` now also takes set/list/preview alongside the
-- unchanged on/off. Parse up to three tokens (sub, after, trailing name) so
-- `sound set <name>` / `sound preview <name>` work.
local function calloutSound(g, after, name)
    -- Unchanged audio master toggle.
    if after == "on" or after == "off" then
        g.callout_sound = (after == "on")
        out("Callout sound " .. (g.callout_sound and "enabled" or "disabled") .. ".")
        return
    end
    if after == "list" then
        out("Callout sounds (current: " .. ns.Callout.CurrentSoundName() .. "):")
        for _, c in ipairs(ns.Callout.SOUND_CHOICES) do
            local mark = (c.id == ns.Callout.CurrentSoundId()) and " *" or ""
            print(string.format("  %-12s %s%s", c.name, c.label, mark))
        end
        return
    end
    if after == "set" then
        local id = ns.Callout.ResolveSoundName(name)
        if not id then
            out("Unknown sound '" .. (name ~= "" and name or "<none>")
                .. "'. Run /tox callout sound list.")
            return
        end
        g.callout_sound_id = id
        out("Callout sound set to " .. name .. ".")
        ns.Callout.PreviewSound(name)
        return
    end
    if after == "preview" then
        if not ns.Callout.PreviewSound(name) then
            out("Unknown sound '" .. (name ~= "" and name or "<none>")
                .. "'. Run /tox callout sound list.")
        end
        return
    end
    if after == "" then
        out("Callout sound: " .. (g.callout_sound and "on" or "off")
            .. ", selected " .. ns.Callout.CurrentSoundName() .. ".")
        out("Usage: /tox callout sound on||off || set <name> || list || preview <name>")
        return
    end
    out("Usage: /tox callout sound on||off || set <name> || list || preview <name>")
end

function Commands.callout(rest)
    local g = db(); if not g then return end
    local a, b, c = rest:match("^(%S*)%s*(%S*)%s*(.*)$")
    local sub   = (a or ""):lower()
    local after = (b or ""):lower()
    local name  = ((c or ""):match("^(%S*)") or ""):lower()

    if sub == "" then
        out("Callout: master "
            .. (g.callout_enabled and "on" or "off")
            .. ", ui "    .. (g.callout_ui    and "on" or "off")
            .. ", sound " .. (g.callout_sound and "on" or "off")
            .. " (" .. ns.Callout.CurrentSoundName() .. ").")
        if ns.Callout and ns.Callout.GetStateMismatchNote then
            local note = ns.Callout.GetStateMismatchNote()
            if note then out(note) end
        end
        return
    end

    if sub == "on" then
        g.callout_enabled = true
        out("Callout enabled.")
        if ns.Callout and ns.Callout.GetStateMismatchNote then
            local note = ns.Callout.GetStateMismatchNote()
            if note then out(note) end
        end
        return
    end
    if sub == "off" then
        g.callout_enabled = false
        out("Callout disabled.")
        return
    end

    if sub == "ui" then
        if after ~= "on" and after ~= "off" then
            out("Usage: /tox callout ui <on||off>")
            return
        end
        g.callout_ui = (after == "on")
        out("Callout visual " .. (g.callout_ui and "enabled" or "disabled") .. ".")
        return
    end
    if sub == "sound" then
        calloutSound(g, after, name)
        return
    end

    out("Usage: /tox callout || /tox callout on||off"
        .. " || /tox callout ui on||off || /tox callout sound on||off||set||list||preview")
end

-- Sprint 5b: /tox reminders. Master toggle + reset. No-arg form prints state.
-- Mirrors /tox callout's no-arg behavior (state, not toggle) — the same
-- distinction the spec called for between /tox positive (no-arg toggles) and
-- /tox callout (no-arg shows state). Reminders is a master+behavior toggle
-- with no sub-toggles, so the state line is minimal.
function Commands.reminders(rest)
    local g = db(); if not g then return end
    local sub = rest:match("^(%S*)") or ""
    sub = sub:lower()

    if sub == "" then
        local enc_count, seen_count = 0, 0
        if ns.TacticReminders then
            local _, ec = ns.TacticReminders.CountEncounters()
            enc_count  = ec
            seen_count = ns.TacticReminders.CountSeen()
        end
        out("Reminders: master "
            .. (g.tactic_reminders_enabled and "on" or "off")
            .. ". " .. enc_count .. " encounters in journal, "
            .. seen_count .. " seen this session.")
        return
    end

    if sub == "on" then
        g.tactic_reminders_enabled = true
        out("Reminders enabled.")
        return
    end
    if sub == "off" then
        g.tactic_reminders_enabled = false
        out("Reminders disabled.")
        return
    end
    if sub == "reset" then
        if ns.TacticReminders then ns.TacticReminders.ResetSession() end
        out("Reminders session reset. Each (encounter, difficulty) will re-surface on next pull.")
        return
    end

    out("Usage: /tox reminders || /tox reminders on||off || /tox reminders reset")
end

-- Sprint 5c: /tox warnings. Master toggle + reset. No-arg form prints state.
-- Mirrors /tox reminders shape exactly — master+behavior toggle, no sub-toggles.
function Commands.warnings(rest)
    local g = db(); if not g then return end
    local sub = rest:match("^(%S*)") or ""
    sub = sub:lower()

    if sub == "" then
        local inst_count, seen_count = 0, 0
        if ns.PreDungeon then
            inst_count = ns.PreDungeon.CountInstances()
            seen_count = ns.PreDungeon.CountSeen()
        end
        out("Warnings: master "
            .. (g.predungeon_warnings_enabled and "on" or "off")
            .. ". " .. inst_count .. " instances with warning data, "
            .. seen_count .. " seen this session.")
        return
    end

    if sub == "on" then
        g.predungeon_warnings_enabled = true
        out("Warnings enabled.")
        return
    end
    if sub == "off" then
        g.predungeon_warnings_enabled = false
        out("Warnings disabled.")
        return
    end
    if sub == "reset" then
        if ns.PreDungeon then ns.PreDungeon.ResetSession() end
        out("Warnings session reset. Each dungeon will re-surface on next key.")
        return
    end

    out("Usage: /tox warnings || /tox warnings on||off || /tox warnings reset")
end

-- Sprint 5d: /tox category. Two family master toggles sitting above the
-- per-feature toggles. No-arg prints both states. These toggles never touch the
-- per-feature sub-state (positive_ui, callout_*, reminders, warnings, channels,
-- handling) — turning a category off then on resumes features as they were.
local CATEGORY_FIELD = {
    toxfilter = "category_toxfilter_enabled",
    uplifter  = "category_uplifter_enabled",
}

function Commands.category(rest)
    local g = db(); if not g then return end
    local name, state = rest:match("^(%S*)%s*(%S*)$")
    name  = (name or ""):lower()
    state = (state or ""):lower()

    if name == "" then
        out("Categories:")
        print(string.format("  %-12s %s", "toxfilter",
            ns.Category and ns.Category.isEnabled("toxfilter") and "on" or "off"))
        print(string.format("  %-12s %s", "uplifter",
            ns.Category and ns.Category.isEnabled("uplifter") and "on" or "off"))
        return
    end

    local field = CATEGORY_FIELD[name]
    if not field then
        out("Unknown category '" .. name .. "'. Use toxfilter or uplifter.")
        return
    end
    if state == "on" then
        g[field] = true
        out(name .. " category enabled.")
        return
    end
    if state == "off" then
        g[field] = false
        out(name .. " category disabled.")
        return
    end
    out("Usage: /tox category || /tox category toxfilter on||off || /tox category uplifter on||off")
end

function Commands.retention(rest)
    local arg = rest:match("^(%S+)") or ""
    if arg == "" then
        local g = db(); if not g then return end
        out("Retention: " .. tostring(g.retention_days or 30) .. " days.")
        return
    end
    local n = tonumber(arg)
    if not n or n < 7 or n > 365 then
        out("Usage: /tox retention <days> (7-365)")
        return
    end
    local g = db(); if not g then return end
    g.retention_days = math.floor(n)
    if ns.Buffer then ns.Buffer:Prune(g.retention_days) end
    out("Retention set to " .. g.retention_days .. " days.")
end

-- ===== Top-level dispatch =====

local DISPATCH = {
    on        = function(_)    Commands.on()        end,
    off       = function(_)    Commands.off()       end,
    status    = function(_)    Commands.status()    end,
    combat    = function(rest) Commands.combat(rest) end,
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
    lift      = function(_)    Commands.lift()      end,
    positive  = function(rest) Commands.positive(rest) end,
    session   = function(_)    Commands.session()   end,
    stats     = function(rest) Commands.stats(rest) end,
    week      = function(_)    Commands.week()      end,
    star      = function(rest) Commands.star(rest)  end,
    unstar    = function(rest) Commands.unstar(rest) end,
    starred   = function(_)    Commands.starred()   end,
    check     = function(rest) Commands.check(rest) end,
    retention = function(rest) Commands.retention(rest) end,
    breathe   = function(rest) Commands.breathe(rest) end,
    ready     = function(rest) Commands.ready(rest)   end,
    callout   = function(rest) Commands.callout(rest) end,
    reminders = function(rest) Commands.reminders(rest) end,
    warnings  = function(rest) Commands.warnings(rest) end,
    category  = function(rest) Commands.category(rest) end,
    state     = function(_)    Commands.state()     end,
    config    = function(_)    Commands.config()    end,
    debug     = function(rest) if ns.Debug then ns.Debug.dispatch(rest) else
                                   out("Unknown command 'debug'. Try /tox help.") end end,
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
