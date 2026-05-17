-- Sprint 5b gating + Lookup test scenarios. Pure Lua, no Python conversion.
-- Loaded directly by scripts/run-corpus.sh via dofile().
--
-- The harness seeds ns.JournalData.instances with this file's `fixtures.instances`
-- and walks `scenarios` in order. Each scenario:
--   1. Applies `setup`  - master toggle, role, optional reset_seen.
--   2. Captures emitted print lines.
--   3. Calls TacticReminders.Surface(instance, encounter, bucket).
--   4. Asserts `expect.emitted` (boolean) and `expect.seen` (boolean) match,
--      and optionally `expect.mechanic_count` if surfaced lines are checked.
--
-- Scenarios deliberately do NOT cover the isPaused() defensive guard: the
-- harness has no pause state. The guard is exercised in-game per Section K.

return {
    fixtures = {
        instances = {
            ["TestDungeon A"] = {
                difficulty_modifiers = {
                    ["mythic"] = {
                        extra_mechanics = {
                            tank   = { "Mythic-only tank thing." },
                            healer = {},
                            dps    = {},
                        },
                    },
                },
                encounters = {
                    ["First Boss"] = {
                        tank   = { "Tank thing one.", "Tank thing two." },
                        healer = { "Healer thing one.", "Healer thing two." },
                        dps    = {},  -- empty role list: no-emit case
                    },
                    ["Second Boss"] = {
                        tank   = { "Second tank thing." },
                        healer = { "Second healer thing." },
                        dps    = { "Second dps thing." },
                    },
                },
            },
        },
    },
    scenarios = {
        {
            id = "master_off",
            setup = { master = false, role = "tank", reset_seen = true },
            call  = { instance = "TestDungeon A", encounter = "First Boss", bucket = "heroic" },
            expect = { emitted = false, seen = false },
        },
        {
            id = "role_nil",
            setup = { master = true, role = nil, reset_seen = true },
            call  = { instance = "TestDungeon A", encounter = "First Boss", bucket = "heroic" },
            expect = { emitted = false, seen = false },
        },
        {
            id = "unknown_instance",
            setup = { master = true, role = "tank", reset_seen = true },
            call  = { instance = "Nope", encounter = "First Boss", bucket = "heroic" },
            expect = { emitted = false, seen = false },
        },
        {
            id = "unknown_encounter",
            setup = { master = true, role = "tank", reset_seen = true },
            call  = { instance = "TestDungeon A", encounter = "Nope", bucket = "heroic" },
            expect = { emitted = false, seen = false },
        },
        {
            id = "first_attempt_tank",
            setup = { master = true, role = "tank", reset_seen = true },
            call  = { instance = "TestDungeon A", encounter = "First Boss", bucket = "heroic" },
            expect = { emitted = true, seen = true, mechanic_count = 2 },
        },
        {
            id = "second_attempt_same_silent",
            -- Note: depends on prior scenario's seen-map; reset_seen=false.
            setup = { master = true, role = "tank", reset_seen = false },
            call  = { instance = "TestDungeon A", encounter = "First Boss", bucket = "heroic" },
            expect = { emitted = false, seen = true },
        },
        {
            id = "different_bucket_emits",
            setup = { master = true, role = "tank", reset_seen = false },
            call  = { instance = "TestDungeon A", encounter = "First Boss", bucket = "mythic" },
            -- mythic adds 1 extra mechanic on top of base 2 = 3 lines
            expect = { emitted = true, seen = true, mechanic_count = 3 },
        },
        {
            id = "reset_then_re_emits",
            setup = { master = true, role = "tank", reset_seen = true },
            call  = { instance = "TestDungeon A", encounter = "First Boss", bucket = "heroic" },
            expect = { emitted = true, seen = true, mechanic_count = 2 },
        },
        {
            id = "empty_role_list_silent",
            setup = { master = true, role = "dps", reset_seen = true },
            call  = { instance = "TestDungeon A", encounter = "First Boss", bucket = "heroic" },
            -- First Boss has dps = {}; no emit even though the encounter exists.
            expect = { emitted = false, seen = false },
        },
        {
            id = "base_only_no_modifier_for_bucket",
            setup = { master = true, role = "healer", reset_seen = true },
            call  = { instance = "TestDungeon A", encounter = "First Boss", bucket = "heroic" },
            -- heroic has no difficulty_modifier; base is 2 mechanics for healer.
            expect = { emitted = true, seen = true, mechanic_count = 2 },
        },
        {
            id = "modifier_empty_role_falls_back_to_base",
            setup = { master = true, role = "healer", reset_seen = true },
            call  = { instance = "TestDungeon A", encounter = "First Boss", bucket = "mythic" },
            -- mythic.extra_mechanics.healer = {}; base is 2; combined = 2.
            expect = { emitted = true, seen = true, mechanic_count = 2 },
        },
        {
            id = "different_encounter_independently_tracked",
            -- After reset, fire First Boss (emit, mark seen), then Second Boss
            -- (also emit because different encounter key). We test this by NOT
            -- resetting before the second call.
            setup = { master = true, role = "tank", reset_seen = true,
                      pre_calls = {
                          { instance = "TestDungeon A", encounter = "First Boss", bucket = "heroic" },
                      } },
            call  = { instance = "TestDungeon A", encounter = "Second Boss", bucket = "heroic" },
            expect = { emitted = true, seen = true, mechanic_count = 1 },
        },
    },
}
