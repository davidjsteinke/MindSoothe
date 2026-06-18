-- Sprint 7a (F1) in-combat silent-drop gate. Pure Lua, loaded by
-- scripts/run-corpus.sh via dofile(). Each case runs RuleEngine.classify on a
-- real input (placeholder slur/harm tokens live in the shipped RuleData), then
-- checks CombatDrop.eligible (classification-only) and CombatDrop.shouldDrop
-- (folds in the toggle + ToxFilter category + master).
--
-- Proves: pure slur/harm drops; mixed tactical+hostility passes (purity guard);
-- a flagged-but-out-of-set category (role_attack) passes; toggle-off,
-- ToxFilter-off, and master-off each suppress the drop while eligibility (a pure
-- classification fact) is unchanged.

return {
    cases = {
        -- Pure hostility, all gates open → drops.
        { id = "pure_slur_drops",   input = "placeholder_slur_c",
          master = true, tf = true, toggle = true, exp_eligible = true,  exp_drop = true  },
        { id = "pure_harm_drops",   input = "testword_harm_a",
          master = true, tf = true, toggle = true, exp_eligible = true,  exp_drop = true  },
        { id = "pure_slur_trailing_neutral", input = "testword_slur_a everyone",
          master = true, tf = true, toggle = true, exp_eligible = true,  exp_drop = true  },

        -- Mixed tactical + hostility → not pure → passes untouched in combat.
        { id = "mixed_tactical_slur_passes", input = "interrupt the cast testword_slur_b",
          master = true, tf = true, toggle = true, exp_eligible = false, exp_drop = false },

        -- Flagged but category not in the narrow set (role_attack) → passes.
        { id = "role_attack_out_of_set", input = "worst tank ever",
          master = true, tf = true, toggle = true, exp_eligible = false, exp_drop = false },

        -- Clean message → never eligible.
        { id = "clean_passes", input = "thanks tank",
          master = true, tf = true, toggle = true, exp_eligible = false, exp_drop = false },

        -- Hierarchy: eligibility holds (pure slur) but each gate suppresses drop.
        { id = "toggle_off_no_drop", input = "placeholder_slur_c",
          master = true, tf = true, toggle = false, exp_eligible = true, exp_drop = false },
        { id = "toxfilter_off_no_drop", input = "placeholder_slur_c",
          master = true, tf = false, toggle = true, exp_eligible = true, exp_drop = false },
        { id = "master_off_no_drop", input = "placeholder_slur_c",
          master = false, tf = true, toggle = true, exp_eligible = true, exp_drop = false },
    },
}
