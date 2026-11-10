---
name: make-it-so
description: Take a Jira issue to a merge-ready GitHub PR — set up the branch and worktree with `foreman start` (or use the one already checked out), implement, verify, commit, push, run an isolated subagent review, open the PR with `foreman review`, then monitor CI to green. Infers the issue key from the branch or worktree path when none is given. Autonomous, interrupting only at genuine decision points. Use when asked to ship, start-to-finish, fully work, or "make it so" for a Jira issue.
argument-hint: "[issue-key] [--slug <slug>]"
---

Take Jira issue $ARGUMENTS from open issue to merge-ready GitHub PR,
working autonomously except at genuine decision points (defined
below). The argument is a Jira issue key (`ABC-123`, any case) or a
full Jira issue URL; `--slug <slug>` after it names the branch and
workspace (see step 2), and any other words after it are extra
instructions to honor.

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
`foreman_project`, foreman must find its project from the cwd (see
**Project root** below); if it can't, ask for the root rather than
guessing.

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
- **Project root.** `<root>` is the `foreman_project` setting when
  set. Otherwise foreman finds its project by walking up from the
  cwd to a `.foreman/` directory, and `<root>` is that directory's
  parent. Repository names are that root's directory names (`api`,
  `web`, …). Workspaces live under `<root>/<wsroot>`, where
  `<wsroot>` is `workspace.root` in `<root>/.foreman/config.yaml`,
  one per issue, laid out as `<root>/<wsroot>/<branch>/<repo>`.
  Pass `--project <root>` whenever the cwd is outside it.

Foreman owns the issue's lifecycle state: `start` moves it to In
Progress, `review` moves it to Review. Those transitions are
expected side effects. Beyond them, the Jira issue is read-only to
you — never transition it, comment on it, or edit its fields
directly.

## Pushing

Every push rebases the branch onto its base first, so a push is also
what keeps the branch current with the branch it will merge into. The
first push sets that baseline; every push after it keeps it. `<base>`
is the branch this one merges into: the open PR's base once a PR
exists (`gh pr list --head <branch> --state open --json baseRefName
--jq '.[0].baseRefName'` — not `gh pr view`, which falls back to a
merged or closed PR), else the branch it was cut from in step 2, else
what `foreman review` would target: the repo's `pull_request.base` in
the foreman config, or the default branch (`git ls-remote --symref
origin HEAD`).
A branch whose PR is already merged is done — stop rather than push;
one whose PR was closed unmerged is a question for the user.

1. **Preconditions.** The working tree is clean
   (`git status --porcelain --untracked-files=no` prints nothing):
   commit first, never autostash. No rebase, merge, or cherry-pick is
   in progress (neither `$(git rev-parse --git-path rebase-merge)` nor
   `rebase-apply` exists; `git rev-parse --quiet --verify MERGE_HEAD`
   and `CHERRY_PICK_HEAD` both fail). The clone is not shallow
   (`git rev-parse --is-shallow-repository` prints `false`; otherwise
   `git fetch --unshallow origin` first).
2. **Fetch.** `git fetch origin`, then the base by refspec so a
   single-branch clone has it too:
   `git fetch origin "+refs/heads/<base>:refs/remotes/origin/<base>"`.
