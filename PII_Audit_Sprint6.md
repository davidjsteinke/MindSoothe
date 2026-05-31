# PII Audit — Sprint 6 (audit and document)

Audit-and-document pass only. No code was changed, no schema was touched, no
remediation was performed. This document records what the addon stores, what is
actually stored at rest, and where the principle is honored, strained, or in
need of a decision.

Principle under test:

> No third-party PII is recorded. The installing user's own data is theirs to retain.

Scope of evidence:

- **Code review** — every module that writes to AceDB or otherwise persists
  (`Database`, `Buffer`, `PositiveCapture`, `PIIScrub`, `UserRules`, `Stats`,
  `TacticReminders`, `PreDungeon`, `Grounding`, `Ready`, `Breathing`, `Debug`,
  `Commands`, and the `ToxFilter` event handlers).
- **Data at rest** — five real SavedVariables files from this device:
  - `WTF/Account/QUESOMAN/SavedVariables/ToxFilter.lua` (schema v9, live, modified today)
  - `WTF/Account/662242#1/SavedVariables/ToxFilter.lua` (schema v7) and its `.bak`
  - `newold/Account/QUESOMAN/SavedVariables/ToxFilter.lua` (schema v7, prior install copy)
  - `newold/Account/662242#1/SavedVariables/ToxFilter.lua` (schema v6, prior install copy)

Third-party identifiers in the live data are redacted in this document per the
audit's redaction requirement. The installing user's own data (own character
names, own role, own counters, captured-text bodies that contain no third-party
name) is quoted directly.

---

## 1. Summary

**As actually stored today, the addon holds no third-party player names.** Across
all five SavedVariables files, every captured positive-moment body is a generic
role or callout phrase (`thanks tank`, `thanks healer, interrupt next add`,
`great pull tank`, `gg`) — none contains another player's name, and no captured
moment stores the sender's name as a field. Flagged events store only a
category, severity, and timestamp — never message text and never an author. The
counters store Blizzard zone names and the installing user's own activity.

**But the code can store third-party-authored content, and the name-stripping is
narrow enough that the clean result is partly a property of what was tested, not
a guarantee of the design.** Positive-moment capture writes the *verbatim message
body* (after `PIIScrub`) of messages other players typed. `PIIScrub` only removes
names in two narrow positions, and several plausible real-world inputs — a
lowercase name, a name with an apostrophe or connected-realm suffix, or any name
not immediately following a "thanks" token — would survive into storage. Pinned
moments copy that body and are never pruned.

Net: the principle is honored in the data-at-rest reviewed, but the live path has
latent gaps that could record a third-party name under inputs the test data did
not exercise. There is also one genuine judgment call — whether storing a third
party's message body verbatim (even with names stripped) is consistent with the
principle, or needs a documented carve-out.

---

## 2. Storage inventory

AceDB scope is account-wide (`global`); there is no per-character split. All
fields below live under `ToxFilterDB.global` unless noted. "Owner" is assessed
against the installing user.

