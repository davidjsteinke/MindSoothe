#!/usr/bin/env bash
# Run the corpus against the addon's rule engine + classifier + rewrite + callout.
# Pure-Lua harness: loads the addon's actual modules with a minimal WoW-API stub.
# One source of truth for engine logic; no Python re-implementation. Python is
# used only to convert corpus JSON to Lua tables.
#
# Sprint 2 pass: per-category catch + pass-through FP + rewrite exact-match.
# Sprint 5 pass: callout detection precision/recall + role-match correctness.
# No threshold enforcement until Sprint 7.
#
# Usage: ./scripts/run-corpus.sh

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADDON_DIR="$PROJECT_ROOT/addon"
CORPUS_FILE="$PROJECT_ROOT/corpus/sprint2.json"
CALLOUT_CORPUS_FILE="$PROJECT_ROOT/corpus/sprint5.json"
REMINDERS_CORPUS_FILE="$PROJECT_ROOT/corpus/sprint5b_gating.lua"
WARNINGS_CORPUS_FILE="$PROJECT_ROOT/corpus/sprint5c_gating.lua"
CATEGORY_CORPUS_FILE="$PROJECT_ROOT/corpus/sprint5d_gating.lua"

if ! command -v lua >/dev/null 2>&1; then
    echo "Error: 'lua' interpreter not found. Install via: sudo apt-get install lua5.1" >&2
    exit 1
fi

if [[ ! -f "$CORPUS_FILE" ]]; then
    echo "Error: $CORPUS_FILE not found." >&2
    exit 1
fi

CORPUS_LUA=$(mktemp --suffix=.lua)
CALLOUT_CORPUS_LUA=$(mktemp --suffix=.lua)
HARNESS_LUA=$(mktemp --suffix=.lua)
trap "rm -f '$CORPUS_LUA' '$CALLOUT_CORPUS_LUA' '$HARNESS_LUA'" EXIT

# Sprint 5b gating tests are pure Lua, no Python conversion needed. The path is
# passed directly to the harness; an empty/missing file is acceptable.
if [[ ! -f "$REMINDERS_CORPUS_FILE" ]]; then
    REMINDERS_CORPUS_FILE=""
fi

# Sprint 5c gating tests are pure Lua too. Missing file is acceptable.
if [[ ! -f "$WARNINGS_CORPUS_FILE" ]]; then
    WARNINGS_CORPUS_FILE=""
fi

# Sprint 5d category-gate tests are pure Lua too. Missing file is acceptable.
if [[ ! -f "$CATEGORY_CORPUS_FILE" ]]; then
    CATEGORY_CORPUS_FILE=""
fi

python3 - "$CORPUS_FILE" "$CORPUS_LUA" <<'PY'
import json, sys
src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    data = json.load(f)

def lua_str(s):
    if s is None:
        return "nil"
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"').replace("\n", "\\n") + '"'

with open(dst, "w") as f:
    f.write("return {\n")
    f.write("    entries = {\n")
    for e in data["entries"]:
        f.write("        {\n")
        f.write(f'            id = {lua_str(e["id"])},\n')
        f.write(f'            input = {lua_str(e["input"])},\n')
        f.write(f'            expected_handling = {lua_str(e["expected_handling"])},\n')
        f.write(f'            expected_category = {lua_str(e.get("expected_category"))},\n')
        f.write(f'            expected_rewrite = {lua_str(e.get("expected_rewrite"))},\n')
        f.write("        },\n")
    f.write("    },\n")
    f.write("}\n")
PY

if [[ -f "$CALLOUT_CORPUS_FILE" ]]; then
python3 - "$CALLOUT_CORPUS_FILE" "$CALLOUT_CORPUS_LUA" <<'PY'
import json, sys
src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    data = json.load(f)

def lua_str(s):
    if s is None:
        return "nil"
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"').replace("\n", "\\n") + '"'

def lua_list(items):
    if not items:
        return "{}"
    return "{ " + ", ".join(lua_str(x) for x in items) + " }"

