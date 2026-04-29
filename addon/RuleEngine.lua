-- Rule engine: tokenize → normalize → hash → lookup → classifier → pick winning
-- handling. The classifier runs on every message (even with zero rule hits) so
-- it can flag role-attack patterns and sarcasm against placeholder content.
--
-- Attack-span vs winning-category decoupling: when a slur (rule hit) sits inside
-- a role-attack scaffold (e.g. "you're a placeholder_slur_c tank"), the rule
-- winner determines result.category (slur, severity wins) but the classifier
-- owns result.labels — Rewrite reads labels, not category, so it strips the
-- entire scaffold even though the winning category is slur.

local _, ns = ...

local function classify(msg)
    local rule_data = ns.RuleData
    local Hash      = ns.Hash
    local Normalize = ns.Normalize
    local Categories = ns.Categories
    local Classifier = ns.Classifier

    local raw_tokens = Normalize.tokenize(msg)
    local normalized = {}
    for i = 1, #raw_tokens do
        normalized[i] = Normalize.normalize(raw_tokens[i])
    end

    local all_hits = {}
    local rule_hit_by_index = {}

    if rule_data then
        for i = 1, #normalized do
            local n = normalized[i]
            if n ~= "" then
                local entry = rule_data.words[Hash.fnv1a(n)]
                if entry then
                    local hit = {
                        raw        = raw_tokens[i],
                        normalized = n,
                        index      = i,
                        category   = entry.category,
                        severity   = entry.severity,
                        handling   = Categories.HANDLING[entry.category] or "pass",
                    }
                    all_hits[#all_hits + 1] = hit
                    rule_hit_by_index[i] = hit
                end
            end
        end

        -- Phrase matching: check that all phrase tokens appear in `normalized`
        -- in order, with each consecutive pair within max_distance. Sprint 1/2
        -- ship no phrase entries; the loop is exercised but produces nothing.
        if rule_data.phrases then
            for _, phrase in ipairs(rule_data.phrases) do
                local last_idx = 0
                local matched = true
                for ti = 1, #phrase.tokens do
                    local target = phrase.tokens[ti]
                    local found = nil
                    local search_from = last_idx + 1
                    local search_to   = (last_idx == 0) and #normalized
                                        or math.min(#normalized, last_idx + phrase.max_distance)
                    for ni = search_from, search_to do
                        if Hash.fnv1a(normalized[ni]) == target then
                            found = ni
                            break
                        end
                    end
                    if not found then
                        matched = false
                        break
                    end
                    last_idx = found
                end
                if matched then
                    all_hits[#all_hits + 1] = {
                        raw        = "<phrase>",
                        normalized = "<phrase>",
                        category   = phrase.category,
                        severity   = phrase.severity,
                        handling   = Categories.HANDLING[phrase.category] or "pass",
                        is_phrase  = true,
                    }
                end
            end
        end
    end

    local cls = Classifier.classify(raw_tokens, normalized, rule_hit_by_index)

    local handling, category, severity, whole_message_preserved

    if #all_hits > 0 then
        local rank = Categories.HANDLING_RANK
        local winner = all_hits[1]
        for i = 2, #all_hits do
            local h = all_hits[i]
            local cur = rank[h.handling] or 0
            local win = rank[winner.handling] or 0
            if cur > win or (cur == win and h.severity > winner.severity) then
                winner = h
            end
        end
        handling = winner.handling
        category = winner.category
        severity = winner.severity
        whole_message_preserved = false
    elseif cls.suggested_category then
        category = cls.suggested_category
        handling = Categories.HANDLING[category] or "edit"
        severity = 5
        whole_message_preserved = false
    elseif cls.sarcasm_only_category then
        category = cls.sarcasm_only_category
        handling = "edit"
        severity = 5
        whole_message_preserved = true
    else
        handling = "pass"
        category = nil
        severity = nil
        whole_message_preserved = false
    end

    return {
        handling                = handling,
        category                = category,
        severity                = severity,
        hits                    = #all_hits,
        all_hits                = all_hits,
        raw_tokens              = raw_tokens,
        normalized_tokens       = normalized,
        labels                  = cls.labels,
        signals                 = cls.signals,
        whole_message_preserved = whole_message_preserved,
    }
end

local function buildEditMessage(msg, result)
    return ns.Rewrite.rewrite(msg, result)
end

local function buildDeleteLabel(result)
    local label = ns.Categories.LABEL[result.category] or result.category or "Unknown"
    return "[ToxDel: " .. label .. "]"
end

ns.RuleEngine = {
    classify         = classify,
    buildEditMessage = buildEditMessage,
    buildDeleteLabel = buildDeleteLabel,
}
