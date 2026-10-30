# Migration checklist

Tracks what still lives in my Claude Code config dirs and wants to move into
this repo, so a machine can be rebuilt from here (DESIGN.md priority 2) and
each item has one editable home (priority 3).

Scope: the two config dirs in use —

- `~/.claude` — the default (home) config dir.
- `~/Dropbox/Projects/Clearstory/.claude` — the Clearstory config dir
  (`~/Projects/Clearstory` is a symlink to the same place). Marked
  **[clrstry]** below; the home dir is **[home]**, both is **[both]**.

Compiled 2026-10-30 by surveying both dirs. Caches, transcripts
(`projects/`, `*.jsonl`), `sessions/`, `telemetry/`, `backups/`, and the
rest of Claude Code's own runtime state are deliberately left out — only
authored customizations are listed.

Legend: `[x]` done · `[ ]` to do · `[~]` partially done / needs a decision.

## How to read this

Items are grouped by the content types in [DESIGN.md](DESIGN.md) (skills,
plugins, hooks, output styles, settings fragments, instructions, scripts).
Most skills aren't standalone candidates — several form coupled suites that
should land as plugins, the way `dispatch`/`pickup` became `relay`. Grouping
reflects that. Ownership flags:

- **(portable)** — general-purpose, no external-tool coupling. Easiest wins.
- **(coupled: X)** — depends on tool X (foreman, Jira, Scape MCP, nodeterm,
  Safari…). Still mine, but the glue travels with it.
- **(verify ownership)** — may be distributed by another tool (Scape, Cate,
  the `.agents` framework) rather than hand-authored. Confirm before moving;
  migrating a vendored copy just forks it.

## Done

- [x] **`pr` plugin** — `/pr:review`, `/pr:address`, `/pr:sweep`,
  `/pr:automate`. Ported from the Clearstory skills `review`,
  `coderabbit`, `review-slack`.
- [x] **`relay` plugin** — `/dispatch` + `/pickup`, with the `dispatches`
  script and a `SessionStart` hook. Ported from `[both]` `dispatch` and
  `pickup`; scattered copies removed; the hand-wired `settings.json` hook
  dropped in favor of the plugin's `hooks/hooks.json`.
- [x] **`review` forwarder** — standalone skill at
  `clients/claude/skills/review/`, symlinked into both config dirs, claiming
  the bare `/review` name for `pr:review`.

## Skills

### Jira → PR workflow suite (candidate plugin)

A tightly coupled set around the Jira-to-merge-ready-PR flow (foreman /
bosun / Jira / GitHub). These call each other by name and share the same
toolchain, so they want to land together as one plugin, not as loose skills.

- [ ] `make-it-so` — **[both]**, **diverged**: the `[home]` copy is a
  GitHub-generic version; the `[clrstry]` copy uses Jira + `foreman start`
  and is the active one. Reconcile to one before moving; don't copy both.
  (coupled: foreman, Jira, GitHub)
- [ ] `in-my-ready-room` — **[clrstry]**. Grooms a Jira issue to hand to
  `make-it-so`. (coupled: Jira)
- [ ] `state-the-nature` — **[clrstry]**. Bug triage → Jira diagnosis;
  feeds `in-my-ready-room`. (coupled: Jira, Datadog, Sentry)
- [ ] `start-work` — **[home]**. Jira issue → `bosun start` workspace.
  Overlaps `make-it-so`'s setup; decide whether it folds in or stays
  separate. (coupled: Jira, bosun)
- [ ] `15five` — **[clrstry]**. Weekly check-in drafted from Jira, GitHub,
  Granola, Calendar, Slack. Related but standalone; could be its own skill
  rather than part of the suite. (coupled: many connectors)

### General utilities (portable — easiest to migrate)

- [ ] `git-stash-cleanup` — **[home]**. (portable)
- [ ] `recall` — **[home]**. Find the session where a commit was made.
  (portable)
- [ ] `restate` — **[home]**. Rewrite the previous message plainly.
  (portable)
- [ ] `fix-console-errors` — **[home]**. Web-dev console error triage.
  (portable)

### Scape / Cate IDE-coupled

Authored for the Scape/Cate IDE workflow. Several are identical across both
config dirs; `scape-table` has **diverged** between them. Confirm these are
mine to centralize and aren't shipped by Scape before moving.

