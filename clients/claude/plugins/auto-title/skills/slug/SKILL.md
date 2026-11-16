---
name: slug
description: Turn an issue title into the slug that names its branch, workspace, and session, the one auto-title uses for session titles, picked by a model once per title and cached. Use when a skill is about to name a branch or workspace from an issue title, or when the user asks what slug a title gives.
argument-hint: <title>
---

Run this, with the title on its own line between the markers, and reply
with the one line of output and nothing else:

```bash
CLAUDE_PLUGIN_DATA="${CLAUDE_PLUGIN_DATA}" "${CLAUDE_PLUGIN_ROOT}/auto-title" slug <<'TITLE'
$ARGUMENTS
TITLE
```

The quoted heredoc means the title needs no escaping, whatever it
contains. The output is the slug: two to five lowercase words,
hyphenated, chosen by a short headless model call (a couple of seconds)
and cached under the plugin's data directory, so the same title gives
the same slug to every later caller, including the hook that titles
sessions. A leading issue key or `Area ::` prefix is dropped before the
lookup, so `EX-1337: Timecard sync improvements for the payroll
integration` and the bare summary give the same slug, such as
`timecard-sync-improvements`. When the model is off or unreachable, a
fixed rule answers instead: stopwords removed, the first five words.

Use the slug exactly as printed. It is the same text auto-title puts in
the session title, so a branch named with it and the sessions for that
issue read the same. If the command prints nothing and exits 1, the
title had no words left once its references were stripped; say so and
ask for a slug.