| Field | Type / shape | Owner | Purpose | Lifetime | PII assessment |
|---|---|---|---|---|---|
| `schema_version` | int | neither | migration bookkeeping | persists | none |
| `enabled` | bool | user config | addon master toggle | persists | none |
| `channels.{raid,instance,battleground,whisper}` | bool | user config | per-channel filtering | persists | none |
| `handling[category]` | string | user config | per-category handling override | persists | none |
| `role` | string | user (own role) | role selection | persists | none (own) |
| `role_last_seen` | string | user (own role) | cached role for login window | persists | none (own) |
| `blacklist` | map: hash → normalized token | user-authored words | user filter list | persists | **potential** — user could enter a third party's name; stored as normalized plaintext + hash (see §3.3) |
| `whitelist` | map: hash → normalized token | user-authored words | rule-exemption list | persists | **potential** — same as blacklist |
| `whisper_intro_shown` | bool | neither | one-shot privacy-note flag | persists | none |
| `retention_days` | int | user config | windowed-event retention | persists | none |
| `grounding_items` | list of strings | user-authored (own) | grounding ritual items | persists | none (own free-text; e.g. `phone away`, `hydrated`) |
| `stats_threshold` | int | user config | wipe-rate surfacing gate | persists | none |
| `stats_surface` | bool | user config | live stats surfacing toggle | persists | none |
| `positive_ui` | bool | user config | highlight toggle | persists | none |
| `breathe_cycles`, `breathe_count` | int | user config | breathing UI | persists | none |
| `breathe_position` | `{x,y}` | user config | UI frame offset | persists | none |
| `ready_config` | `{include, order}` | user config | `/tox ready` orchestration | persists | none |
| `debug_enabled` | bool | user config | developer flag | persists | none |
| `callout_enabled`, `callout_ui`, `callout_sound` | bool | user config | callout feature | persists | none |
| `tactic_reminders_enabled` | bool | user config | reminders master | persists | none |
| `tactic_reminders_seen` | map: `instance\|encounter\|bucket` → true | neither | session de-dupe | session-scoped (cleared in `OnInitialize`) | none — keys are Blizzard content names |
| `predungeon_warnings_enabled` | bool | user config | warnings master | persists | none |
| `predungeon_warnings_seen` | map: instance → true | neither | session de-dupe | session-scoped (cleared in `OnInitialize`) | none — keys are Blizzard zone names |
| `category_toxfilter_enabled`, `category_uplifter_enabled` | bool | user config | category master toggles | persists | none |
| `feedback_log` | table (declared `{}`) | — | none — **never written** (see §4) | n/a | none — orphan default |
| `session_buffer.counters.instances[zone][bucket]` | `{deaths,wipes,completions,last_event}` | user activity | per-dungeon counters | permanent (never pruned) | none — `zone` is a Blizzard instance name; counts are the user's own |
| `session_buffer.counters.sessions.current` / `history[]` | `{started_at,last_activity_at,deaths,thanks_received,encounters_completed,encounters_wiped}` | user activity | session rollups | permanent (history capped 20) | none — own play timestamps + counts |
| `session_buffer.counters.thanks_total` | int | user activity | lifetime thanks count | permanent | none |
| `session_buffer.events.flagged_events[]` | `{ts,category,severity}` | user experience | windowed flag log | windowed (`retention_days`) | none — **no message text, no author** |
| `session_buffer.events.positive_moments[]` | `{id,ts,text,signals.pattern,direct_to_user}` | **third-party-authored** body + own metadata | captured praise | windowed (`retention_days`) | **the key item** — see §3.1 |
| `session_buffer.events.activity_log[]` | `{ts,type}` | user activity | source-of-truth for windowed aggregates | windowed (`retention_days`) | none — own event timestamps |
| `session_buffer.next_pm_id` | int | neither | id sequence | persists | none |
| `pinned_moments[id]` | `{id,ts,text,signals,direct_to_user,pinned_at}` | **third-party-authored** body + own metadata | user-pinned praise | **permanent (never pruned)** | same concern as positive_moments, with unbounded lifetime — see §3.2 |
| `profileKeys["<Char> - <Realm>"]` | map → "Default" | installing user (own characters) | **AceDB-managed**, not written by addon code | persists permanently | own data, but identifying — see §3.5 and §4 |

---

## 3. Third-party data findings

### 3.1 Positive-moment bodies (`session_buffer.events.positive_moments[].text`) — primary item

- **What is stored:** the message body, run through `ns.PIIScrub.scrub` at
  `Buffer:RecordPositiveMoment`. The full body is retained, not just the trigger
  tokens — e.g. `thanks healer, interrupt next add` is stored in its entirety.
- **Sender's name:** **not stored.** There is no author field. The capture
  records `text`, `ts`, a synthetic `id`, `signals.pattern`, and the boolean
  `direct_to_user`. The sender's character name is never written.
- **Is the body verbatim or normalized?** Verbatim, minus whatever `PIIScrub`
  removes. `PIIScrub` is narrow (see the gap analysis below); it does **not**
  normalize, lowercase, or tokenize the stored form — it returns the original
  text with at most a couple of name-position substitutions.
- **Retention:** bounded. Positive moments are pruned on addon load by
  `Buffer:Prune(retention_days)` (default 30; the live file sets 60).
- **Live data:** in all five files, every `text` value is a generic role/callout
  phrase with no player name (`thanks tank`, `thanks healer`, `ty tank`,
  `nice pull`, `good heals`, `great pull tank`, `gg`, `gg ty`). No third-party
  name is present in any captured moment.

**PIIScrub gap analysis (why the clean data is not a guarantee).** `PIIScrub`
removes a name only in two positions:

1. the single token immediately after a thanks-token (`thanks/thank/thx/ty/tysm`),
   and only if that token matches `^%u%a+$` (initial capital, ASCII letters only);
2. anywhere an `@mention` appears.

The following plausible inputs would **not** be scrubbed and would be stored with
the name intact, provided some pattern triggers capture:

- **Lowercase name after thanks** — `thanks bob nice kick`. `bob` fails the
  `^%u` test; `nice kick` triggers `compliment_play`; stored as `thanks bob nice kick`.
- **Name with apostrophe / hyphen / digit / non-ASCII** — `thanks Al'ar`,
  `thanks Naz'grim`, accented names. All fail `^%u%a+$` and survive.
