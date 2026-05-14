#!/usr/bin/env bash
# DDW shared config discovery.
# Source this from any hook script: source "$(dirname "$0")/_config.sh"
#
# Exports: DDW_PROJECT_DIR, DDW_WORKFLOW_DIR, DDW_CONFIG_FILE
# Exits 0 silently if no ddw.json found (non-DDW project).

DDW_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"

# Search common locations for ddw.json
DDW_CONFIG_FILE=""
for candidate in "workflows" ".workflows" ".claude"; do
  if [[ -f "$DDW_PROJECT_DIR/$candidate/ddw.json" ]]; then
    DDW_CONFIG_FILE="$DDW_PROJECT_DIR/$candidate/ddw.json"
    break
  fi
done

if [[ -z "$DDW_CONFIG_FILE" ]]; then
  # Not a DDW project
  exit 0
fi

# Read workflowDir from config (in case it differs from the directory where ddw.json was found)
DDW_WORKFLOW_DIR=$(python3 -c "import json; print(json.load(open('$DDW_CONFIG_FILE')).get('workflowDir','workflows'))" 2>/dev/null || echo "workflows")

# Read worktree.taskDir template if configured (e.g. ".worktrees/{TASK_NAME}").
# Empty when worktree feature is disabled — downstream hooks treat empty as
# "no enforcement" so legacy projects without worktree configs aren't gated.
DDW_WORKTREE_TASKDIR=$(python3 -c "import json; c=json.load(open('$DDW_CONFIG_FILE')); wt=c.get('worktree') or {}; print(wt.get('taskDir',''))" 2>/dev/null || echo "")
