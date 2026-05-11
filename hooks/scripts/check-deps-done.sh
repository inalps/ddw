#!/usr/bin/env bash
# DDW Hook: check-deps-done
# Blocks in_progress when Depends-On tasks aren't done yet.
# Runs as a PreToolUse hook on Write|Edit.

set -euo pipefail

INPUT=$(cat)

# Extract the file path from the hook input
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty' 2>/dev/null || true)

# Skip if not a TASK file
if [[ -z "$FILE_PATH" || "$FILE_PATH" != *"TASK-"* ]]; then
  exit 0
fi

# Extract the content being written
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // .tool_input.new_string // empty' 2>/dev/null || true)

# Skip if content doesn't contain in_progress (not a status transition)
if [[ -z "$CONTENT" ]] || ! echo "$CONTENT" | grep -q 'in_progress'; then
  exit 0
fi

# Auto-mode bypass: /ddw:auto manages dependency ordering; this gate is for humans.
source "$(dirname "$0")/_config.sh"
DDW_RUNTIME="$DDW_PROJECT_DIR/$DDW_WORKFLOW_DIR/.ddw"
if [[ -f "$DDW_RUNTIME/AUTO_RUN_ACTIVE" ]]; then
  exit 0
fi

# Read the task file to get the Depends-On field
if [[ ! -f "$FILE_PATH" ]]; then
  exit 0
fi

DEPENDS_ON=$(sed -n 's/.*\*\*Depends-On:\*\* *//p' "$FILE_PATH" | tr -d '[:space:]' || true)

# If no dependencies or "none", allow
if [[ -z "$DEPENDS_ON" || "$DEPENDS_ON" == "none" ]]; then
  exit 0
fi

# Locate workflow dir
WORKFLOW_DIR="$DDW_PROJECT_DIR/$DDW_WORKFLOW_DIR"
TASKS_DIR="$WORKFLOW_DIR/tasks"

if [[ ! -d "$TASKS_DIR" ]]; then
  exit 0
fi

# Split comma-separated TASK IDs and check each
IFS=',' read -ra DEP_IDS <<< "$DEPENDS_ON"
NOT_DONE=()

for DEP_ID in "${DEP_IDS[@]}"; do
  # Trim whitespace
  DEP_ID=$(echo "$DEP_ID" | xargs)
  [[ -z "$DEP_ID" ]] && continue

  DEP_FILE="$TASKS_DIR/${DEP_ID}.md"

  # Also check archive if not found in active tasks
  if [[ ! -f "$DEP_FILE" ]]; then
    DEP_FILE="$TASKS_DIR/archive/${DEP_ID}.md"
  fi

  if [[ ! -f "$DEP_FILE" ]]; then
    NOT_DONE+=("$DEP_ID (file not found)")
    continue
  fi

  DEP_STATUS=$(grep -m1 '^\*\*Status:\*\*' "$DEP_FILE" 2>/dev/null | sed 's/\*\*Status:\*\* *//' | xargs)

  if [[ "$DEP_STATUS" != "done" ]]; then
    NOT_DONE+=("$DEP_ID (status: ${DEP_STATUS:-unknown})")
  fi
done

# If any deps not done, block
if [[ ${#NOT_DONE[@]} -gt 0 ]]; then
  echo ""
  echo "BLOCKED: This task has unfinished dependencies."
  echo ""
  echo "Depends-On tasks not yet done:"
  for D in "${NOT_DONE[@]}"; do
    echo "  - $D"
  done
  echo ""
  echo "Complete the dependency tasks first, then start this one."
  exit 2
fi

exit 0
