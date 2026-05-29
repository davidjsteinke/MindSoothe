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
        JOURNAL_DATA_VERSION = 8,
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
        -- Source for Nexus-Point Xenas: Wowhead Midnight Season 1 cheat
        -- sheet (image) + citation URL wowhead.com/guide/midnight/
        -- nexus-point-xenas-dungeon-overview-location-rewards. Boss
        -- Tips section only; Key Interrupts, Key Dispels, and Tips and
        -- Tricks deferred to Sprint 5c. Mechanic-name strings (Reflux
        -- Charge, Corespark Detonation, Lightscared Flame, Nullify,
        -- Image of Lothraxion) quoted from source. Encounter-name
        -- strings verified against the in-game Adventure Journal
        -- screenshot; K-protocol diagnostic-print pattern confirms
        -- ENCOUNTER_START payload matches at deploy.
        ["Nexus-Point Xenas"] = {
            encounters = {
                ["Chief Corewright Kasreth"] = {
                    tank = {
                        "Stand on beam intersections if targeted.",
                        "Avoid knockbacks into beams.",
                    },
                    healer = {
                        "Stand on beam intersections if targeted.",
                        "Avoid knockbacks into beams.",
                    },
                    dps = {
                        "Stand on beam intersections if targeted.",
                        "Avoid knockbacks into beams.",
                    },
                },
                ["Corewarden Nysarra"] = {
                    tank = {
                        "Pick up summoned adds.",
                        "Stand in Lightscared Flame beam.",
                    },
                    healer = {
                        "Stand in Lightscared Flame beam for bonus healing.",
                    },
                    dps = {
                        "Kill summoned adds and interrupt Nullify.",
                        "Stand in Lightscared Flame beam for bonus damage.",
                    },
                },
                ["Lothraxion"] = {
                    tank = {
                        "Avoid Lothraxion clones and their charges.",
                        "Interrupt the Image without horns.",
                    },
                    healer = {
                        "Avoid Lothraxion clones and their charges.",
                    },
                    dps = {
                        "Avoid Lothraxion clones and their charges.",
                        "Interrupt the Image without horns.",
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
        -- Source for Windrunner Spire: Wowhead Midnight Season 1 cheat
        -- sheet (image, by Squishei) + in-game Adventure Journal
        -- screenshot (name confirmation) + citation URL wowhead.com/
        -- guide/midnight/windrunner-spire-dungeon-overview-location-
        -- rewards. Boss Tips, Key Interrupts/Dispels, and Tips and
        -- Tricks sections used. Mechanic-name strings from the cheat
        -- sheet: Flaming Updrafts, Burning Gale, Splattering Spew,
        -- Heaving Yank, Curse of Darkness, Intimidating Shout, Reckless
        -- Leap, Bolt Gale, Bullseye Windblast, Squall Leap, Phantasmal
        -- Mystic. "Searing Beak" (Emberdawn tank-defensive cue) and the
        -- "focus Mystic first" add-priority refinement on Commander
        -- Kroluk came from user direction against the linked full guide,
        -- not the cheat-sheet image. Encounter-name strings come from
        -- the Adventure Journal; K-protocol diagnostic-print pattern
        -- confirms ENCOUNTER_START payload matches at deploy.
        ["Windrunner Spire"] = {
            encounters = {
                ["Emberdawn"] = {
                    tank = {
                        "Place Flaming Updrafts on room edges.",
                        "Use defenses during Searing Beak.",
                        "Dodge tornadoes and frontal cones.",
                    },
                    healer = {
                        "Place Flaming Updrafts on room edges.",
                        "Dodge tornadoes and frontal cones.",
                    },
                    dps = {
                        "Place Flaming Updrafts on room edges.",
                        "Dodge tornadoes and frontal cones.",
                    },
                },
                ["Derelict Duo"] = {
                    tank = {
                        "Move bosses apart into open areas.",
                        "Place Splattering Spew at room edges.",
                        "Walk behind ghost boss to interrupt Heaving Yank.",
                    },
                    healer = {
                        "Dispel Curse of Darkness.",
                        "Place Splattering Spew at room edges.",
                        "Walk behind ghost boss to interrupt Heaving Yank.",
                    },
                    dps = {
                        "Kill both bosses simultaneously.",
                        "Place Splattering Spew at room edges.",
                        "Walk behind ghost boss to interrupt Heaving Yank.",
                    },
                },
                ["Commander Kroluk"] = {
                    tank = {
                        "Stack for Intimidating Shout fear.",
                        "Grab adds; boss immune until they die.",
                        "Run out, soak second Reckless Leap.",
                    },
                    healer = {
                        "Stack for Intimidating Shout fear.",
                        "Soak Reckless Leap if farthest targeted.",
                    },
                    dps = {
                        "Stack for Intimidating Shout fear.",
                        "Kill summoned adds; focus Mystic first.",
                        "Soak Reckless Leap if farthest targeted.",
                    },
                },
                ["The Restless Heart"] = {
                    tank = {
                        "Spread from Bolt Gale; target stands still.",
                        "Walk into arrow during Bullseye Windblast.",
                        "Clear Squall Leap stacks by hitting arrows.",
                    },
                    healer = {
                        "Spread from Bolt Gale; target stands still.",
                        "Walk into arrow during Bullseye Windblast.",
                        "Clear Squall Leap stacks by hitting arrows.",
                    },
                    dps = {
                        "Spread from Bolt Gale; target stands still.",
                        "Walk into arrow during Bullseye Windblast.",
                        "Clear Squall Leap stacks by hitting arrows.",
                    },
                },
            },
        },
        -- Source for Algeth'ar Academy: Wowhead Midnight Season 1 cheat
        -- sheet (image, by Squishei) + in-game Adventure Journal
        -- screenshot (name confirmation) + citation URL wowhead.com/
        -- guide/midnight/algethar-academy-dungeon-overview-mythic-plus.
        -- Boss Tips, Key Interrupts/Dispels, and Tips and Tricks used.
        -- Mechanic-name strings quoted from source: Germinate, Ancient
        -- Branch, Healing Touch, Deafening Screech, Arcane Orb, Arcane
        -- Fissure, Arcane Rifts, Overwhelming Power. The Crawth ball-
        -- throw line folds the boss tip ("three balls, same goal") with
        -- the Tips-and-Tricks note ("Wind goal first"). Encounter-name
        -- strings come from the Adventure Journal (which lists Vexamus
        -- first, vs. the cheat sheet's third ordering); K-protocol
        -- diagnostic-print pattern confirms ENCOUNTER_START payload at
        -- deploy.
        ["Algeth'ar Academy"] = {
            encounters = {
                ["Vexamus"] = {
                    tank = {
                        "Soak Arcane Orb to drop debuff.",
                        "Keep moving during Arcane Fissure.",
                    },
                    healer = {
                        "Soak Arcane Orb to drop debuff.",
                        "Keep moving during Arcane Fissure.",
                    },
                    dps = {
                        "Soak Arcane Orb to drop debuff.",
                        "Keep moving during Arcane Fissure.",
                    },
                },
                ["Overgrown Ancient"] = {
                    tank = {
                        "Stack during Germinate to clump adds.",
                        "Stand in healing circle to clear bleed.",
                    },
                    healer = {
                        "Stack during Germinate to clump adds.",
                        "Stand in healing circle to clear bleed.",
                    },
                    dps = {
                        "Stack during Germinate to clump adds.",
                        "Stand in healing circle to clear bleed.",
                        "Interrupt Healing Touch from Ancient Branch.",
                    },
                },
                ["Crawth"] = {
                    tank = {
                        "Spread and stop casting during Deafening Screech.",
                        "Throw three balls into Wind goal first.",
                    },
                    healer = {
                        "Spread and stop casting during Deafening Screech.",
                        "Throw three balls into Wind goal first.",
                    },
                    dps = {
                        "Spread and stop casting during Deafening Screech.",
                        "Throw three balls into Wind goal first.",
                    },
                },
                ["Echo of Doragosa"] = {
                    tank = {
                        "Tank boss away from Arcane Rifts.",
                        "At two Overwhelming Power, move to edge.",
                    },
                    healer = {
                        "Dodge orbs away from Arcane Rifts.",
                        "At two Overwhelming Power, move to edge.",
                    },
                    dps = {
                        "Dodge orbs away from Arcane Rifts.",
                        "At two Overwhelming Power, move to edge.",
                    },
                },
            },
        },
        -- Source for Seat of the Triumvirate: Wowhead Midnight Season 1
        -- cheat sheet (image, by Squishei) + in-game Adventure Journal
        -- screenshot (name confirmation) + citation URL wowhead.com/
        -- guide/midnight/seat-of-the-triumvirate-dungeon-overview-
        -- mythicplus. Boss Tips, Key Interrupts/Dispels, and Tips and
        -- Tricks used. Mechanic-name strings quoted from source: Decimate,
        -- Dread Screech, Void Bombs, Overload, Collapsing Void, Mind
        -- Blast, Discordant Beam, Note of Despair, Disintegrate.
        -- Interrupt lines (Dread Screech, Mind Blast) go to DPS only --
        -- never healer (current retail: healers rarely have interrupts)
        -- and not tank (tank can interrupt as backup but doesn't need the
        -- reminder). Trash-only items excluded: four-Rift-Wardens gate,
        -- Chains of Subjugation, and the trash Key Interrupt/Dispel
        -- entries. Encounter-name strings come from the Adventure Journal
        -- ("L'ura", vs. cheat sheet's all-caps "L'URA"); K-protocol
        -- diagnostic-print pattern confirms ENCOUNTER_START payload at
        -- deploy.
        ["Seat of the Triumvirate"] = {
            encounters = {
                ["Zuraal the Ascended"] = {
                    tank = {
                        "Kill or CC slimes before the boss.",
                        "Drop Decimate at edge away from slimes.",
                    },
                    healer = {
                        "Kill or CC slimes before the boss.",
                        "Drop Decimate at edge away from slimes.",
                    },
                    dps = {
                        "Kill or CC slimes before the boss.",
                        "Drop Decimate at edge away from slimes.",
                    },
                },
                ["Saprish"] = {
                    tank = {
                        "Stack bosses to cleave.",
                        "Run into remaining Void Bombs.",
                    },
                    healer = {
                        "Destroy Void Bombs with Overload.",
                    },
                    dps = {
                        "Stack bosses to cleave.",
                        "Destroy Void Bombs with Overload.",
                        "Interrupt Dread Screech when cast.",
                    },
                },
                ["Viceroy Nezhar"] = {
                    tank = {
                        "Move to center during Collapsing Void.",
                    },
                    healer = {
                        "Move to center during Collapsing Void.",
                    },
                    dps = {
                        "Cleave summoned tentacles to lower damage.",
                        "Move to center during Collapsing Void.",
                        "Interrupt Mind Blast from Viceroy Nezhar.",
                    },
                },
                ["L'ura"] = {
                    tank = {
                        "Discordant Beam: hit a Note of Despair relic.",
                        "Rotate in a circle to dodge Disintegrate.",
                    },
                    healer = {
                        "Discordant Beam: hit a Note of Despair relic.",
                        "Rotate in a circle to dodge Disintegrate.",
                    },
                    dps = {
                        "Discordant Beam: hit a Note of Despair relic.",
                        "Rotate in a circle to dodge Disintegrate.",
                        "Burn boss after all relics disabled.",
                    },
                },
            },
        },
        -- Source for Skyreach: Wowhead Midnight Season 1 cheat sheet
        -- (image, by Squishei) + in-game Adventure Journal screenshot
        -- (name confirmation) + citation URL wowhead.com/guide/midnight/
        -- skyreach-dungeon-overview-mythicplus. Boss Tips and Key
        -- Interrupts used. Mechanic-name strings quoted from source: Gale
        -- Surge, Wind Chakrams, Chakram Vortex, Energize, Fiery Smash,
        -- Searing Quills, Sunwings, Lens Flare, Cast Down, Solar Blast.
        -- Interrupt line (Solar Blast) goes to DPS only -- never healer,
        -- and not tank (tank can interrupt as backup but doesn't need the
        -- reminder). Encounter-name strings come from the Adventure
        -- Journal; K-protocol diagnostic-print pattern confirms
        -- ENCOUNTER_START payload at deploy.
        ["Skyreach"] = {
            encounters = {
                ["Ranjit"] = {
                    tank = {
                        "Drop Gale Surge away from the edge.",
                        "Dodge Wind Chakrams and Chakram Vortex.",
                    },
                    healer = {
                        "Drop Gale Surge away from the edge.",
                        "Dodge Wind Chakrams and Chakram Vortex.",
                    },
                    dps = {
                        "Drop Gale Surge away from the edge.",
                        "Dodge Wind Chakrams and Chakram Vortex.",
                    },
                },
                ["Araknath"] = {
                    tank = {
                        "Soak an Energize beam to stop healing.",
                        "Aim boss away from beams; dodge Fiery Smash.",
                    },
                    healer = {
                        "Soak an Energize beam to stop healing.",
                    },
                    dps = {
                        "Soak an Energize beam to stop healing.",
                    },
                },
                ["Rukhran"] = {
                    tank = {
                        "Hide behind center pillar during Searing Quills.",
                    },
                    healer = {
                        "Hide behind center pillar during Searing Quills.",
                    },
                    dps = {
                        "Kill Sunwings apart to stop respawns.",
                        "Hide behind center pillar during Searing Quills.",
                    },
                },
                ["High Sage Viryx"] = {
                    tank = {
                        "Kite Lens Flare laser around the room.",
                        "Kill Cast Down add; targeted runs to entrance.",
                    },
                    healer = {
                        "Kite Lens Flare laser around the room.",
                        "Kill Cast Down add; targeted runs to entrance.",
                    },
                    dps = {
                        "Kite Lens Flare laser around the room.",
                        "Kill Cast Down add; targeted runs to entrance.",
                        "Interrupt Solar Blast on the boss.",
                    },
                },
            },
        },
        -- Source for Pit of Saron: Wowhead Midnight Season 1 cheat sheet
        -- (image, by Squishei) + in-game Adventure Journal screenshot
        -- (name confirmation) + citation URL wowhead.com/guide/midnight/
        -- pit-of-saron-dungeon-overview-mythicplus. Boss Tips and Key
        -- Interrupts used. Mechanic-name strings quoted from source:
        -- Orebreaker, Ore Chunk, Glacial Overload, Shades of Krick, Death
        -- Bolt, Frost Spit, Scourgelord's Brand, Army of the Dead, Scourge
        -- Plaguespreaders. Interrupt lines (Death Bolt, Plaguespreaders)
        -- go to DPS only -- never healer (current retail: healers rarely
        -- have interrupts) and not tank (tank can interrupt as backup but
        -- doesn't need the reminder). "Bosses share health" (Ick and
        -- Krick) omitted -- informational, not an actionable reminder.
        -- Encounter-name strings come from the Adventure Journal;
        -- K-protocol diagnostic-print pattern confirms ENCOUNTER_START
        -- payload at deploy.
        ["Pit of Saron"] = {
            encounters = {
                ["Forgemaster Garfrost"] = {
                    tank = {
                        "Drop Orebreaker on Ore Chunk.",
                        "Hide behind an Ore Chunk during Glacial Overload.",
                    },
                    healer = {
                        "Hide behind an Ore Chunk during Glacial Overload.",
                    },
                    dps = {
                        "Hide behind an Ore Chunk during Glacial Overload.",
                    },
                },
                ["Ick and Krick"] = {
                    tank = {
                        "Kill Shades of Krick quickly.",
                        "Run away when fixated by Ick.",
                    },
                    healer = {
                        "Kill Shades of Krick quickly.",
                        "Run away when fixated by Ick.",
                    },
                    dps = {
                        "Kill Shades of Krick quickly.",
                        "Run away when fixated by Ick.",
                        "Interrupt Krick's Death Bolt.",
                    },
                },
                ["Scourgelord Tyrannus"] = {
                    tank = {
                        "Frost Spit: hit the glowing bone pile.",
                        "After Scourgelord's Brand knockback, avoid the circle.",
                        "Kill Scourge Plaguespreaders after Army of the Dead.",
                    },
                    healer = {
                        "Frost Spit: hit the glowing bone pile.",
                        "Kill Scourge Plaguespreaders after Army of the Dead.",
                    },
                    dps = {
                        "Frost Spit: hit the glowing bone pile.",
                        "Interrupt and kill Scourge Plaguespreaders after Army.",
                    },
                },
            },
        },
    },
}
