#!/usr/bin/env bash
# DDW Hook: auto-session-handoff
# Stop hook — auto-populates the Session Handoff section for any in_progress
# task with machine-derivable fields (Status, Completed/Remaining ACs, Files touched).
# Blockers, Next action, and Context are left as-is (require Claude's judgment).
# Exit 0 = allow (this hook never blocks).

set -euo pipefail

INPUT=$(cat)

# Resolve workflow dir
source "$(dirname "$0")/_config.sh"
WORKFLOW_DIR="$DDW_PROJECT_DIR/$DDW_WORKFLOW_DIR"

# Find in_progress task files
shopt -s nullglob
TASK_FILES=("$WORKFLOW_DIR"/tasks/TASK-*.md)
shopt -u nullglob

if [[ ${#TASK_FILES[@]} -eq 0 ]]; then
  exit 0
fi

for TASK_FILE in "${TASK_FILES[@]}"; do
  # Only process in_progress tasks
  if ! grep -q '\*\*Status:\*\* in_progress' "$TASK_FILE" 2>/dev/null; then
    continue
  fi

  # Check if handoff section already has content (Status not "none")
  HANDOFF_STATUS=$(grep -oP '^\- \*\*Status:\*\* \K.*' "$TASK_FILE" 2>/dev/null | tail -1 || echo "")
  # If handoff already populated by Claude (not "none" and not empty), skip
  if [[ -n "$HANDOFF_STATUS" && "$HANDOFF_STATUS" != "none" ]]; then
    continue
  fi

  # --- Extract Completed and Remaining ACs from the AC table ---
  COMPLETED_ACS=()
  REMAINING_ACS=()
  IN_AC_TABLE=false

  while IFS= read -r line; do
    if [[ "$line" == "## Acceptance Criteria"* ]]; then
      IN_AC_TABLE=true
      continue
    fi
    if [[ "$IN_AC_TABLE" == true && "$line" == "##"* ]]; then
      break
    fi
    if [[ "$IN_AC_TABLE" == true ]]; then
      # Parse AC table rows: | AC-XX | ... |
      AC_ID=$(echo "$line" | grep -oP '^\|\s*\K(AC-\d+)' 2>/dev/null || echo "")
      if [[ -n "$AC_ID" ]]; then
        # Check completion criteria for this AC (look for checked box mentioning it)
        if grep -qP "^\s*- \[x\].*$AC_ID" "$TASK_FILE" 2>/dev/null; then
          COMPLETED_ACS+=("$AC_ID")
        else
          REMAINING_ACS+=("$AC_ID")
        fi
      fi
    fi
  done < "$TASK_FILE"

  # Format AC lists
  if [[ ${#COMPLETED_ACS[@]} -gt 0 ]]; then
    COMPLETED_STR=$(IFS=', '; echo "${COMPLETED_ACS[*]}")
  else
    COMPLETED_STR=""
  fi

  if [[ ${#REMAINING_ACS[@]} -gt 0 ]]; then
    REMAINING_STR=$(IFS=', '; echo "${REMAINING_ACS[*]}")
  else
    REMAINING_STR=""
  fi

  # --- Get files touched from git ---
  FILES_TOUCHED=""
  if git rev-parse --git-dir &>/dev/null; then
    # Get files changed on the current branch vs main/master
    MAIN_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")
    if git rev-parse "$MAIN_BRANCH" &>/dev/null; then
      FILES_TOUCHED=$(git diff --name-only "$MAIN_BRANCH"...HEAD 2>/dev/null | paste -sd ', ' - || echo "")
    fi
    # Also include uncommitted changes
    UNCOMMITTED=$(git diff --name-only HEAD 2>/dev/null | paste -sd ', ' - || echo "")
    if [[ -n "$UNCOMMITTED" ]]; then
      if [[ -n "$FILES_TOUCHED" ]]; then
        FILES_TOUCHED="$FILES_TOUCHED, $UNCOMMITTED"
      else
        FILES_TOUCHED="$UNCOMMITTED"
      fi
    fi
  fi

  # --- Write structured handoff ---
  # Use python3 for reliable in-place section replacement
  python3 - "$TASK_FILE" "$COMPLETED_STR" "$REMAINING_STR" "$FILES_TOUCHED" <<'PYEOF'
import sys
import re

task_file = sys.argv[1]
completed = sys.argv[2]
remaining = sys.argv[3]
files_touched = sys.argv[4]

with open(task_file, 'r') as f:
    content = f.read()

# Build the new handoff section
handoff = f"""## Session Handoff
<!-- Auto-populated by hook on session end. Parsed by /ddw:sendit on resume. -->
<!-- Clear this section when resuming (sendit step 4 does this automatically). -->

- **Status:** in_progress
- **Completed ACs:** [{completed}]
- **Remaining ACs:** [{remaining}]
- **Files touched:** {files_touched}
- **Blockers:** none
- **Next action:**
- **Context:**"""

# Replace the Session Handoff section (up to the next ## heading)
pattern = r'## Session Handoff.*?(?=\n## |\Z)'
content = re.sub(pattern, handoff, content, count=1, flags=re.DOTALL)

with open(task_file, 'w') as f:
    f.write(content)
PYEOF

done

exit 0
