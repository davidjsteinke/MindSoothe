-- Sprint 7a (F4) emote parsing. Pure Lua, loaded by scripts/run-corpus.sh.
-- Exercises PositiveCapture.emoteDetect on rendered emote text.
--
-- Scope of this harness: emoteDetect's keyword + self-target logic only. The
-- following are IN-GAME-ONLY and cannot be exercised here:
--   * the CHAT_MSG_TEXT_EMOTE event firing and its exact arg layout;
--   * whether enUS targeted emotes actually render "you" (assumed by design);
--   * the self-sender guard (own outgoing emote skipped) — it lives in
--     captureEmote, which needs Buffer/Database the detect harness does not load;
--   * the Uplifter category gate around captureEmote (covered by the 5d gating);
--   * the post-7a taint fix: captureEmote's player-source GUID guard (NPC /
--     system emotes from Delve-end / vendor-close are dropped before touching the
--     emote text) and the pcall firewall around emoteDetect. Both depend on the
--     live CHAT_MSG_TEXT_EMOTE GUID arg + secret-value semantics and cannot be
--     modeled here; emoteDetect's keyword/self-target logic below is unchanged.
--
-- emoteDetect is enUS-only by construction (English emote verbs + "you"/"your");
-- other locales are a documented limitation, not a silent gap.

return {
    -- emoteDetect must return non-nil: an emote verb AND a self-target token,
    -- i.e. aimed at the player.
    positive_cases = {
        { id = "thanks_you",       text = "Bob thanks you."        },  -- targeted
        { id = "salutes_you",      text = "Carol salutes you."     },  -- targeted
        { id = "cheers_at_you",    text = "Dave cheers at you."    },  -- targeted ("at you")
    },

    -- emoteDetect must return nil.
    negative_cases = {
        { id = "third_party",        text = "Bob cheers at Carol." },  -- aimed elsewhere (N23)
        { id = "verb_not_emote",     text = "Bob dances with you." },  -- self-target, wrong verb
        { id = "untargeted_dance",   text = "Bob dances."          },  -- not an emote verb
        -- N22 (Sprint 7a in-game): untargeted emotes carry no self-target token,
        -- so they must NOT capture. An earlier 7a draft captured untargeted
        -- /thanks and /cheer via a broadcast-verb rule; that rule is removed —
        -- these now sit alongside the untargeted /salute as non-capturing.
        { id = "untargeted_cheer",   text = "Bob cheers."          },  -- /cheer, no target
        { id = "untargeted_thanks",  text = "Bob thanks everyone." },  -- /thanks, no target
        { id = "untargeted_salute",  text = "Bob salutes."         },  -- /salute, no target
    },
}
