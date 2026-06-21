-- Sprint 7a: silent-drop classification gate (CURRENTLY INERT — see N12 below).
-- shouldDrop was intended to add ONE carve-out to chatFilter's paused branch:
-- high-confidence pure hostility silent-dropped while paused. Rationale: a rewrite
-- mistake in combat is expensive, but a message with zero information content
-- costs nothing to drop.
--
-- NOTE (N12): chatFilter's paused branch is never invoked in combat (the filter
-- does not run, and in-combat chat text is a secret/tainted value), and shouldDrop
-- is wired ONLY into that paused branch (ToxFilter.lua) — not the non-paused path.
-- So this carve-out has no runtime effect today: dead in combat, absent out of
-- combat. The module and its toggle are retained for the pause-dispatch guard and
-- a possible future non-paused home. The classification gate below is still
-- correct and corpus-tested.
--
-- The gate errs narrow. A message qualifies only when ALL hold:
--   1. Winning category is in CATEGORIES — the two rule-data-driven, near-zero-
--      information categories (slur, harm_invocation). identity_attack is
--      deliberately excluded: its rule coverage is sparse, and sparse + silent +
--      combat is the worst place for a false drop. Editable here.
--   2. handling ~= "pass" (it actually flagged).
--   3. Purity: no token carries the "tactical" label. ANY tactical/informational
--      content makes the message pass through untouched. "move out of fire <slur>"
--      keeps its fire/move/out tactical labels -> not pure -> passes.
--
-- shouldDrop also folds in the toggle (db.combat_silent_drop) and the ToxFilter
-- category gate (which includes the addon master). It's chat-hygiene handling, so
-- it rides the ToxFilter family, not Uplifter.
--
-- Pure read; never writes. Safe for the corpus harness — it drives shouldDrop
-- directly off RuleEngine.classify output.

local _, ns = ...

local CombatDrop = {}

-- Editable narrow set. Do not add identity_attack without revisiting the
-- sparse-coverage reasoning above.
local CATEGORIES = {
    slur            = true,
    harm_invocation = true,
}
CombatDrop.CATEGORIES = CATEGORIES

-- No surviving tactical/informational token.
local function isPure(result)
    local labels = result and result.labels
    if not labels then return false end
    for i = 1, #labels do
        if labels[i] == "tactical" then return false end
    end
    return true
end
CombatDrop.isPure = isPure

-- Classification-only eligibility: category in the narrow set, flagged, pure.
-- No db / toggle / category consultation — that is shouldDrop's job.
function CombatDrop.eligible(result)
    if not result then return false end
    if result.handling == "pass" then return false end
    if not CATEGORIES[result.category] then return false end
    return isPure(result)
end

-- Full live decision: eligible AND the toggle is on AND the ToxFilter category
-- (and thus the addon master) is on.
function CombatDrop.shouldDrop(result)
    if not CombatDrop.eligible(result) then return false end
    local g = ns.Database and ns.Database:Get() or nil
    if not g or not g.combat_silent_drop then return false end
    if not (ns.Category and ns.Category.gate("toxfilter")) then return false end
    return true
end

ns.CombatDrop = CombatDrop
