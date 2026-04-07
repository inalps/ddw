#!/usr/bin/env bash
# DDW Hook: require-all-tasks
# Blocks in_progress when the parent decision has tasks not yet in TASK_LOG.
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

# Read the task file to get the Decision field
if [[ ! -f "$FILE_PATH" ]]; then
  exit 0
fi

DECISION=$(sed -n 's/.*\*\*Decision:\*\* *//p' "$FILE_PATH" | tr -d '[:space:]' || true)

# If decision is "none" or empty, skip
if [[ -z "$DECISION" || "$DECISION" == "none" ]]; then
  exit 0
fi

# Locate the decision file
source "$(dirname "$0")/_config.sh"
WORKFLOW_DIR="$DDW_PROJECT_DIR/$DDW_WORKFLOW_DIR"
DEC_FILE="$WORKFLOW_DIR/decisions/${DECISION}.md"

if [[ ! -f "$DEC_FILE" ]]; then
  # Legacy task or missing decision — warn but don't block
  exit 0
fi

# Extract task IDs from the ## Tasks section of the decision
IN_TASKS=false
TASK_IDS=()
while IFS= read -r line; do
  if [[ "$line" == "## Tasks"* ]]; then
    IN_TASKS=true
    continue
  fi
  if [[ "$IN_TASKS" == true && "$line" == "##"* ]]; then
    break
  fi
  if [[ "$IN_TASKS" == true ]]; then
    # Skip "(none — proposed only)" placeholder
    if echo "$line" | grep -q 'none.*proposed'; then
      exit 0
    fi
    # Extract TASK-{date}-{slug} pattern (BSD-compatible grep)
    TASK_ID=$(echo "$line" | grep -oE 'TASK-[0-9]{8}-[a-zA-Z0-9_-]+' || true)
    if [[ -n "$TASK_ID" ]]; then
      TASK_IDS+=("$TASK_ID")
    fi
  fi
done < "$DEC_FILE"

# If no tasks found in decision, nothing to enforce
if [[ ${#TASK_IDS[@]} -eq 0 ]]; then
  exit 0
fi

# Check each task ID exists in TASK_LOG
TASK_LOG="$WORKFLOW_DIR/logs/TASK_LOG.md"
if [[ ! -f "$TASK_LOG" ]]; then
  exit 0
fi

MISSING=()
for TID in "${TASK_IDS[@]}"; do
  if ! grep -q "$TID" "$TASK_LOG"; then
    MISSING+=("$TID")
  fi
done

# If any missing, block
if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo ""
  echo "BLOCKED: Decision $DECISION lists tasks not yet in TASK_LOG."
  echo ""
  echo "Missing:"
  for M in "${MISSING[@]}"; do
    echo "  - $M"
  done
  echo ""
  echo "Create all planned tasks with /ddw:task before starting any of them."
  exit 2
fi

exit 0
