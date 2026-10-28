---
name: review
description: Review a pull request. Use when the user runs /pr:review, asks to review a PR, or wants feedback on changes in a pull request.
argument-hint: "[pr-number] [--comments=<none|post|submit>] [--level=<severity>] [--watch=<off|on>] [--fresh]"
---

Review pull request $ARGUMENTS and produce a review in two stages: build a
structured record of findings, write it to a JSON artifact, then render the
report from that artifact and nothing else. The same artifact can then be
rendered a second time, as inline comments on a GitHub review.

The two stages are the point. Reviewing straight into prose is what makes
successive reviews of the same diff disagree with each other. Judgments are
made once, into typed fields with closed vocabularies; the report is a
mechanical render of those fields.

## Local conventions take precedence

This skill is self-contained. Every rule it relies on is written here, so it
behaves the same in a repository it has never seen and does not quietly change
behavior when moved.

Where the host disagrees, the host wins. A rule in a user or project CLAUDE.md
that answers the same question as a rule here replaces it, and replaces only
it. The rest of the skill is unaffected.

Three qualifications keep that from becoming a licence to improvise:

- **Silence is not disagreement.** No rule on the point means the rule here
  stands. The existence of a CLAUDE.md is not a reason to soften a default.
- **The same question, not the same subject.** A host rule on commit messages
  does not govern comment length. Override only where the two speak to the
  same specific choice and give different answers.
- **Say so.** When a host rule displaces one of these, name both in the output.
  A silent override is indistinguishable from the skill misbehaving.

## Deciding options

Several points in this skill have more than one reasonable behavior. They are
all settled the same way, and a new one should follow this pattern rather than
inventing its own.

**One decision, one argument, one enum.** Each decision gets a single flag
whose values are its complete set of outcomes: `--comments=none|post|submit`,
not a scatter of booleans. Three booleans across two decisions can be combined
into states that mean nothing, and there is no honest way to spell "leave this
one to me" when absence is already load-bearing.

**An argument always wins.** When a flag carries a value, act on it and never
prompt. Flags are what let the skill run unattended.

**With no argument, ask with the `AskUserQuestion` tool.** Not in prose. A
question written as a sentence at the end of a long report is not a prompt: it
reads as a sign-off, it arrives after the user has stopped reading, and it
offers no options and names no flag. Reaching for text output here is the
likeliest way this mechanic fails, because writing the question feels like
having asked it.

One question per decision, never two decisions folded into one question. Where
several decisions come due at the same moment, put them in a single
`AskUserQuestion` call rather than a call each: the tool takes up to four
questions and renders them as tabs, so the user settles the whole set in one
interaction instead of being interrupted once per decision. Batch only what is
genuinely open. A decision a flag has already settled is not asked, and neither
is one a flag has already made moot.

Batching does mean a question can be answered and then turn out not to matter,
because a sibling answer mooted it. Discard that answer and say nothing about
it. One skippable tab is cheaper than the round trip that asking in sequence
would have cost.

If `AskUserQuestion` is unavailable, that is the unattended case below. Take the
default and say so; do not substitute prose.

**The default is the recommended option and the unattended fallback, and they
are the same value.** It leads the option list, it is what a headless run,
cron job, or subagent takes when there is no one at the prompt, and it is what
the documentation describes. Keeping these as one value is deliberate. When the
recommendation and the fallback disagree, the skill behaves differently
depending on who is watching.

**Ask when the answer is informed, not at invocation.** Prompting up front
forces a blind choice. Carry the decision until the user has what they need,
then ask. For posting, that means after the report is on screen. It also means
the options can quote real numbers from the artifact instead of describing
themselves in the abstract.

**The options mirror the flag values exactly**, one per value, no more and no
fewer, and each names the value that skips the prompt next time. The
interactive and unattended paths then cannot drift apart, and the prompt
teaches the flag.

**Say what each option costs**, not just what it does. Reversible and
irreversible options should not read alike.

**A cache is not a decision.** Reuse of prior work is settled by validating it,
not by asking. If the validation passes, reuse and say so; if it fails, rebuild.
Give it an escape-hatch flag for the user who does not trust the validation, but
do not spend a prompt on it. Only genuine forks in behavior earn a question.

**Report what was chosen without being asked.** When a run takes a default
because nothing was passed and no one could answer, say so in the output and
name the flag that would have changed it.

## 1. Resolve the PR

If a number is given in the arguments, use it. If not, try the current
branch's PR (`gh pr view` with no number resolves it). If that fails, run
`gh pr list`, show the open PRs, and ask which one.

Then collect metadata and the diff:

```bash
gh pr view <n> --json number,title,url,author,baseRefName,headRefName,\
headRefOid,state,additions,deletions,changedFiles,labels,body
gh pr diff <n>
```

If `state` is `MERGED` or `CLOSED`, stop immediately and tell the user
the PR is already merged/closed. Do not proceed with the review.

Record `headRefOid` as the reviewed sha. A review is only valid for one
commit, and naming it lets a later run tell whether the PR has moved.

## 2. Read beyond the diff

### Work from the PR's code

Fetch file contents at the PR's head SHA via the GitHub contents API. This
works for any repository without needing a local clone, and always returns
the code the PR actually contains:

```bash
gh api repos/<owner>/<repo>/contents/<path>?ref=<head_sha> \
  --jq '.content' | base64 --decode
```

Always specify `ref`. Omitting it returns the default branch, not the PR.

For CI results, which inform `unverified` items:

```bash
gh pr checks <n>
```

### What to read

Findings must be anchored in what the code actually does, not in what the
diff looks like. For each changed file, open the surrounding code: the
callers of changed functions, the schema behind changed queries, the tests
that cover the changed path.