- [ ] `scape-codex-review` — **[both]**, identical. (coupled: Scape;
  verify ownership)
- [ ] `scape-note` — **[both]**, identical. (coupled: Scape MCP;
  verify ownership)
- [ ] `scape-playbook` — **[both]**, identical. (coupled: Scape;
  verify ownership)
- [ ] `scape-table` — **[both]**, **diverged**; reconcile first. (coupled:
  Scape MCP; verify ownership)
- [ ] `cate-theme` — **[home]**. Author/edit a Cate IDE theme. (coupled:
  Cate; verify ownership)
- [ ] `manage-nodeterm-canvas` — **[home]**. (coupled: nodeterm;
  verify ownership)
- [ ] `get-linked-context` — **[home]**. Read another agent node's
  context. (coupled: nodeterm)
- [ ] `tab-triage` — **[home]**. Triage open Safari tabs. (coupled: Safari)

### External / symlinked — not `.claude`-authored (decide separately)

Already centralized outside `.claude`; listed so they're not forgotten, but
they aren't sitting loose in a config dir.

- [~] `find-skills`, `orca-cli`, `orchestration` — **[clrstry]**, symlinks
  into `~/.agents/skills/`. Managed by the `.agents` framework. Decide
  whether agent-tooling should own them or leave them where they are.
- [~] `skills/synced/` — **[both]**. Account/Scape skill-sync buckets
  (UUID-named), not source. Skip; managed by the sync mechanism.

## Hooks

- [ ] `hooks/mail-send-guard.sh` — **[home]**, wired as a `PreToolUse`
  hook. The one hand-authored hook. (coupled: Mail MCP)
- [n/a] Everything else in `settings.json` hooks is third-party integration
  glue injected by its own tool — Scape (`~/.scape/`), AgentDeck, nodeterm
  (`~/.nodeterm/`), Orca (`~/.orca/`), iTerm2 `cc-status`, voice-hooks. It
  lives in those tools' dirs and is theirs to manage, not ours to migrate.

## Output styles

- [ ] `output-styles/eli5.md` — **[both]** (identical). `settings.local.json`
  selects it as the active `outputStyle: ELI5` on `[home]`.

## Settings fragments

Not whole `settings.json` files (most is tool-injected hooks) — just the
authored bits worth centralizing as fragments.

- [ ] Permission allowlists — curated `permissions.allow` entries in
  `settings.json` and `settings.local.json`, **[both]**. Candidate for a
  shared fragment plus the `fewer-permission-prompts` workflow.
- [~] Voice-hooks block in `[home]` `settings.local.json` — decide keep or
  drop; it's local experimentation, not clearly worth centralizing.

## Shared instructions

- [~] Global `CLAUDE.md` — **[home]** symlink to
  `~/Dropbox/.system/macos/assets/synced/user/.ai/AGENTS.md`. Already
  centralized in the `.system` dotfiles sync. Decide whether agent-tooling
  becomes its home (DESIGN lists shared instructions as in scope) or it
  stays in `.system`. The Clearstory `CLAUDE.md` is empty — nothing there.

## Scripts

- [ ] `bin/claude-vscode-wrapper.sh` — **[clrstry]**. Standalone wrapper
  script. (portable)
- [x] oh-my-posh status-line dispatch count — external glue at
  `~/.config/oh-my-posh/claude-statusline.sh`, repointed at the `relay`
  plugin's script during that migration. Stays outside the repo by design
  (one specific oh-my-posh setup), but noted here as handled.

## Mods / status line

- [~] `dev-mods/` — **[home]**, a single UUID dir that appears empty.
  Verify it holds anything before deciding; likely stale.
- [n/a] Active status line is `bash ~/.scape/bridge.sh` (Scape), not ours.

## Not migrating (reference)

- Live dispatch queues (`dispatches/*.md`) — per-repo runtime state, not
  config.
- `plans/`, `feedback/`, `paste-cache/`, `state/`, `jobs/`, `session-env/`,
  `shell-snapshots/`, `ide/`, `daemon/`, `backups/` — Claude Code runtime
  and tool state.
- `*.bak` settings backups left during the `relay` migration — delete once
  session-start notices are confirmed working.
