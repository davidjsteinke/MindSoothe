-- Sprint 7a (F4) emote parsing. Pure Lua, loaded by scripts/run-corpus.sh.
-- Exercises PositiveCapture.emoteDetect on rendered emote text.
--
-- Scope of this harness: emoteDetect's keyword + self-target logic only. The
-- following are IN-GAME-ONLY and cannot be exercised here:
--   * the CHAT_MSG_TEXT_EMOTE event firing and its exact arg layout;
--   * whether enUS targeted emotes actually render "you" (assumed by design);
--   * the self-sender guard (own outgoing emote skipped) — it lives in
--     captureEmote, which needs Buffer/Database the detect harness does not load;
--   * the Uplifter category gate around captureEmote (covered by the 5d gating).
--
-- emoteDetect is enUS-only by construction (English emote verbs + "you"/"your");
-- other locales are a documented limitation, not a silent gap.

return {
    -- emoteDetect must return non-nil (a positive emote: aimed at the player, or
    -- an untargeted /thanks or /cheer broadcast to the room).
    positive_cases = {
        { id = "thanks_you",       text = "Bob thanks you."        },  -- targeted
        { id = "salutes_you",      text = "Carol salutes you."     },  -- targeted
        { id = "cheers_at_you",    text = "Dave cheers at you."    },  -- targeted
        { id = "untargeted_cheer", text = "Bob cheers."            },  -- /cheer, no target
        { id = "untargeted_thanks", text = "Bob thanks everyone."  },  -- /thanks, no target
    },

    -- emoteDetect must return nil.
    negative_cases = {
        { id = "third_party",        text = "Bob cheers at Carol." },  -- cheer aimed elsewhere
        { id = "verb_not_emote",     text = "Bob dances with you." },  -- self-target, wrong verb
        { id = "untargeted_salute",  text = "Bob salutes."         },  -- not a broadcast verb
        { id = "untargeted_dance",   text = "Bob dances."          },  -- not an emote verb
    },
}
