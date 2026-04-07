#!/usr/bin/env bash
# DDW Hook: session-status (copied to project by /ddw:init)
# Announces project status on session start.
# Scans only active (non-archived) files for speed.
# Self-contained — no external dependencies.
# VERSION: 1

set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"

# Find ddw.json
CONFIG_FILE=""
for candidate in "workflows" ".workflows" ".claude"; do
  if [[ -f "$PROJECT_DIR/$candidate/ddw.json" ]]; then
    CONFIG_FILE="$PROJECT_DIR/$candidate/ddw.json"
    break
  fi
done
[[ -z "$CONFIG_FILE" ]] && exit 0

WORKFLOW_DIR=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE')).get('workflowDir','workflows'))" 2>/dev/null || echo "workflows")
PROJECT_NAME=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE')).get('project',''))" 2>/dev/null || echo "")
USER_NAME=$(git config user.name 2>/dev/null || whoami)

TASKS_DIR="$PROJECT_DIR/$WORKFLOW_DIR/tasks"
PRDS_DIR="$PROJECT_DIR/$WORKFLOW_DIR/prds"
DECS_DIR="$PROJECT_DIR/$WORKFLOW_DIR/decisions"

OUTPUT=""

# --- In-progress tasks (yours) + session handoff ---
if [[ -d "$TASKS_DIR" ]]; then
  for f in "$TASKS_DIR"/TASK-*.md; do
    [[ -f "$f" ]] || continue
    STATUS=$(grep -m1 '^\*\*Status:\*\*' "$f" 2>/dev/null | sed 's/\*\*Status:\*\* *//' | xargs) || true
    OWNER=$(grep -m1 '^\*\*Owner:\*\*' "$f" 2>/dev/null | sed 's/\*\*Owner:\*\* *//' | xargs) || true

    if [[ "$STATUS" == "in_progress" && ( "$OWNER" == "$USER_NAME" || -z "$OWNER" ) ]]; then
      TASK_ID=$(basename "$f" .md)
      HANDOFF=$(sed -n '/^## Session Handoff/,/^## /{ /^## Session Handoff/d; /^## /d; /^$/d; p; }' "$f" 2>/dev/null | head -3) || true
      if [[ -n "$HANDOFF" ]]; then
        OUTPUT+="In progress: $TASK_ID\n   Handoff: $(echo "$HANDOFF" | head -1)\n"
      else
        OUTPUT+="In progress: $TASK_ID\n"
      fi
    fi
  done

  # --- Tasks waiting for review ---
  for f in "$TASKS_DIR"/TASK-*.md; do
    [[ -f "$f" ]] || continue
    STATUS=$(grep -m1 '^\*\*Status:\*\*' "$f" 2>/dev/null | sed 's/\*\*Status:\*\* *//' | xargs) || true
    if [[ "$STATUS" == "review_and_bugfix" ]]; then
      TASK_ID=$(basename "$f" .md)
      OWNER=$(grep -m1 '^\*\*Owner:\*\*' "$f" 2>/dev/null | sed 's/\*\*Owner:\*\* *//' | xargs) || true
      OUTPUT+="Needs review: $TASK_ID ($OWNER)\n"
    fi
  done

  # --- Planned tasks (next up, yours) ---
  for f in "$TASKS_DIR"/TASK-*.md; do
    [[ -f "$f" ]] || continue
    STATUS=$(grep -m1 '^\*\*Status:\*\*' "$f" 2>/dev/null | sed 's/\*\*Status:\*\* *//' | xargs) || true
    OWNER=$(grep -m1 '^\*\*Owner:\*\*' "$f" 2>/dev/null | sed 's/\*\*Owner:\*\* *//' | xargs) || true
    if [[ "$STATUS" == "planned" && ( "$OWNER" == "$USER_NAME" || -z "$OWNER" ) ]]; then
      TASK_ID=$(basename "$f" .md)
      OUTPUT+="Planned: $TASK_ID\n"
    fi
  done
fi

# --- Draft PRDs ---
if [[ -d "$PRDS_DIR" ]]; then
  for f in "$PRDS_DIR"/PRD-*.md; do
    [[ -f "$f" ]] || continue
    STATUS=$(grep -m1 'Status:' "$f" 2>/dev/null | sed 's/.*Status:[[:space:]]*//' | xargs) || true
    if [[ "$STATUS" == "draft" ]]; then
      PRD_ID=$(basename "$f" .md)
      OUTPUT+="Draft PRD: $PRD_ID\n"
    fi
  done
fi

# --- Proposed decisions ---
if [[ -d "$DECS_DIR" ]]; then
  for f in "$DECS_DIR"/DEC-*.md; do
    [[ -f "$f" ]] || continue
    STATUS=$(grep -m1 '^\*\*Status:\*\*' "$f" 2>/dev/null | sed 's/\*\*Status:\*\* *//' | xargs) || true
    if [[ "$STATUS" == "proposed" ]]; then
      DEC_ID=$(basename "$f" .md)
      OUTPUT+="Proposed decision: $DEC_ID\n"
    fi
  done
fi

# --- Print ---
if [[ -n "$OUTPUT" ]]; then
  echo "=== DDW Status: ${PROJECT_NAME:-$(basename "$PROJECT_DIR")} ==="
  echo ""
  echo -e "$OUTPUT"
fi

exit 0
