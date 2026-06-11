# ToxFilter

Working name. Will be renamed before public distribution — keep references to the name flexible (TOC, slash command prefix, README all carry the working name today).

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
`addon/Commands.lua addon/PositiveCapture.lua addon/Stats.lua addon/Grounding.lua addon/ToxFilter.lua addon/Database.lua addon/Buffer.lua addon/PIIScrub.lua addon/Highlight.lua addon/Breathing.lua addon/Ready.lua addon/Debug.lua addon/Callout.lua addon/JournalData.lua addon/TacticReminders.lua addon/PreDungeonData.lua addon/PreDungeon.lua addon/Category.lua addon/Options.lua`

## Repo layout

```
addon/                  WoW addon source — what gets deployed
  ToxFilter.toc         TOC manifest, Interface 120005 (Midnight retail)
  ToxFilter.lua         Main addon code
  Libs/                 Embedded Ace3
  README.md             Pre-release user-facing description
app/                    Companion app (empty; Build 2)
corpus/                 Test corpora (sprint2.json, sprint5.json, sprint5b_gating.lua)
docs/                   Design docs (empty)
sensitive/              Slur lists / harassment patterns — gitignored
scripts/
  deploy.sh             rsync addon/ -> Windows AddOns folder
  run-corpus.sh         host-side corpus + gating test harness
.luacheckrc             Lua static analysis config
CLAUDE.md               This file — current state + active principles
CLAUDE_ARCHIVE.md       Per-sprint detailed write-ups (historical reference)
Verification_Protocol.md  In-game verification steps per sprint
```

## Dev loop

WSL Ubuntu 24.04 → Windows WoW client.

1. Edit Lua/TOC in WSL.
2. `luacheck addon/` from project root — must pass.
3. `./scripts/run-corpus.sh` — Sprint 2, Sprint 5, Sprint 5b passes all 100%.
4. Tonal-grep pass on changed files (see Tone section).
5. Pipe-doubling audit on any new user-facing string (see Conventions).
6. `./scripts/deploy.sh` — rsyncs `addon/` to AddOns folder.
7. In-game `/reload` (manual — addon never triggers /reload itself).
8. Verify per `Verification_Protocol.md` section for the current sprint.

## Current state — Build 1 Sprint 5d

Version `0.4.0-sprint5d`. Schema v9. Two layered features have shipped since 5b polish:

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
- **Time-critical UI vs passive UI (Sprint 5):** passive UI for emotional support pauses during the Midnight combat window (Sprint 4b Highlight). Time-critical UI stays active during combat (Sprint 5 Callout). Sprint 5b's TacticReminders fires pre-pull from `OnEncounterStart`, so the pause question is moot for it.

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
- **Color register table:** `|cFF66AA66` desaturated green = positive moments (passive, pauses). `|cFFEEBB55` warm amber = role callouts (time-critical, active during combat). Future sprints adding tints check this list before picking.

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
3. Callout.detect + matchesUser (read-only; runs during pause too — time-critical)
4. If paused:
     - channel-on AND callout matches: tint + sound, return tinted
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

Blizzard's Midnight expansion restricts addon code execution during boss encounters and Mythic+ pulls. While paused, chatFilter passes everything through with two read-only exceptions: callout detection + tint + sound, and tactical-reminder surface (which actually fires BEFORE setPaused in the encounter-start handler).

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
- **Build 1 Sprint 6:** PII scrub audit (Sprint 4a's conservative scrubber is intentionally minimal; Sprint 6 expands).
- **Build 1 Sprint 7:** corpus expansion + threshold-gate enforcement. Locked targets: slur ≥98%, role_attack ≥90%, harm_invocation ≥95%, identity_attack ≥90%, harassment ≥70%, general_hostility ≥60%, rewrite correctness ≥90%. Tuning pass: under-absorbed neutrals at attack-span edges; spec-name attack detection; absorption-list expansion.
- **Build 1 Sprint 8:** CurseForge distribution pipeline. `METADATA.JOURNAL_DATA_VERSION` enables content-only updates.
- **Build 1 Sprint 9:** configuration UI.
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
- **Sprint 5d** — category master toggles (`Category.lua`): ToxFilter / Uplifter families, `/tox category`, three-layer master→category→feature gate, sub-state preservation, Stats counting ungated while surfacing gated, `/tox off` promoted to addon-wide master; schema v9. **Current sprint.**