Skip files that carry no review signal, and record each one with its
reason: generated output, lockfiles, vendored code, snapshots, binaries.
Skipping silently reads as having reviewed them.

## 3. Build finding records

Every finding is one record:

```json
{
  "id": "F1",
  "file": "routes/foo.js",
  "line": 212,
  "end_line": 214,
  "side": "RIGHT",
  "severity": "major",
  "category": "correctness",
  "confidence": "confirmed",
  "claim": "One sentence stating what is wrong.",
  "mechanism": "How it goes wrong and what breaks, naming the specific function, column, or path.",
  "evidence": ["src/db/schema.sql:41", "ran `npm test -- foo` → 3 failures"],
  "fix": "A single proposed change.",
  "suggestion": null,
  "duplicate_of": null,
  "posted": null
}
```

`line` and `end_line` anchor to the head commit; `end_line` equals `line`
for a single-line finding. `side` is `RIGHT` for added or context lines and
`LEFT` for removed ones. Both are GitHub anchor fields, consumed by stage 6
when posting inline comments.

`suggestion` holds a verbatim replacement for lines `line` through `end_line`,
at their real indentation, or `null`. See **When a finding earns a suggestion**
below.

`posted` is `null` until the finding is staged as a comment, and is written
back afterwards. See **Record what was posted** in stage 6.

### When a finding spans a range

Anchor a range when the defect has the shape of a block, and a point when it
has the shape of a point. The test is whether one line is more responsible for
the defect than its neighbours.

Use a range when:

- The finding is about a construct as a whole and no line inside it is the
  culprit: a memo and its dependency array, a `switch`, a `try`/`catch`, a
  chained query builder. "This memo recomputes on every render" is about the
  memo, not about the line the reader happens to be sent to.
- `suggestion` spans more than one line. This one is not a judgment call: the
  anchor must cover exactly the lines the block replaces.

Use a point when one line carries the defect: a wrong operator, a missing
`await`, an argument passed in the wrong position.

Set the range to the construct's own extent. Do not pad it out to a
comfortable window, and do not include a trailing blank line or closing brace
that is not part of what is wrong.

Widening a block-shaped defect to its real extent also makes the anchor
reproducible. When the defect is a block and the anchor is a point, *which*
point is arbitrary, so two runs over the same diff can disagree and the
deduplication in **Re-running** has to fall back to matching text. The range is
determined by the code and comes out the same every time.

### Severity

Apply these as rules, not as adjectives:

- **blocker** — data loss, credential or authorization exposure, or breaks
  currently-working behavior on a production path.
- **major** — produces a wrong result for a reachable input, or new
  branching logic with no test covering it.
- **minor** — correct, but violates a convention documented in CLAUDE.md or
  visibly established in the repo. Cite the precedent in `evidence`.
- **nit** — style or naming with no functional effect.

`blocker` and `major` are the merge-blocking tiers: both describe code that is
wrong, and neither should land as-is. `minor` and `nit` describe code that
works. That line, between `major` and `minor`, is what drives both the
recommendation and the `--level` default.

Emit at most five nits. Count the rest into `suppressed_nits` rather than
dropping them silently.

### Category

One of: `correctness`, `security`, `data-integrity`, `api-contract`,
`performance`, `test-coverage`, `convention`, `maintainability`.

### Confidence

Either `confirmed` (verified by reading the relevant code or running
something) or `probable` (a specific mechanism, but a step of it is
unverified). There is no lower tier on purpose. Anything you cannot get to
`probable` is not a finding: it goes to `observations` or is dropped.

### When a finding earns a suggestion

A suggestion block is a button that commits your code verbatim, frequently with
no further review. The test is therefore not whether the fix is short. It is
whether the author can click it without thinking. Set `suggestion` only when
all four hold, and `null` otherwise:

1. **Self-contained.** Committing it alone leaves the code correct. No
   companion import, helper, call site, or test is required. Length is not the
   issue here: a one-line suggestion that also needs an import is worse than
   prose, because clicking it produces a build error, while a twelve-line one
   that needs nothing else is fine.
2. **Determinate.** There is one defensible answer, not several. `>` should be
   `>=` is determinate. A better name for a variable is not: several are good
   and a suggestion presumes yours. Small fixes tend to be suggestible because
   they tend to be determinate, which is why length looks like the criterion
   and is not.
3. **Confirmed.** `confidence` is `confirmed`, never `probable`. A `probable`
   finding has an unverified step, which means types, names, or scope are being
   guessed at, and guessed code should not sit one click from the base branch.
4. **Contained.** The whole change fits between `line` and `end_line` at real
   indentation, and does not move the anchor.

Never write a partial suggestion. When a fix has two parts and only one fits
the range, a suggestion covering that part hands the author a half-fix that
looks complete. Prose covering both is better.

By category this mostly settles itself. `convention` and `nit` findings are
usually suggestible. `correctness` sometimes is. `test-coverage` almost never
is, because the fix is a new test somewhere the anchor cannot reach, and
neither are `maintainability` findings that ask for a different shape.

### Emission gate

A record is emitted only when all four hold:

1. It anchors to a line the diff touches.
2. It has a concrete failure scenario: inputs or state, then the wrong
   result.
3. `evidence` is non-empty.
4. It is not already covered by an earlier finding. When the same issue
   recurs, set `duplicate_of` to the first finding's id, keep the anchor and
   any `suggestion` (the mechanical fix may differ per site), and do not
   restate the reasoning.

Anything failing the gate is not a quiet omission. If it is worth saying at
all, it becomes one line in `observations`.

### Sort and ids

