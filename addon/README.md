# Mind Soothe

World of Warcraft addon that filters incoming group/raid/instance/BG chat for the installing user only. Pre-release.

## Status

Build 1 Sprint 5. Adds tactical role-callout prioritization on top of the Sprint 4 family (4a affirmative data + 4b visual UI + three rounds of post-verification fixes). When a message contains a tactical callout addressed to the user's effective role, the line gets a warm-amber tint and a subtle audio cue plays. Opt-in via `/mind callout on`; off by default. Callouts are out-of-combat-only: during boss encounters and Mythic+ pulls the game restricts addon code execution and delivers incoming chat as a protected value addons cannot read, so no addon can inspect chat during a fight. Callouts (and the rest of chat filtering) resume the moment the pull ends.

## What it does today

The addon hooks incoming chat in PARTY, RAID, INSTANCE_CHAT, BATTLEGROUND, and (opt-in) WHISPER channels. Each message is tokenized, normalized (lowercase, punctuation stripped, repetition collapsed, leetspeak normalized), hashed, and looked up in a static rule table. The classifier identifies attack-context tokens (role-noun + negative modifier, you-pronoun + negative modifier) and tactical-content tokens (mechanic and direction words), so the rewrite preserves tactical meaning while dropping the hostile scaffold. User blacklist entries surface as `general_hostility` rule hits; whitelist entries suppress rule matching for that token.

Four handling modes per category, user-overridable via `/mind handle`:

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

## Limitations

The game does not run addon chat filters during boss combat, and the chat message text it delivers to addon code in combat is a protected value that addons cannot read. Any feature that needs to inspect chat during a boss fight is therefore impossible — for every addon, not just this one. Two features are scoped by this:

- **Role-aware callouts are out-of-combat only.** They tint chat and play their cue outside the combat window; during a boss fight they do not fire. In-combat tactical information is instead carried by the pre-pull boss-tactic reminders, which use a different delivery path (fired at encounter start, drawn to the RaidWarning area) that does work in combat.
- **The combat silent-drop toggle (`/mind combat`) currently has no effect.** It was built to silently drop pure hostility (slurs, harm) during the combat pause, but the same restriction prevents it from running there, and it is not wired into the out-of-combat path. Out of combat, hostility is handled by the normal category handling (edit or delete with a visible tag, per `/mind handle`). The toggle is left in place (default on) for a possible future out-of-combat home.

## Whisper filtering — default OFF

`CHAT_MSG_WHISPER` is hooked but the whisper channel toggle defaults to `off`. Whispers are private 1:1 messages and the user's expectation is privacy. Turning whisper filtering on is the user opting into filtering their private conversations, which is their right but should be a deliberate choice. Outgoing whispers (`CHAT_MSG_WHISPER_INFORM`) are never hooked — text the user typed is never filtered.

(Known limitation: a one-line privacy note was intended to print the first time whisper filtering is enabled; it does not currently print. Enabling whisper filtering is still a deliberate, user-initiated action.)

## Slash commands

Run `/mind help` for the grouped summary or `/mind help <command>` for details on a specific command.

**Filtering:**
- `/mind on` / `/mind off` — master toggle.
- `/mind status` — Active, Disabled, or Paused (combat window). Reports a soft-disabled state when every category is set to `pass`.

**Channels:**
- `/mind channel <name> on|off` — toggle one of `raid`, `instance`, `battleground`, `whisper`. `party` is accepted as an input alias for `instance` (WoW retail folds /p into instance chat).
- `/mind channel list` — show all channel states. The instance row is annotated `(also: party)`.

**Category handling:**
- `/mind handle <category> <pass|edit|del|silent>` — override default handling.
- `/mind handle list` — show current map.
- Categories: `identity_attack`, `slur`, `role_attack`, `harassment`, `harm_invocation`, `general_hostility`.

**Role:**
- `/mind role <auto|tank|healer|dps>` — set or override role. `auto` uses `GetSpecializationRole()`. Consumed by Sprint 4a positive capture (`thanks tank` is direct-to-user when role matches) and Sprint 5 callout prioritization.

**User lists:**
- `/mind blacklist add|remove|list <word>` — user-added words. Hits route to `edit` handling regardless of category default — surgical rewrite is the respectful default for personally-flagged words.
- `/mind whitelist add|remove|list <word>` — exempt a word from rule-engine matching.
- Both lists are stored hashed (FNV-1a); the entry's normalized plaintext is kept alongside the hash for `list` output.

