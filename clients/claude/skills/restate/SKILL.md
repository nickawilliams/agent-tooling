---
name: restate
description: Rewrite the previous assistant message plainly and clearly so it is easier to process and absorb. Use when the user invokes /restate or asks for the last message to be said more plainly, simply, or coherently.
---

# Restate

Rewrite your most recent substantive message so a reader encountering it
cold can absorb it in one pass. If arguments were provided with the
invocation, treat them as direction (a part to focus on, a complaint to
address); otherwise restate the whole message.

This is a rewrite, not new work. Do not run tools, re-investigate, or
change any conclusion. If while rewriting you notice a real gap or error
in the original, flag it explicitly in one line at the end rather than
silently patching it.

## Audience reset

Write for a reader who saw only your prose messages. They did not see
tool calls, shell commands, command output, file contents, or anything
in your thinking. Any fact that came from those places must be stated
plainly in the message itself, including where it came from when that
matters ("the build log shows...", "in `config.yaml`, the timeout is
set to 30s").

Do not reference labels, codenames, numbering, or shorthand you invented
earlier in the conversation. Expand every such reference into what it
actually means, in place.

## Structure

1. Lead with the outcome: the answer, the result, or the state of
   things. The first sentence should be what the reader would ask for
   if they said "just give me the TLDR."
2. Follow with supporting detail in order of importance to the reader,
   not in the order you discovered it. Connect facts into one narrative
   thread; explain how each relates to the outcome rather than listing
   observations side by side.
3. End with anything that needs the reader: a decision, a question, a
   next step. Keep these separate from the explanation so they are not
   buried.

## Language

- Complete sentences and plain prose. No fragments, no arrow chains
  (`A -> B -> fails`), no telegraphic compression.
- Spell out technical terms on first use if their meaning is not
  obvious from context.
- Be selective rather than compressed: include only facts that change
  the reader's understanding or their next action, and drop the rest
  entirely. What survives gets written out fully.
- Preserve exact values the reader may need verbatim: paths, commands,
  numbers, error text, names.

## Delivery

Output the restatement directly, with no preamble ("Here's a clearer
version...") and no meta-commentary about the rewriting. The result
should read as if it were the message you sent the first time.
