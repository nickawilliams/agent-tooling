---
name: auto-title
description: Show which skills set the session title automatically and whether auto-title is healthy. Use when the user runs /auto-title, asks why a session was or wasn't renamed, or asks how to make a skill name its session.
disable-model-invocation: true
---

Run this and show its output verbatim in a code block, without
summarizing or reordering it:

```bash
CLAUDE_PLUGIN_DATA="${CLAUDE_PLUGIN_DATA}" "${CLAUDE_PLUGIN_ROOT}/auto-title" status
```

It reports on the most recently started session, which is usually this
one. If it reports problems, add one line per problem saying what fixes
it:

- `claude` or `jq` not on `PATH`: the hook inherits the environment that
  launched Claude Code; launch it from a shell where both resolve.
- Not among the plugins Claude Code lists: the plugin was loaded with
  `--plugin-dir`, which the plugin list omits. Install it from a
  marketplace instead.
- No index for this session: the `SessionStart` hook did not run. Check
  `/hooks`, then start a new session.

If the user asks how to make a skill name its session: put an executable
named `auto-title` beside that skill's `SKILL.md`. It receives the
`UserPromptSubmit` hook payload (JSON with `prompt`, `cwd`, and
`session_id`) on stdin, runs in the session's working directory, and
prints one line. Printing nothing declines. The line is normally a JSON
object of title fields, which the plugin assembles into the house format
`[<issue> · ]<name> · <verb>[ → <target>]`:

```json
{"issue": "EX-1337", "name": "Timecard sync drops overtime",
 "verb": "review", "target": "api#3442"}
```

gives `EX-1337 · timecard sync drops overtime · review → api#3442`.
Every field is optional; `issue` is the issue key, `name` the issue's or
PR's title (the plugin lowercases it, strips a leading key or `Area ::`
prefix, and shortens it to fit), `verb` what the session does, and
`target` what the verb acts on. A title needs an issue, a name, or a
target. Any line that isn't a JSON object is used as the title verbatim.

The skill then answers to both `/<plugin>:<skill>` and bare `/<skill>`;
no pattern is written. The new handler is picked up at the next session
start. An existing title, whether from `/rename` or an earlier handler,
is never overwritten.
