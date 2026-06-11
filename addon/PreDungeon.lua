-- Sprint 5c: per-key pre-dungeon warnings — role-filtered Key Interrupts,
-- Key Dispels, and Tips, surfaced ONCE at CHALLENGE_MODE_START (the M+
-- countdown). Mythic+ only: CHALLENGE_MODE_START fires only for keys, never
-- on normal/heroic. Once-per-instance per session — an instance already
-- surfaced this session stays silent until /tox warnings reset or /reload.
--
-- Distinct from Sprint 5b's TacticReminders (per-encounter, ENCOUNTER_START).
-- Separate module, separate trigger, separate data (PreDungeonData.lua).
--
-- The empty case is a first-class state, not an error. Lookup returns nil ONLY
-- when the instance is unauthored. An authored instance with no dispels (no
-- dispellable debuffs) or no tips returns those categories as empty tables, and
-- Surface omits an empty category entirely — no bare "Dispels:" / "Tips:"
-- header. If every role-filtered category is empty, Surface emits nothing.
--
-- Gating order (Surface):
--   1. db.predungeon_warnings_enabled == false → silent
--   2. isPaused()                              → silent (defensive; natural
--                                                  caller fires pre-pause)
--   3. instance nil                            → silent
--   4. effective role nil                      → silent (defer; next event
--                                                  re-checks)
--   5. instance not in PreDungeonData          → silent
--   6. instance already seen this session      → silent
--   7. all role-filtered categories empty      → silent
--   8. emit role-filtered block; mark seen
--
-- Surfaces: chat (full review log incl. tips) + RaidWarningFrame (condensed:
-- interrupts + dispels only; tips are routing/reference text, not glanceable in
-- an ~8s countdown, and would overflow the warning frame). RaidNotice_AddMessage
-- writes to the user's own widget only — never broadcasts (architectural
-- commitment #4). The broadcasting equivalent is SendChatMessage(...,
-- "RAID_WARNING"), which this addon never calls.
--
-- Diagnostic prints (gated on db.debug_enabled): mirror Sprint 5b precedent —
-- log the gating outcome at each early return so future investigations are
-- self-evident without re-instrumenting.

local _, ns = ...

local PreDungeon = {}

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

-- Capitalize role name for display (tank → Tank, healer → Healer, dps → DPS).
local function displayRole(role)
    if role == "dps" then return "DPS" end
    if role == "tank" then return "Tank" end
    if role == "healer" then return "Healer" end
    return role
end

-- Default role for a category entry when the data omits an explicit role.
-- Interrupts are DPS responsibility in practice; dispels are healer.
local function entryRole(entry, fallback)
    return (entry and entry.role) or fallback
end

