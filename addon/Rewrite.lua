-- Surgical rewrite engine. Consumes classifier per-token labels and produces
-- the [ToxEdit] body. Two modes:
--   * whole_message_preserved (sarcasm-only): emit input verbatim with prefix.
--   * default: drop attack-labeled tokens, keep tactical and neutral tokens.
--     If no tactical token exists in the message, drop neutrals too — neutral
--     fillers (the/a/of/...) only travel with adjacent tactical content.

local _, ns = ...

local function rewrite(msg, result)
    if result.whole_message_preserved then
        local body = msg:match("^%s*(.-)%s*$") or ""
        if body == "" then return "[ToxEdit]" end
        return "[ToxEdit] " .. body
    end

    local raw_tokens = result.raw_tokens or {}
    local labels     = result.labels or {}

    local has_tactical = false
    for i = 1, #labels do
        if labels[i] == "tactical" then has_tactical = true; break end
    end

    local kept = {}
    for i = 1, #raw_tokens do
        local lbl = labels[i] or "neutral"
        if lbl == "tactical" then
            kept[#kept + 1] = raw_tokens[i]
        elseif lbl == "neutral" and has_tactical then
            kept[#kept + 1] = raw_tokens[i]
        end
    end

    local body = table.concat(kept, " ")
    body = body:match("^%s*(.-)%s*$") or ""
    if body == "" then return "[ToxEdit]" end
    return "[ToxEdit] " .. body
end

ns.Rewrite = { rewrite = rewrite }
