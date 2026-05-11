#!/usr/bin/env bash
# Auto-format the file the agent just wrote, if a formatter is available for
# its extension. Silent on success and on missing formatters. Always exits 0.
#
# Triggered by the PostToolUse(Write|Edit) hook in hooks.json. Reads the hook
# payload (JSON) on stdin and extracts the file path from it. For direct/manual
# invocation, also accepts the file path as $1.
#
# Environment variables:
#   TRIAD_NO_AUTOFORMAT=1   Bypass entirely (e.g. you have your own format-on-save).
#   TRIAD_HOOK_TRACE=1      Append a diagnostic line per invocation to the log.
#                           Defaults to 0 (off). Turn on when debugging whether
#                           the hook is firing or which formatter ran.
#   TRIAD_HOOK_LOG=path     Log destination. Defaults to <cwd>/.triad/hook.log
#                           (project-level, next to plan files; .triad/ is
#                           gitignored per the README). Falls back to
#                           /tmp/triad-hook.log if .triad/ can't be created.
#   TRIAD_HOOK_NOTIFY=0     Suppress the hookSpecificOutput.additionalContext
#                           message that gets injected back into the agent's
#                           context after a formatter runs (so the user sees
#                           "auto-formatted X with prettier" in the agent's
#                           reply). Defaults to 1 (on).
#
# Initial supported formatters:
#   - prettier   for .js .jsx .ts .tsx .mjs .cjs .json .css .html .md .yaml .yml
#   - ruff       for .py
#   - gofmt      for .go
#   - rustfmt    for .rs

set -u

# Bypass switch — users with their own format-on-save tooling can opt out.
[[ "${TRIAD_NO_AUTOFORMAT:-0}" == "1" ]] && exit 0

# Diagnostic trace. Off by default — set TRIAD_HOOK_TRACE=1 to enable.
# Picks a log path in this order:
#   1. $TRIAD_HOOK_LOG, if explicitly set
#   2. <cwd>/.triad/hook.log, if .triad/ exists or can be created
#   3. /tmp/triad-hook.log
_resolve_log_path() {
  if [[ -n "${TRIAD_HOOK_LOG:-}" ]]; then
    printf '%s' "$TRIAD_HOOK_LOG"
    return
  fi
  if mkdir -p "$(pwd)/.triad" 2>/dev/null; then
    printf '%s' "$(pwd)/.triad/hook.log"
    return
  fi
  printf '%s' "/tmp/triad-hook.log"
}

trace() {
  [[ "${TRIAD_HOOK_TRACE:-0}" == "1" ]] || return 0
  printf '[triad-hook] %s %s\n' \
    "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" \
    >> "$(_resolve_log_path)" 2>/dev/null || true
}

# Read the hook payload from stdin if there is one (it'll be a pipe under the
# real hook; a tty during direct invocation). Capture the raw payload for
# diagnostics — we want to see exactly what shape the host is sending, since
# Claude Code and VS Code Copilot may differ.
payload=""
if [[ ! -t 0 ]]; then
  payload="$(cat)"
fi

# Try a series of known JSON paths for the file path. Claude Code's documented
# field is .tool_input.file_path; we also probe camelCase and a few other
# plausible shapes so the hook keeps working if a host renames it.
_extract_file_path() {
  [[ -z "$payload" ]] && return 0
  command -v jq >/dev/null 2>&1 || return 0
  local key v
  for key in \
    '.tool_input.file_path' \
    '.tool_input.filePath' \
    '.tool_input.path' \
    '.toolInput.file_path' \
    '.toolInput.filePath' \
    '.toolInput.path' \
    '.input.file_path' \
    '.input.filePath' \
    '.input.path' \
    '.file_path' \
    '.filePath' \
    '.path'; do
    v="$(printf '%s' "$payload" | jq -r "$key // empty" 2>/dev/null)"
    if [[ -n "$v" && "$v" != "null" ]]; then
      printf '%s\t%s' "$key" "$v"
      return 0
    fi
  done
}

# Tool name (best-effort) — useful in the log when matchers are ignored.
tool_name="?"
if [[ -n "$payload" ]] && command -v jq >/dev/null 2>&1; then
  tool_name="$(printf '%s' "$payload" | jq -r '.tool_name // .toolName // "?"' 2>/dev/null)"
  [[ -z "$tool_name" || "$tool_name" == "null" ]] && tool_name="?"
fi

case "$tool_name" in
  Write|Edit|MultiEdit|create_file|replace_string_in_file|insert_edit_into_file|apply_patch|\?)
    ;;
  *)
    trace "skip: non-mutating tool=$tool_name"
    exit 0
    ;;
