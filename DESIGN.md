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
- Settings fragments, scripts, workflows, and playbooks
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
  actually uses it, or when it is client-neutral by design, as the global
  `AGENTS.md` is; that file started `common/` on 2026-11-02. Extract the part both clients share, and leave each
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

### Linked items

*Adopted.* Linked by `clients/claude/scripts/install`, checked by
`install doctor`. Called "standalone items" until 2026-11-02; renamed for
what happens to them rather than for what they aren't.

An item that isn't part of any plugin lives at its kind's directory under
`clients/claude/`, and the install script symlinks it into each config dir:

| Kind | Source | Linked as |
|---|---|---|
| Skill | `skills/<name>/` | `<config_dir>/skills/<name>` |
| Output style | `output-styles/<name>.md` | `<config_dir>/output-styles/<name>.md` |
| Hook | `hooks/<name>/` | `<config_dir>/hooks/<name>`, plus its `settings.json` fragment merged into `<config_dir>/settings.json` |
| Instructions | `common/instructions/AGENTS.md` | `<config_dir>/CLAUDE.md` |

Sources are under `clients/claude/` except the instructions, which are the
first item in `common/` and link to the fixed file name Claude Code reads.

**Opting out.** A config dir lists items it doesn't want in
`<config_dir>/.agent-tooling-ignore`, one `kind/name` per line as linked
(`skills/make-it-so`, `output-styles/eli5.md`). `install` skips them and
removes their link and settings entries if present; `doctor` reports a
lingering link as stale. The file is named for this repo because it sits
in a directory Claude Code owns. Its first use keeps the GitHub
`make-it-so` out of the Clearstory config dir, where the bare
`/make-it-so` must fall through to `work:make-it-so`; a personal skill
would otherwise win the name.

**Settings fragments.** A hook has no discovery directory: Claude Code
reads hooks from `settings.json`. So a hook item is a directory holding
the script and a `settings.json` fragment, the `hooks` object its entries
belong in, with the literal `{{config_dir}}` standing for the config dir
(hook commands get no variable for it). `install` substitutes the path,
adds each entry the config dir's `settings.json` lacks, and removes
entries it owns that no item wants any more; `doctor` reports both. An
entry is owned when one of its commands names a path under
`<config_dir>/hooks/`. Nothing else in the file is touched; `jq` rewrites
it and keeps its two-space layout. The permission allowlist stays out of
the repo: it grows with every approval, so a fragment would be a second
copy to keep in step by hand, and bypass mode makes it inert anyway.

