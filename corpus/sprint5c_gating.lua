-- Sprint 5c gating + Lookup test scenarios for PreDungeon (per-key pre-dungeon
-- warnings). Pure Lua, loaded directly by scripts/run-corpus.sh via dofile().
--
-- The harness seeds ns.PreDungeonData.instances with this file's
-- `fixtures.instances` and walks `scenarios` in order. Each scenario:
--   1. Applies `setup`  - master toggle, role, optional reset_seen, pre_calls.
--   2. Captures emitted print lines.
--   3. Calls PreDungeon.Surface(instance).
--   4. Asserts `expect.emitted` (boolean), `expect.seen` (boolean), and
--      optionally `expect.bullet_count` (number of "  - " lines surfaced).
--
-- Scenarios deliberately do NOT cover the isPaused() defensive guard: the
-- harness has no pause state. The guard is exercised in-game.
--
-- Coverage targets the Sprint 5c-specific behaviors that differ from 5b:
--   * per-instance seen-key (once per dungeon, not per encounter)
--   * role-filtered interrupts/dispels (tank-interrupt + healer-dispel cases)
--   * the empty-category-omitted requirement (no bare headers)
--   * the all-empty-for-this-role silent case vs. emit for another role

return {
    fixtures = {
        instances = {
            ["KeyDungeon A"] = {
                interrupts = {
                    { spell = "Polymorph",   mob = "Arcane Magister", role = "dps" },
                    { spell = "Shield Bash", mob = "Hulking Add",     role = "tank" },
                },
                dispels = {
                    { debuff = "Curse of Frost", from = "Frost Caller", role = "healer" },
                },
                tips = { "Pull the first hallway with Bloodlust." },
            },
            -- Authored, but no dispels and no tips: dps player sees one
            -- interrupt and nothing else (no bare Dispels:/Tips: headers).
            ["KeyDungeon B"] = {
                interrupts = {
                    { spell = "Fireball", mob = "Caster", role = "dps" },
                },
                dispels = {},
                tips    = {},
            },
            -- Authored, but only a tank interrupt + healer dispel, no tips:
            -- a dps player sees nothing (all-empty → silent); a tank sees one.
            ["KeyDungeon C"] = {
                interrupts = {
                    { spell = "Crushing Blow", mob = "Boss", role = "tank" },
                },
                dispels = {
                    { debuff = "Venom", from = "Serpent", role = "healer" },
                },
                tips = {},
            },
        },
    },
    scenarios = {
        {
            id = "master_off",
            setup = { master = false, role = "dps", reset_seen = true },
            call  = { instance = "KeyDungeon A" },
            expect = { emitted = false, seen = false },
        },
        {
            id = "role_nil",
            setup = { master = true, role = nil, reset_seen = true },
            call  = { instance = "KeyDungeon A" },
            expect = { emitted = false, seen = false },
        },
        {
            id = "unknown_instance",
            setup = { master = true, role = "dps", reset_seen = true },
            call  = { instance = "Nope" },
            expect = { emitted = false, seen = false },
        },
        {
            id = "first_attempt_dps",
            setup = { master = true, role = "dps", reset_seen = true },
            call  = { instance = "KeyDungeon A" },
            -- 1 dps interrupt (Polymorph) + 1 tip = 2 bullets. (Dispel is
            -- healer-only, omitted for dps.)
            expect = { emitted = true, seen = true, bullet_count = 2 },
        },
        {
            id = "second_attempt_same_silent",
            setup = { master = true, role = "dps", reset_seen = false },
            call  = { instance = "KeyDungeon A" },
            expect = { emitted = false, seen = true },
        },
        {
            id = "reset_then_re_emits",
            setup = { master = true, role = "dps", reset_seen = true },
            call  = { instance = "KeyDungeon A" },
            expect = { emitted = true, seen = true, bullet_count = 2 },
        },
        {
            id = "healer_sees_dispels",
            setup = { master = true, role = "healer", reset_seen = true },
            call  = { instance = "KeyDungeon A" },
            -- 1 healer dispel + 1 tip = 2 bullets. (Interrupts are dps/tank.)
            expect = { emitted = true, seen = true, bullet_count = 2 },
        },
        {
            id = "tank_sees_tank_interrupt",
            setup = { master = true, role = "tank", reset_seen = true },
            call  = { instance = "KeyDungeon A" },
            -- 1 tank interrupt (Shield Bash) + 1 tip = 2 bullets.
            expect = { emitted = true, seen = true, bullet_count = 2 },
        },
        {
            id = "empty_dispels_and_tips_omitted",
            setup = { master = true, role = "dps", reset_seen = true },
            call  = { instance = "KeyDungeon B" },
            -- Only 1 interrupt; no Dispels:/Tips: sections at all = 1 bullet.
            expect = { emitted = true, seen = true, bullet_count = 1 },
        },
        {
            id = "all_empty_for_role_silent",
            setup = { master = true, role = "dps", reset_seen = true },
            call  = { instance = "KeyDungeon C" },
            -- dps: no dps interrupt, no dps dispel, no tips → silent, not seen.
            expect = { emitted = false, seen = false },
        },
        {
            id = "same_instance_emits_for_other_role",
            setup = { master = true, role = "tank", reset_seen = true },
            call  = { instance = "KeyDungeon C" },
            -- tank: 1 tank interrupt, no tips = 1 bullet.
            expect = { emitted = true, seen = true, bullet_count = 1 },
        },
        {
            id = "different_instance_independently_tracked",
            setup = { master = true, role = "dps", reset_seen = true,
                      pre_calls = {
                          { instance = "KeyDungeon A" },
                      } },
            call  = { instance = "KeyDungeon B" },
            -- A was surfaced in pre_calls; B is a different instance key, so
            -- it still emits = 1 bullet.
            expect = { emitted = true, seen = true, bullet_count = 1 },
        },
    },
}
