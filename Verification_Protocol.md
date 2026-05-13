# ToxFilter Verification Protocol

Manual in-game verification checklist run after every fix sprint. Items are numbered by topic prefix:

- **A** — addon loadup / lifecycle
- **E** — escape characters / text rendering
- **F** — filtering, channels, handling, lists, role
- **H** — history, counters, positive moments, debug tool
- **I** — interactive UI (breathing, ready, ritual)

Each item has a one-line setup and the exact command(s) to run. Commands are in fenced blocks so they can be copy-pasted directly from the rendered doc into the chat bar.

---

## A — Addon loadup

### A1. Clean luacheck
From the project root:

```
luacheck addon/
```

Expect: `0 warnings / 0 errors`.

### A4. Deploy + load
Deploy to the Windows AddOns folder, then `/reload` in-game:

```
./scripts/deploy.sh
```

```
/reload
```

Expect: `[ToxFilter] Loaded — version 0.0.8-sprint4-fix2` in chat. No load-time errors. No migration noise on a fresh install; existing testers see the v5 migration line.

### A5. Status / version
```
/tox status
```

```
/tox version
```

Expect: status reports `Active`; version matches the TOC and the chat banner.

### A6. Help renders correctly
```
/tox help
```

```
/tox help ready
```

```
/tox help breathe
```

Expect: no garbled `<addemove>`-style output. Pipe characters render correctly. Each detail page mentions the relevant subcommands.

---

## E — Escape characters / text rendering

### E2. ASCII arrows in /tox test, classify, rewrite
WoW chat font lacks `→`. Confirm ASCII `->`:

```
/tox test ToxFilterTest:Edit hi
```

```
/tox classify good job einstein
```

```
/tox rewrite ToxFilterTest:Del whatever
```

Expect: every output line uses `->` (no replacement-glyph boxes).

---

## F — Filtering, channels, handling, lists

### F3-F5. Party/instance channel alias
WoW retail folds `/p` into instance chat. The slash UI accepts `party` as an alias for `instance`:

```
/tox channel party off
```

```
/tox channel list
```

Expect: instance row shows `off` and is annotated `(also: party)`. The header reads `Channels (master: enabled):`.

```
/tox channel party on
```

Expect: confirmation message; instance row toggles back to `on`.

### F9. Handle default interpolation
```
/tox handle role_attack default
```

Expect: `Category 'role_attack' reset to default (edit).` (resolved value shown in parens).

### F14. Blacklist routes to edit
```
/tox blacklist add coolword
```

Then in chat: `coolword bothered me earlier`. Expect: `[ToxEdit] bothered me earlier` (handling=edit, not del). The category is still `general_hostility` internally; only the handling differs.

```
/tox blacklist remove coolword
```

### F18. Whisper privacy note (first enable)
Fresh state required (the v5 migration re-arms existing testers). Confirm:

```
/tox channel whisper off
```

```
/tox channel whisper on
```

Expect: the privacy note prints on the second command:

```
[ToxFilter] Whisper filtering enabled. Note: this reads private messages
sent to you. Filtered output is shown only to you. Disable with /tox
channel whisper off.
```

### F18b. Whisper privacy note does NOT print on subsequent enables
```
/tox channel whisper off
```

```
/tox channel whisper on
```

Expect: the second `on` prints `Channel 'whisper' enabled.` only. No privacy note.

---

## H — History, counters, positive moments, debug tool

### H1. Per-bucket stats display
```
/tox stats
```

Expect: lifetime aggregate (lifetime thanks, instance deaths, instance attempts, instance count, threshold/surface settings). One-line summary per metric. No per-bucket rows in the no-arg form.

```
/tox stats <instance-substring>
```

Expect: per-bucket rows for matching instances, formatted as `bucket: N completed, M wiped (X% wipe), D deaths`. Bucket order is whatever insertion order produced; per-instance sorting is alphabetical.

### H1b. /tox stats vs /tox session distinction
```
/tox stats
```

```
/tox stats current session
```

Expect: the second prints `No instance named 'current session' found. Use /tox session for current-session stats.`

```
/tox session
```

Expect: current-session detail (started timestamp, encounters won/wiped, deaths, thanks).

### H8. Positive moment captured on any channel that filters are observing
With instance filtering on (default) and whisper off (default), have a teammate (or self in a party) say:

```
ty <your-character-name>
```

…in `/p` or `/i`. Expect: the message is captured. Confirm via:

```
/tox lift
```

The most recent positive moment should match.

### H8b. Whisper privacy carve-out
With whisper filtering OFF, have someone whisper you `gg` or `ty <name>`. Expect: NO capture. Confirm `/tox lift` shows the previous moment, not the whisper.

Then enable whisper filtering, repeat:

```
/tox channel whisper on
```

Expect: privacy note (if not previously shown), then a whisper of `gg` IS captured. Confirm via `/tox lift`.

### H22. Debug counter round-trip (set semantics)
Seed a counter via the developer tool. The command is a **set**, not an add — three invocations with the same value leave the counter at that value, not at three times the value. This is the round-3 fix3 regression check; if H22 shows accumulation, the deploy is stale.

```
/tox debug enable
```

```
/tox debug counter reset all confirm
```

```
/tox debug counter "Halls of Atonement" heroic deaths 10
```

```
/tox debug counter "Halls of Atonement" heroic deaths 10
```

```
/tox debug counter "Halls of Atonement" heroic deaths 10
```

```
/tox debug counter list "Halls of Atonement"
```

Expect: `deaths=10` (not 30). Repeat for `completions` and `wipes` if desired. Then a roundtrip to `/tox stats`:

