-- Const.lua — single source of truth for the addon's identity surface.
-- Loaded FIRST in the TOC (before Hash.lua, whose load-time asserts use PREFIX)
-- so ns.Const is available to every later file at both load and call time.
--
-- Sprint 8 centralization: the product/addon identity ("Mind Soothe") flows from
-- here, not from scattered literals. The five collision-bearing surfaces — addon
-- name, SavedVariables global, slash token, chat prefix, and the global frame
-- name — all derive from these constants so the dual-build (ship "Mind Soothe" /
-- dev "Mind Dev") is a build-time substitution rather than a hunt.
--
-- The dev build is produced by scripts/deploy.sh applying THREE substitutions to
-- a throwaway staged copy:
--     MindSoothe   -> MindDev     (ADDON_NAME, SAVEDVAR, FRAME_PREFIX, APP token)
--     Mind Soothe  -> Mind Dev    (DISPLAY_NAME, chat prefix, TOC Title, panel)
--     /mind        -> /mdev       (SLASH + all help/description copy)
-- The committed tree IS the ship identity, so ship needs no stamping.
--
-- NOT centralizable here (reported per the Sprint 8 plan):
--   * The TOC ## Title: / ## SavedVariables: / ## Version: lines — a .toc cannot
--     read Lua. They stay literals in MindSoothe.toc, kept in sync with these
--     constants by construction (the same dev-stamp tokens rewrite both).
--   * The /mind mentions in help/description copy — display text, not the slash
--     *token*. Rewritten to literals; the runtime token still derives from SLASH.

local _, ns = ...

ns.Const = {
    -- No-space identifier form: AceAddon NewAddon name, AceConfig registration
    -- token (APP), C_AddOns.GetAddOnMetadata key, SavedVariables global stem,
    -- global frame-name stem.
    ADDON_NAME   = "MindSoothe",

    -- Space form for human-readable display: TOC Title, options panel title,
    -- Blizzard AddOns-menu label.
    DISPLAY_NAME = "Mind Soothe",

    -- SavedVariables global. Must match the TOC ## SavedVariables: line.
    SAVEDVAR     = "MindSootheDB",

    -- Slash command. SLASH_DISPLAY carries the leading slash so the dev-build
    -- stamp (/mind -> /mdev) rewrites it in one pass; the bare token AceConsole
    -- registers is derived from it below. Help/description copy uses the literal
    -- "/mind" (also stamped). Storing only the leading-slash form keeps the dev
    -- stamp from needing a separate, over-eager rule for the bare word "mind".
    SLASH_DISPLAY = "/mind",

    -- Chat-line prefix on every print()/out(); trailing space included.
    PREFIX       = "[Mind Soothe] ",

    -- Prefix for debug-gated diagnostic prints (gated on db.debug_enabled).
    DEBUG_PREFIX = "[Mind Soothe Debug] ",

    -- Stem for CreateFrame global names (e.g. FRAME_PREFIX .. "BreathingFrame").
    -- Per-build so two coexisting installs never share a global frame name.
    FRAME_PREFIX = "MindSoothe",
}

-- Bare slash token AceConsole RegisterChatCommand wants (no leading slash),
-- derived from the single stampable SLASH_DISPLAY source.
ns.Const.SLASH = (ns.Const.SLASH_DISPLAY:gsub("^/", ""))
