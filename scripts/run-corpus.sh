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

local addon_dir          = arg[1]
local corpus_file        = arg[2]
local callout_corpus_file = arg[3]

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

-- Database stub for Callout.matchesUser. The harness sets currentRole per
-- entry; Callout consults ns.Database:Get() (must return non-nil) and
-- ns.Database:GetEffectiveRole() to decide match.
local stubbedRole = nil
ns.Database = {
    Get = function() return { callout_enabled = true, callout_ui = true, callout_sound = true } end,
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
LUA

lua "$HARNESS_LUA" "$ADDON_DIR" "$CORPUS_LUA" "$CALLOUT_CORPUS_LUA"