Sort findings by severity descending (blocker, major, minor, nit), then
`file` ascending, then `line` ascending. Assign `F1`..`Fn` after sorting, so
the same diff and the same findings produce the same ids across runs and
back-references stay stable.

## 4. Write the artifact

Write the complete record to `review-pr-<n>.json` in the session scratchpad
directory. Outside the repo, so it cannot be committed by accident.

```json
{
  "pr": {
    "number": 0,
    "title": "",
    "url": "",
    "author": "",
    "base": "",
    "head": "",
    "head_sha": "",
    "state": "",
    "additions": 0,
    "deletions": 0,
    "changed_files": 0,
    "labels": []
  },
  "reviewed_at": "",
  "summary": "",
  "scope": {
    "reviewed": ["path"],
    "skipped": [{ "file": "", "reason": "generated" }]
  },
  "findings": [],
  "observations": [{ "note": "", "file": null }],
  "unverified": [{ "item": "", "reason": "" }],
  "earlier_threads": [
    {
      "thread_id": "PRRT_…",
      "file": "",
      "claim": "",
      "status": "addressed",
      "commit_referenced": true,
      "resolved": false
    }
  ],
  "suppressed_nits": 0,
  "recommendation": ""
}
```

`summary` is at most three sentences on what the PR does. `unverified` is
what could not be checked and why (no database, external service, manual QA
path). Leaving it out makes unchecked things read as checked.

`earlier_threads` holds your unresolved threads from earlier submitted
reviews, each marked `addressed` or `open`. See **Threads from earlier
reviews** under **Re-running**. `resolved` starts `false` and is written back
once the thread is resolved, the same way `posted` is.

`recommendation` is derived, not judged, from the merge-blocking line: any
blocker or major gives `request-changes`, and anything else gives `approve`.
It is advice to a human that maps directly to the GitHub event used when
submitting.

Two values, because the line from stage 3 has two sides. A review that found
only minors and nits found code that works, and withholding approval over a
stale doc comment misreports that. The findings carry the detail; the verdict
carries whether it should land.

`comment` is an event, not a recommendation. It is what a self-authored PR
submits under, since GitHub rejects self-approval — see the mapping in stage 6.

## 5. Render the report

Render from the artifact only. Introduce no finding, caveat, or
qualification at render time that is not in a field. Every section appears
every time; an empty one says `None.` rather than disappearing.

```
## [PR #<number> — <title>](<url>)
<base> ← <head> · <author> · <head_sha> · +<additions>/-<deletions> across <changed_files> files

### Summary
<summary>

### Scope
Reviewed: <paths>
Skipped: <file> (<reason>)

### Findings
**[F1] blocker · correctness · routes/foo.js:212**
<claim>
<mechanism>
<fix>
<suggestion, as a fenced block, when present>

### Earlier threads
Addressed: <file> — <claim>
Open: <file> — <claim>

### Observations
### Unverified
### Recommendation
<recommendation>
```

The heading is a markdown link on `pr.url`, so the PR is one click away from
the first line. Use a markdown link rather than emitting an OSC-8 escape
directly: where the renderer converts it, the URL collapses into the title, and
where it does not, the raw URL is still on screen and every modern terminal
makes it clickable. A hand-rolled escape sequence has no such fallback.

For a duplicate, render the claim line and then `Same as <file>:<line>.` in
place of the mechanism, plus its suggestion if it has one.

When `suppressed_nits` is above zero, close the findings section with
`<n> further nits suppressed.`

Skip the hedging and the compliments. State each finding once and stop.

## 6. Post the review

`--comments` decides what reaches GitHub. When it was not passed, it is asked
under **The prompt** below, once the report is on screen and never at
invocation, so the user is deciding whether to post *these* findings rather
than answering in the abstract.

| `--comments` | Effect |
| --- | --- |
| `none` | Ends at the rendered report. Nothing touches GitHub. |
| `post` | Findings become inline comments on a pending review, visible only to you. Appends to your open review on that PR if one exists. |
| `submit` | Stages, then publishes. Everyone is notified at once and it cannot be undone. |

### Which findings become comments

`--level` sets the lowest severity that earns an inline comment. Findings at
that level or above are commented; everything below is listed in the review
body instead.

| `--level` | Commented |
| --- | --- |
| `blocker` | blockers |
| `major` | blockers, majors |
| `minor` | blockers, majors, minors |
| `nit` | everything |

Unset, it rides in the same call as the `--comments` question, as the second
of the two. It is dropped when `--comments=none` arrived as a flag: nothing is
being posted, and that is knowable before the prompt is built. When the
*answer* turns out to be `Don't post`, the threshold answer is discarded
without comment.

It is also dropped when every level would produce the same total, most often
because there are no findings, or because every finding is a blocker. The
choice then changes nothing about what is posted, so asking it spends a tab on
a decision that does not exist. Apply the `major` default and say in the output
that the threshold was not asked because every level yields <n> comments,
naming `--level` as the flag that would set it.

`major` is the default because it is the merge-blocking line and the unattended
fallback. It does not lead the option list, though: these options are a scale,
and a scale reads in order. See the second question under **The prompt**.

The default is the merge-blocking line from stage 3, so out of the box a line
gets a comment when something on it has to change before the PR lands. Findings
that only ask the author to consider something do not interrupt the diff.
Lower the level to `minor` or `nit` to include those, or raise it to `blocker`
on a large diff where only the worst should surface inline.

This gates one surface only. The terminal report and the artifact always carry
every finding, and the threshold is not recorded in the artifact: it is how a
review is posted, not part of what the review found. The same artifact can be
posted twice at two levels without being rebuilt.

Findings below the level are not posted. They stay in the terminal report
only.