with open(dst, "w") as f:
    f.write("return {\n")
    f.write("    entries = {\n")
    for e in data["entries"]:
        f.write("        {\n")
        f.write(f'            id = {lua_str(e["id"])},\n')
        f.write(f'            input = {lua_str(e["input"])},\n')
        f.write(f'            expected_roles = {lua_list(e.get("expected_roles") or [])},\n')
        user_role = e.get("user_role_for_test")
        f.write(f'            user_role_for_test = {lua_str(user_role)},\n')
        em = e.get("expected_match")
        if em is None:
            f.write('            expected_match = nil,\n')
        else:
            f.write(f'            expected_match = {"true" if em else "false"},\n')
        f.write("        },\n")
    f.write("    },\n")
    f.write("}\n")
PY
else
    echo "return { entries = {} }" > "$CALLOUT_CORPUS_LUA"
fi

cat > "$HARNESS_LUA" <<'LUA'
-- ToxFilter corpus harness.
-- Loads addon modules with a minimal WoW-API stub and runs Sprint 2 + Sprint 5
-- passes. Single source of truth for engine logic; Python only converts JSON
-- to Lua tables.

local addon_dir            = arg[1]
local corpus_file          = arg[2]
local callout_corpus_file  = arg[3]
local reminders_corpus_file = arg[4]
local warnings_corpus_file  = arg[5]
local category_corpus_file  = arg[6]

-- WoW-API stub: bit library (only bxor needed for FNV-1a), nothing else.
_G.bit = {
    bxor = function(a, b)
        local result = 0
        local bitval = 1
        for _ = 1, 32 do
            local abit = a % 2
            local bbit = b % 2
            if abit ~= bbit then result = result + bitval end
            a = (a - abit) / 2
            b = (b - bbit) / 2
            bitval = bitval * 2
        end
        return result
    end,
}

local ns = {}

local function load_module(name)
    local path = addon_dir .. "/" .. name
    local chunk, err = loadfile(path)
    if not chunk then error("loadfile failed for " .. path .. ": " .. tostring(err)) end
    chunk("ToxFilter", ns)
end

-- TOC order minus Libs/ and ToxFilter.lua (lifecycle / AceAddon, not needed here).
load_module("Hash.lua")
load_module("Normalize.lua")
load_module("Categories.lua")
load_module("Patterns.lua")
load_module("RuleData.lua")
load_module("Classifier.lua")
load_module("Rewrite.lua")
load_module("RuleEngine.lua")
load_module("Callout.lua")
load_module("JournalData.lua")
load_module("TacticReminders.lua")
load_module("PreDungeonData.lua")
load_module("PreDungeon.lua")
load_module("Category.lua")

-- Database stub: a mutable singleton table so TacticReminders' writes to
-- tactic_reminders_seen are observable across calls. Fields are seeded with
-- the same defaults DEFAULTS would supply for a fresh install at v7.
local stubbedRole = nil
local stubDB = {
    callout_enabled = true,
    callout_ui      = true,
    callout_sound   = true,
    tactic_reminders_enabled = false,
    tactic_reminders_seen    = {},
    predungeon_warnings_enabled = false,
    predungeon_warnings_seen    = {},
    enabled                     = true,
    category_toxfilter_enabled  = true,
    category_uplifter_enabled   = true,
    debug_enabled = false,
}
ns.Database = {
    Get = function() return stubDB end,
    GetEffectiveRole = function() return stubbedRole end,
}

local corpus = dofile(corpus_file)

local stats_by_category = {}  -- expected category -> {expected, caught, category_correct}
local pass_through = { expected = 0, false_positive = 0 }
local rewrite_stats = { expected = 0, exact = 0, mismatches = {} }

