---
name: standup
description: Build scannable yesterday/today/blockers notes for a daily standup from Jira, GitHub, local git, Claude Code sessions, Granola, Calendar, Slack, Gmail, and the previous standup. Takes an optional reference day ("tomorrow", "last tuesday", "10/28"; default today). Use when the user says "standup", "standup notes", "prep for standup", or "what did I do yesterday".
argument-hint: "[day]"
---

Produce short notes the user can read off of, live, during standup. The
notes are a crib sheet, not a report: if a line can't be read aloud in
about five seconds, it is too long.

Every line must trace to something that actually happened in the
evidence. Leave a section at `none` rather than pad it.

## Settings

These come from the `work` plugin's settings (`/config`, or `claude
plugin configure work`):

| Setting | Value |
| --- | --- |
| `work_email` | `${user_config.work_email}` |
| `slack_user_id` | `${user_config.slack_user_id}` |
| `jira_site` | `${user_config.jira_site}` |
| `standup_channel` | `${user_config.standup_channel}` |
| `standup_event` | `${user_config.standup_event}` |
| `async_standup_event` | `${user_config.async_standup_event}` |
| `repo_globs` | `${user_config.repo_globs}` |
| `session_cwd_regex` | `${user_config.session_cwd_regex}` |

A value that is empty, or still reads as a literal `${user_config…}`
placeholder (as it does when this file is read directly rather than loaded
as a plugin skill), is unset. Skip whatever depends on it, keep going, and
name the missing setting in the footer. Only `async_standup_event` is
expected to be empty for some users.

## Stage 0 — Resolve the day

`$ARGUMENTS` names the reference day (the standup being prepared for).
Empty means today. Resolve it with GNU date (`gdate` on macOS, `date`
elsewhere), which understands `tomorrow`, `last tuesday`, `10/28`, `Nov
3`:

```sh
gdate -d "${ARGUMENTS:-today}" +%F
```

If it fails to parse, ask rather than guess. If it lands on a weekend,
say so and use the next Monday.

Then fix three things:

- **REF** — the reference day.
- **PREV** — the last workday before REF. Skip weekends and company
  holidays, and keep walking back past days that are all-day
  out-of-office on the calendar (or where the user posted in Slack that
  they were out). On the first workday of a week — Monday, or Tuesday
  after a Monday holiday — PREV is the previous Friday.
- **CUTOFF** — REF's standup start time, from the calendar: the
  `standup_event` meeting, or on async days the `async_standup_event`
  reminder. With neither on REF's calendar, use 09:00 and say so.

The evidence window for **Yesterday** is PREV 00:00 → CUTOFF, so work done
the morning of standup counts, and so does anything over the weekend or a
holiday in between: a Monday window rolls Friday through Sunday into one
Yesterday. When the window spans more than one day, the header says
`covers <PREV>–<last day before REF>`, e.g. `covers Fri–Sun`.

REF is an **async day** when the `async_standup_event` reminder is on its
calendar and no `standup_event` meeting is.

Mode follows from REF against now:

- **today** — REF is today's date, whether run before or after standup.
- **past** — REF is before today's date. Reconstruct what the notes
  would have said then: cap every source at CUTOFF, and use Jira history
  (`status WAS ... ON`) rather than current status. Do not persist.
- **future** — REF is after today (e.g. `tomorrow`). The Yesterday window
  runs to now and is still open; mark the section `(so far)`.

## Stage 1 — Gather

Fire every source in one parallel batch. A source that fails, is
unauthenticated, or comes back empty degrades the notes; it never blocks
them. Track which ones failed for the footer.

| Source | Feeds | How |
| --- | --- | --- |
| Jira | Y, T, B | `searchJiraIssuesUsingJql`, cloudId `jira_site`. Y: `assignee = currentUser() AND status CHANGED DURING ("<PREV>", "<REF>")`. T: `assignee = currentUser() AND statusCategory = "In Progress"` (past mode: `status WAS "In Progress" ON "<REF>"`). B: flagged issues or status `Blocked`. Capture the transition, not just the title. |
| GitHub | Y, T, B | `gh search prs` with `--author @me` for merged, created, and updated in the window; `--reviewed-by @me` for candidate reviews given, then keep only PRs where `gh api repos/<owner>/<repo>/pulls/<n>/reviews` shows a review by `gh api user --jq .login` with `submitted_at` inside the window (`--reviewed-by` matches a review from any date); `--review-requested @me --state open` for reviews owed. Request `--json url` for links. Open PRs of theirs with failing checks or no review after a day are blocker candidates. |
| Git | Y | Unpushed work only; GitHub covers the rest. Expand `repo_globs`, dedupe worktrees by `git rev-parse --git-common-dir`, then per repo: `git log --branches --not --remotes --author=<work_email> --since=<start> --until=<end> --format='%h %cd %s' --date=format:'%a %H:%M'`. Skip repos with no output. |
| Claude Code | Y, B | `bash "${CLAUDE_PLUGIN_ROOT}/skills/standup/sessions.sh" "<PREV> 00:00" "<CUTOFF>" '<session_cwd_regex>'`. The regex must be anchored: a bare project name also matches scratchpad test sessions under `/private/tmp`. The cwd and branch name the ticket; the prompts say what the work was. A prompt about raising something at standup marks a question or blocker: read that session's last assistant reply for it. |
| Granola | Y, T | `list_meetings` over the window for decisions and commitments. Also find the previous `standup_event` note and read what the user said they would do — that is the baseline for reconciliation. |
| Calendar | Y, T | `list_events` for PREV (time spent with no artifact) and REF (meetings that shape today). All-day OOO events adjust PREV. |
| Slack | Y, T, B | `slack_search_public_and_private` with `from:<@slack_user_id>` over the window: unblocking others, testing handoffs, decisions. Separately, messages mentioning them that they haven't answered (T or B), with bots and notification channels (such as a Jira feed) excluded. Also their last `Y:`/`T:`/`B:` post in `standup_channel`, which sets the voice. |
| Gmail | T, B | One `search_threads` call over the window: `after:<PREV> before:<REF+1> -from:me -from:notifications@github.com -from:jira@<jira_site> -from:noreply -from:no-reply`. Don't add `in:inbox` or `category:` — filtered mail never reaches the primary inbox, so those can return nothing. Use only threads that ask something of the user; skip recruiters and newsletters. No usable email is a normal result, not a failure. |
| Graphiti | T | `search_memory_facts` for the previous standup episode (see Stage 4). Its Today items are the reconciliation baseline when Granola has none. Skip if no Graphiti server is configured. |
| Datadog | B | `search_datadog_incidents` for incidents active in the window that involve the user. Only an active incident earns a line. |

Fetch titles and status, not diffs or full transcripts. Open a Granola
transcript only when the note lacks a commitment that clearly happened.

## Stage 2 — Reconcile

Before writing anything, take the previous standup's Today items (from
Granola, Graphiti, or the last Slack post) and mark each **done**,
**partial**, or **dropped** against the evidence. Done items lead
Yesterday. Partial items carry into Today. Dropped items are mentioned
only if someone is waiting on them.

Then collapse evidence into work units: one unit per ticket or theme, not
per event. A Jira transition, three commits, a PR, and a Claude Code
session on the same issue key are one line.

## Stage 3 — Write

Print this, and nothing before it:

```
**Standup · <Ddd Mmm D>** — covers <Ddd>–<Ddd>, only when the window spans more than one day>

