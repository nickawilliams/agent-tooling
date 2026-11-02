---
name: tab-triage
description: Triage open Safari tabs across all windows. Each tab is archived to GoodLinks, closed, or left open; pinned tabs are never touched.
disable-model-invocation: true
---

# Tab Triage

Goal: drop the user's tab count meaningfully without losing anything they care
about, in one session.

This is a flat router: `[open tabs] → [GoodLinks | Close | Leave open]`.

## The three destinations

| Destination | Action | When |
|---|---|---|
| **GoodLinks** | AppleScript: `make new link` with 2–4 tags | Save-for-later, reference material, "I might want this someday." DEFAULT for unclear cases. |
| **Close** | Safari MCP `safari_close_tab` | Dupes, finished reads, search-result pages, login pages, "Just a moment..." Cloudflare challenges, dead/redirect, broken. |
| **Leave open** | No-op | Currently in active use. |

**When in doubt, route to GoodLinks.** Leaving a tab open should be a positive
decision ("I'm actively using this"), not the default for ambiguous cases.

## Pinned tabs are off-limits

Pinned tabs are never closed, archived, or proposed for triage. Pinning is the
user's strongest "I'm keeping this" signal — overriding it would be the worst
possible failure mode of this skill.

Detection: pinned tabs in Safari are stored as descendants of the root-level
bookmark folder `pinned` (id=2). Per-tab-group pinned sections likely follow a
similar marker-folder structure. Filter them out at inventory time (see the SQL
in step 1).

Safari's AppleScript dictionary does **not** expose a `pinned` property on
tabs, so runtime tab inspection cannot distinguish pinned from unpinned. All
pin awareness must come from the DB inventory. This also means **close by
index is dangerous** unless you've verified from the DB that no pinned tabs
sit at lower indices in the same window — pinned tabs occupy the leftmost
slots. Prefer close-by-URL (look up the index of each URL we intend to close,
sort high-to-low, then close) over blind index ranges.

## Procedure

### 1. Inventory

Read live tab state from Safari's own DB (read-only). The query excludes any
tab that's a descendant of the root `pinned` (id=2) or `privatePinned` (id=3)
folders, so pinned tabs never enter the triage flow:

```bash
sqlite3 ~/Library/Containers/com.apple.Safari/Data/Library/Safari/SafariTabs.db "
SELECT w.id AS window_id, tg.title AS tab_group, t.id AS tab_id,
       t.title AS tab_title, t.url
FROM windows w
JOIN windows_tab_groups wtg ON wtg.window_id = w.id
JOIN bookmarks tg ON tg.id = wtg.tab_group_id
JOIN bookmarks t  ON t.parent = tg.id
WHERE w.date_closed IS NULL AND t.deleted = 0 AND t.url IS NOT NULL
  AND t.id NOT IN (
    SELECT folder_id FROM folder_ancestors WHERE ancestor_id IN (2, 3)
  )
ORDER BY w.id, tg.id, t.order_index;
"
```

Also fetch a pinned-tab count so the report can mention how many were skipped:

```bash
sqlite3 ~/Library/Containers/com.apple.Safari/Data/Library/Safari/SafariTabs.db "
SELECT COUNT(*) FROM bookmarks b
JOIN folder_ancestors fa ON fa.folder_id = b.id
WHERE fa.ancestor_id IN (2, 3) AND b.deleted = 0 AND b.url IS NOT NULL AND b.url != '';
"
```

Report starting totals (N triageable tabs across M windows, plus N pinned
skipped) before any decisions.

### 2. Pre-process (whole-inventory pass)

Done once, before iterating windows. Output is a single normalized inventory
the per-window loop draws from.

- **Dedupe** by URL across all windows. Also normalize away tracking params
  (`utm_*`, `ref`, `fbclid`).
- **Flag auto-close candidates** — propose, never auto-close:
  - Title is exactly `"Just a moment..."` (Cloudflare challenge that never resolved)
  - URL is a search-results page (`google.com/search`, `duckduckgo.com/?q=`, `bing.com/search`)
  - Title contains "Sign in" / "Log in" / "Login" / "Authentication required"
  - URL is an auth/SSO callback (`accounts.google.com/v3/signin`, `/oauth/`, `/auth/callback`)

### 3. Per-window loop

Process **one window at a time**, in order of `window_id`. The user already
tends to group related tabs by window, so the window itself is the primary
cluster. Don't pre-cluster across windows — emergent cross-window themes can be
handled by reusing tag names in GoodLinks.

For each window:

1. **Sub-cluster within the window** by domain or topic if it helps the user
   eyeball the proposal. A 6-tab window usually doesn't need sub-clustering.