local total = #corpus.entries
for _, entry in ipairs(corpus.entries) do
    local result = ns.RuleEngine.classify(entry.input)
    local actual_handling = result.handling
    local actual_category = result.category

    local actual_rewrite
    if actual_handling == "edit" then
        actual_rewrite = ns.Rewrite.rewrite(entry.input, result)
    elseif actual_handling == "del" then
        actual_rewrite = ns.RuleEngine.buildDeleteLabel(result)
    elseif actual_handling == "silent" then
        actual_rewrite = "(silent)"
    else
        actual_rewrite = nil
    end

    if entry.expected_handling == "pass" then
        pass_through.expected = pass_through.expected + 1
        if actual_handling ~= "pass" then
            pass_through.false_positive = pass_through.false_positive + 1
            print(string.format("  FP %s: '%s' → handling=%s, category=%s",
                  entry.id, entry.input, actual_handling, tostring(actual_category)))
        end
    else
        local cat = entry.expected_category or "unknown"
        local s = stats_by_category[cat] or { expected = 0, caught = 0, category_correct = 0 }
        s.expected = s.expected + 1
        if actual_handling ~= "pass" then
            s.caught = s.caught + 1
            if actual_category == entry.expected_category then
                s.category_correct = s.category_correct + 1
            end
        else
            print(string.format("  MISS %s: '%s' expected %s/%s, got pass",
                  entry.id, entry.input, entry.expected_handling, cat))
        end
        stats_by_category[cat] = s
    end

    if entry.expected_rewrite then
        rewrite_stats.expected = rewrite_stats.expected + 1
        if actual_rewrite == entry.expected_rewrite then
            rewrite_stats.exact = rewrite_stats.exact + 1
        else
            rewrite_stats.mismatches[#rewrite_stats.mismatches + 1] = string.format(
                "  REWRITE %s: '%s'\n           expected: '%s'\n           actual:   '%s'",
                entry.id, entry.input, entry.expected_rewrite, tostring(actual_rewrite))
        end
    end
end

if #rewrite_stats.mismatches > 0 then
    print()
    print("Rewrite mismatches:")
    for _, line in ipairs(rewrite_stats.mismatches) do print(line) end
end

print()
print("=== ToxFilter Sprint 2 corpus ===")
print(string.format("Entries: %d", total))
print()
print(string.format("  %-22s %8s %8s %8s %12s",
      "category", "n", "caught", "catch%", "category-ok"))