Post the findings as one review, never as standalone comments on
`POST /pulls/<n>/comments`. Batching gives one notification instead of one per
finding, and unanchored findings need a review body to live in. Standalone
comments are for replying to an existing thread, which is follow-up work rather
than review.

Posting renders the *same* artifact to a second surface. Do not re-review, do
not re-judge severity, and do not introduce a finding that is not already in
the artifact.

### The prompt

All open decisions go in one `AskUserQuestion` call, up to three questions.
They render as tabs, so posting, threshold, and watching are settled in a
single interaction. Include only what is still open: a flag-supplied value is
never asked, and the threshold is dropped when `--comments=none` came in as a
flag or when every level yields the same total. The watch question has its own
drop rules, under the third question.

Never drop individual levels from the threshold question, even when a level
adds nothing. The options mirror the flag values, a zero is itself
information, and pruning can leave fewer than the two options the tool
requires. The question is asked whole or not at all.

**Derive the event before writing the prompt.** Determine the GitHub event once,
explicitly, before constructing the questions. Check `recommendation` and
whether the PR author matches your login (`gh api user --jq .login`):

- `approve` + author ≠ you → `APPROVE`
- `request-changes` → `REQUEST_CHANGES`
- anything else, including `approve` on your own PR → `COMMENT`

Write the result down, then substitute it into the option label below. Do not
derive the event inline while composing the question — that is what leads to
writing `COMMENT` when `APPROVE` is correct.

Ask them exactly like this, so there is nothing to improvise.

First question:

- header: `Posting`
- question: `Post this review to GitHub?`
- options, in this order:
  1. `Don't post` — Ends at the report above. Nothing reaches GitHub.
     `--comments=none`.
  2. `Stage as pending` — Stages <n> comments on a review only you can see.
     Reversible. `--comments=post`.
  3. `Stage and submit (<event>)` — Publishes it. Notifies everyone at once and
     cannot be undone. `--comments=submit`. Substitute the event derived above
     for `<event>`.

  When `earlier_threads` has addressed entries, add
  `Resolves <m> addressed threads.` to options 2 and 3. See **Threads from
  earlier reviews**.

Second question:

- header: `Comment level`
- question: `Minimum severity for inline comments?`
- options: one per row of the `--level` table above, always in severity order,
  `blocker`, `major`, `minor`, `nit`. This is the one exception to the default
  leading the list: a threshold is a scale, and reordering it to put `major`
  first makes the counts read out of sequence. Mark the default in its
  description instead.

Each label carries the total comments that level would produce, and every
level after the first also carries its delta, `(+N)`, how many of those it
adds over the level above it. The total is what the choice costs; the delta is
what it buys. `blocker` has no level above it, so its total is its delta and
it gets no `(+N)`. Totals are cumulative, so each is the previous total plus
this level's delta. Count from the artifact, which exists by now, so these are
real numbers. A duplicate is still a comment and counts at its own severity.

Align the labels into columns, since the options render in a monospace
terminal and aligned numbers can be scanned down rather than read across. Pad
the severity to seven characters (the width of `blocker`), right-align the
total to the widest total, and separate columns with two spaces. Always write
`comments`, even for a count of one, so the column edge stays straight:

```
blocker   0 comments
major     3 comments  (+3)
minor     3 comments  (+0)
nit       3 comments  (+0)
```

Labels are plain text. Do not try to mute the delta with ANSI escapes or
markup: the tool offers no styling field, and an escape that is not rendered
lands raw in the label and in the answer that comes back.

Descriptions, in the same order:

- `blocker`: `Blockers only. --level=blocker`
- `major`: `Blockers and majors. Default. --level=major`
- `minor`: `Blockers, majors, minors. --level=minor`
- `nit`: `Everything. --level=nit`

Third question:

- header: `Watch`
- question: `Monitor this PR for changes?`
- options, in this order:
  1. `No` — Ends once the review is submitted. `--watch=off`.
  2. `Yes` — Re-reviews each new push and posts it the same way, without
     asking again. Every round that submits notifies everyone.
     `--watch=on`.

Ask it when there is a review to follow up on, from either of two sources:

- **This run.** The derived event is `REQUEST_CHANGES` or `COMMENT`, and the
  review may be submitted: `--comments=none` and `--comments=post` did not
  come in as flags.
- **An earlier run.** Your latest submitted review on the PR is
  `CHANGES_REQUESTED` or `COMMENTED`. This covers a re-run on a PR you have
  already reviewed, where this run may post nothing new.

```bash
me=$(gh api user --jq .login)
gh api --paginate repos/<owner>/<repo>/pulls/<n>/reviews \
  --jq "[.[] | select(.user.login == \"$me\" and .state != \"PENDING\")]
        | last | .state"
```

Drop it when neither source applies, when `--watch` was passed, and when a
watcher for this PR is already running in the session. Name the running
watcher in the output instead of asking.

When only this run qualifies and the *answer* to the first question is
anything but `Stage and submit`, discard the watch answer without comment: a
review nobody else can see has nothing to follow up on. When an earlier review
qualifies, the watch answer stands whatever the first answer was.

A watch started on an earlier review has no posting choice from round one to
carry forward, since this run may have answered `Don't post`. Its rounds post
with `--comments=submit` and the level chosen in this run, `major` if none
was. Say so in the `Yes` option's description when this is the case.

Option one of the first question leads because it is what an unattended run
takes, not because it is usually right. `<n>` is the comment count at the level
that will actually apply: the `--level` flag when one was passed, otherwise the
`major` default. It is therefore exact whenever the second tab is left alone,
and the second tab is where the other levels' counts are shown.

Everything below runs only under `post` and `submit`.

### Preconditions