**Yesterday**
- [PROJ-412](https://example.atlassian.net/browse/PROJ-412) Billing export: fixed QA findings, ephemeral updated
  - QA by Sam + Priya
- Reviewed Lee's [api#3704](https://github.com/example/api/pull/3704), [#3705](https://github.com/example/api/pull/3705)
**Today**
- [PROJ-430](https://example.atlassian.net/browse/PROJ-430): start legacy migration, PR by EOD
- 14:00 PROJ-430 sync w/ Jo
**Blockers**
- none
```

Rules:

- At most four bullets per section, each under about 70 characters.
  Lead with the issue key when there is one. Drop the least important
  units before you exceed the limit. The limit counts visible text, not
  link URLs.
- Every Jira key and PR is a Markdown link. Jira:
  `https://<jira_site>/browse/<KEY>`. PRs: the URL from `gh`, labeled
  `<repo>#<n>`; later PRs from the same repo in one bullet can shorten to
  `#<n>`.
- Write in the user's voice, matched to their past posts in
  `standup_channel`. By default: terse, comma-joined clauses, no full
  sentences, no adjectives, e.g. `Revised + released DB migrations,
  prepped config backfill`.
- Order Yesterday by what teammates care about: shipped, then unblocked
  someone, then in-progress. Reviews and support for others belong here
  — they are invisible to Jira.
- Today lists commitments, not the whole backlog. Include a meeting only
  when it is about their own work: a sync or check-in on one of their
  tickets, a QA session for their feature, a design review they called.
  Leave out all-hands, team rituals, and recurring meetings with no
  ticket attached.
- A blocker names who or what it waits on: `PROJ-436 PR waiting on
  review from Alex since Thu`. A stale review request or an unanswered
  question is a blocker candidate; a vague worry is not.
- Names:
  - **Credit** — at most one indented sub-bullet per item, for someone
    who tested, unblocked, or carried part of the work. Only when a
    message, ticket comment, or PR shows their involvement. Never for
    routine reviews of the user's own PRs.
  - **Context** — naming whose PR they reviewed or whom they unblocked
    (`Reviewed Lee's api#3704`). Counts toward the line limit; drop the
    name before dropping a bullet.

After the notes, one line only if something failed or a setting is unset:
`_Missing: Gmail (unauthenticated), Datadog (timeout), repo_globs (unset)_`

**Async days.** Also print the Slack-ready version in their format, one
line per section with no hard wraps, in a fenced block they can paste:

```
Y: <yesterday items, comma-joined>
T: <today items>
B: <blockers or none>
```

Jira keys and PRs in the block are Markdown links, same URLs and labels
as the notes; Slack's composer turns them into links on paste. When
posting for the user with `slack_send_message`, pass the same Markdown.

Offer to post it to `standup_channel`. Never post without an explicit
yes. Don't offer in past mode.

Keep the evidence in mind after printing; follow-ups like "what was the
PR for that?" should be answered from it without refetching.

## Stage 4 — Persist

In **today** mode, write a Graphiti `add_memory` episode named `Standup
<REF>` holding the Today and Blockers lines verbatim. Tomorrow's run
reads it back in Stage 1. In **future** mode, persist only once the user
confirms the notes. Never persist in **past** mode. Skip this stage if no
Graphiti server is configured.

If the write fails, say so after the notes — Graphiti unavailable, the
error, and that the standup episode was not saved — and ask the user to
restore the connection. Do not fall back to a file.
