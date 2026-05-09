#!/usr/bin/env bash
# DDW Hook: require-active-task
# Blocks code writes when no task is in_progress.
# Runs as a PreToolUse hook on Write|Edit.

set -euo pipefail

INPUT=$(cat)

# Extract the file path from the hook input
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty' 2>/dev/null || true)

if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# Resolve config (exits if not a DDW project)
source "$(dirname "$0")/_config.sh"

# Skip workflow/doc files — only gate implementation code
if [[ "$FILE_PATH" == *"/$DDW_WORKFLOW_DIR/"* ]] || \
   [[ "$FILE_PATH" == *"CLAUDE.md"* ]] || \
   [[ "$FILE_PATH" == *".claude/"* ]] || \
   [[ "$FILE_PATH" == *"/docs/"* ]] || \
   [[ "$FILE_PATH" == *"/tasks/"* ]] || \
   [[ "$FILE_PATH" == *"/.gitignore" || "$FILE_PATH" == *".gitignore" ]] || \
   [[ "$FILE_PATH" == *"/.worktrees/"* ]] || \
   [[ "$FILE_PATH" == *".md" && "$FILE_PATH" != *"index"* ]]; then
  exit 0
fi

# Resolve user identity: git config user.name → whoami
USER_NAME=$(git config user.name 2>/dev/null || whoami)

if [[ -z "$USER_NAME" ]]; then
  # Can't resolve identity — allow
  exit 0
fi

TASKS_DIR="$DDW_PROJECT_DIR/$DDW_WORKFLOW_DIR/tasks"

if [[ ! -d "$TASKS_DIR" ]]; then
  exit 0
fi

# Check if this user has an in_progress task
for TASK_FILE in "$TASKS_DIR"/TASK-*.md; do
  [[ -f "$TASK_FILE" ]] || continue
  OWNER=$(grep -m1 '^\*\*Owner:\*\*' "$TASK_FILE" 2>/dev/null | sed 's/\*\*Owner:\*\* *//' | xargs)
  STATUS=$(grep -m1 '^\*\*Status:\*\*' "$TASK_FILE" 2>/dev/null | sed 's/\*\*Status:\*\* *//' | xargs)

  # Legacy tasks without Owner field — allow anyone
  if [[ -z "$OWNER" && "$STATUS" == "in_progress" ]]; then
    exit 0
  fi

  if [[ "$OWNER" == "$USER_NAME" && "$STATUS" == "in_progress" ]]; then
    exit 0
  fi
done

echo "BLOCKED: No in_progress task found for user '$USER_NAME'."
echo "Create a task with /ddw:task and start it with /ddw:sendit."
exit 2
