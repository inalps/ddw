#!/usr/bin/env bash
# DDW Hook: require-review-before-close
# Blocks setting a task to "done" unless Owner Review Checklist is complete
# and a QA report exists in the Review Log.
# Runs as a PreToolUse hook on Write|Edit.

set -euo pipefail

INPUT=$(cat)

# Extract the file path from the hook input
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty' 2>/dev/null || true)

# Only check task files
if [[ -z "$FILE_PATH" || "$FILE_PATH" != *"TASK-"* ]]; then
  exit 0
fi

# Check if this edit is setting status to done
NEW_STRING=$(echo "$INPUT" | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null || true)

if ! echo "$NEW_STRING" | grep -q '**Status:** done'; then
  exit 0
fi

# This edit is trying to set a task to done — enforce review gates

# Auto-mode bypass: /ddw:auto ticks all checklist items and sets status to done
# in a single edit. Reading the pre-edit file would see unchecked items and
# false-block. Auto's confirm_on gates handle autonomy; this hook is for humans.
source "$(dirname "$0")/_config.sh" 2>/dev/null || true
DDW_RUNTIME="${DDW_PROJECT_DIR:-$CLAUDE_PROJECT_DIR}/${DDW_WORKFLOW_DIR:-workflows}/.ddw"
if [[ -f "$DDW_RUNTIME/AUTO_RUN_ACTIVE" ]]; then
  exit 0
fi

if [[ ! -f "$FILE_PATH" ]]; then
  exit 0
fi

# Gate 1: All Owner Review Checklist items must be checked
IN_CHECKLIST=false
UNCHECKED=0

while IFS= read -r line; do
  if [[ "$line" == "## Owner Review Checklist"* ]]; then
    IN_CHECKLIST=true
    continue
  fi
  if [[ "$IN_CHECKLIST" == true && "$line" == "##"* ]]; then
    break
  fi
  if [[ "$IN_CHECKLIST" == true ]]; then
    if echo "$line" | grep -qE '^\s*- \[ \]'; then
      UNCHECKED=$((UNCHECKED + 1))
    fi
  fi
done < "$FILE_PATH"

if [[ $UNCHECKED -gt 0 ]]; then
  echo "BLOCKED: Owner Review Checklist has $UNCHECKED unchecked item(s)."
  echo "Run /ddw:review first to complete the checklist before setting task to done."
  exit 2
fi

# Gate 2: Review Log must contain a QA report
IN_REVIEW=false
HAS_QA=false

while IFS= read -r line; do
  if [[ "$line" == "## Review Log"* ]]; then
    IN_REVIEW=true
    continue
  fi
  if [[ "$IN_REVIEW" == true && "$line" == "##"* && "$line" != "###"* && "$line" != "####"* ]]; then
    break
  fi
  if [[ "$IN_REVIEW" == true ]]; then
    if echo "$line" | grep -qi 'QA Run\|Verdict:'; then
      HAS_QA=true
      break
    fi
  fi
done < "$FILE_PATH"

if [[ "$HAS_QA" != true ]]; then
  echo "BLOCKED: No QA report found in Review Log."
  echo "Run /ddw:review first — it runs QA checks and logs results before the owner checklist."
  exit 2
fi

exit 0
