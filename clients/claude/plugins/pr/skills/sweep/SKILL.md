---
name: sweep
description: Sweep for pull requests awaiting your review, from a Slack channel and from GitHub review requests, and review the ones you haven't looked at yet with pr:review, staging a pending review on each. Use when asked to sweep PRs, catch up on PRs posted to Slack or requested on GitHub, check the PR channel, or batch review unseen PRs.
argument-hint: "[slack|github] [--channel=<name>] [--days=<n>] [--limit=<n>] [--comments=<none|post|submit>] [--level=<severity>] [--yes]"
---

Find pull requests waiting on your review, from a Slack channel and from
GitHub review requests, run `pr:review` on each in its own subagent, and
report back. State lives in Slack reactions and on GitHub. This skill keeps
no ledger of its own.

This is a convenience for staying on top of review requests. It is not a
system of record. A PR that slips through is a missed convenience, not a
failure worth engineering around.

## Arguments

| Argument     | Default         | Meaning                                                                                       |
| ------------ | --------------- | --------------------------------------------------------------------------------------------- |
| `slack` or `github` | both     | Positional. Sweep only that source.                                                           |
| `--channel`  | plugin setting  | Slack channel to sweep, with or without the leading `#`. Overrides the setting below.         |
| `--days`     | 7               | How far back to look for _new_ Slack posts. Bounds Slack discovery only. GitHub requests and resolution in stage 6 ignore it. |
| `--limit`    | 5               | Most PRs to review in one run. Held-back PRs are named in the digest.                         |
| `--comments` | `post`          | Passed to `pr:review`. `none` makes the run a dry run.                                        |
| `--level`    | `major`         | Passed to `pr:review`.                                                                        |
| `--yes`      | off             | Skip the confirmation prompt. Scheduled runs pass it.                                         |

### The Slack channel

The configured channel is `${user_config.slack_channel}`, from the `pr`
plugin's `slack_channel` setting. `--channel` overrides it.

If `--channel` wasn't passed and that value is empty, or still reads as a
literal `${user_config…}` placeholder (as it does when this file is read
directly rather than loaded as a plugin skill), there is no channel. Skip
the Slack source, keep going with GitHub, and say in the digest that Slack
was skipped, naming `--channel` and the plugin's `slack_channel` setting.
When only `slack` was requested and there is no channel, stop and say so.

## 1. Find candidates

### Slack

Resolve the channel to an id with `slack_search_channels`. Then let Slack do
the filtering:

```
in:#<channel> has:link -hasmy::eyes: after:<YYYY-MM-DD>
```

`hasmy::eyes:` matches your own reaction, so `-hasmy::eyes:` is exactly the
set you have not marked. Sort by timestamp, not relevance, and page until
the window is covered. If search returns nothing and you suspect indexing
lag, fall back to `slack_read_channel` and filter on the reactions it
returns inline.

A message you react to with `:eyes:` by hand is therefore skipped forever.
That is a feature: it is how you mute one.

Parse GitHub PR URLs from message text and from any attachment or block
content, since app-posted messages often put the link there rather than in
the body. Reduce each to `owner/repo#number`. Keep the mapping from message
to PRs: reactions apply to the message, so a message linking three PRs gets
one reaction reflecting all three.

### GitHub

```bash
gh search prs --review-requested=@me --state=open \
  --json repository,number,title,author,isDraft,url,createdAt --limit 100
```

This includes requests made to teams you're on. It isn't bounded by
`--days`: an open request is wanted however old it is.

### Merge

Combine both lists into one set keyed by `owner/repo#number`. One PR is
reviewed once per run, however many times and places it appeared. Record
each PR's source (`slack`, `github`, or `both`) and, for Slack, the
messages that carried it.

## 2. Decide what to review

For each PR, two cheap checks before spending a subagent:

```bash
gh pr view <owner>/<repo>#<n> --json state,isDraft,headRefOid
gh api repos/<owner>/<repo>/pulls/<n>/reviews \
  --jq '[.[] | select(.user.login == "'"$(gh api user --jq .login)"'") | .state]'
```

Skip, recording the reason, when:

- the PR is closed, merged, or unreadable;
- it is a draft;
- you have a `PENDING` review on it. A previous sweep staged it and it is
  waiting for you to submit;
- it came **only from Slack** and you have any submitted review on it.
  Skipping on any review of yours means a clean PR you never approved comes
  back next sweep, which is the correct nudge: go approve it.

A PR that GitHub currently requests from you is reviewed even if you
reviewed it before. GitHub clears the request when you submit a review and
adds it back when the author re-requests, so being requested means "look
again now". `pr:review` handles the earlier threads on a re-run.

Apply `--limit` after filtering, taking the **oldest** first: by the Slack
message's timestamp, or the PR's `createdAt` for a PR only GitHub found.
Selection has to run oldest-first or an old PR starves whenever new ones
arrive faster than the cap.

### Confirm before spawning

Print the surviving PRs, one per line, with enough to judge them: repo and
number, title, author, `+n/-n`, source, and how long ago it was posted or
opened. Size and author are what let you spot the one you would rather read
yourself.

Sort the list newest first, breaking ties on PR number ascending so a
message linking several stays in a stable order. This is the reverse of the
selection order above: the oldest are chosen, then shown newest first.
Choosing oldest-first prevents starvation, and reading newest-first matches
how you scan a channel. Use the same order everywhere the skill lists PRs,
including the digest.

Then ask with `AskUserQuestion`. Not in prose, and not by assuming.

