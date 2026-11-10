#!/usr/bin/env bash

#?/name     auto-title.sh — Title fields for the Jira lifecycle skills
#?/version  2.1.0
#?/synopsis source "${BASH_SOURCE[0]%/*}/../../lib/auto-title.sh"
#?/description
 # Sourced by the auto-title handlers beside make-it-so, ready-room, and
 # state-the-nature. A handler is two lines: source this file and call
 # work_title::run with its verb. The run reads the UserPromptSubmit
 # payload, resolves the issue and its name, and prints the title fields
 # as JSON for the auto-title plugin to assemble into
 # `EX-1337 · timecard-sync-drops-overtime · implement`. Printing nothing
 # declines.
 #
 # Resolution order, the same for all three skills. The issue is the
 # prompt's first operand when that is a Jira key (any case) or a Jira
 # /browse/ URL, else the single key in the branch name, else the single
 # key in the last components of the working directory; make-it-so also
 # takes a plain number as a GitHub issue. The name is the slug after
 # the key in the branch name, else in the workspace name, which is the
 # same across every session of the issue; else a `--slug` typed on the
 # prompt, which make-it-so will name the branch with; else the issue's
 # Jira summary, for sessions that start before a workspace exists,
 # which the plugin slugifies by the same rules make-it-so names
 # branches with. Without an issue, the name is the typed slug or the
 # free-text argument; a URL, a file path, or no argument gives no
 # title.
 #
 # The Jira lookup is opportunistic: a hook has no MCP, so when the
 # working directory is inside a foreman project this reads the tracker
 # credentials with `foreman config get` and makes one read-only REST
 # call, and anywhere else it is skipped. The token goes to curl on
 # stdin, never on a command line, and is never printed. A "not found"
 # answer also settles a key-shaped operand that isn't a key (`utf-8`):
 # it is treated as free text, as the skills treat it.
 #
 # Needs bash and jq; git, foreman, curl, and gh only for what they
 # fetch. No module-sh, as with every script a hook runs here.
 ##

# A Jira key with a letters-only project prefix, which keeps hex path
# segments from reading as keys, preceded by a non-word character or
# the start of the string. No trailing boundary: `EX-123_slug` is a key.
readonly WORK_TITLE_KEY_PATTERN='(^|[^A-Za-z0-9])([A-Za-z]{2,10}-[0-9]+)'

# Prefixes that look like project keys and aren't.
readonly WORK_TITLE_NOT_KEYS=" UTF SHA ISO HTTP TLS SSL CVE RFC PEP MD UTC "

#@/private
 # Print every Jira key in a string, upper-cased, one per line.
 #
 # @operand <text>         Text to scan
 #
 # @stdout                 Keys in order of appearance, possibly repeated
 ##
work_title::_keys() {
  local text="${1}" key

  while [[ "${text}" =~ ${WORK_TITLE_KEY_PATTERN} ]]; do
    key="$(printf '%s' "${BASH_REMATCH[2]}" | tr '[:lower:]' '[:upper:]')"
    [[ "${WORK_TITLE_NOT_KEYS}" == *" ${key%%-*} "* ]] || printf '%s\n' "${key}"
    text="${text#*"${BASH_REMATCH[2]}"}"
  done
}

#@/private
 # Print the one distinct key in a string, or nothing.
 #
 # @operand <text>         Text to scan
 #
 # @stdout                 The key when exactly one is found
 ##
work_title::_single_key() {
  local keys

  keys="$(work_title::_keys "${1}" | sort -u)"
  [[ -n "${keys}" && "${keys}" != *$'\n'* ]] && printf '%s' "${keys}"
  return 0
}

#@/private
 # Print the argument: everything after the command word.
 #
 # @operand <prompt>       The typed prompt
 #
 # @stdout                 The argument, trimmed; empty if none
 ##
