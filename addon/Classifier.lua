-- Constructive-vs-hostile classifier. Operates on tokens already produced by
-- Normalize.tokenize/normalize and on the rule-engine's per-index hit table.
-- Returns per-token labels (attack / tactical / neutral) plus signal flags.
-- Pure functions, no state. Live path is deterministic only — no LLM, no I/O.

local _, ns = ...

local ROLE_WINDOW = 3
local YOU_WINDOW  = 2

local function classify(raw_tokens, normalized_tokens, rule_hit_by_index)
    local Patterns = ns.Patterns
    local n = #raw_tokens
    local labels = {}
    for i = 1, n do labels[i] = "neutral" end

    local signals = {}

    -- Pass 1: tactical markers. Tactical wins on overlap with role nouns —
    -- documented spec-name false-negative.
    for i = 1, n do
        local t = normalized_tokens[i]
        if t ~= "" then
            if Patterns.TACTICAL_MARKERS[t] or Patterns.is_numeric_tactical(t) then
                labels[i] = "tactical"
            end
        end
    end

    -- Pass 2: rule-data hits → attack (only if not already tactical).
    if rule_hit_by_index then
        for i, _ in pairs(rule_hit_by_index) do
            if labels[i] ~= "tactical" then
                labels[i] = "attack"
            end
        end
    end

    local function absorbable(idx)
        if idx < 1 or idx > n then return false end
        if labels[idx] == "tactical" then return false end
        local t = normalized_tokens[idx]
        return Patterns.YOU_PRONOUNS[t]
            or Patterns.NEUTRAL_FILLERS[t]
            or Patterns.INTENSIFIERS[t]
            or Patterns.NEG_MODIFIERS[t]
            or Patterns.INTELLIGENCE_MOCKING[t]
    end

    local function blocked_by_tactical(a, b)
        local lo, hi = math.min(a, b), math.max(a, b)
        for k = lo + 1, hi - 1 do
            if labels[k] == "tactical" then return true end
        end
        return false
    end

    local function fire_attack_span(a, b)
        local mn, mx = math.min(a, b), math.max(a, b)
        for k = mn, mx do
            if labels[k] ~= "tactical" then labels[k] = "attack" end
        end
        local lk = mn - 1
        while absorbable(lk) do
            labels[lk] = "attack"; lk = lk - 1
        end
        local rk = mx + 1
        while absorbable(rk) do
            labels[rk] = "attack"; rk = rk + 1
        end
    end

    -- Pass 3: role-attack pattern. Per Sprint 2 design, NEG_MODIFIERS in
    -- tactical context (separated from the role noun by a tactical token) do
    -- NOT fire — that's intensification of tactical content, not attack.
    local role_attack_fired = false
    for i = 1, n do
        local t = normalized_tokens[i]
        if Patterns.ROLE_NOUNS[t] and labels[i] ~= "tactical" then
            local lo = math.max(1, i - ROLE_WINDOW)
            local hi = math.min(n, i + ROLE_WINDOW)
            for j = lo, hi do
                if j ~= i then
                    local nj = normalized_tokens[j]
                    local is_trigger = labels[j] == "attack" or Patterns.NEG_MODIFIERS[nj]
                    if is_trigger and not blocked_by_tactical(i, j) then
                        fire_attack_span(i, j)
                        role_attack_fired = true
                        signals.role_label_modifier = true
                        break
                    end
                end
            end
        end
    end

    -- Pass 4: you-pronoun + modifier (harassment-style attack with no role noun).
    local you_attack_fired = false
    for i = 1, n do
        local t = normalized_tokens[i]
        if Patterns.YOU_PRONOUNS[t] and labels[i] == "neutral" then
            local lo = math.max(1, i - YOU_WINDOW)
            local hi = math.min(n, i + YOU_WINDOW)
            for j = lo, hi do
                if j ~= i then
                    local nj = normalized_tokens[j]
                    local is_trigger = labels[j] == "attack"
                        or Patterns.NEG_MODIFIERS[nj]
                        or Patterns.INTELLIGENCE_MOCKING[nj]
                    if is_trigger and not blocked_by_tactical(i, j) then
                        fire_attack_span(i, j)
                        you_attack_fired = true
                        signals.you_pronoun_attack = true
                        break
                    end
                end
            end
        end
    end

    -- Pass 5: sarcasm signals. Don't relabel tokens — these set flags only and
    -- (when classifier-only) drive whole-message preservation in Rewrite.

    -- Antonymic praise + intelligence-mocking noun.
    local found_antonymic = false
    for i = 1, n - 1 do
        if Patterns.ANTONYMIC_PRAISE_FIRST[normalized_tokens[i]]
           and Patterns.ANTONYMIC_PRAISE_SECOND[normalized_tokens[i + 1]] then
            for j = i + 2, n do
                if Patterns.INTELLIGENCE_MOCKING[normalized_tokens[j]] then
                    signals.sarcasm_antonymic_praise = true
                    found_antonymic = true
                    break
                end
            end
        end
        if found_antonymic then break end
    end

    -- Passive-aggressive thanks.
    for i = 1, n do
        if Patterns.PASSIVE_THANKS_FIRST[normalized_tokens[i]] then
            for j = i + 1, math.min(n, i + 4) do
                if Patterns.PASSIVE_THANKS_NEG[normalized_tokens[j]] then
                    signals.sarcasm_passive_thanks = true
                    break
                end
            end
        end
    end

    -- "/s" suffix (raw token, since "/" gets stripped by normalization).
    for i = 1, n do
        local raw = raw_tokens[i]
        if raw == "/s" or raw == "/S" then
            signals.sarcasm_slash_s = true
        end
    end

    -- Conditional-blame phrases.
    for _, phrase in ipairs(Patterns.CONDITIONAL_BLAME_TRIGGERS) do
        local plen = #phrase
        if plen <= n then
            for i = 1, n - plen + 1 do
                local match_ok = true
                for k = 1, plen do
                    if normalized_tokens[i + k - 1] ~= phrase[k] then
                        match_ok = false; break
                    end
                end
                if match_ok then
                    signals.sarcasm_maybe_try = true
                    break
                end
            end
        end
    end

    local sarcasm_fired = signals.sarcasm_antonymic_praise
        or signals.sarcasm_passive_thanks
        or signals.sarcasm_slash_s
        or signals.sarcasm_maybe_try

    local any_attack = false
    for i = 1, n do
        if labels[i] == "attack" then any_attack = true; break end
    end

    local sarcasm_only_category = nil
    if sarcasm_fired and not any_attack then
        sarcasm_only_category = "harassment"
    end

    local suggested_category = nil
    if role_attack_fired then
        suggested_category = "role_attack"
    elseif you_attack_fired then
        suggested_category = "harassment"
    end

    return {
        labels                = labels,
        signals               = signals,
        suggested_category    = suggested_category,
        sarcasm_only_category = sarcasm_only_category,
    }
end

ns.Classifier = { classify = classify }