- **Connected-realm suffix** — `thanks Bob-Thrall`. `PositiveCapture` strips the
  realm suffix for *matching*, but `PIIScrub` does not strip it before its
  `looksLikeName` test, so `Bob-Thrall` (internal hyphen) fails `^%u%a+$` and
  survives.
- **Name not adjacent to a thanks token** — `Bob nice kick` (compliment_play) or
  `gg Bob` (positive_callout). `PIIScrub` only checks the post-thanks position
  and `@mentions`, so a name anywhere else is never examined.
- **Second name after thanks** — `thanks Bob and Jim`. Only the first post-thanks
  token is checked; `Jim` survives.

None of these manifested in the test corpus, but each is ordinary group-chat
phrasing. The clean data-at-rest reflects what was typed during testing, not a
guarantee the scrubber would have caught a name.

**Whisper interaction.** Positive capture runs on whispers when the whisper
channel is on (it is, in the live file). The whisper privacy carve-out only
suppresses capture when whisper is *off*. So a whispered `thanks <name> nice save`
is in scope for capture and the same scrub gaps apply.

### 3.2 Pinned moments (`pinned_moments[].text`) — unbounded lifetime

Pinning copies a positive moment's `text` verbatim into `pinned_moments`, which
**`Buffer:Prune` never touches**. If any future pinned moment carries an
unscrubbed name (per §3.1), it persists indefinitely with no retention bound.
**No pinned moments exist in any of the five files** — the feature was not
exercised in testing — so there is no live exposure today, only a latent one.

### 3.3 Blacklist / whitelist (`blacklist`, `whitelist`)

User-authored word lists, stored as `hash → normalized plaintext`. A user could
add a third party's name (e.g. to filter mentions of a specific player). That
name would be stored as a normalized plaintext token. This is user-authored,
user-controlled, never transmitted, and entirely the installing user's choice —
but it is a place a third-party name *could* land at rest. **Both lists are empty
in all five files** (absent — AceDB strips the empty-default tables).

### 3.4 Flagged events (`session_buffer.events.flagged_events[]`) — clean

