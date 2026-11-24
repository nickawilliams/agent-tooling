---
name: address
description: >
  Address review feedback on a pull request. Fetches the unresolved inline
  review threads on a PR from any reviewer, human or bot, triages each,
  then works through them one at a time: discussing the ambiguous ones,
  applying fixes, replying on every thread, and resolving it. The PR is
  the one given, else the current branch's, else inferred from the
  checkouts around the working directory, so it works from a workspace
  of several repos or worktrees that each have their own PR. Use when the
  user says "address feedback", "address review comments", "fix review
  comments", "process PR feedback", "coderabbit", or "address CR
  feedback".
argument-hint: "[pr-number | repo#n | owner/repo#n | pr-url] [--from=<login,...>] [--resolve=<on|off>] [--autofix]"
---

# Address review feedback

## Arguments

| Argument | Default | Meaning |
|---|---|---|
| `[pr]` | inferred, see **Resolve the PR** | The PR to work on: a number (`3442` or `#3442`) in the current checkout's repository, or `<repo>#<n>`, `<owner>/<repo>#<n>`, or a PR URL from any directory |
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

### 1. Resolve the PR

The outcome of this step is one PR and its **working checkout**: the
directory whose checked-out branch is the PR's head. Every git command in
this skill runs in the working checkout, every `gh` call that depends on
the current directory takes `--repo <owner>/<repo>`, and the FIX subagents
get it as their repo root. Take `{owner}/{repo}` from the PR's `url`.
Record the PR author's login and your own (`gh api user --jq .login`).

Say how the PR was chosen whenever it wasn't named on the prompt.

#### From an operand

A PR named in full, as `<owner>/<repo>#<n>` or a URL, works from any
directory: `gh pr view <url>` takes the URL directly, and
`<owner>/<repo>#<n>` becomes `--repo <owner>/<repo>` plus the number.

`<repo>#<n>` names the repository without its owner, and is resolved as
`pr:review` resolves it. The owner is the first of these under which the
PR exists: a checkout here whose `origin` remote is that repository (the
working directory's, or a **candidate checkout**'s, below), the current
checkout's owner, your login (`gh api user --jq .login`), your
organizations (`gh api user/orgs --jq '.[].login'`). Probe each with
`gh api repos/<owner>/<repo>/pulls/<n> --jq .html_url`, stop at the first
that answers, and from there treat it as `<owner>/<repo>#<n>`. Say which
owner was resolved. If none answers, say which owners were tried and
stop.

A bare number names a PR in the current checkout's repository. Outside a
checkout, or when that repository has no such PR, look for it among the
**candidate checkouts** (below): the candidate whose repository has an
open PR with that number. If two candidates' repositories both do, ask
which (the question below, with the two as options).

```bash
gh pr view <n> --repo <owner>/<repo> \
  --json number,url,title,author,headRefName,state
```

The working checkout is the current checkout when its branch is the PR's
`headRefName`, else the candidate checkout whose branch is. With neither,
TRIAGE and DISCUSS still work, since they read the PR over the API; say up
front that no local checkout of `<headRefName>` was found and that FIX
needs one, and stop at the start of FIX if it comes to that.

#### From the directory

With no operand, work outward from the working directory:

1. **The current checkout.** When the working directory is inside a git
   work tree (`git rev-parse --show-toplevel` succeeds) and its branch has
   an open PR, that's the PR and this is the working checkout. Done.

   ```bash
   gh pr list --head "$(git branch --show-current)" --state open \
     --json number,url,title,author,headRefName --jq '.[0]'
   ```

   `gh pr list --head`, not `gh pr view` with no number: the latter falls
   back to a merged or closed PR on the branch and would send the skill
   after feedback that no longer matters.

2. **Candidate checkouts.** Otherwise the session may be in a workspace
   where several repositories or worktrees each carry their own PR, such
   as a directory of worktrees cut for one issue, or a checkout of one
   repository with sibling worktrees. Collect the candidates, in parallel:

   - The immediate subdirectories of the working directory that are git
     work trees: `git -C "$dir" rev-parse --show-toplevel` for each
     `*/`. One level only; a directory of many workspaces is too broad to
     guess from.
   - When inside a checkout, that repository's other worktrees, from
     `git worktree list --porcelain`.

   Dedupe by top-level path, then run the step 1 `gh pr list` in each and
   keep the ones whose branch has an open PR. A candidate that fails
   (`main`, a detached HEAD, no remote) is simply not a candidate.

