# Changelog

All notable changes to Mind Soothe are recorded here. Released versions are named
for the git tag, which the packager stamps into the TOC `## Version:` at build
time; the two are kept in sync.

## [1.0.0] — 2026-06-22

First public release. Mind Soothe is live on CurseForge and Wago, built from the
git tag by the automated GitHub Actions release pipeline (BigWigs packager). No
schema, feature, classifier, or rule change from the launch-prep work below;
this tag marks the launch of that work as v1.0.0.

- Published to CurseForge, Wago, and GitHub Releases on tag push
  (`.github/workflows/release.yml`).
- TOC `## Version:` set to `1.0.0`; schema v11.

## [0.8.0-sprint8] — 2026-06-22

Launch preparation: the shipping rename, dual-build tooling, and packaging. No
schema change (still v11); no feature, classifier, or rule changes.

- Renamed the shipping identity from the working name to **Mind Soothe**: folder
  `MindSoothe/`, slash `/mind`, SavedVariables `MindSootheDB`, chat prefix
  `[Mind Soothe]`, options-panel and Blizzard-menu title. The two internal
  feature categories (ToxFilter / Uplifter) keep their names.
- Centralized the identity surface into `addon/Const.lua` (addon name, display
  name, slash, SavedVariables, chat prefix, debug prefix, frame-name stem) so it
  derives from one place. The global breathing-frame name now derives per build.
- Single-sourced the version string: the TOC `## Version:` is the only source;
  Lua reads it via `C_AddOns.GetAddOnMetadata`. The hardcoded Lua version
  constant is removed.
- Dual-build deploy: `./scripts/deploy.sh` ships Mind Soothe verbatim;
  `./scripts/deploy.sh dev` stamps a local-only **Mind Dev** twin (`/mdev`,
  `MindDevDB`, folder `MindDev/`) that coexists in one client with no collision.
  The dev stamp renames both the staged `.toc` and the main `.lua` to match the
  folder, so the stamped TOC's source-file reference resolves and the dev build
  registers its slash. Both builds verified in-game: separate AddOns entries,
  isolated data, each responding only to its own slash.
- Packaging: GPLv3 `LICENSE`, `.pkgmeta` (excludes dev tooling), this changelog,
  and `scripts/run-gauntlet.sh` (luacheck + corpus + tonal grep + pipe audit in
  one command).
- The SavedVariables rename is a fresh start; there is no migration from the old
  database.

## [0.7.0-sprint7b]

Bugfix batch on top of 7a (no schema change):

- Name-escape capture fix in positive-moment handling.
- Record narrowing so stored events keep only the intended fields.
- Combat and callout polish folding in the post-N12 out-of-combat scoping.

## [0.7.0-sprint7a] — Sprint 7a

- Combat silent-drop carve-out for pure hostility (slur / harm only, with a
  purity guard), `/mind combat`, default on. Inert after the N12 finding —
  in-combat chat is uninspectable — and retained for a possible future
  out-of-combat home.
- Selectable callout sound: `/mind callout sound set <name> | list | preview`.
- Damerau distance-1 typo tolerance, scoped to the positive-capture and callout
  keyword sets only — never the classifier, rule engine, blacklist, or
  whitelist. Length-5 floor; role targets stay exact-only.
- Text-emote positive capture for emotes aimed at the user, marked `(emote)`
  in `/mind positive`. enUS-only by construction.
- Schema v11.

## [0.6.0-sprint6b] — Sprint 6 / 6b

- PII scrub audit and remediation: live-path name scrubbing broadened from
  narrow post-thanks matching to known-name matching (message sender, the
  installing user's current character, the alt roster), precision over recall.
- AceConfig options panel (`/mind config`) as a view over existing db state —
  no parallel store — plus `/mind state`, a one-block readout of every toggle
  layer.
- Schema v10.
