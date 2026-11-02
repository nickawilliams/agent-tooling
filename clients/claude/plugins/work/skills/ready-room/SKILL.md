---
name: ready-room
description: Get a Jira issue ready for `make-it-so` — starting from an existing issue key, a file, a free-text description, or nothing (a short Q&A) — have `state-the-nature` diagnose bugs that haven't been diagnosed yet, map the code seams for features, settle the approach, write or refine the issue in Jira after a single approval (an Epic with child issues when the work is too big for one PR), and gate it against what `make-it-so` needs. Outputs the issue key to hand to `make-it-so`. Use when asked to plan, scope, groom, refine, write up, or get work ready before implementation. For diagnosing a bug on its own, use `state-the-nature`.
argument-hint: "[issue-key | file | description]"
---

Get the work described by $ARGUMENTS ready to implement, and finish
by handing back one Jira issue key that `make-it-so` can take from
open issue to merge-ready PR without stopping to ask what was meant.
The output is the issue in Jira, not anything in this session: every
finding and decision that `make-it-so` would need lands in the
issue's description or comments, because those are what it reads.

The work runs one fixed sequence (see Workflow). What varies is where
it starts and how much each step has to do: a well-written story
clears the early steps quickly, a one-line idea needs all of them.
Never skip a step silently — when one has nothing to do, say why in
a sentence and move on.

## Starting point

The argument is optional and takes one of four forms. Classify it in
this order; any words after an issue key are extra instructions to
honor.

| Argument | Recognized by | Starts as |
|---|---|---|
| Jira key or URL | Matches `[A-Za-z]{2,10}-[0-9]+` or a `/browse/` URL, and resolves in Jira | Existing issue |
| File path | `test -f` succeeds (expand `~`) | Seed text: the file's contents |
| Anything else | Fallback | Seed text: the argument itself |
| Nothing | — | Environment check, then Q&A |

A string that looks like a key but doesn't resolve (`utf-8`) is seed
text, not an error.

**No argument.** Look for a key in the surroundings before asking,
using the same method as `make-it-so`:

```bash
{ git branch --show-current; pwd | tr '/' '\n' | tail -4; } \
  2>/dev/null \
  | grep --only-matching --ignore-case --extended-regexp \
    '\b[a-z]{2,10}-[0-9]+' | tr '[:lower:]' '[:upper:]' \
  | sort -u
```

Also consider anything earlier in this conversation: a key, a draft,
an error, a pasted thread. If a candidate resolves to an open issue,
offer it ("Start from EX-123?") rather than assuming it. Otherwise,
open the Q&A — one batch of plain questions, not a form:

- What's wrong, or what should exist that doesn't? Who notices?
- Is something broken (bug) or missing (feature or improvement)?
- Where does it live, if known — product area, repo, service, screen?
- Anything to start from — a Slack thread, a Datadog or Sentry link,
  a Granola meeting, a customer, an existing issue?

Follow any links the answers give, then continue as seed text.

**Seed text** may itself point at sources: Jira keys, Confluence
pages, Slack permalinks, Datadog or Sentry URLs, GitHub PRs. Read
them during intake.

### Tracks

Every starting point settles into one of two tracks, which decide how
investigation and the description template run.

- **Bug track** — something behaves wrongly. Existing issues of type
  Bug, Internal Defect, or Hotfix; seed text that describes a failure,
  an error, or a regression. Diagnosis belongs to the
  `state-the-nature` skill (step 2); this skill picks up from its
  verdict.
- **Feature track** — something new or better. Story, Task,
  Improvement, Exploration, Epic; seed text that describes a need or
  an idea.

When seed text could go either way ("exports are slow"), pick the
track the evidence supports and say which you picked and why. A
misfiled existing issue (a Story that is really a defect) keeps its
track by content, not type; propose the type change in step 6.

## Settings