```
/tox debug counter "Halls of Atonement" heroic completions 5
```

```
/tox debug counter "Halls of Atonement" heroic wipes 1
```

```
/tox stats Halls
```

Expect: the seeded values appear in the heroic row of the Halls of Atonement block.

**NOTE (Hypothesis B, fix3).** The reassuring `/tox stats` surfacing that fires on encounter start is wired to `ENCOUNTER_START` and `CHALLENGE_MODE_START`. Zoning into a dungeon does **not** trigger surfacing on its own — the player must pull a boss or activate the keystone for the message to print. When testing surfacing, seed counters, zone in, and **pull**.

**NOTE (Hypothesis C, fix3).** The instance name the surfacing logic uses comes from `GetInstanceInfo()` and may differ from the user's seed key by leading article or expansion prefix. With `/tox debug enable` on, encounter start prints `[ToxFilter Debug] Encounter start in: '<name>' bucket '<bucket>'` — paste the exact `<name>` back into `/tox debug counter` so the seed matches the API string.

**Optional alias.** `/tox debug count ...` works identically to `/tox debug counter ...`.

### H23. Debug command gating
```
/tox debug disable
```

```
/tox debug counter "Halls of Atonement" heroic completions 99
```

Expect: the counter set is rejected with `Unknown command 'debug'. Try /tox help.` Re-enable to continue:

```
/tox debug enable
```

### H24. Debug counter reset
```
/tox debug counter reset all confirm
```

Expect: counters cleared.

```
/tox stats
```

Expect: empty-state lifetime aggregate (`no instance activity recorded`).

```
/tox debug disable
```

### H25. Counter-increment scope check (fix3 diagnostic)
Verifies the H1 instance-scope filter via the round-3 debug print. Open-world deaths must not bump the counter.

```
/tox debug enable
```

```
/tox debug counter reset all confirm
```

Travel to an open-world zone (e.g. Eversong Woods). Do **not** enter any instance. Die intentionally (jump off something tall).

Expect: no `[ToxFilter Debug] Counter increment: ...` line in chat. The death is silently dropped by the scope filter.

```
/tox debug counter list
```

Expect: `No instance counters recorded.` Now enter a 5-player dungeon or raid and die there.

Expect: `[ToxFilter Debug] Counter increment: <instance> / <bucket> / deaths` prints in chat. Confirms instance-only scope is intact.

```
/tox debug disable
```

---

## I — Interactive UI

### I2. /tox positive ui toggle
Three runs of the no-arg form should alternate state:

```
/tox positive ui
```

```
/tox positive ui
```

```
/tox positive ui
```

Expect: `enabled` → `disabled` → `enabled`. Explicit on/off still works:

```
/tox positive ui off
```

```
/tox positive ui on
```

### I7. Cycle indicator on breathing
```
/tox breathe cycles 3
```

```
/tox breathe count 2
```

```
/tox breathe
```

Expect: the frame shows `Inhale  N` (or current phase) on the upper label and `Cycle X of 3` below it. The cycle number advances at the start of each new cycle.

### I9. Box breathing refuses to start in combat
Engage a target dummy or pull a trash mob. While `InCombatLockdown` is true:

```
/tox breathe
```

Expect: `[ToxFilter] Cannot start breathing during combat.` No frame appears. Drop combat, retry — frame opens normally.

### I12. /tox check y/n inside /tox ready
Configure at least one grounding item:

```
/tox check add Take a breath
```

```
/tox ready
```

Expect: grounding prompt for the first item. Respond:

```
/tox check y
```

Expect: ritual advances (next item or finishes). After grounding completes, breathing step starts (out of combat) or skips (in combat). Lift step prints last positive moment.

### I12b. Standalone /tox check still works
```
/tox check
```

```
/tox check y
```

Expect: ritual works the same standalone (no Ready chain) as inside Ready.

### I16. Cancellation paths
**`/tox check cancel` aborts grounding both standalone AND inside Ready chain:**

```
/tox check
```

```
/tox check cancel
```

Expect: `[ToxFilter] Grounding ritual cancelled.`

```
/tox ready
```

(during grounding step:)

```
/tox check cancel
```

Expect: ritual cancelled, AND the chain aborts (no breathing step starts).

**`/tox ready cancel` master abort:**

```
/tox ready
```

(during any step:)

```
/tox ready cancel
```

Expect: `[ToxFilter] Ready chain cancelled.` Whatever step was active is closed (grounding ritual cleared, breathing frame hidden).

```
/tox ready cancel
```

Expect: `[ToxFilter] No ready chain in progress.`

### I16b. Esc on breathing frame
With breathing running standalone, press Esc. Frame closes silently — no completion print. Re-run; same behaviour mid-cycle.

With breathing running inside `/tox ready`, press Esc. Frame closes; chain aborts (no lift step runs).

---

## Regression checklist (every sprint)

Re-run after any change to chatFilter, RuleEngine, Database, Commands, or Buffer:

- A1 (luacheck), A4 (deploy + reload), A5 (status/version), A6 (help)
- E2 (ASCII arrows)
- F3-F5 (channel alias), F9 (handle default), F14 (blacklist edit)
- H1 (per-bucket display), H8 (capture across channels), H22-H25 (debug round-trip, set semantics, scope diagnostic)
- I7 (cycle indicator), I9 (combat lockdown), I12 (check inside ready), I16 (cancellation)

Plus: tonal grep (`!|great|oops|sorry`) and pipe-doubling audit on any file added to the standard grep set.
