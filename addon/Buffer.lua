-- Session buffer: counters (permanent) + events (windowed) + session lifecycle.
-- Pure read/write/prune operations on db.session_buffer and db.pinned_moments;
-- no UI, no chat output. Callers (Stats, PositiveCapture, ToxFilter event
-- handlers, Commands) own the formatting.
--
-- Storage philosophy:
--   - Counters (per-encounter, per-dungeon, per-session) are aggregated and
--     permanent. Bumped on every event; never pruned.
--   - Events (positive_moments, flagged_events, activity_log) are windowed.
--     Pruned on addon load using db.retention_days (default 30).
--   - Pinned moments live in db.pinned_moments, separate from events, so
--     retention pruning never touches them. Capped at PINNED_CAP.
--
-- Session lifecycle: each addon load resumes the previous "current" session
-- if its last_activity_at is within SESSION_RESUME_WINDOW_S; otherwise the
-- previous current is archived to history and a new one begins. /reload
-- doesn't reset session counters during normal play.
--
-- All chat content is run through ns.PIIScrub before storage.

local _, ns = ...

local SESSION_RESUME_WINDOW_S = 60 * 60
local SESSION_HISTORY_CAP     = 20
local PINNED_CAP              = 100

local Buffer = {}

local function db()
    return ns.Database and ns.Database:Get() or nil
end

local function now_ts()
    return (time and time()) or os.time()
end

-- Counter shape, post Sprint 4 fix v4 schema:
--   counters.instances[<name>][<bucket>] = { deaths, wipes, completions, last_event }
-- where <name> is GetInstanceInfo()'s instance name and <bucket> is one of
--   normal | heroic | mythic | M0 | M2-5 | M6-10 | M10+
-- locked at run start by ToxFilter.lua and read back here at record time.
--
-- The old encounters[encounterID][difficultyID] and dungeons[mapID] tables and
-- the global deaths_total were removed in v4 — they conflated BG/world/dungeon
-- scope. thanks_total is preserved (positive-moment-derived, separate scope).
local function ensureShape(g)
    g.session_buffer = g.session_buffer or {}
    local sb = g.session_buffer
    sb.counters = sb.counters or {}
    sb.counters.instances  = sb.counters.instances or {}
    sb.counters.sessions   = sb.counters.sessions or {}
    sb.counters.sessions.history = sb.counters.sessions.history or {}
    sb.counters.thanks_total = sb.counters.thanks_total or 0
    sb.events = sb.events or {}
    sb.events.positive_moments = sb.events.positive_moments or {}
    sb.events.flagged_events   = sb.events.flagged_events or {}
    sb.events.activity_log     = sb.events.activity_log or {}
    sb.next_pm_id = sb.next_pm_id or 1
    g.pinned_moments = g.pinned_moments or {}
end

local function ensureInstanceRec(g, instance, bucket)
    local instances = g.session_buffer.counters.instances
    instances[instance] = instances[instance] or {}
    instances[instance][bucket] = instances[instance][bucket]
        or { deaths = 0, wipes = 0, completions = 0 }
    return instances[instance][bucket]
end

local function newSession(t)
    return {
        started_at           = t,
        last_activity_at     = t,
        encounters_completed = 0,
        encounters_wiped     = 0,
        deaths               = 0,
        thanks_received      = 0,
    }
end

