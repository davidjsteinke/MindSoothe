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