**Plugin or linked.** Ease of install doesn't decide it: both install in
one step from the same single copy. Make an item part of a plugin when it
belongs to a bundle, needs plugin-only features (`userConfig`,
`${CLAUDE_PLUGIN_ROOT}`), or is meant for other people. A hook on its own
is linked too; a hook that belongs with a skill ships in that skill's
plugin, as `relay`'s does. Keep an item linked when it is personal, stands
alone, and a namespace would add nothing, or when it must not ship in a
plugin at all, such as a personal override of a built-in command name (see
[Command names](#command-names)). A plugin reaches everyone who installs
it; linked items reach only my machines. Promote a linked item into a
plugin once it gains siblings or needs a plugin feature.

## Distribution

### Root marketplace on `main`

*Adopted.*

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
- To claim such a name, use a personal [linked skill](#linked-items)
  that forwards to the plugin skill, with `disable-model-invocation: true`
  so Claude only sees the real one. Keep it out of the plugin, so other
  people who install the plugin keep the built-in.
- Skills that call each other, and routine prompts, use the full
  `/<plugin>:<skill>` name, which a later install can't take over.
- A typed `/<skill>` is expanded inline with no tool call, so only a
  `UserPromptSubmit` hook sees it, as the raw text. A skill that forwards
  to another invokes it through the `Skill` tool, which fires
  `PreToolUse` with `tool_input.skill` (tested 2026-11-04).

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
  - Plugins: a cloud session installs none on its own. A repo's
    `enabledPlugins` and `extraKnownMarketplaces` are read but not acted
    on, since adding a marketplace needs the trust dialog cloud never
    shows, and user settings aren't read at all. What works, tested
    2026-11-04 in three sessions on an Anthropic-hosted environment: a
    custom environment's setup script running
    `clients/claude/scripts/cloud-setup`. The script runs as root with
    `HOME=/root`, `claude` on `PATH`, and `CLAUDE_CODE_REMOTE=true`;
    the session runs as the same user, so what the script installs
    under `~/.claude/plugins` is what the session loads, hooks included.
    `git clone` of a public repo works through the proxy whether or not
    the repo is attached (the documented 403 covers API and archive
    requests). The install is frozen in the environment snapshot for up
    to seven days; editing the setup script forces a rebuild.
  - The cloud clone is built from a seed bundle and has **no remote**,
    so `git remote get-url origin` is empty and anything that starts
    from `gh pr view` has nothing to resolve against. `gh api
    repos/<owner>/<repo>/…` works once the repo is attached. The web
    UI's "Add repository" sends the session a prompt to clone a second
    copy; it doesn't attach the existing clone.
  - Hook-set session titles don't reach the claude.ai session name. A
    `UserPromptSubmit` hook's `sessionTitle` does set the title in the
    cloud session itself: a later hook payload carries it as
    `session_title`, and `claude --teleport` of that session shows it in
    the terminal. Only the name in the claude.ai sidebar ignores it,
    following `/rename` and the server's own naming alone. So
    `auto-title` can't name cloud sessions where you look for them; see
    its section. Hooks added to `~/.claude/settings.json` mid-session
    are hot-loaded and fire on the next prompt.

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
  entry, so sharing doesn't force a build step. The other direction, a
  plugin offering a capability others opt into, has one instance: a file
  convention the offering plugin discovers, with no dependency either way
  (see [`auto-title`](#auto-title-plugin)).
- **An `automate` convention.** Candidate: a plugin with automation exposes
  an `automate` skill with `install` (default), `doctor`, `off`, and
  `task`, the recurring entry point a routine invokes. Named for the idea
  rather than Claude's term, since the docs now call routines "scheduled
  tasks". Decide when a second plugin needs one.
- **Routines.** Answered by the `pr` routine's first runs (2026-10-28):
  - `gh` is installed and works, but `gh auth status` fails: `GH_TOKEN`
    is a placeholder and a proxy attaches credentials per request. Check
    with a real call such as `gh api user`.
  - claude.ai connectors (Slack) work, including writes such as reactions.
  - A routine can be created with `RemoteTrigger` (via `/schedule`), but
    the API trigger and its token were added in the web UI; the create call
    takes no trigger fields. The server also jitters the cron minute.
  - Still unverified: whether a routine can clone a non-default branch.

## Planned additions

### `pr` plugin

Pull request skills, ported from
`~/Dropbox/Projects/Clearstory/.claude/skills/` (`~/Projects/Clearstory` is a
symlink to the same directory, so each exists once). It's a port and
refactor, not a plain move.

| From | To | Change |
|---|---|---|
| `review` | `/pr:review` | Moved as is; description no longer claims `/review` |
| `review-slack` | `/pr:sweep` | Reworked: adds GitHub review requests; channel is a plugin setting |
| `coderabbit` | `/pr:address` | Generalized: any reviewer's inline threads, not just CodeRabbit |

- A personal linked skill at `clients/claude/skills/review/` claims
  `/review` and forwards to `/pr:review`. It stays outside the plugin.
- `sweep` only finds PRs and reviews each with `/pr:review`. It has no
  single-PR mode; a routine fired for one PR invokes `/pr:review` directly.
- Automation: a cloud routine with an API trigger, fired by a local launchd
  job while the Mac is awake, plus an hourly schedule as a fallback. It's
  managed by a fourth skill, `/pr:automate`:

  | Command | Runs | Does |
  |---|---|---|
  | `/pr:automate` (`install`) | my Mac | create or update the routine and local trigger |
  | `/pr:automate doctor` | my Mac | check both are healthy |
  | `/pr:automate off` | my Mac | remove the trigger, disable the routine |
  | `/pr:automate task` | the routine | sweep, or review the PR a fire payload names, every flag pinned |

  The routine's stored prompt is one line: read
  `clients/claude/plugins/pr/skills/automate/SKILL.md` and follow its
  `task` section. agent-tooling is public, so anyone's routine can clone
  it, and behavior changes are commits rather than routine edits. Per-user
  values (`slack_channel`, the schedule, the cloud environment) are plugin
  `userConfig`, asked for at install. No separate config file; revisit if
  that proves too thin.
- Belongs in `clients/claude/` because `review` names `AskUserQuestion`
  throughout.
- `review` ships an `auto-title` handler (2026-11-04; title fields
  since 2026-11-06) that names the session
  `<issue> · <name> · review → <repo>#<n>`; see the [`auto-title`
  plugin](#auto-title-plugin). Nearly every PR sits under an issue, and
  one issue can have PRs in several repos, so the issue leads and the
  PR is the target. The issue is the first of: `--issue=<key>` on the
  prompt, an upper-case key in the PR's title, one in its branch name;
  a short list of look-alikes (`UTF-8`, `CVE-…`) is skipped. `--issue`
  is in the skill's argument hint for that purpose alone and plays no
  part in the review. The name is the slug after the key in the PR's
  branch name, hand-written to be short and kept in its own casing,
  else the PR's title. The PR is the first
  operand: a number for the current checkout's repo, or
  `<owner>/<repo>#<n>` or a PR URL from any directory, forms the skill
  accepts too since 2026-11-06 (`pr:sweep` already passed the first).
  A bare number takes the repo from the `origin` remote; no operand
  means the current branch's open PR. One REST call fetches the
  number, title, and branch. REST, because the cloud GitHub proxy
  rejects GraphQL and with it `gh pr view`.

Phases, each committed to `main` on its own and leaving things working:

1. **Move `review`.** *Done 2026-10-28.* Root `marketplace.json`,
   `clients/claude/plugins/pr/` with `plugin.json`, `review` copied with
   minimal edits, the `/review` forwarder and its symlink setup. Validate,
   install `pr@nickawilliams` from the local checkout, compare a real
   review against the old skill, then delete the Clearstory copy.
2. **Generalize `coderabbit` into `address`.** *Done 2026-10-28, shipped
   without a dedicated test; the old skill is parked in the Clearstory
   config dir's `retired-skills/`.* Every reviewer's unresolved
   inline threads (narrowed by `--from`), judged on the whole
   conversation. Every fixed or skipped thread gets a reply, and
   `--resolve=on|off` (default `on`) decides whether it is then resolved.
   Commits follow the repo's own conventions rather than a hardcoded Jira
   scope. Test on a PR, then delete the old copy.
3. **Rework `review-slack` into `sweep`.** *Done 2026-10-28, shipped
   without a dedicated test; the old skill is parked beside `coderabbit`.*
   Planned in plan mode. Adds
   GitHub review requests (`gh search prs --review-requested=@me`) beside
   Slack, picked with a positional `slack|github`. The channel moves to the
   plugin's `slack_channel` setting; with none, Slack is skipped. Skips
   drafts and PRs with a pending review of mine; a GitHub re-request is
   reviewed again, while a Slack-only PR I've reviewed is still skipped.
   Dispatches `/pr:review` by full name with every flag pinned, including
   `--watch=off`. Test locally, delete the old copy.
4. **Write `automate`'s `task` and create the routine by hand.** *Done
   2026-10-28.* Routine `pr-automate` (`trig_01XXU4R1jZS6UX7gqQF4P1AE`):
   hourly, Opus, Slack connector, prompt passes `--channel=bb-prs`. Its API
   trigger URL and token are in 1Password at
   `op://Clearstory/clearstory-anthropic-trigger-pr-automate/{url,credential}`.
   The first full run staged a pending review and marked Slack messages.
5. **`automate`'s `install`, `doctor`, and `off`.** The fire script, the
   launchd plist, the `/fire` token read from 1Password with `op read`,
   the routine itself from `userConfig`, and the README checklist.

### `relay` plugin

*Done 2026-10-29.* The `dispatch`/`pickup` pair, ported from
`~/Dropbox/Projects/Clearstory/.claude/skills/` and `~/.claude/skills/`
(identical copies in both). A straight move into one plugin, named `relay`
for the baton-pass metaphor rather than after either skill, so neither half
is subordinated and both still answer to the bare `/dispatch` and `/pickup`
(no built-in collisions).

| From | To | Change |
|---|---|---|
| `dispatch` | `/relay:dispatch` | Moved as is; no glue paths in the skill |
| `pickup` | `/relay:pickup` | Script path and packaging note repointed at `${CLAUDE_PLUGIN_ROOT}` |

- The `dispatches` script stays inside `skills/pickup/`, so the skill and the
  code its hook runs move together. It keeps its deliberate portability: no
  `module-sh`, bash 3.2 compatible, no `$PATH` dependencies, because it runs
  at every session start under a possibly restricted `PATH`.
- The `SessionStart` hook ships in the plugin's `hooks/hooks.json`
  (`matcher: startup|resume`), running the script via `${CLAUDE_PLUGIN_ROOT}`.
  This replaces the hand-wired entry in `~/.claude/settings.json`, which is
  removed as part of the move.
- The oh-my-posh status-line count stays external glue at
  `~/.config/oh-my-posh/claude-statusline.sh`, deliberately not in the
  plugin. It can't read `${CLAUDE_PLUGIN_ROOT}` (unset at render time), so it
  points at the script in the local checkout. This is the one place the
  plugin's install path leaks out; acceptable because the wrapper is
  machine-specific glue that already lives outside the repo.
- No `userConfig`: the queue lives in each repo's `.claude/dispatches/`, with
  no per-user values to set.

### `work` plugin

*Done 2026-11-02.* A home for daily and weekly work rituals: `/standup`,
built in the Clearstory project config dir the same day and moved here
once its format settled, then `/15five`. Named for the area rather than
either skill so more can join; both still answer bare (no built-in
collisions).

| From | To | Change |
|---|---|---|
| `standup` | `/work:standup` | Clearstory values moved to `userConfig`; examples use placeholder names |
| `15five` | `/work:15five` | Moved nearly as is; Jira site and Slack user ID read from the shared settings |
| `make-it-so` (Clearstory) | `/work:make-it-so` | Project root from a new `foreman_project` setting; workspace root read from the foreman config; generic repo names |
| `in-my-ready-room` | `/work:ready-room` | Renamed; same settings; GitHub org taken from a repo remote |
| `state-the-nature` | `/work:state-the-nature` | Same settings and org change; cross-references use full plugin names |

- The repo is public, so nothing employer-specific ships in the skill:
  email, Slack user ID, Jira site, standup channel, the calendar event
  titles that set the evidence cutoff, repo globs, and the session cwd
  regex are all `userConfig`. An unset value degrades its source and is
  named in the footer rather than failing the run.
- `sessions` stays beside `SKILL.md` and runs via
  `${CLAUDE_PLUGIN_ROOT}`. Like `dispatches`, it skips `module-sh`; it
  needs only `jq` and a GNU-compatible `date`.
- `15five` drives the live 15Five form through the Safari MCP tools and
  stops before Submit. 15Five's URLs and form selectors are the product's
  own, not employer-specific, so they stay in the skill.
- Graphiti is optional: with no server configured, the reconciliation
  baseline comes from Granola or the last Slack post and nothing is
  persisted.
- The three Jira lifecycle skills ship `auto-title` handlers
  (`make-it-so` 2026-11-04; all three, with names, 2026-11-06) that
  name the session `<issue> · <name> · <verb>` with the verbs `triage`,
  `plan`, and `implement`; see the [`auto-title`
  plugin](#auto-title-plugin). They share `lib/auto-title.sh`, so each
  handler supplies only its verb. The issue is the prompt's first
  operand (a Jira key or URL; for `make-it-so` also a plain number,
  since the bare `/make-it-so` belongs to the GitHub skill in some
  config dirs), else the one key in the branch name, else the one key
  in the last path components. Branch before path: directory names are
  arbitrary, and one named for the branch adds nothing. The name is the
  Jira summary when the cwd is inside a foreman project, fetched with
  one REST call using the credentials `foreman config get` returns,
  because a hook has no MCP; elsewhere it is the slug after the key in
  the branch or workspace name, casing kept. A key Jira reports unknown (`utf-8`) is
  free text. With no issue, the name is the first five words of a
  free-text argument; a URL, a file, or no argument declines. The
  surroundings count whatever the argument is: `/state-the-nature the
  export button 500s` inside the `EX-1337` workspace triages that
  symptom on `EX-1337`, and `ready-room` and `state-the-nature` were
  changed the same day to offer the key in that case, as they already
  did with no argument.
- `15five` ships its own handler (2026-11-06): no issue or name, the
  verb `15five.check-in`, and the check-in's week as the target,
  giving `15five.check-in → 2026-W39`. 15Five weeks run Saturday to
  Friday and the archive lists them as ranges, so the week is named by
  the ISO week of its Friday, which holds its working days and reads
  as a sequence in the list, whatever form the prompt used (`last
  week`, `Sep 19`, `Sep 19 – Sep 25`, nothing for the current week).
  Words that name no week are kept as the target verbatim, in quotes
  (`15five.check-in → "the week after my vacation"`), so the session
  is still findable by what was typed. The dates are worked out in
  bash arithmetic, so the handler needs neither GNU nor BSD `date`
  beyond printing today.
- The three Jira lifecycle skills moved in on 2026-11-02 and call each
  other by full name (`/work:ready-room`, `work:state-the-nature`), so a
  later install can't take the names over. They drive the `foreman` CLI,
  which must be on `PATH`. The GitHub-generic `make-it-so` in
  `~/.claude/skills` is still separate; reconciling the two is open.

### `mail-send-guard` hook

*Done 2026-11-02.* The outbound-mail guard, moved from `~/.claude/hooks/`
and its hand-wired `PreToolUse` entry in `~/.claude/settings.json` to the
linked `hooks/` kind. For about an hour the same day it shipped as a
one-hook `mail` plugin, because a plugin's `hooks.json` was the only
one-step install that existed; the settings-fragment merge in
the install script replaced that, and the plugin was removed before
anything but this machine installed it.

- The hook matches the Mail MCP server's send tools by basename
  (`smtp_send_message`, `smtp_reply_message`, `graph_send_message`,
  `ews_send_message`), so the server prefix can change without disarming
  it. It answers `ask` on every send, restoring the prompt that
  `bypassPermissions` mode skips, and `deny` when `smtp_send_message`
  carries hand-built `in_reply_to` or `references` values, which must
  come from the server via `smtp_reply_message`.
- The script has no `.sh` extension (executables have none here) and
  needs only `bash` and `jq`. The install script itself now needs `jq`
  too, for the merge.

### VS Code wrapper

*Done 2026-11-02.* `clients/claude/scripts/claude-vscode-wrapper` is the
`claudeCode.claudeProcessWrapper` for the VS Code extension. It replaces
a script in the Clearstory config dir that hardcoded that one project and
still named the config dir by a path renamed months earlier, so it had
been silently inert.

- The wrapper knows no projects. It runs the CLI through `direnv exec`
  for the workspace directory, so the `.envrc` that sets
  `CLAUDE_CONFIG_DIR` in the terminal governs VS Code too, and the two
  can't drift again. Without direnv, or with a blocked `.envrc`, the CLI
  runs unchanged.
- Plain bash, no `module-sh`: VS Code launches it with its own `PATH`,
  and module routing would treat the wrapped command as a subcommand.
  It looks in the usual package-manager bin dirs for direnv for the same
  `PATH` reason.
- The VS Code setting points at the repo checkout rather than a link,
  since there is one such setting and it names a file, not a directory.

### Global instructions

*Done 2026-11-02.* `common/instructions/AGENTS.md` is the global
instruction file, moved from `~/Dropbox/.system/…/.ai/AGENTS.md`, where
Dropbox synced it but nothing versioned it; the dotfiles repo never
tracked that directory. The install script links it as each config
dir's `CLAUDE.md`, which also closed a gap: the Clearstory config dir had
an empty `CLAUDE.md`, so sessions there ran without the house rules.

- It is the first item in `common/`, ahead of a second client, because it
  is client-neutral by design and the layout reserved the place. Codex or
  Gemini would get it through a `clients/<name>` overlay that links the
  same file to their own instruction path.
- Nothing else read the Dropbox copy, and the rest of the `.ai`
  directory was dead (an empty MCP config and a stale settings copy), so
  the dotfiles installer no longer links `~/.ai` and the directory is
  gone. Sync across machines is unchanged: the repo itself lives in
  Dropbox, so the working tree propagates the same way the old copy did,
  with git for history.
- The dotfiles installer (`.system/macos/install.sh`, step Agent Tooling)
  runs `clients/claude/scripts/install` against `~/.claude` and, when `claude` is
  present, adds the marketplace and installs the plugins. That is the
  rebuild path; the README steps are the same commands by hand.

### `auto-title` plugin

*Done 2026-11-04.* Names a session after the skill that starts it, so
the session list reads `ABC-123 review api#456` instead of the first
prompt. It began as a hook for `pr:review` alone and became a shared
plugin: the hook has to run on every prompt and filter, so one hook any
plugin can opt into costs the same as one serving `pr`, and `pr` stays
unaware of how it was invoked.

**Registration.** A skill opts in by shipping an executable named
`auto-title` beside its `SKILL.md`. That file is the whole registration:
auto-title derives the two spellings the skill answers to,
`/<plugin>:<skill>` and bare `/<skill>`, from the plugin's manifest name
and the skill's frontmatter name, so a consumer never writes a pattern
and never restates the client's naming rule. The handler gets the
`UserPromptSubmit` payload on stdin, runs in the session's cwd, and
prints one line or nothing: a JSON object of title fields (`issue`,
`name` or `slug`, `verb`, `target`), which the plugin assembles into the format
below (since 2026-11-06), or any other text, used verbatim. Empty
output or a non-zero exit declines, and the next matching rule is
tried. Colocation won over a plugin-root
`auto-title.json`: the rule is keyed on the skill, so its location can
carry the key, and skill, rule, and handler move together as `relay`'s
hook script does. A root file with explicit patterns can be added later
for rules that aren't skills; none exist.

- The bare spelling is derived, not resolved. auto-title can't tell
  whether `/review` reached `pr:review`, the personal forwarder, or the
  built-in `code-review` alias; the handler runs on all three and either
  finds the branch's PR or declines. If that ever mis-titles a session,
  the precise fix is an alias file in the personal skill naming the
  plugin skill it forwards to, deliberately not built yet.
- Only `skills/*/` is scanned. Skills a `plugin.json` declares at custom
  paths are missed; extend the scanner when one appears.
- Cloud sessions: the plugin installs and its hooks run there (see
  [Consumers](#consumers)), and the title it sets is kept by the
  session and shows after `claude --teleport`, but the claude.ai
  sidebar name follows only `/rename`. Tested 2026-11-04; nothing a
  plugin does can change it. The `pr` handler
  still degrades sanely there: the cloud clone has no remote, so a bare
  number yields `review → #<n>` (led by the issue if `--issue` was
  passed), a `<owner>/<repo>#<n>` or URL operand still names the repo
  and fetches the title, and no operand declines.

**Title format.** `[<issue> · ]<name> · <verb>[ → <target>]`, settled
2026-11-06 by iterating on a mock session list:

```
EX-1337 · timecard sync drops overtime · triage
EX-1337 · timecard sync drops overtime · plan
EX-1337 · timecard sync drops overtime · implement
EX-1337 · timecard sync drops overtime · review → api#3442
dedupe vendor imports · plan
```

The issue leads because the session list is opened to find a piece of
work, not a kind of session; with it first, every session for an issue
shares a prefix across its lifecycle and across the repos its PRs land
in. The name follows because a bare key says nothing about the work: it
is the issue's or PR's title as a lowercase slug with spaces, so the key
stays the only uppercase landmark, or a branch's own slug with its
casing kept, since someone already wrote that as a name. The verb comes
last, lowercase, from
one small vocabulary (`triage`, `plan`, `implement`, `review`), not the
skill's name and not a noun; a target follows it only where one issue
can have several sessions of the same kind, as reviews do, one per PR.
The middle dot separates fields because the hyphen already appears
inside keys and slugs, and the arrow reads as "acting on". An unknown
field is dropped with no placeholder and the order is kept
(`review → api#456`, `dedupe vendor imports · plan`). The plugin
assembles the title from the handler's fields, so the format lives in
one place: it slugifies the name, strips a leading key or `Area ::`
prefix from it, requires an issue, a name, or a target, and fits the
title to 80 characters by shortening the name at a word boundary, never
the issue, verb, or target. The earlier format was `<issue> <verb>
[<qualifier>]` (2026-11-04). Two things the format doesn't attempt:
sorting as text (keys and verbs don't, and `/resume` orders by
recency), and a table view (a mod can't restyle the `/resume` picker; a
separate pane could, parked).

**Mechanics.** One script, `auto-title`, with hook modes `index`
(`SessionStart`, every source) and `prompt` (`UserPromptSubmit`), and a
`status` mode behind the `/auto-title` skill. `index` runs
`claude plugin list --json`, the documented enumeration (about 0.6s,
once per session), keeps entries enabled here (project and local scope
only when the cwd is inside their `projectPath`; `enabled` alone is not
cwd-aware), dedupes by id, reads each plugin from `readFromFolder` when
present (in-place plugins, such as this marketplace from a checkout)
else `installPath`, and writes the rules to
`${CLAUDE_PLUGIN_DATA}/sessions/<session_id>.json`. Keying by session
rather than one shared file keeps concurrent sessions in different
projects from racing; files older than seven days are swept. `prompt`
reads only that file: no enumeration and no `claude` spawn per prompt.
It exits at once when the payload carries `session_title`, which is
present only once a title exists, so a `/rename` is never overwritten
and a session is titled at most once.

**Naming after the fact** (2026-11-06). The model can't rename a
session, but the `UserPromptSubmit` hook can on any prompt, and it
overrides an existing title as `/rename` does, so the `/auto-title`
command is the one exception to titling once. Bare, the hook reads the
transcript the payload names (`transcript_path`) for the latest skill
invocation that has a handler, typed (`<command-name>` and
`<command-args>` tags in a user entry) or made through the Skill tool
(an assistant tool_use), and replays it in the `cwd` recorded with it,
so the title comes out as it would have at the time. With an invocation
of its own, `/auto-title /pr:review 3442`, it replays that one in the
current cwd. The outcome, the title or the reason there is none, goes
to the skill as `additionalContext`, and the skill only reports it. The
health report moved to `/auto-title status`, which the hook leaves
alone. Only a live session can be named this way: the title lives in
its transcript, and the hook runs inside it, so an old session is
`claude --resume`d first.

**Failing loudly.** The cache layout and `installed_plugins.json` aren't
documented as stable, so nothing globs them. The enumeration is still an
assumption, and `index` checks it every session with the plugin's own
presence as the canary: its `${CLAUDE_PLUGIN_ROOT}` must be one of the
listed plugin paths, and the scanner that finds every consumer's skills
must find its own. Any failure (`claude` or `jq` off `PATH`, the list
command failing or changing shape, self not listed, as under
`--plugin-dir`) is reported once through `systemMessage`, prefixed
`auto-title: DISABLED`, and recorded in the index so `prompt` stays
quiet. `systemMessage` renders muted, like an info line, so the prefix
carries the severity. Success is silent; an index with no rules at all
gets a one-line note.

Reference facts, tested 2026-11-04 on Claude Code 2.1.308:

- `hookSpecificOutput.sessionTitle` sets the title from `SessionStart`
  and `UserPromptSubmit`, with the same effect as `/rename`. `PreToolUse`
  can't, so the `Skill` tool call a forwarder makes is no use for
  titling. `session_title` appears in those two payloads only once a
  title exists, whether set by `-n`, `/rename`, or a hook.
- Hooks inherit the launching shell's `PATH` and get
  `CLAUDE_PLUGIN_ROOT` and `CLAUDE_PLUGIN_DATA` as environment
  variables, not only as substitutions in the command string.
- `claude plugin list --json` works from inside a hook and omits
  `--plugin-dir` plugins. Project-scope entries carry `projectPath`;
  `projectEnabled` says whether the cwd's project enables the plugin,
  not whether it is enabled at all.
- A plugin loaded in place from a directory marketplace still has a
  stale copy in the cache at `installPath`; `readFromFolder` is what
  Claude Code reads.
- `systemMessage` from `SessionStart` is shown in the TUI and persists,
  styled as a muted info line.
