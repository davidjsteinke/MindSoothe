# ToxFilter

Working name. Pre-release. World of Warcraft addon that filters incoming group/raid/instance/BG chat for the installing user only.

## Status

Build 1 Sprint 5. Adds tactical role-callout prioritization on top of the Sprint 4 family (4a affirmative data + 4b visual UI + three rounds of post-verification fixes). When a message contains a tactical callout addressed to the user's effective role, the line gets a warm-amber tint and a subtle audio cue plays. Opt-in via `/tox callout on`; off by default. Callouts are out-of-combat-only: during boss encounters and Mythic+ pulls the game restricts addon code execution and delivers incoming chat as a protected value addons cannot read, so no addon can inspect chat during a fight. Callouts (and the rest of chat filtering) resume the moment the pull ends.

## What it does today

The addon hooks incoming chat in PARTY, RAID, INSTANCE_CHAT, BATTLEGROUND, and (opt-in) WHISPER channels. Each message is tokenized, normalized (lowercase, punctuation stripped, repetition collapsed, leetspeak normalized), hashed, and looked up in a static rule table. The classifier identifies attack-context tokens (role-noun + negative modifier, you-pronoun + negative modifier) and tactical-content tokens (mechanic and direction words), so the rewrite preserves tactical meaning while dropping the hostile scaffold. User blacklist entries surface as `general_hostility` rule hits; whitelist entries suppress rule matching for that token.

Four handling modes per category, user-overridable via `/tox handle`:

- **Pass** — message displays unchanged.
- **Edit** — `[ToxEdit] ` is prefixed and the attack span is removed; tactical content is preserved. When the entire message is attack with no tactical content, only `[ToxEdit]` displays.
- **Del** — line is replaced with `[ToxDel: <Category>]`.
- **Silent** — line never renders.

Sprint 0's hardcoded test triggers are still recognised as a fallback so the four handling modes can be verified without touching the wordlists:

| Type this in chat                | What you'll see                       |
|----------------------------------|---------------------------------------|
| `ToxFilterTest:Pass hello`       | `ToxFilterTest:Pass hello` (unchanged) |
| `ToxFilterTest:Edit hey ok`      | `[ToxEdit] hey ok`                    |
| `ToxFilterTest:Del whatever`     | `[ToxDel: TestCategory]`              |
| `ToxFilterTest:Silent anything`  | (nothing — line never renders)        |

The rule engine runs first, so a real rule hit always wins over a fixture trigger if a single message contains both.

## Pause behaviour

The addon pauses filtering during boss encounters and Mythic+ pulls (Blizzard restricts addon code execution during these windows). When paused, all messages pass through unchanged. You'll see one chat-frame line when paused and one when filtering resumes.

## Whisper filtering — default OFF

`CHAT_MSG_WHISPER` is hooked but the whisper channel toggle defaults to `off`. Whispers are private 1:1 messages and the user's expectation is privacy. Turning whisper filtering on is the user opting into filtering their private conversations, which is their right but should be a deliberate choice. The first time you run `/tox channel whisper on`, a one-line privacy note prints to confirm the choice. Outgoing whispers (`CHAT_MSG_WHISPER_INFORM`) are never hooked — text the user typed is never filtered.

## Slash commands

Run `/tox help` for the grouped summary or `/tox help <command>` for details on a specific command.

**Filtering:**
- `/tox on` / `/tox off` — master toggle.
- `/tox status` — Active, Disabled, or Paused (combat window). Reports a soft-disabled state when every category is set to `pass`.

**Channels:**
- `/tox channel <name> on|off` — toggle one of `raid`, `instance`, `battleground`, `whisper`. `party` is accepted as an input alias for `instance` (WoW retail folds /p into instance chat).
- `/tox channel list` — show all channel states. The instance row is annotated `(also: party)`.

**Category handling:**
- `/tox handle <category> <pass|edit|del|silent>` — override default handling.
- `/tox handle list` — show current map.
- Categories: `identity_attack`, `slur`, `role_attack`, `harassment`, `harm_invocation`, `general_hostility`.

**Role:**
- `/tox role <auto|tank|healer|dps>` — set or override role. `auto` uses `GetSpecializationRole()`. Consumed by Sprint 4a positive capture (`thanks tank` is direct-to-user when role matches) and Sprint 5 callout prioritization.