These come from the `work` plugin's settings (`/config`, or `claude
plugin configure work`):

| Setting | Value |
| --- | --- |
| `jira_site` | `${user_config.jira_site}` |
| `foreman_project` | `${user_config.foreman_project}` |

A value that is empty, or still reads as a literal `${user_config…}`
placeholder (as it does when this file is read directly rather than
loaded as a plugin skill), is unset. Without `jira_site`, take the
cloudId from `getAccessibleAtlassianResources`. Without
`foreman_project`, find the project by walking up from the cwd to a
`.foreman/` directory; if there is none, ask for the root rather than
guessing.

## Jira

The project, site, and code layout come from foreman's config at
`<root>/.foreman/config.yaml`, where `<root>` is the project root
from Settings. Read `issue_tracker.project` (the project key),
`issue_tracker.base_url`, `workspace.root` (`<wsroot>`, the
workspaces directory under `<root>`), and the `services:` map (code
paths to repos). Never print or copy `issue_tracker.token`.

Reads and writes go through the Atlassian MCP tools (cloudId
`jira_site`). Don't use `foreman create`: it can't set a parent, only
knows Story, Bug, and Task, and sends the description as plain text.

- **Issue types.** Bug for defects that reach production; Internal
  Defect for defects found during development or release testing that
  haven't; Story for user-facing capability; Improvement for making
  existing behavior better; Task for engineering chores. Epic is the
  parent when work is split — the project's children are Stories,
  Tasks, and Bugs under an Epic, never Sub-tasks.
- **Links.** `Blocks` for ordering between children (the blocker is
  the `inwardIssue`), `Relates` for context, `Duplicate` when one
  supersedes another, `Problem/Incident` from a bug to the change
  that caused it, `Work item split` from an issue to the pieces it
  was split into.
- **Summaries.** Plain sentence case naming the outcome, not the
  activity. Match the prefix convention of sibling issues in the same
  Epic when they have one (`Area :: Summary`).
- **Lifecycle is not yours.** Never transition an issue, assign it,
  or put it in a sprint unless the user asks — `foreman start` (via
  `make-it-so`) moves it to In Progress.

### Description templates

Write Markdown (`contentFormat: "markdown"`). Omit a section rather
than fill it with "N/A". Match the voice of recent engineer-written
issues in the project: short, concrete, code names in backticks, file paths
relative to the repo.

Feature track:

```markdown
### Background
What exists today and why it falls short. Code pointers.

### Goal
The outcome, in terms a reviewer can check.

### Approach
The chosen approach and why. Alternatives considered and why not.

### Acceptance criteria
- [ ] Observable, testable statements — one behavior each

### Out of scope
What a reasonable implementer might otherwise include.

### Pointers
Repos, services, files, related issues and docs.
```

Bug track: `state-the-nature`'s bug template (its "Bug description
template" section), with two changes once the approach is decided.
Its "Fix options" section becomes a **Fix** section stating the
chosen fix and why, and an acceptance criteria section is added
after it:

```markdown
### Fix
The chosen fix and why; the options not taken and why not.

