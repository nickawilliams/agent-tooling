---
name: dispatch
description: Send a work item that surfaced mid-session to a fresh session, in another repo or this one. Writes a self-contained kickoff prompt into the destination's pending queue. Use when a tangent comes up that belongs in a different codebase, when the user wants to queue a todo for a later session here, or when they ask for a prompt to give a fresh session elsewhere.
user-invocable: true
argument-hint: "[destination] [what the work is]"
---

Write a kickoff prompt for work that shouldn't happen in this session, and
park it where a future session will find it.

`$ARGUMENTS` is an optional destination followed by an optional description
of the work. Both may be omitted. The current session is **not** ending;
this is a tangent being set aside so the user can get straight back to what
they were doing.

## When to use something else

This is for work whose recipient **doesn't exist yet**: a tangent noted now
and picked up in that repo days later.

If a session is already live in the target repo and needs something *now*
(a finding, a breaking change, an answer it's blocked on), use
cross-session messaging instead: `ListAgents` to find it, `SendMessage` to
tell it. That delivers immediately; this parks a file for later.

Don't combine them. Don't check `ListAgents` first and send directly when
the destination happens to be running. A live session there is working on
something else, and a dispatch is new work, not news about theirs.
Interrupting it is the exact thing the queue exists to avoid.

## The constraint that governs everything

This must cost less than typing the prompt by hand. That is the entire
reason it exists.

**Do not explore.** No file reads, no searches, no test runs, no
verification passes. Write from what is already in the conversation. At
most one cheap state probe (`git branch --show-current`) if a branch name
belongs in the output. If you find yourself wanting to check something
before writing it, don't: write it down as unverified and move on. The
destination session will verify it far more cheaply than you can from
here.

Never ask a clarifying question before composing. Compose from what you
have, then put the finished thing in front of the user in one step. The
only interaction is the send gate in step 4, which costs one keystroke.

## Steps

1. **Resolve the destination.** Work down this order and stop at the first
   that lands:

   1. **A path in the arguments** (absolute, `~`-relative, or relative) is
      used as given.
   2. **The first word**, if it resolves as a repo name (below).
   3. **Any other word in the arguments** that resolves as a repo name.
      This catches natural phrasings like `/dispatch send the auth thing to
      legacy-api`, where the destination isn't first.
   4. **The session's project directory**, when the arguments contain no
      destination at all and read purely as a description of work, or when
      there are no arguments. This is the "queue a todo for a later session
      here" case, and it's a first-class use, not a fallback for failure.

      Use the *session's* directory, not the shell's. A `cd` earlier in the
      session leaves `pwd` pointing somewhere transient, and the arrival
      hook reads `$CLAUDE_PROJECT_DIR`, so a dispatch parked against a
      drifted `pwd` would never be announced.

   Resolve a bare name like `legacy-api` against the repo tree:

   ```bash
   find ~/Dropbox/Projects -maxdepth 2 -type d -name "<name>" \
     -not -path "*/_*" -not -path "*/.*"
   ```

   Prefer a match that is a git repo. When the current session is itself
   inside `~/Dropbox/Projects/Clearstory/`, prefer a sibling there; names
   like `bosun` exist at both levels and the sibling is nearly always what
   was meant.

   **Ask instead of guessing** when a word was evidently meant as a
   destination but doesn't resolve (a typo'd repo name, a path that doesn't
   exist), or when more than one plausible match survives. Do not silently
   fall through to the current directory in those cases: the user aimed
   somewhere and missed, and quietly parking their prompt here is worse
   than asking. Never create a destination directory.

2. **Identify the thread.** Whatever words remain once the destination is
   accounted for name what to write up. With none, infer the tangent from
   recent conversation and say what you inferred, so a wrong guess is
   obvious before the gate. If nothing in the conversation plausibly needs
   setting aside, say so and stop rather than inventing a task. That is the
   right response to a bare `/dispatch` typed by mistake.

3. **Show the composed dispatch.** Print the resolved destination and the
   full body as ordinary markdown, so it renders properly and stays in the
   transcript. Nothing has been written to disk yet.

