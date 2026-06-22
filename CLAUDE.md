# ToxFilter

Shipping name is **Mind Soothe** (renamed from the working name "ToxFilter" in Sprint 8). The identity surface — addon name, display name, slash `/mind`, SavedVariables `MindSootheDB`, chat prefix `[Mind Soothe]`, debug prefix, global frame-name stem — is centralized in `addon/Const.lua` and flows from there; `deploy.sh dev` stamps a local-only "Mind Dev" (`/mdev`) twin from the same source. The two internal feature *categories* "ToxFilter" and "Uplifter" are NOT the product name and keep their names. Historical sprint write-ups below predate the rename and still say "ToxFilter" / `/tox` / `ToxFilterDB` / `ToxFilter.lua`; read those as the now-renamed surfaces (`MindSoothe` / `/mind` / `MindSootheDB` / `MindSoothe.lua`). The Sprint 0 test fixtures (`ToxFilterTest:*`, `[ToxEdit]`, `[ToxDel]`) and the internal `ns.ToxFilter*` namespace handles were deliberately left unrenamed (internal, not product identity).

## What it is

A World of Warcraft addon that filters incoming group/raid/instance/BG chat for the installing user only. The visible mechanism is text filtering; the actual goal is reducing role anxiety for players in high-pressure roles (tanks, healers, mechanics-heavy specs). That framing — role-confidence support, not censorship — drives what we filter, what we preserve, and how we tone every user-facing string.

## Architectural commitments (non-negotiable)

