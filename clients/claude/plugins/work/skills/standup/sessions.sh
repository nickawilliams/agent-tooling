#!/usr/bin/env bash

#?/name     sessions — Summarize Claude Code sessions active in a time window
#?/version  1.0.0
#?/synopsis sessions <start> <end> [cwd-regex]
#?/description
 # Reads Claude Code session transcripts and prints the human prompts each
 # session received inside a time window, for the `standup` skill.
 #
 # Ships inside the `work` plugin and runs as
 # ${CLAUDE_PLUGIN_ROOT}/skills/standup/sessions.sh. House shell conventions
 # (module-sh) are deliberately not applied: a plugin script can't assume
 # tools beyond jq and a GNU-compatible date (gdate on macOS).
 ##

set -euo pipefail

readonly PROMPT_WIDTH=160

#@/private
 # Log an error message to STDERR.
 #
 # @operand <message...>   Error message text
 # @stderr                 Error message
 ##
sessions::_err() {
  echo "sessions: $*" >&2
}

#@/private
 # List the distinct Claude Code projects directories on this machine.
 #
 # @env     CLAUDE_CONFIG_DIR  Alternate config root, if set
 # @stdout                     One resolved directory per line
 ##
sessions::_roots() {
  local -a candidates=("${HOME}/.claude/projects")
  local dir

  if [[ -n "${CLAUDE_CONFIG_DIR:-}" ]]; then
    candidates+=("${CLAUDE_CONFIG_DIR}/projects")
  fi

  for dir in "${candidates[@]}"; do
    [[ -d "${dir}" ]] && (cd "${dir}" && pwd -P)
  done | sort -u
}

#@/private
 # Summarize one session transcript, or print nothing if it has no human
 # prompts inside the window.
 #
 # @operand <file>         Session JSONL transcript
 # @operand <start>        Window start, epoch seconds
 # @operand <end>          Window end, epoch seconds
 # @operand <match>        Regex the session's cwd must match
 # @stdout                 Markdown block for the session
 ##
sessions::_summarize() {
  local file="$1"
  local start="$2"
  local end="$3"
  local match="$4"

  # Keep human-typed prompts only: drop meta records, sidechains (subagent
  # traffic), tool results, and harness-injected caveats and reminders.
  # Slash-command invocations are kept, reduced to "/name args".
  jq --raw-input --raw-output --slurp \
    --argjson start "${start}" \
    --argjson end "${end}" \
    --argjson width "${PROMPT_WIDTH}" \
    --arg match "${match}" '
    [ split("\n")[]
      | select(length > 0)
      | (try fromjson catch empty)
      | select(.type == "user" and (.isMeta | not) and (.isSidechain | not))
      | select((.cwd // "") | test($match))
      | .epoch = (.timestamp | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601)
      | select(.epoch >= $start and .epoch <= $end)
      | .text = (
          .message.content
          | if type == "string" then .
            else ([.[]? | select(.type == "text") | .text] | join(" "))
            end
        )
      | .text |= (
          if test("<command-name>") then
            (capture("<command-name>(?<n>[^<]*)</command-name>").n) + " " +
            ((capture("<command-args>(?<a>[^<]*)</command-args>").a) // "")
          else . end
        )
      | select(.text | test("^\\s*<|^Caveat:|^\\[Request interrupted") | not)
      | .text |= (gsub("\\s+"; " ") | ltrimstr(" ") | .[0:$width])
      | select(.text | length > 0)
    ] | reduce .[] as $x ([]; if .[-1].text == $x.text then . else . + [$x] end)
    | . as $p
    | if ($p | length) == 0 then empty else
        ($p | sort_by(.epoch)) as $s
        | "## \($s[0].cwd // "?") (\($s[-1].gitBranch // "-"))",
          "\($s[0].epoch | localtime | strftime("%a %H:%M"))–" +
            "\($s[-1].epoch | localtime | strftime("%H:%M")), " +
            "\($s | length) prompts",
          ( (if ($s | length) > 5 then ($s[0:3] + $s[-2:]) else $s end)[]
            | "- \(.text)" ),
          ""
      end
  ' "${file}"
}

#@/command
 # Print each session with human prompts in the window: working directory,
 # branch, active span, and its first and last few prompts.
 #
 # @operand <start>        Window start, any GNU date string
 # @operand <end>          Window end, any GNU date string
 # @operand [cwd-regex=.]  Only sessions whose cwd matches this regex
 #
 # @stdout                 Markdown, one block per session
 # @stderr                 Usage and dependency errors
 #
 # @exit    0              Success, including no sessions found
 # @exit    1              Bad usage or missing dependency
 ##
sessions() {
  if (( $# < 2 || $# > 3 )); then
    sessions::_err "Usage: sessions <start> <end> [cwd-regex]"
    return 1
  fi

  if ! command -v jq &> /dev/null; then
    sessions::_err "Required command not found: jq"
    return 1
  fi

  # GNU date parses relative strings like "yesterday 09:45"; on macOS it
  # is installed as gdate.
  local date_cmd="gdate"
  if ! command -v gdate &> /dev/null; then
    if ! date -d now &> /dev/null; then
      sessions::_err "GNU date not found: install coreutils (gdate)"
      return 1
    fi
    date_cmd="date"
  fi

  local start end since root file
  local match="${3:-.}"
  start="$("${date_cmd}" -d "$1" +%s)"
  end="$("${date_cmd}" -d "$2" +%s)"
  since="$("${date_cmd}" -d "@${start}" '+%Y-%m-%d %H:%M:%S')"

  while IFS= read -r root; do
    # mtime prefilter: a transcript untouched since the window opened
    # cannot hold prompts inside it.
    while IFS= read -r file; do
      sessions::_summarize "${file}" "${start}" "${end}" "${match}"
    done < <(find "${root}" -maxdepth 2 -name '*.jsonl' -newermt "${since}")
  done < <(sessions::_roots)
}

sessions "$@"