Re-read the artifact rather than working from memory. Then confirm the PR has
not moved:

```bash
gh pr view <n> --json headRefOid --jq .headRefOid
```

If it no longer matches `pr.head_sha`, the PR moved mid-run. Stop and tell the
user: the findings are anchored to lines that may no longer exist. Rebuild the
artifact rather than posting stale anchors. On a normal run this check passes,
because **Re-running** already invalidated any artifact built against an older
sha.

Then look for a pending review you already own:

```bash
gh api repos/<owner>/<repo>/pulls/<n>/reviews \
  --jq '.[] | select(.state == "PENDING") | {id, node_id}'
```

GitHub allows only one pending review per user per PR and rejects a second with
a 422, so this determines which path to take: create a new review when there is
none, add to the existing one when there is.

### Validate every anchor first

The reviews API is all-or-nothing: one comment on a line outside the diff
returns 422 and the entire review fails to post. Before building the payload,
confirm each finding's `file` and `line` fall inside a hunk of the diff on the
matching side.

A range has to clear more than its endpoints. `line` and `end_line` must sit in
the *same* hunk, with `end_line` greater than `line`, and every line between
them commentable on that side. A range that reaches across a hunk boundary is
rejected even though both ends are individually valid. When one fails that
test, narrow it to the single line that best carries the defect rather than
demoting the finding, and note the narrowing in the output.

A finding that fails validation is not dropped and does not block the post.
Add it to the review body as a brief comment in the same two-paragraph format
as inline comments, prefixed with its `file:line` so the author can locate it.

### Render the comment bodies

A comment body is a render of a severity label, then `claim`, then
`mechanism`, then `fix`, in that order and with nothing else in it.

**Label.** The first line is `severity · category` in bold, exactly as the
report shows it minus the id: `**major · correctness**`. It sits directly
above the claim, separated by a single newline rather than a blank line.
GitHub's hardbreaks turn that newline into a line break, so the label stacks
over the claim as one paragraph and the two-paragraph shape below holds. The
label tells the author how much weight the comment carries before they read
it, which the prose alone leaves them to infer.

**Shape.** The `claim` stands alone as the first paragraph, under its label. A
blank line, then the `mechanism` and the closing question as the second. That
single break is the only structure a comment gets, and it exists so the eye
has somewhere to land: the first sentence is the headline.

**Budget.** Under 80 words. No sentence over 20. Let the sentence count fall
out of those two numbers rather than the reverse: do not merge clauses to hit a
lower count, and do not pad to reach a higher one. A cap on sentences alone
just moves the density inside them.

- **Open with the defect alone.** What is wrong, in plain language. Not what
  the code does, not the mechanism, not what it costs. A conjunction in the
  first sentence means two ideas are welded together: move the second one down.
- **Give the trigger and the outcome, not the path between them.** Do not walk
  the call chain, and do not narrate intermediate states either. "The flag
  resolves after the query fires, so the key changes and the feed drops back
  into a loading state" replaces a four-step trace and loses nothing the reader
  needed.
- **Exactly one supporting fact** from `evidence`. Not the strongest two: the
  strongest one. A second precedent makes the reader weigh two arguments for a
  conclusion they had already accepted.
- **Cite evidence, do not transcribe it.** Never enumerate a list inline to
  establish something the reader will take on trust. "Both memos take the same
  four arguments" carries exactly what naming all four carries. `evidence` is
  what makes a finding checkable; it is not what makes a comment readable.
- **At most four backticked identifiers,** each named once. Use a pronoun or a
  short noun phrase after the first mention. The comment is anchored to a line,
  so the reader can already see the function they are standing in: naming it
  back to them spends a slot on nothing.
- **No invented example values.** Tracing two placeholder ids through makes
  the reader hold state for no gain. Say "the old id" and "the new one": they
  have the diff open.
- **Close with `fix` as a question** that proposes it, "Can we ...?" or "Could
  this ...?", never a directive. One fix, not a menu. Under 15 words, and it
  carries nothing but the fix: no precedent, no rationale, no justification. If
  a precedent matters, it belongs in the mechanism. Name what it acts on, "drop
  this file" rather than "drop it". Leave out any hedge about the finding being
  void: the question invites that reply on its own.
- **No em-dashes.** Use a period or a colon.
- **No hedging and no compliments.** State it once and stop. No trailing
  "which is ..." clause restating the point just made.

Three points diverge from the terminal render, and are the easiest to get wrong
by carrying a habit across:

- **No id.** The report leads with `[F1] blocker · correctness`; the comment
  leads with `**blocker · correctness**`. Ids are local to the artifact and
  mean nothing to the author.
- **No hard wrapping.** GitHub renders comment bodies with hardbreaks on, so
  every newline becomes a literal `<br>`. Write one line per paragraph. This
  holds even though this file is wrapped at 80 and the body is staged in a
  file first: the destination decides, not the container.
- **No headings, no bullets, no other labels.** The report uses them; the
  comment is the severity label and two paragraphs of prose and nothing else.

A finding with `duplicate_of` set renders as its label and claim followed by
`Same as <file>:<line>.` and nothing else, plus its own suggestion block when
the mechanical fix differs at that site. Reference by file and line, not by
comment link: comments in an unsubmitted review have no stable URL yet.

When `suggestion` is present, emit it as a `suggestion` fenced block. The
comment must be anchored to exactly the lines the block replaces, so its
`start_line`/`line` must equal the record's `line`/`end_line`.

The block does not change the prose around it. A suggestion is a directive in
form, so the comment still closes on the question that proposes it. Do not
restate the change in words the block already makes.

### Check each body before staging

