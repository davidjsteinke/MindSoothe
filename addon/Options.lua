-- Sprint 6b: AceConfig-3.0 options panel. A VIEW over existing db state, never a
-- parallel store. Every control's get/set reads and writes the SAME db fields
-- (or calls the SAME ns.* module methods) the slash commands use, so the GUI and
-- /tox slash commands never diverge. There is no GUI-local state.
--
-- The options table is registered as a FUNCTION (buildOptions), not a static
-- table. AceConfigRegistry re-invokes it on every fetch/refresh, which gives the
-- dynamic list editors (blacklist/whitelist/grounding) live entries for free and
-- re-evaluates the category disabled() closures each render.
--
-- Greying (Sprint 5d sub-state preservation): each category's sub-group carries a
-- disabled() closure tied to ns.Category.isEnabled(family). AceConfig inherits
-- `disabled` to children, so a disabled sub-group greys all its controls while
-- they STILL display their preserved get() values. Re-enabling the category
-- un-greys at those preserved values. Grounding is deliberately NOT gated (it is
-- user-invoked, not Uplifter-category-gated today), so its sub-group is left
-- enabled.
--
-- Live refresh limitation (accepted for 6b): category toggles flipped IN-PANEL
-- call AceConfigRegistry:NotifyChange so the sub-groups grey/un-grey immediately,
-- and the Ready order swap refreshes its sibling selects. Settings changed via a
-- SLASH command while the panel is open are NOT wired to NotifyChange and may
-- display stale until the panel is reopened. This is an accepted 6b limitation;
-- we do not instrument every slash handler with NotifyChange.

local _, ns = ...

local APP = "ToxFilter"

local AceConfig         = LibStub("AceConfig-3.0", true)
local AceConfigDialog   = LibStub("AceConfigDialog-3.0", true)
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0", true)

local Options = {}

local function db()
    return ns.Database and ns.Database:Get() or nil
end

local function notify()
    if AceConfigRegistry then AceConfigRegistry:NotifyChange(APP) end
end

-- Write a single db field. Keeps the inline set closures short and routes every
-- GUI write through ns.Database:Get() — the same table the slash commands write.
local function setField(field, v)
    local g = db(); if g then g[field] = v end
end

-- Category ordering for the handling dropdowns; mirrors Commands.CATEGORY_ORDER.
local CATEGORY_ORDER = {
    "identity_attack", "slur", "role_attack",
    "harassment", "harm_invocation", "general_hostility",
}

local HANDLING_VALUES  = { default = "default", pass = "pass", edit = "edit",
                          del = "del", silent = "silent" }
local HANDLING_SORTING = { "default", "pass", "edit", "del", "silent" }

local ROLE_VALUES  = { auto = "auto", tank = "tank", healer = "healer", dps = "dps" }
local ROLE_SORTING = { "auto", "tank", "healer", "dps" }

local STEP_VALUES  = { grounding = "grounding", breathing = "breathing", lift = "lift" }
local STEP_SORTING = { "grounding", "breathing", "lift" }
local READY_STEPS  = { "grounding", "breathing", "lift" }

-- ===== disabled() closures per family =====

local function toxfilterDisabled()
    return not (ns.Category and ns.Category.isEnabled("toxfilter"))
end
local function uplifterDisabled()
    return not (ns.Category and ns.Category.isEnabled("uplifter"))
end

-- ===== Dynamic list editors (blacklist / whitelist / grounding) =====

-- Build per-entry remove buttons for a UserRules list. order0 reserves the
-- ordering band; the add-input sits below the entries.
local function userRuleEntries(listName, order0)
    local args = {}
    local entries = ns.UserRules and ns.UserRules.list(listName) or {}
    for i, word in ipairs(entries) do
        args["entry" .. i] = {
            type  = "execute",
            order = order0 + i,
            name  = word,
            desc  = "Remove this entry from the " .. listName .. ".",
            width = "full",
            func  = function()
                ns.UserRules.remove(listName, word)
                notify()
            end,
        }
    end
    return args
end

local function groundingEntries(order0)
    local args = {}
    local items = ns.Grounding and ns.Grounding.ListItems() or {}
    for i, item in ipairs(items) do
        args["item" .. i] = {
            type  = "execute",
            order = order0 + i,
            name  = item,
            desc  = "Remove this grounding item.",
            width = "full",
            func  = function()
                ns.Grounding.RemoveItem(item)
                notify()
            end,
        }
    end
    return args
end

-- ===== Ready order: swap-on-change keeps a valid permutation =====

local function readyOrder()
    local cfg = ns.Ready and ns.Ready.GetConfig()
    local o = cfg and cfg.order
    if type(o) == "table" and #o == 3 then
        return { o[1], o[2], o[3] }
    end
    return { "grounding", "breathing", "lift" }