### Acceptance criteria
- [ ] The symptom is gone in the reproduction above
- [ ] A regression test covers the failing path
```

Epic (when split): a Goal section, then the children in order with
one line each on what they deliver and what blocks what.

## Workflow

1. **Intake.** Gather everything the starting point offers. For an
   existing issue: description, comments (they often carry decisions
   the description predates), links, parent Epic and its siblings,
   linked Confluence pages, and any PRs mentioning the key
   (`gh search prs <KEY> --owner <org>`, with the org taken from a
   project repo's `origin` remote). For seed text: the
   text plus every source it points at. End with a two-to-four
   sentence problem statement and the track, and state them before
   continuing — correcting a misread here is cheap.

2. **Investigate.** Read code from the default branch, not whatever
   a checkout happens to have: `git -C <repo> fetch` first, then read
   through `origin/<default>` (`git -C <repo> show`,
   `git -C <repo> grep <pattern> origin/<default>`) or from a checkout
   you've confirmed is on an up-to-date default branch. Never switch
   branches, stash, or edit files in the user's checkouts.
   Repos live at the foreman project root; `services:` maps paths to
   them.

   - **Bug track:** if the issue already carries a diagnosis — a
     reproduction plus a root cause or an explicit hypothesis, as
     `state-the-nature` writes them — verify it still matches the
     code and use it. Otherwise invoke the `state-the-nature` skill
     with the Skill tool in embedded mode, passing the issue key or
     the seed text and saying it was called from the ready room. It
     returns a verdict, its drafted Jira changes, and the root cause
     and fix options. Carry the drafts into step 6 so the user
     approves once. Then:
     - **Confirmed:** continue to step 3 with its fix options as the
       starting point for step 4.
     - **Duplicate, not a bug, or cannot reproduce:** there's
       nothing to get ready. Skip to step 6 with only its drafted
       changes, then report the verdict instead of a key to hand to
       `make-it-so`.
     - **Incident:** `state-the-nature` has already alerted the
       user. Stop here until they say how to proceed.
   - **Feature track:** map the seams the work will touch — the
     handlers, models, components, and tests involved, and how
     similar features were built. Find prior art and earlier
     attempts.
   - **Existing issue:** check its claims against the code as built.
     Issues are often written before the code they describe; record
     each mismatch.
   - **Runtime questions:** when the approach depends on what happens
     in production — whether a route, flag, column, or job is still
     used, by which clients, how often — answer it with evidence
     rather than leaving it open. Query Datadog (APM and logs) and
     Sentry over a window long enough to catch infrequent callers
     (90 days by default), even when no link was given. Search the
     repos that consume the code for callers, not only the repo
     being changed: front ends, mobile clients, and other services.
     Record the queries, the window, and the result in the issue so
     the decision can be checked later. If a source fails to connect,
     handle it as Boundaries describes instead of assuming the answer.

   Investigation is read-only. Any scratch code stays in the
   scratchpad; nothing is committed or pushed.

3. **Dedupe and relate.** Search Jira for duplicates and related
   work (`text ~ "<terms>"` in the project, recently created and still
   open, plus the parent Epic's other children). Check for workspaces
   already holding the key (`find -E <root>/<wsroot> -mindepth 1
   -maxdepth 2 -type d -iregex '.*/<KEY>([^0-9][^/]*)?'`) and open
   PRs. A likely duplicate is a decision point: show both and ask
   whether to merge into the existing issue, link them, or proceed.
   On the bug track, `state-the-nature` has already checked for
   duplicate defects; only the workspace and PR checks remain.

4. **Decide the approach.** Lay out the realistic options with their
   trade-offs — usually two or three, never a survey — and recommend
   one. This is the step that's meant to involve the user: ask
   whenever the options lead to materially different
   implementations, user-visible behavior, or scope. Decide yourself
   only where the codebase or conventions settle it, and record the
   reasoning. For a bug with one obvious fix, state it and move on.

5. **Size and shape.** Decide whether the work fits one reviewable
   PR. Signs it doesn't: pieces that could ship and be reviewed
   independently, a backend change that other work waits on, changes
   across repos with separate deploys, or acceptance criteria that
   fall into unrelated groups. When it doesn't fit:

   - Split into an Epic with child issues, each passing the readiness
     gate on its own, ordered by `Blocks` links so it's clear which
     can run in parallel.
   - Starting from an existing Story or Task that's too big: keep it
     as one child (narrowed to its slice), create its siblings, and
     put them under a new Epic. If it already sits in an Epic that
     holds other work, ask whether the new children go into that
     Epic or a new one.
   - The output becomes the parent Epic's key.

6. **Draft and approve.** Assemble every Jira change into one plan
   and present it in a single message: each issue to create (type,
   summary, parent, full description), each edit to an existing
   issue (a before/after of the changed sections), each comment, and
   each link, including any changes drafted by `state-the-nature`
   (merged with yours where they touch the same issue, not listed
   twice). Then ask for approval once with AskUserQuestion. Write
   nothing to Jira before that approval; incorporate any revisions
   and re-present only what changed.

   When editing an issue someone else wrote, preserve their content:
   restructure it into the template and add to it, but don't drop or
   reword their requirements. Record what the ready room changed and
   decided as a comment as well, so the history shows it.

   After approval, write in dependency order: Epic, then children
   (with `parent`), then edits, then links, then comments. Re-fetch
   each issue afterward and confirm the write landed; stop and report
   any that failed rather than retrying blindly.

7. **Readiness gate.** Check the issue as it now exists in Jira —
   re-fetched, not the draft. For an Epic, run it on every child.

   - Open, and not already In Progress with someone else's workspace
     or PR.
   - Type and summary fit the work.
   - Problem and goal are stated; acceptance criteria are observable
     and testable.
   - The repo (or repos) is named or follows unambiguously from the
     `services:` map.
   - The approach is decided; no open question in the description or
     comments would change the implementation.
   - Bug track: reproduction, expected versus actual, and a root
     cause or an explicit hypothesis with where to look.
   - Out of scope is stated wherever scope is ambiguous.
   - Blocking issues are done, or the dependency is stated and
     accepted.
   - The work fits one PR (or is an Epic whose children each do).

   A failing check sends the work back to the step that owns it.
   Hand off only when every check passes, or when the user explicitly
   accepts a listed gap — the accepted gap is then written into the
   issue so `make-it-so` sees it too.

8. **Hand off.** Finish with a short report: the issue key and URL,
   the track, the decisions made (yours and the user's), the
   readiness result with any accepted gaps, and the next step —
   `/work:make-it-so <KEY>`. For an Epic, list the children in order with
   what blocks what. Don't start `make-it-so` yourself.

## Boundaries

- Read-only everywhere except Jira, and Jira only after approval.
  No branches, worktrees, commits, or `foreman` lifecycle commands.
- Slack, Datadog, Sentry, Granola, and Confluence are sources. Don't
  post, comment, or edit there.
- A Datadog, Sentry, or database source that fails to connect is
  reported, not worked around; carry on with what's available and
  note the gap in the issue.

## When to interrupt the user

- The intake reading of the problem, when the starting point is thin
  or could mean several things (step 1).
- A likely duplicate or an existing workspace for the key (step 3).
- Any choice between approaches with materially different results
  (step 4).
- Where new child issues go when the original already has an Epic
  (step 5).
- The single Jira approval (step 6).
- Accepting a readiness gap (step 7).

Batch questions where possible. Don't ask about anything the code,
git history, Jira, or conventions settle — decide, and record the
decision in the issue.
