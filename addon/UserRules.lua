-- User-managed blacklist / whitelist.
--
-- Storage: db.blacklist and db.whitelist are maps keyed by FNV-1a hash with
-- the *normalized* token text as value (post Normalize.normalize). This means
-- /tox blacklist add Foo and /tox blacklist add foo collapse to the same
-- entry, and /tox blacklist list shows the canonical normalized form. The
-- user only ever sees and removes by what they typed, but the table identity
-- is the hash, matching the hot-path lookup shape of RuleData.
--
-- Runtime integration lives in RuleEngine.classify: lookups consult
-- ns.UserRules.blacklistEntry / whitelistEntry, both of which return nil when
-- ns.Database isn't wired (e.g. the corpus harness), so the rule engine path
-- is byte-identical for tests.

local _, ns = ...

local UserRules = {}

local function ensureLists()
    local db = ns.Database and ns.Database:Get()
    if not db then return nil end
    db.blacklist = db.blacklist or {}
    db.whitelist = db.whitelist or {}
    return db
end

-- Returns hash, normalized for a user-entered token, or nil if it normalizes
-- to empty (all punctuation, whitespace, etc).
local function hashOf(word)
    if type(word) ~= "string" then return nil end
    local normalized = ns.Normalize.normalize(word)
    if normalized == "" then return nil end
    return ns.Hash.fnv1a(normalized), normalized
end

local function add(listName, word)
    local db = ensureLists()
    if not db then return false, "no_db" end
    local hash, normalized = hashOf(word)
    if not hash then return false, "empty" end
    local list = db[listName]
    if list[hash] then return false, "duplicate", normalized end
    list[hash] = normalized
    return true, nil, normalized
end

local function remove(listName, word)
    local db = ensureLists()
    if not db then return false, "no_db" end
    local hash, normalized = hashOf(word)
    if not hash then return false, "empty" end
    local list = db[listName]
    if not list[hash] then return false, "absent", normalized end
    list[hash] = nil
    return true, nil, normalized
end

local function list(listName)
    local db = ensureLists()
    if not db then return {} end
    local out = {}
    for _, plaintext in pairs(db[listName]) do
        out[#out + 1] = plaintext
    end
    table.sort(out)
    return out
end

local function count(listName)
    local db = ensureLists()
    if not db then return 0 end
    local n = 0
    for _ in pairs(db[listName]) do n = n + 1 end
    return n
end

-- Hot-path lookup. Returns plaintext if hash is in the named list, else nil.
local function entry(listName, hash)
    local db = ensureLists()
    if not db then return nil end
    return db[listName][hash]
end

UserRules.add              = add
UserRules.remove           = remove
UserRules.list             = list
UserRules.count            = count
UserRules.blacklistEntry   = function(hash) return entry("blacklist", hash) end
UserRules.whitelistEntry   = function(hash) return entry("whitelist", hash) end

ns.UserRules = UserRules
