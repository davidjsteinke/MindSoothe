-- Sprint 5d: category master toggles. Two families of features sit beneath the
-- addon-wide master (/mind on|off):
--   * "toxfilter" — chat hygiene: rule-engine handling, blacklist/whitelist,
--     surgical rewrite, the Sprint 0 fixtures.
--   * "uplifter"  — affirmative/confidence: positive capture, highlight,
--     callouts, tactic reminders, pre-dungeon warnings, stats surfacing.
--
-- Layer hierarchy (Sprint 5d):
--   master (db.enabled, /mind on|off)
--     -> category (db.category_<name>_enabled, /mind category)
--       -> per-feature toggle (callout_enabled, positive_ui, etc.)
--
-- Category.gate(name) collapses the top two layers into one live-gate check.
-- It is the LIVE gate only: passive/automatic surfacing and chatFilter handling
-- consult it. User-invoked slash commands (/mind lift, /mind stats, /mind breathe,
-- etc.) deliberately bypass it — same principle as every other toggle (Sprint
-- 4a: live respects toggles, user-invoked is always honored).
--
-- Because gate() folds in db.enabled, /mind off is a true addon-wide kill: it
-- stops both families, including the event-driven uplifter surfacing that
-- historically ignored db.enabled (Sprint 5d behavior change, intentional).
--
-- Default-on semantics: a nil category field reads as ON. DEFAULTS seeds both
-- to true and migration v9 backfills, but the `~= false` test means a pre-v9
-- db that somehow reaches gate() before migration still behaves as enabled
-- rather than silently suppressing every feature.
--
-- Pure read; never writes. Safe for the corpus harness.

local _, ns = ...

local Category = {}

local FIELD = {
    toxfilter = "category_toxfilter_enabled",
    uplifter  = "category_uplifter_enabled",
}

local function db()
    return ns.Database and ns.Database:Get() or nil
end

-- True when the addon master is on AND the named category is not explicitly
-- off. Unknown names return false (defensive: a typo shouldn't silently
-- enable a feature). nil db returns false.
function Category.gate(name)
    local g = db()
    if not g then return false end
    if not g.enabled then return false end
    local field = FIELD[name]
    if not field then return false end
    return g[field] ~= false
end

-- Category bit only, ignoring the master. Used by /mind status and /mind list so
-- they can report category state independently of the master toggle.
function Category.isEnabled(name)
    local g = db()
    if not g then return false end
    local field = FIELD[name]
    if not field then return false end
    return g[field] ~= false
end

ns.Category = Category