- header: `Review PRs`
- question: `Review these <n> PRs?`
- options:
  1. `Review all <n>` — Stages a pending review on each. Nothing is
     submitted.
  2. `Dry run` — Reviews and reports, posts nothing. Same as
     `--comments=none`.
  3. `Skip this run` — Nothing is marked, nothing is reviewed.

Keep the list in the printed output rather than in the question text, so it
stays readable past four PRs. The free-text option covers naming a subset,
and an answer like "just 2141 and 2150" is honored as given.

Nothing has been marked at this point, and that is deliberate. Reactions
cannot be removed, so applying `:eyes:` before the answer would permanently
mark a batch the user declined. Confirm first, react second.

With `--yes`, skip the prompt and proceed as `Review all`. Without it and
with no one at the prompt, skip the run and say so: an unattended sweep
that reviews without being asked is the failure mode this prompt exists to
prevent, and a scheduled run should be passing `--yes` anyway.

## 3. Review

### Dispatch

Before reacting or spawning, resolve the posting flags. They apply to every
review in this run, so ask once here rather than having each subagent
prompt separately, which they cannot do unattended anyway. If `--comments`
was not passed, ask with `AskUserQuestion` using the same header, question,
and options as the `pr:review` skill's stage 6 prompt. If `--level` was not
passed and `--comments` is not `none`, ask the `--level` question in the
same call, again mirroring `pr:review`. Pass the resolved values explicitly
to every dispatch below.

For a PR that came from Slack, react `:eyes:` to its message first, then
dispatch. Reacting first is deliberate: it signals in the channel that the
PR is being looked at while the work is still running. A PR only GitHub
found has no message and gets no reaction.

**When exactly one PR survived filtering**, invoke `pr:review` directly in
this session rather than via subagent, with the resolved flags and
`--watch=off`. The output is fully visible and no rollup table is needed.
Skip the digest for that PR and go straight to stage 4.

**When two or more PRs**, spawn one subagent per PR, at most three at a
time. GitHub's secondary rate limits on mutations are real and twenty
concurrent reviewers will trip them.

Every subagent dispatch names the skill by its full name and pins every
flag:

```
Run the pr:review skill on <owner>/<repo>#<n>
with --comments=<value> --level=<value> --watch=off.
```

This is not optional. A subagent has nobody at the prompt, so an unflagged
`pr:review` falls through to `--comments=none`, does the entire review, and
posts nothing. The run would look successful and land no comments.

Ask each subagent to return only: PR, recommendation, comments staged,
comments skipped as already present, review URL, anything it listed as
`unverified`, and whether the review body was suppressed because it
appended to a bodyless pending review. Not its report. Ten full reports
defeat the point of fanning out.

If a review fails, react `:warning:` to its Slack message, if it has one.
Reactions cannot be removed, so the `:eyes:` cannot be taken back; the
warning is what keeps the message visible as needing attention.

## 4. Mark resolved reviews

Runs whenever the Slack source is active, including when stage 1 found
nothing new and under `--comments=none`. It writes no reviews, only
reactions, so a dry run still catches up the marks. Skip it when there is
no channel or only `github` was requested.

It is not bounded by `--days`. A PR reviewed a month ago can be approved
today, and a window that hides it would mean the message never resolves.
Search the channel's whole history for the unresolved set:

```
in:#<channel> hasmy::eyes: -hasmy::white_check_mark:
  -hasmy::arrows_clockwise: -hasmy::speech_balloon:
```

For each, check every PR the message links. Once all of them carry a
submitted review of yours, react with the most blocking outcome across
them:

| Your latest review  | Reaction             |
| ------------------- | -------------------- |
| `CHANGES_REQUESTED` | `:arrows_clockwise:` |
| `COMMENTED`         | `:speech_balloon:`   |
| `APPROVED`          | `:white_check_mark:` |

Precedence runs down that table. A commented review counts as resolved: it
is a deliberate way to leave feedback without gating the merge, not an
unfinished approval.

Scanning unbounded is cheap because the result set is self-limiting: it is
your unresolved queue, and every message that resolves leaves it
permanently. If it ever returns a large backlog, that is information rather
than a cost to optimize away.

Leave the message at `:eyes:` while any linked PR is still `PENDING` or has
no review at all. A message that flips outcomes as its PRs land one at a
time is worse than one that waits.

## 5. Report

One digest, grouped:

**Reviewed**: a table, one row per PR:

| PR | Source | Recommendation | Comments | Review |
| --- | --- | --- | --- | --- |
| [`<repo>#<n>`](<pr-url>) <title> | slack / github / both | request-changes / comment / approve-with-nits | `<n> staged` / `<n> posted` / `none` | [view](<review-url>) |

PR column: the linked text is `<repo-name>#<pr-number>`, followed by the PR
title as plain text. Comments column: `<n> staged` under `--comments=post`,
`<n> posted` under `--comments=submit`, `none` under `--comments=none`.
Review column: `[view](<url>)` when a review was created or appended to,
`—` when nothing was posted.

**Skipped**: with the reason: draft, pending review awaiting you, already
reviewed (Slack only), closed, merged, unreadable.

**Held back** by `--limit`.

**Failed**: with the error.

**Newly marked resolved**: with the outcome applied.

**Sources**: if Slack was skipped for want of a channel, say so, naming
`--channel` and the `slack_channel` setting.

Say the count of reviews left pending and unsubmitted, since nothing in
this skill submits them unless `--comments=submit` was passed. Submitting
stays a human act by default, and a batch that published reviews on
colleagues' PRs unattended is the one bad outcome available here.
