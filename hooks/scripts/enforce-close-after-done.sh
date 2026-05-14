#!/usr/bin/env bash
# DDW Hook: enforce-close-after-done
# Stop hook — blocks Claude from finishing if any task is `Status: done` but
# still sitting in active `tasks/` (not archived). The /ddw:close skill is the
# only step that archives a done task; without this hook, tasks pile up in the
# active tasks/ directory after being marked done.
#
# Opt-out: touch ${workflowDir}/.ddw/skip-close-enforcement to silence (e.g.
# while cleaning up a backlog of pre-hook done tasks).
#
# Exit 2 = block, exit 0 = allow.

set -euo pipefail

INPUT=$(cat)

# Resolve workflow dir
source "$(dirname "$0")/_config.sh"
WORKFLOW_DIR="$DDW_PROJECT_DIR/$DDW_WORKFLOW_DIR"

# Skip during auto runs — /ddw:auto handles close itself
if [[ -f "$WORKFLOW_DIR/.ddw/AUTO_RUN_ACTIVE" ]]; then
  exit 0
fi

# Opt-out: backlog cleanup escape hatch
if [[ -f "$WORKFLOW_DIR/.ddw/skip-close-enforcement" ]]; then
  exit 0
fi

# Scan active tasks/ for done-but-not-archived
shopt -s nullglob
TASK_FILES=("$WORKFLOW_DIR"/tasks/TASK-*.md)
shopt -u nullglob

if [[ ${#TASK_FILES[@]} -eq 0 ]]; then
  exit 0
fi

DONE_TASKS=()
for TASK_FILE in "${TASK_FILES[@]}"; do
  STATUS=$(grep -m1 '^\*\*Status:\*\*' "$TASK_FILE" 2>/dev/null | sed 's/\*\*Status:\*\* *//' | xargs || true)
  if [[ "$STATUS" == "done" ]]; then
    DONE_TASKS+=("$(basename "$TASK_FILE" .md)")
  fi
done

if [[ ${#DONE_TASKS[@]} -eq 0 ]]; then
  exit 0
fi

# Block — list the offenders
COUNT=${#DONE_TASKS[@]}
{
  if [[ $COUNT -eq 1 ]]; then
    echo "BLOCKED: ${DONE_TASKS[0]} is Status: done but still in active tasks/ — not archived."
    echo "Run /ddw:close ${DONE_TASKS[0]} to archive it."
  else
    echo "BLOCKED: $COUNT tasks are Status: done but still in active tasks/ — not archived:"
    for t in "${DONE_TASKS[@]}"; do
      echo "  - $t"
    done
    echo
    echo "Run /ddw:close <task> on each to archive."
  fi
  echo
  echo "Backlog cleanup escape hatch (suppresses this block until removed):"
  echo "  touch $WORKFLOW_DIR/.ddw/skip-close-enforcement"
} >&2

exit 2
