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

## Current state — Build 0 Sprint 1

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

## What's out of scope per sprint

- Sprint 0 (done): skeleton + four-mode dispatcher + Midnight pause logic.
- Sprint 1 (now): rule engine, hash table lookup, encoded rule data, real categories.
- Sprint 2 adds: constructive-vs-hostile classifier, real surgical rewrite logic, populated phrase rules, test corpus harness.
- Sprint 3 (Build 1) adds: AceDB / SavedVariables, whisper toggle, per-user category-handling overrides.
- Build 1 also brings configuration UI.
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
