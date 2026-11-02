---
name: 15five
description: Draft the weekly 15Five check-in from real evidence — Jira, GitHub, Granola, Calendar, Slack, and prior check-ins — reading the live form for its current questions, then filling it in Safari after approval. Stops before Submit. Use when the user says "15five", "weekly check-in", or asks to write or fill out their check-in.
argument-hint: "[week] [--draft-only]"
---

Draft this week's 15Five check-in and fill it into the live form, stopping
short of Submit. `$ARGUMENTS` may name a week (`last week`, `Sep 19`,
`Sep 19 - Sep 25`) to target a past-due check-in instead of the current
one, and may carry `--draft-only` to skip filling the form entirely.

The discipline that makes this worth doing: **every sentence you write
traces to something that actually happened.** A check-in assembled from
plausible-sounding engineering activity is worse than a blank one — it
reads fine to you and reads hollow to a manager who was in the same
sprint. Gather evidence first, draft only from it, and leave a field
blank rather than pad it.

Two fields are never yours to write: the mood score and the High Five.
Both are first-person judgments. Propose, never fill.

## Stage 0 — Open the check-in

Open a background tab and **keep the receipt**:

- `safari_new_tab` with `https://my.15five.com/report/current/`. That URL
  redirects to `https://my.15five.com/report/archive/`.
- The call returns a `receipt`. Pass it as `receipt` on every later Safari
  call. Tab indexes go stale the moment another tab opens or closes, and a
  stale index fails with `Can't get tab N of window 1`.

Safari attaches to the real browser, so an existing 15Five session is
already authenticated — there is no login step. If the page is a login
screen, **stop and ask the user to log in.** Never type credentials, and never
read them from a password manager.

The archive table lists every week with its state:

```
Check-in frequency   Submitted        Action
Sep 26 – Oct 2       —                Fill out current Check-in
Sep 19 – Sep 25      —                Fill out Check-in
Sep 12 – Sep 18      Sep 18, 2026     View Check-in
```

`safari_extract_links` with filter `/report/` maps those rows to URLs:
fill-out pages are `/report/fillout/report/<id>/` and submitted ones are
`/report/<id>/`. Pick the row matching `$ARGUMENTS`, or the current week
if no week was given. Navigate to its fill-out URL.

## Stage 1 — Read the form, never assume it

The question set rotates — at least one question varies between check-ins,
and priorities carry over from the previous week. Read them every run.

Enumerate the writable slots with `safari_evaluate`:

```js
try {
  var tas = Array.prototype.slice.call(
    document.querySelectorAll('#fillout-report-form textarea[name="new"]'));
  var res = tas.map(function (t, i) {
    var el = t, label = null;
    for (var d = 0; d < 8; d++) {
      el = el.parentElement;
      if (!el) break;
      var txt = (el.innerText || '').trim();
      if (txt && txt.length < 400 && txt.indexOf('?') !== -1) {
        label = txt.split('\n')[0];
        break;
      }
    }
    return { i: i, ph: t.placeholder, label: label };
  });
  return JSON.stringify(res);
} catch (e) { return 'ERR: ' + e.message; }
```

That returns an index → question map, e.g. slots 0–2 are
`Add a new priority` and slots 3–5 are `Add a new answer` labelled with
the actual question text. Fill by index into that NodeList.

Form facts worth knowing before you touch anything:

- The form is `#fillout-report-form`, posting to `/report/submit/<id>/`.
- Mood is a radio group `name="happiness_value"`, ids `#pulse-input-1`
  through `#pulse-input-5`.
- **Every blank textarea shares `id="new"`.** Duplicate IDs — `#new` is
  not a usable selector. Always index into
  `querySelectorAll('textarea[name="new"]')`, or use `safari_snapshot`
  refs.
- Carried-over priorities are prefilled textareas named
  `q_<questionId>_a_<answerId>`. Read their values; they are last week's
  commitments and the spine of Stage 3.
- The "mark priorities complete" checkboxes live in a **separate sibling
  form** on the same page, not in `#fillout-report-form`.

## Stage 2 — Gather evidence

Determine the evidence window first. Normally it is the check-in's own
date range. **If the previous check-in was never submitted**, extend the
window back to the end of the last week that was, and say so in Stage 4 —
otherwise a fortnight of work silently disappears.