**Surface (Sprint 4a / 4b):**
- `/mind lift` — print the most recent positive moment captured. Works during combat-pause windows; user-invoked surfacing is independent of live filtering.
- `/mind positive` — print the 10 most recent positive moments.
- `/mind positive ui` — toggle the in-line highlight (or pass `on`/`off` to set explicitly). Captured positive moments display with a subtle green tint when on. Default off; opt-in. Pause windows suppress the tint regardless.
- `/mind session` — current play-session detail (this session only: start time, encounters, deaths, thanks). For lifetime aggregates across all sessions and instances, use `/mind stats`.

**Stats (Sprint 4a + fix):**
- `/mind stats` — lifetime aggregate across all instances and difficulty buckets. (For the current play session only, use `/mind session`.)
- `/mind stats <instance>` — per-difficulty breakdown (substring match on instance name). Each bucket prints one row: completions, wipes, wipe rate, deaths.
- `/mind stats threshold <0-100>` — wipe-rate threshold for live surfacing (default 30).
- `/mind stats surface on|off` — toggle live surfacing of encounter/dungeon stats (default on).
- `/mind week` — last 7 days summary.

Counters are scoped to dungeons and raids only — battleground, arena, scenario, and open-world deaths aren't tracked. Each (instance, difficulty bucket) pair counts independently. Buckets: `normal`, `heroic`, `mythic`, plus M+ tiers `M0`, `M2-5`, `M6-10`, `M10+` locked at the start of a keystone run.

Live surfacing is asymmetric: a stat is shown only when reassuring (wipe rate ≤ threshold for that specific bucket) or when it's the first attempt. Above-threshold stats are suppressed silently.

**Pinned (Sprint 4a):**
- `/mind star <id>` — pin a positive moment by its `pm_NNN` id. Pinned moments survive retention pruning. Cap 100; oldest unpins on overflow.
- `/mind unstar <id>` — unpin.
- `/mind starred` — list pinned moments chronologically.

**Ritual (Sprint 4a):**
- `/mind check` — start the grounding ritual.
- `/mind check add <item>` / `/mind check remove <item>` / `/mind check list` — manage items. Default list is empty; no suggested items.
- `/mind check y` / `/mind check n` — answer the current item.
- `/mind check cancel` — abort an in-flight ritual.

**Box breathing (Sprint 4b):**
- `/mind breathe` — run an animated box-breathing exercise. Four phases per cycle (inhale / hold / exhale / hold), each `count` seconds. Default 4 cycles × 4 seconds = ~64 seconds. The frame shows the current phase, seconds remaining, and a `Cycle N of M` indicator.
- `/mind breathe cycles <1-20>` — cycle count.
- `/mind breathe count <1-20>` — seconds per phase.
- `/mind breathe position <x> <y>` — frame offset from screen center; `reset` recenters. The frame is drag-to-move; position persists.
- Esc closes the frame mid-cycle. Entering combat (`PLAYER_REGEN_DISABLED`) closes the frame silently — same clean-exit behaviour as Esc, no completion message. Invoking `/mind breathe` while already in combat refuses to start and prints `Cannot start breathing during combat.`

**Callout (Sprint 5):**
- `/mind callout` — print the current state of all three callout settings.
- `/mind callout on|off` — master toggle for the entire feature. Off by default; opt-in.
- `/mind callout ui on|off` — visual sub-toggle. When a message contains a tactical callout addressed to your effective role, the chat line is wrapped in a warm-amber color tint.
- `/mind callout sound on|off` — audio sub-toggle. Plays a subtle UI cue at the same moment. The two sub-toggles are independent for users in voice chat who want one but not the other.
- `/mind callout sound set <name> | list | preview <name>` (Sprint 7a) — choose among a few built-in cues. `list` shows the choices, `preview` plays one once, `set` selects it (and previews it). Default is the low ready-check cue (`readycheck2`, "Ready check, low").
- Sub-toggles persist independently of the master across sessions, so re-enabling the master after sub-toggles were turned off may produce no visible/audible callouts. `/mind callout` shows current state for all three.
- Callouts are out-of-combat-only. During the combat pause the game both stops invoking chat filters and delivers chat text as a protected value, so the addon cannot inspect chat mid-fight; callouts resume when the pull ends. Sprint 4b's passive positive-moment highlight likewise pauses during combat.
- Co-occurrence: a message that's both a positive moment and a callout for your role shows the callout amber tint (not the positive green). The moment is still captured to buffer.

