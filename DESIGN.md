# Design

The master plan for this repo: where it is headed, not where it is. The
README describes the repo as it actually is today.

This is a living document. The repo's real shape comes from what each new
piece of content actually needs. This plan keeps those pieces cohesive. When
an addition doesn't fit the plan, either move the repo toward the plan or
revise the plan, and say which in the commit. Rework any part of it when
reality shows it was wrong.

Each section carries a status:

- **Adopted**: the repo works this way today.
- **Not yet**: the intended direction, not built.
- **Open**: undecided; settle it when real content forces the question.

## Purpose

*Adopted.*

A central repository for all of my custom AI agent tooling. It should be
DRY and support multiple clients. It should reduce vendor lock-in, but not
at all costs. Claude Code is the only client in use today.

It is meant to hold:

- Skills (Agent Skills `SKILL.md` folders)
- Claude Code plugins, mods (panes, bands, status lines, toasts), and hooks
- MCP servers written locally (cloud-hosted MCP services live in
  `~/Projects/mcp`)
- Subagent definitions, slash commands, and prompt templates
- Shared instructions (`CLAUDE.md`, `AGENTS.md`) and their parts
- Settings fragments, standalone scripts, workflows, and playbooks
- Configs for tools around the agents, such as the oh-my-posh status line
- Cloud routines (scheduled tasks) and their local triggers

## Priorities

*Adopted (draft order, may be revised).*

1. **Works for me today.** Adding or editing an item is low-friction, and
   changes take effect quickly.
2. **Easy to rebuild on a new machine.** Setup works even after I've
   forgotten how a thing works.
