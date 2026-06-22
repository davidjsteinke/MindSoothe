-- Sprint 7a N12 regression harness: drives the REAL chatFilter dispatch through
-- the combat-pause state. Stubs the WoW API, loads every live module INCLUDING
-- ToxFilter.lua, and calls chatFilter via the ns.ToxFilterDispatch test hook so
-- the paused path (callout-survives-pause) is exercised against production code
-- rather than Callout.detect in isolation. One source of truth for engine logic.
--
-- Usage: lua scripts/pause-dispatch.lua <addon_dir> <cases_file>

local addon_dir  = arg[1]
local cases_file = arg[2]

-- FNV-1a needs bxor; nothing else from bit.
_G.bit = { bxor = function(a, b)
    local r, bv = 0, 1
    for _ = 1, 32 do
        local x, y = a % 2, b % 2
        if x ~= y then r = r + bv end
        a = (a - x) / 2; b = (b - y) / 2; bv = bv * 2
    end
    return r
end }

-- Minimal WoW globals the live modules + MindSoothe.lua touch.
_G.ChatFrame_AddMessageEventFilter    = function() end
_G.ChatFrame_RemoveMessageEventFilter = function() end
_G.PlaySound        = function(...) _G.__lastSound = select(1, ...); return true end
_G.UnitName         = function() return "Tester" end
-- Sprint 8: MindSoothe.lua reads the single-sourced version via C_AddOns at load.
_G.C_AddOns         = { GetAddOnMetadata = function() return "0.8.0-sprint8" end }

-- LibStub / AceAddon stub: enough for the NewAddon call at MindSoothe.lua load.
local aceAddonObj = setmetatable({}, { __index = function() return function() end end })
_G.LibStub = function(name)
    if name == "AceAddon-3.0" then
        return { NewAddon = function() return aceAddonObj end }
    end
    return setmetatable({}, { __index = function() return function() end end })
end

local ns = {}
local function load_module(name)
    local chunk, err = loadfile(addon_dir .. "/" .. name)
    if not chunk then error("loadfile " .. name .. ": " .. tostring(err)) end
    chunk("ToxFilter", ns)
end

for _, m in ipairs({
    "Const.lua",
    "Hash.lua", "Normalize.lua", "Categories.lua", "Patterns.lua", "Fuzzy.lua",
    "RuleData.lua", "Classifier.lua", "Rewrite.lua", "RuleEngine.lua",
    "CombatDrop.lua", "Callout.lua", "PositiveCapture.lua", "Category.lua",
}) do load_module(m) end

-- Highlight + Buffer stubs: chatFilter references both. Highlight returns nil so
-- the passive tint never fires (it must stay paused in combat — asserting it is
-- a no-op keeps the callout-vs-passive distinction honest).
ns.Highlight = { tintIfEligible = function() return nil end, OnPositiveMoment = function() end }
ns.Buffer    = { RecordFlaggedEvent = function() end, RecordPositiveMoment = function() return nil end }

local stubbedRole = "tank"
local stubDB = {
    enabled = true, debug_enabled = false,
    callout_enabled = true, callout_ui = true, callout_sound = true,
    category_toxfilter_enabled = true, category_uplifter_enabled = true,
    combat_silent_drop = true, callout_sound_id = 8959,
    channels = { instance = true, raid = true, battleground = true, whisper = false },
}
ns.Database = {
    Get               = function() return stubDB end,
    GetEffectiveRole  = function() return stubbedRole end,
    ResolveHandling   = function() return nil end,
}

load_module("MindSoothe.lua")

local D = ns.ToxFilterDispatch
assert(D and D.chatFilter and D.setPausedForTest, "ToxFilterDispatch test hook missing")

local loaded = dofile(cases_file)
local cases = loaded.cases

local AMBER = "|cFFEEBB55"
local function outcomeOf(r1, r2)
    if r1 == true then return "drop" end
    if r1 == false and type(r2) == "string" and r2:find(AMBER, 1, true) then return "tint" end
    return "pass"
end

local total, pass, fails = 0, 0, {}
for _, c in ipairs(cases) do
    total = total + 1
    stubbedRole                       = c.role
    stubDB.callout_enabled            = c.callout
    stubDB.category_uplifter_enabled  = c.up
    stubDB.category_toxfilter_enabled = true
    stubDB.enabled                    = c.master
    stubDB.combat_silent_drop         = c.toggle
    D.setPausedForTest(c.paused)

    local r1, r2 = D.chatFilter(nil, "CHAT_MSG_INSTANCE_CHAT", c.msg, "Mate-Realm")
    local got = outcomeOf(r1, r2)
    if got == c.expect then
        pass = pass + 1
    else
        fails[#fails + 1] = string.format(
            "  FAIL %s: msg=%q paused=%s -> got=%s want=%s (r1=%s r2=%s)",
            c.id, c.msg, tostring(c.paused), got, c.expect, tostring(r1), tostring(r2))
    end
end

-- (Sprint 7a N12, final): there is no in-combat callout path to drive. Midnight
-- delivers in-combat chat text as a secret/tainted value, so no addon can inspect
-- chat during a boss fight; the OnCombatChat / RaidWarningFrame surface and its
-- fixtures were removed. The chatFilter paused-branch cases above remain the
-- valid paused-dispatch guard.

print()
print("=== ToxFilter Sprint 7a pause dispatch (N12) ===")
print(string.format("Checks:    %d", total))
print(string.format("Pass:      %d / %d (%.1f%%)", pass, total, total > 0 and 100.0 * pass / total or 0.0))
if #fails > 0 then
    print()
    print("Failures:")
    for _, l in ipairs(fails) do print(l) end
end
