---
name: make-it-so
description: Take a GitHub issue from open to merge-ready PR autonomously — branch, implement, verify, commit, PR, isolated subagent review, CI monitoring, Codecov diff-coverage follow-through. Interrupts only at genuine decision points. Use when asked to ship, start-to-finish, fully work, or "make it so" for an issue by number.
argument-hint: <issue-number> [--slug <slug>]
---

Take issue $ARGUMENTS from open issue to merge-ready PR, working
autonomously except at genuine decision points (defined below). The
argument is an issue number (with or without a leading `#`) or a full
issue URL; `--slug <slug>` after it names the branch (see step 2), and
any other words after it are extra instructions to honor. If no issue
was provided, ask for one before doing anything else.

## Pushing

Every push rebases the branch onto its base first, so a push is also
what keeps the branch current with the branch it will merge into. The
first push sets that baseline; every push after it keeps it. `<base>`
is the branch this one merges into: the open PR's base once a PR
exists (`gh pr list --head <branch> --state open --json baseRefName
--jq '.[0].baseRefName'` — not `gh pr view`, which falls back to a
merged or closed PR), else the branch it was cut from in step 2, else
the default branch (`git ls-remote --symref origin HEAD`).
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

1. **Pre-flight.** `git fetch` the remote. Verify the issue exists
   and is open — if it's closed or already has a merged PR, stop and
   ask. Check for an existing branch, open PR, or worktree for this
   issue (`gh pr list --search "<N>" --state all`, remote branch
   names, `git worktree list`): if found, resume from where things
   stand instead of starting over — never create a duplicate branch
   or PR. Look PRs up with `gh pr list` and a `--state`, never
   `gh pr view <branch>`, which quietly falls back to a merged or
   closed PR when none is open. A closed, unmerged PR is a question
   for the user.
   All work happens in a dedicated per-issue worktree, never in the
   user's checkout — this also keeps simultaneous invocations for
   different issues isolated from each other. If an existing
   worktree for the issue shows activity this session didn't produce
   (fresh uncommitted changes), another run may be live — stop and
   ask.

2. **Orient.** `gh issue view` the issue. Determine the branch name
   from the repo's branch-naming convention — check CLAUDE.md/memory,
   CONTRIBUTING, and recent branch names (`git branch -r`, merged PR
   head refs); default to `<N>-<slug>` when no convention is
   evident. Whatever the convention, the slug inside it is the one
   the user passed as `--slug`, exactly as typed; otherwise invoke
   `/auto-title:slug <issue title>` (the `auto-title` plugin must be
   installed) and use its one line of output verbatim. Never write
   the slug yourself: the same rules name the session, so the branch
   and the session title carry the same words. For example,
   "A. Create the configuration schema and transition view" →
   `a-create-configuration-schema-transition-view`.
   Enter the work area with Claude Code's native worktree
   support: EnterWorktree with that name (creates the worktree under
   `.claude/worktrees/` on a fresh branch from `origin/<default>`
   and switches the session into it), or EnterWorktree with `path`
   to re-enter the issue's existing worktree when resuming. If the
   created branch name doesn't match the convention, rename it
   before pushing. That default branch is the base for **Pushing** and
   for the PR. When the extra instructions name a different base — a
   release branch, or another issue's branch to stack on — point the
   fresh branch at it before any work (`git reset --hard
   origin/<base>`) and carry that name as `<base>` instead. Read the
   docs the issue links to and enough of the relevant code to map the
   real seams before writing anything.
   Issues are often written before the implementation existed —
   where the issue's plan doesn't match the code as built, adapt the
   plan to reality, and record each deviation with its rationale for
   the PR description. A deviation is only an escalation if it
   changes the issue's _goal_, not its mechanics.

3. **Implement.** Follow the surrounding code's existing patterns and
   the repo's conventions. Build incrementally — get one vertical
   slice working end-to-end before filling out the rest. If the work
   exposes a genuine bug outside the issue's file list, fix it when
   it's small and blocking, scoped to what the issue needs; note
   larger shared instances of the same bug for their own issues
   rather than expanding scope.

