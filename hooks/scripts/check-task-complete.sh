#!/usr/bin/env bash
# DDW Hook: check-task-complete
# After edits, checks if all completion criteria are ticked and reminds to run /ddw:close.
# Runs as a PostToolUse hook on Edit|Write.

set -euo pipefail

INPUT=$(cat)

# Extract the file path
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty' 2>/dev/null || true)

# Only check task files
if [[ -z "$FILE_PATH" || "$FILE_PATH" != *"TASK-"* ]]; then
  exit 0
fi

# Check if all completion criteria checkboxes are ticked
if [[ ! -f "$FILE_PATH" ]]; then
  exit 0
fi

# Count unchecked and checked boxes in the Completion Criteria section
IN_SECTION=false
UNCHECKED=0
CHECKED=0

while IFS= read -r line; do
  if [[ "$line" == "## Completion Criteria"* ]]; then
    IN_SECTION=true
    continue
  fi
  if [[ "$IN_SECTION" == true && "$line" == "##"* ]]; then
    break
  fi
  if [[ "$IN_SECTION" == true ]]; then
    if echo "$line" | grep -qE '^\s*- \[ \]'; then
      UNCHECKED=$((UNCHECKED + 1))
    elif echo "$line" | grep -qE '^\s*- \[x\]'; then
      CHECKED=$((CHECKED + 1))
    fi
  fi
done < "$FILE_PATH"

if [[ $CHECKED -gt 0 && $UNCHECKED -eq 0 ]]; then
  # Check if review has been done (QA report in Review Log OR review_and_bugfix in Work Log)
  IN_REVIEW=false
  IN_WORKLOG=false
  HAS_QA=false

  while IFS= read -r line; do
    if [[ "$line" == "## Review Log"* ]]; then
      IN_REVIEW=true
      IN_WORKLOG=false
      continue
    fi
    if [[ "$line" == "## Work Log"* ]]; then
      IN_WORKLOG=true
      IN_REVIEW=false
      continue
    fi
    if [[ ("$IN_REVIEW" == true || "$IN_WORKLOG" == true) && "$line" == "##"* && "$line" != "###"* && "$line" != "####"* ]]; then
      if [[ "$line" != "## Work Log"* && "$line" != "## Review Log"* ]]; then
        IN_REVIEW=false
        IN_WORKLOG=false
      fi
      continue
    fi
    if [[ "$IN_REVIEW" == true ]]; then
      if echo "$line" | grep -qi 'QA Run\|Verdict:\|Review —'; then
        HAS_QA=true
        break
      fi
    fi
    if [[ "$IN_WORKLOG" == true ]]; then
      if echo "$line" | grep -q 'review_and_bugfix'; then
        HAS_QA=true
        break
      fi
    fi
  done < "$FILE_PATH"

  if [[ "$HAS_QA" != true ]]; then
    # No review yet — nudge toward /ddw:review
    cat <<'HOOK_JSON'
{"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": "All completion criteria are ticked but NO review has been run yet. You MUST run /ddw:review for this task NOW before doing anything else. Do not skip this step."}}
HOOK_JSON
  else
    # Review done — check if status is already done
    TASK_STATUS=$(grep -m1 '^\*\*Status:\*\*' "$FILE_PATH" 2>/dev/null | sed 's/\*\*Status:\*\* *//' | xargs)
    if [[ "$TASK_STATUS" == "done" ]]; then
      # Status is done — nudge toward /ddw:close
      cat <<'HOOK_JSON'
{"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": "All completion criteria ticked and review is done. Run /ddw:close to finalize this task."}}
HOOK_JSON
    else
      # Status not done yet — ask owner for verbal confirmation
      cat <<'HOOK_JSON'
{"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": "All completion criteria ticked and review is done. Ask the owner: \"All criteria passed and review is complete. OK to mark done and close?\" If the owner confirms (yes / ok / all clear / checked / close it / go), set **Status:** done in the task file, add a Work Log entry, and run /ddw:close. The owner may also set **Status:** done manually in the task file — either way is valid."}}
HOOK_JSON
    fi
  fi
fi

exit 0