3. **Single home.** Each item has exactly one editable copy, in this repo.
   Clients use it from a checkout through their own install mechanism (the
   marketplace, or the item's setup step), never through copies kept in
   sync by hand.
4. **Portable content.** Open formats, with harness glue kept separate so
   moving to another client is mechanical.
5. **Multi-client support.** Built when a second client is actually in use,
   not before. Keeping items DRY across clients (extracting `common/`)
   belongs here.

When ease of use today conflicts with portability, ease of use wins, except
where portability is cheap. Ease of use does not justify a second copy: a
scattered copy may exist briefly while an item moves in, never as a resting
state.

Bringing items in from `~/.claude` and project `.claude/` directories
serves both #2 and #3, since a machine can only be rebuilt from the repo if
everything lives in it.

## Content versus glue

*Adopted.*

The expensive parts to write are already in open formats: Agent Skills
`SKILL.md`, MCP, and `AGENTS.md`. The Claude-specific parts are glue: plugin
manifests, hooks, routines, tool names such as `AskUserQuestion`, launchd and
Keychain setup. Glue is cheap to rewrite.

So the guard against lock-in is a writing habit, not a directory rule: keep
glue out of `SKILL.md` content where that's easy. Where it isn't easy, keep
the glue and move on.

Anything that runs off this machine must not assume local-only tools. That
covers hook scripts shipped in a plugin and anything a cloud routine runs.
In particular, such scripts don't use `module-sh`, even though the shell
style guide in my global `CLAUDE.md` otherwise calls for it. They depend
only on what the target environment is known to provide.

## Layout

### Client-first

*Adopted.*

Each item starts complete inside `clients/claude/`, in whatever shape it
needs. Nothing goes in `common/` while Claude Code is the only client:
deciding up front where the shared line falls is a guess that one client
can't test, and it costs effort on every item.

### Target layout

*Not yet.* Reached by extraction, once a second client is in use.

```
agent-tooling/
├── common/                 # client-neutral source, the only copy of each item
│   └── <type>/             #   skills, agents, commands, mcp, instructions, …
│       └── <name>/
├── clients/                # client-specific items, and overlays on common/
│   └── <client>/           #   claude (later: codex, gemini, …)
│       └── <type>/         #   plugins, mods, hooks, settings, or a common type
│           └── <name>/
└── dist/                   # build output; gitignored, never hand-edited
    └── <client>/
```

- **When to extract.** Move an item to `common/` when a second client
  actually uses it. Extract the part both clients share, and leave each
  client's glue in `clients/<client>/` as an overlay.
- **Overlays.** An item in `clients/<client>/` with the same type and name as
  one in `common/` adds to or replaces parts of it for that client.
- **`common/` at the root.** It is the base layer every client inherits, not
  a client, so it doesn't sit under `clients/`. If a layer shared by only
  some clients ever appears (e.g. Codex and ChatGPT), switch to a neutral
  parent such as `layers/{common,openai,claude}/`.

### Packages

*Adopted* for where plugins live; *open* for includes.

A Claude plugin lives at `clients/claude/plugins/<name>/`, with its manifest
and everything it ships, skills included. Packaging rules differ per client,
so there is no client-neutral package format. If the same include lists
start repeating across clients, move them to `common/packages/`.

Once `common/` exists, a plugin will need to pull items in from it. See
the open questions on includes.

### Standalone skills

*Not yet.* The first one arrives with the `pr` plugin.

A skill that isn't part of any plugin lives at
`clients/claude/skills/<name>/`, and its setup step symlinks it into
`~/.claude/skills/<name>`. Use this for skills that must not ship inside a
plugin, such as personal overrides of built-in command names (see
[Command names](#command-names)). A plugin reaches everyone who installs
it; these reach only my machines.

## Distribution

### Root marketplace on `main`

*Not yet.* Takes effect with the first plugin.

The marketplace is named `nickawilliams`, the same identifier as my npm
scope, so install ids read `<plugin>@nickawilliams`. A generic name such as
`agent-tooling` adds no information and is likelier to collide with another
marketplace on the same machine.

`.claude-plugin/marketplace.json` sits at the root of `main`, with entries
pointing straight at `./clients/claude/plugins/<name>`. `main` is then
directly installable:

```bash
claude plugin marketplace add nickawilliams/agent-tooling    # remote
claude plugin marketplace add ./                             # local dev
```

With a local directory marketplace, edits apply on `/reload-plugins` or at
the next session start, with no build step. For a one-off test:
`claude --plugin-dir ./clients/claude/plugins/<name>`.

### Build and `dist` branch

*Not yet.* Needed only once `common/` exists and must be merged in.

The build merges `common/` with `clients/<client>/` into `dist/<client>/`
by copying, never symlinking, and CI publishes `dist/claude/` as the root of
a `dist` branch. Then:

- Install from `nickawilliams/agent-tooling@dist`.
- Local dev registers `./dist/claude` once, rebuilds on save with a file
  watcher (e.g. `watchexec`), and runs `/reload-plugins`.
- **Trade-off:** moving from the root marketplace to `dist` changes the
  install ref, so every existing install has to be pointed at the new one.
- Build script: bash, following the shell style guide in my global
  `CLAUDE.md`. After CI exists, test `marketplace add …@dist` end to end.

### Claude Code marketplace constraints

Reference facts, checked against code.claude.com docs on 2026-10-07.
Recheck before relying on them.

- A git-hosted marketplace needs `.claude-plugin/marketplace.json` at the
  root of the ref. `marketplace add` has no subdirectory option, and
  `--sparse` only limits the checkout.
- `owner/repo@ref` and `owner/repo#ref` both pin a branch or tag.
- Relative plugin sources must start with `./` and must not contain `..`.
  Each entry's `name` must match the `name` in that plugin's `plugin.json`.
- A plugin can't declare components outside its own directory: a `..`
  path or a symlink leading out of the plugin is rejected. The exception is
  a symlink to another plugin in the same marketplace (rechecked
  2026-10-28). A plugin can also declare `dependencies` on other plugins.
- A directory marketplace reads plugins in place: edits apply at the next
  session start or on `/reload-plugins`.
- Not chosen: a `command` plugin source runs a command at install time and
  installs the directory it prints.

### Command names

*Adopted.* Reference facts, from the docs and tests on Claude Code 2.1.308
(2026-10-28).

- A plugin skill always runs as `/<plugin>:<skill>`. It also answers to the
  bare `/<skill>`, but only while no other command uses that name. The
  plugin name is never a command on its own. A skill named after its
  plugin is what makes `/<plugin>` work.
- When names collide, the bare name goes to, in order: a personal skill,
  a project skill, a built-in command or alias, then a plugin skill.
- So a plugin skill can't take a name a built-in alias holds, such as
  `/review` (an alias of `/code-review`). Setting `skillOverrides` to turn
  `code-review` off doesn't free the alias, it just makes `/review` fail.
  `disableBundledSkills` frees it, but turns off every bundled skill.
- To claim such a name, use a personal [standalone skill](#standalone-skills)
  that forwards to the plugin skill, with `disable-model-invocation: true`
  so Claude only sees the real one. Keep it out of the plugin, so other
  people who install the plugin keep the built-in.
- Skills that call each other, and routine prompts, use the full
  `/<plugin>:<skill>` name, which a later install can't take over.

## Consumers

*Not yet.*

Two things read this repo, and the layout has to serve both:

- **The plugin marketplace**, as above.
- **Cloud routines** (Claude Code scheduled tasks), which clone the repo.
  Checked against code.claude.com/docs/en/routines.md on 2026-10-28:
  - Triggers are schedule, API, and GitHub, and one routine can combine
    them. Schedules run at most hourly.
  - The API `/fire` endpoint allows 30 fires per hour per routine and 100
    per account. Its optional `text` arrives wrapped in
    `<routine-fire-payload>` as untrusted data, and the routine's prompt
    must opt in to acting on it.
  - Cloud runs don't read `~/.claude/skills`, and plugins enabled only in
    user settings don't load. Skills load from the cloned repo's
    `.claude/skills/` and from skills enabled on the claude.ai account.
  - claude.ai connectors such as Slack are available.

Working proposal (open): a routine's prompt says "read
`clients/claude/plugins/<name>/skills/<skill>/SKILL.md` and follow it"
instead of relying on skill discovery.

## Rebuilding on a new machine

*Adopted.*

The layout alone doesn't deliver priority 2. The setup has to be recorded
next to the thing it sets up:

- **Every item that needs machine setup owns an idempotent setup step** (a
  skill or a script) with a `doctor` mode that checks the setup is still
  healthy. Items with no setup need nothing.
- **How items reach the machine:** plugins come from the marketplace, with
  the local checkout added as a directory marketplace so edits apply in
  place. Things a plugin can't deliver (an oh-my-posh config, a launchd
  plist, a settings fragment) are installed by the item's setup step, by
  symlink into the checkout or, where a real file is required, by
  generating it from the repo source.
- **A short root checklist** in the README lists the first steps: add the
  marketplace, then run each item's setup.
- **A top-level script** that runs every setup step comes only once the
  checklist gets tedious.

## Open questions

- **Includes.** How a plugin declares the items it pulls in (list file,
  YAML, …), where they are looked up (`common/` alone, or `common/` with the
  client layer applied on top), and where they land (likely
  `<type>/<name>` inside the plugin).
- **Overlay detection.** Implicitly, by a matching `common/<type>/<name>`, or
  explicitly, e.g. an `overrides/` directory. Implicit was favored.
- **Overlay merging.** File-by-file replacement was favored over merging
  inside a file. A common `SKILL.md` can link to a file only the overlay
  supplies.
- **Plugin-private versus shared items.** Likely rule: an item lives inside
  its plugin unless it is portable or shared. A plugin that needs another
  plugin's skill can invoke it by full name and declare a `dependencies`
  entry, so sharing doesn't force a build step.
- **Routines, unverified:**
  - whether a routine can clone a non-default branch;
  - whether `gh` is installed and authenticated in the cloud VM;
  - whether a routine's API trigger and token can be created
    programmatically.

## Planned additions

### `pr` plugin

Pull request skills, ported from
`~/Dropbox/Projects/Clearstory/.claude/skills/` (`~/Projects/Clearstory` is a
symlink to the same directory, so each exists once). It's a port and
refactor, not a plain move.

| From | To | Change |
|---|---|---|
| `review` | `/pr:review` | Moved as is; description no longer claims `/review` |
| `review-slack` | `/pr:sweep` | Reworked: adds GitHub review requests as a source |
| `coderabbit` | `/pr:address` | Renamed; may later cover human review comments |

- A personal standalone skill at `clients/claude/skills/review/` claims
  `/review` and forwards to `/pr:review`. It stays outside the plugin.
- `sweep` only finds PRs and reviews each with `/pr:review`. It has no
  single-PR mode; a routine fired for one PR invokes `/pr:review` directly.
- Automation: a cloud routine with an API trigger, fired by a local launchd
  job while the Mac is awake, plus an hourly schedule as a fallback. The
  routine's prompt reads each `SKILL.md` by path and passes every posting
  flag explicitly, since nobody is there to answer a prompt.
- Belongs in `clients/claude/` because `review` names `AskUserQuestion`
  throughout.

Phases, each committed to `main` on its own and leaving things working:

1. **Move `review`.** Root `marketplace.json`, `clients/claude/plugins/pr/`
   with `plugin.json`, `review` copied with minimal edits, the `/review`
   forwarder and its symlink setup. Validate, install `pr@nickawilliams`
   from the local checkout, compare a real review against the old skill,
   then delete the Clearstory copy.
2. **Move `coderabbit` to `address`.** Rename, update the description and
   triggers, test on a PR, delete the old copy.
3. **Rework `review-slack` into `sweep`.** The one real redesign: start it
   in plan mode. Add the GitHub source, invoke `/pr:review` by full name,
   keep `--yes` and the posting flags. Test locally, delete the old copy.
4. **Create the routine by hand.** Run it once to answer the three
   unverified routine questions (above), and record the results here.
5. **Local trigger and setup.** The fire script, the launchd plist, the
   `/fire` token in the Keychain, an idempotent setup skill with a `doctor`
   mode, and the README checklist.