3. **Pick one.**

   - **No candidate has a PR.** Name the checkouts that were examined
     and stop.
   - **Exactly one does.** Use it, and say so: *No PR for this directory;
     using `<repo>#<n>` from `<dir>`, the only PR among the checkouts
     here.*
   - **Several do.** Infer first, ask last:

     1. **The conversation.** The user's message, or the session before
        it, may name one: a repository or directory, a PR number or
        branch, a file path under one checkout, or a reviewer who
        commented on just one of them. One clear match wins; say what
        matched.
     2. **The feedback.** Fetch the unresolved thread count for each
        candidate with the step 2 query, filtered as step 2 filters
        (not yours, and `--from` when passed). Exactly one candidate
        with unresolved threads wins, since the others have nothing to
        address; say so. None with unresolved threads: report the
        candidates and that every thread on each is resolved, and stop.
     3. **Ask.** Otherwise ask with `AskUserQuestion`, one option per
        candidate, in directory order:

        ```
        question: "Several checkouts here have open PRs. Which should I address?"
        header: "Which PR"
        options:
          - label: "<repo>#<n>"
            description: "<title> — <headRefName> in <dir>, <k> unresolved threads"
        multiSelect: true
        ```

        Choosing several runs the phases below once per PR, in the order
        offered, each with its own working checkout, item list, and
        prompt. Finish one PR's FIX before starting the next TRIAGE.

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
with its author), the file path, line, diff hunk, and the working checkout
as the repo root, plus this instruction:

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

- **Repo root**: the working checkout from step 1, as an absolute path.
  Without one, stop here: fixes need a checkout of the PR's branch.
- **Commit convention**: read `CLAUDE.md` and `AGENTS.md` in the working
  checkout, and run `git log --oneline -20` there. Match the subject
  format the history uses, including a ticket key as scope when the
  history does so and the branch name carries one (e.g.
  `feature/EX-30696_…` → `EX-30696`).
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
with its short SHA, and move straight on to the next item. Choosing
**Fix** at step 4 approved the whole set, so don't confirm between
items. Stop only when a fix's tests fail or its close-out fails: report
what failed, and leave the remaining items open.

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
every status updated. Then re-request reviews (below).

### Re-request reviews

A reviewer whose feedback is fully handled gets asked to look again, so
the PR doesn't sit on a stale "changes requested". Read each reviewer's
latest review and the current requests:

```bash
gh pr view {pr_number} --repo {owner}/{repo} \
  --json latestReviews,reviewRequests,author
```

Re-request a reviewer when all of these hold:

- They're a human: not a bot, not you, not the PR author. Bots re-review
  on push by themselves.
- Their latest review is `CHANGES_REQUESTED` or `COMMENTED`, not
  `APPROVED`, and they aren't already in `reviewRequests`.
- Every inline thread they started is now resolved; a deferred thread
  counts as unresolved. A review whose summary asks for changes with no
  inline thread counts as handled only once a PR comment answers it.
- The fixes are on the remote: the working checkout has no unpushed
  commits (`git rev-list --count @{upstream}..HEAD` prints `0` there).
  This skill doesn't push, so when commits are unpushed, name the
  reviewers that would be re-requested and say they wait for the push.

```bash
gh api --method POST \
  repos/{owner}/{repo}/pulls/{pr_number}/requested_reviewers \
  -f 'reviewers[]=<login>'
```

Report who was re-requested, and who wasn't and why.

---

## Notes

- In a workspace of several checkouts, the working checkout is the only
  one touched. Don't read, edit, or commit in a sibling, even when a
  thread's path happens to exist there too.
- A comment on an outdated diff position may not map onto the current
  file. Read the file fresh rather than trusting the line number.
- When a request conflicts with documented project conventions, follow the
  conventions and say so in the skip reply.
