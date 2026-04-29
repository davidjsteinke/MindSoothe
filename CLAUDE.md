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

## Repo layout

```
addon/                  WoW addon source — what gets deployed
  ToxFilter.toc         TOC manifest, Interface 120005 (Midnight retail)
  ToxFilter.lua         Main addon code
  Libs/                 Embedded Ace3 (LibStub, CallbackHandler, AceAddon, AceEvent, AceConsole)
  README.md             Pre-release user-facing description
app/                    Companion app (empty; Build 2)
corpus/                 Test corpus (empty; later sprints)
docs/                   Design docs (empty)
sensitive/              Slur lists / harassment patterns — gitignored, never committed
scripts/
  deploy.sh             rsync addon/ -> Windows AddOns folder
.luacheckrc             Lua static analysis config
CLAUDE.md               This file
```

## Dev loop

WSL Ubuntu 24.04 → Windows WoW client.

1. Edit Lua/TOC in WSL.
2. `luacheck addon/` from project root — must pass before deploy.
3. `./scripts/deploy.sh` — rsyncs `addon/` to `/mnt/g/Blizzard/World of Warcraft/_retail_/Interface/AddOns/ToxFilter/`.
4. In-game `/reload` (manual — addon never triggers /reload itself).
5. Test in a chat-eligible context.

## Current state — Build 0 Sprint 2

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

## Midnight restricted-execution pause

Blizzard's Midnight expansion restricts addon code execution during boss encounters and Mythic+ pulls. While paused, the chat filter passes everything through unchanged — no rewrite attempts during restricted windows.

**Hooked events (Sprint 0):** `ENCOUNTER_START`/`ENCOUNTER_END`, `CHALLENGE_MODE_START`/`CHALLENGE_MODE_COMPLETED`/`CHALLENGE_MODE_RESET`. These are classical events that have existed for many expansions and fire reliably.

**Known gap, revisit Build 1 Sprint 7:** Midnight may have introduced *additional* event names specifically for restricted-execution windows that we haven't hooked. Anything Midnight added is additive — the classical events still fire — so Sprint 0 won't be silently broken, but coverage may be incomplete. Verify against current `Events.lua` / WoW API docs during Build 1 testing.

**Known gap, PvP:** `PVP_MATCH_ACTIVE` covers entire BG/arena matches rather than per-fight restricted windows, so we deliberately did not hook it. Need to determine what Midnight actually restricts in PvP before adding pause coverage there.

**Known gap, mid-encounter reload:** if the user `/reload`s during an active encounter, `ENCOUNTER_START` won't re-fire and `isPaused` will be `false` (incorrectly). Sprint 0 doesn't address this. Persistence in Sprint 3 might inform a fix.

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

## What's out of scope per sprint

- Sprint 0 (done): skeleton + four-mode dispatcher + Midnight pause logic.
- Sprint 1 (done): rule engine, hash table lookup, encoded rule data, real categories.
- Sprint 2 (done): constructive-vs-hostile classifier, surgical rewrite, test corpus harness.
- Sprint 3 (Build 1) adds: AceDB / SavedVariables, whisper toggle, per-user category-handling overrides.
- Build 1 also brings configuration UI and Sprint 7's threshold gate.
- Build 2 is the companion app.

Don't pre-build any of these. Each sprint validates a layer; later sprints add functionality on top.

## Conventions

- Lua module-local state for module-private values; AceAddon methods for things called via the lifecycle/callback registry.
- WoW API globals are declared in `.luacheckrc` as `read_globals`. Add new ones as we use them.
- TOC paths use backslashes (Windows convention; WoW client accepts on both OSes).
- Ace3 lives under `addon/Libs/` and is excluded from luacheck.
- All user-visible chat output uses literal `[ToxFilter]` prefix via `print()` so the format is consistent regardless of where in the code it originates.

## Things that are NOT in this repo

- The slur/harassment-pattern corpus lives under `sensitive/` and is gitignored. It must not be committed and must not be referenced in code by any public identifier.
- Anything LLM-related (recap generation, central rule classification) lives in the companion app, not in the addon.