Every rule above is countable, so count them. A body failing any of these is
rewritten, not posted, and not posted with an apology either.

- Opens with the `**severity · category**` label, then a single newline.
- Under 80 words.
- Longest sentence under 20 words.
- At most four backticked identifiers, none repeated.
- No conjunction joining two ideas in the first sentence.
- One blank line, after the claim.
- Closing question under 15 words, naming its object.
- Exactly one supporting fact.

A duplicate is exempt from the word and sentence budget: it is a claim and a
back-reference, and it should stay that short. A body carrying a suggestion
block counts only its prose. The label is not counted toward any budget.

Density is the failure mode here, not length. A comment that satisfies a
sentence count by packing five clauses into three sentences is worse than one
that takes five short sentences to say the same thing.

### Stage: no pending review yet

Write the payload to the session scratchpad as `review-pr-<n>-post.json`:

```json
{
  "commit_id": "<pr.head_sha>",
  "body": "<review body>",
  "comments": [
    { "path": "routes/foo.js", "line": 212, "side": "RIGHT", "body": "..." },
    { "path": "src/x.js", "start_line": 10, "start_side": "RIGHT",
      "line": 14, "side": "RIGHT", "body": "..." }
  ]
}
```

`start_line` is omitted for single-line findings. For a range, `line` is the
*end* of the range, not the start.

Omitting `event` is deliberate: it leaves the review pending. Post it with:

```bash
gh api repos/<owner>/<repo>/pulls/<n>/reviews --input review-pr-<n>-post.json
```

The review body contains only findings that could not be anchored to a diff
line, each rendered the same way as an inline comment. The terminal report
carries the summary, observations, unverified items, and suppressed-nit count.
When every finding has a valid anchor, omit the body entirely — do not
substitute a placeholder or summary sentence.

### Stage: a pending review already exists

Add to it rather than replacing it. It may hold comments the user wrote by
hand, and deleting it would discard them along with every anchor. The one
exception is a pending review left over from an older commit, covered under
**Re-running**.

List what it already holds, and combine that with your submitted comments on
the PR, per **Re-running**. Pending comments are not public and so do not
appear in the PR-wide list.

Read them over GraphQL, not REST. The REST endpoint
`/pulls/<n>/reviews/<id>/comments` returns `line`, `start_line`, and `side` as
`null` for every comment in a pending review, populating only `position`. The
anchors themselves are fine; REST just will not report them until the review is
submitted. Deduplicating against that response compares every finding against a
null line, matches nothing, and posts the whole review a second time.

```bash
gh api graphql -f query='
  query($owner: String!, $repo: String!, $pr: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $pr) {
        reviews(last: 5, states: PENDING) {
          nodes { id comments(first: 100) {
            nodes { id path line startLine originalLine }
          } }
        }
      }
    }
  }' -f owner=<owner> -f repo=<repo> -F pr=<n>
```

The `id` on each comment is its `node_id`, so this same response feeds the edit
mutation below. A comment whose `line` differs from its `originalLine` has been
shifted by a later commit; one whose `line` is null is outdated, which is the
condition **Re-running** prompts on.

Skip any finding already commented on, matching as **Re-running** describes:
on `file` plus the defect the claim states, not on an exact line match. Do not
treat changed wording as a new comment: that is an edit, handled below. Report
the skipped count rather than staying silent about it.

Add each remaining finding with the GraphQL mutation, which takes the pending
review's `node_id` and so attaches the thread to it rather than publishing a
standalone comment:

```bash
gh api graphql -f query='
  mutation($review: ID!, $path: String!, $line: Int!, $body: String!) {
    addPullRequestReviewThread(input: {
      pullRequestReviewId: $review, path: $path, line: $line,
      side: RIGHT, body: $body
    }) { thread { id } }
  }' -f review="<node_id>" -f path="<file>" -F line=<line> -f body="<body>"
```

The REST reviews endpoint cannot do this: it only creates whole reviews.

For a range, add `startLine` and `startSide` to the mutation input, where
`startLine` is the record's `line` and `line` is its `end_line`. The GraphQL
input inverts the record's naming, so read that mapping twice. Set `side` and
`startSide` to `LEFT` for a finding on a removed line; do not hardcode `RIGHT`
in the query string, since a `LEFT` finding then posts against the wrong side
of the diff without erroring.

### Record what was posted

The append branch sends one mutation per finding and writes no payload file, so
without this step nothing on disk answers "what did we actually post". Append a
`posted` block to each finding in the artifact as its thread is created:

```json
"posted": { "review_id": "PRR_…", "thread_id": "PRRT_…", "line": 407 }
```

`posted` is the artifact's only mutable part. It records where a finding went
rather than what it says, so writing it back does not make the review itself
non-deterministic. A re-run in the same session then skips on `posted` alone
and never has to match text.

### The review body on an existing pending review

Adding threads does not touch the review body, and a pending review with an
empty body cannot be given one: `updatePullRequestReview` rejects it with
`Could not edit a review with a missing body`. The body has to be supplied on
the submit call instead.

Under `--comments=post` against a bodyless pending review, any unanchored
findings will not reach GitHub until the review is submitted. Say so, and keep
the prepared body in the artifact for whenever the review is submitted.

When the pending review already has a body and the artifact's differs, show the
user both and let them choose rather than silently replacing it.

### Submit

Staging is private; submitting is not, and it cannot be reversed. Deleting
comments afterward does not recall the notifications.

Under `--comments=post`, stop here. Report the review URL, how many comments
were staged, how many were skipped as already present, how many fell below
`--level`, and that the review stays pending until submitted. The review URL
is `https://github.com/<owner>/<repo>/pull/<n>#pullrequestreview-<review_id>`
(use the numeric `id` from the review creation response, not the node_id).
Always end the response with this as a markdown link on its own line.

