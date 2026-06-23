# Mind Soothe

A World of Warcraft addon that filters incoming group, raid, instance, and
battleground chat for the installing player only. The visible mechanism is text
filtering; the goal is reducing role anxiety for players in high-pressure roles —
tanks, healers, and mechanics-heavy specs. The framing is role-confidence
support, not censorship, and it shapes what the addon filters, what it preserves,
and how it words everything it shows you.

Available on [CurseForge](https://www.curseforge.com/wow/addons/mindsoothe) and
Wago — search "Mind Soothe". Current release: **v1.0.0**.

## What it does

Incoming chat is tokenized, normalized, and classified against a static rule
table entirely on your machine — no network calls, no LLM, no machine learning on
the message path. Each message is handled per category, with the mode
configurable per category:

- **Pass** — shown unchanged.
- **Edit** — the hostile span is removed and the line is tagged `[ToxEdit]`;
  tactical content is preserved.
- **Delete** — the line is replaced with a short `[ToxDel: <Category>]` tag.
- **Silent** — the line is not shown.

Around the filter sit a set of role-confidence features:

- **Positive-moment capture** — thanks and praise aimed at you (including
  directed `/thank`, `/cheer`, `/salute` emotes) are recorded and can be
  resurfaced later, with an optional in-line highlight.
- **Out-of-combat role callouts** — a message carrying a tactical callout for
  your role gets a tint and a selectable audio cue.
- **Pre-pull tactic reminders and per-key pre-dungeon warnings** — short,
  role-filtered reminders drawn to the raid-warning area at encounter and
  Mythic+ start, before the combat lockdown.
- **Stats** — session and lifetime completion/wipe/death counts per dungeon and
  difficulty, surfaced only when reassuring.
- **Grounding and box-breathing rituals** — `/mind check`, `/mind breathe`, and
  a `/mind ready` chain that runs them in your chosen order.
- **Typo tolerance** on the positive-capture and callout keywords (never on the
  hostility classifier), category master toggles, and a Settings panel.

Run `/mind help` in-game for the full command list. The detailed reference lives
in [`addon/README.md`](addon/README.md).

## Privacy and safety

These are foundational commitments, not options:

- **Local and one-directional.** All output is to your own chat frame. Nothing is
  ever sent to your group, broadcast, or transmitted to a server. The addon never
  sends chat, never simulates input, and never triggers a reload.
- **No PII.** Player, character, guild, and realm names are stripped from anything
  stored.
- **Deterministic.** The live message path is pure Lua against a static rule
  table — no remote API, no ML, no network requests.

## Install

Install through the CurseForge or Wago app, or download the release from the
[CurseForge page](https://www.curseforge.com/wow/addons/mindsoothe) and unzip it
into `Interface/AddOns/`. Then `/reload` or restart the client and run
`/mind help`.

## Known issues

- The one-shot whisper privacy note does not print the first time whisper
  filtering is enabled. Enabling it is still a deliberate, user-initiated action.
- The Settings panel does not expose the event-retention control; set it with
  `/mind retention <days>`.
- Edit-mode rewrite can occasionally over-strip a neutral word at the edge of a
  hostile span. Affected lines still display with the `[ToxEdit]` tag — the
  message is never dropped silently.

## Building from source

For development, not normal use. From the project root:

```
./scripts/build-rules.sh   # regenerate addon/RuleData.lua from sensitive/
./scripts/deploy.sh        # ship build -> AddOns/MindSoothe/
./scripts/deploy.sh dev    # local-only dev twin -> AddOns/MindDev/  (/mdev)
./scripts/run-gauntlet.sh  # luacheck + corpus + tonal grep + pipe audit
```

Releases are produced by the GitHub Actions pipeline
(`.github/workflows/release.yml`, BigWigs packager) on tag push.

## License

Mind Soothe is licensed under the GNU General Public License v3.0 — see
[LICENSE](LICENSE).

The embedded Ace3 libraries under `addon/Libs/` are third-party, distributed
under their own (permissive) licenses, and are not relicensed under GPLv3.
