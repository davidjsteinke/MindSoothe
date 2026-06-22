-- Category → handling mapping. Sprint 3 will let users override HANDLING via
-- /mind handle <category> <pass|edit|del|silent>; keep this table the single
-- source of truth so that override is a one-line change.

local _, ns = ...

ns.Categories = {
    HANDLING = {
        identity_attack   = "edit",
        slur              = "edit",
        role_attack       = "edit",
        harassment        = "edit",
        harm_invocation   = "del",
        general_hostility = "del",
    },
    LABEL = {
        identity_attack   = "Identity Attack",
        slur              = "Slur",
        role_attack       = "Role Attack",
        harassment        = "Harassment",
        harm_invocation   = "Harm Invocation",
        general_hostility = "General Hostility",
    },
    -- Aggressiveness ranking. Higher wins when a single message hits multiple
    -- rules with different handlings.
    HANDLING_RANK = {
        pass   = 0,
        edit   = 1,
        del    = 2,
        silent = 3,
    },
}
