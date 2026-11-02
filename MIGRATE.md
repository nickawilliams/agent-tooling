# Migration checklist

Authored customizations to pull from `~/.claude` and the Clearstory
`.claude` into this repo.

- [x] `pr` plugin (`review`, `coderabbit`, `review-slack`)
- [x] `relay` plugin (`dispatch`, `pickup`)
- [x] `review` forwarder skill
- [x] `eli5` output style
- [x] `work` plugin (`standup`, `15five`, `make-it-so` and `ready-room` from
      Clearstory)
- [ ] `make-it-so` (home, GitHub-generic; reconcile with `work:make-it-so`)
- [x] `in-my-ready-room` (as `work:ready-room`)
- [ ] `state-the-nature`
- [x] `git-stash-cleanup` (standalone skill)
- [x] `recall` (standalone skill)
- [x] `restate` (standalone skill)
- [ ] `fix-console-errors`
- [ ] `tab-triage`
- [ ] `mail-send-guard.sh` hook
- [ ] permission allowlists (settings fragment)
- [ ] `claude-vscode-wrapper.sh`
- [ ] global `CLAUDE.md` / `AGENTS.md` (currently synced from `.system`)
