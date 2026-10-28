---
name: address
description: >
  Address review feedback on a pull request. Fetches the unresolved inline
  review threads on the current branch's PR (or a given PR number) from any
  reviewer, human or bot, triages each, then works through them one at a
  time: discussing the ambiguous ones, applying fixes, replying on every
  thread, and resolving it. Use when the user says "address feedback",
  "address review comments", "fix review comments", "process PR feedback",
  "coderabbit", or "address CR feedback".
argument-hint: "[pr-number] [--from=<login,...>] [--resolve=<on|off>] [--autofix]"
---

# Address review feedback

## Arguments

| Argument | Default | Meaning |
|---|---|---|
| `[pr-number]` | current branch's PR | The PR to work on |
| `--from=<login,...>` | everyone but you | Only threads started by these logins. A login matches on prefix, so `coderabbitai` also matches `coderabbitai[bot]` |
| `--resolve=<on\|off>` | `on` | Whether a thread is resolved after its reply, for fixes and skips alike. Every fixed or skipped thread gets a reply either way |
| `--autofix` | off | After triage, skip the prompt and go straight to **FIX**. Discuss items stay open |

Report the values used when a default applied, naming the flag that would
have changed it.

## Phases

- **TRIAGE**: fetch the review threads, evaluate the unresolved ones in
  parallel, present the full item list.
- **DISCUSS**: work through discuss items one at a time; each becomes fix,
  skip, or deferred.
- **FIX**: apply fixes through sequential subagents, then close out every
  fixed and skipped thread.

Only inline review threads are in scope. Review summaries and PR
conversation comments can't be resolved, so they aren't tracked here.

---

## TRIAGE

### 1. Identify the PR

If a PR number was given, use it. Otherwise find the current branch's PR:

```bash
gh pr view --json number,url,title,author
```

If the branch has no PR, say so and stop. Record the PR author's login and
your own (`gh api user --jq .login`).

### 2. Fetch the threads

```bash
gh api graphql -f query='
  query {
    repository(owner: "{owner}", name: "{repo}") {
      pullRequest(number: {pr_number}) {
        reviewThreads(first: 100) {
          nodes {
            id
            isResolved
            isOutdated
            path
            line
            comments(first: 50) {
              nodes {
                databaseId
                author { login __typename }
                body
                diffHunk
                createdAt
              }
            }
          }
        }
      }
    }
  }'
```

Get `{owner}/{repo}` from `gh repo view --json nameWithOwner --jq
.nameWithOwner` if needed.

Keep a thread when the login of its **first** comment:

- isn't yours, and
- matches `--from` when it was passed.

Keep matching threads whatever their resolved state.

A thread's **reviewer** is that first login. It's a bot when the author's
`__typename` is `Bot` or the login ends in `[bot]`. Reply wording below
differs for bots and humans.

### 3. Evaluate the unresolved threads

Spawn one subagent per **unresolved** thread, **in parallel**, with the
Agent tool. Pass each one the whole conversation (every comment, in order,
with its author), the file path, line, diff hunk, and repo root, plus this
instruction:

> Read the file and examine the flagged code in context. The **latest**
> comments carry the current state of the discussion: a reviewer may have
> narrowed, changed, or withdrawn the original request, or the author may
> already have answered it. Before forming a verdict: (1) run
> `git log -p -5 -- <path>` and check whether a recent commit deliberately
> made the choice being flagged, which is strong evidence against changing
> it; (2) read `CLAUDE.md` and `AGENTS.md` in the repo root, if present, and
> check whether the request conflicts with documented conventions. Return
> JSON with `verdict` (`fix`, `skip`, or `discuss`), `heading` (one line
> summarizing what the reviewer asked for), `reason` (one sentence, citing
> history or conventions where relevant), and `suggested_fix` (a brief
> description of the change, or null unless the verdict is `fix`). Prefer
> `discuss` when the evidence is mixed, and always for a human reviewer's
> request that changes behavior or design rather than fixing a defect. Make
> no edits.

Assign each thread a status:

- Already resolved on GitHub → **resolved**
- Otherwise the subagent's verdict → **fix**, **skip**, or **discuss**

### 4. Present the item list and prompt

List every item, numbered from 1 in thread order:

- Each item is one bold line:
  `**N. STATUS \`path/to/file:line\` - Heading. (reviewer)**`
- `STATUS` is `RESOLVED`, `FIX`, `SKIP`, or `DISCUSS`, padded with spaces
  so the path column aligns.
- `RESOLVED` items have no commentary line.
- Every other item has a commentary line directly after the bold line, with
  no blank line between them: `\` + newline + `\` + newline + 12 spaces,
  then `*italic text*`. Wrap commentary at column 120, ending each wrapped
  line with `\` and indenting continuations by 12 spaces.
- Separate items with a blank line.

```
**1. RESOLVED `path/to/file.go:90` - Heading of a resolved thread. (alice)**

**2. FIX      `path/to/file.go:42` - Heading of a fix thread. (coderabbitai[bot])**\
\
            *What the issue is and the proposed fix, wrapped at column 120 with a backslash at the end\
            of each line and 12 spaces of indentation on continuation lines.*

**3. SKIP     `path/to/file.go:18` - Heading of a skip thread. (bob)**\
\
            *Why this doesn't apply: false positive, convention conflict, or already handled.*

