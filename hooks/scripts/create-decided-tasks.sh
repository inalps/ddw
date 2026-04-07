#!/usr/bin/env bash
# DDW Hook: create-decided-tasks
# Fires after a decision file is edited to "decided" status.
# Outputs an enforcement message listing all uncreated tasks,
# prompting Claude to invoke /ddw:task for each one.
# Runs as a PostToolUse hook on Edit|Write.

set -euo pipefail

INPUT=$(cat)

# Extract the file path from the hook input
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty' 2>/dev/null || true)

# Skip if not a decision file
if [[ -z "$FILE_PATH" || "$FILE_PATH" != *"DEC-"* ]]; then
  exit 0
fi

# Extract the content being written
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // .tool_input.new_string // empty' 2>/dev/null || true)

# Skip if content doesn't contain "decided" (not a status transition)
if [[ -z "$CONTENT" ]] || ! echo "$CONTENT" | grep -q 'decided'; then
  exit 0
fi

# Read the decision file to confirm status is now decided
if [[ ! -f "$FILE_PATH" ]]; then
  exit 0
fi

# Check that the file actually has Status: decided
if ! grep -q '^Status: decided' "$FILE_PATH"; then
  exit 0
fi

# Extract decision ID from filename
DEC_ID=$(basename "$FILE_PATH" .md)

# Extract uncreated tasks from the ## Tasks section
IN_TASKS=false
UNCREATED=()
while IFS= read -r line; do
  if [[ "$line" == "## Tasks"* ]]; then
    IN_TASKS=true
    continue
  fi
  if [[ "$IN_TASKS" == true && "$line" == "##"* ]]; then
    break
  fi
  if [[ "$IN_TASKS" == true ]]; then
    if echo "$line" | grep -q '(not yet created)'; then
      # Trim leading "- " and trailing whitespace
      ENTRY=$(echo "$line" | sed 's/^- *//')
      UNCREATED+=("$ENTRY")
    fi
  fi
done < "$FILE_PATH"

# If no uncreated tasks, nothing to do
if [[ ${#UNCREATED[@]} -eq 0 ]]; then
  exit 0
fi

echo ""
echo "ACTION REQUIRED: Decision $DEC_ID moved to decided."
echo "Create all planned tasks now with /ddw:task for each:"
echo ""
for ENTRY in "${UNCREATED[@]}"; do
  echo "  - $ENTRY"
done
echo ""
echo "Pass the decision ID, slug, and details from the architect review to each /ddw:task invocation."

exit 0
