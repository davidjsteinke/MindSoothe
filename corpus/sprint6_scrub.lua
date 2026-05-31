-- Sprint 6 PIIScrub fixtures.
--
-- Weighted precision-first per the locked Sprint 6 policy: the PRIMARY job is
-- proving legitimate positive moments survive intact; name-stripping is the
-- secondary, best-effort check. Each fixture stubs the installing user's
-- current character (`user`), an optional alt `roster`, and the message
-- `sender` (the CHAT_MSG_* author the live path threads in), then asserts the
-- scrubbed body equals `expected`.
--
-- Known-name set per fixture = { user, roster..., sender }. A name not in that
-- set is NOT a known name and must survive (precision). The class-name-collision
-- decision is B1: a known name that is also a class/role word is spared.

return {
    fixtures = {
        -- ===== Must survive intact (precision — the priority) =====
        {
            id = "keep_no_name",
            input = "great pull", user = "Edvins", sender = "Manehealer",
            expected = "great pull",
        },
        {
            id = "keep_class_word_not_player",
            -- "Hunter" is a class reference, not the user and not the sender.
            input = "thanks Hunter", user = "Edvins", sender = "Manehealer",
            expected = "thanks Hunter",
        },
        {
            id = "keep_gg_phrase",
            input = "gg well played", user = "Edvins", sender = "Manehealer",
            expected = "gg well played",
        },
        {
            id = "keep_common_words",
            input = "nice clutch save", user = "Edvins", sender = "Manehealer",
            expected = "nice clutch save",
        },
        {
            id = "keep_substring_safe",
            -- user named "Ash"; must not bite inside "smash" or "Ashbringer".
            input = "great smash Ashbringer ready", user = "Ash", sender = "Randoms",
            expected = "great smash Ashbringer ready",
        },
        {
            id = "keep_collision_user_named_hunter",
            -- B1: user literally named Hunter; protect-list spares it so the
            -- class-reference reading of the moment stays intact.
            input = "thanks Hunter nice kick", user = "Hunter", sender = "Manehealer",
            expected = "thanks Hunter nice kick",
        },
        {
            id = "keep_collision_user_named_tank",
            -- B1: role word as a known name is spared too.
            input = "thanks Tank", user = "Tank", sender = "Manehealer",
            expected = "thanks Tank",
        },
        {
            id = "keep_acronym_mention",
            -- @-acronym spared by PROTECTED_CAPS.
            input = "@DPS check", user = "Edvins", sender = "Manehealer",
            expected = "@DPS check",
        },

        -- ===== Should scrub (recall — best-effort) =====
        {
            id = "scrub_sender_capword",
            input = "thanks Manehealer", user = "Edvins", sender = "Manehealer",
            expected = "thanks <player>",
        },
        {
            id = "scrub_sender_lowercase",
            input = "thanks manehealer", user = "Edvins", sender = "Manehealer",
            expected = "thanks <player>",
        },
        {
            id = "scrub_sender_realm_suffix",
            -- Suffix and all; trailing comma preserved.
            input = "thanks Manehealer-Thrall,", user = "Edvins", sender = "Manehealer",
            expected = "thanks <player>,",
        },
        {
            id = "scrub_mid_sentence",
            input = "you carried us Manehealer", user = "Edvins", sender = "Manehealer",
            expected = "you carried us <player>",
        },
        {
            id = "scrub_leading_position",
            -- Position-independent: name at the start, no thanks token.
            input = "Manehealer carried us hard", user = "Edvins", sender = "Manehealer",
            expected = "<player> carried us hard",
        },
        {
            id = "scrub_accented_name",
            input = "thanks Mané", user = "Edvins", sender = "Mané",
            expected = "thanks <player>",
        },
        {
            id = "scrub_own_name",
            -- The installing user's own name is now scrubbed (own data, but the
            -- stored form is uniform).
            input = "thanks Edvins", user = "Edvins", sender = "Manehealer",
            expected = "thanks <player>",
        },
        {
            id = "scrub_roster_alt",
            -- Alt-roster source: sender is unknown, but the named token is one
            -- of the user's own characters.
            input = "ty Maneheal", user = "Edvins", roster = { "Maneheal", "Edvins" },
            sender = "Randoms", expected = "ty <player>",
        },
        {
            id = "scrub_mention_known",
            input = "@Manehealer nice save", user = "Edvins", sender = "Manehealer",
            expected = "@<player> nice save",
        },

        -- ===== Edge / accepted limitation =====
        {
            id = "edge_second_name_unknown_survives",
            -- Only the sender is known; the second, unrelated name survives.
            -- Accepted per precision-over-recall.
            input = "thanks Bob and Jim", user = "Edvins", sender = "Bob",
            expected = "thanks <player> and Jim",
        },
    },
}