1. **Live path is deterministic only.** No LLM, no remote API, no ML, no network requests on the message-display path. Pure Lua + a static rule table at runtime. LLMs are used only offline (recap generation, central rule classification — both Build 2 territory).
2. **No automation, ever.** Never sends chat, never simulates input, never invokes /reload programmatically. Display-only modification of the user's own chat frame.
3. **No PII anywhere.** Player names, character names, guild names, server names, Battletags get stripped from anything stored or transmitted. Foundational principle even before persistence exists.
4. **Output is for the installing user only.** Never broadcast, never sent to a group, never modifies what other players see.
5. **Blizzard compliance:** free (Policy #1), unobfuscated (Policy #2), no offensive material at rest (Policy #6 — addressed later via hash-encoded rule data).

## Tone

User-facing text — slash command output, system messages, errors, README — is simple, low-affect, factual. No cheerleading, no exclamation points beyond punctuation requirement. Surface facts; the user processes feelings. Strip an adjective if unsure.

**Tonal-violation grep (permanent CI hygiene, every sprint).** Before declaring user-facing string changes done, grep the diff for `!`, `great`, `oops`, `sorry` in any string literal printed via `print(` or `out(`. Cheap; running it consistently keeps drift from accumulating. Self-referential matches (the grep documentation itself, pattern-data tables that legitimately contain words like "great") are acceptable.

Current grep target set:
`addon/Commands.lua addon/PositiveCapture.lua addon/Stats.lua addon/Grounding.lua addon/MindSoothe.lua addon/Const.lua addon/Database.lua addon/Buffer.lua addon/PIIScrub.lua addon/Highlight.lua addon/Breathing.lua addon/Ready.lua addon/Debug.lua addon/Callout.lua addon/JournalData.lua addon/TacticReminders.lua addon/PreDungeonData.lua addon/PreDungeon.lua addon/Category.lua addon/Options.lua addon/CombatDrop.lua addon/Fuzzy.lua`

(As of Sprint 8 `scripts/run-gauntlet.sh` globs `addon/*.lua` minus `Libs/` for the tonal grep and pipe audit, so this list is informational — it no longer has to be kept in lockstep.)

## Repo layout

```
addon/                  WoW addon source — what gets deployed
  MindSoothe.toc        TOC manifest, Interface 120005 (Midnight retail)
  MindSoothe.lua        Main addon code (AceAddon lifecycle, chatFilter dispatch)
  Const.lua             Single-source identity surface (name/slash/SV/prefix/frame)
  Libs/                 Embedded Ace3 (third-party; own licenses; GPLv3 carve-out)
  README.md             Pre-release user-facing description
app/                    Companion app (empty; Build 2)
corpus/                 Test corpora (sprint2/sprint5 JSON; 5b/5c/5d gating + sprint6 scrub Lua)
docs/                   Design docs (empty)
sensitive/              Slur lists / harassment patterns — gitignored
scripts/
  deploy.sh             ship -> AddOns/MindSoothe ; `dev` stamps AddOns/MindDev (local-only)
  run-corpus.sh         host-side corpus + gating test harness
  run-gauntlet.sh       luacheck + corpus + tonal grep + pipe audit, one command
.luacheckrc             Lua static analysis config
.pkgmeta                CurseForge/Wago packager manifest (excludes dev tooling)
LICENSE                 GPLv3 (Ace3 under Libs/ is third-party, not relicensed)
CHANGELOG.md            Version history (0.6.0 → 0.8.0)
CLAUDE.md               This file — current state + active principles
CLAUDE_ARCHIVE.md       Per-sprint detailed write-ups (historical reference)
Verification_Protocol.md  In-game verification steps per sprint
```

## Dev loop

WSL Ubuntu 24.04 → Windows WoW client.

1. Edit Lua/TOC in WSL.
2. `luacheck addon/` from project root — must pass.
3. `./scripts/run-corpus.sh` — all passes (Sprint 2, 5, 5b, 5c, 5d, 6 scrub) 100%.
4. Tonal-grep pass on changed files (see Tone section).
5. Pipe-doubling audit on any new user-facing string (see Conventions).
6. `./scripts/deploy.sh` — rsyncs `addon/` to AddOns folder.
7. In-game `/reload` (manual — addon never triggers /reload itself).
8. Verify per `Verification_Protocol.md` section for the current sprint.

## Current state — Build 1 Sprint 8

Version `0.8.0-sprint8`. Schema **frozen at v11** (no change; the SavedVariables rename is handled by accepting a data reset, NOT migration). Sprint 8 is launch-prep — rename, dual-build, packaging — with no feature/classifier/rule changes. Shipped:

- **Rename to "Mind Soothe"** (working name "ToxFilter" retired). Five identity surfaces: folder `MindSoothe/`, TOC Title `Mind Soothe`, slash `/mind`, SavedVariables `MindSootheDB`, and the addon-name string (`NewAddon`, AceConfig APP token, GUI/Blizzard-menu title, `[Mind Soothe]` chat prefix). The two internal feature *categories* "ToxFilter"/"Uplifter" stay. Sprint 0 fixtures (`ToxFilterTest:*`, `[ToxEdit]`, `[ToxDel]`) and the internal `ns.ToxFilter*` handles (`Addon`/`State`/`Dispatch`) and the file-local `ToxFilter` AceAddon object are deliberately left unrenamed (internal, not product identity).
- **`addon/Const.lua` — single source** (loaded FIRST in the TOC). Holds `ADDON_NAME`, `DISPLAY_NAME`, `SAVEDVAR`, `SLASH_DISPLAY` (`/mind`; bare `SLASH` derived from it so the dev stamp catches it), `PREFIX`, `DEBUG_PREFIX`, `FRAME_PREFIX`. Every former literal routes here: all `print`/`out` prefixes, the SavedVariables global (now `_G[ns.Const.SAVEDVAR]` dynamic indexing in `Database.lua`/`PIIScrub.lua` — so `.luacheckrc` no longer declares it), `RegisterChatCommand`, the AceConfig APP token, the Blizzard breathing-frame global name (`FRAME_PREFIX .. "BreathingFrame"` — a 5th collision surface, now per-build). **Not centralizable:** the TOC `## Title:`/`## SavedVariables:`/`## Version:` lines (a `.toc` can't read Lua — kept in sync by the same dev-stamp tokens) and the `/mind` mentions in help copy (display text rewritten to literals; the runtime token still derives from `SLASH`).
- **Version single-sourced** from the TOC `## Version:` via `C_AddOns.GetAddOnMetadata(ns.Const.ADDON_NAME, "Version")`. The hardcoded Lua `VERSION` literal is gone. (`C_AddOns` added to `.luacheckrc`; the corpus pause harness stubs it.)
- **Dual-build** (`scripts/deploy.sh [ship|dev]`): ship rsyncs `addon/` verbatim to `AddOns/MindSoothe/` (committed tree IS ship identity — directly packageable). `dev` stages a throwaway copy under `.build/` (gitignored), applies THREE substitutions (`MindSoothe→MindDev`, `Mind Soothe→Mind Dev`, `/mind→/mdev`), then renames BOTH `MindSoothe.toc→MindDev.toc` (folder-match requirement) AND `MindSoothe.lua→MindDev.lua` (the stamp rewrote the TOC's `MindSoothe.lua` source-file reference to `MindDev.lua`, so the file on disk must match or WoW silently skips the main module and the addon never registers its slash — the post-deploy dev-build bug, fixed), and rsyncs to `AddOns/MindDev/`. All four-plus collision surfaces differ (folder, Title, slash `SLASH_MIND1`/`SLASH_MDEV1`, SavedVariables, AceAddon/AceConfig registration, frame name) → coexist with zero collision. Dev build is LOCAL-ONLY: never committed, never packaged.
- **Packaging:** GPLv3 `LICENSE` (verbatim FSF text; Ace3 under `Libs/` is third-party, not relicensed — noted in README), `.pkgmeta` (excludes `scripts/`, `corpus/`, `CLAUDE.md`, docs, `.build`, `sensitive`, `*.bak.*`; `move-folders: MindSoothe: addon` for the subfolder layout), `CHANGELOG.md` (0.6.0→0.8.0), `scripts/run-gauntlet.sh` (luacheck + corpus + tonal grep + pipe audit, exits nonzero on any failure; tonal+pipe scoped to `print(`/`out(` lines over `addon/*.lua` minus `Libs/`). `.gitignore` gains `.build/` + `*.bak.*`.
- **F1/F2 whisper-note honesty (doc/string only, no code fix):** README no longer claims the one-shot whisper privacy note prints (reworded to a known-limitation note); the `Commands.lua` whisper-note comment is the deferred code fix's territory and untouched beyond the rename. The code path is unchanged this sprint.
- **TOC Interface** stays `120005`; developer reconfirms against the live patch at upload.
- Gauntlet green at handoff: luacheck 0/0 (31 files), full corpus 100% (incl. scrub corpus under the renamed SV global and the N12 pause-dispatch under `MindSoothe.lua` + `C_AddOns` stub), tonal grep + pipe audit clean.
- **In-game verification PASSED (Sprint 8 scope):** both builds install as separate AddOns-list entries with isolated data; ship "Mind Soothe" responds to `/mind` (and not `/mdev`), dev "Mind Dev" responds to `/mdev` (and not `/mind`). The post-deploy dev-build bug above (TOC `MindDev.lua` reference vs on-disk `MindSoothe.lua`) was caught in this verification and fixed before it passed. (Broader per-feature in-game verification — the pending 5b/7a items elsewhere in this doc — is unchanged by Sprint 8.)
- **Flagged for the developer (not done here):** the stale README body (Sprint-5-era feature copy — listing-copy territory) and the stale `Verification_Protocol.md`; the two leftover `claude/*` branches; the pre-public git-history audit; the GitHub rename + visibility flip; the actual CurseForge/Wago upload. The CHANGELOG's `[Sprint 7b]` entry reflects 7b's *defined scope* — CLAUDE.md's prior "Current state" lagged at 7a, so confirm/adjust whether 7b shipped.

### Prior — Build 1 Sprint 7a

Version `0.7.0-sprint7a-fix`. Schema v11. Shipped in 7a (feature build; 7b is later — classifier tuning, content language polish, full regression pass — do NOT start tuning here). The `-fix` suffix marks the post-verification corrections folded in: emote untargeted-capture removed (N22), the fuzzy length floor hardened to be both-ended in one place (N16), and the fresh-install callout-sound default moved to `8959` ("readycheck2"):

- **Feature 1 — silent-drop carve-out (currently inert)** (`addon/CombatDrop.lua`): a paused-branch carve-out *intended* to silent-drop high-confidence *pure* hostility during the Midnight combat pause. **N12 established that `chatFilter`'s paused branch is never invoked in combat** (the filter does not run, and in-combat chat text is a secret/tainted value) — the same wall callouts hit. `CombatDrop.shouldDrop` is called **only** in that paused branch (`ToxFilter.lua:225`) and is **not wired into the non-paused path**, so the carve-out has **no runtime effect in any state today**: dead code in combat, and absent out of combat. Retained for the pause-dispatch guard; the toggle is kept (DEFAULT ON, v11) for a possible future non-paused home. Out of combat, pure slur/harm is handled by **normal category handling** (`slur`→edit, `harm_invocation`→del per `Categories.HANDLING`), independent of this toggle — there is no out-of-combat *silent* drop of slur/harm by default. The classification gate itself is correct and corpus-tested (errs narrow): winning category ∈ `{ slur, harm_invocation }` (identity_attack deliberately excluded — sparse rule coverage, worst place for a blind silent drop; editable in `CombatDrop.CATEGORIES`), `handling ~= "pass"`, and **purity** = no token carries the `"tactical"` label (any tactical/informational content → not pure). `CombatDrop.shouldDrop` folds in the toggle + `Category.gate("toxfilter")` (which includes the master); when the dead branch flags, the flagged-event write would record classification metadata only (category, severity, `combat=true`) — never the body. `ToxFilterTest:Silent` is silent-dropped in-game by the **non-paused Sprint 0 fixture** (`chatFilter` fixture stage, step 9), *not* by the paused carve-out (inert), so the earlier "rides the combat path" claim and the G3-widening erratum are moot. `/tox combat [on|off]`; GUI toggle under ToxFilter. **User-facing strings (resolved — Sprint 7b Track 2a):** the `/tox status` and `/tox state` paused lines no longer claim silent-drop is active; `/tox combat` output, the GUI toggle name/desc, and `README.md` (Limitations section) all describe the toggle as having no current effect, retained for a possible future out-of-combat home.
- **Feature 2 — selectable callout sound** (`addon/Callout.lua`): `Callout.SOUND_CHOICES` is one easily-edited `{id,name,label}` table (ids PROVISIONAL — audition via preview and swap). `playSoundIfEligible` reads `callout_sound_id` via `Callout.CurrentSoundId` (falls back to the `CALLOUT_SOUND_ID` constant if the stored id is no longer a valid choice). Fresh-install default is `8959` ("readycheck2", "Ready check, low") in both `DEFAULTS` and the `CALLOUT_SOUND_ID` fallback; the `migrations[11]` backfill still seeds `8960` so v10→v11 upgraders keep their existing cue (no schema bump — default change reaches fresh SavedVariables only). `/tox callout sound on|off` unchanged; added `set <name>` / `list` / `preview <name>`. GUI dropdown under Uplifter→Callout previews on select.
- **Feature 3 — typo tolerance** (`addon/Fuzzy.lua`): Damerau distance-1 (`within1`, direct O(n), no DP table) for the positive-capture (`THANKS_TOKENS`/`POS_VERBS`/`POS_PLAYS`) and callout (`CALLOUT_VERBS`) keyword sets ONLY — never the classifier/rule engine/blacklist/whitelist (load-bearing scope line). Guards: length floor 5 (short keywords exact-only) and **role targets always exact-only** (a typo firing the wrong-role callout is the expensive failure; a fuzzy verb can only fire alongside a correctly-spelled role anchor). Exact lookup stays the hot path; fuzzy only on miss, length-bucketed against <50 keywords — negligible per-message cost.
- **Feature 4 — emote capture** (`addon/PositiveCapture.lua` `emoteDetect`/`captureEmote`, `CHAT_MSG_TEXT_EMOTE` handler in `ToxFilter.lua`): a single match rule — an emote verb (`thank`/`cheer`/`salute` + plural forms) AND a self-target token ("you"/"your"), i.e. the emote is aimed at the player ("Bob thanks you.", "Dave cheers at you."). Untargeted emotes ("Bob cheers.", "Bob thanks everyone.") and third-party emotes ("Bob cheers at Carol.") carry no self-target token and are NOT captured. (The 7a-fix N22 correction removed an earlier `BROADCAST_VERBS` rule that captured untargeted `/thanks`/`/cheer`.) Captured as positive moments. Own outgoing emotes skipped (sender == player guard). Records via `RecordPositiveMoment` with `direct_to_user=true` so it increments the same thanks counters; `signals.emote` drives a `(emote)` marker in `/tox positive`/`lift`/`starred`. PII-scrubbed like any capture; self-gates on `Category.gate("uplifter")`. **enUS-only by construction** (documented in code + README). v11 adds no field for F3/F4.
- **Schema v11 (sole Sprint 7 bump):** `migrations[11]` backfills exactly two fields — `callout_sound_id=8960`, `combat_silent_drop=true` — and nothing else.
- Corpus: `corpus/sprint7a_combat.lua` (18 checks — gate truth table via real classify→shouldDrop), `corpus/sprint7a_fuzzy.lua` (14 — distance-1 positives fire, short-word/role-target guards hold incl. the N16 `rank`/`task`/`tans`-vs-`tank` regression, must-not-fire slur variant stays pass + uncaptured), `corpus/sprint7a_emote.lua` (9 — emoteDetect logic incl. the N22 untargeted-emote non-capture; event wiring + self-sender guard + enUS rendering are in-game-only). Harness loads `Fuzzy`/`CombatDrop`/`PositiveCapture`.
- **N12 — callouts suppressed in combat — RESOLVED: in-combat chat handling is impossible; callouts are out-of-combat-only.** The investigation peeled three layers: (1) the ChatFrame message filter is **not invoked** during the Midnight pause (a hooked `CHAT_MSG_INSTANCE_CHAT` produced no `chatFilter received` debug line while `ENCOUNTER_START` reminders fired) — so the first two "reorder the paused branch" fixes could never work; (2) an AceEvent `OnCombatChat` subscription *did* fire in combat, but died with `attempt to compare execution tainted by 'ToxFilter'` — first traced to the protected spec read in `GetEffectiveRole` (`GetSpecialization`/`GetSpecializationRole`), worked around with an out-of-combat role cache; (3) the **final wall**: `attempt to compare local 'msg' (a secret string value, while execution tainted)` — Midnight delivers the chat message text itself to in-combat handlers as a **secret/tainted value that cannot even be read or compared in combat**. There is no taint-avoidance for this: no addon can inspect chat during a boss fight. **Final state:** `OnCombatChat`, its AceEvent registration, the role cache (`cachedRole`/`refreshRoleCache`/`OnCombatStart`/`PLAYER_REGEN_DISABLED`), the `pcall` taint firewall, `Callout.SurfaceCombatCallout`, and `Callout.matchesUserRole` are all **deleted**. Callouts run only out of combat, via the chat-filter tint path (original Sprint 5 behavior). During the pause NO callout code runs at all. The `chatFilter` paused branch still contains the callout-tint code but is dead in combat (filter not invoked) — retained for the dispatch guard and harmless.
  - **Survivor from the N12 work — event-name fix + init hardening (kept).** Registering the group `CHAT_MSG_*` events via `RegisterEvent` (during the since-removed `OnCombatChat` experiment) surfaced that **`CHAT_MSG_BATTLEGROUND` / `CHAT_MSG_BATTLEGROUND_LEADER` were removed from the WoW API** (verified via warcraft.wiki.gg; BG chat now arrives as `CHAT_MSG_INSTANCE_CHAT`). They were dropped from `CHAT_EVENTS` (no coverage lost — `ChatFrame_AddMessageEventFilter` had silently tolerated the dead names). Hardening kept even though the event loop is gone: `RegisterChatCommand("tox")` is the FIRST line of `OnEnable`, so no later `RegisterEvent` throw can ever skip slash registration again. The vestigial `battleground` channel toggle is left for 7b to reconcile or retire.
- **N12 pause-dispatch guard** (`corpus/sprint7a_pause.lua` + `scripts/pause-dispatch.lua`, 8 checks): a separate Lua process that loads `ToxFilter.lua` with WoW-API stubs and drives the real `chatFilter` through `isPaused` via the `ns.ToxFilterDispatch` hook (`chatFilter`, `setPausedForTest`) — callout tints when paused, toggles/role/silent-drop all gate correctly. (The in-combat `OnCombatChat`/RaidNotice fixtures were removed with that code; there is no in-combat path left to model.)

### Prior — Build 1 Sprint 6b

Version `0.6.0-sprint6b`. Schema v10. Shipped since 5d:

- **Sprint 6 — PII scrub audit + remediation** (`addon/PIIScrub.lua`): live-path name scrubber broadened from narrow post-thanks Capword matching to known-name matching against the sender (CHAT_MSG_* author, threaded `chatFilter → capture → RecordPositiveMoment → scrub`), the user's current character, and the alt roster from AceDB profileKeys. Case-insensitive, connected-realm-suffix-aware (strips `Name-Realm` whole), position-independent. Precision over recall: only KNOWN names are stripped, never names guessed from token shape; a known name that is also a class/role word or acronym is spared (B1 collision rule) so positive moments stay intact. Orphan `feedback_log` field removed (schema v9 → v10, defensive no-op clear). 18-fixture scrub corpus in `corpus/sprint6_scrub.lua`. Audit findings in `PII_Audit_Sprint6.md`.
- **Sprint 6b — options panel** (`addon/Options.lua` + embedded AceGUI-3.0/AceConfig-3.0): AceConfig panel registered into the Blizzard AddOns menu from `OnInitialize`. A view over existing db state, never a parallel store — every control's get/set reads and writes the same db fields (or calls the same ns.* methods) the slash commands use. Options table is registered as a function so dynamic list editors (blacklist/whitelist/grounding) and category `disabled()` closures re-evaluate each render. Category greying displays preserved sub-toggle values (Sprint 5d sub-state preservation made visible). `/tox config` opens the panel; `/tox state` is a dense one-block readout of every toggle layer. Accepted 6b limitation: slash-command changes made while the panel is open may display stale until reopen (in-panel changes do call `NotifyChange`).

Sprint 5c/5d detail below is retained as recent reference:

- **Sprint 5c — pre-dungeon warnings** (`addon/PreDungeon.lua` + `addon/PreDungeonData.lua`): role-filtered Key Interrupts / Key Dispels / Tips surfaced once per Mythic+ key at `CHALLENGE_MODE_START` (before `setPaused(true)`), dual-surface (chat + `RaidWarningFrame`). `PREDUNGEON_DATA_VERSION = 0` — infrastructure only; interrupt/dispel/tip content authoring is pending per the per-dungeon approval workflow. Empty categories (no dispels, no tips) are a first-class state and produce no output (never a bare header). `/tox warnings [on|off|reset]`; default off; seen-map session-scoped (cleared in `OnInitialize`); schema v8.
- **Sprint 5d — category master toggles** (`addon/Category.lua`): two families — ToxFilter (chat hygiene) and Uplifter (confidence) — gated by `/tox category toxfilter|uplifter on|off`. `Category.gate(name)` folds the addon master (`db.enabled`) and the category bit into one live check, giving a `master → category → per-feature` hierarchy. Both default ON (migration v9). Per-feature sub-state is preserved across category off/on. User-invoked commands bypass the gate; passive surfacing and chat handling respect it. Stats *counting* keeps running when Uplifter is off (only *surfacing* is gated); positive *capture* is gated off. `/tox off` is now a true addon-wide kill — it also stops event-driven Uplifter surfacing that previously ignored it. 26-check gating corpus in `corpus/sprint5d_gating.lua`.

The 5b-polish detail below is retained as historical reference.

**Sprint 5b shape:**

- `addon/JournalData.lua` — static encounter-data table, hand-curated per dungeon. `METADATA.JOURNAL_DATA_VERSION` reserved for Sprint 8's distribution pipeline.
- `addon/TacticReminders.lua` — gating + Lookup + Surface. Public surface: `Surface(instance, encounter, bucket)`, `ResetSession()`, `Lookup(...)`, `CountEncounters()`, `CountSeen()`.
- `db.tactic_reminders_enabled` (default off, opt-in) + `db.tactic_reminders_seen` (session-scoped despite db storage; cleared in `OnInitialize`).
- `/tox reminders [on|off|reset]` — master toggle + session re-arm.
- Schema migration v6 → v7 backfills the two fields.
- `OnEncounterStart` calls `TacticReminders.Surface` BEFORE `setPaused(true)` so the function's internal `isPaused()` guard doesn't block the natural firing path.
- 12-scenario gating-test corpus in `corpus/sprint5b_gating.lua`; harness extended in `scripts/run-corpus.sh`.
- **Dual-surface display (polish):** Surface writes the existing multi-line block to chat (review log, full `Dungeon (bucket) — Role reminders:` header) AND posts a tighter version to `RaidWarningFrame` via `RaidNotice_AddMessage` (header `Role — Encounter:`, then one warning-frame line per mechanic). RaidWarningFrame is a local widget; `RaidNotice_AddMessage` writes directly to the user's screen and never broadcasts. Broadcasting would be `SendChatMessage(..., "RAID_WARNING")`, which this addon never calls. No audio cue — the on-screen visual is the cue; adding audio would risk doubling raid-warning sounds played by other addons.

**JournalData authoring rules (load-bearing for content sprints):**

1. **Source-required.** Content for the four Midnight-rebuilt dungeons (Magisters' Terrace, Maisara Caverns, Nexus-Point Xenas, Windrunner Spire) must come from user-provided source material — never from training data. Same applies to the four legacy-layout dungeons (Pit of Saron, Skyreach, Algeth'ar Academy, Seat of the Triumvirate) unless explicitly tagged HIGH/MEDIUM/LOW confidence and verified by the user. Confidently shipping wrong mechanics betrays the very users the project exists to support.
2. **6 words ±2, verb required, mechanic-named.** Target 6 words per reminder, range 4-8. Every reminder includes an imperative verb. Preserve proper-noun mechanic names. Terminal period included.
3. **Reminders, not tutorials.** The player already knows the mechanic or has looked it up elsewhere. The reminder's job is recall, not teaching.
4. **Role-split preferred when mechanics differ across roles.** The addon only renders on the user's screen, so role-flavored reminders never leak to other roles. Clarity for the surfaced role beats compactness across roles. Universal mechanics: role-duplication is fine.
5. **Per-dungeon approval workflow.** Propose planned reminders in chat per dungeon; wait for explicit lock before writing to `addon/JournalData.lua`. One dungeon at a time. Never bulk-propose.

**Current JournalData coverage:** All eight dungeons locked — Magisters' Terrace, Maisara Caverns, Nexus-Point Xenas, Windrunner Spire, Algeth'ar Academy, Seat of the Triumvirate, Skyreach, Pit of Saron. `JOURNAL_DATA_VERSION = 8`. In-game verification still pending (not all zones tested for bugs yet).

## Load-bearing decisions (don't regress)

Decisions reached through in-game testing or verification cycles that future sprints must respect. Each lives in `CLAUDE_ARCHIVE.md`'s relevant sprint section with full reasoning; this is the index.

**Live-path / detection:**

- **Disposition rule (Sprint 2):** in surgical rewrite, drop only `attack`-labeled tokens; preserve everything else (tactical AND neutral outside attack spans). Conservatism direction: drop is the exceptional path, preserve is the default. If a neutral at an attack-span edge survives, fix the absorption-list / NEG_MODIFIERS coverage, not the Rewrite disposition.
- **Attack-span vs winning-category decoupling (Sprint 2):** rule-hit winning category determines `result.category`; classifier `labels` are the source of truth for Rewrite. Don't couple span identification to winning-category.
- **Blacklist routes to edit (Sprint 4 fix):** user blacklist hits hardcode `handling = "edit"` regardless of category default OR user `/tox handle` override. Inline at the blacklist branch in `RuleEngine.lua` with comment block citing this decision.
- **Channel-off doesn't short-circuit (Sprint 4 fix2):** `chatFilter` always runs the rule engine and (when verdict is `pass`) `PositiveCapture.capture`; channel-off only suppresses handling (silent/del/edit) and the highlight tint. Whisper is the privacy exception — `PositiveCapture.capture` returns nil unconditionally when whisper is opted out.
- **Time-critical UI vs passive UI (Sprint 5; amended by N12):** passive UI for emotional support pauses during the Midnight combat window (Sprint 4b Highlight). Sprint 5's intent was that time-critical callouts stay active during combat — but **N12 proved this is impossible on Midnight**: chat filters aren't invoked in combat and in-combat chat text is a secret/tainted value, so callouts are out-of-combat-only like the passive UI. The only UI that works in combat is pull-boundary, pre-registered surfaces: Sprint 5b's TacticReminders fires pre-pull from `OnEncounterStart`, so the pause question is moot for it.

**Storage:**

- **Counters: permanent. Events: windowed. (Sprint 4a)** Counters never prune. Windowed events (positive_moments, flagged_events, activity_log) prune on addon load via `Buffer:Prune(retention_days)`. Pinned moments never prune. Activity log is the source of truth for any time-windowed aggregate.
- **Counter shape (Sprint 4 fix):** `db.session_buffer.counters.instances[<instance>][<bucket>]` where bucket ∈ `normal | heroic | mythic | M0 | M2-5 | M6-10 | M10+`. Scope filter (locked): `PLAYER_DEAD` / `ENCOUNTER_END` / `CHALLENGE_MODE_COMPLETED` only count when `instanceType` is `party` (5-player) or `raid`. No world-death counter.
- **Bucket precedence:** M+ keystone bucket is sticky across pulls from `CHALLENGE_MODE_START` to `CHALLENGE_MODE_COMPLETED`/`RESET`. Encounter-level bucket is per-pull from `ENCOUNTER_START` to `END`. `effectiveBucket() = mplus_bucket or encounter_bucket or bucketForDifficulty(<current GetInstanceInfo difficultyID>)`.

**Asymmetric display:**

- **Stats surfacing (Sprint 4a):** live encounter/dungeon stat surfacing fires only when reassuring. First-attempt → always surface. Wipe rate ≤ threshold → surface. Wipe rate > threshold → suppress silently. The user is never told their wipe rate is "too high to surface."
- **Live vs user-invoked:** live filtering and live surfacing respect their toggles; user-invoked (`/tox stats`, `/tox week`) is always honored regardless of toggle.

**Category master toggles (Sprint 5d):**

- **Three-layer gate.** `master (db.enabled) → category (category_<fam>_enabled) → per-feature toggle`. `ns.Category.gate(name)` collapses the top two and is the live gate; `ns.Category.isEnabled(name)` reports the category bit alone (for `/tox status` and `/tox list`). ToxFilter family = rule-engine handling + Sprint 0 fixtures (gated in `chatFilter`). Uplifter family = capture, highlight, callouts, reminders, warnings, stats *surfacing*. Each feature calls `gate` at its existing toggle point (chatFilter call sites for callout/handling/highlight/fixtures; internal self-gate in `PositiveCapture.capture`, `TacticReminders.Surface`, `PreDungeon.Surface`, `Stats.OnEncounterStart`/`OnChallengeModeStart`).
- **Counting is not gated.** Stats *surfacing* is Uplifter; the underlying `Buffer:Record*` counting (encounter/death/key-complete handlers) keeps running when Uplifter is off so `/tox stats` stays gap-free. Positive-moment *capture*, by contrast, IS gated off — it's a named Uplifter feature, not incidental storage.
- **Sub-state preservation (locked).** Toggling a category never writes per-feature toggles; resuming a category restores features as they were. Load-bearing for the Sprint 6b GUI.
- **User-invoked bypass.** `/tox lift`, `/tox stats`, `/tox breathe`, etc. work regardless of category state — extends the Sprint 4a live-vs-user-invoked rule above.
- **`/tox off` is addon-wide.** Because `gate` includes `db.enabled`, the master now also stops the event-driven Uplifter surfacing (reminders, warnings, stats) that historically ignored it.

**UI primitives:**

- **Highlight two-surface design (Sprint 4b):** sync helper `Highlight.tintIfEligible` is called inline from `chatFilter` for return-value tint. Subscriber `Highlight.OnPositiveMoment` is a no-op observer that preserves the subscriber API for future modules. Don't collapse the two surfaces.
- **Color register table:** `|cFF66AA66` desaturated green = positive moments (passive, pauses). `|cFFEEBB55` warm amber = role callouts (out-of-combat-only per N12; the chat-line tint cannot render in combat). Future sprints adding tints check this list before picking.

**State-persistence trap pattern (Sprint 4 fix2 / Sprint 5 fix / Sprint 5 fix2):**

AceDB preserves explicit non-default writes across `/reload`. Three documented instances:
1. F18 — `whisper_intro_shown` persisted `true` and masked re-test (fixed via migration v5 one-shot reset).
2. Sprint 5 fix — sub-toggle off-state persisted; user re-enabled master and saw silent feature (diagnostic prints surfaced it).
3. Sprint 5 fix2 — same pattern; UX fix via `Callout.GetStateMismatchNote()` surfaced inconsistency.

**Generalized rule:** any feature with master + N sub-toggles surfaces a state-mismatch note when master is on but a sub-toggle is off. Verification protocols re-arm sub-toggle state in Phase 0 before testing master-toggle behavior.

**Diagnostic-print discipline:**

Debug-gated prints (gated on `g.debug_enabled`) are permanent infrastructure, not removed after the bug they helped diagnose ships. Current set: counter increments in `Buffer.lua`, encounter-start logging in `Stats.lua`, chatFilter entry + Callout detect/matchesUser results in `ToxFilter.lua`/`Callout.lua`, TacticReminders gating in `TacticReminders.lua`. Zero cost when off.

## chatFilter dispatch order (current — Sprint 5 final; Sprint 5d category gates layered on)

```
1. master toggle off                            -> pass
2. RuleEngine.classify (read-only; always runs)
3. Callout.detect + matchesUser (read-only). NOTE (N12): in real combat the chat filter is never invoked, so this paused-branch path is dead in combat — callouts are out-of-combat-only. Retained for the pause-dispatch guard.
4. If paused:
     - channel-on AND callout matches: tint + sound, return tinted
     - channel-on AND `CombatDrop.shouldDrop(result)` (Sprint 7a F1): silent-drop
       (return true) + flagged-event write (metadata only). NOTE (N12): like the
       callout path above, this paused branch is never invoked in combat, so this
       is dead code — retained for the pause-dispatch guard. F1 is not wired into
       the non-paused branch either, so the silent-drop carve-out is inert in all
       states (see Current state, Feature 1).
     - channel-on AND `combat_silent_drop` + ToxFilter category + `ToxFilterTest:Silent`
       substring (Sprint 7a F1): silent-drop test path — also dead in combat. The
       working `ToxFilterTest:Silent` test runs through the non-paused fixture (step 9).
     - otherwise: pass
5. Non-paused, channel-on: handling (silent/del/edit) with flagged-event buffer write
6. Non-paused: PositiveCapture.capture on `pass` verdict (whisper carve-out inside)
7. Non-paused, channel-on: callout match preempts positive Highlight (callout color wins; sound plays once)
8. Non-paused, channel-on: Highlight.tintIfEligible only when no callout match
9. Non-paused, channel-on: Sprint 0 fixtures
```

Sprint 5b's TacticReminders is event-driven (`ENCOUNTER_START`), not chatFilter-routed. It surfaces before `setPaused(true)` in the encounter-start handler, independent of this chain. Sprint 5c's PreDungeon is likewise event-driven (`CHALLENGE_MODE_START`, pre-pause).

**Sprint 5d category gates layered on this chain:** the ToxFilter category gate (`Category.gate("toxfilter")`) wraps step 5's handling and step 9's fixtures; the Uplifter gate (`Category.gate("uplifter")`) wraps callout detection (feeding steps 4 and 7), capture (step 6, self-gated inside `PositiveCapture.capture`), and Highlight (step 8). The event-driven Uplifter surfacing (TacticReminders, PreDungeon, Stats) self-gates on `Category.gate("uplifter")` at its entry. `Category.gate` includes `db.enabled`, so `/tox off` short-circuits all of it.

## Sprint 0 fixtures (still active)

Hardcoded test triggers preserved as architectural-validation tests. The rule engine runs first; fixtures only fire when no rule matches and the channel is enabled.

| Trigger substring         | Mode               | Display |
|---------------------------|--------------------|---------|
| `ToxFilterTest:Pass`      | Pass-through       | unchanged |
| `ToxFilterTest:Edit`      | Surgical rewrite   | `[ToxEdit] <body with trigger removed>` |
| `ToxFilterTest:Del`       | Visible deletion   | `[ToxDel: TestCategory]` |
| `ToxFilterTest:Silent`    | Silent drop        | (nothing rendered) |

Edit-mode format: prefix-plus-removal. Tag prefixed at start of line; offending substring removed from body; whitespace collapsed.

## Midnight restricted-execution pause

Blizzard's Midnight expansion restricts addon code execution during boss encounters and Mythic+ pulls. **Confirmed N12 findings:** (1) the restriction extends to ChatFrame message filters — `chatFilter` is NOT invoked for incoming chat during the pause (a hooked `CHAT_MSG_INSTANCE_CHAT` produced no debug entry in combat while AceEvent-driven reminders fired); and (2) the chat message text delivered to any in-combat event handler is a **secret/tainted value that cannot be read or compared in combat**. Together these make in-combat chat inspection impossible for any addon, so there is no in-combat callout/handling path — callouts and chat filtering are out-of-combat-only. The paused branch of `chatFilter` is effectively dead code in real combat (the filter isn't invoked); it is retained for the `pause-dispatch` guard and is harmless. Only pull-boundary, pre-registered surfaces work in combat — e.g. the tactic-reminder `RaidWarningFrame` surface, which fires BEFORE `setPaused` in the encounter-start handler.

**Hooked events:** `ENCOUNTER_START`/`ENCOUNTER_END`, `CHALLENGE_MODE_START`/`CHALLENGE_MODE_COMPLETED`/`CHALLENGE_MODE_RESET`. Classical events present across many expansions, fire reliably.

**Known gaps (revisit during in-game verification):**
- Midnight may have introduced additional event names specifically for restricted-execution windows we haven't hooked. Anything Midnight added is additive; classical events still fire so this isn't silently broken, just possibly incomplete.
- PvP: `PVP_MATCH_ACTIVE` covers entire BG/arena matches rather than per-fight restricted windows. Need to determine what Midnight actually restricts in PvP before adding pause coverage.
- Mid-encounter reload: if user `/reload`s during an active encounter, `ENCOUNTER_START` won't re-fire and `isPaused` will be `false` (incorrectly).

## Conventions

- Lua module-local state for module-private values; AceAddon methods for things called via the lifecycle/callback registry.
- WoW API globals are declared in `.luacheckrc` as `read_globals`. Add new ones as we use them.
- TOC paths use backslashes (Windows convention; WoW client accepts on both OSes).
- Ace3 lives under `addon/Libs/` and is excluded from luacheck.
- All user-visible chat output uses literal `[ToxFilter]` prefix via `print()` for consistent format regardless of origin.
- **Pipe characters in chat strings must be doubled (`||`).** WoW's chat-frame parser treats `|` as the lead-in for color escapes (`|cffrrggbb...|r`), hyperlinks (`|H...|h...|h`), textures (`|T...|t`), etc. A literal `|r` in help text gets eaten as a color reset. Discipline:
  - **Literal display pipes** (e.g. `<a|b|c>` choice notation in help text) — double to `||`.
  - **Functional WoW escapes** (`|c<AARRGGBB>`, `|r`, `|H...|h...|h`, `|T...|t`) — keep as single pipes.
  - Pipe-doubling audits exclude `|c[0-9A-Fa-f]{8}` and `|r` patterns when scanning files that legitimately use color escapes (Highlight.lua, Callout.lua; future UI modules).

## What's out of scope per sprint (forward-looking only)

Shipped-sprint detail lives in `CLAUDE_ARCHIVE.md`. Future work:

- **Sprint 5b content:** complete — all eight dungeons locked. In-game verification still pending (not all zones tested for bugs yet).
- **Sprint 5c content:** pre-dungeon warning data (interrupts/dispels/tips) per the per-dungeon approval workflow; `PREDUNGEON_DATA_VERSION` still 0.
- **Build 1 Sprint 7a:** feature build — shipped (see Current state). In-game verification still pending.
- **Build 1 Sprint 7b:** classifier tuning + content language polish + full regression pass with threshold-gate enforcement. Locked targets: slur ≥98%, role_attack ≥90%, harm_invocation ≥95%, identity_attack ≥90%, harassment ≥70%, general_hostility ≥60%, rewrite correctness ≥90%. Tuning pass: under-absorbed neutrals at attack-span edges; spec-name attack detection; absorption-list expansion. (Do not start tuning before 7b.)
- **Build 1 Sprint 8:** shipped (see Current state) — rename to Mind Soothe, dual-build, packaging (`LICENSE`/`.pkgmeta`/`CHANGELOG.md`/`run-gauntlet.sh`), single-sourced version. In-game verified for the dual-build slash/isolation. **Remaining (developer-handled, not this sprint):** the actual CurseForge/Wago upload + listing copy, the pre-public git-history audit, and the GitHub rename + visibility flip. `METADATA.JOURNAL_DATA_VERSION` still enables future content-only update packaging.
- **Build 1 Sprint 9:** configuration UI — shipped early as Sprint 6b's options panel; remaining Sprint 9 scope (if any) to be decided.
- **Build 2:** companion app — LLM-based recap generation, central rule classification.
- **Build 3:** central rule service.

Don't pre-build any of these. Each sprint validates a layer; later sprints add functionality on top.

## Things that are NOT in this repo

- The slur/harassment-pattern corpus lives under `sensitive/` and is gitignored. Must not be committed, must not be referenced in code by any public identifier.
- Anything LLM-related (recap generation, central rule classification) lives in the companion app, not in the addon.

## Sprint history index

Each entry corresponds to a detailed section in `CLAUDE_ARCHIVE.md`. The archive is authoritative when implementing a fix or extension that touches a load-bearing decision.

- **Sprint 0** — skeleton + four-mode dispatcher + Midnight pause logic.
- **Sprint 1** — rule engine, FNV-1a hash, normalization pipeline, encoded rule data, six categories.
- **Sprint 2** — constructive-vs-hostile classifier, surgical rewrite, corpus harness; disposition rule and attack-span/winning-category decoupling established here.
- **Sprint 3** — AceDB persistence, full slash suite, whisper hook; schema v1.
- **Sprint 3 fix1** — `/tox role auto` crash, pipe-doubling rule established, channel-list master-state header.
- **Sprint 4a** — session buffer, positive-moment capture, pinned moments, asymmetric stats surfacing, grounding ritual; schema v2.
- **Sprint 4b** — chat-line Highlight UI, animated box-breathing frame, `/tox ready` orchestration; schema v3; color-code escape carve-out from pipe-doubling rule.
- **Sprint 4 fix** — ASCII arrows, channel alias, default interpolation, blacklist-edit routing, whisper text, instance+bucket counter shape rebuild, breathing combat-cancel, `/tox debug` developer tool; schema v4.
- **Sprint 4 fix2** — whisper privacy bit reset (migration v5); channel-off no longer short-circuits capture (whisper privacy carve-out); `-Server` suffix strip; `/tox positive ui` no-arg toggles; combat-lockdown gate; cycle indicator; `/tox ready cancel`.
- **Sprint 4 fix3** — `count` alias for `counter`; diagnostic-print pattern established as permanent infrastructure; Hypothesis B (encounter pull required for surfacing) documented.
- **Sprint 5** — tactical role-callout prioritization (warm-amber tint + audio cue, `/tox callout`); time-critical-vs-passive UI principle established; schema v6.
- **Sprint 5 fix** — audio swap `540061` → `8960`; diagnostic-print discipline extended; sub-toggle state-persistence trap diagnosed.
- **Sprint 5 fix2** — `Callout.GetStateMismatchNote()`; state-persistence trap pattern named (third instance) and generalized.
- **Sprint 5b** — pre-encounter tactical reminders module + Magisters' Terrace content; JournalData authoring rules established (source-required, brevity, per-dungeon approval); schema v7.
- **Sprint 5b polish** — dual-surface display via `RaidWarningFrame` alongside chat; on-screen header tightened to `Role — Encounter:`; chat retains full `Dungeon (bucket)` header as review log; local-widget-only (never broadcasts).
- **Sprint 5b content** — tactical reminders authored and locked for all eight Midnight Season 1 dungeons; `JOURNAL_DATA_VERSION = 8`.
- **Sprint 5c** — per-key pre-dungeon warnings (`PreDungeon.lua`/`PreDungeonData.lua`): role-filtered interrupts/dispels/tips at `CHALLENGE_MODE_START`, dual-surface, empty-category-as-first-class; `/tox warnings`; schema v8; infrastructure only (`PREDUNGEON_DATA_VERSION = 0`, content authoring pending).
- **Sprint 5d** — category master toggles (`Category.lua`): ToxFilter / Uplifter families, `/tox category`, three-layer master→category→feature gate, sub-state preservation, Stats counting ungated while surfacing gated, `/tox off` promoted to addon-wide master; schema v9.
- **Sprint 6** — PII scrub audit (`PII_Audit_Sprint6.md`, audit-only commit) + remediation: PIIScrub broadened to known-name matching (sender threading, current character, alt roster; precision over recall; B1 collision rule); orphan `feedback_log` removed; schema v10; 18-fixture scrub corpus.
- **Sprint 6b** — options panel (`Options.lua` + embedded AceGUI/AceConfig): GUI as a view over db state (no parallel store), function-built options table, category greying with preserved sub-state values, `/tox config` + `/tox state`.
- **Sprint 7a** — feature build (`CombatDrop.lua`, `Fuzzy.lua`; extends `Callout.lua`/`PositiveCapture.lua`/`Commands.lua`/`Options.lua`/`ToxFilter.lua`): silent-drop carve-out for pure hostility (slur/harm only, purity guard, `/tox combat`, default on; **inert post-N12** — paused-branch-only and never invoked in combat, see Current state), selectable callout sound (`SOUND_CHOICES` table, `/tox callout sound set/list/preview`), Damerau-1 typo tolerance scoped to positive/callout keyword sets (length-5 floor, role targets exact-only), and TEXT_EMOTE positive capture (enUS-only, `(emote)` marker). Schema v11 (two fields).
- **Sprint 8** — launch-prep: rename working name → **Mind Soothe** across the five identity surfaces (folder/Title/slash `/mind`/SavedVariables `MindSootheDB`/addon-name string + `[Mind Soothe]` prefix); centralize the identity into `addon/Const.lua` (single source; frame name now per-build — 5th collision surface); single-source the version via `C_AddOns.GetAddOnMetadata` (TOC `## Version:` only); dual-build `deploy.sh [ship|dev]` (local-only stamped "Mind Dev"/`/mdev` twin, zero collision); packaging (`LICENSE` GPLv3, `.pkgmeta`, `CHANGELOG.md`, `run-gauntlet.sh`); whisper-note doc honesty (no code fix). No schema/feature/classifier change. **Current sprint.**
