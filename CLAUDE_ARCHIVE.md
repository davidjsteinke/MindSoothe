# ToxFilter — Sprint Archive

Historical write-ups for shipped sprints. `CLAUDE.md` keeps the current-state and active-principles index; load-bearing decisions are summarized there. This file holds the full reasoning, in-the-moment context, and detail for each shipped sprint. Read this when implementing a fix that touches a documented decision, or when investigating why something is the way it is.

Sections are preserved verbatim from the original CLAUDE.md at the time of archival (Sprint 5b). Some statements (e.g. "Status: complete") are snapshots from when they were written; the index in CLAUDE.md is the live source of truth for what has shipped.

---

## Sprint 2 closing state (historical snapshot — was "Current state — Build 0 Sprint 2")

Rule engine in place. Real chat is tokenized → normalized → hashed → looked up in a static rule table; matching tokens dispatch through the same four handling modes Sprint 0 built. Sprint 0 fixtures still work as fallback (rule engine runs first; fixtures only fire when no rule matches).

**Sprint 0 fixtures (still working, kept as architectural-validation tests):**

| Trigger substring         | Mode               | Display |
|---------------------------|--------------------|---------|
| `ToxFilterTest:Pass`      | Pass-through       | unchanged |
| `ToxFilterTest:Edit`      | Surgical rewrite   | `[ToxEdit] <body with trigger removed>` |
| `ToxFilterTest:Del`       | Visible deletion   | `[ToxDel: TestCategory]` |
| `ToxFilterTest:Silent`    | Silent drop        | (nothing rendered) |

Edit-mode format is **prefix-plus-removal**: the tag is prefixed at the start of the line, and the offending substring is genuinely removed from the body (whitespace collapsed). Example: `"hey ToxFilterTest:Edit ok"` → `"[ToxEdit] hey ok"`. The rule engine uses the same shape — every rule-hit raw token is removed and the line is prefixed with `[ToxEdit] `.

**Hooked channels:** PARTY, PARTY_LEADER, RAID, RAID_LEADER, RAID_WARNING, INSTANCE_CHAT, INSTANCE_CHAT_LEADER, BATTLEGROUND, BATTLEGROUND_LEADER. WHISPER intentionally excluded — whisper is user-toggle/default-off, deferred to Sprint 3.

**Slash commands:** `/tox status`, `/tox version`, `/tox rules`, `/tox test <message>`. Anything else prints usage.

---

## Sprint 1: rule engine

**Hash function.** FNV-1a 32-bit, implemented in pure Lua (`addon/Hash.lua`) and Python (inline in `scripts/build-rules.sh`). Both produce identical output; `Hash.lua` runs three known-vector self-test asserts at addon load (`""`, `"a"`, `"test"`) so divergence fails loudly. Lua side uses `bit.bxor` for the XOR step plus a split-multiply trick for the `* 16777619 mod 2^32` step (Lua 5.1 doubles only carry 53 bits of precision, so a direct multiply would silently lose bits).

**Normalization pipeline (`addon/Normalize.lua`, mirrored in Python).** Order matters; each step's output feeds the next:

1. Lowercase.
2. Strip punctuation (`.,!?;:'"()[]{}<>/\|`).
3. Collapse 3+ identical consecutive characters to 1; 2 stay (`book` → `book`, `boook` → `bok`, `baaaaad` → `bad`).
4. Leetspeak: `0→o, 1→i, 3→e, 4→a, 5→s, 7→t, 8→b, @→a, $→s`. **Decision: `1→i`** (more common in obfuscation than `1→l`).
5. Strip remaining whitespace within tokens.

Bumping any step bumps `NORMALIZATION_VERSION`; the addon refuses rule data whose version doesn't match.

**Categories (`addon/Categories.lua`).** Six categories with default handling:

| Category            | Handling | `[ToxDel: ...]` label |
|---------------------|----------|-----------------------|
| `slur`              | edit     | Slur                  |
| `identity_attack`   | edit     | Identity Attack       |
| `role_attack`       | edit     | Role Attack           |
| `harassment`        | edit     | Harassment            |
| `harm_invocation`   | del      | Harm Invocation       |
| `general_hostility` | del      | General Hostility     |

Multi-hit messages: aggressiveness wins (silent > del > edit > pass); ties are broken by severity for the category-label choice.

**Phrase matching.** Schema lives in `RuleData.lua` under `phrases = {}`; matching loop is in `RuleEngine.lua`. Sprint 1 ships zero phrase entries — the structure is exercised but nothing matches. **Phrase tokens are normalized at build time before hashing**, identical to runtime: a source phrase like `"k1ll y0urself"` becomes `"kill yourself"` before hashing, so phrase matching works against obfuscated speech without requiring multiple phrase entries per concept. Default `max_distance = 3`.

**Wordlist sources (`sensitive/<category>.txt`, gitignored).** One file per category, one entry per line. Optional `:N` severity suffix (1–10, default 5). Comments (`#`) and blank lines OK. Sprint 1 ships placeholders only — `testword_*`, `placeholder_*`, `fakehate_*`, `fakeword_*`. Real wordlists are populated off-platform.

**Build command.** `./scripts/build-rules.sh` produces `addon/RuleData.lua`. The output is sorted by hash for stable diffs and uses the newest source-file mtime as `generated_at`, so reruns with no input change produce no diff. Missing input files are silently skipped with a note. Hash collisions between two distinct normalized inputs are fatal — fix the inputs.

**`addon/RuleData.lua` is tracked.** Reasoning: `sensitive/` is gitignored, so a fresh clone has no way to regenerate it; tracking the artifact means the addon works after `deploy.sh` even without sensitive data present. Revisit if merge-conflict pain shows up.

**Known gaps (Sprint 1).**
- Multi-word phrases: schema only, no entries.
- Real wordlists: not yet populated.
- Test corpus harness: deferred to Sprint 2.
- Constructive-vs-hostile classifier: Sprint 2.
- Encoded-rule-data versioning is basic (two version strings); harden in Sprint 7.

---

## Sprint 2: classifier + surgical rewrite + corpus harness

**Status: complete.**

Three modules sit on top of Sprint 1's rule engine:

- `addon/Patterns.lua` — pure data: role nouns, negative modifiers, intensifiers, you-pronouns, neutral fillers, tactical markers, intelligence-mocking nouns, antonymic-praise / passive-thanks / conditional-blame phrase triggers.
- `addon/Classifier.lua` — labels each token `attack` / `tactical` / `neutral` and records signals.
- `addon/Rewrite.lua` — drops attack-labeled tokens, preserves tactical and (when tactical exists) neutral tokens, prefixes `[ToxEdit]`.

`RuleEngine.classify` runs the classifier on every message — even with zero rule hits — and now returns `{handling, category, severity, hits, all_hits, raw_tokens, normalized_tokens, labels, signals, whole_message_preserved}`. `buildEditMessage` is now a one-line wrapper around `Rewrite.rewrite`.

### Classifier patterns

The classifier walks five passes:

1. **Tactical markers.** Mechanic/direction/imperative/numeric tokens labeled `tactical`. Tactical wins on overlap with role nouns (documented spec-name false-negative — see "fire mage" caveat below).
2. **Rule hits.** Every rule-data hit labeled `attack` (unless already tactical).
3. **Role-attack pattern.** For each role-noun token, search ±3 window for a trigger (rule hit or `NEG_MODIFIER`). **Critical refinement:** the trigger is invalid if any tactical token sits between it and the role noun — negative modifiers in tactical context are intensification, not attack. So `fucking trash tank` fires role_attack; `fucking move out of fire` stays pass-through. When valid, mark the span attack and absorb adjacent you-pronouns, neutral fillers, intensifiers, and other neg-modifiers/mocking-nouns outward (still blocked by tactical).
4. **You-pronoun pattern.** Same shape as role-attack but the anchor is a `YOU_PRONOUN` and triggers include `INTELLIGENCE_MOCKING`. Suggested category: `harassment`. Same tactical-blocking rule.
5. **Sarcasm signals (no relabeling).** Flags `sarcasm_antonymic_praise` (great/nice/good + job/play/work/... + intelligence-mocking noun), `sarcasm_passive_thanks` (`thanks for the wipe`-style), `sarcasm_slash_s` (literal `/s`), `sarcasm_maybe_try` (`maybe try`/`have you tried`/`ever heard of`).

Sarcasm-only handling (no other attack labels): `whole_message_preserved=true`, `category=harassment`, `handling=edit`. Rewrite emits `[ToxEdit] <body>` verbatim, since the rhetorical attack is the whole utterance.

### Surgical rewrite algorithm

```
if whole_message_preserved:  emit "[ToxEdit] " + msg verbatim
else:                        emit "[ToxEdit] " + every token whose label != "attack"
                             (i.e. tactical AND neutral both preserve)
empty body:                  emit "[ToxEdit]" (bare)
```

