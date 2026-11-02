---
name: make-it-so
description: Take a Jira issue to a merge-ready GitHub PR — set up the branch and worktree with `foreman start` (or use the one already checked out), implement, verify, commit, push, run an isolated subagent review, open the PR with `foreman review`, then monitor CI to green. Infers the issue key from the branch or worktree path when none is given. Autonomous, interrupting only at genuine decision points. Use when asked to ship, start-to-finish, fully work, or "make it so" for a Jira issue.
argument-hint: "[issue-key]"
---

Take Jira issue $ARGUMENTS from open issue to merge-ready GitHub PR,
working autonomously except at genuine decision points (defined
below). The argument is a Jira issue key (`ABC-123`, any case) or a
full Jira issue URL; any words after it are extra instructions to
honor.

**Resolving the issue key.** When no key is given, derive it rather
than asking. Collect candidates from the current branch name and
from the last few components of the working directory path, since
the worktree is usually named for the issue:

```bash
{ git branch --show-current; pwd | tr '/' '\n' | tail -4; } \
  | grep --only-matching --ignore-case --extended-regexp \
    '\b[a-z]{2,10}-[0-9]+' | tr '[:lower:]' '[:upper:]' \
  | sort -u
```

The letters-only prefix is deliberate: it keeps hex path segments
in temp and session directories from reading as issue keys. There
is deliberately no trailing `\b`: workspaces named
`feature/EX-123_slug` put a word character right after the digits,
and a boundary there would miss the key. Fall
back to the branch's commit subjects (`git log --oneline
origin/<default>..HEAD`) if that finds nothing.

Resolve the candidate in Jira before using it — the pattern also
matches things like `utf-8`, and a lookup settles it. When several
candidates survive, prefer the one whose prefix is a real project
key (`getVisibleJiraProjects`) and whose issue is still open. Ask
the user only when nothing resolves, or when two plausible keys
remain and neither is obviously right — name the candidates in the
question. State the key you settled on and where it came from
before starting work.

## Foreman

Branch/worktree setup and PR posting go through the `foreman` CLI
(`foreman help <subcommand>` for flags). It is built for a human at
a terminal, so drive it with these rules:

- **Use long-form flags.** Write `--issue`, `--workspace`,
  `--project`, `--approve` — never `-i`, `-w`, `-p`, `-a` — so each
  command reads on its own when the user audits the transcript. The
  same goes for any other tool whose flag has a long form (`git`,
  `gh`, `grep`); short-only flags (`git -C`, `find -E`) are fine.
- **Pass everything as flags.** Foreman prompts only when stdin is a
  TTY, which it never is under the Bash tool — so a value it can't
  resolve from flags, env, or the cwd is an error, not a prompt.
  Always pass `--issue <KEY>`, and `--workspace <workspace>` once
  one exists.
- **Always pass `--approve`.** Every mutating command gates
  on a plan confirmation; non-interactively it exits 1 with
  "confirmation required" unless approved.
- **Always pass `--repository`.** With no filter, a non-interactive
  `foreman start` operates on every repository in the project
  (`workspace.repositories: ./*`) — dozens of branches and
  worktrees. Repeat the flag for a multi-repo issue.
- **Don't rely on `--dry-run`.** With stdout not a terminal, foreman
  renders in plain mode, which suppresses plan cards — a dry run
  prints the header and little else. Output is one line per step,
  prefixed `[ok]`, `[skip]`, `[fail]`, `[warn]`, or `[info]`;
  errors go to stderr with a non-zero exit. Read every `[fail]`
  line even on exit 0 (reviewer, assignee, and notification
  failures are best-effort and don't fail the command), and verify
  outcomes with git and `gh` rather than trusting the transcript.
- **Project root.** Foreman finds its project by walking up from the
  cwd to a `.foreman/` directory — normally `~/Projects/Clearstory`.
  Repository names are that root's directory names (`extracker`,
  `legacy-api`, …). Workspaces live under `workspace.root`
  (`_workspaces/`), one per issue, laid out as
  `<root>/_workspaces/<branch>/<repo>`. Pass `--project <root>`
  whenever the cwd is outside it.

Foreman owns the issue's lifecycle state: `start` moves it to In
Progress, `review` moves it to Review. Those transitions are
expected side effects. Beyond them, the Jira issue is read-only to
you — never transition it, comment on it, or edit its fields
directly.

## Workflow

1. **Pre-flight.** Fetch the issue from Jira with the Atlassian MCP
   tools (`getAccessibleAtlassianResources` for the cloudId, then
   `getJiraIssue`) and verify it's real and still open — if it's
   already Done, Resolved, or Closed, stop and ask. Then classify the
   current checkout:

   - **Already set up:** the cwd is a git checkout on a non-default
     branch that plausibly belongs to this issue (name or path
     carries the key, or the user said so). Take it as given and
     skip step 2. `git fetch` the remote.
   - **Inside the issue's workspace, but not a repo** (the cwd is
     `<root>/_workspaces/<ws>` and `<ws>` carries the key): the
     workspace is already chosen. Go to step 2 and use it.
   - **Anything else** (project root, a repo on its default branch,
     a branch for a different issue, outside the project): go to
     step 2. The current checkout is left untouched — foreman
     creates a separate worktree — so a foreign branch is not a
     reason to stop.

   Then check whether work is already underway for this issue
   (`gh pr list --search "<KEY>"`, commits on the branch): if so,
   resume from where things stand instead of starting over, and
   never open a duplicate PR. Uncommitted changes you didn't make
   are the user's — ask before building on top of them.

   **Readiness check.** When starting fresh (not resuming), read the
   description and comments for questions the issue leaves open
   before anything is set up. Phrases like "find out whether",
   "decide", "confirm first", or a fix offered as alternatives
   ("if X, do A; otherwise B") are the usual signs. An open question
   blocks only when its answer changes what gets built or which
   repos change, and the code alone can't answer it — it needs
   production data, a product call, or someone else's input. A
   question settled in a later comment is not open. If any blocking
   question remains, stop before `foreman start`: list each one,
   quote where it appears, and point the user to
   `/in-my-ready-room <KEY>`. Don't research it yourself — that
   skill records the answer in Jira, where this one can read it.
   Extra instructions after the key that settle a question, or tell
   you to proceed anyway, override this check.

2. **Set up the work area.** Decide which repository (or
   repositories) the issue needs. If the cwd is inside a repo
   checkout, that repo is the default — its name is the directory
   holding the main checkout:

   ```bash
   basename "$(dirname "$(git rev-parse --path-format=absolute \
     --git-common-dir)")"
   ```

   Otherwise infer it from the issue (components, labels, paths and
   services named in the description; the `services:` map in
   `<root>/.foreman/config.yaml` maps code paths to repos). Ask only
   when two repos are plausible and the issue doesn't settle it.

   **Look for existing workspaces for the key** — unless the cwd is
   already inside the issue's workspace (step 1), which settles it.
   Workspace names may carry a category directory
   (`feature/EX-123_slug`), and the trailing class keeps `EX-123`
   from matching `EX-1234`:

   ```bash
   find -E <root>/_workspaces -mindepth 1 -maxdepth 2 -type d \
     -iregex '.*/<KEY>([^0-9][^/]*)?'
   ```

   - **None:** create one with `foreman start` (below).
   - **One or more:** ask the user whether to do the work in an
     existing workspace (name each) or in a new one. This is a
     scheduled stop — don't guess, since an existing workspace may
     hold someone's in-progress or abandoned attempt.

   **Using an existing workspace** `<ws>`: if the repo isn't in it
   yet, add it — the repo the work needs is the right one to bring
   in:

   ```bash
   foreman workspace repos add <repo> --project <root> \
     --workspace <ws> --approve
   ```

   **Creating a new workspace**, when none exists:

   ```bash
   foreman start --project <root> --issue <KEY> --repository <repo> \
     --approve
   ```

   It branches from the repo's default branch, names the branch from
   the issue title, and moves the issue to In Progress.

   Always pass `--slug <slug>` rather than letting foreman slugify the
   full title, which yields unwieldy branch and workspace names. Write
   the slug yourself: lowercase, hyphen-separated, aiming for 5 words
   or fewer and never more than 6 unless the issue genuinely can't be
   named in fewer. Keep the distinctive nouns and the core verb; drop
   articles, filler ("a", "the", "and", "for", "of"), and words the
   issue key or repo already implies. Preserve an outline prefix like
   `A.` or `Part 1:` as the slug's leading segment (`a-`, `part-1-`),
   since it keeps sibling issues sorted and scannable; it doesn't
   count toward the word limit. Examples:

   - "A. Create the configuration schema and transition view" →
     `a-config-schema-transition-view`
   - "Timecard sync improvements for the extracker integration" →
     `timecard-sync-improvements`

   When the user wants a new workspace alongside an existing one,
   `foreman start` can't make it: it always reuses the issue's
   workspace, and with more than one it errors (its suggestion to
   pass `--workspace` doesn't work — `start` ignores that flag).
   Use `foreman workspace create` with a branch name distinct from
   the existing workspace's, following the same `<KEY>-<slug>`
   pattern and the same slug length rules as above (ask the user for
   the slug if nothing distinguishes the attempts):

   ```bash
   foreman workspace create <KEY>-<slug> <repo> --project <root> \
     --approve
   ```

   It creates branch and worktree but does not transition the issue.
   From then on two workspaces match the key, so never run
   `foreman start` for it again, and always pass `--workspace` to
   the other foreman commands.

   Either way, the worktree is `<root>/_workspaces/<ws>/<repo>`;
   confirm it exists (`git -C <path> branch --show-current`) rather
   than trusting foreman's output. `cd` into it; the Bash tool keeps
   that cwd for the rest of the session. Never call
   EnterWorktree/ExitWorktree. Because the session started
   elsewhere, the worktree's own CLAUDE.md / AGENTS.md were not
   loaded — read them now. Record `<ws>` for step 9.

3. **Orient.** Read the issue's description and acceptance criteria,
   its comments (they often carry decisions the description
   predates), and any linked Confluence pages or issues. Read enough
   of the relevant code to map the real seams before writing
   anything.
   Issues are often written before the implementation existed —
   where the issue's plan doesn't match the code as built, adapt the
   plan to reality, and record each deviation with its rationale for
   the PR description. A deviation is only an escalation if it
   changes the issue's _goal_, not its mechanics.

4. **Implement.** Follow the surrounding code's existing patterns and
   the repo's conventions. Build incrementally — get one vertical
   slice working end-to-end before filling out the rest. If the work
   exposes a genuine bug outside the issue's file list, fix it when
   it's small and blocking, scoped to what the issue needs; note
   larger shared instances of the same bug for their own issues
   rather than expanding scope.

5. **Verify.** Targeted tests for the new work, then the full test
   suite, then the repo's lint/format gate (check the Makefile,
   CI workflow, or package scripts for the canonical invocation).
   Add a race/concurrency pass where the toolchain offers one (e.g.
   `go test -race`) if the change touches goroutines, shared state,
   or I/O lifecycles. All gates green before any commit.

   **Diff coverage check.** After the test suite passes, measure how
   much of the _changed lines_ are exercised — using the same
   pipeline the repo's Codecov check uses, not an ad-hoc metric of
   your own. A local number produced a different way tells you
   nothing about whether `codecov/patch` will pass.

   Work out how this repo feeds Codecov before measuring. It varies
   per repo, so read, in order: `codecov.yaml`/`.codecov.yml` at the
   root, the CI workflow steps that upload coverage (search
   `.github/workflows/` for `codecov-action` and note its `files`,
   `flags`, and working directory), and the command that produces
   the report those steps upload (Makefile target, package script,
   `go test -coverprofile`, `pytest --cov`, `jest --coverage`,
   whatever the workflow actually runs). Reproduce that command
   locally with the same flags and the same coverage config
   (`.coveragerc`, `jest.config`, `nyc`, `codecov.yaml`'s `ignore:`),
   so your numbers and the check's numbers come from one source.

   Read the bar from `codecov.yaml` rather than assuming one:
   `coverage.status.patch` is the diff-coverage gate, and its
   `target`, `threshold`, and `informational` flag say how much of
   the diff must be covered and whether falling short actually
   fails the PR. In a monorepo with flags or components, measure the
   ones your diff touches. If the repo has no Codecov config, has it
   only in `informational` mode, or the workflow doesn't upload at
   all, say so and fall back to the repo's own coverage tooling —
   then the goal is to cover as much of the diff as is _reasonable_,
   a deliberate audit rather than a number.

   Either way, cross-reference the report against the changed lines
   (`git diff origin/<default>...HEAD`); a whole-project percentage
   is not diff coverage. Uncovered diff lines in low-value
   categories are acceptable without comment:
   straightforward delegations, unreachable error returns, logging/UI
   output, and paths the test infrastructure structurally cannot reach
   (e.g., non-TTY paths in a harness that always injects an
   interactive reader). Everything else warrants a test attempt.

   When diff lines are uncovered and a test _would_ be possible but
   requires fixtures or scaffolding outside the current file's scope:
   write it anyway if the effort is low (a handful of harness calls,
   a simple table-driven case, reuse of existing fixture helpers). The
   bar for "too much lift" is roughly: would this test require
   introducing new test infrastructure, a new fake, or significant
   new fixture setup that doesn't exist in the surrounding test files?
   If yes, note the gap and the reason in the PR body. If no, write
   the test.

   Document every intentional coverage gap in the PR body (step 9) —
   one line per gap, naming the uncovered path and why it was left
   out. This makes gaps visible for human reviewers rather than
   invisible.

6. **Commit and push.** Split into logical commits following the
   repo's commit-message conventions (match recent history for
   type/scope/phrasing). Push the branch — foreman won't push for
   you, and skips any repo whose branch has no remote head.

7. **Independent review — before the PR exists.** Opening the PR
   requests the team's review and announces it in Slack, so the
   self-review comes first. Spawn a subagent with a completely fresh
   context to review the pushed branch. Give it only: the worktree
   path, the branch and its base (`origin/<default>`), the Jira
   issue key, and instructions to be adversarial, read the full diff
   (`git diff origin/<default>...HEAD`) plus surrounding code,
   verify claims empirically (run the tests itself), and report
   findings ranked by severity with file:line and concrete failure
   scenarios. Do not share your own conclusions with it. Explicitly
   instruct the reviewer to audit diff coverage through the repo's
   own Codecov pipeline (step 5): for each changed file, identify
   diff lines with no test coverage and assess whether the gap is
   justified (low-value path, structural harness limitation) or a
   missing test worth adding.

8. **Triage the review yourself — don't rubber-stamp it.** For each
   finding, form your own judgment: is it legitimate, and is the
   suggested fix actually correct in this codebase? Fix what's real
   and in scope (as follow-up commits with messages noting they're
   review follow-ups); decline intentional trade-offs and non-issues
   with a stated reason. If a reviewer's suggested fix is right in
   spirit but wrong in mechanism, implement the correct mechanism and
   say so. Re-run the full verification gate after fixes and push.

9. **Open the PR with foreman.** First confirm no PR is already open
   for the branch (`gh pr list --head <branch> --state open`). If
   one is, skip this step: with `--repository`, `foreman review`
   overwrites an open PR's title and body, and the PR's content is
   the user's once it exists.

   Write the body to a scratch file outside the repo (the session
   scratchpad directory) so it can't be committed by accident:
   summary of what landed, any fixes the work flushed out,
   deviations from the issue with rationale, verification
   performed, review findings fixed vs. declined, coverage gaps with
   reasons, remaining manual checks if any, and a link to the Jira
   issue. GitHub closing keywords do nothing for Jira, so don't
   write `Closes #`: the issue key in the title, branch, or body is
   what the Jira integration keys off. Then, from the worktree:

   ```bash
   foreman review --issue <KEY> --workspace <workspace> \
     --repository <repo> \
     --body "$(cat <scratch-path>)" --approve
   ```

   Leave the title to foreman's `code_host.pr.title_template`
   (`[<KEY>] <issue summary>`) — that is the team convention — and
   leave reviewers and assignees to config (the configured team is
   requested and the author self-assigned). Pass `--title` only if
   the user asked for a different one. Don't pass `--draft` unless
   asked: it also skips the Review transition and the Slack
   announcement, and foreman can't promote a draft afterward.

   This step is autonomous — invoking the skill authorizes posting
   the PR, the review request, the Slack announcement, and the
   status transition that come with it. Confirm the PR exists with
   `gh pr list --head <branch> --json number,url`. If foreman exits
   non-zero or no PR appears, stop and report its stderr; don't fall
   back to `gh pr create`, which would silently skip the
   announcement and the transition.