**Sprint 7a additions:**
- `/mind combat on|off` — combat silent-drop toggle (default on, but currently has no effect). It was intended to silently drop high-confidence pure hostility (slurs, harm) during the combat pause, but the game does not run chat filters in combat (see Limitations), so nothing is dropped. The toggle is kept for a possible future out-of-combat home.
- Typo tolerance: the positive-capture and callout keyword matching tolerates a single-character typo ("thansk tank" still registers). Applies only to those keyword sets — never to the hostility classifier, rule engine, blacklist, or whitelist. Short words and role names stay exact-match-only.
- Emote capture: `/thanks`, `/cheer`, `/salute` and similar emotes aimed at you are captured as positive moments, marked `(emote)` in `/mind positive`. The emote must be directed at you — untargeted emotes (sent to the room with no target) are ignored. Respects the Uplifter category like typed praise. **Limitation: emote detection is English-client (enUS) only** — it keys on English emote wording, so other locales will not capture emotes. A future locale pass would address this.

**Ready (Sprint 4b):**
- `/mind ready` — chain grounding → breathing → lift in your configured order. Each step's natural completion advances the chain. If invoked during combat, the breathing step is skipped (with a message) and the chain proceeds.
- `/mind ready list` — show current chain.
- `/mind ready cancel` — master abort, regardless of which step is currently running.
- `/mind check cancel` or Esc on the breathing frame also aborts the chain.
- `/mind ready include <grounding|breathing|lift> on|off` — toggle a step's inclusion.
- `/mind ready order <step> <step> <step>` — reorder.

**Buffer (Sprint 4a):**
- `/mind retention <days>` — set windowed-event retention (7-365). Default 30. Pinned moments are exempt.

**Inspect:**
- `/mind version`, `/mind rules`, `/mind list`, `/mind test <msg>`, `/mind classify <msg>`, `/mind rewrite <msg>`.

**Developer (hidden):**
- `/mind debug` — counter manipulation tool, gated behind `db.debug_enabled` (default off). Hidden from `/mind help`. Lets a developer seed (instance, difficulty) counter values directly so verification of asymmetric surfacing doesn't require building a real wipe history. Subcommands: `enable | disable`, `version`, `counter <instance> <bucket> <field> <value>`, `counter list [<instance>]`, `counter reset <instance> <bucket>`, `counter reset all confirm`, `session reset`. Buckets accept case-insensitively. Quote instance names with spaces.

## Persistence

Settings are stored via AceDB-3.0 in account-wide scope (`MindSootheDB`). A schema-version migration framework is in place; future sprints add migrations as needed. If the SavedVariables file is corrupted, the addon resets to defaults and prints a single line to chat — no silent data loss.

## Install (dev)

This is pre-release; there's no public distribution yet. From the project root:

```
./scripts/build-rules.sh   # regenerate addon/RuleData.lua from sensitive/
./scripts/deploy.sh        # ship build  -> AddOns/MindSoothe/
./scripts/deploy.sh dev    # dev twin    -> AddOns/MindDev/  (local-only, isolated data)
```

The dev twin (`Mind Dev`, slash `/mdev`, SavedVariables `MindDevDB`) installs alongside the ship build with a fully distinct identity, so the two never collide and keep separate data. It is local-only — never committed, never packaged.

Then `/reload` in-game.

## Session buffer (Sprint 4a)

Counters (per-encounter, per-dungeon, per-session) are aggregated and permanent — they survive retention pruning. Windowed events (positive moments, flagged events, activity log) are pruned on addon load using `/mind retention` (default 30 days). Pinned moments live separately and are never pruned. All chat content stored to the buffer is run through a name-context PII scrubber first; Sprint 6 will audit comprehensively.

## What it does not do

The addon never sends chat, never simulates input, never modifies what other players see, never makes network requests, and never stores or transmits player names or any other identifying info. All output is local to this user's chat frame.

## License

Mind Soothe is licensed under the GNU General Public License v3.0 — see [LICENSE](../LICENSE).

The embedded Ace3 libraries under `addon/Libs/` are third-party, distributed under their own (permissive) licenses, and are not relicensed under GPLv3.