work_title::_argument() {
  local arg=""

  [[ "${1}" =~ ^/[^[:space:]]*[[:space:]]*(.*)$ ]] && arg="${BASH_REMATCH[1]}"
  arg="${arg%"${arg##*[![:space:]]}"}"
  printf '%s' "${arg}"
}

#@/private
 # Print the key an operand names, upper-cased, or nothing.
 #
 # @operand <operand>      A Jira key in any case, or a /browse/ URL
 #
 # @stdout                 The key
 ##
work_title::_operand_key() {
  local operand="${1}" key

  if [[ "${operand}" =~ ^([A-Za-z]{2,10}-[0-9]+)$ ]] \
      || [[ "${operand}" =~ /browse/([A-Za-z]{2,10}-[0-9]+) ]]; then
    key="$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:lower:]' '[:upper:]')"
    [[ "${WORK_TITLE_NOT_KEYS}" == *" ${key%%-*} "* ]] || printf '%s' "${key}"
  fi
}

#@/private
 # Print the one key in the current branch name, or nothing.
 #
 # @stdout                 The key
 ##
work_title::_branch_key() {
  local branch

  branch="$(git branch --show-current 2>/dev/null)" || return 0
  work_title::_single_key "${branch}"
}

#@/private
 # Print the one key in the last four path components, or nothing.
 #
 # @stdout                 The key
 ##
work_title::_path_key() {
  work_title::_single_key "$(pwd | tr '/' '\n' | tail -4 | tr '\n' '/')"
}

#@/private
 # Print the text that follows a key in the branch or workspace name.
 #
 # Workspaces and branches are named `<KEY>-<slug>` or `<KEY>_<slug>`;
 # the slug is the offline stand-in for the issue's summary.
 #
 # @operand <key>          The issue key
 #
 # @stdout                 The slug, hyphens and underscores intact
 ##
work_title::_env_slug() {
  local key="${1}" candidate branch i
  local -a parts candidates

  branch="$(git branch --show-current 2>/dev/null)" || branch=""
  candidates=("${branch}")
  # The branch first, then the path from its innermost component out.
  IFS='/' read -r -a parts <<< "${PWD}"
  for (( i = ${#parts[@]} - 1; i >= 0 && i >= ${#parts[@]} - 4; i-- )); do
    candidates+=("${parts[i]}")
  done

  shopt -s nocasematch
  for candidate in "${candidates[@]}"; do
    [[ -n "${candidate}" ]] || continue
    if [[ "${candidate}" =~ (^|[^A-Za-z0-9])${key}[-_]([^/]+) ]]; then
      shopt -u nocasematch
      printf '%s' "${BASH_REMATCH[2]}"
      return 0
    fi
  done
  shopt -u nocasematch
  return 0
}

#@/private
 # Fetch an issue's summary from Jira, when the surroundings allow it.
 #
 # Looks up from the working directory for a foreman project, reads the
 # tracker's base URL, email, and token with `foreman config get`, and
 # makes one GET with a short timeout. The token reaches curl through a
 # config on stdin, so it never appears on a command line.
 #
 # @operand <key>          The issue key
 #
 # @stdout                 The summary
 #
 # @exit    0              Found
 # @exit    1              Not attempted or failed; nothing is known
 # @exit    4              Jira reports no such issue
 ##
work_title::_jira_summary() {
  local key="${1}" dir base email token out code body

  command -v foreman >/dev/null 2>&1 || return 1
  command -v curl >/dev/null 2>&1 || return 1

  dir="${PWD}"
  while [[ ! -f "${dir}/.foreman/config.yaml" ]]; do
    [[ "${dir}" == "/" || -z "${dir}" ]] && return 1
    dir="${dir%/*}"
    dir="${dir:-/}"
  done

  base="$(foreman config get issue_tracker.base_url --project "${dir}" \
    2>/dev/null)" || return 1
  email="$(foreman config get issue_tracker.email --project "${dir}" \
    2>/dev/null)" || return 1
  token="$(foreman config get issue_tracker.token --project "${dir}" \
    2>/dev/null)" || return 1
  [[ -n "${base}" && -n "${email}" && -n "${token}" ]] || return 1

  out="$(curl -sS --max-time 3 -K - -H 'Accept: application/json' \
    -w $'\n%{http_code}' \
    "${base%/}/rest/api/3/issue/${key}?fields=summary" 2>/dev/null \
    <<< "user = \"${email}:${token}\"")" || return 1
  code="${out##*$'\n'}"
  body="${out%$'\n'*}"

  case "${code}" in
    200) jq -r '.fields.summary // empty' <<< "${body}" 2>/dev/null ;;
    404) return 4 ;;
    *)   return 1 ;;
  esac
}

#@/private
 # Fetch a GitHub issue's title from the `origin` remote's repository.
 #
 # @operand <number>       The issue number, digits only
 #
 # @stdout                 The title, or nothing
 ##
work_title::_github_title() {
  local number="${1}" remote

  command -v gh >/dev/null 2>&1 || return 0
  remote="$(git remote get-url origin 2>/dev/null)" || return 0
  remote="${remote%.git}"
  remote="${remote%/}"
  [[ "${remote}" =~ [:/]([^/:]+)/([^/]+)$ ]] || return 0
  gh api "repos/${BASH_REMATCH[1]}/${BASH_REMATCH[2]}/issues/${number}" \
    --jq '.title // empty' 2>/dev/null
  return 0
}

