#!/usr/bin/env bash
# DDW Hook: clear-awaiting-go
#
# UserPromptSubmit — clears per-task awaiting-go markers when the owner
# authorizes implementation. Pairs with require-explicit-implementation-go.sh.
#
# Authorization rules (in priority order):
#   1. User message names a task ID or slug → clear matching marker(s).
#   2. User message is a short standalone affirmative AND exactly ONE marker
#      exists → clear it. (Multiple markers + bare affirmative is ambiguous;
#      the require-explicit-implementation-go hook will keep blocking until
#      the owner names which task.)
#
# Why this design: short affirmatives like "go" / "yes" / "do it" are common
# even when the owner is responding to something unrelated. Auto-clearing on
# any affirmative would re-introduce the ambiguous-do-it failure mode this
# whole gate is designed to prevent. Affirmative + exactly-one marker is the
# safe case — there's nothing to be ambiguous about.

set -euo pipefail

INPUT=$(cat)

# Only run inside DDW projects (config.sh exits silently otherwise).
source "$(dirname "$0")/_config.sh"

WORKFLOW_DIR="$DDW_PROJECT_DIR/$DDW_WORKFLOW_DIR"
DDW_RUNTIME="$WORKFLOW_DIR/.ddw"

if [[ ! -d "$DDW_RUNTIME" ]]; then
  exit 0
fi

shopt -s nullglob
MARKERS=("$DDW_RUNTIME"/awaiting-go-*.flag)
shopt -u nullglob

if [[ ${#MARKERS[@]} -eq 0 ]]; then
  exit 0
fi

# Extract user prompt from hook payload. Different schema versions use
# different field names; try the common ones.
USER_PROMPT=$(echo "$INPUT" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print('')
    sys.exit(0)
for k in ('prompt', 'userMessage', 'message', 'text'):
    v = d.get(k)
    if isinstance(v, str) and v.strip():
        print(v)
        sys.exit(0)
# Some schemas nest under tool_input or similar
ti = d.get('tool_input') or {}
for k in ('prompt', 'message'):
    v = ti.get(k)
    if isinstance(v, str) and v.strip():
        print(v)
        sys.exit(0)
print('')
" 2>/dev/null || true)

if [[ -z "$USER_PROMPT" ]]; then
  exit 0
fi

# --- Strategy A: user names a specific task ID or slug → clear matching marker
CLEARED=0
for m in "${MARKERS[@]}"; do
  base=$(basename "$m" .flag)
  task_id="${base#awaiting-go-}"

  # Slug heuristic: TASK-{date}-{slug}; everything after the second dash group.
  # e.g. TASK-20260509-m3-app-split → slug = m3-app-split
  slug="${task_id#TASK-}"
  if [[ "$slug" == *-* ]]; then
    slug="${slug#*-}"  # drop date prefix
  fi

  # Match on either full TASK ID (case-insensitive) or slug (word-boundary).
  if echo "$USER_PROMPT" | grep -qiE "${task_id}|(^|[^a-zA-Z0-9_-])${slug}([^a-zA-Z0-9_-]|$)"; then
    rm -f "$m"
    CLEARED=$((CLEARED + 1))
    echo "[ddw] cleared awaiting-go marker for $task_id (named in user message)" >&2
  fi
done

if [[ $CLEARED -gt 0 ]]; then
  exit 0
fi

# --- Strategy B: bare affirmative + exactly one marker → clear it
# Only run when there's no ambiguity (single marker). Bare affirmatives in
# multi-marker situations should keep blocking until the owner names which.
if [[ ${#MARKERS[@]} -ne 1 ]]; then
  exit 0
fi

# Normalize: lowercase, strip whitespace and basic punctuation.
TRIMMED=$(echo "$USER_PROMPT" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:][:punct:]' )

case "$TRIMMED" in
  go|yes|y|ok|okay|continue|proceed|doit|do|sure|please|gogogo|gogo|goahead|yep|yeah|yo|yup|fine|approved|approve|lgtm)
    rm -f "${MARKERS[0]}"
    base=$(basename "${MARKERS[0]}" .flag)
    task_id="${base#awaiting-go-}"
    echo "[ddw] cleared awaiting-go marker for $task_id (single-task affirmative)" >&2
    ;;
esac

exit 0
