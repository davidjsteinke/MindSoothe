-- Sprint 4b: animated box-breathing frame.
--
-- OnUpdate-driven state machine. Four phases per cycle:
--   inhale  → block scales from MIN to MAX over `count` seconds
--   hold1   → block stays at MAX for `count` seconds
--   exhale  → block scales from MAX to MIN over `count` seconds
--   hold2   → block stays at MIN for `count` seconds
-- After `cycles` cycles, the frame auto-closes and prints "Box breathing
-- complete." Esc cancels mid-cycle (UISpecialFrames registration); cancel
-- skips the completion print and skips onComplete so Ready.lua treats it as
-- chain abort.
--
-- Singleton frame: lazily created on first Run, reused after. The frame is
-- hidden on completion/cancel so subsequent runs reuse the existing texture
-- and FontString instances.
--
-- Tone: phase labels are bare ("Inhale  4"), no exclamation, no encouragement.

local _, ns = ...

local Breathing = {}

-- Global frame name derives from the per-build identity so two coexisting
-- installs (ship + dev) never share a _G frame name or UISpecialFrames entry.
local FRAME_NAME       = ns.Const.FRAME_PREFIX .. "BreathingFrame"

local BLOCK_MIN_SIZE   = 40
local BLOCK_MAX_SIZE   = 160
local FRAME_SIZE       = 200
local PHASES           = { "inhale", "hold1", "exhale", "hold2" }
local PHASE_LABELS     = { inhale = "Inhale", hold1 = "Hold", exhale = "Exhale", hold2 = "Hold" }

local frame = nil
local state = nil
local cancel_hook = nil

local function db()
    return ns.Database and ns.Database:Get() or nil
end

local function out(line) print(ns.Const.PREFIX .. line) end

local function fireCancelHook()
    local cb = cancel_hook
    cancel_hook = nil
    if cb then
        local ok, err = pcall(cb)
        if not ok then
            print(ns.Const.PREFIX .. "Breathing cancel hook error: " .. tostring(err))
        end
    end
end

local function lerp(a, b, t)
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    return a + (b - a) * t
end

local function applyPhaseVisual(phase, phase_progress, phase_remaining)
    local size
    if phase == "inhale" then
        size = lerp(BLOCK_MIN_SIZE, BLOCK_MAX_SIZE, phase_progress)
    elseif phase == "hold1" then
        size = BLOCK_MAX_SIZE
    elseif phase == "exhale" then
        size = lerp(BLOCK_MAX_SIZE, BLOCK_MIN_SIZE, phase_progress)
    else
        size = BLOCK_MIN_SIZE
    end
    frame.block:SetSize(size, size)
    frame.label:SetText(string.format("%s  %d", PHASE_LABELS[phase], math.ceil(phase_remaining)))
    if state and frame.cycle_label then
        frame.cycle_label:SetText(string.format("Cycle %d of %d", state.cycle, state.cycles))
    end
end

local function teardown()
    state = nil
    if frame then frame:Hide() end
end

local function finish(natural)
    local cb = state and state.on_complete or nil
    cancel_hook = nil
    teardown()
    if natural then
        out("Box breathing complete.")
        if cb then
            local ok, err = pcall(cb)
            if not ok then
                print(ns.Const.PREFIX .. "Breathing completion callback error: " .. tostring(err))
            end
        end
    end
end

local function onUpdate(_, elapsed)
    if not state then return end
    state.phase_elapsed = state.phase_elapsed + elapsed

    local count = state.count
    while state.phase_elapsed >= count do
        state.phase_elapsed = state.phase_elapsed - count
        state.phase_idx = state.phase_idx + 1
        if state.phase_idx > #PHASES then
            state.phase_idx = 1
            state.cycle = state.cycle + 1
            if state.cycle > state.cycles then
                finish(true)
                return
            end
        end
    end

    local phase = PHASES[state.phase_idx]
    local progress  = state.phase_elapsed / count
    local remaining = count - state.phase_elapsed
    applyPhaseVisual(phase, progress, remaining)
end

