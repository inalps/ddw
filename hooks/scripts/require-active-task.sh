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

# Cross-repo exemption: if the file lives outside the current DDW project's
# filesystem subtree, this project's hooks don't gate it. Edits to a different
# repo (e.g. a plugin or external tool checked out elsewhere) are evaluated by
# their own project's hooks if any. Without this exemption the worktree-
# locality check below would block any cross-repo work from inside a session
# rooted at a DDW project.
PROJECT_ABS=$(cd "$DDW_PROJECT_DIR" 2>/dev/null && pwd -P || echo "$DDW_PROJECT_DIR")
case "$FILE_PATH" in
  "$PROJECT_ABS/"*) ;;        # inside project — proceed to gates below
  *) exit 0 ;;                  # outside project — pass through
esac

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

# Auto-mode bypass — /ddw:auto runs are gated by auto.confirm_on instead of
# per-edit checks, and may legitimately operate outside per-task worktrees.
DDW_RUNTIME="$DDW_PROJECT_DIR/$DDW_WORKFLOW_DIR/.ddw"
AUTO_BYPASS=0
if [[ -f "$DDW_RUNTIME/AUTO_RUN_ACTIVE" ]]; then
  AUTO_BYPASS=1
fi

# PROJECT_ABS already resolved above for the cross-repo exemption.

# Collect IDs of in_progress tasks owned by this user (or legacy ownerless).
INPROG_IDS=()
for TASK_FILE in "$TASKS_DIR"/TASK-*.md; do
  [[ -f "$TASK_FILE" ]] || continue
  OWNER=$(grep -m1 '^\*\*Owner:\*\*' "$TASK_FILE" 2>/dev/null | sed 's/\*\*Owner:\*\* *//' | xargs)
  STATUS=$(grep -m1 '^\*\*Status:\*\*' "$TASK_FILE" 2>/dev/null | sed 's/\*\*Status:\*\* *//' | xargs)

  if [[ "$STATUS" != "in_progress" ]]; then
    continue
  fi

  # Legacy tasks without Owner field — anyone may match
  if [[ -z "$OWNER" || "$OWNER" == "$USER_NAME" ]]; then
    TID=$(basename "$TASK_FILE" .md)
    INPROG_IDS+=("$TID")
  fi
done

# No in_progress tasks at all → original behavior: block with helpful message.
if [[ ${#INPROG_IDS[@]} -eq 0 ]]; then
  echo "BLOCKED: No in_progress task found for user '$USER_NAME'."
  echo "Create a task with /ddw:task and start it with /ddw:sendit."
  exit 2
fi

# At least one in_progress task. Original behavior would pass-through here.
# New rule: when worktree.taskDir is configured AND we're not in auto-mode,
# the file being edited must live INSIDE one of those tasks' worktree
# directories. This forces step 7.5 of /ddw:sendit (worktree setup) to have
# actually been honored, instead of being silently skipped.
if [[ -z "$DDW_WORKTREE_TASKDIR" || $AUTO_BYPASS -eq 1 ]]; then
  exit 0
fi

# Resolve the absolute path of the file being edited (it might be a symlink).
FILE_ABS=$(cd "$(dirname "$FILE_PATH")" 2>/dev/null && pwd -P 2>/dev/null)/$(basename "$FILE_PATH")
if [[ -z "$FILE_ABS" || "$FILE_ABS" == "/$(basename "$FILE_PATH")" ]]; then
  # Fallback: file may not exist yet (Write-create case). Use raw FILE_PATH.
  FILE_ABS="$FILE_PATH"
fi

# Build candidate worktree paths and check whether the file lives in one.
for TID in "${INPROG_IDS[@]}"; do
  WT_REL="${DDW_WORKTREE_TASKDIR/\{TASK_NAME\}/$TID}"
  # Strip a leading ./ if any
  WT_REL="${WT_REL#./}"
  WT_ABS="$PROJECT_ABS/$WT_REL"
  # Trailing slash to avoid a partial-prefix false positive
  case "$FILE_ABS/" in
    "$WT_ABS/"*) exit 0 ;;
  esac
done

# File is not inside any in_progress task's worktree. Block.
INPROG_LIST=$(printf "  - %s\n" "${INPROG_IDS[@]}")
EXAMPLE_TID="${INPROG_IDS[0]}"
EXAMPLE_WT_REL="${DDW_WORKTREE_TASKDIR/\{TASK_NAME\}/$EXAMPLE_TID}"

cat <<EOF

BLOCKED: edit is outside the in_progress task's worktree.

In-progress tasks for '$USER_NAME':
$INPROG_LIST
File being edited:
  $FILE_PATH

Project '$DDW_PROJECT_DIR' has worktree.taskDir configured as '$DDW_WORKTREE_TASKDIR',
so per-task implementation must happen inside the corresponding worktree
directory. main is integration only — it does NOT receive direct edits while
a task is in progress. Closes the gap that earlier let /ddw:sendit step 7.5
be silently skipped.

To proceed:
  1. Ensure the worktree exists for the task you intend to edit:
       bash \${CLAUDE_PLUGIN_DIR}/scripts/setup-worktree.sh $EXAMPLE_TID
     (creates $EXAMPLE_WT_REL/ on a fresh task/$EXAMPLE_TID branch)
  2. Issue subsequent edits with absolute paths under that worktree, e.g.
       $PROJECT_ABS/$EXAMPLE_WT_REL/<your file>
  3. Inside an active /ddw:auto session, the AUTO_RUN_ACTIVE marker bypasses
     this gate (auto's autonomy gate is the per-task check at that level).

Workflow paperwork edits (workflows/, CLAUDE.md, .claude/, docs/, tasks/,
.gitignore, *.md) are exempt above and remain editable on the working tree
without being inside a worktree — only implementation files are gated.
EOF
exit 2
