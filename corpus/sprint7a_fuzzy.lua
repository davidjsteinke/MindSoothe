-- Sprint 7a (F3) typo tolerance. Pure Lua, loaded by scripts/run-corpus.sh.
-- Drives PositiveCapture.detect (via RuleEngine.classify for normalized tokens +
-- signals) for the positive/negative cases, and RuleEngine.classify directly for
-- the must-not-fire classifier case.
--
-- Proves: distance-1 positives fire (transposition + deletion, on THANKS,
-- POS_VERBS, POS_PLAYS); the length-5 floor keeps short keywords exact-only;
-- role targets are exact-only (never fuzzed); and the hostility classifier gains
-- NO fuzzy matching — a distance-1 slur variant stays "pass" and is not captured
-- as a positive moment.

return {
    -- detect() must fire (non-nil); expect_pattern names the firing pattern.
    positive_cases = {
        { id = "thanks_transposition", input = "thansk tank",   expect_pattern = "thanks_role" },
        { id = "thanks_deletion",      input = "thaks tank",    expect_pattern = "thanks_role" },
        { id = "thanks_exact_control", input = "thanks tank",   expect_pattern = "thanks_role" },
        { id = "verb_transposition",   input = "cluthc save",   expect_pattern = "compliment_play" },
        { id = "play_deletion",        input = "nice interupt", expect_pattern = "compliment_play" },
        -- "tnak" is distance-1 from the role target "tank", but role targets are
        -- exact-only, so thanks_ROLE does not fire on a misspelled role. The bare
        -- "thanks" still captures as the un-targeted "thanks" pattern (not direct)
        -- — proof the role anchor was never fuzzy-matched.
        { id = "role_target_exact_only", input = "thanks tnak", expect_pattern = "thanks" },
    },

    -- detect() must NOT fire (nil).
    negative_cases = {
        -- "goed"(4) is distance-1 from the verb "good", but "good"(4) is below
        -- the length floor so it is never fuzzed — and no thanks/callout token is
        -- present, so "goed kick" yields nothing.
        { id = "short_word_floor",      input = "goed kick"   },

        -- N16 (Sprint 7a in-game): "rank"/"task"/"tans" are 4-char distance-1
        -- neighbours of the ROLE NOUN "tank", which lives in POS_PLAYS. The
        -- length-5 floor (enforced on both the input token AND the candidate
        -- keyword) keeps "tank" out of every fuzzed set, so these must NOT
        -- capture as standalone tokens. The original short_word_floor case only
        -- exercised a keyword ("good") that was ALSO sub-floor; it never covered
        -- a short input against a keyword that genuinely sits in a fuzzed set —
        -- this is that coverage.
        { id = "tank_neighbour_rank",   input = "rank"        },
        { id = "tank_neighbour_task",   input = "task"        },
        { id = "tank_neighbour_tans",   input = "tans"        },
        -- Same neighbours as the second token of a would-be compliment_play
        -- ("nice <play>"): the verb is exact, but the play-noun is a sub-floor
        -- typo of "tank" and must not fuzzy-match, so no compliment fires.
        { id = "tank_neighbour_in_play_rank", input = "nice rank" },
        { id = "tank_neighbour_in_play_task", input = "good task" },
    },

    -- classify() must stay "pass" on a distance-1 slur variant: proof the
    -- classifier/rule engine never gained fuzzy matching.
    classifier_cases = {
        { id = "slur_variant_not_fuzzed", input = "testwore_slur_a", exp_handling = "pass" },
    },
}
