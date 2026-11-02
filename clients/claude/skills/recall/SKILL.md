---
name: recall
description: Find the Claude Code session where a given commit was made or referenced. Use when the user wants to find conversation context for a specific commit.
user-invocable: true
argument-hint: "<commit-ish>"
---

Find the Claude Code session associated with the given commit. The argument is a git commit-ish (hash, short hash, branch name, HEAD~N, etc.).

## Step 1 — Resolve the commit

Run `git rev-parse <argument>` and `git log --format="%H %aI %s" -1 <argument>` to get the full hash, author timestamp, and subject. If the argument is invalid, tell the user and stop.

Store these values for later:
- `COMMIT_HASH` — full 40-char hash
- `COMMIT_SHORT` — first 7 chars
- `COMMIT_TS` — author timestamp (ISO 8601)
- `COMMIT_SUBJECT` — subject line

## Step 2 — Search by timestamp proximity (primary method)

The commit was likely made *during* a session. Search `~/.claude/history.jsonl` for sessions in the same project directory whose activity window spans the commit timestamp.

**Important:** The current working directory may be a symlink. The project path stored in `history.jsonl` may be either the symlink path or the resolved real path. To handle this, resolve both `$(pwd)` and `$(pwd -P)` (physical path) and match against either.

Also derive the Claude project directory slug — this is the path with `/` replaced by `-` and leading `-` stripped, prefixed with `-`. For example `/Users/foo/my-project` becomes `-Users-foo-my-project`. You need this for the fallback hash search in Step 3. Try both the `pwd` and `pwd -P` variants and use whichever directory exists under `~/.claude/projects/`.

Use a script like this to find candidate sessions:

```bash
python3 -c "
import json, os, sys
from datetime import datetime
from pathlib import Path

commit_ts_str = sys.argv[1]
cwd = sys.argv[2]
cwd_real = sys.argv[3]

ct = datetime.fromisoformat(commit_ts_str)
commit_ms = int(ct.timestamp() * 1000)

project_dirs = {cwd, cwd_real}

sessions = {}
history = Path.home() / '.claude' / 'history.jsonl'
with open(history) as f:
    for line in f:
        obj = json.loads(line.strip())
        if obj.get('project') not in project_dirs:
            continue
        sid = obj.get('sessionId', '')
        if not sid:
            continue
        ts = obj.get('timestamp', 0)
        msg = obj.get('display', '')
        if sid not in sessions:
            sessions[sid] = {'first_ts': ts, 'last_ts': ts, 'first_msg': msg, 'count': 0}
        sessions[sid]['first_ts'] = min(sessions[sid]['first_ts'], ts)
        sessions[sid]['last_ts'] = max(sessions[sid]['last_ts'], ts)
        sessions[sid]['count'] += 1

buffer = 300000  # 5 min
matches = []
for sid, info in sessions.items():
    if info['first_ts'] - buffer <= commit_ms <= info['last_ts'] + buffer:
        matches.append((sid, info))

matches.sort(key=lambda x: abs(commit_ms - (x[1]['first_ts'] + x[1]['last_ts']) // 2))

if matches:
    print('TIMESTAMP_MATCHES')
    for sid, info in matches:
        f_dt = datetime.fromtimestamp(info['first_ts']/1000)
        l_dt = datetime.fromtimestamp(info['last_ts']/1000)
        print(f'{sid}|{f_dt}|{l_dt}|{info[\"count\"]}|{info[\"first_msg\"][:120]}')
else:
    print('NO_TIMESTAMP_MATCHES')
" "$COMMIT_TS" "$(pwd)" "$(pwd -P)"
```

## Step 3 — Search by commit hash reference (fallback)

If Step 2 finds no matches, or as supplementary evidence, search for the commit hash (both full and short) in the session tool-result files and JSONL transcripts under the Claude project directory:

```bash
# Derive the Claude project slug from both cwd variants; use whichever exists
for p in "$(pwd)" "$(pwd -P)"; do
  slug=$(echo "$p" | tr '/' '-')
  dir="$HOME/.claude/projects/$slug"
  if [ -d "$dir" ]; then
    grep -rl "$COMMIT_SHORT" "$dir" 2>/dev/null
    break
  fi
done
```

Map any matching files back to their session ID (the UUID directory name they live under).

## Step 4 — Present results

Format the output as follows:

### Header
```
Commit: {COMMIT_SHORT} — {COMMIT_SUBJECT}
Date:   {COMMIT_TS}
```

### If exactly one timestamp match
Present the session details and tell the user they can resume it:

```
Session: {session_id}
Active:  {start_time} → {end_time} ({message_count} messages)
Context: {first_message_preview}

Resume with: /resume {session_id}
```

### If multiple timestamp matches
Present all matches as a numbered list:

```
Multiple sessions were active around this commit:

1. {session_id}
   Active: {start} → {end} ({count} messages)
   Context: {first_msg}

2. ...

Resume one with: /resume {session_id}
```

### If no timestamp matches but hash references found
```
No session was active when this commit was authored, but it was
referenced in these sessions:

1. {session_id} (found in: {file_path})
   ...
```

### If no matches at all
```
No session found for this commit. It was likely made outside of Claude Code.
```
