std = "lua51"

exclude_files = {
    "addon/Libs/",
}

read_globals = {
    -- WoW chat-frame filter API
    "ChatFrame_AddMessageEventFilter",
    "ChatFrame_RemoveMessageEventFilter",

    -- Spec / role detection (Sprint 3 role auto-detect)
    "GetSpecializationRole",
    "GetSpecialization",

    -- Sprint 4a: encounter / dungeon counters and PII scrub
    "GetInstanceInfo",
    "UnitName",

    -- Sprint 4 fix: M+ keystone level for difficulty bucket (Issue 6).
    "C_ChallengeMode",

    -- Sprint 4a: time/date globals (WoW exposes these at top level alongside the os.* equivalents)
    "time",
    "date",

    -- Sprint 4b: WoW UI primitives for the breathing frame.
    "CreateFrame",
    "UIParent",
    "UISpecialFrames",
    "GetTime",
    "tinsert",

    -- Sprint 4 fix2 (I9): combat-lockdown gate on /tox breathe.
    "InCombatLockdown",

    -- Ace3
    "LibStub",

    -- WoW exposes the LuaJIT-style bit library at the global scope.
    "bit",
}

globals = {
    -- SavedVariables global; AceDB:New manages it but Database.lua touches
    -- it directly for corruption recovery.
    "ToxFilterDB",
}

ignore = {
    "211",  -- unused local (intentional migration placeholder funcs)
    "212",  -- unused argument (chat filter args we deliberately drop)
    "213",  -- unused loop variable
}