end

local function readyInclude(step)
    local cfg = ns.Ready and ns.Ready.GetConfig()
    local inc = cfg and cfg.include
    if inc and inc[step] ~= nil then return inc[step] end
    return true
end

-- Setting position `pos` to step `v` swaps `v` with whatever currently occupies
-- pos, so the three selects always form a permutation (no duplicate-rejection
-- dead-ends from three independent dropdowns).
local function setReadyPosition(pos, v)
    local order = readyOrder()
    if order[pos] == v then return end
    local other
    for j = 1, 3 do if order[j] == v then other = j end end
    if not other then return end
    order[pos], order[other] = v, order[pos]
    if ns.Ready then ns.Ready.SetOrder(order) end
    notify()
end

-- ===== Channel set with whisper privacy parity =====

local WHISPER_NOTE = "Whisper filtering enabled. Note: this reads private messages"
    .. " sent to you. Filtered output is shown only to you. Disable with"
    .. " /tox channel whisper off."

local function setChannel(name, on)
    local g = db(); if not g then return end
    g.channels[name] = on
    if name == "whisper" and on and ns.Database
        and ns.Database:NoteWhisperIntroIfNeeded() then
        print("[ToxFilter] " .. WHISPER_NOTE)
    end
end

-- ===== Status description (General tab) =====