**User lists:**
- `/tox blacklist add|remove|list <word>` — user-added words. Hits route to `edit` handling regardless of category default — surgical rewrite is the respectful default for personally-flagged words.
- `/tox whitelist add|remove|list <word>` — exempt a word from rule-engine matching.
- Both lists are stored hashed (FNV-1a); the entry's normalized plaintext is kept alongside the hash for `list` output.

**Surface (Sprint 4a / 4b):**
- `/tox lift` — print the most recent positive moment captured. Works during combat-pause windows; user-invoked surfacing is independent of live filtering.
- `/tox positive` — print the 10 most recent positive moments.
- `/tox positive ui` — toggle the in-line highlight (or pass `on`/`off` to set explicitly). Captured positive moments display with a subtle green tint when on. Default off; opt-in. Pause windows suppress the tint regardless.
- `/tox session` — current play-session detail (this session only: start time, encounters, deaths, thanks). For lifetime aggregates across all sessions and instances, use `/tox stats`.

**Stats (Sprint 4a + fix):**
- `/tox stats` — lifetime aggregate across all instances and difficulty buckets. (For the current play session only, use `/tox session`.)
- `/tox stats <instance>` — per-difficulty breakdown (substring match on instance name). Each bucket prints one row: completions, wipes, wipe rate, deaths.
- `/tox stats threshold <0-100>` — wipe-rate threshold for live surfacing (default 30).
- `/tox stats surface on|off` — toggle live surfacing of encounter/dungeon stats (default on).
- `/tox week` — last 7 days summary.

Counters are scoped to dungeons and raids only — battleground, arena, scenario, and open-world deaths aren't tracked. Each (instance, difficulty bucket) pair counts independently. Buckets: `normal`, `heroic`, `mythic`, plus M+ tiers `M0`, `M2-5`, `M6-10`, `M10+` locked at the start of a keystone run.

Live surfacing is asymmetric: a stat is shown only when reassuring (wipe rate ≤ threshold for that specific bucket) or when it's the first attempt. Above-threshold stats are suppressed silently.

**Pinned (Sprint 4a):**
- `/tox star <id>` — pin a positive moment by its `pm_NNN` id. Pinned moments survive retention pruning. Cap 100; oldest unpins on overflow.
- `/tox unstar <id>` — unpin.
- `/tox starred` — list pinned moments chronologically.

**Ritual (Sprint 4a):**
- `/tox check` — start the grounding ritual.
- `/tox check add <item>` / `/tox check remove <item>` / `/tox check list` — manage items. Default list is empty; no suggested items.
- `/tox check y` / `/tox check n` — answer the current item.
- `/tox check cancel` — abort an in-flight ritual.

**Box breathing (Sprint 4b):**
- `/tox breathe` — run an animated box-breathing exercise. Four phases per cycle (inhale / hold / exhale / hold), each `count` seconds. Default 4 cycles × 4 seconds = ~64 seconds. The frame shows the current phase, seconds remaining, and a `Cycle N of M` indicator.
- `/tox breathe cycles <1-20>` — cycle count.
- `/tox breathe count <1-20>` — seconds per phase.
- `/tox breathe position <x> <y>` — frame offset from screen center; `reset` recenters. The frame is drag-to-move; position persists.
- Esc closes the frame mid-cycle. Entering combat (`PLAYER_REGEN_DISABLED`) closes the frame silently — same clean-exit behaviour as Esc, no completion message. Invoking `/tox breathe` while already in combat refuses to start and prints `Cannot start breathing during combat.`