Run all six sources in parallel. If one is unauthenticated, empty, or
slow, note it and move on; a missing source degrades the draft, it does
not block it.

Jira and Slack read the `work` plugin's `jira_site` and `slack_user_id`
settings. If either is empty, or still a literal `${user_config…}`
placeholder (as when this file is read directly rather than loaded as a
plugin skill), look the value up another way
(`getAccessibleAtlassianResources`, the Slack user's own profile) or skip
that source and say so in Stage 4.

- **GitHub** — `gh search prs --author @me --merged ">=<start>"`, plus
  `--review-requested @me` and `--created` for work still open. Pull
  titles and repos, not diffs.
- **Jira** — `searchJiraIssuesUsingJql` (cloudId `${user_config.jira_site}`)
  over the window, something like
  `assignee = currentUser() AND updated >= "<start>" ORDER BY updated`.
  Capture status transitions, not just titles: "moved to Done" is the
  evidence, "exists" is not.
- **Granola** — `list_meetings` across the window, then
  `get_meeting_transcript` only for meetings that look substantive.
  This is where non-code work lives — design reviews, incidents,
  planning.
- **Google Calendar** — `list_events` across the window, to catch time
  spent that produced no artifact.
- **Slack** — `slack_search_public_and_private` for the user's own messages
  (`from:<@${user_config.slack_user_id}>`).
  This catches unblocking other people, which is invisible to Jira and
  GitHub and is exactly what "what went well" should capture.
- **Prior check-ins** — open the last two or three `/report/<id>/` pages
  from the archive. Read them for two things: the voice to match, and
  threads they said they would carry forward.

## Stage 3 — Draft

Reconcile before you compose. For each carried-over priority, assign
**done / partial / not started** and name the evidence. That reconciliation
is the single most useful thing in the check-in, and it is the part that
cannot be faked.

Then draft each field the form actually asked for:

- **Priorities for next week** — concrete and checkable. Carry forward
  anything unfinished rather than quietly dropping it. Prefer what the
  sprint actually holds over aspirational items.
- **What went well** — specific, with the issue key or PR where it reads
  naturally. Three or four items beats a paragraph.
- **Biggest challenge, and how can I help** — a real one. If the evidence
  shows a blocker (a stalled review, a flaky pipeline, a dependency on
  another team), name it and name the ask. If nothing was genuinely
  blocking, say that plainly instead of manufacturing a struggle.
- **What can we do better as a company** — optional. Leave it blank
  unless the week produced an actual observation. Filler here costs
  credibility.

Match the voice from prior check-ins — sentence length, formality, and
whether they write bullets or prose. Do not upgrade their register.

Do not write the mood score. Do not write the High Five. If the evidence
shows someone unblocked them or carried something, surface them as a
*candidate* with the one-line reason, and let them decide.

## Stage 4 — Present for approval

Render one block per field, headed by the question text **exactly as read
from the form** in Stage 1. Under each block, a short evidence line so they
can audit the claim without opening six tabs:

```
What went well this week?

  <draft text>

  ← PROJ-412 moved to Done; example/api#1183 merged Tue
```

Flag separately: the mood score (unanswered, theirs), the High Five
(candidate or none, theirs), any source that failed to return, and an
extended evidence window if the prior week was unsubmitted.

Then ask: fill it as drafted, edit first, or stop here.

## Stage 5 — Fill, and stop

Skip this stage entirely on `--draft-only`.

- Fill via `safari_fill` with a **ref from `safari_snapshot`**, not a raw
  `element.value = ...` assignment. The form is React-controlled; a
  direct value write does not update component state and is discarded on
  submit.
- Select the mood radio only if the user gave you a number.
- Tick the carried-priority completion checkboxes only for priorities they
  confirmed as done.
- Re-read the form afterward and verify every field landed. Report any
  that did not rather than assuming success.

**Never click Submit.** Leave the tab filled and tell them it is ready.
Submitting early raises a "You're here early!" confirmation modal with
*Submit now* / *Submit later* — theirs to resolve, not yours.

## Stage 6 — Persist

Once they confirm they submitted, write a short `add_memory` episode: the
week, the priorities they committed to, and any thread they flagged as
carrying forward. Next week's run reads that back in Stage 2, so
continuity across check-ins survives the session ending.

If Graphiti is unavailable, say so plainly and name what went unwritten —
do not fall back to a file silently.
