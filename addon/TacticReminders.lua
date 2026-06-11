-- Sprint 5b: pre-encounter role-filtered tactical reminders.
--
-- At ENCOUNTER_START, look up the encounter in JournalData and surface the
-- 2-3 most critical mechanics for the user's effective role. First-attempt-
-- only per session: a (instance, encounter, bucket) triple that's already
-- surfaced this session stays silent until /tox reminders reset or /reload.
--
-- Architectural principle: this is pre-pull factual data, not real-time
-- tactical guidance during combat (that's Sprint 5's Callout). Display only,
-- no audio. The user reads the reminder in the first ~1-2 seconds of the
-- encounter window — ENCOUNTER_START fires AT engage, not strictly before.
--
-- Gating order (Surface):
--   1. db.tactic_reminders_enabled == false   → silent
--   2. isPaused()                              → silent (defensive; natural
--                                                  caller pre-pause)
--   3. effective role nil                      → silent (defer; next event
--                                                  re-checks)
--   4. instance not in JournalData             → silent
--   5. encounter not in instance               → silent
--   6. (instance|encounter|bucket) seen        → silent
--   7. mechanics list empty for role+bucket    → silent
--   8. emit role-specific block; mark seen
--
-- Diagnostic prints (gated on db.debug_enabled): mirror Sprint 4 fix3 /
-- Sprint 5 fix precedent. Surface logs the gating outcome at each early-
-- return so future investigations are self-evident without re-instrumenting.

local _, ns = ...

local TacticReminders = {}

local SEEN_DELIM = "|"

local function db()
    return ns.Database and ns.Database:Get() or nil
end

local function out(line) print("[ToxFilter] " .. line) end

local function isPaused()
    return ns.ToxFilterState and ns.ToxFilterState.isPaused() or false
end

local function dprint(line)
    local g = db()
    if g and g.debug_enabled then
        print("[ToxFilter Debug] " .. line)
    end
end

-- Compose the seen-key. Underscore-free instance/encounter names contain
-- spaces; pipe is a stable delimiter that does not appear in instance or
-- encounter names returned by the API.
local function seenKey(instance, encounter, bucket)
    return tostring(instance) .. SEEN_DELIM
        .. tostring(encounter) .. SEEN_DELIM
        .. tostring(bucket)
end

-- Pure lookup. Returns the ordered mechanic list for (instance, encounter,
-- bucket, role) or nil. No DB access; safe for the corpus harness.
function TacticReminders.Lookup(instance, encounter, bucket, role)
    if not (instance and encounter and bucket and role) then return nil end
    local J = ns.JournalData
    if not (J and J.instances) then return nil end
    local inst = J.instances[instance]
    if not inst or not inst.encounters then return nil end
    local enc = inst.encounters[encounter]
    if not enc then return nil end
    local base = enc[role]
    if not base or #base == 0 then
        -- Difficulty modifier on a missing/empty base means we have nothing
        -- to surface for this role; absent base is a content choice.
        return nil
    end

    local mods = inst.difficulty_modifiers
        and inst.difficulty_modifiers[bucket]
        and inst.difficulty_modifiers[bucket].extra_mechanics
        and inst.difficulty_modifiers[bucket].extra_mechanics[role]
    if not mods or #mods == 0 then
        -- Return the base list as a new table; never hand the caller a
        -- reference to the data table.
        local copy = {}
        for i = 1, #base do copy[i] = base[i] end
        return copy
    end

    local combined = {}
    for i = 1, #base do combined[i] = base[i] end
    for i = 1, #mods do combined[#combined + 1] = mods[i] end
    return combined
end

-- Count of encounters in JournalData. Used by /tox reminders state line.
function TacticReminders.CountEncounters()
    local J = ns.JournalData
    if not (J and J.instances) then return 0, 0 end
    local instances, encounters = 0, 0
    for _, inst in pairs(J.instances) do
        instances = instances + 1
        if inst.encounters then
            for _ in pairs(inst.encounters) do
                encounters = encounters + 1
            end
        end
    end
    return instances, encounters
end

-- Count of (instance|encounter|bucket) triples surfaced this session.
function TacticReminders.CountSeen()
    local g = db(); if not g or not g.tactic_reminders_seen then return 0 end
    local n = 0
    for _ in pairs(g.tactic_reminders_seen) do n = n + 1 end
    return n
end

