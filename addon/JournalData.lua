-- Sprint 5b: static dungeon-journal data for pre-encounter role-filtered
-- tactical reminders. Hand-curated; one file ships with the addon. No live
-- API reads of journal data — keeps runtime cost zero and ensures consistency
-- across user clients. Updates ride on addon updates (Sprint 8 distribution).
--
-- Shape:
--   ns.JournalData.METADATA      = { JOURNAL_DATA_VERSION, last_content_patch }
--   ns.JournalData.instances     = {
--       [<instance_name from GetInstanceInfo()>] = {
--           difficulty_modifiers = {
--               [<bucket>] = { extra_mechanics = { tank = {...}, healer = {...}, dps = {...} } },
--           },
--           encounters = {
--               [<encounter_name from ENCOUNTER_START payload>] = {
--                   tank   = { "...", "...", "..." },   -- 2-3 imperative strings, ≤80 chars
--                   healer = { "...", "...", "..." },
--                   dps    = { "...", "...", "..." },
--               },
--           },
--       },
--   }
--
-- Bucket keys mirror Sprint 4 fix's counter buckets: normal | heroic | mythic
-- for non-M+, M0 | M2-5 | M6-10 | M10+ for M+. M+ buckets share base mechanics;
-- a mechanic that activates only at high keys can be encoded as a modifier on
-- the relevant M+ bucket. For first cut, M+ modifier entries are rare and
-- only added when community knowledge says a mechanic genuinely changes.
--
-- Methodology for picking the 2-3 mechanics per role per encounter (documented
-- in CLAUDE.md):
--   1. Survival-relevance: can wipe the pull, or unique-failure mode.
--   2. Role uniqueness: the role specifically must handle this mechanic.
--   3. Frequency of failure: commonly missed in pug groups.
--   4. Hard cap of 3 base + 2 per difficulty modifier.
--   5. Sources: in-game Adventure Journal, Wowhead, IcyVeins — hand-curated.
--
-- Tonal register: imperative, ≤80 chars, terminal period included. No
-- exclamation, no encouragement. Pipe-doubling does not apply here (no chat
-- escape sequences in this file); tonal-grep target list does include it.
--
-- METADATA.JOURNAL_DATA_VERSION is reserved for Sprint 8's distribution
-- pipeline — a future content-only update will bump this without bumping
-- the addon's main schema_version.

local _, ns = ...

ns.JournalData = {
    METADATA = {
        JOURNAL_DATA_VERSION = 2,
        last_content_patch   = "Midnight Season 1 (pre-launch draft)",
    },
    instances = {
        -- Encounters land iteratively as each dungeon is locked. Order:
        -- Magisters' Terrace, then the other seven Midnight Season 1
        -- M+ dungeons as user-provided source material arrives.
        --
        -- Source for Magisters' Terrace: Wowhead Midnight Season 1 cheat-
        -- sheet (image) + in-game Adventure Guide screenshot (name
        -- confirmation). All mechanic-name strings (Refueling Protocol,
        -- Runic Marks, Suppression Zone, Wave of Silence, Neutral Link,
        -- Astral Grasp, Hulking Fragment) are quoted from the source as
        -- written. Encounter and instance name strings come from the
        -- in-game Adventure Guide; the K-protocol diagnostic-print
        -- pattern confirms ENCOUNTER_START payload matches at deploy.
        ["Magisters' Terrace"] = {
            -- No difficulty_modifiers entry: the cheat sheet does not
            -- differentiate by heroic / mythic / M+ bracket.
            encounters = {
                ["Arcanotron Custos"] = {
                    tank = {
                        "Tank along the edge for puddles.",
                        "Soak orbs during Refueling Protocol.",
                    },
                    healer = {
                        "Soak orbs during Refueling Protocol.",
                    },
                    dps = {
                        "Soak orbs during Refueling Protocol.",
                        "Burst during Refueling Protocol.",
                    },
                },
                ["Seranel Sunlash"] = {
                    tank = {
                        "Clear one Runic Mark at a time.",
                        "Stand in zone for Wave of Silence.",
                    },
                    healer = {
                        "Clear one Runic Mark at a time.",
                        "Stand in zone for Wave of Silence.",
                    },
                    dps = {
                        "Clear one Runic Mark at a time.",
                        "Stand in zone for Wave of Silence.",
                    },
                },
                ["Gemellus"] = {
                    tank = {
                        "Run to red clone for Neutral Link.",
                        "Avoid clones during Astral Grasp.",
                    },
                    healer = {
                        "Run to red clone for Neutral Link.",
                        "Avoid clones during Astral Grasp.",
                    },
                    dps = {
                        "Run to red clone for Neutral Link.",
                        "Avoid clones during Astral Grasp.",
                    },
                },
                ["Degentrius"] = {
                    tank = {
                        "Split the party.",
                        "Soak the volleyball in your area.",
                        "Move to alternating sides for dispels.",
                    },
                    healer = {
                        "Split the party.",
                        "Soak the volleyball in your area.",
                        "Dispel tank on alternating sides.",
                    },
                    dps = {
                        "Split the party.",
                        "Soak the volleyball in your area.",
                    },
                },
            },
        },
        -- Source for Maisara Caverns: Wowhead Midnight Season 1 cheat
        -- sheet (image) + citation URL wowhead.com/guide/midnight/
        -- maisara-caverns-dungeon-overview-location-rewards. Boss Tips
        -- section only; Key Interrupts and Key Dispels deferred to
        -- Sprint 5c. Mechanic-name strings (Carrion Swoop, Freezing
        -- Trap, Barrage, Crush Souls) quoted from source. Encounter-
        -- name strings verified against ENCOUNTER_START payload via
        -- K-protocol: Wowhead's all-caps headers ("MURO'JIN AND
        -- NEKRAXX", "RAK'TUL") resolve to "Muro'jin and Nekraxx" and
        -- "Rak'tul, Vessel of Souls" in-game — cheat sheet stylizes
        -- capitalization and omits title suffixes.
        ["Maisara Caverns"] = {
            encounters = {
                ["Muro'jin and Nekraxx"] = {
                    tank = {
                        "Stack bosses for cleave damage.",
                        "Step onto Freezing Trap for Carrion Swoop.",
                        "Dodge Barrage cone; defensive if targeted.",
                    },
                    healer = {
                        "Step onto Freezing Trap for Carrion Swoop.",
                        "Dodge Barrage cone; defensive if targeted.",
                    },
                    dps = {
                        "Split damage for simultaneous kill.",
                        "Step onto Freezing Trap for Carrion Swoop.",
                        "Dodge Barrage cone; defensive if targeted.",
                    },
                },
                ["Vordaza"] = {
                    tank = {
                        "Kite adds in pairs to detonate.",
                        "Dodge orbs during intermission.",
                    },
                    healer = {
                        "Dodge orbs during intermission.",
                    },
                    dps = {
                        "Detonate adds in pairs.",
                        "Break shield to end intermission.",
                        "Dodge orbs during intermission.",
                    },
                },
                ["Rak'tul, Vessel of Souls"] = {
                    tank = {
                        "Stack near allies if targeted by Crush Souls.",
                        "Interrupt, CC, and dodge ghosts.",
                    },
                    healer = {
                        "Stack near allies if targeted by Crush Souls.",
                        "Interrupt, CC, and dodge ghosts.",
                    },
                    dps = {
                        "Stack near allies if targeted by Crush Souls.",
                        "Interrupt, CC, and dodge ghosts.",
                        "Kill totems after Crush Souls leaps.",
                    },
                },
            },
        },
    },
}
