---
name: state-the-nature
description: Triage a bug or defect — starting from a Jira issue, a file, an error, a Datadog or Sentry link, a Slack report, a description, or nothing (a short Q&A) — reproduce it, trace it to a root cause in code, history, and telemetry, and reach a verdict (confirmed defect, not a bug, duplicate, cannot reproduce, or active incident) with type and priority. Writes the diagnosis to Jira after a single approval. Confirmed defects hand off to `ready-room`, which also calls this skill for undiagnosed bugs. Use when asked to triage, diagnose, investigate, or root-cause a bug, error, alert, or support escalation.
argument-hint: "[issue-key | file | symptom]"
---

Please state the nature of the medical emergency: diagnose the
problem described by $ARGUMENTS and reach a verdict on it. This skill
answers *what is wrong and why*. Deciding how to fix it, shaping the
work, and checking it's ready to implement belong to
`ready-room`; implementing it belongs to `make-it-so`.

The output is a diagnosis recorded in Jira — on an existing issue or
a new Bug or Internal Defect — plus a verdict. Anything learned that
an implementer would need goes into the issue, because the session
won't outlive it.

## Modes

- **Standalone** (invoked by the user): run the full workflow, get
  approval for the Jira changes, write them, and report.
- **Embedded** (invoked by `ready-room` for an undiagnosed
  bug): run steps 1–5, then return the verdict and the *drafted* Jira
  changes to the ready room without writing anything or asking for
  approval. The ready room folds them into its own single approval,
  so the user approves once, not twice. Treat the invocation as
  embedded when the ready room's instructions said so.

## Starting point

The argument is optional and takes one of four forms, classified in
this order. Any words after an issue key are extra instructions.

| Argument | Recognized by | Starts as |
|---|---|---|
| Jira key or URL | Matches `[A-Za-z]{2,10}-[0-9]+` or a `/browse/` URL, and resolves in Jira | Existing issue |
| File path | `test -f` succeeds (expand `~`) | Report: the file's contents (a log, a stack trace, a pasted thread) |
| Anything else | Fallback | Report: the text itself (an error message, a symptom, a Datadog, Sentry, or Slack link) |
| Nothing | — | Environment check, then Q&A |

**No argument.** Look first for a key in the branch name, the working
directory path, and this conversation, the same way
`ready-room` does, and look for an error or stack trace pasted
earlier in the conversation. Offer what you find rather than assume
it. Otherwise ask one batch of questions:

- What happened, and what should have happened instead?
- Where — product area, screen, endpoint, job — and for whom (a
  customer, a company id, a project id)?
- When did it start, and is it still happening?
- Any evidence — an error, a screenshot, a Datadog or Sentry link,
  a Slack thread, a support ticket?

A starting point that turns out to be a feature request, not a
defect, isn't this skill's work. Say so and suggest
`ready-room` instead (in embedded mode, return that verdict).

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

Use the same conventions as `ready-room` (see its Jira section):
`<root>/.foreman/config.yaml` for the project key and `services:`
map, the Atlassian MCP (cloudId `jira_site`) for reads and writes,
never printing the config's token, and never transitioning,
assigning, or sprinting an issue.

- **Type.** Bug when the defect reached production; Internal Defect
  when it was found during development or release testing and hasn't.
  Hotfix only when the user decides the fix must skip the normal
  release process — propose it, never choose it.
- **Priority.** Propose one of the project's values (High, Medium,
  Low) from impact and reach: High when a core workflow is blocked or
  data is wrong for customers with no workaround; Medium when there's
  a workaround or the reach is narrow; Low for cosmetic or rare
  problems. State the reasoning. The user approves it with everything
  else.
- **Links.** `Duplicate` to an existing issue for the same defect;
  `Problem/Incident` (`causes`) from the issue whose change introduced
  the defect, when one exists; `Relates` for context.

### Bug description template

Write Markdown. Omit a section rather than fill it with "N/A".

```markdown
### Symptoms
What the user sees, where, for whom, and since when.

### Steps to reproduce
1. …

**Expected:** … **Actual:** …

### Impact
Who is affected and how badly; how many (from data or telemetry where
available); workaround if any.

### Root cause
What's wrong in the code, with `path:line` at `<repo>@<sha>`, and the
change that introduced it if known. If unconfirmed: the leading
hypothesis, the evidence for it, what was ruled out, and where to look
next.

### Fix options
The realistic fixes with their trade-offs, and which one the
diagnosis points to. The decision is made in `ready-room`.

### Evidence
Logs, traces, error-tracking links, queries run, and the
reproduction script or test if one was written.
```

