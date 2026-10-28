---
name: review
description: Review a pull request. Forwards to the pr plugin's review skill.
argument-hint: "[pr-number] [--comments=<none|post|submit>] [--level=<severity>] [--watch=<off|on>] [--fresh]"
disable-model-invocation: true
---

Invoke the `pr:review` skill, passing these arguments through unchanged:
$ARGUMENTS

This skill only claims the bare `/review` name, which otherwise belongs to
the built-in `/code-review` alias. All behavior lives in `pr:review`.