local function ensureFrame()
    if frame then return frame end
    frame = CreateFrame("Frame", FRAME_NAME, UIParent, "BackdropTemplate")
    frame:SetSize(FRAME_SIZE, FRAME_SIZE)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local g = db()
        if g then
            local x, y = self:GetCenter()
            local px, py = UIParent:GetCenter()
            if x and y and px and py then
                g.breathe_position = { x = x - px, y = y - py }
            end
        end
    end)

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    bg:SetColorTexture(0, 0, 0, 0.55)
    frame.bg = bg

    local block = frame:CreateTexture(nil, "ARTWORK")
    block:SetPoint("CENTER", frame, "CENTER", 0, 16)
    block:SetSize(BLOCK_MIN_SIZE, BLOCK_MIN_SIZE)
    block:SetColorTexture(0.4, 0.65, 0.4, 0.85)
    frame.block = block

    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    label:SetPoint("BOTTOM", frame, "BOTTOM", 0, 28)
    label:SetText("")
    frame.label = label

    -- Sprint 4 fix2 (I7): cycle indicator below the phase/count label.
    local cycle_label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cycle_label:SetPoint("BOTTOM", frame, "BOTTOM", 0, 10)
    cycle_label:SetText("")
    frame.cycle_label = cycle_label

    frame:SetScript("OnUpdate", onUpdate)
    frame:SetScript("OnHide", function()
        if state then
            -- Hidden mid-run -> user closed via Esc, combat start, or other
            -- dismissal. Treat as cancel: drop state, fire cancel hook so any
            -- in-flight Ready chain aborts, no completion print.
            state = nil
            fireCancelHook()
        end
    end)

    -- Sprint 4 fix Issue 7: combat-cancel. Hiding the frame on combat start
    -- routes through OnHide above so cancel-hook semantics stay consistent
    -- with Esc; the user shouldn't have a static UI element obscuring the
    -- screen during a pull.
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_DISABLED" and state then
            self:Hide()
        end
    end)
    frame:Hide()

    if type(_G.UISpecialFrames) == "table" then
        local already = false
        for i = 1, #_G.UISpecialFrames do
            if _G.UISpecialFrames[i] == FRAME_NAME then
                already = true
                break
            end
        end
        if not already then
            tinsert(_G.UISpecialFrames, FRAME_NAME)
        end
    end
    return frame
end

local function applyStoredPosition(f)
    local g = db()
    if not g or not g.breathe_position then
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        return
    end
    local p = g.breathe_position
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", p.x or 0, p.y or 0)
end

function Breathing.Run(onComplete)
    local g = db()
    if not g then
        out("Settings not loaded.")
        if onComplete then pcall(onComplete) end
        return false
    end

    if state then
        out("Box breathing already running.")
        return false
    end

    -- Sprint 4 fix2 (I9): refuse to start during combat. Routes through
    -- onComplete so a /mind ready chain advances past this step rather than
    -- stalling. The frame's PLAYER_REGEN_DISABLED hook (Sprint 4 fix1)
    -- handles the case where combat starts WHILE breathing is running.
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        out("Cannot start breathing during combat.")
        if onComplete then pcall(onComplete) end
        return false
    end

    if type(CreateFrame) ~= "function" or type(UIParent) ~= "table" then
        out("Box breathing requires the WoW UI; not available in this environment.")
        if onComplete then pcall(onComplete) end
        return false
    end

    local f = ensureFrame()
    applyStoredPosition(f)

    state = {
        cycles        = math.max(1, math.floor(g.breathe_cycles or 4)),
        count         = math.max(1, math.floor(g.breathe_count or 4)),
        phase_idx     = 1,
        phase_elapsed = 0,
        cycle         = 1,
        on_complete   = onComplete,
    }

    applyPhaseVisual(PHASES[1], 0, state.count)
    f:Show()
    return true
end

function Breathing.IsRunning()
    return state ~= nil
end

-- Cancel hook: Ready.lua registers itself for the duration of a Breathing
-- step. If the user presses Esc / closes the frame mid-cycle, the hook fires
-- so Ready knows to abort the chain. SetCancelHook(nil) clears.
function Breathing.SetCancelHook(fn)
    cancel_hook = fn
end

-- Programmatic cancel (used by external callers; Esc path goes through OnHide).
function Breathing.Cancel()
    if not state then return false end
    state = nil
    if frame then frame:Hide() end
    fireCancelHook()
    return true
end

ns.Breathing = Breathing