local cats = {}
for k in pairs(stats_by_category) do cats[#cats + 1] = k end
table.sort(cats)
for _, cat in ipairs(cats) do
    local s = stats_by_category[cat]
    local pct = (s.expected > 0) and (100.0 * s.caught / s.expected) or 0.0
    print(string.format("  %-22s %8d %8d %7.1f%% %12d",
          cat, s.expected, s.caught, pct, s.category_correct))
end
print()
local fp_pct = (pass_through.expected > 0)
    and (100.0 * pass_through.false_positive / pass_through.expected) or 0.0
print(string.format("Pass-through:  %d / %d expected; false positives: %d (%.1f%%)",
      pass_through.expected - pass_through.false_positive,
      pass_through.expected, pass_through.false_positive, fp_pct))

local rw_pct = (rewrite_stats.expected > 0)
    and (100.0 * rewrite_stats.exact / rewrite_stats.expected) or 0.0
print(string.format("Rewrite:       %d / %d exact match (%.1f%%)",
      rewrite_stats.exact, rewrite_stats.expected, rw_pct))
print()
print("Note: Sprint 2 has no threshold gate. Build 1 Sprint 7 introduces enforcement.")

-- ===== Sprint 5 pass: Callout.detect + Callout.matchesUser =====

local cc_ok, cc = pcall(dofile, callout_corpus_file)
if not cc_ok or not cc or not cc.entries or #cc.entries == 0 then
    print()
    print("=== Sprint 5 callout corpus: none found, skipping ===")
    return
end

local function rolesetEq(actual, expected)
    if #actual ~= #expected then return false end
    local seen = {}
    for i = 1, #actual do seen[actual[i]] = true end
    for i = 1, #expected do
        if not seen[expected[i]] then return false end
    end
    return true
end

local function rolesList(roles)
    if not roles or #roles == 0 then return "{}" end
    return "{" .. table.concat(roles, ",") .. "}"
end

local cl_stats = {
    detect_total = 0, detect_correct = 0,
    pos_total = 0, pos_caught = 0,             -- expected_roles non-empty
    neg_total = 0, neg_rejected = 0,           -- expected_roles empty
    match_total = 0, match_correct = 0,
    detect_mismatches = {},
    match_mismatches = {},
}

for _, entry in ipairs(cc.entries) do
    -- Re-run classifier so we have signals/labels for the detect gate.
    local result = ns.RuleEngine.classify(entry.input)
    local detection = ns.Callout.detect(entry.input, result)
    local actual_roles = detection and detection.roles or {}

    cl_stats.detect_total = cl_stats.detect_total + 1
    if #entry.expected_roles == 0 then
        cl_stats.neg_total = cl_stats.neg_total + 1
        if #actual_roles == 0 then
            cl_stats.neg_rejected = cl_stats.neg_rejected + 1
            cl_stats.detect_correct = cl_stats.detect_correct + 1
        else
            cl_stats.detect_mismatches[#cl_stats.detect_mismatches + 1] = string.format(
                "  FP  %s: '%s' expected no roles, got %s",
                entry.id, entry.input, rolesList(actual_roles))
        end
    else
        cl_stats.pos_total = cl_stats.pos_total + 1
        if rolesetEq(actual_roles, entry.expected_roles) then
            cl_stats.pos_caught = cl_stats.pos_caught + 1
            cl_stats.detect_correct = cl_stats.detect_correct + 1
        else
            cl_stats.detect_mismatches[#cl_stats.detect_mismatches + 1] = string.format(
                "  MISS %s: '%s' expected %s, got %s",
                entry.id, entry.input, rolesList(entry.expected_roles), rolesList(actual_roles))
        end
    end

    if entry.expected_match ~= nil then
        cl_stats.match_total = cl_stats.match_total + 1
        stubbedRole = entry.user_role_for_test
        local matched
        if detection then
            matched = ns.Callout.matchesUser(detection)
        else
            matched = false
        end
        if (matched and true or false) == entry.expected_match then
            cl_stats.match_correct = cl_stats.match_correct + 1
        else
            cl_stats.match_mismatches[#cl_stats.match_mismatches + 1] = string.format(
                "  MATCH %s: role=%s detection=%s expected_match=%s actual=%s",
                entry.id,
                tostring(entry.user_role_for_test),
                rolesList(actual_roles),
                tostring(entry.expected_match),
                tostring(matched and true or false))
        end
    end
end
stubbedRole = nil

if #cl_stats.detect_mismatches > 0 then
    print()
    print("Detection mismatches:")
    for _, l in ipairs(cl_stats.detect_mismatches) do print(l) end
end
if #cl_stats.match_mismatches > 0 then
    print()
    print("Match mismatches:")
    for _, l in ipairs(cl_stats.match_mismatches) do print(l) end
end

print()
print("=== ToxFilter Sprint 5 callout corpus ===")
print(string.format("Entries: %d  (positives %d, negatives %d, match cases %d)",
    cl_stats.detect_total, cl_stats.pos_total, cl_stats.neg_total, cl_stats.match_total))
local det_pct = (cl_stats.detect_total > 0)
    and (100.0 * cl_stats.detect_correct / cl_stats.detect_total) or 0.0
print(string.format("Detection overall: %d / %d correct (%.1f%%)",
    cl_stats.detect_correct, cl_stats.detect_total, det_pct))
local pos_pct = (cl_stats.pos_total > 0)
    and (100.0 * cl_stats.pos_caught / cl_stats.pos_total) or 0.0
print(string.format("Positive recall:   %d / %d (%.1f%%)",
    cl_stats.pos_caught, cl_stats.pos_total, pos_pct))
local neg_pct = (cl_stats.neg_total > 0)
    and (100.0 * cl_stats.neg_rejected / cl_stats.neg_total) or 0.0
print(string.format("Negative reject:   %d / %d (%.1f%%)",
    cl_stats.neg_rejected, cl_stats.neg_total, neg_pct))
local mat_pct = (cl_stats.match_total > 0)
    and (100.0 * cl_stats.match_correct / cl_stats.match_total) or 0.0
print(string.format("Role-match:        %d / %d (%.1f%%)",
    cl_stats.match_correct, cl_stats.match_total, mat_pct))

-- ===== Sprint 5b pass: TacticReminders gating + Lookup =====

if not reminders_corpus_file or reminders_corpus_file == "" then
    print()
    print("=== Sprint 5b reminders corpus: none found, skipping ===")
    return
end

local rok, rcorpus = pcall(dofile, reminders_corpus_file)
if not rok or not rcorpus or not rcorpus.scenarios then
    print()
    print("=== Sprint 5b reminders corpus: failed to load, skipping ===")
    return
end

-- Seed JournalData with fixture instances. Production JournalData ships with
-- an empty instances table at scaffold time; tests own their fixture.
ns.JournalData.instances = rcorpus.fixtures.instances

-- Capture print emissions during a Surface call. We patch _G.print to push
-- lines into a buffer, then restore.
local original_print = print
local capture_buffer = nil
local function startCapture()
    capture_buffer = {}
    _G.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
        capture_buffer[#capture_buffer + 1] = table.concat(parts, "\t")
    end
end
local function stopCapture()
    _G.print = original_print
    local out = capture_buffer
    capture_buffer = nil
    return out or {}
end

local function countBulletLines(lines)
    local n = 0
    for i = 1, #lines do
        if lines[i]:find("^%[ToxFilter%]%s+%- ") then n = n + 1 end
    end
    return n
end

local function hasHeaderLine(lines)
    for i = 1, #lines do
        -- Header line example:
        --   [ToxFilter] First Boss (heroic) — Tank reminders:
        if lines[i]:find("reminders:$") then return true end
    end
    return false
end

local function applySetup(setup)
    if setup.master ~= nil then stubDB.tactic_reminders_enabled = setup.master end
    stubbedRole = setup.role
    if setup.reset_seen then ns.TacticReminders.ResetSession() end
    if setup.pre_calls then
        startCapture()
        for _, pc in ipairs(setup.pre_calls) do
            ns.TacticReminders.Surface(pc.instance, pc.encounter, pc.bucket)
        end
        stopCapture()
    end
end

local rs_total, rs_pass, rs_fail = 0, 0, 0
local rs_failures = {}

for _, sc in ipairs(rcorpus.scenarios) do
    rs_total = rs_total + 1
    applySetup(sc.setup)

    startCapture()
    ns.TacticReminders.Surface(sc.call.instance, sc.call.encounter, sc.call.bucket)
    local lines = stopCapture()

    local emitted_header = hasHeaderLine(lines)
    local mechanic_count = countBulletLines(lines)
    local emitted = emitted_header or mechanic_count > 0

    -- Seen-map state for this triple after the call.
    local seen_key = tostring(sc.call.instance) .. "|"
        .. tostring(sc.call.encounter) .. "|"
        .. tostring(sc.call.bucket)
    local seen = stubDB.tactic_reminders_seen[seen_key] == true

    local ok = true
    local reasons = {}
    if sc.expect.emitted ~= nil and emitted ~= sc.expect.emitted then
        ok = false
        reasons[#reasons + 1] = string.format("emitted=%s expected=%s",
            tostring(emitted), tostring(sc.expect.emitted))
    end
    if sc.expect.seen ~= nil and seen ~= sc.expect.seen then
        ok = false
        reasons[#reasons + 1] = string.format("seen=%s expected=%s",
            tostring(seen), tostring(sc.expect.seen))
    end
    if sc.expect.mechanic_count ~= nil and mechanic_count ~= sc.expect.mechanic_count then
        ok = false
        reasons[#reasons + 1] = string.format("mechanic_count=%d expected=%d",
            mechanic_count, sc.expect.mechanic_count)
    end

    if ok then
        rs_pass = rs_pass + 1
    else
        rs_fail = rs_fail + 1
        rs_failures[#rs_failures + 1] = string.format("  FAIL %s: %s",
            sc.id, table.concat(reasons, "; "))
    end
end

print()
print("=== ToxFilter Sprint 5b reminders gating ===")
print(string.format("Scenarios: %d", rs_total))
local rs_pct = (rs_total > 0) and (100.0 * rs_pass / rs_total) or 0.0
print(string.format("Pass:      %d / %d (%.1f%%)", rs_pass, rs_total, rs_pct))
if rs_fail > 0 then
    print()
    print("Failures:")
    for _, l in ipairs(rs_failures) do print(l) end
end

-- ===== Sprint 5c pass: PreDungeon gating + Lookup =====
-- Reuses the capture helpers (startCapture/stopCapture/countBulletLines)
-- defined in the Sprint 5b pass above; they live in the same chunk scope.

if not warnings_corpus_file or warnings_corpus_file == "" then
    print()
    print("=== Sprint 5c warnings corpus: none found, skipping ===")
    return
end

local wok, wcorpus = pcall(dofile, warnings_corpus_file)
if not wok or not wcorpus or not wcorpus.scenarios then
    print()
    print("=== Sprint 5c warnings corpus: failed to load, skipping ===")
    return
end

-- Seed PreDungeonData with fixture instances. Production PreDungeonData ships
-- with an empty instances table at scaffold time; tests own their fixture.
ns.PreDungeonData.instances = wcorpus.fixtures.instances

-- PreDungeon header line example:
--   [ToxFilter] KeyDungeon A — pre-key reminders (DPS):
local function hasWarningHeader(lines)
    for i = 1, #lines do
        if lines[i]:find("pre%-key reminders") then return true end
    end
    return false
end

local function applyWarningSetup(setup)
    if setup.master ~= nil then stubDB.predungeon_warnings_enabled = setup.master end
    stubbedRole = setup.role
    if setup.reset_seen then ns.PreDungeon.ResetSession() end
    if setup.pre_calls then
        startCapture()
        for _, pc in ipairs(setup.pre_calls) do
            ns.PreDungeon.Surface(pc.instance)
        end
        stopCapture()
    end
end

local ws_total, ws_pass, ws_fail = 0, 0, 0
local ws_failures = {}

for _, sc in ipairs(wcorpus.scenarios) do
    ws_total = ws_total + 1
    applyWarningSetup(sc.setup)

    startCapture()
    ns.PreDungeon.Surface(sc.call.instance)
    local lines = stopCapture()

    local emitted_header = hasWarningHeader(lines)
    local bullet_count = countBulletLines(lines)
    local emitted = emitted_header or bullet_count > 0

    -- Seen-map state for this instance after the call (per-instance key).
    local seen = stubDB.predungeon_warnings_seen[sc.call.instance] == true

    local ok = true
    local reasons = {}
    if sc.expect.emitted ~= nil and emitted ~= sc.expect.emitted then
        ok = false
        reasons[#reasons + 1] = string.format("emitted=%s expected=%s",
            tostring(emitted), tostring(sc.expect.emitted))
    end
    if sc.expect.seen ~= nil and seen ~= sc.expect.seen then
        ok = false
        reasons[#reasons + 1] = string.format("seen=%s expected=%s",
            tostring(seen), tostring(sc.expect.seen))
    end
    if sc.expect.bullet_count ~= nil and bullet_count ~= sc.expect.bullet_count then
        ok = false
        reasons[#reasons + 1] = string.format("bullet_count=%d expected=%d",
            bullet_count, sc.expect.bullet_count)
    end

    if ok then
        ws_pass = ws_pass + 1
    else
        ws_fail = ws_fail + 1
        ws_failures[#ws_failures + 1] = string.format("  FAIL %s: %s",
            sc.id, table.concat(reasons, "; "))
    end
end

print()
print("=== ToxFilter Sprint 5c warnings gating ===")
print(string.format("Scenarios: %d", ws_total))
local ws_pct = (ws_total > 0) and (100.0 * ws_pass / ws_total) or 0.0
print(string.format("Pass:      %d / %d (%.1f%%)", ws_pass, ws_total, ws_pct))
if ws_fail > 0 then
    print()
    print("Failures:")
    for _, l in ipairs(ws_failures) do print(l) end
end

-- ===== Sprint 5d pass: category gate + Uplifter suppression =====
-- Reuses startCapture/stopCapture from the Sprint 5b pass (same chunk scope).
if not category_corpus_file or category_corpus_file == "" then
    print()
    print("=== Sprint 5d category corpus: none found, skipping ===")
else
local cdok, ccorpus = pcall(dofile, category_corpus_file)
if not cdok or not ccorpus then
    print()
    print("=== Sprint 5d category corpus: failed to load, skipping ===")
else

local cs_total, cs_pass, cs_fail = 0, 0, 0
local cs_failures = {}
local function expectBool(id, what, got, want)
    cs_total = cs_total + 1
    if got == want then
        cs_pass = cs_pass + 1
    else
        cs_fail = cs_fail + 1
        cs_failures[#cs_failures + 1] = string.format("  FAIL %s/%s: got=%s want=%s",
            id, what, tostring(got), tostring(want))
    end
end

-- gate() truth table: master × toxfilter × uplifter.
for _, c in ipairs(ccorpus.gate_cases or {}) do
    stubDB.enabled = c.master
    stubDB.category_toxfilter_enabled = c.tf
    stubDB.category_uplifter_enabled  = c.up
    expectBool(c.id, "gate.toxfilter", ns.Category.gate("toxfilter"), c.exp_tf)
    expectBool(c.id, "gate.uplifter",  ns.Category.gate("uplifter"),  c.exp_up)
end

-- isEnabled() reports the category bit only, independent of the master.
for _, c in ipairs(ccorpus.isenabled_cases or {}) do
    stubDB.enabled = false
    stubDB.category_toxfilter_enabled = c.tf
    stubDB.category_uplifter_enabled  = c.up
    expectBool(c.id, "isEnabled.toxfilter", ns.Category.isEnabled("toxfilter"), c.exp_tf)
    expectBool(c.id, "isEnabled.uplifter",  ns.Category.isEnabled("uplifter"),  c.exp_up)
end

-- Unknown category name is defensively false.
stubDB.enabled = true
stubDB.category_toxfilter_enabled = true
stubDB.category_uplifter_enabled  = true
expectBool("unknown_name", "gate.bogus", ns.Category.gate("bogus"), false)

-- Behavioral suppression through PreDungeon (an Uplifter feature the harness
-- loads): emits only when master AND uplifter are on.
ns.PreDungeonData.instances = ccorpus.predungeon_fixture
stubDB.predungeon_warnings_enabled = true
for _, c in ipairs(ccorpus.surface_cases or {}) do
    stubDB.enabled = c.master
    stubDB.category_uplifter_enabled = c.up
    stubDB.category_toxfilter_enabled = true
    stubbedRole = c.role
    ns.PreDungeon.ResetSession()
    startCapture()
    ns.PreDungeon.Surface("GateDungeon")
    local lines = stopCapture()
    expectBool(c.id, "emitted", #lines > 0, c.emitted)
end

-- Restore stub defaults.
stubDB.enabled = true
stubDB.category_toxfilter_enabled = true
stubDB.category_uplifter_enabled  = true

print()
print("=== ToxFilter Sprint 5d category gating ===")
print(string.format("Checks:    %d", cs_total))
local cs_pct = (cs_total > 0) and (100.0 * cs_pass / cs_total) or 0.0
print(string.format("Pass:      %d / %d (%.1f%%)", cs_pass, cs_total, cs_pct))
if cs_fail > 0 then
    print()
    print("Failures:")
    for _, l in ipairs(cs_failures) do print(l) end
end

end
end

LUA

lua "$HARNESS_LUA" "$ADDON_DIR" "$CORPUS_LUA" "$CALLOUT_CORPUS_LUA" "$REMINDERS_CORPUS_FILE" "$WARNINGS_CORPUS_FILE" "$CATEGORY_CORPUS_FILE"