2. **Present the per-window proposal** with a destination for each
   sub-cluster / tab. Use `AskUserQuestion` only when the destination is
   genuinely ambiguous; for clear proposals, prose + "approve / change?" is
   faster.
3. **Execute** the closes + GoodLinks archives for that window (see step 4).
4. **Tidy the window** (see step 5) before moving to the next.

For Work tabs (Jira tickets, internal dashboards, ticket-specific docs), be
conservative — propose Leave open unless the user signals they're done with
that context.

Example per-window proposal:

> **Window 10647 — "To Organize" (25 tabs)**
> - Mermaid Live Editor × 3 → **Close** (per user instruction)
> - Document-management cluster (5: paperless-ngx, DEVONthink ×2, Docspell, alternatives reddit) → **GoodLinks** `document-management`, `selfhosted`
> - Safari MCP options × 3 → **GoodLinks** `mcp`, `safari`
> - "Just a moment..." × 1 → **Close** (auto)
> - … (continues)

### 4. Execute (per window)

#### GoodLinks

AppleScript, batched per window:

```applescript
tell application "GoodLinks"
  make new link with properties {url:"https://example.com/foo", tag names:{"terminal", "reference"}}
  make new link with properties {url:"https://example.com/bar", tag names:{"terminal"}}
end tell
```

Pick 2–4 tags per link. Mix specific (`oh-my-posh`) and general (`terminal`,
`reference`). GoodLinks tags are flat — no hierarchy. Reuse the same tag names
across windows so cross-window themes are findable in GoodLinks even though we
didn't cross-cluster up front.

After archiving, close the source tab in Safari — GoodLinks does not.

#### Close

Use AppleScript to close by tab index within the target window, from **highest
index to lowest** (indices shift after each close).

**Look up the index for each URL we intend to close** rather than passing a
blind range — pinned tabs occupy the leftmost slots and AppleScript can't
distinguish them, so a range like `1..N` would happily close a pinned tab.
The inventory query already excluded pinned tabs, so anything in our close set
is safe; the danger is only that other tabs in the window may be pinned at
indices we'd otherwise sweep through.

```applescript
tell application "Safari"
  set wTarget to window id 10640
  set urlsToClose to {"https://example.com/a", "https://example.com/b"}
  set tcount to count of tabs of wTarget
  set indicesToClose to {}
  repeat with i from 1 to tcount
    if urlsToClose contains (URL of tab i of wTarget) then
      set indicesToClose to {i} & indicesToClose -- prepend, so list is high-to-low
    end if
  end repeat
  repeat with idx in indicesToClose
    close tab idx of wTarget
  end repeat
end tell
```

Safari MCP's `safari_close_tab` only operates on the frontmost window, so it's
not usable for non-foreground windows — prefer AppleScript with `window id`.

#### Leave open

No-op on the tab itself. If the tab lives in a tab group, "leave open" means
"keep accessible," not "keep the window open" — see step 5.

### 5. Tidy window (per window, immediately after execute)

If, after this window's executes, the window's remaining tabs are all
"leave open" AND the window is bound to a tab group (the inventory's
`tab_group` column was non-empty for it), close the window. Tabs in a tab group
are persisted regardless of whether any window is currently displaying them —
reopen the tab group from Safari's sidebar to get them back. Closing the window
reduces visible noise for subsequent windows' triage.

If all the window's tabs were closed/archived (none left), Safari closes the
window automatically — nothing to do.

Skip the close when:

- The window is **not** bound to a tab group (ad-hoc window — closing it
  discards the remaining tabs).
- The user has signalled active monitoring of those tabs (dashboard refresh,
  in-progress form, ephemeral environment they're watching).

Close via AppleScript:

```applescript
tell application "Safari" to close window id 10640
```

Don't ask per window — apply the policy above by default. Mention which
windows you closed in the final report.

### 6. Report

Tight summary at the end:

- Started: N triageable tabs across M windows (+ N pinned, untouched)
- Archived to GoodLinks: N (broken down by tag bundle)
- Closed: N
- Left open: N
- Windows closed during tidy: N
- Ended: N tabs visible

## Notes

- `SafariTabs.db` is read-only for our purposes. Writing directly is unsafe — the
  `SafariBookmarksSyncAgent` daemon and iCloud Tabs sync use opaque `sync_data`
  BLOBs and CloudKit metadata that hand-rolled writes can't reproduce. Use
  AppleScript or the Safari MCP for any mutations.
- Private browsing tabs are not in `SafariTabs.db` and are out of scope.
- GoodLinks lives at `/Applications/GoodLinks.app`. If it's missing, stop and
  tell the user rather than picking a different archive destination silently.
