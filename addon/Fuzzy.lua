-- Sprint 7a: edit-distance-1 fuzzy matching for the positive-capture and callout
-- keyword sets ONLY. Never wired into the hostility classifier, rule engine,
-- blacklist, or whitelist — that scope line is load-bearing (a fuzzy slur match
-- would be a precision disaster). PositiveCapture and Callout consult this on an
-- exact-match miss; the exact hash/membership lookup stays the hot path.
--
-- Distance model: Damerau (adjacent transposition counts as distance 1), not
-- plain Levenshtein. Required by the motivating case: "thansk" is a k/s
-- transposition of "thanks", which plain Levenshtein scores as 2 (a miss).
--
-- within1 is a direct O(n) check rather than a DP table: equal strings -> 0; same
-- length -> count byte mismatches (1 = substitution; exactly 2 adjacent + swapped
-- = transposition); length differing by 1 -> single insertion/deletion via a
-- one-skip walk. No per-call allocation. Tokens are already lowercased upstream
-- (Normalize for PositiveCapture, tokenize for Callout) so byte compare is safe.
--
-- Guards live at the call sites, not here: a length floor (5) and exact-only
-- role targets. This module is pure mechanics.

local _, ns = ...

local Fuzzy = {}

-- True iff the Damerau edit distance between a and b is <= 1.
local function within1(a, b)
    if a == b then return true end
    local la, lb = #a, #b
    local diff = la - lb
    if diff < -1 or diff > 1 then return false end

    if la == lb then
        local first = nil
        local mismatches = 0
        for i = 1, la do
            if a:byte(i) ~= b:byte(i) then
                mismatches = mismatches + 1
                if not first then first = i end
                if mismatches > 2 then return false end
            end
        end
        if mismatches == 1 then return true end          -- single substitution
        if mismatches == 2 then
            -- Transposition iff the two mismatches are exactly first and first+1
            -- and the pair is swapped. The i+1 mismatch check pins them adjacent.
            local i = first
            if i < la
               and a:byte(i)     == b:byte(i + 1)
               and a:byte(i + 1) == b:byte(i)
               and a:byte(i + 1) ~= b:byte(i + 1) then
                return true
            end
        end
        return false
    end

    -- Length differs by 1: one insertion/deletion. Walk the longer against the
    -- shorter, permitting a single skip in the longer string.
    local long, short = a, b
    if lb > la then long, short = b, a end
    local i, j = 1, 1
    local ls, ss = #long, #short
    local skipped = false
    while i <= ls and j <= ss do
        if long:byte(i) == short:byte(j) then
            i = i + 1; j = j + 1
        else
            if skipped then return false end
            skipped = true
            i = i + 1
        end
    end
    return true
end

-- Build a length-bucketed list of a set's keys whose length >= minlen. Done once
-- at module load per keyword set; lets matches() consult only nearby lengths.
function Fuzzy.bucketize(set, minlen)
    local byLen = {}
    for key in pairs(set) do
        if #key >= minlen then
            local L = #key
            byLen[L] = byLen[L] or {}
            byLen[L][#byLen[L] + 1] = key
        end
    end
    return byLen
end

-- True if token (length >= minlen) is within distance 1 of any bucketized
-- keyword. Only lengths len-1, len, len+1 can be within 1, so only those are
-- scanned.
function Fuzzy.matches(token, buckets, minlen)
    local lt = #token
    if lt < minlen then return false end
    for d = -1, 1 do
        local list = buckets[lt + d]
        if list then
            for i = 1, #list do
                if within1(token, list[i]) then return true end
            end
        end
    end
    return false
end

Fuzzy.within1 = within1

ns.Fuzzy = Fuzzy
