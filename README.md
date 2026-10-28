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
├── clients/
│   └── claude/             # everything for Claude Code
│       ├── plugins/        #   plugins, installed from the marketplace
│       ├── scripts/        #   setup scripts
│       └── skills/         #   standalone skills, symlinked into a config dir
├── AGENTS.md               # guidelines for agents working in this repo
├── DESIGN.md               # master plan
└── README.md
```

Items start complete inside `clients/<client>/`. A shared `common/` layer
is extracted only once a second client is in use (see DESIGN.md).

## Plugins

| Plugin | Skills |
|---|---|
| `pr` | `/pr:review` |

## Install

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
   claude plugin install pr@nickawilliams
   ```

3. Link the standalone skills, and check them later with `doctor`:

   ```bash
   clients/claude/scripts/skills install [config_dir...]
   ```
