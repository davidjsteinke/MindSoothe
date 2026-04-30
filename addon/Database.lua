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

local LATEST_SCHEMA_VERSION = 1

-- Sprint 3 schema (top-level v1). Anything user-overridable is named here so a
-- fresh install lands at v1 already populated. handling[<cat>] left absent on
-- purpose: nil means "use Categories.HANDLING default" — set/clear is symmetric.
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
        channels = {
            party        = true,
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

        -- Reserved for future sprints. Empty table values keep AceDB's defaults
        -- merge from re-creating them on every login.
        session_buffer = {},
        pinned_moments = {},
        stats          = {},
        feedback_log   = {},
    },
}

-- Migration N: db at version (N-1) → version N. AceDB stores SavedVariables
-- whose schema_version we set here; future sprints append entries.
local migrations = {
    [1] = function(_db) end, -- Sprint 3 ships v1 as the baseline; nothing to migrate from.
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
