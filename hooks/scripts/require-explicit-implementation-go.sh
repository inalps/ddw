#!/usr/bin/env bash
# DDW Hook: require-explicit-implementation-go
#
# Closes the "ambiguous-do-it" gap: prevents Claude from beginning Edit/Write/
# Bash actions for a task that was just flipped to in_progress by /ddw:sendit
# without explicit owner authorization in this session.
#
# Pairs with:
#   - clear-awaiting-go.sh  (UserPromptSubmit) — clears markers on affirmative
#                            user prompts or when the user names a task.
#   - /ddw:sendit step 7    — writes the marker after status flip.
#   - /ddw:auto step 4      — writes AUTO_RUN_ACTIVE bypass marker on entry.
#
# Marker layout:
#   {workflowDir}/.ddw/awaiting-go-{TASK-ID}.flag      (per task awaiting go)
#   {workflowDir}/.ddw/AUTO_RUN_ACTIVE                  (bypass while auto is up)
#
# Why a hook (not just a SKILL.md instruction): a SKILL.md "stop and ask" step
# is advisory — the model can talk itself past it. A PreToolUse hook fails
# closed: as long as the marker exists, no edits land. The model is forced to
# stop and produce a plan summary instead.

set -euo pipefail

INPUT=$(cat)

# _config.sh exits 0 silently in non-DDW projects; same fast-path applies.
source "$(dirname "$0")/_config.sh"

WORKFLOW_DIR="$DDW_PROJECT_DIR/$DDW_WORKFLOW_DIR"
DDW_RUNTIME="$WORKFLOW_DIR/.ddw"

# Auto-mode bypass — /ddw:auto orchestration writes AUTO_RUN_ACTIVE on entry
# and removes it on exit. Inside an auto run, per-task owner-go confirmation
# is replaced by the orchestrator's autonomy gate (auto.confirm_on).
if [[ -f "$DDW_RUNTIME/AUTO_RUN_ACTIVE" ]]; then
  exit 0
fi

# No runtime dir → no markers possible → fast pass.
if [[ ! -d "$DDW_RUNTIME" ]]; then
  exit 0
fi

shopt -s nullglob
MARKERS=("$DDW_RUNTIME"/awaiting-go-*.flag)
shopt -u nullglob

if [[ ${#MARKERS[@]} -eq 0 ]]; then
  exit 0
fi

# At least one task is awaiting owner go-ahead. Block.
TASK_IDS=()
for m in "${MARKERS[@]}"; do
  base=$(basename "$m" .flag)
  TASK_IDS+=("${base#awaiting-go-}")
done

echo ""
echo "BLOCKED: implementation requires explicit owner go-ahead."
echo ""
echo "Task(s) awaiting confirmation:"
for tid in "${TASK_IDS[@]}"; do
  echo "  - $tid"
done
echo ""
echo "/ddw:sendit moved the task(s) above to in_progress, but the owner has"
echo "not yet authorized starting implementation in THIS session. Closes the"
echo "ambiguous-affirmation gap — 'do it' / 'go' / 'yes' from a prior turn"
echo "with multiple proposals on the table is not enough by itself."
echo ""
echo "To proceed, the agent should:"
echo "  1. Stop and summarize what it intends to build (Goal + Scope highlights)."
echo "  2. Wait for the owner's reply."
echo ""
echo "Owner authorizes by either:"
echo "  - Typing an affirmative ('go' / 'yes' / 'continue' / 'proceed' / 'ok')"
echo "    when exactly ONE task is awaiting (clear-awaiting-go hook clears it);"
echo "  - Naming the task id or slug ('go on m3-app-split' / 'continue with"
echo "    TASK-20260509-m3-app-split');"
echo "  - Running /ddw:auto, which sets AUTO_RUN_ACTIVE and bypasses this gate."
echo ""
exit 2
