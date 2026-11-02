---
name: fix-console-errors
description: Work through a web app's browser console errors and warnings one at a time, reading the console through a connected browser tool, fixing each, verifying it is gone, and committing each fix on its own. Use when the user wants the console cleaned up.
disable-model-invocation: true
argument-hint: "[url]"
---

Clear the browser console of the app at $ARGUMENTS, one entry at a
time. Each fix is verified against the live console before and after,
and lands as its own commit.

## Reach the console

Read the console yourself through whichever browser tool this session
has. In order of preference:

1. A tab already showing the app, in any connected browser tool.
2. Scape's browser (`scape_browser_*`), when running inside Scape.
3. Claude in Chrome (`mcp__claude-in-chrome__*`), loading its tools with
   one ToolSearch call and following its skill first.
4. The Safari or Chrome MCP servers.

With a URL argument, open it in that tool. Without one, use the tab
that shows the app, or ask for the URL. If no browser tool is connected,
ask the user to paste the console output and to reload when told to;
the rest of the workflow is the same, only slower.

Capture errors and warnings from a fresh load: clear the console,
reload, let the page settle, then read. Repeat the reads for any
interaction the user names as part of the reproduction.

## Build the list

Group repeated entries into one item: the same message from the same
source, logged once per render or per request, is one problem. Record
for each item the level, the message, the source location if the
console gives one, and the count. Order by level (errors first), then
by count. Present the list and the planned order before changing
anything. Entries from browser extensions or third-party scripts the
repo can't change are listed, marked out of scope, and skipped.

Track progress with the todo list, one item per problem, exactly one
`in_progress` at a time.

## Work the list

For each item:

1. Clear the console, reload, and confirm the entry is still there.
   Earlier fixes often clear later entries; a resolved item is marked
   done with a note saying which fix cleared it.
2. Find the cause in the code and fix it. Fix the cause, not the
   symptom: silencing a warning or wrapping a throw is not a fix unless
   the user asks for exactly that.
3. Clear the console, reload, and read it again. The entry must be gone
   and no new entry may have appeared. If the entry persists, keep
   working on it; if a new one appeared, it joins the list as a new
   item and this fix is not committed until it is understood.
4. Commit the fix on its own. Follow the repo's commit conventions
   (CLAUDE.md, AGENTS.md, recent history). Absent a convention, use
   Conventional Commits with the area touched as scope and a summary of
   the fix, not of the error:

   ```
   fix(<area>): <what changed>

   Clears the console <level>: <message, trimmed to identify it>
   ```

5. Mark the item done and move to the next.

Don't batch fixes into one commit, and don't commit while an item's
verification is pending.

## Finish

Reload one last time and read the console. Report what was fixed, with
one commit hash each, anything left and why (out of scope, needs a
decision, couldn't reproduce), and any entry that appeared during the
work.