Under `--comments=submit`, publish it. The decision was already made, by flag
or at the prompt, so do not ask a second time:

```bash
gh api repos/<owner>/<repo>/pulls/<n>/reviews/<review_id>/events \
  -f event=<event> -f body="$(cat <body-file>)"
```

Pass `body` whenever the pending review has one and the review is bodyless,
which is every review built by the append branch. This is the only point at
which such a review can be given one, so omitting it here permanently discards
any unanchored findings.

Submitting requires an event; there is no publish-without-verdict. Map
`recommendation` to it:

- `request-changes` → `REQUEST_CHANGES`
- `approve` → `APPROVE`, unless the PR author matches your GitHub login
  (`gh api user --jq .login`), in which case use `COMMENT` (GitHub rejects
  self-approval)
- anything else → `COMMENT`

Always end the response with the review URL as a markdown link on its own line:
`https://github.com/<owner>/<repo>/pull/<n>#pullrequestreview-<review_id>`.

### Resolve addressed threads

Under `post` and `submit`, resolve every `addressed` entry in
`earlier_threads` as **Threads from earlier reviews** describes. Do it after
staging under `post` and after submitting under `submit`, so a failed post
leaves the threads as they were. Under `none`, nothing touches GitHub: the
report lists them and stops. Report how many threads were resolved, and how
many of those got a reply.

Under `--watch=on`, start the watcher from stage 7 immediately after
submitting, before writing that response.

### Editing a staged comment

Comments in an unsubmitted review are not reachable through the REST review
comment endpoint: `PATCH /repos/<owner>/<repo>/pulls/comments/<id>` returns 404
until the review is submitted. Reword them with the GraphQL
`updatePullRequestReviewComment` mutation against the comment's `node_id`,
which preserves the review id and every anchor:

```bash
gh api graphql -f query='
  mutation($comment: ID!, $body: String!) {
    updatePullRequestReviewComment(input: {
      pullRequestReviewCommentId: $comment, body: $body
    }) { pullRequestReviewComment { id } }
  }' -f comment="<node_id>" -f body="<body>"
```

Collect the node ids from the listing in the previous section.

Never delete and recreate the review to fix wording: it discards every anchor.

## 7. Watch the PR

Runs only under `--watch=on`, and only when a submitted review exists: one
from this run, or an earlier one per the third question in stage 6. The
default is `off`, which is also what an unattended run takes: a watcher nobody
asked for keeps publishing reviews long after anyone is reading them.

Start the watcher at the end of the run either way, with `reviewed` set to the
head this run reviewed. Under **A round**, an earlier review's findings are
reconciled from GitHub rather than from a prior artifact: each of your
unresolved threads on the PR stands in for a `posted` finding.

### The watcher

Start a background shell with the Bash tool's `run_in_background`. It polls,
and exits the moment there is something to act on; its exit is what wakes the
session. Do not poll from the foreground or schedule short wakeups instead.

```bash
reviewed=<pr.head_sha>
while (( SECONDS < 86400 )); do
  sleep 300
  read -r state head < <(gh pr view <n> --json state,headRefOid \
    --jq '"\(.state) \(.headRefOid)"') || continue
  if [[ "${state}" != "OPEN" ]]; then
    echo "closed ${state}"; exit 0
  fi
  [[ "${head}" == "${reviewed}" ]] && continue
  # Let a burst of pushes settle before reviewing any of them.
  sleep 300
  if [[ "$(gh pr view <n> --json headRefOid --jq .headRefOid)" == "${head}" ]]
  then
    echo "moved ${head}"; exit 0
  fi
done
echo "expired"
```

The settle wait matters. Authors often push a fix in two or three commits, and
reviewing the first one alone raises findings the second already resolves.

### On wake

The watcher prints one of three outcomes:

- `closed MERGED` or `closed CLOSED`: stop. Say so, and do not restart.
- `expired`: stop. Say the watch lapsed after 24 hours and that
  `/pr:review <n>` resumes it.
- `moved <sha>`: run a round, below.

A failed `gh` call is retried by the loop rather than ending the watch, so a
network blip does not read as a closed PR.

### A round

1. Rename the artifact to `review-pr-<n>.<old sha7>.json` so the prior round
   survives the rebuild.
2. Run stages 1 through 5. The sha has moved, so **Re-running** rebuilds the
   artifact, and deduplication keeps findings already commented on out of the
   new review.
3. Reconcile your earlier threads per **Threads from earlier reviews**. Within
   the session, the prior artifact's `posted` blocks name the threads directly,
   so no text matching is needed for those.
4. Resolve the `addressed` ones the same way. Leave `open` threads untouched:
   the comment already says what is wrong.
5. Post with the `--comments` and `--level` chosen in round one. Do not prompt
   again; the watch answer covered every round. Submit only when there is
   something to say: new comments, or a recommendation that changed since the
   last submitted review. Replies alone do not justify an empty review.
6. Restart the watcher with `reviewed` set to the new head, unless the stop
   condition below holds.

An `open` finding still counts toward the recommendation even though it is not
re-posted, so a PR that ignores a requested change stays at
`request-changes`.

### When the watch ends

Stop after any round whose recommendation is `approve`, once that review is
submitted. Nothing is left to follow up on.

Report each round in a few lines: the new sha, findings addressed, findings
still open, new findings, the event submitted if any, and the review URL as a
markdown link on its own line. The full report from stage 5 is still rendered;
this summary closes it.

## Re-running

A second run against the same PR must not duplicate the first. Three kinds of
state survive a run, and each is reconciled differently.

### The artifact is a cache

