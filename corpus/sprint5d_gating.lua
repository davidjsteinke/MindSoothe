-- Sprint 5d category-gate test data. Pure Lua, loaded by scripts/run-corpus.sh
-- via dofile(). Two parts:
--
--   gate_cases    — truth table for ns.Category.gate / ns.Category.isEnabled
--                   across master (db.enabled) × toxfilter × uplifter. Proves
--                   the three-layer hierarchy: master kills both families; a
--                   category bit only gates its own family; nil reads as ON.
--
--   surface_cases — behavioral proof that an Uplifter feature (PreDungeon, which
--                   the harness already loads) goes silent when the uplifter
--                   category OR the addon master is off, and emits when both are
--                   on. This is the regression guard: "both on → behaves exactly
--                   as pre-5d" and "category off → passive surfacing stops."
--
-- ToxFilter-family suppression (rule-engine handling, fixtures) lives in
-- chatFilter, which the harness does not drive; that is verified in-game per the
-- Sprint 5d verification protocol. PositiveCapture/Stats are likewise not loaded
-- by the harness, so their internal gates are covered in-game. The gate logic
-- those features share IS proven here via gate_cases.

return {
    -- master = db.enabled; tf/up = category bits (nil means "field absent",
    -- which must read as ON via the ~= false test).
    gate_cases = {
        { id = "all_on",          master = true,  tf = true,  up = true,  exp_tf = true,  exp_up = true  },
        { id = "master_off_kills",master = false, tf = true,  up = true,  exp_tf = false, exp_up = false },
        { id = "toxfilter_off",   master = true,  tf = false, up = true,  exp_tf = false, exp_up = true  },
        { id = "uplifter_off",    master = true,  tf = true,  up = false, exp_tf = true,  exp_up = false },
        { id = "both_cat_off",    master = true,  tf = false, up = false, exp_tf = false, exp_up = false },
        { id = "nil_reads_on",    master = true,  tf = nil,   up = nil,   exp_tf = true,  exp_up = true  },
        { id = "master_off_nil",  master = false, tf = nil,   up = nil,   exp_tf = false, exp_up = false },
    },

    -- isEnabled ignores the master — reports the category bit only (used by
    -- /tox status and /tox list). nil reads as ON.
    isenabled_cases = {
        { id = "ie_on",       tf = true,  up = true,  exp_tf = true,  exp_up = true  },
        { id = "ie_tf_off",   tf = false, up = true,  exp_tf = false, exp_up = true  },
        { id = "ie_up_off",   tf = true,  up = false, exp_tf = true,  exp_up = false },
        { id = "ie_nil_on",   tf = nil,   up = nil,   exp_tf = true,  exp_up = true  },
    },

    -- Single PreDungeon fixture with dps-visible content (one interrupt + one
    -- tip) so a dps player emits when the gate is open.
    predungeon_fixture = {
        ["GateDungeon"] = {
            interrupts = { { spell = "Polymorph", mob = "Magister", role = "dps" } },
            dispels    = {},
            tips       = { "Skip the side packs." },
        },
    },

    surface_cases = {
        { id = "both_on_emits",       master = true,  up = true,  role = "dps", emitted = true  },
        { id = "uplifter_off_silent", master = true,  up = false, role = "dps", emitted = false },
        { id = "master_off_silent",   master = false, up = true,  role = "dps", emitted = false },
    },
}
