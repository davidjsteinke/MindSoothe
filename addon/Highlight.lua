-- Sprint 4b: in-line color tint for chat lines containing captured positive
-- moments. Two surfaces because they serve different needs:
--
--   1. tintIfEligible(msg, moment)  — synchronous helper invoked from
--      ToxFilter.lua's chatFilter on the pass-through branch. Wraps the
--      message in WoW color escapes when conditions hold (positive_ui on,
--      not paused, moment captured). The chatFilter return path is the only
--      place that can actually change what the user sees, so the rewriting
--      logic lives there, not in the subscriber.
--
--   2. OnPositiveMoment(moment)     — registered via PositiveCapture.subscribe.
--      No-op observer in 4b; kept so the subscriber API contract holds and
--      future telemetry / sound cues / etc. can attach the same way.
--
-- WoW chat-frame escape sequences `|c<AARRGGBB>` and `|r` are functional
-- control codes — they MUST stay as single pipes. The pipe-doubling rule in
-- Sprint 3 fix1 applies only to literal display pipes (e.g. `<a|b|c>` choice
-- notation in help text). See CLAUDE.md.

local _, ns = ...

local Highlight = {}

-- Desaturated medium green. Reads cleanly against WoW's default white chat
-- and doesn't conflict with system message yellow/orange or whisper purple.
local TINT_OPEN  = "|cFF66AA66"
local TINT_CLOSE = "|r"

local function db()
    return ns.Database and ns.Database:Get() or nil
end

local function isPaused()
    return ns.ToxFilterState and ns.ToxFilterState.isPaused() or false
end

function Highlight.tintIfEligible(msg, moment)
    if not moment then return nil end
    if type(msg) ~= "string" or msg == "" then return nil end
    local g = db(); if not g then return nil end
    if not g.positive_ui then return nil end
    if isPaused() then return nil end
    return TINT_OPEN .. msg .. TINT_CLOSE
end

-- Subscriber stub. PositiveCapture.notify fires this after capture stores the
-- moment; future consumers (telemetry, sound cues) attach via the same hook.
function Highlight.OnPositiveMoment(_moment)
end

ns.Highlight = Highlight