**4. DISCUSS  `path/to/file.go:75` - Heading of a discuss thread. (alice)**\
\
            *The ambiguity and the decision needed.*
```

Keep commentary short: the issue, why it was raised, and for SKIP or
DISCUSS the key tradeoff or reason.

**With `--autofix`**, skip the prompt and go to **FIX**. Discuss items stay
open.

Otherwise ask with `AskUserQuestion`:

```
question: "How would you like to proceed?"
header: "Next step"
options:
  - label: "Discuss"
    description: "Work through items marked discuss. To discuss specific items instead (including ones marked fix or skip), use Other and list the item numbers (e.g. '1, 3')."
  - label: "Fix"
    description: "Fix all fix items and close out skip items now, leaving discuss items open. To fix specific items instead, use Other and list the item numbers (e.g. '2, 4')."
multiSelect: false
```

Routing:

- "Discuss" with discuss items → **DISCUSS** them, then return to step 4
  with the updated list.
- "Discuss" with none → ask which items to discuss, then **DISCUSS**.
- "Discuss" via Other with item numbers → **DISCUSS** only those, then
  return to step 4.
- "Fix" → **FIX** every fix item.
- "Fix" via Other with item numbers → **FIX** only those.
- Other with custom instructions → follow them.

---

## DISCUSS

Work through each discuss item **one at a time**:

1. Present it: file and line, the conversation so far (quote the latest
   comment in full; summarize earlier ones), and the relevant code.
2. Give your assessment of the tradeoff.
3. Ask with `AskUserQuestion`:

   ```
   question: "<brief summary of the open question>"
   header: "Your call"
   options:
     - label: "Fix it"
       description: "Apply the requested change"
     - label: "Skip it"
       description: "Decline it with a short reply on the thread"
     - label: "Defer it"
       description: "Leave the thread open and untouched, to handle elsewhere"
   multiSelect: false
   ```

4. Record the verdict and any notes typed into Other. Notes on a skip
   become the basis of its reply.

When every discuss item is settled, set each to **fix**, **skip**, or
**deferred**, and return to **TRIAGE** step 4.

---

## FIX

Work through fix items **one at a time**, sequentially, to avoid git
conflicts.

Before spawning the first subagent, work out from the repo and session:

- **Repo root**: the absolute path.
- **Commit convention**: read `CLAUDE.md` and `AGENTS.md`, and run
  `git log --oneline -20`. Match the subject format the history uses,
  including a ticket key as scope when the history does so and the branch
  name carries one (e.g. `feature/EX-30696_…` → `EX-30696`).
- **Commit trailer**: the attribution trailer this session's instructions
  specify, if any. Don't invent one.
- **Checks**: the formatter, typecheck, and test commands, from `CLAUDE.md`
  or `AGENTS.md`.

Spawn a subagent per item with the Agent tool. Pass it the file path, line,
diff hunk, the thread conversation, the suggested fix, and everything
above, plus this instruction:

> Read the file and apply the fix. Then: (1) run the formatter on the
> changed files; (2) run the typecheck and the relevant tests, and note
> whether they passed; (3) commit following the given convention and
> trailer, with a subject under 50 characters and a body if needed. Don't
> reply on or resolve the thread. Return JSON with `sha` (short hash) and
> `tests_passed` (bool).

After it returns, close out the thread (below), set the item to **fixed**
with its short SHA, and confirm before moving on:

```
question: "Fix applied (commit <short_sha>). Continue to the next item?"
header: "Next item"
options:
  - label: "Continue"
    description: "Move on to the next fix"
  - label: "Stop here"
    description: "End the session; remaining items stay open"
multiSelect: false
```

Mention in the description if tests failed or the close-out failed.

Don't batch unrelated fixes into one commit.

**Skip** items need no code change. Close them out as soon as the plan is
confirmed.

### Close out a thread

Every fixed or skipped thread gets a reply. Then, under `--resolve=on`, it
is resolved; under `--resolve=off`, it stays open for the reviewer.
Deferred threads get neither.

The reply goes on the thread's first comment, by its `databaseId`:

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments/{comment_databaseId}/replies \
  -f body="<reply>"

gh api graphql -f query='
  mutation {
    resolveReviewThread(input: {threadId: "<thread_node_id>"}) {
      thread { isResolved }
    }
  }'
```

Replies are one or two sentences, never more than 60 words, with no
paragraph breaks, lists, or quoting of the review:

- **Fix**: `Fixed in <short_sha>.`, plus a clause only when the fix
  differs from what was asked.
- **Skip**: `Skipping — <reason>.` Just the why-not: a convention
  conflict, a false positive, parity with existing code. To a human
  reviewer, write it as a reply to a colleague, not a verdict on a tool,
  and don't argue the point.

A good skip reply: *"Skipping — sibling pcoPush manifest fields aren't
validated either, so adding a guard just here would be one-off
defensiveness against a value the typed backend can't actually send."*

A bad one: anything longer, anything that argues with the reviewer, or
anything that explains what the original code does.

When every item is processed, run the full test suite for the affected
packages, then present the final list in the **TRIAGE** step 4 format with
every status updated.

---

## Notes

- A comment on an outdated diff position may not map onto the current
  file. Read the file fresh rather than trusting the line number.
- When a request conflicts with documented project conventions, follow the
  conventions and say so in the skip reply.