local function archiveCurrent(sessions)
    local cur = sessions.current
    if not cur then return end
    local hist = sessions.history
    hist[#hist + 1] = cur
    while #hist > SESSION_HISTORY_CAP do table.remove(hist, 1) end
    sessions.current = nil
end

function Buffer:Init()
    local g = db()
    if not g then return self end
    ensureShape(g)

    local t = now_ts()
    local sessions = g.session_buffer.counters.sessions
    local cur = sessions.current
    if cur and cur.last_activity_at and (t - cur.last_activity_at) <= SESSION_RESUME_WINDOW_S then
        cur.last_activity_at = t
    else
        archiveCurrent(sessions)
        sessions.current = newSession(t)
    end

    self:Prune(g.retention_days or 30)
    return self
end

local function touchSession(g)
    local cur = g.session_buffer.counters.sessions.current
    if cur then cur.last_activity_at = now_ts() end
end

local function pruneList(list, cutoff)
    local kept = {}
    for i = 1, #list do
        if (list[i].ts or 0) >= cutoff then kept[#kept + 1] = list[i] end
    end
    return kept
end

function Buffer:Prune(retention_days)
    local g = db(); if not g then return end
    local cutoff = now_ts() - (retention_days or 30) * 86400
    local sb = g.session_buffer
    sb.events.positive_moments = pruneList(sb.events.positive_moments, cutoff)
    sb.events.flagged_events   = pruneList(sb.events.flagged_events, cutoff)
    sb.events.activity_log     = pruneList(sb.events.activity_log, cutoff)
end

local function logActivity(g, kind)
    table.insert(g.session_buffer.events.activity_log, { ts = now_ts(), type = kind })
end

-- Sprint 4 fix3 (Issue 2 diagnostic): print every counter increment when
-- db.debug_enabled is true. Zero-cost for normal users; lets us trace whether
-- counters move outside instance scope (open-world deaths, zone changes, etc.)
-- by watching chat output in real time. Increment site responsibility: pass
-- the resolved (instance, bucket, field) that just changed.
local function debugIncrement(g, instance, bucket, field)
    if not g.debug_enabled then return end
    print(string.format(ns.Const.DEBUG_PREFIX .. "Counter increment: %s / %s / %s",
        instance or "?", bucket or "?", field or "?"))
end

function Buffer:RecordPositiveMoment(text, signals, direct_to_user, sender)
    local g = db(); if not g then return nil end
    local scrubbed = ns.PIIScrub and ns.PIIScrub.scrub(text, sender) or text
    local id = string.format("pm_%03d", g.session_buffer.next_pm_id)
    g.session_buffer.next_pm_id = g.session_buffer.next_pm_id + 1
    local moment = {
        id             = id,
        ts             = now_ts(),
        text           = scrubbed,
        signals        = signals or {},
        direct_to_user = direct_to_user and true or false,
    }
    table.insert(g.session_buffer.events.positive_moments, moment)
    if direct_to_user then
        g.session_buffer.counters.thanks_total = (g.session_buffer.counters.thanks_total or 0) + 1
        local cur = g.session_buffer.counters.sessions.current
        if cur then cur.thanks_received = (cur.thanks_received or 0) + 1 end
        logActivity(g, "thanks_received")
    end
    touchSession(g)
    return moment
end

-- Sprint 7a (F1): `combat` flags a record dropped during the combat pause. Like
-- every flagged event it stores classification metadata (category, severity)
-- only — never the message body. Combat drops are pure third-party hostility and
-- the body must not be retained; this matches the non-combat silent path and
-- does not exceed it.
function Buffer:RecordFlaggedEvent(category, severity, combat)
    local g = db(); if not g then return end
    local rec = { ts = now_ts(), category = category, severity = severity or 5 }
    if combat then rec.combat = true end
    table.insert(g.session_buffer.events.flagged_events, rec)
    touchSession(g)
end

-- Sprint 4 fix: encounter/death/challenge-mode recording is keyed by
-- (instance_name, difficulty_bucket). The bucket is derived once at run start
-- by ToxFilter.lua and threaded through every record call so that all events
-- inside a run land in the same cell — including PLAYER_DEAD that fires
-- between pulls and CHALLENGE_MODE_COMPLETED whose difficultyID API isn't
-- meaningful for keystone runs.
function Buffer:RecordEncounter(instance, bucket, success)
    local g = db(); if not g then return end
    if not instance or not bucket then return end
    local rec = ensureInstanceRec(g, instance, bucket)
    rec.last_event = now_ts()
    local cur = g.session_buffer.counters.sessions.current
    if success then
        rec.completions = (rec.completions or 0) + 1
        if cur then cur.encounters_completed = (cur.encounters_completed or 0) + 1 end
        logActivity(g, "encounter_completed")
        debugIncrement(g, instance, bucket, "completions")
    else
        rec.wipes = (rec.wipes or 0) + 1
        if cur then cur.encounters_wiped = (cur.encounters_wiped or 0) + 1 end
        logActivity(g, "encounter_wiped")
        debugIncrement(g, instance, bucket, "wipes")
    end
    touchSession(g)
end

-- PLAYER_DEAD scope filter is the caller's job (ToxFilter.lua only invokes
-- this when GetInstanceInfo's instanceType is party or raid). No bucket means
-- the caller couldn't resolve one — the death is simply not counted, matching
-- the design call to skip non-instance deaths entirely.
function Buffer:RecordDeath(instance, bucket)
    local g = db(); if not g then return end
    if not instance or not bucket then return end
    local rec = ensureInstanceRec(g, instance, bucket)
    rec.deaths = (rec.deaths or 0) + 1
    rec.last_event = now_ts()
    local cur = g.session_buffer.counters.sessions.current
    if cur then cur.deaths = (cur.deaths or 0) + 1 end
    logActivity(g, "death")
    debugIncrement(g, instance, bucket, "deaths")
    touchSession(g)
end

function Buffer:RecordChallengeMode(instance, bucket, completed)
    local g = db(); if not g then return end
    if not instance or not bucket then return end
    local rec = ensureInstanceRec(g, instance, bucket)
    rec.last_event = now_ts()
    if completed then
        rec.completions = (rec.completions or 0) + 1
        local cur = g.session_buffer.counters.sessions.current
        if cur then cur.encounters_completed = (cur.encounters_completed or 0) + 1 end
        logActivity(g, "encounter_completed")
        debugIncrement(g, instance, bucket, "completions")
    end
    touchSession(g)
end

function Buffer:GetInstanceStats(instance, bucket)
    local g = db(); if not g then return nil end
    local rec = g.session_buffer.counters.instances[instance]
    if not rec then return nil end
    return rec[bucket]
end

function Buffer:GetInstanceBuckets(instance)
    local g = db(); if not g then return nil end
    return g.session_buffer.counters.instances[instance]
end

function Buffer:GetAllInstances()
    local g = db(); if not g then return {} end
    return g.session_buffer.counters.instances
end

function Buffer:GetSessionCurrent()
    local g = db(); if not g then return nil end
    return g.session_buffer.counters.sessions.current
end

function Buffer:GetActivityLog()
    local g = db(); if not g then return {} end
    return g.session_buffer.events.activity_log
end

function Buffer:GetPositiveMoments(limit)
    local g = db(); if not g then return {} end
    local pm = g.session_buffer.events.positive_moments
    local n = #pm
    limit = limit or 10
    local startIdx = math.max(1, n - limit + 1)
    local out = {}
    for i = startIdx, n do out[#out + 1] = pm[i] end
    return out
end

function Buffer:GetMostRecentPositiveMoment()
    local g = db(); if not g then return nil end
    local pm = g.session_buffer.events.positive_moments
    return pm[#pm]
end

local function findMoment(g, id)
    for i = 1, #g.session_buffer.events.positive_moments do
        local m = g.session_buffer.events.positive_moments[i]
        if m.id == id then return m end
    end
    return nil
end

local function pinnedCount(g)
    local n = 0
    for _ in pairs(g.pinned_moments) do n = n + 1 end
    return n
end

local function evictOldestPinned(g)
    local oldest_id, oldest_at
    for pid, m in pairs(g.pinned_moments) do
        local at = m.pinned_at or 0
        if not oldest_at or at < oldest_at then
            oldest_id, oldest_at = pid, at
        end
    end
    if oldest_id then g.pinned_moments[oldest_id] = nil end
    return oldest_id
end

function Buffer:Pin(id)
    local g = db(); if not g then return nil, "no_db" end
    if g.pinned_moments[id] then return nil, "already_pinned" end
    local found = findMoment(g, id)
    if not found then return nil, "not_found" end

    local evicted_id = nil
    if pinnedCount(g) >= PINNED_CAP then
        evicted_id = evictOldestPinned(g)
    end

    g.pinned_moments[id] = {
        id             = found.id,
        ts             = found.ts,
        text           = found.text,
        signals        = found.signals,
        direct_to_user = found.direct_to_user,
        pinned_at      = now_ts(),
    }
    return g.pinned_moments[id], nil, evicted_id
end

function Buffer:Unpin(id)
    local g = db(); if not g then return nil, "no_db" end
    if not g.pinned_moments[id] then return nil, "not_found" end
    g.pinned_moments[id] = nil
    return true
end

function Buffer:GetPinned()
    local g = db(); if not g then return {} end
    local list = {}
    for _, m in pairs(g.pinned_moments) do list[#list + 1] = m end
    table.sort(list, function(a, b) return (a.ts or 0) < (b.ts or 0) end)
    return list
end

Buffer.PINNED_CAP              = PINNED_CAP
Buffer.SESSION_RESUME_WINDOW_S = SESSION_RESUME_WINDOW_S

ns.Buffer = Buffer
