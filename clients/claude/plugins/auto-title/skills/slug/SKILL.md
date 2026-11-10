---
name: slug
description: Turn an issue title into the slug that names its branch, workspace, and session, by the one set of rules auto-title uses for session titles. Use when a skill is about to name a branch or workspace from an issue title, or when the user asks what slug a title gives.
argument-hint: <title>
---

Run this, with the title on its own line between the markers, and reply
with the one line of output and nothing else:

```bash
"${CLAUDE_PLUGIN_ROOT}/auto-title" slug <<'TITLE'
$ARGUMENTS
TITLE
```

The quoted heredoc means the title needs no escaping, whatever it
contains. The output is the slug: the title's words, lowercased and
hyphenated, with a leading issue key or `Area ::` prefix dropped, an
outline prefix such as `A.` or `Part 1:` kept in front, stopwords
removed, and the rest cut to five words. `Timecard sync improvements
for the payroll integration` gives
`timecard-sync-improvements-payroll-integration`.

Use the slug exactly as printed. It is the same text auto-title puts in
the session title, so a branch named with it and the sessions for that
issue read the same. If the command prints nothing and exits 1, the
title had no words left once its references were stripped; say so and
ask for a slug.
