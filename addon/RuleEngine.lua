-- Rule engine: tokenize → normalize → hash → lookup → pick winning handling.
-- Phrase matching is structurally complete but no-op until Sprint 2 populates
-- ns.RuleData.phrases.

local _, ns = ...

local function classify(msg)
    local rule_data = ns.RuleData
    if not rule_data then
        return { handling = "pass", hits = 0, all_hits = {} }
    end

    local Hash = ns.Hash
    local Normalize = ns.Normalize
    local Categories = ns.Categories

    local raw_tokens = Normalize.tokenize(msg)
    local normalized = {}
    for i = 1, #raw_tokens do
        normalized[i] = Normalize.normalize(raw_tokens[i])
    end

    local all_hits = {}

    for i = 1, #normalized do
        local n = normalized[i]
        if n ~= "" then
            local entry = rule_data.words[Hash.fnv1a(n)]
            if entry then
                all_hits[#all_hits + 1] = {
                    raw        = raw_tokens[i],
                    normalized = n,
                    category   = entry.category,
                    severity   = entry.severity,
                    handling   = Categories.HANDLING[entry.category] or "pass",
                }
            end
        end
    end

    -- Phrase matching: check that all phrase tokens appear in `normalized` in
    -- order, with each consecutive pair within max_distance. Sprint 1 has no
    -- phrase entries so this loop is structurally exercised but produces nothing.
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

    if #all_hits == 0 then
        return { handling = "pass", hits = 0, all_hits = {} }
    end

    -- Aggressiveness wins; tie-break by severity for the category-label choice.
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

    return {
        handling = winner.handling,
        category = winner.category,
        severity = winner.severity,
        hits     = #all_hits,
        all_hits = all_hits,
    }
end

local function buildEditMessage(msg, result)
    local hit_set = {}
    if result.all_hits then
        for i = 1, #result.all_hits do
            local h = result.all_hits[i]
            if h.raw and not h.is_phrase then
                hit_set[h.raw] = true
            end
        end
    end

    local kept = {}
    for word in msg:gmatch("%S+") do
        if not hit_set[word] then
            kept[#kept + 1] = word
        end
    end

    local body = table.concat(kept, " ")
    body = body:match("^%s*(.-)%s*$") or ""
    if body == "" then
        return "[ToxEdit]"
    end
    return "[ToxEdit] " .. body
end

local function buildDeleteLabel(result)
    local label = ns.Categories.LABEL[result.category] or result.category or "Unknown"
    return "[ToxDel: " .. label .. "]"
end

ns.RuleEngine = {
    classify          = classify,
    buildEditMessage  = buildEditMessage,
    buildDeleteLabel  = buildDeleteLabel,
}
