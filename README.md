# agent-tooling

A central repository for my custom AI agent tooling: skills, plugins,
hooks, MCP servers, prompts, instructions, and the scripts around them.
Claude Code is the only client in use today.

This README describes the repo as it is. [DESIGN.md](DESIGN.md) is the
living master plan: the priorities, the target structure, and the open
questions. The repo grows toward that plan one real addition at a time.

## Layout

```
agent-tooling/
├── .claude-plugin/
│   └── marketplace.json    # the `nickawilliams` plugin marketplace
├── common/
│   └── instructions/       # client-neutral AGENTS.md, linked as each config dir's CLAUDE.md
├── clients/
│   └── claude/             # everything for Claude Code
│       ├── hooks/          #   linked hooks, each with a settings fragment merged into the config dir
│       ├── output-styles/  #   linked output styles
│       ├── plugins/        #   plugins, installed from the marketplace
│       ├── scripts/        #   the install script, the cloud setup script, and the VS Code process wrapper
│       └── skills/         #   linked skills
├── AGENTS.md               # guidelines for agents working in this repo
├── DESIGN.md               # master plan
└── README.md
```

Items start complete inside `clients/<client>/`. The shared `common/` layer
holds what is client-neutral by design, so far the global instructions;
other items are extracted into it only once a second client uses them
(see DESIGN.md).

## Plugins

| Plugin | Skills |
|---|---|
| `auto-title` | `/auto-title` |
| `pr` | `/pr:review`, `/pr:address`, `/pr:sweep`, `/pr:automate` |
| `relay` | `/dispatch`, `/pickup` |
| `work` | `/standup`, `/15five`, `/state-the-nature`, `/ready-room`, `/make-it-so` |

`/pr:sweep` reads its Slack channel from the plugin's `slack_channel`
setting (in `/config`). Leave it empty to sweep GitHub review requests only.

`work` asks for its settings at install (work email, Slack user ID, Jira
site, standup channel and calendar events, repo globs, a session
directory regex, and the foreman project root). Change them later in
`/config` or with `claude plugin configure work`. `/standup` also uses a
Graphiti memory server when one is configured. `/make-it-so` drives the
`foreman` CLI, which must be on `PATH`.

The linked `mail-send-guard` hook gates the Mail MCP server's send
tools: it asks before every send, even in `bypassPermissions` mode, and
denies an `smtp_send_message` call that carries hand-built threading
headers, pointing at `smtp_reply_message` instead.

`relay` ships a `SessionStart` hook that announces work dispatched to a repo
and still waiting there. Its oh-my-posh status-line count is separate glue
at `~/.config/oh-my-posh/claude-statusline.sh`, pointed at the script in
this checkout.

`auto-title` names a session after the skill that starts it. A skill in
any plugin opts in with an executable named `auto-title` beside its
`SKILL.md`; it gets the prompt payload on stdin and prints the title, or
nothing to decline. `/pr:review` (or bare `/review`) ships one and titles
the session `review: <repo> #<n>`; `/work:make-it-so` (or bare
`/make-it-so`) ships one and titles it `<issue> Implementation`, taking
the issue from the prompt or, failing that, the branch or worktree
path. A name set with `/rename` is never
overwritten. `/auto-title` shows the handlers found at the last session
start and any problem that has disabled it. Needs `jq` and `claude` on
`PATH`.

## Install

On my machines the dotfiles installer runs these steps; they are listed
here for doing them by hand.

Run these for each Claude Code config dir in use (`~/.claude` by default,
or whatever `CLAUDE_CONFIG_DIR` points at).

1. Add the marketplace. From a local checkout, edits apply in place on
   `/reload-plugins`:

   ```bash
   claude plugin marketplace add ~/Projects/agent-tooling
   ```

   Elsewhere, use `nickawilliams/agent-tooling` instead.
2. Install the plugins:

   ```bash
   claude plugin install auto-title@nickawilliams
   claude plugin install pr@nickawilliams
   claude plugin install relay@nickawilliams
   claude plugin install work@nickawilliams
   ```

3. Link the global instructions (as the config dir's `CLAUDE.md`) and the
   linked skills, hooks, and output styles (such as `/recall`, the
   outbound-mail guard, and `ELI5`), merging each hook's settings fragment
   into the config dir's `settings.json`. Pass every config dir you use,
   and check them later with `install doctor`. The script needs `jq`:

   ```bash
   clients/claude/scripts/install [config_dir...]
   ```

   A config dir opts out of an item with a `.agent-tooling-ignore` file,
   one `kind/name` per line, such as `skills/make-it-so`.

4. For cloud sessions, add a cloud environment at claude.ai/code with
   `clients/claude/scripts/cloud-setup` as its setup script, and pick it
   with `/remote-env` so `claude --cloud` uses it. The script installs
   the marketplace and the `auto-title` and `pr` plugins on the
   session's VM. Session titles don't follow `auto-title` there; the
   claude.ai name only changes with `/rename`.

5. If a project's `.envrc` sets `CLAUDE_CONFIG_DIR`, point the VS Code
   extension's `claudeCode.claudeProcessWrapper` setting at
   `clients/claude/scripts/claude-vscode-wrapper`. It runs the CLI through
   `direnv exec` for the workspace, so VS Code and the terminal use the
   same config dir.