esac

# Resolve the file path: stdin JSON wins, $1 is a fallback.
file=""
extracted_via=""
if [[ -n "$payload" ]]; then
  ev="$(_extract_file_path)"
  if [[ -n "$ev" ]]; then
    extracted_via="${ev%%$'\t'*}"
    file="${ev#*$'\t'}"
  fi
fi
[[ -z "$file" ]] && file="${1:-}"

# Log raw payload (single-lined) plus the extraction outcome.
if [[ -n "$payload" ]]; then
  payload_oneline="$(printf '%s' "$payload" | tr '\n' ' ' | tr -s ' ')"
  trace "fired tool=$tool_name pwd=$(pwd) extracted_via=${extracted_via:-<none>} file=${file:-<empty>}"
  trace "payload: $payload_oneline"
else
  trace "fired tool=$tool_name pwd=$(pwd) file=${file:-<empty>} (no stdin)"
fi

[[ -z "$file" || ! -f "$file" ]] && { trace "skip: no valid file"; exit 0; }

# Lowercase extension after the last dot.
ext="${file##*.}"
ext="$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')"

# Locate an executable. Walks up from the target file's directory looking for
# node_modules/.bin/<tool> (so project-local prettier/eslint/etc. work even
# when the hook subprocess doesn't have node_modules/.bin/ on PATH), then
# falls back to a regular PATH lookup.
find_bin() {
  local tool="$1"
  local dir
  dir="$(cd "$(dirname "${file:-$PWD}")" 2>/dev/null && pwd)" || dir="$PWD"
  while [[ -n "$dir" && "$dir" != "/" ]]; do
    if [[ -x "$dir/node_modules/.bin/$tool" ]]; then
      printf '%s' "$dir/node_modules/.bin/$tool"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  command -v "$tool" 2>/dev/null
}

# Globals captured by run() so we can emit a result to the agent after dispatch.
formatter_used=""
formatter_status=""
formatter_output=""

# Run a formatter if it's available, walking up for a project-local install
# before falling back to PATH. Captures stdout+stderr so we can surface useful
# diagnostics on failure. Traces the resolution and outcome.
run() {
  local tool="$1"; shift
  local bin
  bin="$(find_bin "$tool")"
  if [[ -n "$bin" ]]; then
    trace "run: $bin $*"
    local out status
    out="$("$bin" "$@" 2>&1)"
    status=$?
    trace "run-exit: $tool status=$status"
    formatter_used="$tool"
    formatter_status="$status"
    formatter_output="$out"
  else
    trace "skip: $tool not in node_modules/.bin nor on PATH"
  fi
}

case "$ext" in
  js|jsx|ts|tsx|mjs|cjs|json|css|html|md|yaml|yml)
    run prettier --write "$file"
    ;;
  py)
    run ruff format "$file"
    ;;
  go)
    run gofmt -w "$file"
    ;;
  rs)
    run rustfmt "$file"
    ;;
  *)
    trace "skip: no formatter for ext=$ext"
    ;;
esac

# Surface a notification both to the user and to the agent's context.
# Suppress with TRIAD_HOOK_NOTIFY=0.
#
# Two fields, because Claude Code and VS Code Copilot route them differently:
#   * systemMessage (top-level)          — displayed directly in the chat in
#                                          VS Code Copilot. Without it, Copilot
#                                          shows nothing to the user.
#   * hookSpecificOutput.additionalContext — injected into the agent's context
#                                          as a system reminder; the canonical
#                                          PostToolUse channel in Claude Code.
# Sending both means the user sees the line (Copilot) AND the model knows
# about it for follow-up reasoning (Claude Code + Copilot).
if [[ -n "$formatter_used" ]] \
   && [[ "${TRIAD_HOOK_NOTIFY:-1}" != "0" ]] \
   && command -v jq >/dev/null 2>&1; then
  rel="$file"
  case "$file" in
    "$PWD"/*) rel="${file#"$PWD"/}" ;;
  esac
  if [[ "$formatter_status" == "0" ]]; then
    msg="Triad auto-formatted ${rel} with ${formatter_used}."
  else
    out_short="$(printf '%s' "$formatter_output" | head -c 500)"
    msg="Triad auto-format with ${formatter_used} FAILED on ${rel} (exit ${formatter_status})."
    [[ -n "$out_short" ]] && msg="${msg} Output: ${out_short}"
  fi
  trace "notify: $msg"
  jq -nc --arg msg "$msg" '{
    systemMessage: $msg,
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      additionalContext: $msg
    }
  }'
fi

exit 0
