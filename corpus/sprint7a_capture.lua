-- Sprint 7b bugfix corpus: positive-moment RECORD narrowing + TINT breadth.
--
-- The bug: typed praise the user SENT (outgoing, echoed back as group chat) and
-- praise between two OTHER players (third-party) were both recorded to the
-- /tox positive log. Only praise DIRECTED AT the user, sent by SOMEONE ELSE,
-- should record. The green tint, by contrast, stays broad for others' positivity
-- but must NOT fire on the user's own outgoing lines.
--
-- Each case asserts two booleans, derived in the harness from the REAL capture()
-- (record) and the chatFilter tint rule (a tint target exists — recorded moment
-- or a broad detect() — AND not isSelfSender(sender)):
--   * recorded — capture() wrote a /tox positive row (real Buffer + PIIScrub).
--   * tinted   — the chat line would be green-tinted.
-- A case may add scrub_absent = "<token>" to assert the recorded body no longer
-- contains that (lowercased) substring.
--
-- Player: UnitName("player") = "Manehealer"; default role healer.

return {
    player = "Manehealer",
    role   = "healer",
    cases = {
        -- Outgoing: the user thanking someone else, echoed back as group chat.
        -- Self sender → neither recorded nor tinted (self gets neither).
        { id = "outgoing_not_recorded", sender = "Manehealer",
          input = "thanks dingles", recorded = false, tinted = false },

        -- Third-party: sender and target both someone else. Not directed at the
        -- user → not recorded; but it IS others' positivity → tinted.
        { id = "third_party_tint_only", sender = "Dingles",
          input = "thanks garrick", recorded = false, tinted = true },

        -- Directed at the user by role match (user is healer). Recorded + tinted.
        { id = "direct_role_recorded", sender = "Dingles", role = "healer",
          input = "thanks healer", recorded = true, tinted = true },

        -- Directed at the user by name. Recorded + tinted; own name scrubbed.
        { id = "direct_name_recorded", sender = "Dingles",
          input = "thanks manehealer", recorded = true, tinted = true,
          scrub_absent = "manehealer" },

        -- Direct role match BUT sent by the user themselves (user is healer,
        -- "thanks healer"). Self-skip beats direct → neither recorded nor tinted.
        -- Locks in "self gets neither" alongside the third-party tint-only case.
        { id = "direct_but_self_neither", sender = "Manehealer", role = "healer",
          input = "thanks healer", recorded = false, tinted = false },
    },
}
