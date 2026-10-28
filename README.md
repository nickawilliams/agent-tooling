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
├── clients/
│   └── claude/             # everything for Claude Code, in whatever shape it needs
├── AGENTS.md               # guidelines for agents working in this repo
├── DESIGN.md               # master plan
└── README.md
```

Items start complete inside `clients/<client>/`. A shared `common/` layer
is extracted only once a second client is in use (see DESIGN.md).

## Install

Nothing to install yet.
