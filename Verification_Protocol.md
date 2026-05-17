# ToxFilter — Verification Protocol
# Current addon version: 0.2.1-sprint5b-polish
# Last updated: Sprint 5b polish verification

This is the cumulative test protocol. When in-game verification is needed, steps are
referenced by section and number (e.g., "run A1-A7, F18, H22-H24").

CONVENTIONS:
- Steps are globally numbered and stable. New sprints append steps at the end.
- Each step has expected behavior. Failures: paste step number and what you saw.
- Non-game steps (A section) run from ~/projects/toxfilter in WSL.
- Slash commands are in code blocks for copy/paste.

IMPORTANT: Run Phase 0 before any verification session to ensure baseline state.

---

## PHASE 0 — Baseline state reset (run before any verification session)

```
/tox handle all default
```
```
/tox channel raid on
```
```
/tox channel instance on
```
```
/tox channel battleground on
```
```
/tox channel whisper off
```
```
/tox callout off
```
```
/tox callout ui on
```
```
/tox callout sound on
```
```
/tox reminders off
```
If debug mode was enabled in a prior session:
```
/tox debug disable
```
Expected: no errors. `/tox list` should show all categories at default, channels at
the states above, master on, state Active. `/tox callout` should report master off
with ui and sound on. `/tox reminders` should report master off.

---

## SECTION A — Build/Lint/Harness (run from ~/projects/toxfilter)

### A1. luacheck (all sprints)
```bash
luacheck addon/
```
Expected: 0 warnings, 0 errors across all files.

### A2. Build script (Sprint 1+)
```bash
./scripts/build-rules.sh
```
Expected: "Generated RuleData.lua: N rules across M categories"
Currently: 136 rules across 5 active categories (slur, harassment, harm_invocation,
role_attack, general_hostility — identity_attack present but sparse).

### A3. Build script idempotency (Sprint 1+)
Run A2 twice, then:
```bash
git diff addon/RuleData.lua
```
Expected: empty diff.

### A4. Corpus harness (Sprint 2+)
```bash
./scripts/run-corpus.sh
```
Expected: 100% across all categories, 0 false positives, 39/39 rewrites.
Currently: 64 entries.

### A5. Tonal grep (Sprint 3+)
```bash
grep -rE '!|great|oops|sorry' addon/
```
Expected: only self-referential matches (pattern-data comments in
PositiveCapture.lua, Normalize.lua, Patterns.lua, Commands.lua grep doc comment,
and Ace3 Libs comments). Nothing in user-facing output strings.

### A6. Pipe-doubling audit (Sprint 3 fix-1+)
```bash
grep -nE 'print\([^)]*\|[^|]' addon/Commands.lua addon/ToxFilter.lua \
  addon/Database.lua addon/Buffer.lua addon/Stats.lua addon/Grounding.lua \
  addon/Ready.lua addon/Breathing.lua
```
Expected: empty result.
NOTE: addon/Highlight.lua is intentionally excluded — it uses WoW color codes
(|cFF66AA66 and |r) which are functional single-pipe escape sequences, not display
pipes. See CLAUDE.md for the pipe-doubling exception.

### A7. Deploy (all sprints)
```bash
./scripts/deploy.sh
```
Expected: rsync completes without errors. Files reach WoW AddOns folder.

---

## SECTION B — Load & Lifecycle (in-game)

### B1. Reload (all sprints)
```
/reload
```
Expected: "[ToxFilter] Loaded — version 0.2.1-sprint5b-polish" in chat. No Lua errors.

### B2. Version
```
/tox version
```
Expected: 0.2.1-sprint5b-polish

### B3. Bare /tox
```
/tox
```
Expected: short orientation help text.

### B4. Status
```
/tox status
```
Expected: "Active" (assuming Phase 0 was run).

### B5. Full help
```
/tox help
```
Expected: full grouped command list including Surface, Stats, Pinned, Ritual,
Buffer, Breathe, Ready groups.

---

## SECTION C — Four Handling Modes (in-game, /instance)

### C1. Pass-through fixture
```
ToxFilterTest:Pass hello
```
Expected: displays as "ToxFilterTest:Pass hello" — verbatim including the trigger
word. Pass-through means no modification at all. This is correct behavior.

### C2. Edit fixture
```
ToxFilterTest:Edit hey ok
```
Expected: "[ToxEdit] hey ok"