10. **Monitor to green — mandatory, not optional.** Once the PR
    exists, and after every follow-up push, run `gh pr checks --watch`
    and wait for _all_ checks to reach a terminal state. A one-time
    spot-check is not sufficient — checks that haven't started yet
    will appear passing until they run. Do not deliver the final
    report until every check is either green or explicitly escalated
    (see below). A repo with no checks configured counts as green.

    A failing `codecov/patch` is a real failure, not noise: it means
    the diff-coverage measurement from step 5 disagreed with the
    check, so reconcile the two rather than re-running. Close the
    gap with tests that actually exercise the uncovered path. Never
    close it by asserting nothing, excluding the file in
    `codecov.yaml`, or lowering the target.

    On failure: diagnose, fix, push, run `gh pr checks --watch` again.
    Bound the loop: after two failed fix attempts on the same check,
    or a failure the diff can't explain (flaky infra, deployment gates,
    checks awaiting human approval), escalate instead of churning
    commits. If human review comments arrive while watching, triage
    them under the same protocol as step 8 — address them or respond
    with a reason; don't ignore them. Don't re-run `foreman review`
    after follow-up pushes; the open PR picks them up.

11. **Stop at merge-ready.** Never merge, never enable auto-merge,
    never force-push over others' work. Leave the workspace in place:
    teardown is `foreman cleanup`, and it's the user's to run after
    merge — don't remove branches or worktrees, and don't run any
    other foreman lifecycle command (`preview`, `prerelease`,
    `release`, `cleanup`). Finish with a report: the PR URL, the
    worktree path, what shipped, deviations taken, review findings
    fixed vs. declined (with reasons), decisions made autonomously,
    any `[fail]` lines foreman printed, and anything flagged for the
    user's attention. Include the final CI status — either "all
    checks green" or a list of any checks that were escalated and
    why.

## When to interrupt the user (and only then)

- The issue leaves open a question that decides what gets built
  (step 1's readiness check).
- The issue's requirements are ambiguous in a way the code and repo
  conventions can't resolve, and the interpretations lead to
  materially different implementations.
- Which repository the issue belongs in can't be settled from the
  cwd or the issue.
- A workspace already exists for the issue and the session isn't in
  it (step 2) — existing workspace or a new one is the user's call.
- Fulfilling the issue requires a behavior change beyond what the
  issue itself calls for — scope the issue asked for is never an
  escalation, however user-visible; scope it didn't ask for is.
- A review finding or CI failure implies a design decision rather
  than a correction.
- A foreman command fails in a way its error doesn't explain.
- Anything destructive, irreversible, or outward-facing beyond the
  workspace setup and the PR itself.

Batch questions where possible. If blocked on one, park it and
continue every part that doesn't depend on the answer. Don't ask
about anything resolvable from the codebase, git history, repo
conventions, or sensible defaults — decide, and disclose the
decision in the final report.