**Callout (Sprint 5):**
- `/tox callout` — print the current state of all three callout settings.
- `/tox callout on|off` — master toggle for the entire feature. Off by default; opt-in.
- `/tox callout ui on|off` — visual sub-toggle. When a message contains a tactical callout addressed to your effective role, the chat line is wrapped in a warm-amber color tint.
- `/tox callout sound on|off` — audio sub-toggle. Plays a subtle UI cue at the same moment. The two sub-toggles are independent for users in voice chat who want one but not the other.
- `/tox callout sound set <name> | list | preview <name>` (Sprint 7a) — choose among a few built-in cues. `list` shows the choices, `preview` plays one once, `set` selects it (and previews it). Default is the low ready-check cue (`readycheck2`, "Ready check, low").
- Sub-toggles persist independently of the master across sessions, so re-enabling the master after sub-toggles were turned off may produce no visible/audible callouts. `/tox callout` shows current state for all three.
- Callouts are out-of-combat-only. During the combat pause the game both stops invoking chat filters and delivers chat text as a protected value, so the addon cannot inspect chat mid-fight; callouts resume when the pull ends. Sprint 4b's passive positive-moment highlight likewise pauses during combat.
- Co-occurrence: a message that's both a positive moment and a callout for your role shows the callout amber tint (not the positive green). The moment is still captured to buffer.

**Sprint 7a additions:**
- `/tox combat on|off` — in-combat silent-drop (default on). During the combat pause the filter otherwise passes everything through; with this on, high-confidence pure hostility (slurs, harm) is silent-dropped while paused. Anything with tactical or informational content passes through untouched. Matching messages vanish with no indication. Gated by the ToxFilter category and the master toggle.
- Typo tolerance: the positive-capture and callout keyword matching tolerates a single-character typo ("thansk tank" still registers). Applies only to those keyword sets — never to the hostility classifier, rule engine, blacklist, or whitelist. Short words and role names stay exact-match-only.
- Emote capture: `/thanks`, `/cheer`, `/salute` and similar emotes aimed at you are captured as positive moments, marked `(emote)` in `/tox positive`. The emote must be directed at you — untargeted emotes (sent to the room with no target) are ignored. Respects the Uplifter category like typed praise. **Limitation: emote detection is English-client (enUS) only** — it keys on English emote wording, so other locales will not capture emotes. A future locale pass would address this.

**Ready (Sprint 4b):**
- `/tox ready` — chain grounding → breathing → lift in your configured order. Each step's natural completion advances the chain. If invoked during combat, the breathing step is skipped (with a message) and the chain proceeds.
- `/tox ready list` — show current chain.
- `/tox ready cancel` — master abort, regardless of which step is currently running.
- `/tox check cancel` or Esc on the breathing frame also aborts the chain.
- `/tox ready include <grounding|breathing|lift> on|off` — toggle a step's inclusion.
- `/tox ready order <step> <step> <step>` — reorder.

**Buffer (Sprint 4a):**
- `/tox retention <days>` — set windowed-event retention (7-365). Default 30. Pinned moments are exempt.

**Inspect:**
- `/tox version`, `/tox rules`, `/tox list`, `/tox test <msg>`, `/tox classify <msg>`, `/tox rewrite <msg>`.

**Developer (hidden):**
- `/tox debug` — counter manipulation tool, gated behind `db.debug_enabled` (default off). Hidden from `/tox help`. Lets a developer seed (instance, difficulty) counter values directly so verification of asymmetric surfacing doesn't require building a real wipe history. Subcommands: `enable | disable`, `version`, `counter <instance> <bucket> <field> <value>`, `counter list [<instance>]`, `counter reset <instance> <bucket>`, `counter reset all confirm`, `session reset`. Buckets accept case-insensitively. Quote instance names with spaces.

## Persistence

Settings are stored via AceDB-3.0 in account-wide scope (`ToxFilterDB`). A schema-version migration framework is in place; future sprints add migrations as needed. If the SavedVariables file is corrupted, the addon resets to defaults and prints a single line to chat — no silent data loss.

## Install (dev)

This is pre-release; there's no public distribution yet. From the project root:

```
./scripts/build-rules.sh   # regenerate addon/RuleData.lua from sensitive/
./scripts/deploy.sh        # rsync addon/ to the WoW AddOns folder
```

Then `/reload` in-game.

## Session buffer (Sprint 4a)

Counters (per-encounter, per-dungeon, per-session) are aggregated and permanent — they survive retention pruning. Windowed events (positive moments, flagged events, activity log) are pruned on addon load using `/tox retention` (default 30 days). Pinned moments live separately and are never pruned. All chat content stored to the buffer is run through a name-context PII scrubber first; Sprint 6 will audit comprehensively.

## What it does not do

The addon never sends chat, never simulates input, never modifies what other players see, never makes network requests, and never stores or transmits player names or any other identifying info. All output is local to this user's chat frame.
