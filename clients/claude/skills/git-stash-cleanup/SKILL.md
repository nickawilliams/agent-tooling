---
name: git-stash-cleanup
description: Review git stashes and recommend which are safe to drop. Use when the user wants to clean up stashes.
disable-model-invocation: true
user-invocable: true
argument-hint: ""
---

Review each stash in this repository and produce the following report as a numbered list (one line per stash):

```
{stash index}. {recommendation symbol} [{commit hash prefix}] {one-sentence summary explaining what the changes do}
```

For the `{recommendation symbol}` use the following character and color:
- ✓ (green): safe to drop — the changes are no longer relevant to the current state of the codebase, or were obvious temporary changes used during development that have no value in being preserved
- ✘ (red): not safe to drop — although there may be some drift, the stashed changes address a problem or make an improvement to code that is still present in some form in HEAD
- ? (orange): unclear — either the diff is too large or is not self-explanatory enough to make a clear determination either way; further investigation is required

The `{commit hash prefix}` is the first 7 characters of the stash commit hash (from `git rev-parse stash@{N}`). Include this as an anchor so each summary is verifiably tied to a specific stash object.

**Important — verification pass:** After generating the initial list, make a second pass over every entry. For each entry, re-read the actual diff (`git stash show -p`) and confirm that the summary accurately describes that diff and that the commit hash matches the stash index. If any entry was misattributed, correct it before presenting the final list. Do not skip this step.

After presenting the final list, ask whether I'd like to proceed with dropping all stashes marked ✓, using a single chained command that drops indices in reverse order to preserve index stability during execution. If I confirm and the drops are executed, verify the remaining stashes by reading each surviving stash's diff and confirming it matches one of the entries that was marked ✘ or ?. If any stash was incorrectly dropped or an unexpected stash survived, recover the missing stashes using `git stash store` with the ref hashes from the drop output, and drop the ones that should not have survived.