4. **Gate on it.** Immediately call AskUserQuestion:

   - `question`: `Send this to <resolved destination>?` When the
     destination is the current directory, append ` (this repo)` so a
     self-dispatch is unmistakable. Bare `/dispatch` is ambiguous between
     "queue this here" and "I forgot the destination," and this label is
     what distinguishes them at a glance.
   - `header`: `Dispatch`
   - Options: **Send it** ("Writes it to `<dest>/.claude/dispatches/` for a
     future session there to pick up.") and **Discard** ("Nothing is
     written. The tangent stays here.")

   Do not add a "Revise" option. The tool appends **Other** automatically,
   and a free-text answer carries the correction in one step ("send to
   legacy-ui instead", "add that we're on JWT v9"), where a bare "Revise"
   would force a second round trip. Treat any Other response as an
   instruction: apply it, show the revised dispatch, and gate again.

   The destination is what this gate is really protecting. A dispatch
   parked in the wrong repo stays invisible until it surfaces somewhere
   unexpected days later, and bare-name resolution is where that goes
   wrong. Put the resolved path in the question text, not just in the
   prose above it.

   Skip the gate entirely in non-interactive runs (`claude -p`), where
   there is nobody to answer it: write directly and report.

5. **Write the file** to
   `<dest>/.claude/dispatches/<YYYY-MM-DD-HHMM>-<slug>.md`, creating
   directories as needed. Format below.

6. **Keep it out of git.** In the destination, if `.claude/` isn't already
   ignored (`git check-ignore -q .claude/` in that repo), append
   `.claude/dispatches/` to its `.git/info/exclude`. That file is
   local-only and untracked, so it changes nothing for collaborators. Say
   that you did it. Skip silently when the destination isn't a git repo.

7. **Confirm in one line and stop.** The body was already shown in step 3;
   don't reprint it. Give the written path and nothing else. No summary of
   your process, no next-step suggestions, no offer to switch directories.
   The user is mid-task in this repo and is returning to it.

If the destination can't be written to for any reason, print the prompt in
the chat for the user to copy, and say why. The manual path always works.

## Format

```markdown
---
summary: <one line, lowercase, no trailing period>
from: <source repo path>
from-branch: <branch, omit if not a repo>
at: <ISO 8601 timestamp>
session: <$CLAUDE_SESSION_ID, or "unknown">
---

<body>
```

`summary` is read by the arrival hook, so keep it to one line and make it
read as the task ("design a real auth layer, current one is ad-hoc"), not
as a category ("auth work").

The body is a **prompt addressed to a fresh session in that repo**. Write
it as prose, in second person, the way you'd brief a competent colleague
who has never seen this conversation. Reach for headings only if it runs
past roughly twenty lines. It must not assume any knowledge of the source
session.

Cover these, in whatever order reads best, omitting any that have nothing
real to put in them:

- **The ask.** What to do, concretely, in the first sentence or two.
- **What was actually observed.** Specific file paths, endpoints, function
  names, response shapes seen in this session. This is the expensive part
  to reconstruct from the other side and the main reason the dispatch beats
  a fresh start.
- **What the source side depends on.** How this repo consumes the thing
  being changed. The destination session cannot see this and will otherwise
  guess or break it.
- **Constraints and no-go zones.** What must not change, and why. Usually
  the single most valuable line in the file, and the one a hand-typed
  prompt forgets.
- **Unverified.** Anything you inferred rather than saw, marked plainly, so
  the destination checks it instead of inheriting it. Include what you
  didn't look at.
- **Where to start.** Files or directories to open first.

Leave out anything the destination session can trivially discover for
itself, anything about what the source session was working on that doesn't
bear on the task, and any pleasantries.

### When the destination is the current repo

Most of the list above exists because the destination session can't see
this codebase. When it can, those sections become the repo explaining
itself to itself, and padding a short todo into a formal briefing is the
main way this gets annoying.

Drop **what the source side depends on** and **constraints and no-go
zones** entirely. Keep the ask, anything concrete you observed (a future
session still won't have read what you read), what's unverified, and where
to start. Two or three sentences is a perfectly good same-repo dispatch.

## Revising after the fact

Most corrections arrive at the gate, as an Other response, before anything
is written. But a follow-up after sending ("add that we're on JWT v9")
edits the file that already exists. Don't re-derive it, don't write a
second one, and don't re-run the gate. Confirm in one line.