If `review-pr-<n>.json` exists for this PR and its `pr.head_sha` matches the
live `headRefOid`, reuse it. Do not re-review: the skill's claim is that the
same commit yields the same findings, and re-deriving them contradicts it while
costing a full pass. Report that the artifact was reused and name `--fresh`,
which forces a rebuild.

Any other case rebuilds: no artifact, a different PR, or a sha that has moved.
This is what makes a re-run after new commits do the right thing without being
told.

The scratchpad is per-session, so a run in a new session finds no artifact and
always re-reviews. That is a known limit, not a bug to route around by writing
the artifact somewhere durable: a stale artifact is worse than a slow one.

Changing only `--level` or `--comments` on a re-run is the case this is for.
Both are applied at render and post time, so neither invalidates the artifact.

### Comments you have already posted

Findings are deduplicated against every comment you have already left on the
PR, not just the ones in the open pending review, whether pending or submitted
and whether or not the thread has been resolved.

**Key on the finding, not the line.** Two runs can anchor the same defect to
different lines: both may be valid anchors inside the same hunk, and a rebuilt
artifact may pick a different one. A finding already commented at line 383 and
re-anchored to 407 on the next run is the same finding, and an exact line match
will not see it. Match on `file` plus the defect the claim states, comparing
against the first sentence of each existing comment body after its leading
`**severity · category**` line, which is that comment's claim by construction.
Comments posted before the label was introduced have no such line; their
first sentence is the claim. Do not treat a severity or category that differs
from the existing label as a new finding: the defect is the match key. Treat
an exact line match as corroboration, not as the test.

Where a match is judged rather than exact, say so in the output and name both
lines. That is the one place this stage cannot be made mechanical, so it should
at least be visible.

```bash
me=$(gh api user --jq .login)
gh api --paginate repos/<owner>/<repo>/pulls/<n>/comments \
  --jq ".[] | select(.user.login == \"$me\") | {path, line, in_reply_to_id}"
```

Combine that with the pending review's own comments, which are not public and
so do not appear in the PR-wide list. Read those over GraphQL, per the append
branch in stage 6: the REST listing reports their `line` as null.

A run that has already staged comments records where each one landed, so a
re-run within the session needs no matching at all. See **Record what was
posted** below.

Counting a resolved thread as already-commented is deliberate. It means a
regression at exactly the same line goes unremarked, which is the rarer and
cheaper failure: the alternative re-raises every previously-settled point on
every run.

A comment from *another* reviewer at the same anchor does not suppress yours.
Two people reaching the same conclusion independently is signal, and swallowing
it silently is worse than the duplication. Note the overlap in the output.

### A pending review older than the current head

When a pending review exists and the PR has advanced since its comments were
written, its anchors point at a commit that is no longer head. GitHub keeps
those comments and marks them outdated rather than moving them.

Report how many of its comments are outdated and ask whether to append to it
anyway or discard it and stage fresh. This is a genuine fork, so it earns a
prompt. Discarding a pending review is allowed, and only a pending one:

```bash
gh api -X DELETE repos/<owner>/<repo>/pulls/<n>/reviews/<review_id>
```

Never do this to fix wording, and never without asking: it destroys any comment
the user staged by hand.

### Threads from earlier reviews

Every run reconciles your unresolved threads from earlier submitted reviews,
watched or not, and in a new session as well as the same one. The source is
GitHub, not a prior artifact, so the scratchpad being per-session does not
matter here.

```bash
gh api graphql -f query='
  query($owner: String!, $repo: String!, $pr: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $pr) {
        reviewThreads(first: 100) {
          nodes { id isResolved path comments(first: 20) {
            nodes { author { login } body pullRequestReview { state } }
          } }
        }
      }
    }
  }' -f owner=<owner> -f repo=<repo> -F pr=<n>
```

Keep the threads that are unresolved, whose first comment is yours, and whose
review is not `PENDING`. A pending review's threads belong to this run's
staging, not to an earlier review. Leave other reviewers' threads alone.

Mark a thread `addressed` when the rebuilt artifact has no finding matching
it, and `open` when one does. Match on file plus claim, as **Comments you have
already posted** describes. Write each one to `earlier_threads`. This is the
mirror image of deduplication: the same match that keeps a finding from being
posted twice is what shows its thread is still open.

Resolve an `addressed` thread with the `resolveReviewThread` mutation:

```bash
gh api graphql -f query='
  mutation($thread: ID!) {
    resolveReviewThread(input: { threadId: $thread }) {
      thread { isResolved }
    }
  }' -f thread="<thread_id>"
```

Before resolving, reply `Addressed in <sha7>.` so the thread names the commit
that closed it. Skip the reply when any comment in the thread, from anyone,
already names a commit as the fix ("Fixed in abc123", "addressed by
1b6e8fd"). A reply that says it was fixed but names no commit does not count.
The reference is what the reply adds, and a second note restating it is
noise. Set `commit_referenced` from that check.

Resolving is reversible, unlike submitting, and the earlier review already
notified everyone. So it rides on the posting answer and does not get a
prompt of its own. The `Posting` options name the count: append
`Resolves <m> addressed threads.` to the `post` and `submit` descriptions when
`<m>` is above zero.

An `addressed` mark is a judgment that the defect is gone, made by the same
review that would have raised it again. If a fix only moved the defect, the
rebuilt artifact raises it as a new finding. It does not reopen the old
thread.

### Submitted reviews accumulate

More than one submitted review on a PR is normal. Apart from resolving threads
the author has since addressed, it needs no reconciliation. Re-reviewing after
the author pushes a fix is the point. Deduplication by anchor is what keeps the
second review from restating the first.