#@/private
 # Print a free-text argument as a name, or nothing.
 #
 # A URL or an existing file is not free text: naming a session after
 # either gives gibberish, so the caller declines instead. The text is
 # passed whole; the plugin drops its stopwords and caps the words.
 #
 # @operand <argument>     The whole argument
 #
 # @stdout                 The argument, or nothing
 ##
work_title::_text_name() {
  local arg="${1}" path

  [[ -n "${arg}" ]] || return 0
  [[ "${arg}" =~ ^[A-Za-z][A-Za-z0-9+.-]*:// ]] && return 0
  path="${arg/#\~/${HOME}}"
  [[ -f "${path}" ]] && return 0

  printf '%s' "${arg}"
}

#@/public
 # Resolve the title fields for a prompt and print them as JSON.
 #
 # Reads the UserPromptSubmit payload on stdin. Prints nothing when no
 # issue and no name can be found, which auto-title treats as declining.
 #
 # @operand <verb>         The skill's verb: implement, plan, or triage
 # @flag    --numbers      A plain-number operand is a GitHub issue
 #
 # @stdin                  UserPromptSubmit hook payload
 #
 # @stdout                 `{"issue","name","slug","verb"}`, or nothing
 #
 # @exit    0              Always
 ##
work_title::run() {
  local verb="${1}" numbers=0
  local payload prompt arg operand issue="" name="" slug="" typed=""
  local from_operand=0 rc

  [[ "${2:-}" == "--numbers" ]] && numbers=1
  payload="$(cat)"
  command -v jq >/dev/null 2>&1 || return 0

  prompt="$(jq -r '.prompt // empty' <<< "${payload}")"
  arg="$(work_title::_argument "${prompt}")"

  # A typed `--slug <slug>` is the name make-it-so will give the branch,
  # so it is the name here too. It is lifted out of the argument so it
  # never reads as the operand or as free text.
  if [[ "${arg}" =~ (^|[[:space:]])--slug[=[:space:]]+([^[:space:]]+) ]]; then
    typed="${BASH_REMATCH[2]}"
    arg="${arg/"${BASH_REMATCH[0]}"/ }"
    arg="${arg#"${arg%%[![:space:]]*}"}"
    arg="${arg%"${arg##*[![:space:]]}"}"
  fi
  operand="${arg%%[[:space:]]*}"

  # Issue: operand, then branch, then path.
  issue="$(work_title::_operand_key "${operand}")"
  if [[ -z "${issue}" && "${numbers}" -eq 1 \
      && "${operand}" =~ ^#?([0-9]+)$ ]]; then
    issue="#${BASH_REMATCH[1]}"
  fi
  [[ -n "${issue}" ]] && from_operand=1
  [[ -n "${issue}" ]] || issue="$(work_title::_branch_key)"
  [[ -n "${issue}" ]] || issue="$(work_title::_path_key)"

  # Name: the slug beside the key in the branch or workspace, else the
  # typed slug, else the tracker's title.
  if [[ "${issue}" == "#"* ]]; then
    slug="${typed}"
    [[ -n "${slug}" ]] || name="$(work_title::_github_title "${issue#\#}")"
  elif [[ -n "${issue}" ]]; then
    slug="$(work_title::_env_slug "${issue}")"
    [[ -n "${slug}" ]] || slug="${typed}"
    if [[ -z "${slug}" ]]; then
      name="$(work_title::_jira_summary "${issue}")"
      rc=$?
      if (( rc == 4 && from_operand )); then
        # A key-shaped operand Jira doesn't know is free text; the
        # issue, if any, comes from the surroundings instead.
        issue="$(work_title::_branch_key)"
        [[ -n "${issue}" ]] || issue="$(work_title::_path_key)"
        name=""
        if [[ -n "${issue}" ]]; then
          slug="$(work_title::_env_slug "${issue}")"
          [[ -n "${slug}" ]] \
            || name="$(work_title::_jira_summary "${issue}")" || name=""
        fi
      fi
    fi
  fi

  # No issue: the typed slug, else the free text itself, else nothing.
  if [[ -z "${issue}" ]]; then
    slug="${typed}"
    [[ -n "${slug}" ]] || name="$(work_title::_text_name "${arg}")"
    [[ -n "${slug}${name}" ]] || return 0
  fi

  jq -nc --arg issue "${issue}" --arg name "${name}" --arg slug "${slug}" \
    --arg verb "${verb}" '{issue: $issue, name: $name, slug: $slug, verb: $verb}'
}
