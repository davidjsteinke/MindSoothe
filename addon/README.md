# ToxFilter

Working name. Pre-release. World of Warcraft addon that filters incoming group/raid/instance/BG chat for the installing user only.

## Status

Build 1 Sprint 3. Persistence (AceDB-3.0, account-wide), full slash-command suite, and an opt-in whisper hook now sit on top of the Build 0 rule engine + classifier + surgical rewrite. Real wordlists are populated off-platform.

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
- `/tox channel <name> on|off` — toggle one of `party`, `raid`, `instance`, `battleground`, `whisper`.
- `/tox channel list` — show all channel states.

**Category handling:**
- `/tox handle <category> <pass|edit|del|silent>` — override default handling.
- `/tox handle list` — show current map.
- Categories: `identity_attack`, `slur`, `role_attack`, `harassment`, `harm_invocation`, `general_hostility`.

**Role:**
- `/tox role <auto|tank|healer|dps>` — set or override role. `auto` uses `GetSpecializationRole()`. The role setting is persisted now; role-aware behaviors arrive in Sprint 5.

**User lists:**
- `/tox blacklist add|remove|list <word>` — user-added words match as `general_hostility` severity 5.
- `/tox whitelist add|remove|list <word>` — exempt a word from rule-engine matching.
- Both lists are stored hashed (FNV-1a); the entry's normalized plaintext is kept alongside the hash for `list` output.

**Inspect:**
- `/tox version`, `/tox rules`, `/tox list`, `/tox test <msg>`, `/tox classify <msg>`, `/tox rewrite <msg>`.

## Persistence

Settings are stored via AceDB-3.0 in account-wide scope (`ToxFilterDB`). A schema-version migration framework is in place; future sprints add migrations as needed. If the SavedVariables file is corrupted, the addon resets to defaults and prints a single line to chat — no silent data loss.

## Install (dev)

This is pre-release; there's no public distribution yet. From the project root:

```
./scripts/build-rules.sh   # regenerate addon/RuleData.lua from sensitive/
./scripts/deploy.sh        # rsync addon/ to the WoW AddOns folder
```

Then `/reload` in-game.

## What it does not do

The addon never sends chat, never simulates input, never modifies what other players see, never makes network requests, and never stores or transmits player names or any other identifying info. All output is local to this user's chat frame.
