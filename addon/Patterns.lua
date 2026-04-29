-- Pattern data for the constructive-vs-hostile classifier.
-- Pure data; no logic. Sets are keyed by normalized token; phrase triggers are
-- sequences of normalized tokens.

local _, ns = ...

local function set(list)
    local s = {}
    for i = 1, #list do s[list[i]] = true end
    return s
end

ns.Patterns = {
    -- Role nouns and class shorthand. Spec adjectives that overlap with mechanic
    -- words (fire, frost, shadow, holy, arcane) are intentionally absent — they
    -- live in TACTICAL_MARKERS instead. Acceptable Sprint 2 false-negative on
    -- "fire mage"-style spec-name attacks.
    ROLE_NOUNS = set({
        "tank", "healer", "dps",
        "mage", "warrior", "paladin", "druid", "priest", "hunter", "warlock",
        "monk", "rogue", "shaman", "demonhunter", "deathknight", "evoker",
        "dk", "dh", "lock", "pally", "sham", "hunt",
        "ret", "prot", "disc", "resto", "balance", "feral", "guardian",
        "fury", "arms", "ele", "enh", "surv", "mm", "bm",
        "aff", "demo", "destro", "ww", "mw", "bdk", "fdk", "udk",
    }),

    -- Personal-attack modifiers. Per Sprint 2 design these only fire as
    -- triggers when paired with a role-noun or you-pronoun in the same window
    -- with no intervening tactical token. So "fucking move out of fire" stays
    -- pass-through; "fucking trash tank" fires role_attack.
    NEG_MODIFIERS = set({
        "trash", "garbage", "garbo", "awful", "terrible", "worst",
        "useless", "pathetic", "idiot", "moron", "stupid", "dumb",
        "braindead", "retarded", "dogshit", "dogwater", "washed",
        "bot", "npc", "brick", "hardstuck", "boosted",
        "shit", "shitty", "suck", "sucks", "ass", "cheeks",
    }),

    -- Profane intensifiers. Absorbed into an attack span when adjacent, but
    -- never sufficient on their own.
    INTENSIFIERS = set({
        "fucking", "fkn", "fking", "fuckin", "goddamn", "damn",
    }),

    -- "You"-class pronouns post-normalization. "you're" → "youre" since
    -- normalization strips apostrophes.
    YOU_PRONOUNS = set({
        "you", "u", "ur", "youre", "your", "yourself", "ya",
    }),

    -- Neutral fillers eligible for absorption into an adjacent attack span.
    NEUTRAL_FILLERS = set({
        "a", "an", "the", "of", "is", "are", "am", "was", "were", "be", "been",
        "this", "that", "those", "these",
    }),

    -- Mechanic, position, imperative, status tactical content.
    TACTICAL_MARKERS = set({
        -- Mechanics
        "fire", "void", "swirly", "swirlies", "puddle", "puddles",
        "dispel", "interrupt", "kick", "stun", "purge", "cleanse",
        "soak", "bait", "pop", "cd", "cooldown", "lust", "hero",
        "bloodlust", "taunt", "cast", "casting",
        -- Direction / position
        "move", "out", "away", "behind", "into", "stack", "spread",
        "left", "right", "north", "south", "front", "back", "up", "down",
        -- Numeric / status markers
        "low", "oom", "topped", "soon", "now", "incoming", "inc",
    }),

    -- Tokens that, when paired with antonymic praise, signal sarcasm. Some
    -- entries (hero) overlap with TACTICAL_MARKERS; that's resolved by context
    -- — the antonymic-praise pattern only fires after great/nice/good + job/etc.
    INTELLIGENCE_MOCKING = set({
        "genius", "einstein", "mastermind", "rockstar", "legend",
        "champ", "hero", "mvp", "goat", "ace", "prodigy", "boss",
    }),

    -- Antonymic-praise leading words (token i).
    ANTONYMIC_PRAISE_FIRST = set({"great", "nice", "good", "well", "way"}),
    -- Following words (token i+1).
    ANTONYMIC_PRAISE_SECOND = set({
        "job", "play", "work", "one", "move", "done", "to", "going",
    }),

    -- Passive-aggressive thanks.
    PASSIVE_THANKS_FIRST = set({"thanks", "thx", "ty", "tysm", "thank"}),
    PASSIVE_THANKS_NEG = set({
        "wipe", "wipes", "death", "deaths", "pull", "pulling", "aggro",
        "carry", "heal", "heals", "dispel", "whatever", "nothing",
    }),

    -- Conditional-blame phrase triggers (sequences of normalized tokens).
    CONDITIONAL_BLAME_TRIGGERS = {
        {"maybe", "try"},
        {"maybe", "just"},
        {"have", "you", "tried"},
        {"ever", "heard", "of"},
    },
}

-- Numeric-tactical predicate: percentages, plain numbers.
ns.Patterns.is_numeric_tactical = function(token)
    if not token or token == "" then return false end
    if token:match("^%d+$") then return true end
    if token:match("^%d+%%$") then return true end
    return false
end
