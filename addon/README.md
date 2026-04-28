# ToxFilter

Working name. Pre-release. World of Warcraft addon that filters incoming group/raid/instance/BG chat for the installing user only.

## Status

Build 0 Sprint 1. Rule engine in place, running on placeholder wordlists. Architecture is validated; real wordlists are populated off-platform from sources the developer selects.

## What it does today

The addon hooks incoming chat in PARTY, RAID, INSTANCE_CHAT, and BATTLEGROUND channels (and their leader/warning variants). Each message is tokenized, normalized (lowercase, punctuation stripped, repetition collapsed, leetspeak normalized), hashed, and looked up in a static rule table. A matching token routes the message to one of four handling modes:

- **Pass** — message displays unchanged.
- **Edit** — `[ToxEdit] ` is prefixed and every rule-hit token is removed from the body.
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

## Slash commands

- `/tox status` — shows `Active` or `Paused — combat window`
- `/tox version` — shows the addon version
- `/tox rules` — shows rule-data version, generation timestamp, and rule counts per category
- `/tox test <message>` — runs `<message>` through the rule engine and prints what handling it would receive, without rendering it. Format: `[ToxFilter] Test result: '<input>' → <handling> (<category>, +N other hits)` if multiple rules hit.

## Install (dev)

This is pre-release; there's no public distribution yet. From the project root:

```
./scripts/build-rules.sh   # regenerate addon/RuleData.lua from sensitive/
./scripts/deploy.sh        # rsync addon/ to the WoW AddOns folder
```

Then `/reload` in-game.

## What it does not do

The addon never sends chat, never simulates input, never modifies what other players see, never makes network requests, and never stores or transmits player names or any other identifying info. All output is local to this user's chat frame.