3. **Integrate the remote branch.** Skip on a first push, when
   `origin/<branch>` doesn't exist. Otherwise, if
   `git merge-base --is-ancestor origin/<branch> HEAD` fails, someone
   added commits to the branch (a reviewer's suggestion, a bot) or
   rewrote it: `git rebase origin/<branch>` puts yours on top of theirs
   and drops any of yours they already carry. A conflict here is
   `git rebase --abort`, then ask.
4. **Rebase onto the base.** Note `git rev-parse HEAD` first, then:

   ```bash
   git rebase origin/<base> --no-rebase-merges --no-update-refs \
     --no-autosquash --no-autostash
   ```

   The flags pin the behavior against the user's `rebase.*` config;
   `--no-update-refs` matters because the default would drag other
   stacked branches along. Merge commits on the branch linearize,
   which is intended. An up-to-date branch is a no-op.
5. **Conflicts.** Resolve one only when the resolution is mechanical
   and plainly within the branch's intent — adjacent imports, a
   renamed helper, a moved line. When upstream changed the seam the
   branch builds on, or the resolution is a design choice,
   `git rebase --abort` and ask; the branch is then exactly as it was.
   Never stop with a rebase in progress. One conflict has a known
   shape: a stacked branch whose parent was squash-merged with edits,
   so the parent's own commits no longer apply. The fix is
   `git rebase --onto origin/<base> origin/<old-parent>` while the
   stale `origin/<old-parent>` still exists locally — propose it in
   the question rather than guessing.
6. **Re-verify** when HEAD moved in step 4 and an upstream commit
   touched a file the branch touches (`git diff --name-only
   "$(git merge-base ORIG_HEAD origin/<base>)" origin/<base>` against
   `git diff --name-only origin/<base>...HEAD`): run the targeted
   tests and the lint gate before pushing. CI runs the full suite
   after. A no-op rebase skips this.
7. **Push.**

   ```bash
   git push --force-with-lease --force-if-includes --set-upstream \
     origin <branch>
   ```

   The bare lease is safe because step 3 ran against the fresh fetch,
   and `--force-if-includes` refuses when the remote tip was never
   integrated. Never use the `<ref>:<sha>` lease form, which disables
   that check, and never retry with `--force`. A lease rejection means
   the remote moved after the fetch: start again from step 2. A
   rejection that names branch protection is a report, not something
   to work around.

## Workflow

1. **Pre-flight.** Fetch the issue from Jira with the Atlassian MCP
   tools (`getJiraIssue`, cloudId `jira_site`) and verify it's real
   and still open — if it's already Done, Resolved, or Closed, stop
   and ask. Then classify the current checkout:

   - **Already set up:** the cwd is a git checkout on a non-default
     branch that plausibly belongs to this issue (name or path
     carries the key, or the user said so). Take it as given and
     skip step 2. `git fetch` the remote.
   - **Inside the issue's workspace, but not a repo** (the cwd is
     `<root>/<wsroot>/<ws>` and `<ws>` carries the key): the
     workspace is already chosen. Go to step 2 and use it.
   - **Anything else** (project root, a repo on its default branch,
     a branch for a different issue, outside the project): go to
     step 2. The current checkout is left untouched — foreman
     creates a separate worktree — so a foreign branch is not a
     reason to stop.

   Then check whether work is already underway for this issue
   (`gh pr list --search "<KEY>" --state all`, commits on the
   branch): if so, resume from where things stand instead of
   starting over, and never open a duplicate PR. A PR already merged
   means the issue shipped — stop and say so; one closed without
   merging is a question for the user. Uncommitted changes you
   didn't make are the user's — ask before building on top of them.

   **Readiness check.** When starting fresh (not resuming), read the
   description and comments for questions the issue leaves open
   before anything is set up. Phrases like "find out whether",
   "decide", "confirm first", or a fix offered as alternatives
   ("if X, do A; otherwise B") are the usual signs. An open question
   blocks only when its answer changes what gets built or which
   repos change, and the code alone can't answer it — it needs
   production data, a product call, or someone else's input. A
   question settled in a later comment is not open. If any blocking
   question remains, stop before `foreman start`: list each one and
   quote where it appears, and point the user to
   `/work:ready-room <KEY>`. Don't research it yourself: that skill
   records the answer in Jira, where this one reads it on the next
   run.
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
   find -E <root>/<wsroot> -mindepth 1 -maxdepth 2 -type d \
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
   the issue title, and moves the issue to In Progress. That default
   branch is the base for **Pushing** and for the PR. When the extra
   instructions name a different base — a release branch, or another
   issue's branch to stack on — run the command from a checkout of
   that branch with `--from-head` (`foreman workspace create` takes
   it too) and carry that name as `<base>` instead.

   Always pass `--slug <slug>` rather than letting foreman slugify the
   full title, which yields unwieldy branch and workspace names. The
   slug is the one the user passed as `--slug`, exactly as typed;
   otherwise invoke `/auto-title:slug <issue summary>` and use its one
   line of output verbatim. Never write the slug yourself: the same
   rules name the session, so the branch, the workspace, and the
   session title carry the same words. Examples:

   - "A. Create the configuration schema and transition view" →
     `a-create-configuration-schema-transition-view`
   - "Timecard sync improvements for the payroll integration" →
     `timecard-sync-improvements-payroll-integration`

   When the user wants a new workspace alongside an existing one,
   `foreman start` can't make it: it always reuses the issue's
   workspace, and with more than one it errors (its suggestion to
   pass `--workspace` doesn't work — `start` ignores that flag).
   Use `foreman workspace create` with a branch name distinct from
   the existing workspace's, following the same `<KEY>-<slug>`
   pattern with the slug from `--slug` (ask the user for one if
   nothing distinguishes the attempts):

   ```bash
   foreman workspace create <KEY>-<slug> <repo> --project <root> \
     --approve
   ```

   It creates branch and worktree but does not transition the issue.
   From then on two workspaces match the key, so never run
   `foreman start` for it again, and always pass `--workspace` to
   the other foreman commands.

   Either way, the worktree is `<root>/<wsroot>/<ws>/<repo>`;
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
   (`git diff origin/<base>...HEAD`); a whole-project percentage
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
   type/scope/phrasing). Push per **Pushing**; this first push sets
   the branch's baseline on its base. Foreman won't push for you, and
   skips any repo whose branch has no remote head.

7. **Independent review — before the PR exists.** Opening the PR
   requests the team's review and, where the project's foreman config
   says so, announces it in Slack, so the self-review comes first.
   Spawn a subagent with a completely fresh context to review the
   pushed branch. Give it only: the worktree
   path, the branch and its base (`origin/<base>`), the Jira
   issue key, and instructions to be adversarial, read the full diff
   (`git diff origin/<base>...HEAD`) plus surrounding code,
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
   say so. Re-run the full verification gate after fixes and push
   per **Pushing**.

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
   issue. Write it as the reviewer will read it: about the change —
   what it does, why, and how it was verified — not about the
   procedure that produced it. GitHub closing keywords do nothing
   for Jira, so don't
   write `Closes #`: the issue key in the title, branch, or body is
   what the Jira integration keys off. Then, from the worktree:

   ```bash
   foreman review --issue <KEY> --workspace <workspace> \
     --repository <repo> --base <base> \
     --body "$(cat <scratch-path>)" --approve
   ```

   `--base` is the `<base>` from **Pushing**. Left out, foreman
   targets its configured `pull_request.base` or the default branch,
   which is wrong for a stacked branch.

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

    On failure: diagnose, fix, push per **Pushing**, run `gh pr checks
    --watch` again.
    Bound the loop: after two failed fix attempts on the same check,
    or a failure the diff can't explain (flaky infra, deployment gates,
    checks awaiting human approval), escalate instead of churning
    commits. If human review comments arrive while watching, triage
    them under the same protocol as step 8 — address them or respond
    with a reason; don't ignore them. Don't re-run `foreman review`
    after follow-up pushes; the open PR picks them up.

11. **Stop at merge-ready.** Never merge, never enable auto-merge.
    Force pushes happen only through **Pushing**: always leased,
    never past a lease rejection, never after its step 3 asks. Leave
    the workspace in place:
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