### C3. Del fixture
```
ToxFilterTest:Del whatever
```
Expected: "[ToxDel: TestCategory]"

### C4. Silent drop fixture
```
ToxFilterTest:Silent anything
```
Expected: nothing displays.

### C5. Empty-body edit edge case
```
ToxFilterTest:Edit
```
Expected: "[ToxEdit]" (bare tag, no body)

---

## SECTION D — Rule Engine + Classifier (in-game, /instance)

### D1. Placeholder slur edit
```
placeholder_slur_c whatever
```
Expected: "[ToxEdit] whatever"

### D2. Placeholder harm invocation deletion
```
placeholder_harm_b boss is dead
```
Expected: "[ToxDel: Harm Invocation]"

### D3. Leetspeak normalization
```
pl4ceh0lder_slur_c whatever
```
Expected: "[ToxEdit] whatever"

### D4. Repetition collapse
```
placeeeholder_slur_c whatever
```
Expected: "[ToxEdit] whatever"

### D5. Multi-hit aggressiveness
```
placeholder_slur_c placeholder_harm_b together
```
Expected: "[ToxDel: Harm Invocation]" (del beats edit)

### D6. Neutral token preserve (Sprint 2 fix)
```
okay placeholder_slur_c
```
Expected: "[ToxEdit] okay" (neutral token preserved outside attack span)

### D7. Role-attack with tactical content
```
move out of fire you trash tank
```
Expected: "[ToxEdit] move out of fire"

### D8. Sarcasm-only handling
```
thanks for the carry, hero
```
Expected: "[ToxEdit] thanks for the carry, hero" (sarcasm flagged, body preserved)

### D9. Pass-through with role noun, no modifier
```
good job tank
```
Expected: displays unchanged.