4. **Verify.** Targeted tests for the new work, then the full test
   suite, then the repo's lint/format gate (check the Makefile,
   CI workflow, or package scripts for the canonical invocation).
   Add a race/concurrency pass where the toolchain offers one (e.g.
   `go test -race`) if the change touches goroutines, shared state,
   or I/O lifecycles. All gates green before any commit.

   **Diff coverage check.** After the test suite passes, measure how
   much of the _changed lines_ are exercised. For Go: run
   `go test -coverprofile=cover.out ./...` then inspect with
   `go tool cover -func=cover.out` and cross-reference against the
   diff. The goal is to cover as much of the diff as is _reasonable_
   — not a hard percentage, but a deliberate audit. Uncovered diff
   lines in low-value categories are acceptable without comment:
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

   **Decide reachability by reading the code path, not by guessing
   from the tests that exist.** Trace every caller, every branch, and
   every config shape that flows into the line before concluding a
   fixture can't produce it — a line reached by a route you didn't
   consider is the common case, not the exception. "The harness can't
   drive this" is a claim about the code, so verify it like one. An
   unchecked guess is how a cheaply-coverable line gets recorded as a
   permanent gap and then defended in review.

   Document every intentional coverage gap in the PR body — one line
   per gap, naming the uncovered path and why it was left out. This
   makes gaps visible for human reviewers rather than invisible.

5. **Commit and open the PR.** Split into logical commits following
   the repo's commit-message conventions (match recent history for
   type/scope/phrasing). Push per **Pushing**; this first push sets
   the branch's baseline on its base. Create the PR with
   `gh pr create --base <base>`, titled per the repo's or user's PR
   conventions (check CLAUDE.md/memory and recent merged PRs);
   default to the issue's title verbatim.
   Body: summary of what landed, any fixes the work flushed
   out, deviations from the issue with rationale, verification
   performed, remaining manual checks if any, `Closes #<N>`. Write
   it as the reviewer will read it: about the change — what it does,
   why, and how it was verified — not about the procedure that
   produced it.

6. **Independent review.** Spawn a subagent with a completely fresh
   context to review the PR. Give it only: repo path, PR number,
   issue number, and instructions to be adversarial, read the full
   diff plus surrounding code, verify claims empirically by running
   *targeted* checks, and report findings ranked by severity with
   file:line and concrete failure scenarios. Targeted means the
   specific experiments that test the author's claims and that
   nothing else performs: revert the production change and confirm
   the new test actually fails without it; pull a coverage profile
   over the changed lines; drive a named edge case. **Do not have it
   run the full test suite.** The author ran it at step 4 and CI
   re-runs it on clean hardware at step 8; a third local run
   duplicates both, buys latency rather than assurance, and its CPU
   contention can distort timings that get misread later as
   regressions. Do not share your own conclusions with it.
   Explicitly instruct the reviewer to audit diff coverage: for each
   changed file, identify diff lines with no test coverage and assess
   whether the gap is justified (low-value path, structural harness
   limitation) or a missing test worth adding.

7. **Triage the review yourself — don't rubber-stamp it.** For each
   finding, form your own judgment: is it legitimate, and is the
   suggested fix actually correct in this codebase? Fix what's real
   and in scope (as follow-up commits with messages noting they're
   review follow-ups); decline intentional trade-offs and non-issues
   with a stated reason. If a reviewer's suggested fix is right in
   spirit but wrong in mechanism, implement the correct mechanism and
   say so. Re-run the full verification gate after fixes and push
   per **Pushing**.

