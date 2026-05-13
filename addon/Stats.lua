-- Counter aggregation and asymmetric-display logic.
--
-- Asymmetric display rule (load-bearing): surface only when reassuring.
--   - First-time encounter / first dungeon run: always surface (no history is
--     neutral, not catastrophizing).
--   - Wipe rate ≤ db.stats_threshold (default 30%): surface.
--   - Wipe rate > threshold: suppress silently. The user is never told their
--     wipe rate is "too high to surface" — that defeats the point.
--
-- Live-vs-invoked distinction: this module's OnEncounterStart /
-- OnChallengeModeStart drive automatic surfacing during play, gated by
-- db.stats_surface. User-invoked commands (/tox stats, /tox week, /tox stats
-- <dungeon>) ignore the surface toggle and the threshold — they print the
-- raw numbers because the user asked.

local _, ns = ...

local Stats = {}

local function db()
    return ns.Database and ns.Database:Get() or nil
end

local function out(line) print("[ToxFilter] " .. line) end

function Stats.shouldSurfaceWipeRate(rec, threshold_pct)
    if not rec then return true, "first_time" end
    local attempts = rec.attempts or 0
    if attempts == 0 then return true, "first_time" end
    local wiped = rec.wiped or 0
    local rate_pct = (wiped / attempts) * 100
    if rate_pct <= threshold_pct then return true, "ok" end
    return false, "suppressed"
end

-- Sprint 4 fix: bucket-aware wipe rate. attempts = wipes + completions for
-- the (instance, bucket) record; the old encounters[].attempts field is gone.
function Stats.shouldSurfaceBucket(rec, threshold_pct)
    if not rec then return true, "first_time" end
    local wipes       = rec.wipes or 0
    local completions = rec.completions or 0
    local attempts    = wipes + completions
    if attempts == 0 then return true, "first_time" end
    local rate_pct = (wipes / attempts) * 100
    if rate_pct <= threshold_pct then return true, "ok" end
    return false, "suppressed"
end

function Stats.formatBucketLine(bucket, rec)
    if not rec then
        return string.format("%s: no data", bucket)
    end
    local d = rec.deaths or 0
    local w = rec.wipes or 0
    local c = rec.completions or 0
    local attempts = w + c
    if attempts == 0 then
        return string.format("%s: %d deaths, no completions or wipes recorded", bucket, d)
    end
    local rate_pct = math.floor(((w / attempts) * 100) + 0.5)
    return string.format("%s: %d completed, %d wiped (%d%% wipe), %d deaths",
        bucket, c, w, rate_pct, d)
end

local BUCKET_DISPLAY_ORDER = { "normal", "heroic", "mythic", "M0", "M2-5", "M6-10", "M10+" }

function Stats.formatInstanceBlock(name, buckets)
    local lines = { name .. ":" }
    for _, b in ipairs(BUCKET_DISPLAY_ORDER) do
        local rec = buckets[b]
        if rec then
            lines[#lines + 1] = "  " .. Stats.formatBucketLine(b, rec)
        end
    end
    return lines
end

-- Sprint 4 fix3 (Issue 3 diagnostic): print the exact (instance, bucket) the
-- API reports at encounter/CM start when db.debug_enabled is true. Lets the
-- user reconcile their seeded instance string against what GetInstanceInfo()
-- actually returns at the moment the surfacing decision is made.
local function debugStart(g, instance, bucket)
    if not g.debug_enabled then return end
    print(string.format("[ToxFilter Debug] Encounter start in: '%s' bucket '%s'",
        instance or "?", bucket or "?"))
end

function Stats.OnEncounterStart(instance, bucket)
    local g = db(); if not g then return end
    debugStart(g, instance, bucket)
    if g.stats_surface == false then return end
    if not instance or not bucket then return end
    local rec = ns.Buffer and ns.Buffer:GetInstanceStats(instance, bucket) or nil
    local should = Stats.shouldSurfaceBucket(rec, g.stats_threshold or 30)
    if not should then return end
    if not rec then
        out("First attempt recorded for " .. instance .. " (" .. bucket .. ").")
        return
    end
    out(Stats.formatBucketLine(bucket, rec))
end

function Stats.OnChallengeModeStart(instance, bucket)
    local g = db(); if not g then return end
    debugStart(g, instance, bucket)
    if g.stats_surface == false then return end
    if not instance or not bucket then return end
    local rec = ns.Buffer and ns.Buffer:GetInstanceStats(instance, bucket) or nil
    local should = Stats.shouldSurfaceBucket(rec, g.stats_threshold or 30)
    if not should then return end
    if not rec then
        out("First run recorded for " .. instance .. " (" .. bucket .. ").")
        return
    end
    out(Stats.formatBucketLine(bucket, rec))
end

-- Computed from db.session_buffer.events.activity_log timestamps. Counters
-- alone don't carry per-event timestamps, so the activity log is the source
-- of truth for windowed aggregates.
function Stats.WeekSummary()
    local g = db(); if not g then return nil end
    local now_ts = (time and time()) or os.time()
    local cutoff = now_ts - 7 * 86400
    local log = g.session_buffer.events.activity_log or {}
    local completions, wipes, deaths, thanks = 0, 0, 0, 0
    for i = 1, #log do
        local e = log[i]
        if (e.ts or 0) >= cutoff then
            local k = e.type
            if     k == "encounter_completed" then completions = completions + 1
            elseif k == "encounter_wiped"     then wipes = wipes + 1
            elseif k == "death"                then deaths = deaths + 1
            elseif k == "thanks_received"      then thanks = thanks + 1 end
        end
    end
    return { completions = completions, wipes = wipes, deaths = deaths, thanks = thanks }
end

ns.Stats = Stats