Stores only `{ts, category, severity}`. No message text, no author, no
normalized token. The categories (`slur`, `role_attack`, `harassment`,
`harm_invocation`, `general_hostility`, `identity_attack`) describe what was
filtered *for the user*, in aggregate, with no third-party identifier and no
verbatim content. Consistent with the principle. (Note for disclosure: this is a
windowed record of abuse categories the user received — the user's own
experience data, not a third party's.)

### 3.5 `profileKeys` — installing user's own roster

Every file carries an AceDB-managed `profileKeys` table mapping
`"<Character> - <Realm>"` to a profile name, one entry per character the user has
logged in with on that account (the live file holds roughly fifty such entries;
the test-account files hold a handful of obvious dummy names). These are the
**installing user's own characters** — own data under the principle, not
third-party. They are identifying (they reveal the user's full alt roster and
realms) and they are written automatically by AceDB, not by any addon code path.
Flagged here for the disclosure note in §5/§6, not as a third-party concern.

---

## 4. Code vs. data-at-rest reconciliation

What the code claims to store matches what is on disk, with three items the
code-only review would have missed or mis-weighted:

- **`profileKeys` is written by AceDB, not by addon code.** Tracing `db.*`
  writes in the modules never surfaces it, because no module writes it — the
  library does. It is present in every file. This is exactly the kind of finding
  the data-at-rest pass exists to catch: the most identifying account-level data
  in the file is generated by the framework, outside the code paths the
  inventory traces.
- **`feedback_log` is an orphan.** Declared in `DEFAULTS` (`Database.lua:108`)
  but never written by any module (confirmed by grep across `addon/`). AceDB
  strips it as equal-to-default, so it never appears on disk. Dead schema field;
  housekeeping only, no PII implication.
- **`pinned_moments`, `blacklist`, `whitelist` are code-supported but unused.**
  Absent from all five files. The code paths exist; testing never populated
  them. Their PII characteristics (§3.2, §3.3) are therefore latent, not live.

Other reconciliation notes:

- **Positive-moment bodies match expectations** — verbatim, scrubbed, no author
  field, all generic phrases in the live data. No surprise content.
- **No orphaned data from removed features.** The Sprint 4 (schema v4) counter
  reshape already discarded the old `encounters[]`/`dungeons[]` shape; no
  remnants appear. Counter tables are all in the current
  `instances[zone][bucket]` shape.
- **Schema spread across files is consistent with migration history** — live
  QUESOMAN is v9; the backup/old-install copies are v6/v7. No file is at an
  unexpected version, and no field appears that its schema version shouldn't have.
- **No per-character SavedVariables exist** for this addon — consistent with the
  account-wide (`global`) scope. Only the AceDB `profileKeys` index is
  per-character, and it lives in the account-wide file.

---

## 5. Flagged items for remediation

Severity legend: **clean** / **needs-carve-out** / **borderline** / **violation**.
No fixes were applied; each remediation is a sketch for the follow-on pass.

1. **PIIScrub coverage gaps — borderline (primary technical exposure).**
   The scrubber catches only post-thanks Capword names and `@mentions`; lowercase
   names, names with apostrophes/hyphens/digits/non-ASCII, connected-realm
   suffixes, names away from the thanks position, and second names all survive
   (§3.1). *Remediation sketch:* strip the realm suffix before the name predicate
   (mirror `PositiveCapture.stripRealmSuffix`); broaden `looksLikeName` to cover
   apostrophes/hyphens and the lowercase post-thanks case; scan all token
   positions rather than only post-thanks; or — more conservatively — change what
   is stored (item 3) rather than chasing every name shape. Requires the
   aggressiveness decision in §6.B.

2. **Pinned moments are never pruned — borderline.**
   `Buffer:Prune` skips `pinned_moments`, so any name that slips past the scrubber
   (§3.1) persists forever once pinned (§3.2). No live exposure today (no pins
   exist). *Remediation sketch:* re-scrub on pin, guarantee scrub is airtight
   before any pin is allowed, or accept pins as deliberately-retained own moments
   (ties to §6.A).

3. **Verbatim third-party body retention — needs-carve-out (judgment call).**
   Even with names fully stripped, `positive_moments.text` and `pinned_moments.text`
   store the *exact sentence a third party typed* (e.g. `thanks healer, interrupt
   next add`). The body minus names is not obviously PII, but it is third-party-
   authored content held at rest. *Remediation sketch (if reduction is chosen):*
   store only `signals.pattern` + `direct_to_user` + `ts` (and optionally the
   matched role), dropping `text` — the surfacing features would render a
   templated line instead of the original words. This eliminates the question
   entirely but loses the verbatim recall the feature currently offers. Decision
   in §6.A.

4. **`feedback_log` orphan field — clean (housekeeping).**
   Declared, never written. *Remediation sketch:* remove from `DEFAULTS`, or wire
   the feature that was intended to use it. No PII implication; cosmetic.

5. **Blacklist/whitelist can hold a third-party name by user choice — clean.**
   User-authored, user-controlled, never transmitted. Flagged for completeness
   only; no remediation proposed beyond awareness in the eventual disclosure.

6. **`profileKeys` reveals the local character roster — clean (disclosure note).**
   Own data, user-side only, never transmitted. Nothing to fix in code. Flagged
   so the Sprint 8 privacy disclosure can state plainly that the addon's
   SavedVariables contains the user's own character/realm list (an AceDB
   artifact), in case that surprises a privacy-conscious reader.

---

## 6. Judgment calls for the user

These are not technical defects with an obvious fix; they are places where the
principle's application is genuinely a decision.

**A. The verbatim-body carve-out (the big one).**
Positive moments — and pins derived from them — store a third party's message
body verbatim, names scrubbed (§3.1, §3.3). Three coherent positions:
   - **(i) Documented carve-out:** "the installing user's own positive moments,
     including the message text that praised them, are the user's data to retain."
     Keep verbatim storage; harden the scrubber (item 1) so names don't ride along.
   - **(ii) Reduce to non-verbatim:** store pattern + role + timestamp, drop the
     `text` body (item 3). Strongest privacy posture; loses verbatim recall.
   - **(iii) Status quo:** keep as-is. Not recommended without at least the
     scrubber hardening, given §3.1.
This is the decision the remediation pass hinges on.

**B. Scrubber aggressiveness.**
If verbatim storage stays (A-i), how aggressive should `PIIScrub` be? Targeted
(fix the named gaps in §3.1, accept some residual risk) versus aggressive
(replace every name-shaped token in a captured body with `<player>`, risking
mangling of proper-noun mechanic names and tactical words that legitimately look
like names). Trade-off is leak risk versus readability of the retained moment.

**C. Whisper capture.**
Positive capture currently runs on whispers when the whisper channel is on
(§3.1). Acceptable, or should capture never run on whisper events regardless of
the channel toggle, treating private 1:1 messages as always out of scope?

**D. `profileKeys` disclosure.**
Nothing to fix technically. Decide whether the Sprint 8 privacy disclosure should
explicitly note that the addon's SavedVariables contains the user's own
character/realm roster (an AceDB artifact, never transmitted).

---

*End of audit. No code, schema, or version changes were made. The only file
created this session is this document.*
