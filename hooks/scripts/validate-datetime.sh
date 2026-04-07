#!/usr/bin/env bash
# DDW Hook: validate-datetime
# Blocks placeholder timestamps like T00:00:00Z in workflow files.
# Runs as a PreToolUse hook on Write|Edit.

set -euo pipefail

INPUT=$(cat)

# Extract the file path from the hook input
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty' 2>/dev/null || true)

# Resolve workflow dir to check against
_SCRIPT_DIR="$(dirname "$0")"
_DDW_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
_DDW_WORKFLOW_DIR=""
for _candidate in "workflows" ".workflows" ".claude"; do
  if [[ -f "$_DDW_PROJECT_DIR/$_candidate/ddw.json" ]]; then
    _DDW_WORKFLOW_DIR=$(python3 -c "import json; print(json.load(open('$_DDW_PROJECT_DIR/$_candidate/ddw.json')).get('workflowDir','workflows'))" 2>/dev/null || echo "$_candidate")
    break
  fi
done

# Only check files inside the workflow directory
if [[ -z "$FILE_PATH" || -z "$_DDW_WORKFLOW_DIR" || "$FILE_PATH" != *"/$_DDW_WORKFLOW_DIR/"* ]]; then
  exit 0
fi

# Extract the content being written/edited
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // .tool_input.new_string // empty' 2>/dev/null || true)

if [[ -z "$CONTENT" ]]; then
  exit 0
fi

# Check for placeholder timestamps
if echo "$CONTENT" | grep -qE 'T00:00:00Z'; then
  echo "BLOCKED: Placeholder timestamp T00:00:00Z detected."
  echo "Run: date -u +\"%Y-%m-%dT%H:%M:%SZ\" and use the actual UTC datetime."
  exit 2
fi

exit 0
