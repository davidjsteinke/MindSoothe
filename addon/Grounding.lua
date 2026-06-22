-- Grounding checklist: user-defined pre-pull ritual.
--
-- Sprint 4a runs as a slash-driven Y/N state machine — no popup frame. The
-- user kicks off /mind check, and each item is presented in turn; the user
-- answers via /mind check y or /mind check n until the list is exhausted, or
-- aborts via /mind check cancel. A new /mind check while a ritual is in flight
-- resets the state and starts a fresh ritual.
--
-- Items live in db.grounding_items as a flat ordered list. Empty by default;
-- no suggested items. /mind check on an empty list prints a usage hint rather
-- than silently doing nothing.
--
-- Sprint 4b can swap the slash flow for a popup frame; the public surface
-- (Start, Respond, Cancel, IsRunning, list/add/remove) stays the same so
-- /mind ready can chain it without changes.

local _, ns = ...

local Grounding = {}

local current_ritual = nil
local cancel_hook    = nil

local function fireCancelHook()
    local cb = cancel_hook
    cancel_hook = nil
    if cb then
        local ok, err = pcall(cb)
        if not ok then
            print(ns.Const.PREFIX .. "Grounding cancel hook error: " .. tostring(err))
        end
    end
end

local function db()
    return ns.Database and ns.Database:Get() or nil
end

local function ensureItems(g)
    g.grounding_items = g.grounding_items or {}
end

local function out(line) print(ns.Const.PREFIX .. line) end

function Grounding.AddItem(item)
    local g = db(); if not g then return false, "no_db" end
    ensureItems(g)
    item = item:match("^%s*(.-)%s*$") or ""
    if item == "" then return false, "empty" end
    for _, existing in ipairs(g.grounding_items) do
        if existing == item then return false, "duplicate" end
    end
    table.insert(g.grounding_items, item)
    return true, nil
end

function Grounding.RemoveItem(item)
    local g = db(); if not g then return false, "no_db" end
    ensureItems(g)
    item = item:match("^%s*(.-)%s*$") or ""
    if item == "" then return false, "empty" end
    for i, existing in ipairs(g.grounding_items) do
        if existing == item then
            table.remove(g.grounding_items, i)
            return true, nil
        end
    end
    return false, "absent"
end

function Grounding.ListItems()
    local g = db(); if not g then return {} end
    ensureItems(g)
    return g.grounding_items
end

function Grounding.Cancel()
    if not current_ritual then return false end
    current_ritual = nil
    fireCancelHook()
    return true
end

function Grounding.IsRunning()
    return current_ritual ~= nil
end

-- Sprint 4b: Ready.lua registers itself for the duration of a grounding step.
-- /mind check cancel fires the hook so the chain can abort. Cleared on
-- completion (finish) and consumed-and-cleared by fireCancelHook on cancel.
function Grounding.SetCancelHook(fn)
    cancel_hook = fn
end

local function presentCurrent()
    local item = current_ritual.items[current_ritual.idx]
    out(string.format("Grounding (%d of %d): %s ? Type /mind check y or /mind check n.",
        current_ritual.idx, #current_ritual.items, item))
end

local function finish()
    local cb = current_ritual.on_complete
    local responses = current_ritual.responses
    current_ritual = nil
    cancel_hook = nil
    out("Grounding ritual finished.")
    if cb then
        local ok, err = pcall(cb, responses)
        if not ok then
            print(ns.Const.PREFIX .. "Grounding completion callback error: " .. tostring(err))
        end
    end
end

function Grounding.Start(onComplete)
    local g = db(); if not g then return false end
    ensureItems(g)
    if #g.grounding_items == 0 then
        out("No grounding items configured. Add items via /mind check add <item>.")
        return false
    end
    current_ritual = {
        items       = {},
        idx         = 1,
        responses   = {},
        on_complete = onComplete,
    }
    for _, it in ipairs(g.grounding_items) do
        table.insert(current_ritual.items, it)
    end
    presentCurrent()
    return true
end

function Grounding.Respond(answer)
    if not current_ritual then
        out("No grounding ritual in progress. Run /mind check to start.")
        return
    end
    if answer ~= "y" and answer ~= "n" then
        out("Use /mind check y or /mind check n.")
        return
    end
    current_ritual.responses[current_ritual.idx] = answer
    if current_ritual.idx >= #current_ritual.items then
        finish()
    else
        current_ritual.idx = current_ritual.idx + 1
        presentCurrent()
    end
end

ns.Grounding = Grounding
