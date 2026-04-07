#!/usr/bin/env bash
# DDW Hook: enforce-review-after-impl
# Stop hook — blocks Claude from finishing if an in_progress task has all
# completion criteria ticked but no review (QA report) has been done.
# Exit 2 = block, exit 0 = allow.

set -euo pipefail

INPUT=$(cat)

# Resolve workflow dir
source "$(dirname "$0")/_config.sh"
WORKFLOW_DIR="$DDW_PROJECT_DIR/$DDW_WORKFLOW_DIR"

# Scan all task files for in_progress tasks needing review
shopt -s nullglob
TASK_FILES=("$WORKFLOW_DIR"/tasks/TASK-*.md)
shopt -u nullglob

if [[ ${#TASK_FILES[@]} -eq 0 ]]; then
  exit 0
fi

for TASK_FILE in "${TASK_FILES[@]}"; do
  # Only check in_progress tasks
  if ! grep -q '\*\*Status:\*\* in_progress' "$TASK_FILE" 2>/dev/null; then
    continue
  fi

  # Count completion criteria checkboxes
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
  done < "$TASK_FILE"

  # All criteria ticked?
  if [[ $CHECKED -eq 0 || $UNCHECKED -gt 0 ]]; then
    continue
  fi

  # Check if review was done (QA report in Review Log)
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
  done < "$TASK_FILE"

  if [[ "$HAS_QA" != true ]]; then
    TASK_NAME=$(basename "$TASK_FILE" .md)
    echo "BLOCKED: $TASK_NAME has all completion criteria ticked but no review has been run."
    echo "Run /ddw:review $TASK_NAME before finishing."
    exit 2
  fi
done

exit 0