-- Pure lookup. Returns nil ONLY when the instance is unauthored. Otherwise
-- returns a table { interrupts = {...}, dispels = {...}, tips = {...} } with
-- interrupts/dispels filtered to the given role and tips passed through
-- (role-agnostic). Any category may be empty. No DB access; safe for the
-- corpus harness. Returned tables are fresh copies — never hands the caller a
-- reference to the data table.
function PreDungeon.Lookup(instance, role)
    if not (instance and role) then return nil end
    local D = ns.PreDungeonData
    if not (D and D.instances) then return nil end
    local inst = D.instances[instance]
    if not inst then return nil end

    local interrupts = {}
    if inst.interrupts then
        for _, e in ipairs(inst.interrupts) do
            if entryRole(e, "dps") == role then
                interrupts[#interrupts + 1] = e
            end
        end
    end

    local dispels = {}
    if inst.dispels then
        for _, e in ipairs(inst.dispels) do
            if entryRole(e, "healer") == role then
                dispels[#dispels + 1] = e
            end
        end
    end

    local tips = {}
    if inst.tips then
        for i = 1, #inst.tips do tips[i] = inst.tips[i] end
    end

    return { interrupts = interrupts, dispels = dispels, tips = tips }
end

-- Count of instances with warning data. Used by /tox warnings state line.
function PreDungeon.CountInstances()
    local D = ns.PreDungeonData
    if not (D and D.instances) then return 0 end
    local n = 0
    for _ in pairs(D.instances) do n = n + 1 end
    return n
end

-- Count of instances surfaced this session.
function PreDungeon.CountSeen()
    local g = db(); if not g or not g.predungeon_warnings_seen then return 0 end
    local n = 0
    for _ in pairs(g.predungeon_warnings_seen) do n = n + 1 end
    return n
end

-- Clear the seen map. Called from OnInitialize so warnings re-surface every
-- /reload (session-scoped despite db storage), and from /tox warnings reset
-- for user-invoked re-arm.
function PreDungeon.ResetSession()
    local g = db(); if not g then return end
    g.predungeon_warnings_seen = {}
end

-- Compose one interrupt/dispel display line. Interrupts: "Spell (Mob)".
-- Dispels: "Debuff (from Source)". Source/mob optional — omit the parens if
-- absent so a bare spell/debuff name still renders cleanly.
local function interruptLine(e)
    if e.mob and e.mob ~= "" then
        return e.spell .. " (" .. e.mob .. ")"
    end
    return e.spell
end

local function dispelLine(e)
    if e.from and e.from ~= "" then
        return e.debuff .. " (from " .. e.from .. ")"
    end
    return e.debuff
end

-- Surface entry point. Called from ToxFilter:OnChallengeModeStart BEFORE
-- setPaused(true) so the isPaused() guard inside doesn't block the natural
-- firing path (same trap as Sprint 5b's TacticReminders).
function PreDungeon.Surface(instance)
    local g = db(); if not g then return end

    -- Sprint 5d: pre-dungeon warnings are an Uplifter feature. Category (or the
    -- addon master) off → silent. Sits above predungeon_warnings_enabled.
    if not (ns.Category and ns.Category.gate("uplifter")) then
        dprint(string.format("PreDungeon.Surface: category_off (instance=%s)", tostring(instance)))
        return
    end

    if not g.predungeon_warnings_enabled then
        dprint(string.format("PreDungeon.Surface: master_off (instance=%s)", tostring(instance)))
        return
    end

    if isPaused() then
        dprint(string.format("PreDungeon.Surface: paused (instance=%s)", tostring(instance)))
        return
    end

    if not instance then
        dprint("PreDungeon.Surface: missing_arg (instance=nil)")
        return
    end

    local role = ns.Database and ns.Database.GetEffectiveRole
        and ns.Database:GetEffectiveRole() or nil
    if not role then
        dprint("PreDungeon.Surface: role_nil (defer until next event)")
        return
    end

    g.predungeon_warnings_seen = g.predungeon_warnings_seen or {}
    if g.predungeon_warnings_seen[instance] then
        dprint("PreDungeon.Surface: already_seen instance='" .. instance .. "'")
        return
    end

    local data = PreDungeon.Lookup(instance, role)
    if not data then
        dprint(string.format("PreDungeon.Surface: no_data instance='%s' role='%s'",
            instance, role))
        return
    end

    local nInt  = #data.interrupts
    local nDisp = #data.dispels
    local nTips = #data.tips
    if nInt == 0 and nDisp == 0 and nTips == 0 then
        dprint(string.format("PreDungeon.Surface: all_empty instance='%s' role='%s'",
            instance, role))
        return
    end

    dprint(string.format("PreDungeon.Surface: emitting instance='%s' role='%s' int=%d disp=%d tips=%d",
        instance, role, nInt, nDisp, nTips))

    -- Chat block (full review log, including tips). Empty categories omitted.
    out(instance .. " — pre-key reminders (" .. displayRole(role) .. "):")
    if nInt > 0 then
        out("Interrupts:")
        for _, e in ipairs(data.interrupts) do
            print("[ToxFilter]   - " .. interruptLine(e))
        end
    end
    if nDisp > 0 then
        out("Dispels:")
        for _, e in ipairs(data.dispels) do
            print("[ToxFilter]   - " .. dispelLine(e))
        end
    end
    if nTips > 0 then
        out("Tips:")
        for _, line in ipairs(data.tips) do
            print("[ToxFilter]   - " .. line)
        end
    end

    -- On-screen surface via RaidWarningFrame (condensed: interrupts + dispels
    -- only; tips stay chat-only). Local widget; never broadcasts. See header.
    local rwInfo = ChatTypeInfo and ChatTypeInfo["RAID_WARNING"]
    if RaidWarningFrame and RaidNotice_AddMessage and rwInfo and (nInt > 0 or nDisp > 0) then
        local rwHeader = displayRole(role) .. " — " .. instance .. ":"
        RaidNotice_AddMessage(RaidWarningFrame, rwHeader, rwInfo)
        dprint("PreDungeon.Surface: RaidNotice header='" .. rwHeader .. "'")
        for _, e in ipairs(data.interrupts) do
            local line = "Interrupt: " .. interruptLine(e)
            RaidNotice_AddMessage(RaidWarningFrame, line, rwInfo)
            dprint("PreDungeon.Surface: RaidNotice line='" .. line .. "'")
        end
        for _, e in ipairs(data.dispels) do
            local line = "Dispel: " .. dispelLine(e)
            RaidNotice_AddMessage(RaidWarningFrame, line, rwInfo)
            dprint("PreDungeon.Surface: RaidNotice line='" .. line .. "'")
        end
    end

    g.predungeon_warnings_seen[instance] = true
end

ns.PreDungeon = PreDungeon