**Disposition rule (load-bearing — don't regress).** Tokens fall into more dispositions than just attack/tactical/drop:

- **Attack** → drop. Confidently identified attack content.
- **Tactical** → preserve. Mechanic/direction/imperative/numeric content.
- **Neutral inside an attack span** → already relabeled `attack` by the classifier's outward absorption walk in Passes 3/4. Drops for free.
- **Neutral outside both spans** → preserve. This is real chat signal — affirmatives (`okay`, `whatever`, `gg`, `ty`, `np`, `lol`, `kk`, `sure`, `fine`), banter, the user's own commentary on a filtered message — and stripping it loses information the user wants to see.

Conservatism direction: drop only what we're confident is attack content; preserve everything else. The earlier Sprint 2 rule ("if no tactical token exists in the message, drop neutrals too") got this backwards — it was fixed mid-Sprint when in-game testing surfaced `placeholder_slur_c whatever` rendering as bare `[ToxEdit]` instead of `[ToxEdit] whatever`. Future passes that touch Rewrite must keep the disposition asymmetric: drop is the exceptional path, preserve is the default.

Practical consequence: if the classifier under-absorbs a token that *should* have been part of an attack span (e.g. `worst healer ever` — `ever` survives because it's not in the absorption-list), the right fix is to extend the absorption list in Patterns/Classifier, not to make Rewrite drop neutrals more aggressively. That's Sprint 7 tuning.

### Attack-span vs winning-category decoupling (load-bearing)

When a rule hit (e.g. slur) sits inside a classifier-detected role-attack scaffold, the rule winner determines `result.category` (severity-based tiebreak), but the classifier's `labels` are the source of truth for Rewrite. So `you're a placeholder_slur_c tank` resolves to `category=slur, handling=edit`, with the entire `you're a placeholder_slur_c tank` span labeled attack — Rewrite strips the whole scaffold to `[ToxEdit]`. Future sprints must not couple attack-span identification to winning-category; they're orthogonal.

### Test corpus and harness

- Corpus: `corpus/sprint2.json`. 64 entries across 15 buckets covering role-attacks (whole-message and tactical-preserving), sarcasm (clear and earnest-praise lookalikes), slurs (whole-message and tactical-preserving), harassment, harm-invocation, multi-hit, pass-through banter/role-noun-no-modifier, intensifier-in-tactical-context, neutral-outside-attack regression (the `ns_*` block, locking in the disposition-rule fix), and Sprint 0 fixture regression. All attack content uses placeholder slugs from `sensitive/*.txt`. Real wordlists are populated off-platform — the same content policy as Sprint 1.
- Harness: `./scripts/run-corpus.sh`. Pure-Lua: loads the addon's actual modules (Hash, Normalize, Categories, Patterns, RuleData, Classifier, Rewrite, RuleEngine) under a minimal WoW-API stub (just `bit.bxor`). Python is used only to convert the JSON corpus to a Lua table — no rule-engine logic in Python, so no parity drift.
- Output: per-category catch / category-correct rates, pass-through false-positive rate, rewrite exact-match rate. Sprint 2 ships at 100% across the board against the seeded corpus.
- **No threshold gate in Sprint 2** — measurement only. Build 1 Sprint 7 introduces enforcement (locked targets: slur ≥98%, role_attack ≥90%, harm_invocation ≥95%, identity_attack ≥90%, harassment ≥70%, general_hostility ≥60%, rewrite correctness ≥90%).

### Known false-positive / false-negative risks

- **Sarcasm vs earnest praise:** `great job, einstein` flags; `great job!` doesn't. The discriminator is the intelligence-mocking noun. Earnest "great job, hero!" would also flag (because `hero` is in `INTELLIGENCE_MOCKING`); acceptable per the design (false-positive cost = `[ToxEdit]` tag on a kind message — annoying, not destructive).
- **`thanks for the carry`** is tagged `known_fuzzy` in the corpus — passive-aggressive thanks pattern fires on it, but it can be genuinely thankful. Default behavior: flag as harassment with body preserved.
- **Spec-name attacks:** mechanic words (fire, frost, shadow, holy, arcane) are tactical-only by default, so `you fire mage suck` won't fire role-attack on the `fire mage` substring. Acceptable Sprint 2 false-negative; revisit if corpus shows it matters.
- **Standalone neg-modifiers without role/you context** (`moron` alone) pass through — by design, per the tactical-context refinement. Same applies to mocking words mixed with a slur but no role/you anchor (`placeholder_slur_c moron` → `[ToxEdit] moron`); the slur drops, the standalone modifier survives until Sprint 7 expands absorption.
- **Under-absorbed neutrals at attack-span edges** (`worst healer ever` → `ever` survives; hypothetically `you're hopeless` → `hopeless` survives if not in NEG_MODIFIERS). The disposition rule is correct (preserve neutrals outside spans); the gap is in the absorption-list / NEG_MODIFIERS coverage. Sprint 7 tuning, not a Rewrite-side fix.
- **`tank`/`heal` as imperative verbs** ("tank the boss") aren't recognized as tactical; "tank" stays role-noun. Acceptable false-negative.

### Slash command additions

- `/tox classify <msg>` prints attack/tactical span breakdown and classifier signals.
- `/tox rewrite <msg>` runs the full pipeline and prints the rendered output.

The original four (`status`, `version`, `rules`, `test`) keep working unchanged.

### Sprint 7 reminder

Corpus growth and measurement only matter at the gate. When wordlists are real, expand `corpus/sprint2.json` (or a successor) and wire the harness's stats into a CI failure threshold per the locked targets above.

---

## Build 1 Sprint 3: persistence + full slash suite + whisper hook

**Status: complete (initial Sprint 3 + fix1 patch).**

**fix1 patch (version `0.0.4-sprint3-fix1`)** — in-game testing surfaced three issues fixed without a re-sprint:
1. `/tox role auto` crashed because `GetSpecializationRole` requires a `specGroupIndex` from `GetSpecialization()`. `Database:GetEffectiveRole` now calls them in the correct order and tolerates `GetSpecialization()` returning nil for low-level chars / pre-spec-data login window.
2. Help text rendered `<add|remove|list>` as `<addemove>` because WoW's chat parser consumes `|r` as a color-reset escape. All literal pipes in `print`-bound strings are now doubled (`||`); this is a permanent code-discipline rule (see Conventions).
3. `/tox channel list` got a master-state header (`Channels (master: enabled):` / `... DISABLED:`) so it doesn't visually mislead when filtering is master-off but channels still show `on`.

fix1 also added `default` as a fifth `<handling>` value (clears overrides) and an `/tox handle all <handling>` batch shorthand. Both documented in the Handle subsection below.

Sprint 3 introduces the user-configuration layer. Storage backend is **AceDB-3.0** (now embedded under `addon/Libs/AceDB-3.0/`); account-wide scope only; profiles are not surfaced in the slash UI but the door is open for a future sprint. An explicit `migrations[N]` table layers schema-version migrations on top of AceDB's defaults system because explicit-and-readable beats implicit defaults-merging for long-term maintainability.

### AceDB schema (top-level v1)

```lua
ToxFilterDB.global = {
    schema_version      = 1,
    enabled             = true,             -- master toggle
    channels            = { party, raid, instance, battleground, whisper },  -- whisper default false
    handling            = {},               -- category -> "pass"|"edit"|"del"|"silent" override; nil = use default
    role                = "auto",
    role_last_seen      = nil,              -- cache for GetSpecializationRole returning nil at login
    blacklist           = {},               -- [hash] = normalized_plaintext
    whitelist           = {},               -- [hash] = normalized_plaintext
    whisper_intro_shown = false,            -- one-shot privacy note bit
    -- reserved for later sprints (empty); shape stable
    session_buffer = {}, pinned_moments = {}, stats = {}, feedback_log = {},
}
```

### Migration pattern

`migrations[N] = function(db) ... end` upgrades from v(N-1) to vN. `Database:Init()` walks `current+1 .. LATEST_SCHEMA_VERSION`, each call wrapped in `pcall` so a broken migration preserves the user's last good `schema_version` instead of corrupting forward. Sprint 3 ships `migrations[1]` as a no-op (initial schema). Future sprints append new entries; do not retroactively edit committed migrations.

If `_G.ToxFilterDB` loaded as a non-table (corrupted file), Database.lua resets to defaults and prints a single chat line — never silently loses data, never crashes the addon.

### Slash command catalog

15 verbs total, grouped by purpose (run `/tox help` in-game for the live summary):

| Group     | Commands |
|-----------|----------|
| Filtering | `/tox on`, `/tox off`, `/tox status` |
| Channels  | `/tox channel <name> on\|off`, `/tox channel list` |
| Handling  | `/tox handle <category> <pass\|edit\|del\|silent\|default>`, `/tox handle all <handling>`, `/tox handle list` |
| Lists     | `/tox blacklist <add\|remove\|list> [word]`, `/tox whitelist <add\|remove\|list> [word]` |
| Role      | `/tox role <auto\|tank\|healer\|dps>` |
| Inspect   | `/tox version`, `/tox rules`, `/tox list`, `/tox test <msg>`, `/tox classify <msg>`, `/tox rewrite <msg>` |
| Help      | `/tox help`, `/tox help <command>` |

Bare `/tox` prints a compact one-line summary; `/tox help` is the grouped view; `/tox help <command>` gives details for one command.

### Handle command — `default` and `all` (added in fix1)

Two ergonomic additions on top of `pass|edit|del|silent`:

- **`default`** — fifth accepted value for `<handling>`. Clears the override (`db.handling[cat] = nil`), making the resolver fall back to `Categories.HANDLING[cat]`. Architecturally, `default` is a **meta-handling**: it never reaches `RuleEngine.classify`'s resolver because the override is deleted before resolution runs. The resolver contract stays clean — it only ever sees `pass|edit|del|silent`. The split is enforced by `HANDLING_INPUT` (accepted at the slash-command boundary, includes `default`) vs `HANDLING_SET` (in-engine, no `default`).
- **`all` shorthand** — `/tox handle all <handling>` applies a handling to every category in `CATEGORY_ORDER` in one call. Works with all five values, including `default` (resets every category at once). The silent-drop note is emitted **once** after the batch summary, not per-category, to avoid spam. The `all` keyword is parsed as a category-name special-case in `Commands.handle` and bypasses per-category-name validation.

### Channel list master-state header (added in fix1)

`/tox channel list` prints a single header line of the form `Channels (master: enabled):` or `Channels (master: DISABLED):` (uppercase deliberate when off) before the per-channel list. Per-channel toggles are independent of the master toggle, so showing all channels as `on` while filtering is globally off would be visually misleading. The `/tox list` comprehensive view already prints master state on its own line; only the dedicated channel-list view needed the header.

### Whisper hook + default-OFF rationale

`CHAT_MSG_WHISPER` is registered alongside the group/raid/instance/BG events but `db.channels.whisper` defaults to `false`. Whispers are private 1:1 communication; filtering them is a deliberate user opt-in, not a default. The first time the user runs `/tox channel whisper on`, a one-line privacy note prints (gated by `db.whisper_intro_shown`) and is never repeated. **`CHAT_MSG_WHISPER_INFORM` (the user's outgoing whispers) is intentionally NOT hooked** — text the user typed themselves is never filtered.

### chatFilter dispatch order (Sprint 3 final)

1. `isPaused` (Midnight combat window) → pass through
2. `db.enabled == false` → pass through
3. `db.channels[event_channel] == false` → pass through (covers Sprint 0 fixtures too — channel-off is total)
4. `RuleEngine.classify(msg, handlingResolver)` — resolver consults `db.handling` for both multi-hit aggressiveness ranking and final dispatch, so the two stay consistent (a user setting slur=silent sees silent win, not a stale default-edit pick)
   - During lookup: whitelist hash suppresses rule hits; blacklist hash synthesizes a `general_hostility` severity-5 hit when no rule already matched
5. Sprint 0 fixtures (fallback when rule engine returns pass)

The handling resolver is an optional second argument to `classify`. The corpus harness omits it → `Categories.HANDLING` defaults → harness behavior unchanged. `ns.UserRules` is also nil in the harness, so blacklist/whitelist branches are skipped there.

### Soft-disabled state

A user who sets every category to `pass` ends up with filtering effectively off even when `enabled=true`. `/tox status` and `/tox list` detect this state via `Database:AllCategoriesPass()` and report `Active — every category set to pass; filtering is effectively off` (status) or `state: soft-disabled (every category set to pass)` (list). Without this, the user could be confused why filtering appears off when they didn't run `/tox off`.

### Blacklist / whitelist storage

Map shape: `[hash] = normalized_plaintext`. The hash is the runtime-lookup key (matches RuleData's hash-keyed table); the normalized plaintext is stored alongside for `list` display. Adding `Foo` and adding `foo` collapse to the same entry, and `list` shows `foo` — the user removes by what they typed, normalization is invisible. Hashing keeps the hot-path lookup at O(1) regardless of list size and matches Policy #6 hygiene at the lookup-table level.

### Role auto-detect

Sprint 3 stores the role setting only; consumers arrive in Sprint 5. `Database:GetEffectiveRole()` resolves `"auto"` lazily via `GetSpecializationRole()` at read time (`TANK`/`HEALER`/`DAMAGER` mapped to `tank`/`healer`/`dps`). When the API returns nil (e.g. login window before specialization data is available) the resolver falls back to `db.role_last_seen`, which is updated whenever a successful auto-detect happens. The user always sees a deterministic role string in `/tox status` and `/tox list`.

### Module layout (Sprint 3)

```
addon/
  Database.lua    AceDB wiring, defaults, migrations, role resolver, soft-disable detector
  UserRules.lua   blacklist/whitelist add/remove/list/lookup
  Commands.lua    all slash handlers + grouped help dispatch (ToxFilter.lua delegates)
  ToxFilter.lua   lifecycle, chatFilter dispatch, pause state, whisper-hook registration
  RuleEngine.lua  classify(msg, handlingResolver) — accepts override resolver, consults ns.UserRules
```

### Hooks reserved for Sprint 4

`db.session_buffer`, `db.pinned_moments`, `db.stats`, `db.feedback_log` exist as empty tables in the v1 schema. Sprint 4 populates them; no migration needed.

---

## Build 1 Sprint 4a: affirmative data layer + slash surfacing

**Status: complete.** Sprint 4 was split: 4a ships everything observable via `/tox` chat output (data layer, pattern detection, slash commands, asymmetric surfacing). 4b ships the visual UI primitives (chat-line tint, animated breathing frame) and `/tox ready` meta-orchestration. Split rationale: 4a is in a regime we already understand (chat-frame output, slash dispatch); 4b is the project's first animated-frame work and is genuinely different.

### Module layout

```
addon/
  PIIScrub.lua         conservative name-context scrubber for buffer-stored content
  Buffer.lua           session_buffer reads/writes/retention pruning, pinned moments
  PositiveCapture.lua  pattern-based positive-moment detection + subscriber list
  Stats.lua            asymmetric-display logic, week aggregation
  Grounding.lua        slash-driven Y/N ritual state machine
```

### Schema (v2)

`migrations[2]` backfills these top-level fields on existing v1 users; fresh installs land at v2 via DEFAULTS:

- `retention_days` = 30 (windowed-event retention)
- `grounding_items = {}` (empty by default — no suggested items)
- `stats_threshold` = 30 (wipe-rate % above which live surfacing is suppressed)
- `stats_surface` = true (live encounter/dungeon stat surfacing toggle)
- `positive_ui` = false (highlight UI toggle; visual treatment ships in 4b)

`db.session_buffer` substructure is shaped at runtime by `Buffer:Init` rather than declared in DEFAULTS, so AceDB's defaults merge doesn't recreate counters tables on every login. Shape:

```
session_buffer = {
    counters = {
        encounters = { [encounterID] = { [difficultyID] = { name, attempts, completed, wiped, last_attempt } } },
        dungeons   = { [mapID] = { name, runs_started, completed, last_run } },
        sessions   = { current = {...}, history = { ...up to 20... } },
        thanks_total, deaths_total,
    },
    events = {
        positive_moments = { { id, ts, text, signals, direct_to_user }, ... },
        flagged_events   = { { ts, category, severity }, ... },
        activity_log     = { { ts, type }, ... },  -- type: encounter_completed/wiped, death, thanks_received
    },
    next_pm_id = N,
}
```

`db.pinned_moments[id]` is a separate top-level table. Pin cap is 100; oldest unpins on overflow with a notification.

### Counters: permanent. Events: windowed.

Counters never prune. Windowed events (positive_moments, flagged_events, activity_log) prune on addon load via `Buffer:Prune(retention_days)`. Pinned moments never prune. This is the load-bearing storage philosophy — don't regress it.

The activity log is the source of truth for `Stats.WeekSummary`. Counters don't carry per-event timestamps, so for any time-windowed aggregate, walk the activity log instead of summing counters.

### Session lifecycle

`Buffer:Init` resumes the previous `current` session if its `last_activity_at` is within `SESSION_RESUME_WINDOW_S` (1 hour); otherwise archives it to `history` and starts a new one. /reload during normal play does not reset session counters. History capped at 20 sessions (oldest dropped).

### Positive-moment detection

Pattern-based, no LLM. `PositiveCapture.capture(msg, classifier_result, event)` runs on every chat-frame message that the rule engine returns as pass-through; sarcasm-flagged messages (any of `sarcasm_antonymic_praise`, `sarcasm_passive_thanks`, `sarcasm_slash_s`, `sarcasm_maybe_try`) are skipped — sarcasm-flagged thanks is not thanks.

Patterns in 4a: `thanks <role>`, `thanks <user-name>`, positive-verb + positive-play (e.g. `good pull`, `clutch save`), single-token callouts (`gg`, `wp`, `ggwp`, `ez`), and phrase callouts (`well played`, `good game`). `direct_to_user` is true when the role matches the user's effective role or the name matches `UnitName("player")`.

Pause skips capture. Buffer writes are addon code execution; Midnight restricts during encounters. User-invoked surfacing (`/tox lift` etc.) is still allowed during pause — that's a separate path through Commands.lua, not through the chat filter.

`PositiveCapture.subscribe(fn)` is the hook 4b's Highlight will use; 4a maintains the subscriber list but no module subscribes yet.

### PII scrub (conservative, name-context only)

`PIIScrub.scrub(text)` replaces:
- `@<word>` → `@<player>` (any @-prefix identifier)
- `<thanks-token> <Capword>` → `<thanks-token> <player>` (after thanks/thank/thx/ty/tysm)

Allowlists: installing user's own name (preserved so direct-to-user matching works), and a small set of common all-caps tokens (GG, OK, DPS, MVP, ...). Sentence-initial caps are NOT scrubbed unless they ARE in name context — `Move out of fire` stays intact, `thanks Bob` becomes `thanks <player>`.

This is over-scrub-conservative: ambiguous tokens in name context become `<player>`. Known false-negatives are acceptable; Sprint 6 will audit comprehensively. Don't try to make 4a's scrubber smarter — the right place is the audit pass.

### Asymmetric display (load-bearing — don't regress)

`Stats.OnEncounterStart` / `Stats.OnChallengeModeStart` surface stats only when reassuring:
- First attempt → always surface (no history is neutral, not catastrophizing).
- Wipe rate ≤ `stats_threshold` → surface.
- Wipe rate > threshold → suppress silently. The user is never told their wipe rate is "too high to surface" — that defeats the point.

User-invoked stats commands (`/tox stats`, `/tox stats <dungeon>`, `/tox week`) ignore the surface toggle and threshold — the user asked, so the raw numbers print regardless. This live-vs-invoked distinction is the rule: live filtering and live surfacing respect their toggles; user-invoked surfacing is always honored.

### chatFilter dispatch (Sprint 4a final)

1. `isPaused` → pass through, no capture, no buffer writes
2. `db.enabled == false` → pass through
3. `db.channels[channel] == false` → pass through
4. `RuleEngine.classify` with handling override resolver
   - `silent`/`del`/`edit`: emit handling, record flagged event in buffer
   - `pass`: continue
5. `PositiveCapture.capture` (only when handling==pass; sarcasm de-flags)
6. Sprint 0 fixtures (fallback)

### Slash commands added

| Group   | Commands |
|---------|----------|
| Surface | `/tox lift`, `/tox positive [ui on\|off]`, `/tox session` |
| Stats   | `/tox stats`, `/tox stats <dungeon>`, `/tox stats threshold <0-100>`, `/tox stats surface on\|off`, `/tox week` |
| Pinned  | `/tox star <id>`, `/tox unstar <id>`, `/tox starred` |
| Ritual  | `/tox check`, `/tox check add\|remove\|list <item>`, `/tox check y\|n\|cancel` |
| Buffer  | `/tox retention <days>` |

`/tox check` is slash-driven Y/N (state machine in Grounding.lua). 4b may add a popup; the public surface (`Start`, `Respond`, `Cancel`, `IsRunning`, `ListItems`, `AddItem`, `RemoveItem`) is stable so 4b's `/tox ready` can chain it without changes.

### Event hooks

`OnPauseEvent`/`OnResumeEvent` were replaced with specific handlers that pause AND record:
- `ENCOUNTER_START` → `OnEncounterStart` (pause + Stats surface)
- `ENCOUNTER_END` → `OnEncounterEnd` (resume + Buffer.RecordEncounter, success-aware)
- `CHALLENGE_MODE_START` → `OnChallengeModeStart` (pause + record runs_started + Stats surface)
- `CHALLENGE_MODE_COMPLETED` → `OnChallengeModeCompleted` (resume + record completed)
- `CHALLENGE_MODE_RESET` → `OnChallengeModeReset` (resume only)
- `PLAYER_DEAD` → `OnPlayerDead` (record death; no pause change)

AceEvent-3.0 only allows one handler per event; combining pause + record into a single handler is the correct pattern. Sprint 0's two-event-name design is preserved at the user-visible level (still pauses, still resumes), the implementation just picked up data-recording responsibilities.

### Known minor false-positives (Sprint 4a; document, don't fix)

- **Self-thanks capture.** A user typing "thanks tank" themselves where they ARE a tank gets captured as direct_to_user. We don't filter on sender. Pragmatic; fine.
- **Generic "thanks all" without role/name.** Captured as `thanks_role`/`thanks_user` only when the next token matches; "thanks all" wouldn't match either. So generic group thanks isn't captured. Acceptable; Sprint 7 tuning if patterns underperform.
- **GetInstanceInfo mid-CHALLENGE_MODE.** The mapID/instanceID we record is what `GetInstanceInfo()` reports at the event, which is stable in practice but not guaranteed across all dungeon types. Counters may bucket incorrectly in edge cases. Revisit if collisions show up.
- **PII scrub misses.** Conservative, name-context-only. A name appearing without a thanks-token or @ prefix isn't scrubbed. Sprint 6 audit.

### Permanent discipline (carried forward)

- **Tonal grep:** every sprint that adds user-output strings, grep `!|great|oops|sorry` against `addon/Commands.lua addon/PositiveCapture.lua addon/Stats.lua addon/Grounding.lua addon/ToxFilter.lua addon/Database.lua addon/Buffer.lua addon/PIIScrub.lua` (plus 4b's new files when 4b lands). Self-referential matches (the grep documentation itself, pattern-data tables that legitimately contain words like "great") are acceptable.
- **Pipe doubling:** every print/chat-bound string with literal pipes uses `||`. Every new help-text addition this sprint follows the rule.

---

## Build 1 Sprint 4b: visual UI + /tox ready orchestration

**Status: complete.**

Three modules layer the visual surface on top of Sprint 4a's data layer:

- `addon/Highlight.lua` — chat-line color tinting on captured positive moments
- `addon/Breathing.lua` — animated box-breathing frame
- `addon/Ready.lua` — `/tox ready` meta-orchestration state machine

### Highlight: two-surface design (load-bearing)

The visual treatment requires synchronous knowledge of whether the current message is a positive moment AT the time `chatFilter` decides what to return — a subscriber callback fires asynchronously after `capture()` returns and cannot influence the chat-frame return path. So Highlight exposes both:

1. **Synchronous helper** — `Highlight.tintIfEligible(msg, moment) -> string|nil`. Called inline from `chatFilter` on the pass-through branch, after `PositiveCapture.capture` returns a moment. Returns a `|cFF66AA66<msg>|r`-wrapped string when `db.positive_ui == true` AND not paused; nil otherwise. The chatFilter then returns `false, tinted, ...` to replace the visible line.
2. **Subscriber stub** — `Highlight.OnPositiveMoment(moment)`. Registered via `PositiveCapture.subscribe` in `OnInitialize`. No-op observer in 4b; preserves the subscriber API contract so future modules (telemetry, sound cues) attach the same way.

Don't collapse this to a single surface — the subscriber-can't-influence-return-value asymmetry is the load-bearing insight.

### chatFilter dispatch (Sprint 4b final)

1. `isPaused` → pass through, no capture, no tint
2. `db.enabled == false` → pass through
3. `db.channels[channel] == false` → pass through
4. `RuleEngine.classify` (silent / del / edit branches as before, all record flagged events)
5. Pass-through: `PositiveCapture.capture` returns a moment (or nil); if a moment exists, `Highlight.tintIfEligible` is called — when it returns a tinted string, chatFilter returns `false, tinted, ...`
6. Sprint 0 fixtures (fallback)

### Pipe-doubling exception for WoW color codes

The Sprint 3 fix1 pipe-doubling rule (`||` for literal display pipes) does NOT apply to WoW chat-frame escape sequences. `|c<AARRGGBB>` and `|r` are functional control codes — the chat parser USES them to apply colors to spans of text. Doubling them would break the escape and the user would see literal `||cFF66AA66...||r` rendered as garbage.

The discipline:

- **Literal display pipes** (e.g. `<a|b|c>` choice notation in help text) — double to `||`.
- **Functional WoW escapes** (`|c<AARRGGBB>`, `|r`, `|H...|h...|h`, `|T...|t`) — keep as single pipes.

Pipe-doubling audits should exclude `|c[0-9A-Fa-f]{8}` and `|r` patterns when scanning files that legitimately use color escapes (Highlight.lua in Sprint 4b; future UI modules).

### Breathing animation

Single shared frame, lazily created on first `Breathing.Run`. 200×200 dark-translucent backdrop with an inner colored block child and a `GameFontNormalLarge` label below.

OnUpdate-driven state machine. Four phases per cycle, each lasting `db.breathe_count` seconds (default 4):

```
inhale  → block scales BLOCK_MIN → BLOCK_MAX (40 → 160 px)
hold1   → block stays at BLOCK_MAX
exhale  → block scales BLOCK_MAX → BLOCK_MIN
hold2   → block stays at BLOCK_MIN
```

Cycle count comes from `db.breathe_cycles` (default 4). On natural completion, the frame hides and prints `Box breathing complete.`.

**Cancellation:** `tinsert(UISpecialFrames, "ToxFilterBreathingFrame")` registers the frame for Esc-close. The frame's `OnHide` script detects mid-run dismissal (state still set) → clears state, fires the cancel hook, no completion print, no `onComplete` callback. Programmatic `Breathing.Cancel()` does the same. Clean cancel/complete asymmetry is what lets `Ready.lua` distinguish "step finished, advance chain" from "step aborted, kill chain."

**Position:** account-wide via `db.breathe_position = { x, y }` (UI choice, not character choice). Drag-to-move via the mouse persists on `OnDragStop`. `/tox breathe position reset` clears it back to center.

### Ready orchestration

`addon/Ready.lua` chains steps in `db.ready_config.order` whose `db.ready_config.include[name]` is true. Default order is `{ "grounding", "breathing", "lift" }`, all included.

State machine:

- Module-local `current_chain = { steps = [...], idx = N, token = {} }`.
- `runStep(name, token)` invokes the primitive with an `advance(token)` continuation.
- `advance(token)` increments `idx` and runs the next step; when `idx > #steps`, clears state.
- The `token` is a per-chain table identity. If the chain is cancelled (state cleared) and a stale callback still fires, the token mismatch makes `advance` a no-op.

Step adapters:

- **grounding** — empty `db.grounding_items` → print `"No grounding items configured. Skipping."` and advance immediately. Otherwise register Ready as the cancel hook on `Grounding`, then call `Grounding.Start(advance)`.
- **breathing** — register Ready as the cancel hook on `Breathing`, then call `Breathing.Run(advance)`.
- **lift** — synchronous: call `Commands.lift()`, then advance.

**Cancellation via cancel_hook (load-bearing):** `Grounding.SetCancelHook(fn)` and `Breathing.SetCancelHook(fn)` let Ready listen for `/tox check cancel` and Esc-on-breathing without the primitives knowing about Ready. The hook clears chain state, which makes any subsequent stale `onComplete` callback no-op via the token check.

The primitives are independent: `Grounding.Cancel` / `Breathing.Cancel` work standalone; the cancel hook is just an additional listener Ready attaches and detaches around its step invocations.

### Schema v3 migration

`migrations[3]` backfills `breathe_cycles` (default 4), `breathe_count` (default 4), and `ready_config` (`{ include, order }`) for existing v2 users. `breathe_position` is intentionally left nil so an unmoved frame anchors `CENTER` rather than to a stale offset. Fresh installs land at v3 via DEFAULTS.

### Slash command additions

| Group    | Commands |
|----------|----------|
| Breathe  | `/tox breathe`, `/tox breathe cycles <N>`, `/tox breathe count <N>`, `/tox breathe position <x> <y>\|reset` |
| Ready    | `/tox ready`, `/tox ready list`, `/tox ready include <step> on\|off`, `/tox ready order <s> <s> <s>` |

`/tox positive ui on|off` from Sprint 4a now actually applies the visual treatment (the "Sprint 4b ships..." parenthetical was removed).

### Tonal grep target list (Sprint 4b extension)

Now includes `addon/Highlight.lua addon/Breathing.lua addon/Ready.lua` in the standard grep set. Phase labels (`Inhale`, `Hold`, `Exhale`) and completion line (`Box breathing complete.`) are deliberately bare — no exclamation, no encouragement.

---

## Build 1 Sprint 4 fix: post-verification corrections + debug counter tool

**Status: complete (rolling release with 4a + 4b).** Version `0.0.7-sprint4-fix`. Schema bumped to v4.

In-game verification of 4a + 4b surfaced eight issues. Rather than re-sprint, this fix lands on top of the working tree and ships with 4a/4b in a single commit.

### Issue summary

1. **ASCII arrows.** `/tox test`, `/tox classify`, `/tox rewrite` rendered `→` as a replacement-glyph box in WoW's chat font. All three now use `->`. Lua-source comments still use `→` because they never reach the chat parser.
2. **`party` channel is an alias for `instance`.** WoW retail no longer routes `/p` as a separate event stream — `CHAT_MSG_PARTY*` folds into `instance`. The canonical key in `db.channels` is `instance`; `party` is accepted only as an input alias on `/tox channel party on|off`. `/tox channel list` annotates the row as `instance: on (also: party)` so the modern name leads but the old habit still works. The v4 migration consolidates a legacy `db.channels.party` into `instance` with OR semantics (if either was on, merged is on) and deletes `db.channels.party`. `EVENT_TO_CHANNEL` maps `CHAT_MSG_PARTY*` → `instance`.
3. **`/tox handle <cat> default` interpolates the resolved value.** "Category 'role_attack' reset to default (edit)." instead of bare "reset to default." — surfaces what the user actually got.
4. **Blacklist routes to `edit` (load-bearing).** User blacklist hits previously inherited `general_hostility`'s default of `del`, which is too aggressive for a personally-flagged word — surgical rewrite preserves the line and respects the user's flag without making the channel feel destructive. The fix is hardcoded inline at the blacklist branch in `RuleEngine.lua` (not a `Database.blacklist_handling` constant): `handling = "edit"` regardless of category default OR user `/tox handle` override. The category label stays `general_hostility` so display/labeling paths don't change. **Don't regress this**: future sprints touching the rule-engine integration must keep the blacklist `handling` field hardcoded to `edit`. The comment block at the call site cites this decision.
5. **Whisper first-enable note text.** The `whisper_intro_shown` infrastructure already existed (Sprint 3); only the printed text changed to the spec's factual one-liner: "Whisper filtering enabled. Note: this reads private messages sent to you. Filtered output is shown only to you. Disable with /tox channel whisper off."
6. **Per-bucket instance death/wipe/completion counters.** Largest fix. See the dedicated subsection below.
7. **Breathing frame closes on combat start.** `frame:RegisterEvent("PLAYER_REGEN_DISABLED")` + an `OnEvent` that calls `frame:Hide()` when `state` is set. Routes through the existing `OnHide` handler so cancel-hook semantics match Esc — silent close, no completion print, fires cancel hook so any in-flight `/tox ready` chain aborts. (The fix-spec said "no callback fired"; we deliberately fire the cancel hook instead because a chain silently advancing to `lift` post-combat is the worse UX. Confirmed at planning.)
8. **`/tox debug` counter tool.** New `addon/Debug.lua`. See the dedicated subsection below.

### Counter shape (v4) — instance + difficulty bucket (Issue 6)

Old shape (`encounters[encounterID][difficultyID]`, `dungeons[mapID]`, global `deaths_total`) is removed. New shape lives entirely in `db.session_buffer.counters.instances`:

```
instances[<instance_name>][<bucket>] = {
    deaths, wipes, completions, last_event,
}
```

`<instance_name>` is `GetInstanceInfo()`'s English name (Localization is Future Work). `<bucket>` is one of `normal | heroic | mythic | M0 | M2-5 | M6-10 | M10+`.

**Scope filter (locked).** `PLAYER_DEAD` only counts when `GetInstanceInfo()`'s `instanceType` is `party` (5-player) or `raid`. Battleground (`pvp`), arena, scenario, and open-world (`none`) deaths are not tracked — there is intentionally **no "world deaths" counter**. `ENCOUNTER_END` and `CHALLENGE_MODE_COMPLETED` apply the same filter.

**Bucket assignment is locked at run start.** Two module-local fields in `ToxFilter.lua`:
- `mplus_bucket` is set on `CHALLENGE_MODE_START` from `C_ChallengeMode.GetActiveKeystoneInfo()` and stays sticky across pulls until `CHALLENGE_MODE_COMPLETED`/`RESET`.
- `encounter_bucket` is set on `ENCOUNTER_START` from the difficultyID parameter (mapped via `DIFFICULTY_TO_BUCKET`) and clears on `ENCOUNTER_END`.

Precedence: M+ wins. `effectiveBucket()` returns `mplus_bucket or encounter_bucket or bucketForDifficulty(<current GetInstanceInfo difficultyID>)`. The fallback covers PLAYER_DEAD between pulls or before any encounter has fired.

**M+ bucket boundaries (locked).** From keystone level: `<= 1` → `M0`, `2..5` → `M2-5`, `6..10` → `M6-10`, `>= 11` → `M10+`. Even though level-1 keystones don't exist in current WoW, the bound is `<=1` so a missing/zero level still buckets cleanly to M0.

**Difficulty-ID → bucket map** is a small static table in `ToxFilter.lua`. Documented entries: 1 (Normal dungeon), 2 (Heroic dungeon), 14 (Normal raid), 15 (Heroic raid), 16 (Mythic raid), 17 (LFR → normal), 23 (Mythic dungeon), 24 (Story → normal), 33 (Timewalking → normal). Mythic Keystone (8) returns nil and the keystone-level path takes over. Unknown IDs default to `"normal"` so we still bucket. Revisit if Midnight introduces new IDs.

**Migration v4 reset.** The previous counter data merged BG/world/dungeon scope. It was test data and is discarded — this is acceptable per the project owner. Migration `[4]` rebuilds `counters` to `{ instances = {}, sessions = <preserved>, thanks_total = <preserved> }` and prints a single line: "Migrating counter schema. Previous counter data is reset due to scope changes." Pinned moments and session history are preserved (different scope).

**Asymmetric display threshold applies per (instance, bucket).** `Stats.shouldSurfaceBucket` computes wipe rate from the (instance, bucket) record's `wipes` and `completions`; suppression is silent when over threshold, same as 4a.

**`/tox stats` views.**
- `/tox stats` (no arg) — single-line aggregate: lifetime thanks, instance deaths, instance attempts (won/wiped), instance count, threshold/surface settings. Points at `/tox stats <name>` for breakdown.
- `/tox stats <substring>` — substring-matches against instance names; for each match prints one row per bucket present, formatted by `Stats.formatBucketLine` ("heroic: 3 completed, 1 wiped (25% wipe), 5 deaths").
- `/tox stats threshold <N>` and `/tox stats surface on|off` are unchanged.

### `/tox debug` (Issue 8)

Developer-only counter manipulation. Approach B: gated by `db.debug_enabled` (default `false`). The toggle is hidden from `/tox help`. When the flag is off, every debug subcommand except `enable` prints "Unknown command 'debug'. Try /tox help." — the surface stays invisible to non-developers.

`/tox debug enable` always works (otherwise turning the tool on would itself be gated). `/tox debug disable` only works when the flag is on.

Subcommands when enabled:

```
/tox debug enable | disable
/tox debug version
/tox debug counter <instance> <difficulty> <field> <value>
/tox debug counter list [<instance>]
/tox debug counter reset <instance> <difficulty>
/tox debug counter reset all confirm
/tox debug session reset
```

Field set: `deaths`, `wipes`, `completions`. Buckets: `normal | heroic | mythic | M0 | M2-5 | M6-10 | M10+` (case-insensitive on input). Quoted instance names accept spaces; unquoted form consumes tokens until one matches a known bucket. `reset all` requires the literal `confirm` token (no popup; matches the slash-surface idiom).

### Files touched

New: `addon/Debug.lua`. Modified: `addon/Commands.lua`, `addon/Database.lua`, `addon/Buffer.lua`, `addon/Stats.lua`, `addon/ToxFilter.lua`, `addon/Breathing.lua`, `addon/RuleEngine.lua` (blacklist routing — chose this over `addon/UserRules.lua` because the routing decision lives at the integration point where the synthetic hit's `handling` field is constructed), `addon/ToxFilter.toc`, `.luacheckrc`. Doc updates: `CLAUDE.md` (this section), `addon/README.md`.

### Verification deltas

- `Stats.formatEncounterLine` / `Stats.formatDungeonLine` / `Stats.shouldSurfaceWipeRate` removed. Replaced by `formatBucketLine`, `formatInstanceBlock`, `shouldSurfaceBucket`. Anything reaching for the old names will break loudly; that's deliberate.
- `Buffer.GetEncounterStats(encounterID, difficultyID)` and `Buffer.GetDungeonStats(mapID)` removed. Replaced by `Buffer.GetInstanceStats(instance, bucket)`, `Buffer.GetInstanceBuckets(instance)`, `Buffer.GetAllInstances()`.
- `Buffer:RecordEncounter(instance, bucket, success)` and `Buffer:RecordDeath(instance, bucket)` and `Buffer:RecordChallengeMode(instance, bucket, completed)` — all changed signature. The (encounterID, difficultyID, mapID) arguments are gone. ToxFilter.lua's event handlers do the bucket resolution.
- Tonal grep + pipe-doubling audit pass against `addon/Debug.lua` plus the rest of the standard set. Existing single-pipe leaks in `Commands.classify` output (` | attack:`, etc.) are doubled in this fix as well.

---

## Build 1 Sprint 4 Verification Round 2 fixes

**Status: complete.** Version `0.0.8-sprint4-fix2`. Schema bumped to v5.

In-game verification of the Round 1 fix (`0.0.7-sprint4-fix`) surfaced eight follow-on issues. Like Round 1, this rolls into the working tree on top of 4a/4b/fix and ships before any commit happens.

### Issue summary

1. **F18 — Whisper privacy note didn't print.** Wire was correct; root cause was that prior testing flipped `whisper_intro_shown=true` and the bit persisted. AceDB only strips values **equal to default**, so a written `true` survives logout. Fix: `migrations[5]` force-resets the bit to `false`. One-shot pre-release re-arm — drop the migration after launch (or convert to a `/tox debug` reset).
2. **H8 — Positive moments only captured when whisper was on.** No actual whisper coupling in the code; the symptom came from `chatFilter` short-circuiting on `db.channels[channel] == false` before `PositiveCapture.capture` could run. Whisper defaults off, so whisper messages never reached capture; the user inferred the wrong cause. **Architectural fix:** channel-off no longer short-circuits. The new dispatch always runs `RuleEngine.classify` and (when verdict is `pass`) `PositiveCapture.capture`; channel-off only suppresses the silent/del/edit handling and the highlight tint. **Whisper carve-out (load-bearing):** `PositiveCapture.capture` checks `event == "CHAT_MSG_WHISPER"` and `db.channels.whisper == false`, returning nil unconditionally. Whisper is the one channel the user explicitly opted out of; capturing positive moments from private 1:1 messages would contradict the opt-out. Don't regress this: the privacy carve-out is a deliberate exception to the otherwise-uniform "channel-off still captures" rule.
3. **H8 supplemental — `ty edvins` didn't capture.** `UnitName("player")` can return `Name-Server` on connected realms. `PositiveCapture.userNameLower` now strips everything from the first `-` onward before lowercasing, so `Edvins-Stormrage` matches `edvins`.
4. **I2 — `/tox positive ui` toggle.** Previous implementation: no-arg form printed state; `on`/`off` set explicitly. The user wanted no-arg to toggle. Fix: bare `/tox positive ui` flips the value; `/tox positive ui on|off` still sets explicitly.
5. **I9 — Box breathing during combat.** `Breathing.Run` now calls `InCombatLockdown()` at entry; if true, prints `Cannot start breathing during combat.` and fires `onComplete` so a `/tox ready` chain advances past the step rather than stalling. Standalone `/tox breathe` just prints and returns. Routed through `onComplete` — not the cancel hook — because skipping is a clean step transition, not an abort.
6. **I12 — `/tox check y/n` inside `/tox ready`.** Diagnostic grep on `Commands.lua` and `Grounding.lua` found no Ready-state guard or early-exit path. Code-side trace through Commands.check → Grounding.Respond → onComplete → Ready.advance is correct. Shipping with no code change; re-verify after the I16 fix lands. If I12 persists, the next investigation should add temporary logging to Grounding.Respond rather than speculating in code.
7. **I16 — Cancellation in Ready chain.** Two parts. Master abort: new `Ready.Cancel()` clears chain state, then calls `Grounding.Cancel`/`Breathing.Cancel` if either primitive is running. Wired to `/tox ready cancel`. The existing `/tox check cancel` cascade was already correct (Grounding.Cancel → fireCancelHook → Ready's hook → clearChainState); no code change needed there beyond documentation.
8. **I7 — Cycle indicator on breathing.** Second `FontString` (`GameFontNormal`, anchored BOTTOM +10) below the existing phase/count label (which moved up to BOTTOM +28 to make room). Updated each tick from `state.cycle` and `state.cycles` in `applyPhaseVisual`. Format: `Cycle 2 of 4`.
9. **H1 clarification — `/tox stats` vs `/tox session`.** Locked: `/tox stats` is lifetime; `/tox session` is current session. No new subcommand on `/tox stats`. Improved error text on no-match: `No instance named 'X' found. Use /tox session for current-session stats.` Help text for both commands now points at the other so the discoverability gap closes.

### Channel-off semantics change (load-bearing — don't regress)

The `chatFilter` dispatch was restructured. Old order: pause → master → channel → engine → capture → fixtures, with channel-off short-circuiting everything. New order: pause → master → engine (always) → handling (channel-gated) → capture (always when verdict is pass; never when whisper is opted out) → highlight (channel-gated) → fixtures (channel-gated).

The principle: **channel-off means "don't modify this channel's messages," not "ignore this channel."** Positive-moment capture is observation, not modification, so it's not gated by the channel toggle. Whisper is the privacy exception: opting whisper off means the user doesn't want ToxFilter reading their private messages at all, including for positive observation.

Future sprints touching `chatFilter` must keep the channel toggle scoped to handling + visual treatment, not the engine pass and not capture (modulo the whisper carve-out).

### Schema v5 migration

`migrations[5]` is a one-shot reset of `whisper_intro_shown` to `false`. Reasoning is in the migration's comment block. Existing testers who saw the privacy note during prior rounds will see it again on next `/tox channel whisper on`. Acceptable for pre-release; remove once shipped, or convert to a `/tox debug` resettable.

### Files touched

Modified: `addon/Database.lua` (LATEST_SCHEMA_VERSION=5, migrations[5]), `addon/ToxFilter.lua` (chatFilter restructure, VERSION bump), `addon/PositiveCapture.lua` (whisper opt-out check, `-Server` suffix strip), `addon/Commands.lua` (positive ui toggle, /tox ready cancel dispatch, stats error text + help refinements, /tox positive help text refresh), `addon/Breathing.lua` (combat-lockdown gate, cycle indicator FontString, label re-anchor), `addon/Ready.lua` (Ready.Cancel master abort), `addon/ToxFilter.toc` (version), `.luacheckrc` (InCombatLockdown global). New: `Verification_Protocol.md` (created from scratch). Doc updates: `CLAUDE.md` (this section), `addon/README.md`.

### Tonal-grep + pipe-doubling discipline

Standard grep set (`Commands.lua`, `PositiveCapture.lua`, `Stats.lua`, `Grounding.lua`, `ToxFilter.lua`, `Database.lua`, `Buffer.lua`, `PIIScrub.lua`, `Highlight.lua`, `Breathing.lua`, `Ready.lua`, `Debug.lua`) ran clean against `!|great|oops|sorry`. Pipe-doubling audit found no single-pipe leaks in user-facing strings (functional `|c<AARRGGBB>` / `|r` color escapes in Highlight.lua remain single-pipe per the documented exception).

---

## Build 1 Sprint 4 Verification Round 3 fixes

**Status: complete.** Version `0.0.9-sprint4-fix3`. No schema change.

Round 2 surfaced four follow-on items in in-game testing. Only one prompted a code edit; the other three resolved as diagnostic investments or documented gotchas. Like prior rounds this rolls into the working tree on top of 4a/4b/fix/fix2 before any commit.

### Issue summary

1. **Counter set vs add (reported as code bug, resolved as no-op).** The user observed `/tox debug counter ... <field> N` appearing additive across invocations. Source-side trace through `addon/Debug.lua` showed `setCounter` at line 109 already writes `instances[instance][bucket][field] = value` — plain assignment, set semantics, no `+=` anywhere in the path. No code change made. Most plausible cause of the in-game observation: stale deploy from an earlier iteration where the operation may have been additive. Re-deploy of current source + re-run of H22 with three identical `N` values is the verification step. If H22 still fails on the fresh source, the diagnostic prints below pin it down.

2. **Counter-scope filter verification (clean trace, no code change).** Walked the `PLAYER_DEAD` / `ENCOUNTER_END` / `CHALLENGE_MODE_COMPLETED` handlers in `ToxFilter.lua`. All three gate on `isCountedScope(instanceType)` which restricts to `party` (5-player dungeon) or `raid`. `PVP`, `arena`, `scenario`, and `none` (open-world) are silently dropped. No `PLAYER_ENTERING_WORLD` or `ZONE_CHANGED_NEW_AREA` handlers exist anywhere. The H1 instance-scope fix is intact. The user's between-readings counter growth was almost certainly Issue 1 (additive debug invocations) bleeding into the test, not real-event increments outside scope.

3. **Reassuring message not surfacing (resolved as testing methodology + a name-string gotcha — see Hypothesis B/C below).** Walked five hypotheses. A (threshold default 30), D (`stats_surface` default true), and E (`<=` boundary inclusive at 30%) all check out in source. The real issues are B and C, both of which are diagnostic-blindness rather than code bugs.

4. **`count` as alias for `counter` (one-line polish).** Added. `/tox debug count ...` now routes to the same handler as `/tox debug counter ...`.

### Hypothesis B (load-bearing testing-methodology gotcha)

`Stats.OnEncounterStart` / `Stats.OnChallengeModeStart` fire from `ENCOUNTER_START` and `CHALLENGE_MODE_START` respectively — **not** from `PLAYER_ENTERING_WORLD`. Zoning into a dungeon surfaces nothing until the user pulls. This is intentional (zoning is preparation, the encounter pull is the role-anxiety moment) but it surprises testers seeding a low-wipe-rate scenario and expecting a message on zone-in. Verification protocol carries an explicit NOTE on H-series surfacing tests so this isn't re-discovered each round.

### Hypothesis C (name-string mismatch — diagnostic-only response)

`GetInstanceInfo()` returns the API's canonical instance name, which may differ from the seed string by leading article, expansion prefix, or localization. Adding a (per-tester, per-run) diagnostic print at encounter start that displays the exact `(instance, bucket)` the API returns lets the user reconcile against the seeded key immediately, without source-side speculation.

### Diagnostic prints (always-on investment, debug-gated)

Two new prints land in `Buffer.lua` and `Stats.lua`, both gated on `db.debug_enabled` so they emit only when the developer surface is on:

- `Buffer.lua`: every successful counter increment in `RecordEncounter` / `RecordDeath` / `RecordChallengeMode` prints `[ToxFilter Debug] Counter increment: <instance> / <bucket> / <field>`. Direct confirmation that scope-filtered events are dropped (no print on BG / arena / world) and that real instance events route correctly.
- `Stats.lua`: `OnEncounterStart` / `OnChallengeModeStart` print `[ToxFilter Debug] Encounter start in: '<instance>' bucket '<bucket>'` at the moment the surfacing decision is made. The instance string here is exactly what `GetInstanceInfo()` returned — paste-it-back-into-debug-counter to seed correctly.

The prints are deliberately not gated on `stats_surface` or scope filter — they fire regardless so the user can see the input the surfacing logic worked with even when surfacing is suppressed. Zero runtime cost when `debug_enabled` is false.

### Issue 4: `count` alias implementation

One line in `Debug.dispatch`: `if sub == "counter" or sub == "count" then cmdCounter(after); return end`. The help-text line also notes the alias parenthetically. The aliasing happens at the dispatch boundary; downstream `cmdCounter` / `cmdCounterSet` are unchanged.

### Files touched

Modified: `addon/Debug.lua` (count alias + help text), `addon/Buffer.lua` (debug increment helper + three call sites), `addon/Stats.lua` (debug start helper + two call sites), `addon/ToxFilter.lua` (VERSION), `addon/ToxFilter.toc` (Version). Doc updates: `CLAUDE.md` (this section), `Verification_Protocol.md` (H22 corrected expectation, new H25 for scope check via diagnostic print).

### Tonal-grep + pipe-doubling discipline

Standard grep set ran clean against `!|great|oops|sorry`. New debug-print strings contain no display pipes; no functional WoW escapes in scope.

---

## Build 1 Sprint 5: tactical role-callout prioritization

**Status: complete.** Version `0.1.0-sprint5`. Schema v6.

Sprint 5 layers a passive UI enhancement on top of Sprint 4a's role-detection infrastructure and Sprint 4b's chat-tinting pattern: when an incoming message contains a tactical callout addressed to the user's effective role, apply a warm-amber color tint and play a subtle audio cue. Opt-in via `/tox callout on`; off by default.

### Module layout

```
addon/
  Callout.lua          detection + match-vs-user + tint helper + sound trigger
corpus/sprint5.json    30 entries: 12 positives, 10 negatives, 4 multi-role, 4 match-vs-role
```

`Callout.detect(msg, classifier_result)` is pure (no DB calls) so the corpus harness tests it without a database stub. `Callout.matchesUser`, `tintIfEligible`, and `playSoundIfEligible` consult `ns.Database` directly.

### Architectural principle: time-critical UI stays active during combat (load-bearing)

Sprint 4b's `Highlight` (positive moments) pauses during combat because positive moments can be reviewed later via `/tox lift`. Sprint 5's `Callout` does **not** pause — callouts during combat are precisely the moment that matters most. The general rule, applied to all future UI sprints:

- **Passive UI for emotional support → pauses during the Midnight combat window.** Sprint 4b Highlight, future positive-affect surfaces.
- **Time-critical UI → stays active during combat.** Sprint 5 Callout, future tactical alerts.

`chatFilter` was restructured to support this distinction (see "chatFilter dispatch — Sprint 5 final" below).

### Color register: warm amber `|cFFEEBB55`

RGB(238, 187, 85). Chosen for:

- **Discrimination from Sprint 4b's positive green `|cFF66AA66`** under all three common colorblindness types. Deuteranopia and protanopia separate the colors via the substantial lightness gap (~170 perceived vs ~140) and the much larger red channel (238 vs 102). Tritanopia separates them via the red component (amber reads red-ish, green reads gray-green).
- **Warning register** ("look here, this is for you"), not celebratory. Cyan/blue would read informational but conflicts with WoW class-color cyan (mage) and is harder for tritanopia to separate from green.
- **Subtle.** Not pure system-yellow `|cFFFFFF00`, not legendary-orange `|cFFFF8000`. Sits in an open register between subtle and salient.

Future sprints needing additional tint colors must check this list before picking. Current registers occupied:
- `|cFF66AA66` desaturated green — Sprint 4b positive moments (passive, pauses)
- `|cFFEEBB55` warm amber — Sprint 5 role callouts (time-critical, active during combat)

### Sound: FileDataID `540061` via `PlaySound(..., "Master")`

Locked Sprint 5. Channel `"Master"` routes through master volume per spec. The sound ID is one line in `Callout.lua` (`local CALLOUT_SOUND_ID = 540061`); J13 verification asks whether the sound feels like "this is for you" rather than a common WoW event (whisper, AH outbid, raid warning, etc.). If swap needed, that's a one-line edit.

### Detection algorithm

`Callout.detect`:
1. **Sarcasm gate.** If `classifier_result.signals` contains any sarcasm flag (antonymic_praise / passive_thanks / slash_s / maybe_try), return nil.
2. **Attack-label gate.** If `classifier_result.labels` contains any `attack` token, return nil ("you trash tank" is already handled by Sprint 2's classifier; treating it as a callout would be wrong).
3. **Callout-local tokenization** on the raw message: split on `[\s/]+` so `tank/healer` parses as two tokens. Lowercase + trim trailing/leading punctuation. Not via `Normalize` because Callout doesn't need hash-table alignment.
4. **Role-target scan.** For each token matching `Patterns.ROLE_TARGETS` (singular + plural + diminutive), check ±3 window for a `Patterns.CALLOUT_VERBS` token. If present, the callout fires for that role.
5. **Multi-role join.** "tank and healer cooldowns" — the trailing verb anchors the first role via window; the second role gets pulled in by direct adjacency or `and`/`&`/`+` separator to an already-hit role position.
6. Return `{ roles = ["tank", "healer"], span = msg }` or nil. Role order is stable: tank, healer, dps.

### Pattern data (Patterns.lua additions)

- `ROLE_TARGETS` — singular + plural + diminutive role tokens. Distinct from `ROLE_NOUNS` (the classifier's role-attack anchor set, intentionally singular-only per Sprint 2 design). `PositiveCapture` was refactored to use this shared table instead of its own local copy.
- `ROLE_TARGET_TO_ROLE` — token → canonical role string (`tank`/`healer`/`dps`).
- `CALLOUT_VERBS` — imperative/directive verbs (subset of `TACTICAL_MARKERS` filtered to imperatives; `stop` added during Sprint 5 corpus tuning). Mechanic nouns (fire, void, swirly, puddle) are deliberately excluded — those are status mentions, not directives.
- `CALLOUT_JOINS` — `{and, &, +}`. The `/` separator is handled by Callout's tokenization, not by this set.

`ROLE_NOUNS` extension (adding plurals) is deferred to Sprint 7 tuning so the Sprint 2 classifier behavior stays unchanged.

### Schema v6 migration

`migrations[6]` backfills three fields on existing v5 users:

```
callout_enabled = false   -- master off by default (opt-in, same default as positive_ui)
callout_ui      = true    -- visual sub-toggle (meaningful only when master is on)
callout_sound   = true    -- audio sub-toggle (same)
```

Fresh installs land at v6 via DEFAULTS.

### chatFilter dispatch — Sprint 5 final (load-bearing — don't regress)

```
1. master toggle off → pass
2. RuleEngine.classify (read-only; always runs)
3. Callout.detectMatching (read-only; runs during pause too — time-critical)
4. If paused:
     - if channel-on and callout matches: tint + sound, return tinted
     - else: pass (no handling, no capture, no highlight, no fixtures)
5. Non-paused, channel-on: handling (silent/del/edit) with flagged-event buffer write
6. Non-paused: PositiveCapture.capture on pass verdict (whisper carve-out inside)
7. Non-paused, channel-on: co-occurrence — callout match preempts positive Highlight (callout color wins, sound plays once)
8. Non-paused, channel-on: Highlight.tintIfEligible only when no callout match
9. Non-paused, channel-on: Sprint 0 fixtures
```

The `isPaused` check is no longer the first short-circuit. Callout's read-only classifier output + chat-frame string return + `PlaySound` are all passive operations safe to perform during the Midnight restricted-execution window. Buffer writes (PositiveCapture, flagged-event recording) and content modification (handling branches, fixtures) remain paused.

### Slash commands

| Group   | Commands |
|---------|----------|
| Callout | `/tox callout`, `/tox callout on\|off`, `/tox callout ui on\|off`, `/tox callout sound on\|off` |

Bare `/tox callout` **prints state** (master + ui + sound), does not toggle. This is deliberately different from `/tox positive ui` (no-arg toggles per Sprint 4 fix2 I2) — the user spec defined them differently. Help group "Callout" added between Ritual and Breathe in the grouped help view. State surfaced in `/tox list` comprehensive snapshot.

### Co-occurrence with PositiveCapture

A message can detect as both a positive moment (Sprint 4a) and a role callout. Precedence per spec:
- PositiveCapture still records the moment to buffer (data layer).
- For chat display: callout tint preempts the green positive tint.
- Audio: callout sound plays once (no stacking).

Implementation: `chatFilter` calls Callout first; if callout matches, returns tinted string. Only when callout doesn't match does Highlight.tintIfEligible get a chance.

### Test corpus

`corpus/sprint5.json` — 30 entries. Sprint 5 ships at 100% detection, 100% negative-rejection, 100% role-match against the seeded corpus. Sprint 2 corpus still at 100% — no regression.

### Known false-positive / false-negative risks (Sprint 7 tuning)

- **`great pull tank` (no mocking noun) fires as a tank callout.** This is earnest praise containing a callout verb. The current detection has no way to distinguish "great pull tank" (praise) from "tank, great pull" (also praise) from "pull tank" (callout). Acceptable false-positive cost: the user gets an amber-tinted "great pull tank!" — annoying-ish but not harmful. Sprint 7 can extend the sarcasm/praise gate (e.g. add `pull` to `ANTONYMIC_PRAISE_SECOND`, or have Callout reject when a positive verb sits adjacent to the role token).
- **`tanks died` doesn't fire.** No verb in window. By design — status reports aren't callouts. Listed for completeness.
- **`tank low`, `dps oom`** — status, not callout. `low` and `oom` are intentionally excluded from `CALLOUT_VERBS`. Acceptable.
- **Self-attribution (`I'm the tank`)** — no callout verb in window. By design.
- **Adversarial sarcasm** — `great pull tank einstein` currently flags as a callout because `pull` isn't in `ANTONYMIC_PRAISE_SECOND`. The corpus uses `good job tank einstein` instead (which the existing sarcasm pipeline does catch). The deeper pattern gap is documented above.

### Harness extension

`scripts/run-corpus.sh` now runs two passes: Sprint 2 (existing) and Sprint 5 (new). The harness loads `Callout.lua` and stubs `ns.Database` with a per-entry effective-role for the role-match assertion. Python-side conversion adds a second JSON-to-Lua step for `corpus/sprint5.json`; the harness exits cleanly when the file is absent (skip with note).

### Files touched

New: `addon/Callout.lua`, `corpus/sprint5.json`. Modified: `addon/Patterns.lua` (ROLE_TARGETS, ROLE_TARGET_TO_ROLE, CALLOUT_VERBS, CALLOUT_JOINS), `addon/PositiveCapture.lua` (refactor to shared role data), `addon/Database.lua` (schema v6, migration, defaults), `addon/Commands.lua` (`/tox callout` + help + list), `addon/ToxFilter.lua` (chatFilter restructure, VERSION), `addon/ToxFilter.toc` (Callout.lua, Version), `scripts/run-corpus.sh` (Sprint 5 pass), `.luacheckrc` (`PlaySound`). Doc updates: `CLAUDE.md` (this section), `addon/README.md`, `Verification_Protocol.md` (Section J).

### Tonal-grep + pipe-doubling discipline

Standard grep set extended to include `addon/Callout.lua`. Color escapes `|cFFEEBB55` / `|r` in Callout.lua remain single-pipe per the documented Sprint 4b carve-out.

---

## Build 1 Sprint 5 fix: audio swap + state-persistence trap diagnosed

**Status: complete.** Version `0.1.1-sprint5-fix`. No schema change.

In-game verification of `0.1.0-sprint5` surfaced two reported issues. Diagnostic prints (gated on `db.debug_enabled`) revealed that one was a real silent-sound bug and the other was a misinterpreted state-persistence trap, not a code latch.

### Issue 1: sound `540061` was silent in-client (real bug, swapped)

Documentation suggested `540061` (a FileDataID) should play through `PlaySound(id, "Master")`. In-client testing showed it produced no audible output (confirmed via `/run PlaySound(540061)` silent, `/run PlaySound(8959)` audible). Swapped `CALLOUT_SOUND_ID` to `8960` (`SOUNDKIT.READY_CHECK`). Audible confirmed. The constant is one line in `addon/Callout.lua` for future swaps.

**Project lesson:** PlaySound IDs sourced from documentation/databases need in-client verification before locking. The silent-vs-audible distinction isn't always documented; the FileDataID vs old SoundKit ID system has compatibility quirks. Future audio choices should test in-client during the build phase, not at verification.

**Subjective register, locked-for-now, flagged-for-future:** `8960` is audible but reads as too prominent for ongoing combat use. Locked at `8960` in this fix; a future quieter alternate (candidates: `38326`, `46167`, or other softer chimes) will be picked when the user has time to feel-test in real combat. The swap is one line.

### Issue 2: reported "first-fire-only" was a state-persistence trap, not a code latch

The original report described "first callout tints; subsequent callouts don't" across messages in the same session. Diagnostic prints showed:

```
playSoundIfEligible entry: enabled=true, sound=false, has_detection=true
tintIfEligible entry: enabled=true, ui=false, has_detection=true
tintIfEligible returning: nil (ui_off)
```

Every print block — including for messages that should have tinted — showed `ui=false` and `sound=false`. `/tox callout on` only flips `callout_enabled`; the sub-toggles persisted from prior J7/J8 sub-toggle testing. AceDB preserves non-default writes across `/reload`, so a `false` set earlier survived indefinitely. After flipping ui+sound back on via `/tox callout ui on` and `/tox callout sound on`, three consecutive `healers dispel` messages all tinted and played audio correctly. No first-fire latch exists in the code.

**Trap shape (worth remembering, applies project-wide):** AceDB persists explicit non-default writes. A sub-toggle off-test followed by re-enabling only the master leaves the sub-toggles off. Verification of any feature with sub-toggles must either (a) explicitly restore sub-toggles in Phase 0 / pre-test setup, or (b) inspect state via `/tox callout` (or equivalent) before declaring a behavior bug. This is the same shape of trap as the Sprint 4 fix2 F18 issue (`whisper_intro_shown` persisting `true` across sessions and masking a re-test) — same lesson, different field.

### Diagnostic prints kept as permanent infrastructure (Sprint 4 fix3 precedent)

Six debug-gated prints landed in `addon/ToxFilter.lua` (chatFilter entry, Callout.detect result, Callout.matchesUser result) and `addon/Callout.lua` (tintIfEligible entry/return, playSoundIfEligible entry). All gated on `g.debug_enabled` — zero cost when off. The `detectMatching` call in chatFilter was inlined as `detect` + `matchesUser` so the intermediate detection result is visible separately from the match decision.

These prints are the established pattern for runtime-only investigations (Sprint 4 fix3 introduced it for counter-scope diagnosis; Sprint 5 fix extends it). They paid for themselves on this very investigation by surfacing the sub-toggle state in one read of the chat log. Future runtime-only bugs follow the same approach: add debug-gated prints, deploy, capture log, diagnose. Do not remove these in subsequent sprints unless the diagnostic-print infrastructure is being replaced by something better (live state inspector, etc.).

### Corpus addition

`corpus/sprint5.json` gains `cl_neg_healer_needs_to_heal` — `"healer needs to heal"` with `expected_roles = []`. Two role-target tokens (`healer`, `heal`) with no callout verb in window; should return nil. Locks in the negative behavior so future tuning that touches verb sets or detection logic can't accidentally over-fire on bare role mentions. Sprint 5 corpus is now 31 entries (was 30) at 100%.

### Files touched

Modified: `addon/Callout.lua` (sound ID, P4/P5/P6 prints), `addon/ToxFilter.lua` (P1/P2/P3 prints, `detectMatching` inlined at call site, VERSION), `addon/ToxFilter.toc` (Version), `corpus/sprint5.json` (one negative entry). Doc updates: `CLAUDE.md` (this section).

### Tonal-grep + pipe-doubling discipline

Standard grep set clean across modified files. New debug-print strings contain no `!|great|oops|sorry` violations and no display pipes.

---

## Build 1 Sprint 5 fix2: callout state-mismatch note

**Status: complete.** Version `0.1.2-sprint5-fix2`. No schema change.

In-game verification of `0.1.1-sprint5-fix` exposed a UX gap, not a bug. A user who toggled a callout sub-toggle off during prior testing (`/tox callout ui off` or `/tox callout sound off`), then later flipped only the master back on with `/tox callout on`, sees confirmation that the feature is enabled but no callouts ever fire visibly or audibly. The sub-toggle state persisted across sessions (AceDB preserves explicit non-default writes), and the master-on confirmation gave no signal that the feature was effectively neutered. The Sprint 5 fix diagnostic prints surfaced this exact trap once (the user re-enabled sub-toggles by hand once they saw the debug state); fix2 closes the gap so a non-developer never has to enable debug to find it.

### The state-persistence trap pattern (load-bearing — name and reuse)

This is the third instance of the same trap shape:

- **Sprint 4 fix2 F18** — `whisper_intro_shown` persisted `true` across sessions, so the privacy note silently failed to re-print during verification re-runs.
- **Sprint 5 fix** — sub-toggle off-state persisted across sessions, so re-enabling the master alone left the feature visually/audibly silent.
- **Sprint 5 fix2** — same shape, different fix angle: instead of resetting the persisted state via migration, surface the inconsistency in the user-facing path.

**Generalized rule for any feature with master + sub-toggles:** the master-on path (slash command, status query, addon load) should detect inconsistent sub-toggle state and surface a brief explanatory note pointing at the specific sub-toggle command to fix it. The note appears only when the user might be surprised — never after an explicit user disable (`off`, `ui off`, `sound off`), because the user just made that choice deliberately. Future sprints adding any feature with this shape (master + N sub-toggles) should include a state-mismatch note from the start, not as a follow-up fix.

### Implementation

`Callout.GetStateMismatchNote()` lives in `addon/Callout.lua` next to the other DB-aware helpers. Returns nil when state is consistent (master off, or master on with both sub-toggles on); returns a single combined string when master is on but at least one sub-toggle is off. Three combined-string variants (ui off only, sound off only, both off) — single combined note per spec, not split. Callers add the `[ToxFilter]` prefix, keeping the helper composable and testable.

Three call sites:

- `addon/Commands.lua` — `Commands.callout` no-arg branch (after the state line) and `sub == "on"` branch (after `out("Callout enabled.")`).
- `addon/ToxFilter.lua` — `OnEnable`, after the version-confirmation `print` so `/reload` re-checks state on every load.

Deliberately **not** called after `off`, `ui off`, `ui on`, `sound off`, `sound on`. The first three are explicit user disables (irrelevant to remind them). The `on` cases for sub-toggles bring the user closer to consistency, not away from it; if they flip the second sub-toggle on, the next state query won't print a note (consistency reached). The deliberate omission is to keep the surface from feeling nagging.

### Files touched

Modified: `addon/Callout.lua` (new helper), `addon/Commands.lua` (two call sites in `Commands.callout`), `addon/ToxFilter.lua` (call site in `OnEnable`, VERSION), `addon/ToxFilter.toc` (Version). Doc updates: `CLAUDE.md` (this section), `addon/README.md` (one line on sub-toggle persistence).

### Tonal-grep + pipe-doubling discipline

Standard grep set ran clean against `!|great|oops|sorry`. New note strings contain a literal `or` between two slash commands (no display pipes), so no pipe-doubling concerns. Discipline still ran.

---

## "What's out of scope per sprint" — historical bullets (verbatim from pre-archive CLAUDE.md)

Preserved as a chronological summary index. The detailed write-ups above are authoritative for each sprint.

- Sprint 0 (done): skeleton + four-mode dispatcher + Midnight pause logic.
- Sprint 1 (done): rule engine, hash table lookup, encoded rule data, real categories.
- Sprint 2 (done): constructive-vs-hostile classifier, surgical rewrite, test corpus harness.
- Sprint 3 (done, Build 1): AceDB / SavedVariables, whisper toggle, per-user category-handling overrides, full slash suite.
- Sprint 4a (done, Build 1): session buffer, positive-moment capture, pinned moments, encounter/dungeon counters, asymmetric stats surfacing, slash-driven grounding ritual.
- Sprint 4b (done, Build 1): chat-line highlight UI, animated box-breathing frame, `/tox ready` meta-orchestration.
- Sprint 4 fix (done, Build 1): post-verification fixes (ASCII arrows, channel alias, default interpolation, blacklist edit-routing, whisper text, instance-only per-bucket counters, breathing combat-cancel) + `/tox debug` developer counter tool.
- Sprint 4 fix2 (done, Build 1): second post-verification round (whisper privacy bit reset via v5 migration, chatFilter channel-off no longer short-circuits capture with whisper privacy carve-out, `-Server` suffix strip on UnitName, `/tox positive ui` no-arg toggles, combat-lockdown gate on `/tox breathe`, cycle indicator on the breathing frame, `/tox ready cancel` master abort, `/tox stats` vs `/tox session` discoverability fixes).
- Sprint 4 fix3 (done, Build 1): third post-verification round — `count` alias for `counter`; debug-gated diagnostic prints on counter increments and encounter-start so future scope/name-mismatch investigations are self-evident; no code change for the reported "additive counter set" (source already uses set semantics) or for the scope-filter (trace clean); Hypothesis B (encounter pull required for surfacing) documented as a permanent testing-methodology gotcha.
- Sprint 5 (done, Build 1): tactical role-callout prioritization — warm-amber chat tint + audio cue when an incoming message contains a tactical callout addressed to the user's effective role; opt-in via `/tox callout on`, ui and sound sub-toggles; time-critical UI principle (fires during combat, unlike Sprint 4b's passive Highlight); `Callout.lua` + corpus `sprint5.json`; shared `ROLE_TARGETS` table replaces PositiveCapture's local copy.
- Sprint 5 fix (done, Build 1): audio swap `540061` → `8960` (former silent in-client despite docs); diagnostic prints in chatFilter + Callout permanent (Sprint 4 fix3 pattern); reported "first-fire-only" diagnosed as a sub-toggle state-persistence trap (AceDB preserves non-default writes — same shape as Sprint 4 fix2 F18 whisper-intro bit); `8960` audible but subjectively too prominent, flagged for future quieter swap; `cl_neg_healer_needs_to_heal` corpus entry added.
- Sprint 5 fix2 (done, Build 1): callout state-mismatch note — `Callout.GetStateMismatchNote()` helper plus three call sites (`/tox callout` no-arg, `/tox callout on`, `OnEnable`) so a master-on with one or both sub-toggles off prints an explanatory line pointing at the specific sub-toggle command. Names the state-persistence trap pattern (third instance: F18, Sprint 5 fix, this) — load-bearing project principle for any future feature with master + sub-toggles.
