std = "lua51"

exclude_files = {
    "addon/Libs/",
}

read_globals = {
    -- WoW chat-frame filter API
    "ChatFrame_AddMessageEventFilter",
    "ChatFrame_RemoveMessageEventFilter",

    -- Ace3
    "LibStub",

    -- WoW exposes the LuaJIT-style bit library at the global scope.
    "bit",
}

ignore = {
    "212",  -- unused argument (chat filter args we deliberately drop)
    "213",  -- unused loop variable
}