-- Clear the seen map. Called from OnInitialize so reminders re-surface
-- every /reload (session-scoped despite the db storage), and from
-- /tox reminders reset for user-invoked re-arm.
function TacticReminders.ResetSession()
    local g = db(); if not g then return end
    g.tactic_reminders_seen = {}
end

-- Capitalize role name for display (tank → Tank, healer → Healer, dps → DPS).
local function displayRole(role)
    if role == "dps" then return "DPS" end
    if role == "tank" then return "Tank" end
    if role == "healer" then return "Healer" end
    return role
end

-- Surface entry point. Called from ToxFilter:OnEncounterStart BEFORE
-- setPaused(true) so the isPaused() guard inside doesn't accidentally
-- block the natural firing path.
function TacticReminders.Surface(instance, encounter, bucket)
    local g = db(); if not g then return end

    -- Sprint 5d: tactic reminders are an Uplifter feature. Category (or the
    -- addon master) off → silent. Sits above tactic_reminders_enabled.
    if not (ns.Category and ns.Category.gate("uplifter")) then
        dprint(string.format("TacticReminders.Surface: category_off (instance=%s)", tostring(instance)))
        return
    end

    if not g.tactic_reminders_enabled then
        dprint(string.format("TacticReminders.Surface: master_off (instance=%s encounter=%s bucket=%s)",
            tostring(instance), tostring(encounter), tostring(bucket)))
        return
    end

    if isPaused() then
        dprint(string.format("TacticReminders.Surface: paused (instance=%s encounter=%s bucket=%s)",
            tostring(instance), tostring(encounter), tostring(bucket)))
        return
    end

    if not (instance and encounter and bucket) then
        dprint(string.format("TacticReminders.Surface: missing_arg (instance=%s encounter=%s bucket=%s)",
            tostring(instance), tostring(encounter), tostring(bucket)))
        return
    end

    local role = ns.Database and ns.Database.GetEffectiveRole
        and ns.Database:GetEffectiveRole() or nil
    if not role then
        dprint("TacticReminders.Surface: role_nil (defer until next event)")
        return
    end

    local key = seenKey(instance, encounter, bucket)
    g.tactic_reminders_seen = g.tactic_reminders_seen or {}
    if g.tactic_reminders_seen[key] then
        dprint("TacticReminders.Surface: already_seen key='" .. key .. "'")
        return
    end

    local mechanics = TacticReminders.Lookup(instance, encounter, bucket, role)
    if not mechanics or #mechanics == 0 then
        dprint(string.format("TacticReminders.Surface: no_data instance='%s' encounter='%s' bucket='%s' role='%s'",
            instance, encounter, bucket, role))
        return
    end

    dprint(string.format("TacticReminders.Surface: emitting key='%s' role='%s' n=%d",
        key, role, #mechanics))

    out(encounter .. " (" .. bucket .. ") — " .. displayRole(role) .. " reminders:")
    for _, line in ipairs(mechanics) do
        print("[ToxFilter]   - " .. line)
    end

    -- On-screen surface via RaidWarningFrame (Sprint 5b polish). Local-only:
    -- RaidNotice_AddMessage writes directly to the user's own widget. The
    -- network-broadcasting equivalent is SendChatMessage("...", "RAID_WARNING"),
    -- which this addon never calls. Architectural commitment #4 (output is
    -- for the installing user only) holds.
    --
    -- Tighter header on the warning frame: "Tank — Arcanotron Custos:".
    -- Dungeon+difficulty stays in chat (review log); the on-screen surface
    -- gets role+boss only, since the player already knows where they are.
    local rwInfo = ChatTypeInfo and ChatTypeInfo["RAID_WARNING"]
    if RaidWarningFrame and RaidNotice_AddMessage and rwInfo then
        local rwHeader = displayRole(role) .. " — " .. encounter .. ":"
        RaidNotice_AddMessage(RaidWarningFrame, rwHeader, rwInfo)
        dprint("TacticReminders.Surface: RaidNotice header='" .. rwHeader .. "'")
        for _, line in ipairs(mechanics) do
            RaidNotice_AddMessage(RaidWarningFrame, line, rwInfo)
            dprint("TacticReminders.Surface: RaidNotice line='" .. line .. "'")
        end
    end

    g.tactic_reminders_seen[key] = true
end

ns.TacticReminders = TacticReminders
