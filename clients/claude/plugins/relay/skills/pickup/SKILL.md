---
name: pickup
description: Take up work dispatched to this repo by an earlier session. Expands a pending dispatch, restates it, and clears it once absorbed. Use when the user asks to pick up a dispatch, wants to see what's pending here, or responds to a session-start dispatch notice.
user-invocable: true
argument-hint: "[which one]"
---

Take up work that an earlier session dispatched to this repo.

Pending dispatches live in `.claude/dispatches/*.md` relative to the
project root. Each is a kickoff prompt parked here for whenever someone got
around to it. That gap is usually days, so treat every one as potentially
stale.

Most come from a session in a different repo. Some were queued by a session
in this one, as a todo for later; `dispatches` reports those as "queued
here" rather than naming the repo back at the user.

`$ARGUMENTS`, if present, selects which dispatch: a number from a listing,
or a few words matching its summary.

## Steps

1. **List them with the bundled script, not by reading files.** Run:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/pickup/dispatches"
   ```

   It parses the queue and prints it sorted, newest first, flagging
   anything over a week old as stale. One Bash call, no file reads, no
   guesswork about format.

   Never reimplement this by globbing the directory and reading frontmatter
   yourself. The script is the one definition of how the queue is read, and
   the SessionStart hook runs the same code via its `hook` argument.

2. **Go straight to the one they meant.** Invoking `/pickup` *is* the
   request, so don't announce and ask again; that dance belongs to the
   session-start notice, which fires unprompted and has to be dismissible.
   Here:

   - One pending, or `$ARGUMENTS` identifies one → expand it now.
   - Several and no argument → show the list and ask which. Only here.
   - None → say so in one line and stop.

3. **Expand it.** Read the chosen file in full. Then, in your own words:
   restate the task, name any constraints it carries, and propose a
   concrete first move. Absorbing a dispatch is not authorization to act on
   it. Never start editing off the back of one.

4. **Ask for the go with `AskUserQuestion`.** End the expansion with the
   question as a prompt, not as a sentence trailing off into "let me know".
   A dispatch lands mid-session, often against whatever the user was
   already doing, so the answer is a real fork and deserves a real choice.
   One question, three options, matching the answers the next section
   describes:

   - **Start on it** — proceed with the first move you just proposed.
   - **Not now** — leave it pending and carry on with something else.
   - **Drop it** — delete the file without acting.

   Phrase the options against *this* dispatch rather than generically:
   "Start on the render harness" beats "Start on it". Then stop. The prompt
   is the last action in the response, but never the last text — anything
   that has to accompany it goes above the tool call, since the question
   renders as a UI component and prose after it is lost.

5. **Check the premise if it's old.** Past about a week (the script marks
   these "stale"), verify the dispatch still describes reality before
   proposing anything: does the code it names still exist, is the problem
   still there, has someone already fixed it. Say what you found. Acting on
   a stale dispatch wastes more time than the dispatch ever saved.

6. **Clear it once absorbed.** Both "start on it" and "drop it" are the
   go-ahead to delete the file; only "not now" leaves it pending. It was
   transport, and its content is now in the conversation. Taking one leaves
   any others pending. Don't delete anything the user hasn't accepted or
   explicitly dropped.

## Responses to expect

The three options cover the common answers; "Other" catches the rest, of
which this last one comes up often enough to offer unprompted.

- **"not now"**: leave everything pending, say nothing more about it, and
  carry on with whatever the user actually wants.
- **"drop it"**: delete without acting. Confirm in one line.
- **"what else did that session know?"**: the frontmatter carries `from`
  and `session`. `cd` to the source repo and `claude --resume <session>`
  reaches the originating conversation for detail the prompt didn't carry.
  If `session` is `unknown`, the newest transcript under
  `~/.claude/projects/<slugified-source-path>/` around the `at` timestamp
  is the one. Offer this when the dispatch is thin on a point that matters,
  rather than guessing at what it meant.

## Listing without a model round trip

The script has three modes, and two of them never involve a model:

| Mode | Output | Used by |
|---|---|---|
| *(none)* | human-readable list, stale flags | step 1 above |
| `count` | bare number, empty when zero | the oh-my-posh status-line segment |
| `hook` | SessionStart JSON | the plugin's `SessionStart` hook |

When the user only wants to look, they don't need this skill at all: the
status line shows a live count and the session-start notice names the
newest. This skill is for the part that genuinely needs a model: absorbing
one. `${CLAUDE_PLUGIN_ROOT}` is set when the model runs step 1, but not in
the shell behind a `!`-prefixed command, so there's no stable one-liner to
hand the user for a bare look — point them at the status line instead.

## Packaging note

The script lives inside this skill's directory on purpose, so the skill and
the code the hook runs move together. The `relay` plugin ships the
`SessionStart` hook in `hooks/hooks.json`, which runs the script as
`${CLAUDE_PLUGIN_ROOT}/skills/pickup/dispatches hook` — no hand-wired entry
in `settings.json`.

One thing outside the plugin still points at the script, and it's glue, not
part of the plugin:

- `~/.config/oh-my-posh/claude-statusline.sh` — the status-line wrapper
  that calls `dispatches count`. It exists only because oh-my-posh 30 has no
  `command` segment and resolves `glob` against its own process cwd rather
  than the session's project directory. It can't use `${CLAUDE_PLUGIN_ROOT}`
  (unset at render time), so it points at the script in the local checkout
  (`clients/claude/plugins/relay/skills/pickup/dispatches`). Update that path
  if the checkout moves.
