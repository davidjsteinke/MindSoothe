-- Sprint 7a N12 regression guard: callout-survives-pause through the REAL
-- chatFilter dispatch. Loaded by scripts/pause-dispatch.lua, which stubs the
-- WoW API, loads every live module INCLUDING ToxFilter.lua, and drives the
-- actual chatFilter via the ns.ToxFilterDispatch test hook.
--
-- Why this file exists: the N12 regression (callouts suppressed in combat)
-- escaped TWICE because the main corpus only ever exercised Callout.detect in
-- isolation — never the chatFilter dispatch with isPaused = true. These cases
-- drive the live dispatch through both pause states and assert the four
-- must-not-regress outcomes:
--   * a matching callout TINTS whether paused or not (callout is time-critical
--     UI, gated ONLY by the callout toggles + Uplifter/master, never by pause);
--   * the callout toggle / Uplifter category still suppress it, in and out of
--     combat;
--   * a callout for another role does NOT tint;
--   * the 7a in-combat silent-drop still fires (and its toggle still gates it).
--
-- expect ∈ { "tint", "drop", "pass" } maps to chatFilter's return contract:
--   tint = (false, "<amber>msg<reset>", ...);  drop = (true);  pass = (false[,nil]).

return {
    cases = {
        -- N12 core: a callout addressed to the user's role must TINT during the
        -- combat pause exactly as it does outside it.
        { id = "callout_tints_when_paused",   msg = "tank cooldowns", paused = true,
          role = "tank", callout = true, up = true, master = true, toggle = true, expect = "tint" },
        { id = "callout_tints_unpaused_ctrl", msg = "tank cooldowns", paused = false,
          role = "tank", callout = true, up = true, master = true, toggle = true, expect = "tint" },

        -- Toggle hierarchy still gates the callout while paused.
        { id = "callout_master_off_paused",   msg = "tank cooldowns", paused = true,
          role = "tank", callout = false, up = true, master = true, toggle = true, expect = "pass" },
        { id = "callout_uplifter_off_paused", msg = "tank cooldowns", paused = true,
          role = "tank", callout = true, up = false, master = true, toggle = true, expect = "pass" },
        { id = "callout_addon_master_off_paused", msg = "tank cooldowns", paused = true,
          role = "tank", callout = true, up = true, master = false, toggle = true, expect = "pass" },

        -- A callout for a different role must not tint for this user.
        { id = "callout_other_role_paused",   msg = "healer dispel now", paused = true,
          role = "tank", callout = true, up = true, master = true, toggle = true, expect = "pass" },

        -- 7a in-combat silent-drop of pure hostility still fires while paused...
        { id = "silent_drop_paused",          msg = "placeholder_slur_c", paused = true,
          role = "tank", callout = true, up = true, master = true, toggle = true, expect = "drop" },
        -- ...and its toggle still gates it (toggle off → message passes in combat).
        { id = "silent_drop_toggle_off_paused", msg = "placeholder_slur_c", paused = true,
          role = "tank", callout = true, up = true, master = true, toggle = false, expect = "pass" },
    },

    -- NOTE (Sprint 7a N12, final): there is no in-combat callout path to model.
    -- Midnight does not invoke the chat filter in combat AND delivers in-combat
    -- chat text as a secret/tainted value, so no addon can inspect chat during a
    -- boss fight. The earlier OnCombatChat / RaidWarningFrame in-combat-surface
    -- fixtures were removed with that code. The `cases` above remain valid: they
    -- exercise the chatFilter paused-branch DISPATCH LOGIC directly (the harness
    -- calls chatFilter, modelling "if the filter were invoked while paused"),
    -- which still guards the callout-tint and silent-drop ordering.
}
