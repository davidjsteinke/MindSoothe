#!/usr/bin/env bash
# run-gauntlet.sh — the one command that must be green before declaring any
# user-facing change done. Runs, in order:
#   1. luacheck      — static analysis (0 warnings / 0 errors required)
#   2. run-corpus    — the full Lua corpus + gating harness (all 100%)
#   3. tonal grep    — no cheerleading tokens in printed strings (CLAUDE.md Tone)
#   4. pipe audit    — bare "|" in chat strings must be doubled (CLAUDE.md Conventions)
#
# Aggregates: every stage runs even if an earlier one fails, and the script exits
# nonzero if ANY stage failed. "Ran the gauntlet" == this exited 0.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

fail=0
banner() { printf '\n=== %s ===\n' "$1"; }

# --- 1. luacheck -----------------------------------------------------------
banner "luacheck"
if luacheck addon/; then
    echo "luacheck: OK"
else
    echo "luacheck: FAILED"
    fail=1
fi

# --- 2. corpus -------------------------------------------------------------
banner "corpus"
if ./scripts/run-corpus.sh; then
    echo "corpus: OK"
else
    echo "corpus: FAILED"
    fail=1
fi

# Lua source files, excluding the embedded third-party Ace3 under Libs/.
mapfile -t LUA_FILES < <(find addon -path addon/Libs -prune -o -name '*.lua' -print)

# --- 3. tonal grep ---------------------------------------------------------
# Cheerleading tokens (!, great, oops, sorry) inside a string printed via
# print(/out(. Low-affect tone: surface facts, no exclamation. Scoping to
# print(/out( lines keeps comments and pattern-data tables (which legitimately
# contain such words) from false-flagging.
banner "tonal grep"
tonal_hits="$(grep -nEH '(print|out)\(' "${LUA_FILES[@]}" \
    | grep -Ei '(!|great|oops|sorry)' || true)"
if [[ -n "$tonal_hits" ]]; then
    echo "tonal grep: FAILED — cheerleading tokens in printed strings:"
    echo "$tonal_hits"
    fail=1
else
    echo "tonal grep: OK"
fi

# --- 4. pipe audit ---------------------------------------------------------
# A single "|" in a chat string must be doubled unless it is a functional WoW
# escape (|c AARRGGBB, |r, |H|h hyperlink, |T|t texture). Scope to print(/out(
# display lines so comments, data delimiters ("|"), and gsub patterns don't
# false-flag. Highlight.lua and Callout.lua use color escapes and are exempt
# (CLAUDE.md carve-out).
banner "pipe audit"
mapfile -t PIPE_FILES < <(find addon -path addon/Libs -prune -o -name '*.lua' \
    ! -name Highlight.lua ! -name Callout.lua -print)
# On print(/out( lines only: strip allowed escapes, then flag any "|" left over.
pipe_hits="$(grep -nHE '(print|out)\(' "${PIPE_FILES[@]}" \
    | sed -E 's/\|\|//g; s/\|c[0-9A-Fa-f]{8}//g; s/\|r//g; s/\|[HhTt]//g' \
    | grep '|' || true)"
if [[ -n "$pipe_hits" ]]; then
    echo "pipe audit: FAILED — undoubled '|' in a chat string:"
    echo "$pipe_hits"
    fail=1
else
    echo "pipe audit: OK"
fi

# --- summary ---------------------------------------------------------------
banner "gauntlet"
if [[ "$fail" -eq 0 ]]; then
    echo "ALL GREEN"
else
    echo "FAILURES ABOVE"
fi
exit "$fail"
