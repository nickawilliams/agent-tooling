# Agents

## Communication Guidelines

When communicating and responding to me, please use the following guidelines:

- When I make a decision, please avoid verbose responses and summaries and instead simply acknowledge the decision and allow the conversation to continue.
- Avoid excessive validation and instead evaluate the information provided to you and make your own judgments. You are free to be diplomatic in delivering a negative response, but I prefer clarity over diplomacy.
- Use US English spelling everywhere (color, behavior, honor, -ize, license as a noun): code, comments, commit messages, PR and issue text, Jira, and Slack.

### Open Threads

"Open Threads" is the trailing block at the end of a response that surfaces
unresolved items — a decision waiting on me, work deliberately deferred, a
blocker, or something noticed but not acted on. It is always a list, never a
prose paragraph, and never opens with a lead-in like "Two things still
open…". It works like this:

- Precede the whole block with a `---` horizontal rule, so it reads as
  distinct from the body of the response rather than as its final paragraph.
- Follow the rule with a bold **Open Threads** label on its own line, then
  one bullet per item. No lead-in sentence, and never count the items ("Two
  things…") — the list already shows how many there are.
- One item per bullet, stating the thing itself first rather than
  scene-setting up to it. Put the ask or the next step in the same bullet.
- Give every item a handle: a backticked `OT{n}` at the head of the bullet,
  then an em dash, then the item itself. The handle is what I quote to
  reopen one without restating it.
- Number them from `OT1` per session, and treat the number as assigned
  rather than positional. A thread keeps its handle for the whole session,
  so restate the same one each time it carries forward; a new thread takes
  the next unused number. Never renumber the list when something resolves,
  and never reuse a retired handle — if I reference one that has since
  closed, say what it was rather than pointing the number at something new.
- The most recent Open Threads block is the register of which handle means
  what. There is nowhere else that state lives, so restate the full active
  set every time rather than emitting deltas.
- Restrict it to items that need me: a decision only I can make, a blocker,
  or work left undone. Progress already reported in the body of the response
  is not an open thread, and repeating it there dilutes the ones that matter.
- When the response ends with a tool call — such as `AskUserQuestion` for
  an interactive prompt — emit the OT block first, then make the tool call.
  The OT block is always the last text in a response, but never the last
  action. A tool call renders a UI component; an OT item is plain text.
  Both can address the same pending decision — they are not equivalent and
  neither replaces the other.
- Drop the block entirely when nothing is open. Padding it to look thorough
  defeats the point of having it.

## File Conventions

- YAML files use the full `.yaml` extension, never `.yml`. When touching a
  file that already uses `.yml`, prefer renaming it (and updating references)
  unless an external tool requires that exact name.
- Hard wrapping is for files, not for web UIs. Wrap prose at ~80 columns in
  anything committed to a repo — Markdown, code comments, commit message
  bodies. There the wrap is free: it keeps diffs line-scoped, and CommonMark
  treats a single newline as a soft break that collapses to a space, so the
  rendered output is unaffected.
- Never hard wrap text sent to a remote field: GitHub issue and PR bodies,
  PR/issue comments, release notes, Jira descriptions, Slack. GitHub renders
  those through GFM with `hardbreaks` enabled, so every newline becomes a
  literal `<br>` — the text is frozen at the wrap column on every screen size
  and re-wraps badly on narrow ones. Write one line per paragraph and let the
  renderer wrap. This holds even when the surrounding repo's `.md` files are
  hard wrapped, and even when the text is staged in a file first: the
  destination decides, not the neighbours or the container.

## Git and GitHub

- Only append the Claude Code session link
  (`https://claude.ai/code/session_…`) to a PR or issue body when the target
  repository is mine, or belongs to an organization I am a member of.
  Everywhere else, leave it off. It resolves to a private session nobody on
  that project can open, so it is dead weight in the description of a
  contribution that should stand on its own.
- Judge by the *target* repo, not the fork the branch lives on. A branch
  pushed to my fork but opened against a third-party upstream is a
  third-party PR. Resolve it with `gh repo view <owner>/<repo> --json owner`
  and compare against `gh api user --jq .login` plus
  `gh api user/orgs --jq '.[].login'`; do not rely on a remembered list of
  orgs, since membership changes.
- The same test applies to anything else that leaks local tooling into a
  public contribution: co-author trailers, generator notices, internal
  ticket links.
- In my personal projects, title PRs and issues with a scope prefix and a
  slug-friendly summary: `<scope>: <Summary>`, where the scope is the
  package or area the change touches (e.g. `eslint: Adopt ESLint 10`). The
  colon strips cleanly when tools derive branch or slug names from the
  title, but keep the summary itself free of characters that slug badly —
  no slashes (`6/7`), scoped package paths (`@eslint/js`), commas, or
  parentheses. Spell those out in words instead, and push detail into the
  body rather than the title.

## Long-term memory (graphiti MCP)

The `graphiti` MCP server is persistent cross-session memory. Use it
proactively — don't wait for "remember this" or "recall X".

**Recall** — before answering, call `search_memory_facts` (relationships,
"what do I/we…") or `search_nodes` (entities) when the task plausibly has
history: it names a person, project, tool, or preference; builds on a past
decision; or continues ongoing work. Skip recall for self-contained tasks
(general knowledge, one-off code, math) — each search costs latency and an
embedding call.

**Persist** — when a durable fact emerges mid-conversation, call `add_memory`
with a short descriptive name and a 1–3 sentence episode stating who/what/when.
Durable: decisions and their rationale, preferences, people and relationships,
project state and milestones, stable facts. Not durable: transient task state,
scratch details, secrets/credentials, anything stale within a week. When new
information supersedes a stored fact, persist the update as a new episode —
the graph tracks validity over time.

**Namespace** — memory is grouped by `group_id`. Omit it so the server's
configured default applies; never pass an explicit `group_id` unless the
operator asks.

**Availability is not optional.** Graphiti is the system of record, so
losing it is data loss, not an inconvenience. If the server is
disconnected, unauthenticated, or an `add_memory` call fails for any
reason:

1. Stop. Do not carry on with other work, and do not quietly fall back to
   file memory or to "I'll note this for later."
2. Say plainly that Graphiti is unavailable, what the error was, and what
   specifically has not been persisted.
3. Ask me to restore the connection (usually `/mcp`; disconnect and
   reconnect if a plain reconnect reports success but calls still fail).
4. Resume only after a write succeeds, or after I explicitly say to
   continue without it.

If I do grant that override, keep working, but track every durable fact
that went unwritten and offer to backfill as soon as the connection is
restored. Silent degradation is the failure mode to avoid: a session that
looks normal while nothing is being recorded is worse than one that stops
and says so.

Claude Code layering: built-in file memory is the hot cache (identity, active
projects, standing feedback — what every session needs in context); graphiti
is the system of record. Answer from in-context file memory first — it's free;
search graphiti when the answer isn't there or involves history/relationships.
Persist durable facts to graphiti; additionally mirror a fact into file memory
only if every future session needs it without a lookup.

## Shell Scripts Style Guide

### Default Location

When the working directory is my home directory (`~`), place new shell
scripts in `~/Scripts/` by default rather than `~` itself. If the working
directory is a project directory, follow that project's conventions
instead. If I specify a path, use the path I gave you.

### Reference Example

```bash
#!/usr/bin/env bash

#?/name     backup — Sync local directories to a remote destination
#?/version  1.0.0
#?/synopsis backup {all|custom <dirs...>}

source module

set -euo pipefail

readonly BACKUP_DIR="/var/backups"
readonly LOG_FILE="/var/log/backup.log"

#@/private
 # Log an error message to STDERR.
 #
 # @operand <message...>   Error message text
 # @stderr                 Timestamped error message
 ##
backup::_err() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

#@/private
 # Validate that required tools are installed.
 #
 # @operand <commands...>  Command names to check
 #
 # @stderr                 Missing command names
 #
 # @exit    0              All commands found
 # @exit    1              One or more commands missing
 ##
backup::_check_deps() {
  local cmd
  for cmd in "$@"; do
    if ! command -v "${cmd}" &> /dev/null; then
      backup::_err "Required command not found: ${cmd}"
      return 1
    fi
  done
}

#@/private
 # Sync directories to the backup destination.
 #
 # @env     BACKUP_DIR     Target backup directory
 # @env     LOG_FILE       Path to log file
 #
 # @operand <dirs...>      Source directories to sync
 #
 # @writes  $LOG_FILE      Rsync output
 #
 # @stdout                 Sync progress
 # @stderr                 Error messages for failed syncs
 #
 # @exit    0              All directories synced
 # @exit    1              One or more syncs failed
 ##
backup::_sync() {
  local -a sources=("$@")
  local dir
  local failed=0

  for dir in "${sources[@]}"; do
    if [[ ! -d "${dir}" ]]; then
      backup::_err "Source directory does not exist: ${dir}"
      (( failed++ ))
      continue
    fi

    echo "Syncing ${dir} → ${BACKUP_DIR}..."
    if ! rsync -az --delete "${dir}" "${BACKUP_DIR}/" \
        >> "${LOG_FILE}" 2>&1; then
      backup::_err "Failed to sync: ${dir}"
      (( failed++ ))
    fi
  done

  if (( failed > 0 )); then
    backup::_err "${failed} source(s) failed to sync"
    return 1
  fi
}

#@/command/all
 # Back up the default set of directories.
 #
 # @stderr                 Error messages
 #
 # @exit    0              Success
 # @exit    1              Sync or dependency failure
 ##
backup::all() {
  backup::_check_deps rsync || return 1
  backup::_sync /home /etc /var/lib
}

#@/command/custom
 # Back up a custom set of directories.
 #
 # @operand <dirs...>      Directories to back up
 #
 # @stderr                 Error messages
 #
 # @exit    0              Success
 # @exit    1              Sync or dependency failure
 ##
backup::custom() {
  backup::_check_deps rsync || return 1
  backup::_sync "$@"
}

#@/command
 # Sync local directories to a remote backup destination.
 #
 # @stderr                 Usage message
 #
 # @exit    1              Prints usage and exits
 ##
backup() {
  backup::_err "Usage: backup {all|custom <dirs...>}"
  return 1
}
```

- **Shell**: Use `bash` unless otherwise specified. Scripts must start with `#!/usr/bin/env bash` and minimal flags. Avoid POSIX compatibility unless required. Use `set` for options.
- **Module Framework**: Use [module-sh](https://github.com/nickawilliams/module-sh) for new scripts. Add `source module` after the shebang/shedoc header, separated by blank lines before and after. Assume it is installed and on `$PATH`. The framework handles execute-vs-source detection and argument routing automatically. When modifying existing scripts that don't use the module system, respect existing patterns. When providing standalone snippets or examples outside of a script context, don't use the module system.
- **File Naming**: Executables: no extension or `.sh`. Libraries: `.sh` and non-executable.
- **Environment**:
  - Errors: Send to `STDERR`.
  - Use functions for logging (e.g., `<script>::_err()`).

### Documentation (Shedoc)

Use the [Shedoc](https://github.com/nickawilliams/shedoc) standard for structured documentation. Three sigils:

- `#!/` — Shebang (interpreter path)
- `#?/` — File metadata (`name`, `version`, `synopsis`, `description`, `examples`, `section`, `author`, `license`)
- `#@/` — Code documentation (`command`, `subcommand <name>`, `public`, `private`)

Multi-line blocks: open with sigil, continue with ` # `, close with ` ##`. Single-line tags need no closing.

**Input tags**: `@flag`, `@option`, `@operand`, `@env`, `@stdin`, `@reads`
**Output tags**: `@exit`, `@stdout`, `@stderr`, `@sets`, `@writes`
**Metadata tags**: `@deprecated`

Value notation: `<required>`, `[optional]`, `[opt=default]`, `<variadic...>`, `[variadic...]`

Additional commenting conventions:

- Comment non-obvious or complex code.
- Use `TODO(name):` for temporary solutions.

### Formatting

- **Indentation**: 2 spaces, no tabs.
- **Line Length**: Max 80 characters. This is a shell script rule; it is not
  a general house style. See File Conventions for prose — and never apply it
  to text posted to a web UI.
- **Pipelines**: Use one segment per line if over 80 characters.
- **Control Flow**: Place `; then` and `; do` on the same line as the opening keyword. Use `fi`, `done`, etc., on their own line.
- **Quoting**:
  - Quote variables and expansions: `"${var}"`.
  - Use `"$@"` for arguments, not `$*`.
- **Tests**:
  - Use `[[ … ]]` for conditions.
  - Prefer `-z`/`-n` for strings.
  - Use `(( … ))` or `$(( … ))` for arithmetic.
- **Case Statements**: Indent cases 2 spaces. Use `;;` for separation.

### Naming Conventions

- Use lowercase with underscores for functions and variables.
- Constants and environment variables: uppercase with underscores.
- Namespace functions with `::`. This is the standard convention and is also required by the module framework for routing. If any function in a file is namespaced, all functions in that file should be namespaced.
- Use `local` for function-specific variables.
- Functions must include parentheses and braces:

  ```shell
  foo::my_func() {
    …
  }
  ```

### Features

- **ShellCheck**: Use to validate scripts.
- **Command Substitution**: Use `$(command)`, not backticks.
- **Eval**: Avoid.
- **Arrays**: Use arrays for lists. Expand safely with `"${array[@]}"`.

### Execution

- **Return Values**: Always check and handle return values.
- **Built-ins**: Prefer built-in commands over external tools.

### Script Structure

- Prefix all functions with a namespace derived from the script basename (e.g., `foo.sh` → `foo::function_name() { … }`).
- Subcommands are routed automatically: `script subcommand` invokes `script::subcommand()`.
- Include a default `<script>()` function as the fallback when no subcommand matches (e.g., `foo.sh` → `foo() { … }`). Use this for usage/help output or single-purpose scripts.
- Private helper functions should use a `_` prefix after `::` (e.g., `backup::_sync()`).
- **Function order**: private, public, subcommands, fallback, then any inline code. Deviation is fine when it aids readability (e.g., a private helper adjacent to the single subcommand that uses it).
- When using the module framework, do **not** add a manual source-guard (`if [[ "${BASH_SOURCE[0]}" == "${0}" ]]`) or trailing `main "$@"` — the framework handles this.

### Miscellaneous

- **SUID/SGID**: Forbidden on scripts. Use `sudo` instead.
- **Wildcard Expansion**: Use `./*` for filenames to avoid issues.
