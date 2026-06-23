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

## Current state — v1.0.0 (released)

**Released.** Mind Soothe shipped publicly as **v1.0.0** — live on CurseForge (project id `1562759`) with a public GitHub repo. Release is tag-driven: pushing a git tag runs `.github/workflows/release.yml` (BigWigs `packager@v2`), which packages `addon/` per `.pkgmeta`, stamps the version from the tag, and publishes to CurseForge, Wago, and GitHub Releases. **Version note:** the committed TOC `## Version:` reads `1.0.0`, matching the git tag. The git tag is the source of the released version — the packager stamps it into the TOC at build time — so a tag push must be paired with the matching `## Version:` bump (as here) to keep the dev tree and the released build in sync.

The launch content below (rename, dual-build, packaging) shipped in the final pre-launch sprint, **Sprint 8**; no feature/classifier/rule change has landed since the Sprint 7b bugfix batch. Schema **frozen at v11** (no change; the SavedVariables rename is handled by accepting a data reset, NOT migration). Shipped through launch:

- **Rename to "Mind Soothe"** (working name "ToxFilter" retired). Five identity surfaces: folder `MindSoothe/`, TOC Title `Mind Soothe`, slash `/mind`, SavedVariables `MindSootheDB`, and the addon-name string (`NewAddon`, AceConfig APP token, GUI/Blizzard-menu title, `[Mind Soothe]` chat prefix). The two internal feature *categories* "ToxFilter"/"Uplifter" stay. Sprint 0 fixtures (`ToxFilterTest:*`, `[ToxEdit]`, `[ToxDel]`) and the internal `ns.ToxFilter*` handles (`Addon`/`State`/`Dispatch`) and the file-local `ToxFilter` AceAddon object are deliberately left unrenamed (internal, not product identity).
- **`addon/Const.lua` — single source** (loaded FIRST in the TOC). Holds `ADDON_NAME`, `DISPLAY_NAME`, `SAVEDVAR`, `SLASH_DISPLAY` (`/mind`; bare `SLASH` derived from it so the dev stamp catches it), `PREFIX`, `DEBUG_PREFIX`, `FRAME_PREFIX`. Every former literal routes here: all `print`/`out` prefixes, the SavedVariables global (now `_G[ns.Const.SAVEDVAR]` dynamic indexing in `Database.lua`/`PIIScrub.lua` — so `.luacheckrc` no longer declares it), `RegisterChatCommand`, the AceConfig APP token, the Blizzard breathing-frame global name (`FRAME_PREFIX .. "BreathingFrame"` — a 5th collision surface, now per-build). **Not centralizable:** the TOC `## Title:`/`## SavedVariables:`/`## Version:` lines (a `.toc` can't read Lua — kept in sync by the same dev-stamp tokens) and the `/mind` mentions in help copy (display text rewritten to literals; the runtime token still derives from `SLASH`).
- **Version single-sourced** from the TOC `## Version:` via `C_AddOns.GetAddOnMetadata(ns.Const.ADDON_NAME, "Version")`. The hardcoded Lua `VERSION` literal is gone. (`C_AddOns` added to `.luacheckrc`; the corpus pause harness stubs it.)
- **Dual-build** (`scripts/deploy.sh [ship|dev]`): ship rsyncs `addon/` verbatim to `AddOns/MindSoothe/` (committed tree IS ship identity — directly packageable). `dev` stages a throwaway copy under `.build/` (gitignored), applies THREE substitutions (`MindSoothe→MindDev`, `Mind Soothe→Mind Dev`, `/mind→/mdev`), then renames BOTH `MindSoothe.toc→MindDev.toc` (folder-match requirement) AND `MindSoothe.lua→MindDev.lua` (the stamp rewrote the TOC's `MindSoothe.lua` source-file reference to `MindDev.lua`, so the file on disk must match or WoW silently skips the main module and the addon never registers its slash — the post-deploy dev-build bug, fixed), and rsyncs to `AddOns/MindDev/`. All four-plus collision surfaces differ (folder, Title, slash `SLASH_MIND1`/`SLASH_MDEV1`, SavedVariables, AceAddon/AceConfig registration, frame name) → coexist with zero collision. Dev build is LOCAL-ONLY: never committed, never packaged.
- **Packaging:** GPLv3 `LICENSE` (verbatim FSF text; Ace3 under `Libs/` is third-party, not relicensed — noted in README), `.pkgmeta` (excludes `scripts/`, `corpus/`, `docs`, `app`, `CLAUDE.md`/`CLAUDE_ARCHIVE.md`, `Verification_Protocol.md`, `PII_Audit_Sprint6.md`, `.build`, `.release`, `packager`, `.github`, `sensitive`, `*.bak.*`; `package-as: MindSoothe` with `move-folders: MindSoothe/addon: MindSoothe` lifting the nested `addon/` to the package root), `CHANGELOG.md` (0.6.0→0.8.0; release notes source via `manual-changelog`), `scripts/run-gauntlet.sh` (luacheck + corpus + tonal grep + pipe audit, exits nonzero on any failure; tonal+pipe scoped to `print(`/`out(` lines over `addon/*.lua` minus `Libs/`). `.gitignore` gains `.build/`, `*.bak.*`, `packager/`, `.release/`.
- **Automated release pipeline** (`.github/workflows/release.yml`): on any tag push, GitHub Actions runs the BigWigs packager (`BigWigsMods/packager@v2`) with `CF_API_KEY`/`GITHUB_TOKEN` from repo Secrets, builds per `.pkgmeta`, and uploads to CurseForge + Wago + GitHub Releases. The vendored `packager/` clone and `.release/` output are gitignored (local-only). This is how v1.0.0 reached CurseForge.
- **F1/F2 whisper-note honesty (doc/string only, no code fix):** README no longer claims the one-shot whisper privacy note prints (reworded to a known-limitation note); the `Commands.lua` whisper-note comment is the deferred code fix's territory and untouched beyond the rename. The code path is unchanged this sprint.
- **TOC Interface** stays `120005`; developer reconfirms against the live patch at upload.
- Gauntlet green at handoff: luacheck 0/0 (31 files), full corpus 100% (incl. scrub corpus under the renamed SV global and the N12 pause-dispatch under `MindSoothe.lua` + `C_AddOns` stub), tonal grep + pipe audit clean.
- **In-game verification PASSED (Sprint 8 scope):** both builds install as separate AddOns-list entries with isolated data; ship "Mind Soothe" responds to `/mind` (and not `/mdev`), dev "Mind Dev" responds to `/mdev` (and not `/mind`). The post-deploy dev-build bug above (TOC `MindDev.lua` reference vs on-disk `MindSoothe.lua`) was caught in this verification and fixed before it passed. (Broader per-feature in-game verification — the pending 5b/7a items elsewhere in this doc — is unchanged by Sprint 8.)
- **Post-launch status of the prior "flagged for the developer" list:** the GitHub visibility flip and the CurseForge upload are **done** (repo is public; v1.0.0 is live). The README has been brought current to the shipped feature set (this post-launch doc pass). **Still open:** the stale `Verification_Protocol.md`; the two leftover `claude/*` branches; broader per-feature in-game verification (the pending 5b/7a items elsewhere in this doc). The CHANGELOG `[Sprint 7b]` entry is undated and describes 7b's *defined scope* (classifier tuning / regression pass) rather than what commit `110f0d4` actually shipped (a bugfix batch: name-escape capture, record narrowing, combat/callout polish) — reconcile if the CHANGELOG matters for a future release.

### Prior — Build 1 Sprint 7a (feature build)

Version `0.7.0-sprint7a-fix`; schema v11 (the sole Sprint 7 bump — `migrations[11]` backfills `callout_sound_id` and `combat_silent_drop`, nothing else). Full writeup in `CLAUDE_ARCHIVE.md`; the sprint index below has the one-liner. Still-live facts:

- **CombatDrop silent-drop carve-out is INERT** (`addon/CombatDrop.lua`). Intended to silent-drop pure hostility (winning category ∈ `{slur, harm_invocation}`, `handling ~= "pass"`, purity = no token carries the `"tactical"` label) during the combat pause, but `CombatDrop.shouldDrop` is called **only** from `chatFilter`'s paused branch, which N12 proved is never invoked in combat — and it is **not wired into the non-paused path**. So it has no runtime effect in any state. Toggle kept (`/mind combat`, default on, v11) for a possible future out-of-combat home; the gate logic is corpus-tested and correct. Out of combat, pure slur/harm goes through normal category handling (slur→edit, harm_invocation→del per `Categories.HANDLING`), not a silent drop. `ToxFilterTest:Silent` is dropped by the **non-paused Sprint 0 fixture** (step 9), not this carve-out. User-facing strings (`/mind status`/`state`/`combat`, GUI, README) describe the toggle as currently having no effect.
- **Selectable callout sound** (`addon/Callout.lua`, `Callout.SOUND_CHOICES`): fresh-install default `8959` ("readycheck2", "Ready check, low"); `migrations[11]` seeds `8960` so v10→v11 upgraders keep their cue. `/mind callout sound set|list|preview`; GUI dropdown previews on select.
- **Typo tolerance** (`addon/Fuzzy.lua`): Damerau distance-1 for the positive-capture and callout keyword sets ONLY — never the classifier/rule engine/blacklist/whitelist (load-bearing scope line). Length floor 5 (short keywords exact-only); **role targets always exact-only** (a typo firing the wrong-role callout is the expensive failure). Exact lookup stays the hot path; fuzzy only on miss.
- **Emote capture** (`addon/PositiveCapture.lua`): an emote verb (`thank`/`cheer`/`salute` + plurals) plus a self-target token ("you"/"your") — i.e. aimed at the player ("Bob thanks you.") — is captured as a positive moment with a `(emote)` marker. Untargeted/third-party emotes are NOT captured (N22 removed an earlier untargeted rule); own outgoing emotes are skipped. PII-scrubbed; self-gates on `Category.gate("uplifter")`. **enUS-only by construction.**
- **N12 — in-combat chat handling is impossible; callouts are out-of-combat-only.** Midnight does not invoke chat filters in combat AND delivers in-combat chat text to any handler as a **secret/tainted value that cannot be read or compared**. The `OnCombatChat` experiment, its role cache, taint firewall, and combat-callout helpers (`Callout.SurfaceCombatCallout`/`matchesUserRole`) were all **deleted**; callouts run only out of combat via the chat-filter tint path. The `chatFilter` paused branch is dead in real combat (filter not invoked) — retained for the pause-dispatch guard. Full three-layer investigation in the archive; essence also in the Midnight pause section below. **Survivor fix:** `CHAT_MSG_BATTLEGROUND`/`_LEADER` were removed from the WoW API (BG chat now arrives as `CHAT_MSG_INSTANCE_CHAT`) and dropped from `CHAT_EVENTS`; `RegisterChatCommand` is the FIRST line of `OnEnable` so a later event throw can't skip slash registration.
- Corpus: `sprint7a_combat.lua` (18), `sprint7a_fuzzy.lua` (14, incl. the N16 `rank`/`task`/`tans`-vs-`tank` regression), `sprint7a_emote.lua` (9), `sprint7a_pause.lua` (8 — the N12 pause-dispatch guard, a separate Lua process driving the real `chatFilter` through `isPaused` via `scripts/pause-dispatch.lua`).

### Prior — Build 1 Sprints 5b–6b

Full writeups in `CLAUDE_ARCHIVE.md`; the sprint index below has one-liners. Schema reached v10 at 6b. Still-live facts not already captured under Load-bearing decisions:

- **Sprint 6 PII scrub** (`addon/PIIScrub.lua`): live-path name scrubber matches KNOWN names only — message sender (threaded `chatFilter → capture → RecordPositiveMoment → scrub`), the user's current character, and the alt roster from AceDB profileKeys. Case-insensitive, connected-realm-suffix-aware (strips `Name-Realm` whole), position-independent. Precision over recall; a known name that is also a class/role word or acronym is spared (B1 collision rule). 18-fixture corpus in `corpus/sprint6_scrub.lua`; audit in `PII_Audit_Sprint6.md`.
- **Sprint 6b options panel** (`addon/Options.lua` + embedded AceGUI/AceConfig): AceConfig panel registered into the Blizzard AddOns menu from `OnInitialize`, a view over db state (never a parallel store) — every control reads/writes the same db fields (or `ns.*` methods) the slash commands use. Options table registered as a function so dynamic list editors and category `disabled()` closures re-evaluate each render. `/mind config` opens it; `/mind state` is a one-block readout of every toggle layer. (Accepted limitation: slash changes while the panel is open may display stale until reopen.)
- **Sprint 5b/5c reminders & warnings**: `TacticReminders` (`addon/TacticReminders.lua` + `JournalData.lua`) surfaces pre-pull from `ENCOUNTER_START`, dual-surface chat + `RaidWarningFrame` (`RaidNotice_AddMessage`, a local widget — never broadcasts), `/mind reminders`. `PreDungeon` (`addon/PreDungeon.lua` + `PreDungeonData.lua`) surfaces per-key at `CHALLENGE_MODE_START`, role-filtered interrupts/dispels/tips, empty-category-as-first-class, `/mind warnings`. Both fire BEFORE `setPaused(true)`. PreDungeon content is infrastructure-only (`PREDUNGEON_DATA_VERSION = 0`, authoring pending).

**JournalData (`addon/JournalData.lua`) — all eight Midnight Season 1 dungeons locked, `JOURNAL_DATA_VERSION = 8`** (in-game verification still pending). Authoring rules (load-bearing for future content updates; full text in `CLAUDE_ARCHIVE.md` and user memory): source-required (never from training data — wrong mechanics betray the users this exists to support); 6 words ±2, imperative verb, mechanic proper-nouns preserved; reminders not tutorials; role-split when mechanics differ across roles (the addon renders only on the user's screen); per-dungeon approval before writing — one at a time, never bulk-propose.

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
- **Sprint 7b** — bugfix batch (commit `110f0d4`): name-escape capture, record narrowing, combat/callout polish. No schema change. (CHANGELOG `[Sprint 7b]` entry is undated and describes the planned tuning scope, not this batch — see the post-launch note in Current state.)
- **Sprint 8** — launch-prep: rename working name → **Mind Soothe** across the five identity surfaces (folder/Title/slash `/mind`/SavedVariables `MindSootheDB`/addon-name string + `[Mind Soothe]` prefix); centralize the identity into `addon/Const.lua` (single source; frame name now per-build — 5th collision surface); single-source the version via `C_AddOns.GetAddOnMetadata` (TOC `## Version:` only); dual-build `deploy.sh [ship|dev]` (local-only stamped "Mind Dev"/`/mdev` twin, zero collision); packaging (`LICENSE` GPLv3, `.pkgmeta`, `CHANGELOG.md`, `run-gauntlet.sh`); whisper-note doc honesty (no code fix). No schema/feature/classifier change.
- **Launch — v1.0.0** — automated tag-driven release pipeline (`.github/workflows/release.yml`, BigWigs `packager@v2`); first public release published to CurseForge (project `1562759`) + Wago + GitHub Releases; GitHub repo made public. TOC `## Version:` bumped to `1.0.0` to match the git tag (the packager stamps the tag at build time). No schema/feature/classifier change.