### D10. Pass-through with mild profanity in tactical context
```
fucking move out of fire
```
Expected: displays unchanged (tactical content; intensifier doesn't fire role-attack)

---

## SECTION E — Slash Inspection Commands

### E1. Rules output
```
/tox rules
```
Expected: rule version, generated timestamp, per-category counts, total entries.

### E2. Test command (fix: ASCII arrow)
```
/tox test placeholder_slur_c whatever
```
Expected: result uses ASCII arrow (-> or :) not a Unicode box character.
Example: "Test result: 'placeholder_slur_c whatever' -> edit (slur)"

### E3. Test fixture passes
```
/tox test ToxFilterTest:Pass hello
```
Expected: "Test result: 'ToxFilterTest:Pass hello' -> pass"

### E4. Classify
```
/tox classify move out of fire you trash tank
```
Expected: role_attack, attack span "you trash tank", tactical span "move out of fire"

### E5. Rewrite
```
/tox rewrite move out of fire you trash tank
```
Expected: "[ToxEdit] move out of fire"

---

## SECTION F — Persistence & Configuration

### F1. Master toggle off
```
/tox off
```
Expected: "[ToxFilter] Filtering disabled."
Send placeholder_slur_c test in /instance — passes through.

### F2. Master toggle on
```
/tox on
```
Expected: "[ToxFilter] Filtering enabled."
Same placeholder — filters.

### F3. Channel toggle — party alias (fix: party is alias for instance)
```
/tox channel party off
```
Expected: disables instance channel.
Send placeholder_slur_c test in /instance — passes through.

### F4. Channel toggle — canonical name
```
/tox channel instance on
```
Expected: re-enables. Same placeholder — filters again.

### F5. Channel list shows alias annotation (fix)
```
/tox channel list
```
Expected: "instance: on (also: party)" — canonical name with alias noted.

### F6. Role auto
```
/tox role auto
```
Expected: "Role set to auto-detect." No Lua error.

### F7. Role manual
```
/tox role tank
```
Expected: "Role set to 'tank'."

### F8. Handle override single
```
/tox handle role_attack del
```
Send "you trash tank" in /instance — displays as "[ToxDel: Role Attack]".

### F9. Handle restore default (fix: shows resolved default value)
```
/tox handle role_attack default
```
Expected: "Category 'role_attack' reset to default (edit)." — default value
interpolated so user knows what they got.

### F10. Handle silent (footgun warning)
```
/tox handle slur silent
```
Expected: confirmation plus one-line note about silent drop.

### F11. Handle list display
```
/tox handle list
```
Expected: per-category display with resolved value and (default) annotation.

### F12. Handle all default
```
/tox handle all default
```
Expected: single summary line. `/tox handle list` shows all six as (default).

### F13. Handle all silent (single note)
```
/tox handle all silent
```
Expected: single summary line plus silent-drop note once (not six times).

### F14. Blacklist add (fix: now routes to edit not del)
```
/tox blacklist add testword_unique
```
Send "testword_unique whatever" in /instance.
Expected: "[ToxEdit] whatever" — NOT [ToxDel].
(Blacklist hits route to edit since Sprint 4 fix.)

### F15. Blacklist remove
```
/tox blacklist remove testword_unique
```
Send same message — passes through unchanged.

### F16. Whitelist add
```
/tox whitelist add placeholder_slur_c
```
Send "placeholder_slur_c whatever" — passes through unchanged.

### F17. Whitelist remove
```
/tox whitelist remove placeholder_slur_c
```
Same message — filters again.

### F18. Whisper opt-in first time (fix: privacy note now prints)
```
/tox channel whisper on
```
Expected: privacy note prints. Text includes: "this reads private messages sent
to you" (or similar). Only prints on first enable ever, OR after a schema migration
reset (current state: v5 migration resets for testers).

### F18b. Whisper second enable — no repeat
```
/tox channel whisper off
/tox channel whisper on
```
Expected: privacy note does NOT print a second time.

### F19. Whisper filtering active (requires friend or alt)
Have a friend whisper "placeholder_slur_c test" — filters.

### F20. Whisper opt-out
```
/tox channel whisper off
```
Same whisper — passes through unchanged.

### F21. /tox list comprehensive view
```
/tox list
```
Expected: master toggle, per-channel states, category-handling map, role,
blacklist count, whitelist count. State should say "Active" with Phase 0 baseline.
If state says "soft-disabled (every category set to pass)" — run
`/tox handle all default` before continuing.

### F22. All-pass status detection
```
/tox handle all pass
/tox status
```
Expected: "soft-disabled (every category set to pass)" visible.
Reset after: `/tox handle all default`

---

## SECTION G — Combat-Period Pause

### G1. Encounter start pause
Enter a Mythic+ key or boss encounter.
Expected: "[ToxFilter] Filtering paused — combat window."

### G2. Pause status
During encounter:
```
/tox status
```
Expected: "Paused — combat window"

### G3. Pause-through fixtures
During encounter, send ToxFilterTest fixtures in /instance.
Expected: all pass through unchanged.

### G4. Encounter end resume
Complete or abandon the encounter.
Expected: "[ToxFilter] Filtering resumed." Then fixtures filter normally.

---

## SECTION H — Affirmative Features (Sprint 4a + fixes)

### H1. /tox stats lifetime aggregate
```
/tox stats
```
Expected: per-bucket breakdown (instance-only — no battleground or world deaths).
Should NOT show "current session" mode here.
If you see a "no-match" error, see H1b.

### H1b. /tox stats invalid argument error text (fix)
```
/tox stats current session
```
Expected: "No instance named 'current session' found. Use /tox session for
current-session stats." — NOT a generic unknown command.

### H2. /tox week
```
/tox week
```
Expected: this-week activity summary.

### H3. Positive moment capture — role (requires friend in /instance)
Have friend send "thanks tank" or "ty healer" in /instance.
```
/tox positive
```
Expected: the message appears in recent positive moments list.

### H3b. Positive moment capture — name (requires friend in /instance)
Have friend send "thanks <your-character-name>" or "ty <your-name>".
```
/tox positive
```
Expected: captured. (Sprint 4 fix2: -Server suffix stripped from UnitName so
connected-realm names match correctly.)
NOTE: As of verification session May 2026, "thanks <name>" not yet confirmed
captured. Retest after fix2 deploy.

### H4. /tox lift
```
/tox lift
```
Expected: surfaces most-recent positive moment, or "No recent positive moments
captured." if buffer is empty.

### H5. Pin a moment
```
/tox positive
```
Find a moment ID (e.g., pm_007).
```
/tox star pm_007
```
Expected: confirmation.

### H6. View pinned
```
/tox starred
```
Expected: chronological list including pinned moment.

### H7. Unpin
```
/tox unstar pm_007
/tox starred
```
Expected: list no longer contains it.

### H8. Positive capture — active channel (requires friend in /instance)
With /instance channel on, have friend send "thanks tank".
```
/tox positive
```
Expected: captured regardless of whisper channel state.
(Sprint 4 fix2: channel-off no longer short-circuits capture for non-whisper
channels.)

### H9. Pull frequency — reassuring data surfaces
Use debug tool to seed low-wipe-rate data:
```
/tox debug enable
/tox debug counter "Mists of Tirna Scithe" heroic completions 10
/tox debug counter "Mists of Tirna Scithe" heroic deaths 2
/tox debug counter "Mists of Tirna Scithe" heroic wipes 1
```
Enter Mists of Tirna Scithe on Heroic.
Expected: stat surfaces at encounter start (wipe rate ≤30%).

### H10. Pull frequency — catastrophizing data suppressed
Seed high-wipe-rate data:
```
/tox debug counter "The Stonevault" heroic completions 3
/tox debug counter "The Stonevault" heroic deaths 12
/tox debug counter "The Stonevault" heroic wipes 8
```
Enter The Stonevault on Heroic.
Expected: nothing surfaces (silent suppression — wipe rate >30%).

### H11. Threshold adjustment
```
/tox stats threshold 50
```
Re-enter The Stonevault — stat now surfaces (50% threshold > actual rate).
Reset after: `/tox stats threshold 30`

### H12. Stats surface toggle
```
/tox stats surface off
```
Re-enter any dungeon — nothing surfaces regardless of threshold.
Reset after: `/tox stats surface on`

### H13. Per-dungeon aggregate
```
/tox stats "Mists of Tirna Scithe"
```
Expected: per-difficulty breakdown showing completions, deaths, wipes for that
dungeon.

### H14. Session detail
```
/tox session
```
Expected: current session: start time, encounters tried, deaths, thanks received.
Not the same as `/tox stats` (lifetime).

### H15. Grounding empty default
```
/tox check
```
With no items configured.
Expected: "No grounding items configured. Add items via /tox check add <item>."

### H16. Grounding add items
```
/tox check add hydrated
/tox check add phone away
/tox check list
```
Expected: both items shown.

### H17. Grounding ritual
```
/tox check
```
Expected: prompted for first item.
```
/tox check y
```
Advances to next item.
```
/tox check y
```
Ritual ends.

### H18. Grounding cancel
Mid-ritual:
```
/tox check cancel
```
Expected: ritual aborts cleanly.

### H19. Grounding remove
```
/tox check remove hydrated
/tox check list
```
Expected: shows only "phone away".

### H20. /tox lift during paused window (requires boss encounter)
Enter a boss encounter (isPaused = true).
```
/tox lift
```
Expected: surfaces a positive moment. User-invoked surfacing works during pause
(only live filter and passive UI pause; user commands remain active).

### H21. Retention setting
```
/tox retention 60
```
Expected: confirms retention set to 60 days.

### H22. Debug counter round-trip (Sprint 4 fix)
```
/tox debug enable
/tox debug counter "Mists of Tirna Scithe" heroic completions 10
/tox debug counter "Mists of Tirna Scithe" heroic deaths 2
/tox debug counter "Mists of Tirna Scithe" heroic wipes 1
/tox debug counter list "Mists of Tirna Scithe"
```
Expected: list shows the seeded values.

### H23. Debug command gating (Sprint 4 fix)
```
/tox debug disable
/tox debug counter "Mists of Tirna Scithe" heroic deaths 5
```
Expected: command unrecognized (debug disabled).
```
/tox debug enable
```
Re-enable for remaining tests.

### H24. Debug counter reset (Sprint 4 fix)
NOTE: Command requires the word "confirm" at the end.
```
/tox debug counter reset all confirm
```
```
/tox stats
```
Expected: counters cleared. Stats shows empty state.

---

## SECTION I — Sprint 4b Visual UI

### I1. Version confirms 4b loaded
```
/reload
```
Expected: "[ToxFilter] Loaded — version 0.2.1-sprint5b-polish"

### I2. Highlight UI toggle (fix: was stuck on off)
```
/tox positive ui
```
Run three times. Expected: toggles on/off/on (or off/on/off). No-arg form is a
toggle. Explicit:
```
/tox positive ui on
/tox positive ui off
```
Both should work and report the new state.

### I3. Highlight capture with tint (requires friend in /instance)
```
/tox positive ui on
```
Have friend send "thanks tank" — chat line should display with subtle green tint.

### I4. Highlight UI off — no tint (requires friend)
```
/tox positive ui off
```
Friend sends thanks — chat line normal, no tint.

### I5. Highlight pauses during combat (requires boss encounter + friend)
```
/tox positive ui on
```
Enter encounter (combat-restricted window).
Friend sends thanks during encounter.
Expected: NO tint despite positive_ui being on.

### I6. Highlight resumes after combat (requires friend)
Exit the encounter.
Friend sends thanks.
Expected: tint reappears.

### I7. Box breathing — frame and cycle indicator
```
/tox breathe
```
Expected: animated frame center-screen. Phase label and countdown visible.
NEW (fix2): "Cycle 1 of 4" (or current/total) displays under the count.

### I8. Box breathing completes
Let default run complete (64 seconds at 4 cycles × 4 count, or use `/tox breathe
cycles 1` for 16-second test).
Expected: frame closes. "[ToxFilter] Box breathing complete." prints.

### I9. Box breathing — combat cancel (fix)
```
/tox breathe
```
Trigger combat mid-animation.
Expected: frame closes silently. No completion message.

NEW (fix2):
```
/tox breathe
```
While already in combat.
Expected: "[ToxFilter] Cannot start breathing during combat." Frame does NOT appear.

### I10. Box breathing — shorter cycles
```
/tox breathe cycles 2
/tox breathe
```
Expected: 2 cycles, then closes.

### I11. Box breathing — count adjustment
```
/tox breathe count 2
/tox breathe
```
Expected: each phase 2 counts (faster animation).

### I12. /tox ready — full chain (re-verify after I16 fix)
Prerequisite: grounding items configured (H16), positive moment captured (H3).
```
/tox ready
```
When grounding prompt appears:
```
/tox check y
```
Expected: advances to next item. (I12 was broken when /tox check y/n wasn't
recognized during /tox ready orchestration. Diagnosed as possibly sharing root
cause with I16. Re-verify after I16 fix.)
Continue: grounding completes → breathing animation → lift output → chain ends.

### I13. /tox ready — empty grounding skip
Remove all grounding items first.
```
/tox ready
```
Expected: "[ToxFilter] No grounding items configured. Skipping." then breathing
starts immediately.

### I14. /tox ready — disable step
```
/tox ready include breathing off
/tox ready
```
Expected: grounding → lift only. No breathing.

### I15. /tox ready — reorder steps
```
/tox ready order lift breathing grounding
/tox ready
```
Expected: lift first → breathing → grounding.

### I16. /tox ready — mid-grounding cancel aborts chain (fix)
```
/tox ready order grounding breathing lift
/tox ready
```
Mid-grounding:
```
/tox check cancel
```
Expected: grounding AND chain abort. Breathing does not start. Lift does not run.

### I16b. /tox ready cancel — master abort (new command, fix2)
```
/tox ready
```
During any step:
```
/tox ready cancel
```
Expected: entire chain aborts cleanly from any step.

### I17. /tox ready — mid-breathing Esc aborts chain
```
/tox ready
```
Let grounding complete. When breathing starts, press Esc.
Expected: breathing closes AND chain aborts. Lift does not run.

### I18. Sprint 4a regression — standalone commands still work
```
/tox lift
/tox positive
/tox starred
/tox stats
/tox week
/tox check
/tox session
```
Expected: all work as standalone commands, unaffected by Sprint 4b additions.

### I19. Sprint 0/1/2/3 regression
Send ToxFilterTest fixtures, placeholder rule hits, run `/tox handle list`,
`/tox channel list`, `/tox role auto`.
Expected: all behave as verified in prior sprints.

---

## SECTION J — Sprint 5 Role-Aware Callout Prioritization

Time-critical UI: callouts fire DURING combat (contrast with Sprint 4b
Highlight which pauses). Visual + audio gated by independent sub-toggles.
Master off by default. Sub-toggles default to on; persist independently
across /reload.

Several steps require a friend in /instance (or party/raid). When deferred,
note the step number for the next session.

### J1. Version load
```
/reload
```
Expected: "[ToxFilter] Loaded — version 0.2.1-sprint5b-polish".

### J2. Callout state — baseline
```
/tox callout
```
Expected: "Callout: master off, ui on, sound on." No mismatch note
(master is off).

### J3. Master on
```
/tox callout on
```
Expected: "Callout enabled." No mismatch note (both sub-toggles on).

### J4. Set role
```
/tox role tank
```
Expected: "Role set to 'tank'." Locks role for J5-J7.

### J5. Matching callout (requires friend in /instance)
Friend sends `tank cooldowns` in /instance.
Expected: chat line displays with warm-amber tint (|cFFEEBB55). Single
audio cue plays (READY_CHECK, sound 8960).

### J6. Non-matching callout (requires friend)
Friend sends `healer cooldowns` in /instance.
Expected: line displays unchanged. No tint. No sound.

### J7. Sound off (requires friend)
```
/tox callout sound off
```
Friend sends `tank cooldowns`.
Expected: tint still applied. No audio.

### J8. Ui off (requires friend)
```
/tox callout ui off
```
Friend sends `tank cooldowns`.
Expected: no tint. No audio.

### J9. Restore both
```
/tox callout on
```
Expected: "Callout enabled." Mismatch note appears (both sub-toggles
still off).
```
/tox callout ui on
/tox callout sound on
```
Friend sends `tank cooldowns`.
Expected: tint + audio restored.

### J10. Master off (requires friend)
```
/tox callout off
```
Friend sends `tank cooldowns`.
Expected: no tint. No audio.

### J11. Co-occurrence — callout preempts positive (requires friend)
```
/tox callout on
/tox positive ui on
```
Friend sends `thanks tank, watch your cooldowns`.
Expected: warm-amber tint (callout color preempts positive green).
Audio plays once.

### J12. Combat-active (requires boss encounter + friend)
Enter a boss encounter. While paused, friend sends `tank cooldowns`
in /instance.
Expected: tint + audio still fire. Confirms time-critical UI does not
pause (architectural distinction from Sprint 4b Highlight).

### J13. Audio character check (requires friend)
Friend sends `tank cooldowns`. Listen.
Expected: the cue (READY_CHECK, sound 8960) is distinguishable from
other common WoW events in your sound mix. If it collides, log it for
a future sound swap.

### J14. Multi-role detection (requires friend)
Friend sends `tank and healer cooldowns`.
With `/tox role tank` → tint + audio fire.
With `/tox role healer` → tint + audio fire.

### J15. Negative detection — these must NOT fire (requires friend)
Have friend send each line in /instance. Expected: no tint, no audio
for any of these.
- `thanks tank`
- `you trash tank`
- `good job tank`
- `i'm the tank`
- `tank died`
- `great pull tank`

### J16. Role auto-detect
```
/tox role auto
```
Expected: "Role set to auto-detect." Friend sends a callout matching
the player's actual spec role → tint + audio fire.

### J17. Sprint 4a regression
```
/tox positive
/tox lift
/tox stats
```
Expected: all three return their expected output, unaffected by
Sprint 5 additions.

### J18. Sprint 4b regression (requires friend)
```
/tox positive ui on
/tox callout off
```
Friend sends `thanks tank` in /instance.
Expected: green positive tint (Sprint 4b Highlight, not callout).

### J19. Sprint 2 regression
```
move out of fire you trash tank
```
in /instance.
Expected: "[ToxEdit] move out of fire" — role attack still routes
through classifier and surgical rewrite.

### J20. Corpus harness
```bash
./scripts/run-corpus.sh
```
Expected: Sprint 2 100%, Sprint 5 100%, Sprint 5b 12/12.

---

## SECTION J fix2 — Callout State-Mismatch Note

Verifies `Callout.GetStateMismatchNote()` surfaces at three call sites:
`/tox callout on` confirmation, `/tox callout` no-arg status, and
ToxFilter:OnEnable (after the version print on /reload). No note on
explicit disables or when master is off.

### J21. Note on /tox callout on
From baseline, run:
```
/tox callout sound off
/tox callout on
```
Expected: "Callout enabled." followed by mismatch note: "Note: audio
cue is off. Run /tox callout sound on to enable."

### J22. Combined note on no-arg status
```
/tox callout ui off
/tox callout
```
Expected: state line plus combined note: "Note: visual tint and audio
cue are off. Run /tox callout ui on or /tox callout sound on to
enable."

### J23. Note on /reload with mismatch state
With the J22 state (master on, ui off, sound off):
```
/reload
```
Expected: load line followed by the combined mismatch note (same text
as J22).

### J24. No note on explicit disable
```
/tox callout on
/tox callout ui on
/tox callout sound on
/tox callout ui off
```
Expected: "Callout visual disabled." No mismatch note on this command
itself (the disable was deliberate).

### J25. No note when master off
```
/tox callout off
```
Expected: "Callout disabled." No mismatch note (master off
short-circuits the note logic).

### J26. No note on /reload with master off
Run Phase 0 (master off, ui on, sound on).
```
/reload
```
Expected: load line, no mismatch note.

---

## SECTION K — Sprint 5b Boss Tactic Reminders

Pre-encounter, role-filtered reminders from JournalData. Surfaces at
ENCOUNTER_START before setPaused(true). Dual-surface: chat block (full
header `Encounter (bucket) — Role reminders:` plus bulleted lines) AND
on-screen via RaidWarningFrame (tighter header `Role — Encounter:` plus
one line per mechanic). No audio. Local-widget only; never broadcasts.
First-attempt-only per session.

Several steps require entering a dungeon currently covered by
JournalData. As of this writing: Magisters' Terrace only. Other
dungeons fall under K10 (silent for uncovered content).

### K1. Version load
```
/reload
```
Expected: "[ToxFilter] Loaded — version 0.2.1-sprint5b-polish".

### K2. Reminders state — baseline
```
/tox reminders
```
Expected: "Reminders: master off. N encounters in journal, 0 seen
this session." N reflects current JournalData coverage.

### K3. Master on
```
/tox reminders on
```
Expected: "Reminders enabled."

### K4. First-attempt reminder (requires Magisters' Terrace pull)
Enter Magisters' Terrace, pull a boss (e.g., Arcanotron Custos).
Expected: BOTH surfaces fire pre-pause:
- Chat block: "[ToxFilter] Arcanotron Custos (<bucket>) — <Role>
  reminders:" followed by bulleted lines ("[ToxFilter]   - …").
- RaidWarningFrame: tighter header "<Role> — Arcanotron Custos:"
  then one line per mechanic.
No audio cue. Filter then pauses ("[ToxFilter] Filtering paused —
combat window.").

### K5. Wipe + re-pull same boss
Wipe; re-pull the same boss.
Expected: no chat block, no RaidWarningFrame post (first-attempt-only
per session per (instance, encounter, bucket) triple).

### K6. Different encounter same key
Pull the next boss in the same key.
Expected: reminder block surfaces (per-encounter, not per-instance).

### K7. Session reset
```
/tox reminders reset
```
Expected: "Reminders session reset. Each (encounter, difficulty) will
re-surface on next pull."

### K8. Re-pull after reset
Re-pull any boss already pulled this session.
Expected: reminder block surfaces again (reset rearmed the seen-map).

### K9. /reload clears seen map
Pull a boss (so it is seen this session).
```
/reload
```
Pull the same boss again.
Expected: reminder block surfaces. OnInitialize clears
tactic_reminders_seen on every /reload; storage in db is session-scoped
despite the persistence.

### K10. Instance not in JournalData
Enter an instance without JournalData coverage (e.g., a non-Midnight
raid or any of the seven not-yet-authored dungeons). Pull a boss.
Expected: silent — no chat block, no RaidWarningFrame post.

### K11. Role auto-detect
```
/tox role auto
```
Pull a Magisters' Terrace boss.
Expected: surfaced reminders match the player's resolved spec role.

### K12. Manual role override
```
/tox role tank
```
Pull a boss for which JournalData has a distinct healer block.
Expected: surfaced reminders are the tank block (override is honored
over auto-detect for reminder selection).

### K13. Master off
```
/tox reminders off
```
Pull a boss.
Expected: no reminder on either surface.

### K14. Sprint 5 callout regression (requires friend in encounter)
```
/tox callout on
/tox reminders off
```
Enter a boss encounter. Friend sends `tank cooldowns` mid-fight.
Expected: tint + audio still fire (Sprint 5 callout unaffected by
Sprint 5b additions).

### K15. Sprint 4a regression
```
/tox positive
/tox stats
```
Expected: both return expected output, unaffected by Sprint 5b
additions.

### K16. Corpus harness
```bash
./scripts/run-corpus.sh
```
Expected: Sprint 5b gating 12/12.

---

## COMMON VERIFICATION RECIPES

Reference these by name when a sprint specifies what to run.

- **Phase 0 only:** baseline state reset before any session
- **Smoke test:** A1, A4, A7, B1-B4 — fastest "is the addon loaded and clean" check
- **Build 0 regression:** C1-C5, G1-G4 — four handling modes plus pause
- **Build 0+1 regression:** Build 0 regression + D1-D10, E1-E5 — adds rule engine
- **Sprint 3 full:** F1-F22 — all persistence and configuration
- **Sprint 4a full:** H1-H21 — affirmative features slash surfacing
- **Sprint 4b full:** I1-I19 — visual UI and orchestration
- **Sprint 4 combined:** H1-H21, I1-I19
- **Sprint 5 full:** J1-J20 — callout detection, visual/audio prioritization
- **Sprint 5 fix2 items:** J21-J26 — state-mismatch note at three call sites
- **Sprint 5b full:** K1-K16 — pre-encounter tactical reminders (dual-surface)
- **Fix sprint items:** F3-F5, F9, F14, F18-F18b, H1b, H22-H24, I2, I7 (cycle), I9 (combat), I12, I16-I16b, J21-J26
- **Full regression:** Phase 0, A1-A7, B1-B5, C1-C5, D1-D10, E1-E5, F1-F22,
  G1-G4, H1-H24, I1-I19, J1-J26, K1-K16

---

## SPRINT INDEX

- Sprint 0: B1-B4, C1-C5, G1-G4
- Sprint 1: A2, A3, A4, D1-D5, E1, E2, E3
- Sprint 2: A4 (extended), D6-D10, E4, E5
- Sprint 3: A5, A6, B5, F1-F22
- Sprint 3 fix-1: F5 (master state header), F9 (default restore), F12, F13
- Sprint 4a: H1-H21
- Sprint 4b: A6 (extended), I1-I19
- Sprint 4 fix (0.0.7): F3-F5, F9, F14, F18-F18b, H1b, H22-H24, I9 (partial), I16
- Sprint 4 fix2 (0.0.8): F18 (re-fix), H3b, I2, I7 (cycle indicator), I9 (entry
  gate), I12 (re-verify), I16b (/tox ready cancel), Phase 0 (new)
- Sprint 5 (0.1.0 / 0.1.1-sprint5-fix): J1-J20. Sound swap 540061→8960, six
  debug-gated diagnostic prints across chatFilter / Callout, multi-fire
  negative corpus case.
- Sprint 5 fix2 (0.1.2-sprint5-fix2): J21-J26 (Callout.GetStateMismatchNote
  at three call sites: /tox callout on, /tox callout no-arg, OnEnable).
- Sprint 5b (0.2.0-sprint5b): K1-K16 (TacticReminders module, Magisters'
  Terrace content, schema v7, /tox reminders commands).
- Sprint 5b polish (0.2.1-sprint5b-polish): K4 (RaidWarningFrame dual-surface
  display alongside chat; local-widget only, never broadcasts).

---

## KNOWN ISSUES / PENDING VERIFICATION

As of version 0.2.1-sprint5b-polish:

- F19-F20 (whisper with friend): deferred (requires friend).
- H3b (thanks <name> capture, generic form): retest required (requires friend).
  Earlier sessions captured "thanks manehealer" and "thanks manehealer-thrall"
  but the bare "thanks <name>" variant remains unconfirmed.
- I3-I6 (highlight visual): partly confirmed during Sprint 5 testing; the
  full combat-pause path (I5/I6) deferred (requires friend in encounter).
- I12 (/tox check y/n inside /tox ready): no code-side bug found. Re-verify
  next time the chain is exercised end-to-end.
- J5-J11 (callout with friend): confirmed working during Sprint 5 in-game
  verification.
- J12 (combat-active callout): confirmed during Sprint 5 in-game
  verification. Re-run when a fresh combat session is available.
- J15 (negative cases with friend): the multi-fire negative case
  `healer needs to heal` is locked into the Sprint 5 corpus; the remaining
  J15 phrasings need in-game re-verification with a friend each fresh
  session.
- K4-K9 (reminders dual-surface in JournalData-covered dungeons):
  Magisters' Terrace confirmed during Sprint 5b polish testing. Remaining
  seven dungeons pending content authoring (per CLAUDE.md sprint plan).
- K10 (instance not in JournalData): confirmed silent.
- H20 (/tox lift during pause): confirmed working in Sprint 5b testing.
- H25 (open-world scope check): confirmed clean during Sprint 4 fix
  testing.
