# agent-tooling

Personal agent tooling (skills, plugins, mods, hooks, MCP servers, prompts,
instructions, and scripts) for Claude Code and other LLM clients.

## Layout

```
common/<type>/<name>/            # client-neutral source, the only copy of each item
clients/<client>/<type>/<name>/  # client-specific items, and overlays on common/
dist/<client>/                   # generated build output, never hand-edited
```

- Edit an item in exactly one place. Client-specific changes to a common item
  go in an overlay under `clients/<client>/`, never in a fork of the item.
- Packages (e.g. Claude plugins) are a client-specific type, such as
  `clients/claude/plugins/<name>/`, and pull in items from `common/`.
- `dist/` is gitignored on `main`. CI publishes `dist/claude/` as the root of
  the `dist` branch, since Claude Code expects `.claude-plugin/` at the root.
- Add a client only when it is actually in use.
