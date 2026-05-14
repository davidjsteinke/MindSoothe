-- ToxFilter persistence layer.
-- AceDB-3.0 is the storage backend; an explicit migrations[] table layers
-- schema-version migrations on top because explicit/readable beats implicit
-- defaults-merging for long-term maintainability across sprints.
--
-- Sprint 3 surfaces only the global (account-wide) scope. Profiles are not
-- exposed in the slash UI but the door is open: a future sprint can add
-- defaults.profile = {...} and a /tox profile command without rewriting this
-- module's wiring.

local _, ns = ...

local LATEST_SCHEMA_VERSION = 6

-- Schema. Anything user-overridable is named here so a fresh install lands at
-- the latest version already populated. handling[<cat>] left absent on purpose:
-- nil means "use Categories.HANDLING default" — set/clear is symmetric.
--
-- NOTE: schema_version is intentionally NOT in DEFAULTS. AceDB strips values
-- equal to their default at logout; if we declared a default of 1, then later
-- bumped LATEST to 2, an existing v1 user's stored value would be missing
-- (stripped) and reads would resolve to 2 (the new default) — silently
-- skipping migrations[2]. Database:Init() writes schema_version explicitly on
-- first init so it's always physically present in SavedVariables.
local DEFAULTS = {
    global = {
        enabled        = true,
        -- Channels: `party` is intentionally absent here. WoW retail no longer
        -- routes /p as a separate channel; CHAT_MSG_PARTY events fold into
        -- `instance`. The slash UI still accepts `party` as an input alias
        -- (Sprint 4 fix Issue 2); the canonical key is `instance`.
        channels = {
            raid         = true,
            instance     = true,
            battleground = true,
            whisper      = false,
        },
        handling = {},
        role                = "auto",
        role_last_seen      = nil,
        blacklist           = {},
        whitelist           = {},
        whisper_intro_shown = false,

        -- Sprint 4a: affirmative-features config. Substructure inside
        -- session_buffer / pinned_moments is shaped by Buffer:Init at runtime
        -- rather than declared here, so AceDB's defaults merge doesn't
        -- recreate counters tables on every login.
        retention_days   = 30,
        grounding_items  = {},
        stats_threshold  = 30,
        stats_surface    = true,
        positive_ui      = false,

        -- Sprint 4b: visual UI + ready orchestration. Position is account-wide
        -- (UI choice, not character choice). breathe_position is left absent on
        -- purpose so an unmoved frame anchors via SetPoint("CENTER") rather
        -- than a stale offset.
        breathe_cycles = 4,
        breathe_count  = 4,
        ready_config = {
            include = { grounding = true, breathing = true, lift = true },
            order   = { "grounding", "breathing", "lift" },
        },

        -- Sprint 4 fix: developer flag, hidden from /tox help. When false,
        -- /tox debug pretends to be an unknown command (only /tox debug
        -- enable always works, to flip the flag).
        debug_enabled = false,

        -- Sprint 5: tactical role-callout prioritization. Master off by
        -- default (opt-in, same default as Sprint 4b's positive_ui). When
        -- master is on, the sub-toggles default true; users in voice chat can
        -- disable callout_sound while keeping callout_ui.
        callout_enabled = false,
        callout_ui      = true,
        callout_sound   = true,

        session_buffer = {},
        pinned_moments = {},
        stats          = {},
        feedback_log   = {},
    },
}

-- Migration N: db at version (N-1) → version N. AceDB stores SavedVariables
-- whose schema_version we set here; future sprints append entries. Never
-- retroactively edit a committed migration.
local migrations = {
    [1] = function(_db) end, -- Sprint 3 ships v1 as the baseline; nothing to migrate from.
    [2] = function(g)
        -- Sprint 4a fields. AceDB DEFAULTS handles fresh installs at v2; this
        -- migration backfills existing v1 users.
        if g.retention_days  == nil then g.retention_days  = 30  end
        if g.grounding_items == nil then g.grounding_items = {}  end
        if g.stats_threshold == nil then g.stats_threshold = 30  end
        if g.stats_surface   == nil then g.stats_surface   = true end
        if g.positive_ui     == nil then g.positive_ui     = false end
    end,
    [3] = function(g)
        -- Sprint 4b: backfill visual UI + ready orchestration settings for
        -- existing v2 users. breathe_position is intentionally left nil so the
        -- frame anchors center until the user moves it.
        if g.breathe_cycles == nil then g.breathe_cycles = 4 end
        if g.breathe_count  == nil then g.breathe_count  = 4 end
        if g.ready_config   == nil then
            g.ready_config = {
                include = { grounding = true, breathing = true, lift = true },
                order   = { "grounding", "breathing", "lift" },
            }
        end
    end,
    [4] = function(g)
        -- Sprint 4 fix:
        --   * debug_enabled: developer flag, default off.
        --   * channels: party folds into instance with OR semantics. WoW
        --     retail no longer routes /p separately; the alias is purely an
        --     input convenience now.
        --   * counters: shape rebuild from (encounterID, difficultyID) and
        --     (mapID) keys to (instance_name, difficulty_bucket). The old
        --     counters mixed BG/world/dungeon deaths because PLAYER_DEAD had
        --     no scope filter; the data was test data and is discarded so
        --     fresh recording can begin under the corrected shape. Session
        --     history is preserved (not affected by the scope bug). Pinned
        --     moments are unaffected.
        if g.debug_enabled == nil then g.debug_enabled = false end

        if g.channels then
            local p = g.channels.party
            if p ~= nil then
                local i = g.channels.instance
                -- OR semantics: if either was on, merged is on. nil treated
                -- as "default true" to match the original DEFAULTS.
                local p_on = (p ~= false)
                local i_on = (i == nil) or (i ~= false)
                g.channels.instance = p_on or i_on
                g.channels.party = nil
            end
        end

        if g.session_buffer and g.session_buffer.counters then
            local sessions = g.session_buffer.counters.sessions
            g.session_buffer.counters = {
                instances    = {},
                sessions     = sessions or { history = {} },
                thanks_total = g.session_buffer.counters.thanks_total or 0,
            }
            print("[ToxFilter] Migrating counter schema. Previous counter data is reset due to scope changes.")
        end
    end,
    [5] = function(g)
        -- Sprint 4 fix2 (F18): pre-release re-arm of the whisper privacy
        -- intro. Prior testing flipped this bit to true; AceDB only strips
        -- values equal to default, so true persisted across reloads. Force
        -- false here so existing testers see the privacy note on next
        -- /tox channel whisper on. One-shot reset; safe to drop after launch.
        g.whisper_intro_shown = false
    end,
    [6] = function(g)
        -- Sprint 5: tactical role-callout fields. Master off by default;
        -- sub-toggles default true so flipping the master on gets the full
        -- feature without a second slash command.
        if g.callout_enabled == nil then g.callout_enabled = false end
        if g.callout_ui      == nil then g.callout_ui      = true  end
        if g.callout_sound   == nil then g.callout_sound   = true  end
    end,
}

local function applyMigrations(g)
    local current = g.schema_version or 0
    if current >= LATEST_SCHEMA_VERSION then return end
    for v = current + 1, LATEST_SCHEMA_VERSION do
        local fn = migrations[v]
        if fn then
            local ok, err = pcall(fn, g)
            if not ok then
                print("[ToxFilter] Migration to schema_version=" .. v
                      .. " failed (" .. tostring(err) .. "). Settings preserved at v"
                      .. tostring(g.schema_version or 0) .. ".")
                return
            end
        end
        g.schema_version = v
    end
end

local Database = {}

local function freshDB()
    _G.ToxFilterDB = nil
    return LibStub("AceDB-3.0"):New("ToxFilterDB", DEFAULTS, true)
end

function Database:Init()
    -- Belt-and-suspenders: if the SavedVariables global loaded as a non-table
    -- (corrupted file persisted past WoW's own parse step), AceDB:New would
    -- error. Reset to defaults and continue rather than crashing the addon.
    local existing = _G.ToxFilterDB
    if existing ~= nil and type(existing) ~= "table" then
        print("[ToxFilter] Settings file corrupted, resetting to defaults.")
        _G.ToxFilterDB = nil
    end

    local ok, dbObj = pcall(LibStub("AceDB-3.0").New, LibStub("AceDB-3.0"), "ToxFilterDB", DEFAULTS, true)
    if not ok or type(dbObj) ~= "table" then
        print("[ToxFilter] Settings file corrupted, resetting to defaults.")
        dbObj = freshDB()
    end

    self.acedb = dbObj
    self.db    = dbObj.global

    -- Fresh install: stamp schema_version explicitly so future LATEST bumps
    -- can detect "user is at v1, need to run migrations[2..N]" reliably.
    if self.db.schema_version == nil then
        self.db.schema_version = LATEST_SCHEMA_VERSION
    end

    applyMigrations(self.db)
    return self
end

function Database:Get() return self.db end

-- "auto" resolves to the current spec role at read time; cached in
-- role_last_seen for the login window where the spec API returns nil.
-- WoW API contract (verified Sprint 3 fix1): GetSpecializationRole takes a
-- specGroupIndex from GetSpecialization(); calling it with no args throws
-- "Usage: GetSpecializationRole(specGroupIndex)". GetSpecialization() can
-- return nil for low-level chars or during the brief window before spec data
-- loads at login — both fall through to role_last_seen.
local ROLE_API_MAP = { TANK = "tank", HEALER = "healer", DAMAGER = "dps" }

function Database:GetEffectiveRole()
    local r = self.db.role or "auto"
    if r ~= "auto" then return r end
    if type(GetSpecialization) == "function"
       and type(GetSpecializationRole) == "function" then
        local specIndex = GetSpecialization()
        if specIndex then
            local apiRole = GetSpecializationRole(specIndex)
            local mapped  = apiRole and ROLE_API_MAP[apiRole]
            if mapped then
                self.db.role_last_seen = mapped
                return mapped
            end
        end
    end
    return self.db.role_last_seen
end

-- One-shot whisper privacy intro. Returns true on the call that flips the bit.
function Database:NoteWhisperIntroIfNeeded()
    if self.db.whisper_intro_shown then return false end
    self.db.whisper_intro_shown = true
    return true
end

-- Soft-disabled detection for /tox status: every category resolved to "pass"
-- means filtering won't visibly fire even though `enabled` is true.
function Database:AllCategoriesPass()
    local Categories = ns.Categories
    if not Categories then return false end
    for cat, defaultHandling in pairs(Categories.HANDLING) do
        local override = self.db.handling[cat]
        local effective = override or defaultHandling
        if effective ~= "pass" then return false end
    end
    return true
end

-- Override resolver for RuleEngine.classify and downstream dispatch. Returns
-- the user-overridden handling for a category, falling back to the default.
function Database:ResolveHandling(category)
    if not category then return nil end
    local override = self.db.handling[category]
    if override then return override end
    return ns.Categories.HANDLING[category]
end

ns.Database = Database