local function statusText()
    local g = db()
    if not g then return "Settings not loaded." end
    local paused = ns.ToxFilterState and ns.ToxFilterState.isPaused()
    local parts = { "Master: " .. (g.enabled and "on" or "off") }
    if paused then parts[#parts + 1] = "paused (combat window)" end
    if ns.Database and ns.Database:AllCategoriesPass() then
        parts[#parts + 1] = "every category set to pass (filtering effectively off)"
    end
    parts[#parts + 1] = "Run /tox state for the full text readout."
    return table.concat(parts, "  ")
end

-- ===== Options table builder =====

local function buildOptions()
    local g = db() or {}

    -- ----- Handling dropdowns -----
    local handlingArgs = {
        header = { type = "description", order = 0,
                   name = "Per-category handling. 'default' clears the override."
                       .. " Silent drop hides messages without indication.", fontSize = "medium" },
    }
    for i, cat in ipairs(CATEGORY_ORDER) do
        handlingArgs[cat] = {
            type    = "select",
            order   = i,
            name    = cat,
            values  = HANDLING_VALUES,
            sorting = HANDLING_SORTING,
            get     = function()
                local gg = db(); if not gg then return "default" end
                return gg.handling[cat] or "default"
            end,
            set     = function(_, v)
                local gg = db(); if not gg then return end
                if v == "default" then gg.handling[cat] = nil else gg.handling[cat] = v end
            end,
        }
    end

    -- ----- Blacklist / whitelist groups -----
    local function listGroup(listName, label, order)
        local args = {
            add = {
                type  = "input",
                order = 1,
                name  = "Add word",
                desc  = "Add a word to the " .. listName .. ". Normalized on entry.",
                get   = function() return "" end,
                set   = function(_, val) ns.UserRules.add(listName, val); notify() end,
            },
            listheader = {
                type  = "description",
                order = 10,
                name  = function()
                    local n = ns.UserRules and ns.UserRules.count(listName) or 0
                    if n == 0 then return label .. " is empty." end
                    return label .. " (" .. n .. ") — click an entry to remove it:"
                end,
            },
        }
        local entries = userRuleEntries(listName, 10)
        for k, v in pairs(entries) do args[k] = v end
        return {
            type     = "group",
            order    = order,
            name     = label,
            inline   = true,
            disabled = toxfilterDisabled,
            args     = args,
        }
    end

    -- ----- Ready chain (include toggles + order selects) -----
    local readyArgs = {
        inchdr = { type = "description", order = 0,
                   name = "Steps included in /tox ready, in order.", fontSize = "medium" },
    }
    for i, step in ipairs(READY_STEPS) do
        readyArgs["inc_" .. step] = {
            type  = "toggle",
            order = i,
            name  = "Include " .. step,
            get   = function() return readyInclude(step) end,
            set   = function(_, val) if ns.Ready then ns.Ready.SetInclude(step, val) end end,
        }
    end
    readyArgs.orderhdr = { type = "description", order = 20,
        name = "Order (changing a position swaps it with the step it displaces).",
        fontSize = "medium" }
    for pos = 1, 3 do
        readyArgs["pos" .. pos] = {
            type    = "select",
            order   = 20 + pos,
            name    = "Position " .. pos,
            values  = STEP_VALUES,
            sorting = STEP_SORTING,
            get     = function() return readyOrder()[pos] end,
            set     = function(_, v) setReadyPosition(pos, v) end,
        }
    end

    -- ----- Grounding items (NOT category-gated) -----
    local groundingArgs = {
        note = { type = "description", order = 0,
                 name = "Grounding items for /tox check. This list is not gated by"
                     .. " the Uplifter toggle; it stays active regardless.", fontSize = "medium" },
        add = {
            type  = "input",
            order = 1,
            name  = "Add item",
            get   = function() return "" end,
            set   = function(_, val) if ns.Grounding then ns.Grounding.AddItem(val) end; notify() end,
        },
        listheader = {
            type  = "description",
            order = 10,
            name  = function()
                local n = ns.Grounding and #ns.Grounding.ListItems() or 0
                if n == 0 then return "No grounding items configured." end
                return "Grounding items (" .. n .. ") — click an item to remove it:"
            end,
        },
    }
    for k, v in pairs(groundingEntries(10)) do groundingArgs[k] = v end

    return {
        type        = "group",
        name        = "ToxFilter",
        childGroups = "tab",
        args = {
            -- ===== General =====
            general = {
                type = "group", order = 1, name = "General",
                args = {
                    master = {
                        type  = "toggle",
                        order = 1,
                        name  = "Enable ToxFilter",
                        desc  = "Addon-wide master. Off is a true kill switch (same as /tox off).",
                        get   = function() local gg = db(); return gg and gg.enabled end,
                        set   = function(_, val) local gg = db(); if gg then gg.enabled = val end; notify() end,
                    },
                    status = {
                        type = "description", order = 2, name = function() return statusText() end,
                        fontSize = "medium",
                    },
                },
            },

            -- ===== Categories =====
            categories = {
                type = "group", order = 2, name = "Categories",
                args = {
                    hdr = { type = "description", order = 0,
                        name = "Category masters sit above the per-feature toggles."
                            .. " Turning one off greys its tab but preserves the"
                            .. " per-feature values for when it is turned back on.",
                        fontSize = "medium" },
                    toxfilter = {
                        type = "toggle", order = 1, name = "ToxFilter (chat hygiene)",
                        desc = "Rule-engine handling, blacklist/whitelist, surgical rewrite, test fixtures.",
                        get  = function() return ns.Category and ns.Category.isEnabled("toxfilter") end,
                        set  = function(_, val)
                            local gg = db(); if gg then gg.category_toxfilter_enabled = val end; notify()
                        end,
                    },
                    uplifter = {
                        type = "toggle", order = 2, name = "Uplifter (confidence)",
                        desc = "Positive capture, highlight, callouts, reminders, warnings, stats surfacing.",
                        get  = function() return ns.Category and ns.Category.isEnabled("uplifter") end,
                        set  = function(_, val)
                            local gg = db(); if gg then gg.category_uplifter_enabled = val end; notify()
                        end,
                    },
                },
            },

            -- ===== ToxFilter family (greyed when category off) =====
            toxfilter = {
                type = "group", order = 3, name = "ToxFilter",
                args = {
                    channels = {
                        type = "group", order = 1, name = "Channels", inline = true,
                        disabled = toxfilterDisabled,
                        args = {
                            raid = { type = "toggle", order = 1, name = "Raid",
                                get = function() return g.channels and g.channels.raid end,
                                set = function(_, v) setChannel("raid", v) end },
                            instance = { type = "toggle", order = 2, name = "Instance (also: party)",
                                get = function() return g.channels and g.channels.instance end,
                                set = function(_, v) setChannel("instance", v) end },
                            battleground = { type = "toggle", order = 3, name = "Battleground",
                                get = function() return g.channels and g.channels.battleground end,
                                set = function(_, v) setChannel("battleground", v) end },
                            whisper = { type = "toggle", order = 4, name = "Whisper",
                                desc = "Off by default. Reads private 1:1 messages; output shown only to you.",
                                get = function() return g.channels and g.channels.whisper end,
                                set = function(_, v) setChannel("whisper", v) end },
                        },
                    },
                    handling = {
                        type = "group", order = 2, name = "Handling", inline = true,
                        disabled = toxfilterDisabled,
                        args = handlingArgs,
                    },
                    blacklist = listGroup("blacklist", "Blacklist", 3),
                    whitelist = listGroup("whitelist", "Whitelist", 4),
                },
            },

            -- ===== Uplifter family (greyed when category off; grounding excepted) =====
            uplifter = {
                type = "group", order = 4, name = "Uplifter",
                args = {
                    positive = {
                        type = "toggle", order = 1, name = "Positive-moment highlight",
                        disabled = uplifterDisabled,
                        get = function() return g.positive_ui end,
                        set = function(_, v) local gg = db(); if gg then gg.positive_ui = v end end,
                    },
                    callout = {
                        type = "group", order = 2, name = "Callout", inline = true,
                        disabled = uplifterDisabled,
                        args = {
                            master = { type = "toggle", order = 1, name = "Enable callouts",
                                get = function() return g.callout_enabled end,
                                set = function(_, v) local gg = db(); if gg then gg.callout_enabled = v end end },
                            ui = { type = "toggle", order = 2, name = "Visual tint",
                                get = function() return g.callout_ui end,
                                set = function(_, v) local gg = db(); if gg then gg.callout_ui = v end end },
                            sound = { type = "toggle", order = 3, name = "Sound cue",
                                get = function() return g.callout_sound end,
                                set = function(_, v) local gg = db(); if gg then gg.callout_sound = v end end },
                        },
                    },
                    reminders = {
                        type = "toggle", order = 3, name = "Pre-encounter reminders",
                        disabled = uplifterDisabled,
                        get = function() return g.tactic_reminders_enabled end,
                        set = function(_, v) local gg = db(); if gg then gg.tactic_reminders_enabled = v end end,
                    },
                    warnings = {
                        type = "toggle", order = 4, name = "Pre-dungeon warnings",
                        disabled = uplifterDisabled,
                        get = function() return g.predungeon_warnings_enabled end,
                        set = function(_, v) local gg = db(); if gg then gg.predungeon_warnings_enabled = v end end,
                    },
                    stats = {
                        type = "group", order = 5, name = "Stats surfacing", inline = true,
                        disabled = uplifterDisabled,
                        args = {
                            surface = { type = "toggle", order = 1, name = "Surface live stats",
                                get = function() return g.stats_surface end,
                                set = function(_, v) local gg = db(); if gg then gg.stats_surface = v end end },
                            threshold = { type = "range", order = 2, name = "Wipe-rate threshold (%)",
                                min = 0, max = 100, step = 1,
                                get = function() return g.stats_threshold or 30 end,
                                set = function(_, v) setField("stats_threshold", math.floor(v)) end },
                        },
                    },
                    breathing = {
                        type = "group", order = 6, name = "Box breathing", inline = true,
                        disabled = uplifterDisabled,
                        args = {
                            cycles = { type = "range", order = 1, name = "Cycles",
                                min = 1, max = 20, step = 1,
                                get = function() return g.breathe_cycles or 4 end,
                                set = function(_, v) setField("breathe_cycles", math.floor(v)) end },
                            count = { type = "range", order = 2, name = "Seconds per phase",
                                min = 1, max = 20, step = 1,
                                get = function() return g.breathe_count or 4 end,
                                set = function(_, v) setField("breathe_count", math.floor(v)) end },
                        },
                    },
                    ready = {
                        type = "group", order = 7, name = "Ready chain", inline = true,
                        disabled = uplifterDisabled,
                        args = readyArgs,
                    },
                    grounding = {
                        type = "group", order = 8, name = "Grounding items", inline = true,
                        disabled = false,  -- explicitly ungated; overrides nothing but documents intent
                        args = groundingArgs,
                    },
                },
            },

            -- ===== Role (shared plumbing — never greyed) =====
            role = {
                type = "group", order = 5, name = "Role",
                args = {
                    role = {
                        type = "select", order = 1, name = "Role",
                        desc = "auto uses spec detection.",
                        values = ROLE_VALUES, sorting = ROLE_SORTING,
                        get = function() local gg = db(); return gg and gg.role or "auto" end,
                        set = function(_, v) local gg = db(); if gg then gg.role = v end end,
                    },
                    effective = {
                        type = "description", order = 2,
                        name = function()
                            local eff = ns.Database and ns.Database:GetEffectiveRole() or "unknown"
                            return "Effective role: " .. eff
                        end,
                    },
                },
            },
        },
    }
end

-- Registers the options table (as a function, for live dynamic content) and adds
-- it to the Blizzard AddOns options menu. Called from OnInitialize after the db
-- is ready.
function Options.Register()
    if not (AceConfig and AceConfigDialog) then
        print("[ToxFilter] Options panel unavailable: AceConfig libraries not loaded.")
        return
    end
    AceConfig:RegisterOptionsTable(APP, buildOptions)
    AceConfigDialog:AddToBlizOptions(APP, "ToxFilter")
end

function Options.Open()
    if AceConfigDialog then
        AceConfigDialog:Open(APP)
    else
        print("[ToxFilter] Options panel unavailable: AceConfig libraries not loaded.")
    end
end

ns.Options = Options