When editing an issue someone else wrote, keep their report intact:
restructure it into the template and add to it, but don't drop or
reword what they observed.

## Workflow

1. **Intake.** Gather what the starting point offers. For an existing
   issue: description, comments, attachments' descriptions, links,
   and the parent Epic. For a report: the text and every source it
   points at (Slack thread, Datadog or Sentry event, support ticket,
   Granola meeting). End with a one-paragraph statement of the symptom
   — what, where, for whom, since when — and state it before going
   further.

   **Active incident check.** If the evidence shows ongoing
   production impact that's spreading or severe (errors climbing,
   data being corrupted, a core workflow down for many customers),
   stop and tell the user immediately, with the evidence and the
   most likely recent change. Containment (rollback, flag off) is
   their call and comes before diagnosis. Resume only when they say
   to.

2. **Check for known issues.** Before any deep work, search for the
   same defect: open and recently closed Bugs and Internal Defects in
   the project matching the symptom's terms, error text, or code
   area; the parent Epic's other children; recent PRs touching the
   area (`gh search prs --owner <org> <terms>`, with the org taken
   from a project repo's `origin` remote). A clear match
   is a likely `duplicate` verdict — confirm the symptoms really match
   before calling it. A recently merged fix may mean the issue is
   already fixed and only waiting on a release.

3. **Reproduce.** Find the narrowest way to make the failure happen:
   an existing test, a new test or script in the session scratchpad,
   a request against a local or ephemeral environment, or a query
   against logs, traces, or data that shows it happening. Record the
   exact steps. If it can't be reproduced, note what was tried and
   continue with the evidence alone — a defect that is visible in
   telemetry is still confirmed.

4. **Find the root cause.** Read code from the default branch, not
   whatever a checkout happens to have: `git -C <repo> fetch` first,
   then read through `origin/<default>` (`git -C <repo> show`,
   `git -C <repo> grep <pattern> origin/<default>`). Never switch
   branches, stash, or edit the user's checkouts; scratch code stays
   in the scratchpad and nothing is committed.

   Trace from the symptom to the responsible code. When the defect
   has a start date, find the change that introduced it (`git log`
   over the area for that window, `git blame`, the PR and Jira issue
   behind the commit). Use Datadog and Sentry for error rates, first
   occurrence, affected customers, and traces through the failing
   path; when a source fails to connect, say so and carry on without
   it. Distinguish what you confirmed from what you inferred — a
   hypothesis is written up as one, with its evidence.

   Stop digging at the point where the cause is clear enough to
   choose a fix. Sketch the realistic fix options; don't pick one.

5. **Verdict.** Reach exactly one:

   | Verdict | Meaning | Jira changes |
   |---|---|---|
   | **Confirmed** | A real defect, cause found or narrowed to a hypothesis | Create or update a Bug or Internal Defect using the template, with type, priority, and links |
   | **Duplicate** | The same defect already has an issue | `Duplicate` link, plus a comment on whichever issue lacked the evidence, adding it |
   | **Not a bug** | The system behaves as designed or specified | On an existing issue, a comment explaining the intended behavior with the code or spec that defines it. Nothing to create from seed text |
   | **Cannot reproduce** | No reproduction and no evidence in telemetry | On an existing issue, a comment listing what was tried and what would help. From seed text, report only |
   | **Incident** | Raised in step 1 | Whatever the user directs |

   Never close, resolve, or transition an issue for any verdict —
   closing is the user's call. In embedded mode, return now: the
   verdict, the symptom statement, the drafted Jira changes, and the
   root cause and fix options for the ready room's approach step.

6. **Draft and approve** (standalone). Present every Jira change in
   one message — new issue in full, before/after for edited sections,
   each comment and link — and ask for approval once with
   AskUserQuestion. Write nothing before approval. After it, write,
   re-fetch each issue, and confirm the changes landed; report any
   that failed instead of retrying blindly.

7. **Report** (standalone). The verdict, the issue key and URL, the
   symptom statement, the root cause (marked confirmed or
   hypothesis), the proposed type and priority, and what remains
   unknown. For a confirmed defect, the next step is
   `/work:ready-room <KEY>` to decide the fix and get it ready for
   `make-it-so`.

## When to interrupt the user

- An active incident (step 1) — immediately.
- The symptom statement, when the report is thin or could mean
  several things (step 1).
- A probable duplicate whose match isn't clear-cut (step 2).
- Reproduction needs access, data, or an environment you don't have.
- The single Jira approval (step 6), which covers type, priority, and
  verdict.

Batch questions where possible, and keep working on everything that
doesn't depend on the answer.
