# agent-tooling

Personal agent tooling for Claude Code and other LLM clients. It holds
everything that would otherwise be scattered across `~/.claude` and similar
client config directories.

## What goes here

- Skills (Agent Skills `SKILL.md` folders)
- Claude Code plugins (bundles of skills, hooks, MCP config, and commands)
- Claude Code mods (live panes, bands, status lines, toasts)
- Hooks, including ones not shipped inside a plugin
- MCP servers written locally (cloud-hosted MCP services live in a separate
  repo, `~/Projects/mcp`)
- Subagent definitions
- Slash commands and prompt templates
- Shared instructions (`CLAUDE.md`, `AGENTS.md`) and the pieces they are
  assembled from
- Settings fragments (permissions, hook registrations)
- Standalone scripts used by the tooling
- Workflows and playbooks
- Configs for tools around the agents, such as the oh-my-posh status line

Claude Code is the only client in use today. Codex, Gemini CLI, and others
are expected later.

## Layout

```
agent-tooling/
├── common/                 # client-neutral source, the only copy of each item
│   └── <type>/             #   skills, agents, commands, mcp, instructions, …
│       └── <name>/
├── clients/                # client-specific items, and overlays on common/
│   └── <client>/           #   claude (later: codex, gemini, …)
│       └── <type>/         #   plugins, mods, hooks, settings, or a common type
│           └── <name>/
├── dist/                   # build output; gitignored, never hand-edited
│   └── <client>/
├── AGENTS.md               # guidelines for agents working in this repo
└── README.md
```

- **One source of truth.** Edit each item in exactly one place. Never fork
  an item to make a client-specific copy.
- **`common/`** holds anything that can be written client-neutrally. Keep it
  free of client-only tool names, hook names, and paths such as
  `~/.claude/`. Client-specific text goes in an overlay.
- **`clients/<client>/`** holds two kinds of things:
  - *Overlays*: an item with the same type and name as one in `common/`
    (e.g. `clients/claude/skills/<name>/`), adding to or replacing parts of
    it for that client.
  - *Client-only items*: things with no neutral form, such as hooks, mods,
    status lines, settings fragments, and packages.
- **Packages are a client-specific type.** A Claude plugin lives at
  `clients/claude/plugins/<name>/`. It holds its manifest and client-only
  files, and declares which `common/` items it pulls in. Packaging rules
  (manifest format, hook wiring, MCP config shape) differ per client, so
  there is no top-level, client-neutral package format. If the same include
  lists start repeating across clients, move them to `common/packages/`.
- **`dist/`** is gitignored on `main`.
- **Add a client only when it is actually in use.** Don't build adapters
  ahead of need.

`common/` sits at the root rather than under `clients/` because it is the
base layer every client inherits, not a client. If a layer shared by only
some clients ever appears (e.g. one for Codex and ChatGPT together), switch
to a neutral parent such as `layers/{common,openai,claude}/`.

## Build and publish

The build merges `common/` with `clients/<client>/` into `dist/<client>/`
by copying, never symlinking: Claude Code skips symlinks that leave a
plugin's directory when it reads a local marketplace. CI publishes
`dist/claude/` as the root of a `dist` branch, since a Claude marketplace
must have `.claude-plugin/` at the root of the ref it is added from.