8. **Monitor to green — mandatory, not optional.** After every push
   (PR creation and any follow-up fixes), run `gh pr checks --watch`
   and wait for _all_ checks to reach a terminal state. A one-time
   spot-check is not sufficient — checks that haven't started yet
   will appear passing until they run. Do not deliver the final
   report until every check is green or explicitly escalated (see
   below) _and_ the Codecov pass below is resolved. A repo with no
   checks configured counts as green.

   On failure: diagnose, fix, push per **Pushing**, run `gh pr checks
   --watch` again.
   Bound the loop: after two failed fix attempts on the same check,
   or a failure the diff can't explain (flaky infra, deployment gates,
   checks awaiting human approval), escalate instead of churning
   commits. If human review comments arrive while watching, triage
   them under the same protocol as step 7 — address them or respond
   with a reason; don't ignore them.

   **Codecov diff coverage.** If the repo uses Codecov, its verdict
   on the patch is part of being done. Detect it from any of: a
   `codecov/patch` or `codecov/project` entry in the status checks, a
   comment from the `codecov` bot, a `codecov.yml` / `.codecov.yml`
   in the repo, or a Codecov step in the CI workflow. None of those →
   the repo doesn't use it; skip this and don't wait.

   Codecov reports only after the test job uploads, so it lands after
   the checks go green — and it **edits one comment in place** rather
   than posting a new one. A comment that is already there may still
   describe an earlier push. Before reading any verdict, confirm the
   comment names the current head SHA (`Comparing base (…) to head
   (<SHA>)`); if it names an older one, keep waiting. Poll on a
   bounded loop (~20s interval, give up after ~10 minutes) and report
   that it never arrived rather than blocking forever.

   Anything below 100% patch coverage is an investigation, not a
   shrug:

   1. **Locate it.** The comment gives files and a miss count; a
      local coverage profile gives the lines. Cross-reference against
      `git diff -U0 origin/<base>...HEAD` so you're judging diff
      lines rather than pre-existing gaps in the same file.
   2. **Judge each line** by step 4's bar — including its rule about
      tracing the real code path instead of guessing at reachability.
      Codecov flagging a line you already declared an intentional gap
      is a reason to re-derive that judgment from the code, not to
      restate it. Being the one who wrote the gap note is not
      evidence the note was right.
   3. **Write the tests** for everything coverable, then prove each
      one earns its place: confirm it moves that block from zero to
      hit, and break the line's behavior to confirm the test fails.
      A test that passes either way covers the line and asserts
      nothing — it buys a number, not a guarantee.
   4. **Re-run the full verification gate, push, and re-watch** —
      the push per **Pushing**, then both the status checks and
      Codecov's re-report against the new head SHA.

   Bound it like a failing check: after two rounds that don't move
   the number, escalate with what's left and why.

   If a line you'd declared an intentional gap turns out to be
   coverable, correct the PR body as well — say the earlier reasoning
   was wrong rather than quietly deleting it. A gap that survives the
   investigation stays, with its reason in the PR body and the final
   report.

9. **Stop at merge-ready.** Never merge, never enable auto-merge.
   Force pushes happen only through **Pushing**: always leased, never
   past a lease rejection, never after its step 3 asks. Leave the
   worktree in place —
   don't ExitWorktree/remove it while the PR is unmerged; the
   session-exit prompt handles cleanup on the user's terms. Finish
   with a report: the PR URL, what shipped, deviations taken, review
   findings fixed vs. declined (with reasons), decisions made
   autonomously, and anything flagged for the user's attention.
   Include the final CI status — either "all checks green" or a list
   of any checks that were escalated and why — and, where the repo
   uses Codecov, its patch verdict plus any coverage gap that
   survived investigation.

## When to interrupt the user (and only then)

- The issue's requirements are ambiguous in a way the code and repo
  conventions can't resolve, and the interpretations lead to
  materially different implementations.
- Fulfilling the issue requires a behavior change beyond what the
  issue itself calls for — scope the issue asked for is never an
  escalation, however user-visible; scope it didn't ask for is.
- A review finding or CI failure implies a design decision rather
  than a correction.
- Anything destructive, irreversible, or outward-facing beyond the PR
  itself.

Batch questions where possible. If blocked on one, park it and
continue every part that doesn't depend on the answer. Don't ask
about anything resolvable from the codebase, git history, repo
conventions, or sensible defaults — decide, and disclose the
decision in the final report.
