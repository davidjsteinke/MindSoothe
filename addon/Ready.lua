-- Sprint 4b: /mind ready meta-orchestration.
--
-- Chains grounding → breathing → lift in user-configured order, respecting
-- per-step include toggles in db.ready_config. Each step is responsible for
-- its own UI and lifecycle; Ready.lua threads onComplete callbacks through.
--
-- Cancellation model:
--   - Each step's primitive exposes SetCancelHook. Ready registers a hook for
--     the duration of the active step; the hook clears module-local chain
--     state so onComplete (when it later fires) becomes a no-op via the
--     stale-token check.
--   - /mind check cancel and Esc-on-breathing both flow through the primitives'
--     own cancel paths, which fire the hook. Lift is synchronous, no
--     cancellation point.
--   - Resetting state instead of nilling-then-checking is the simplest way to
--     keep advance() idempotent in the face of out-of-order callbacks.

local _, ns = ...

local Ready = {}

local KNOWN_STEPS = { grounding = true, breathing = true, lift = true }

local current_chain = nil

local function out(line) print(ns.Const.PREFIX .. line) end

local function db()
    return ns.Database and ns.Database:Get() or nil
end

local function clearChainState()
    current_chain = nil
    if ns.Grounding and ns.Grounding.SetCancelHook then ns.Grounding.SetCancelHook(nil) end
    if ns.Breathing and ns.Breathing.SetCancelHook then ns.Breathing.SetCancelHook(nil) end
end

local advance  -- forward declaration

local function runStep(step_name, token)
    if step_name == "grounding" then
        local g = db()
        if not g or not g.grounding_items or #g.grounding_items == 0 then
            out("No grounding items configured. Skipping.")
            advance(token)
            return
        end
        if ns.Grounding and ns.Grounding.SetCancelHook then
            ns.Grounding.SetCancelHook(function()
                if current_chain and current_chain.token == token then
                    clearChainState()
                end
            end)
        end
        ns.Grounding.Start(function()
            if ns.Grounding and ns.Grounding.SetCancelHook then ns.Grounding.SetCancelHook(nil) end
            advance(token)
        end)
        return
    end

    if step_name == "breathing" then
        if not (ns.Breathing and ns.Breathing.Run) then
            out("Box breathing not available. Skipping.")
            advance(token)
            return
        end
        if ns.Breathing.SetCancelHook then
            ns.Breathing.SetCancelHook(function()
                if current_chain and current_chain.token == token then
                    clearChainState()
                end
            end)
        end
        ns.Breathing.Run(function()
            if ns.Breathing and ns.Breathing.SetCancelHook then ns.Breathing.SetCancelHook(nil) end
            advance(token)
        end)
        return
    end

    if step_name == "lift" then
        if ns.Commands and ns.Commands.lift then
            ns.Commands.lift()
        end
        advance(token)
        return
    end

    -- Unknown step name (config corruption). Skip and continue.
    advance(token)
end

advance = function(token)
    if not current_chain or current_chain.token ~= token then
        -- Chain was cancelled or replaced; abandon callback silently.
        return
    end
    current_chain.idx = current_chain.idx + 1
    if current_chain.idx > #current_chain.steps then
        clearChainState()
        return
    end
    runStep(current_chain.steps[current_chain.idx], token)
end

local function buildSteps(g)
    local order = (g.ready_config and g.ready_config.order) or { "grounding", "breathing", "lift" }
    local include = (g.ready_config and g.ready_config.include) or {
        grounding = true, breathing = true, lift = true,
    }
    local steps = {}
    for _, name in ipairs(order) do
        if KNOWN_STEPS[name] and include[name] then
            steps[#steps + 1] = name
        end
    end
    return steps
end

function Ready.Start()
    local g = db()
    if not g then out("Settings not loaded."); return end

    if current_chain then
        out("Ritual already in progress.")
        return
    end

    local steps = buildSteps(g)
    if #steps == 0 then
        out("All ready steps are excluded. Use /mind ready include <step> on.")
        return
    end

    local token = {}
    current_chain = { steps = steps, idx = 1, token = token }
    runStep(steps[1], token)
end

function Ready.IsRunning()
    return current_chain ~= nil
end

-- Sprint 4 fix2 (I16): master abort. Clears chain state first so any
-- primitive cancel hooks see a stale token and no-op. Then cancels the
-- primitive that's currently running (whichever is in flight). Returns true
-- if a chain was active, false otherwise.
function Ready.Cancel()
    if not current_chain then return false end
    clearChainState()
    if ns.Grounding and ns.Grounding.IsRunning and ns.Grounding.IsRunning() then
        ns.Grounding.Cancel()
    end
    if ns.Breathing and ns.Breathing.IsRunning and ns.Breathing.IsRunning() then
        ns.Breathing.Cancel()
    end
    return true
end

function Ready.SetInclude(step, on)
    if not KNOWN_STEPS[step] then return false, "unknown" end
    local g = db(); if not g then return false, "no_db" end
    g.ready_config = g.ready_config or { include = {}, order = {} }
    g.ready_config.include = g.ready_config.include or {}
    g.ready_config.include[step] = on and true or false
    return true
end

function Ready.SetOrder(list)
    local g = db(); if not g then return false, "no_db" end
    if type(list) ~= "table" or #list ~= 3 then return false, "bad_count" end
    local seen = {}
    for _, name in ipairs(list) do
        if not KNOWN_STEPS[name] then return false, "unknown:" .. tostring(name) end
        if seen[name] then return false, "duplicate:" .. name end
        seen[name] = true
    end
    g.ready_config = g.ready_config or { include = {}, order = {} }
    g.ready_config.order = { list[1], list[2], list[3] }
    return true
end

function Ready.GetConfig()
    local g = db(); if not g then return nil end
    return g.ready_config
end

ns.Ready = Ready
