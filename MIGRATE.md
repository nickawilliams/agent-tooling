# Migration checklist

Authored customizations to pull from `~/.claude` and the Clearstory
`.claude` into this repo.

- [x] `pr` plugin (`review`, `coderabbit`, `review-slack`)
- [x] `relay` plugin (`dispatch`, `pickup`)
- [x] `review` forwarder skill
- [x] `eli5` output style
- [x] `work` plugin (`standup`, `15five`; `make-it-so`, `ready-room`, and
      `state-the-nature` from Clearstory)
- [ ] `make-it-so` (home, GitHub-generic; reconcile with `work:make-it-so`)
- [x] `in-my-ready-room` (as `work:ready-room`)
- [x] `state-the-nature` (as `work:state-the-nature`)
- [x] `git-stash-cleanup` (standalone skill)
- [x] `recall` (standalone skill)
- [x] `restate` (standalone skill)
- [x] `fix-console-errors` (standalone skill, rewritten on arrival)
- [ ] `tab-triage`
- [x] `mail-send-guard.sh` hook (standalone hook)
- [ ] `claude-vscode-wrapper.sh`
- [ ] global `CLAUDE.md` / `AGENTS.md` (currently synced from `.system`)
