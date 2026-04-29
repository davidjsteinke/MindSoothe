-- Surgical rewrite engine. Consumes classifier per-token labels and produces
-- the [ToxEdit] body. Two modes:
--   * whole_message_preserved (sarcasm-only): emit input verbatim with prefix.
--   * default: drop attack-labeled tokens; preserve tactical and neutral.
--     Neutrals adjacent to an attack span are already absorbed into `attack`
--     by the classifier (Passes 3/4), so any surviving `neutral` is outside
--     attack scaffolding and is real chat signal — affirmatives ("okay",
--     "whatever", "gg"), filler, banter — and must be preserved regardless
--     of whether tactical content anchors it.

local _, ns = ...

local function rewrite(msg, result)
    if result.whole_message_preserved then
        local body = msg:match("^%s*(.-)%s*$") or ""
        if body == "" then return "[ToxEdit]" end
        return "[ToxEdit] " .. body
    end

    local raw_tokens = result.raw_tokens or {}
    local labels     = result.labels or {}

    local kept = {}
    for i = 1, #raw_tokens do
        local lbl = labels[i] or "neutral"
        if lbl ~= "attack" then
            kept[#kept + 1] = raw_tokens[i]
        end
    end

    local body = table.concat(kept, " ")
    body = body:match("^%s*(.-)%s*$") or ""
    if body == "" then return "[ToxEdit]" end
    return "[ToxEdit] " .. body
end

ns.Rewrite = { rewrite = rewrite }
