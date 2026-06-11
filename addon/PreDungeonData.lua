-- Sprint 5c: static per-instance pre-dungeon warning data — Key Interrupts,
-- Key Dispels, and Tips. Surfaced ONCE per Mythic+ key at CHALLENGE_MODE_START
-- (the countdown), not per-encounter. Distinct from Sprint 5b's JournalData,
-- which is per-encounter and fires at ENCOUNTER_START. Separate file, separate
-- module (PreDungeon.lua), separate trigger, separate data — do not merge.
--
-- Shape:
--   ns.PreDungeonData.METADATA  = { PREDUNGEON_DATA_VERSION, last_content_patch }
--   ns.PreDungeonData.instances = {
--       [<instance_name from GetInstanceInfo()>] = {
--           interrupts = { { spell = "...", mob = "...", role = "dps" }, ... },
--           dispels    = { { debuff = "...", from = "...", role = "healer" }, ... },
--           tips       = { "...", "..." },   -- plain strings; {} is valid
--       },
--   }
--
-- The absent-data case is normal, not an error:
--   * instance not present at all  → "not authored" (PreDungeon.Lookup returns nil)
--   * interrupts/dispels/tips = {}  → "authored, this category is empty"
-- A genuinely empty category produces no output — never a bare header.
--
-- role on interrupts/dispels: filtered against the player's effective role at
-- surface time. Interrupts are DPS responsibility in practice (default "dps"),
-- but the field supports the occasional tank-specific interrupt. Dispels default
-- "healer" but the field supports dispel-capable DPS/tank cases. Not hardcoded.
--
-- Tips are role-agnostic plain strings — shown to everyone, dungeon-level
-- meta-strategy (routing, big-pull spots, items to use).
--
-- Tonal register: imperative, <=80 chars, terminal period included. No
-- exclamation, no encouragement. Pipe-doubling does not apply here (no chat
-- escape sequences in this file); tonal-grep target list does include it.
--
-- METADATA.PREDUNGEON_DATA_VERSION = 0 marks the scaffold state (no content
-- authored yet). Locking the first dungeon bumps it to 1. Reserved for Sprint
-- 8's distribution pipeline — content-only updates bump this without bumping
-- the addon's main schema_version.
--
-- Content lands iteratively, one dungeon at a time, from user-provided Wowhead
-- cheat-sheet source material (Key Interrupts / Key Dispels / Tips and Tricks).
-- Never author mechanics from training data.

local _, ns = ...

ns.PreDungeonData = {
    METADATA = {
        PREDUNGEON_DATA_VERSION = 0,
        last_content_patch      = "Midnight Season 1 (scaffold — no content yet)",
    },
    instances = {
        -- Empty at scaffold time. Each instance lands when its source material
        -- is provided and the entry is locked per the approval workflow.
    },
}
