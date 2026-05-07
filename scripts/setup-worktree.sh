#!/usr/bin/env bash
# setup-worktree.sh — create a git worktree for a DDW task
# Usage: setup-worktree.sh <TASK-id> [--base <TASK-id>] [--root <consumer-path>]
#
# Chmod: ensure this file is executable:
#   chmod +x scripts/setup-worktree.sh
#   (or: the plugin install step runs chmod +x on all scripts/*.sh and scripts/ddw-*)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  echo "Usage: setup-worktree.sh <TASK-id> [--base <TASK-id>] [--root <consumer-path>]"
  echo ""
  echo "  <TASK-id>       Task ID to create a worktree for (e.g. TASK-20260507-foo)"
  echo "  --base <id>     Branch from task/<id> instead of main"
  echo "  --root <path>   Consumer repo root (default: cwd)"
  exit 1
}

# --- Parse arguments ---
TASK_ID=""
BASE_TASK=""
ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)
      shift
      BASE_TASK="${1:-}"
      [[ -z "$BASE_TASK" ]] && { echo "Error: --base requires a TASK-id argument" >&2; usage; }
      shift
      ;;
    --root)
      shift
      ROOT="${1:-}"
      [[ -z "$ROOT" ]] && { echo "Error: --root requires a path argument" >&2; usage; }
      shift
      ;;
    --help|-h)
      usage
      ;;
    -*)
      echo "Unknown flag: $1" >&2
      usage
      ;;
    *)
      if [[ -z "$TASK_ID" ]]; then
        TASK_ID="$1"
      else
        echo "Unexpected argument: $1" >&2
        usage
      fi
      shift
      ;;
  esac
done

[[ -z "$TASK_ID" ]] && { echo "Error: TASK-id is required" >&2; usage; }

# --- Step 1: Default --root to pwd. Resolve to absolute path. ---
if [[ -z "$ROOT" ]]; then
  ROOT="$(pwd)"
fi
ROOT="$(cd "$ROOT" && pwd)"

# --- Step 2: Check ddw.json exists ---
if [[ ! -f "${ROOT}/ddw.json" ]]; then
  echo "Error: ddw.json not found at ${ROOT}/ddw.json. Run /ddw:init first." >&2
  exit 1
fi

# --- Step 3: Read config values via Node helper ---
node_helper="${SCRIPT_DIR}/_ddw_read_config.mjs"

read_config() {
  local key="$1"
  local default_val="${2:-}"
  local val
  val=$(node "$node_helper" "$key" "$ROOT" 2>/dev/null) || val="$default_val"
  echo "$val"
}

TASK_DIR_TEMPLATE=$(read_config "worktree.taskDir" ".worktrees/{TASK_NAME}")
MAX_CONCURRENT=$(read_config "worktree.maxConcurrent" "3")
SYNC_FILES_JSON=$(read_config "worktree.syncFiles" '[]')
INSTALL_CMD=$(read_config "commands.install" "")

# Parse syncFiles array (JSON) into bash array
# Using node to iterate is simpler and avoids jq dependency
SYNC_FILES=()
while IFS= read -r entry; do
  SYNC_FILES+=("$entry")
done < <(node -e "
  const arr = JSON.parse(process.argv[1]);
  arr.forEach(x => process.stdout.write(x + '\n'));
" "$SYNC_FILES_JSON" 2>/dev/null || true)

# --- Step 4: Compute target dir (substitute {TASK_NAME}) ---
TARGET_DIR="${TASK_DIR_TEMPLATE//\{TASK_NAME\}/$TASK_ID}"
# Resolve relative to root
if [[ "$TARGET_DIR" != /* ]]; then
  TARGET_DIR="${ROOT}/${TARGET_DIR}"
fi

# --- Step 5: Branch name: task/<TASK-id> ---
BRANCH="task/${TASK_ID}"

# --- Step 6: Branch collision check ---
if git -C "$ROOT" rev-parse --verify "$BRANCH" &>/dev/null; then
  echo "Error: Branch ${BRANCH} already exists. Refusing to reuse." >&2
  exit 1
fi

# --- Step 7: Worktree count check ---
WORKTREES_DIR="${ROOT}/.worktrees"
count=0
if [[ -d "$WORKTREES_DIR" ]]; then
  while IFS= read -r d; do
    # Exclude integration dir
    basename_d="$(basename "$d")"
    if [[ "$basename_d" != "integration" ]]; then
      count=$((count + 1))
    fi
  done < <(find "$WORKTREES_DIR" -mindepth 1 -maxdepth 1 -type d -name 'TASK-*' 2>/dev/null || true)
fi

if [[ "$count" -ge "$MAX_CONCURRENT" ]]; then
  echo "Error: Max concurrent worktrees (${MAX_CONCURRENT}) reached. Close one first." >&2
  exit 1
fi

# --- Step 8: Determine base branch ---
if [[ -n "$BASE_TASK" ]]; then
  BASE_BRANCH="task/${BASE_TASK}"
else
  BASE_BRANCH="main"
fi

# --- Step 9: git worktree add ---
echo "Creating worktree at ${TARGET_DIR} from ${BASE_BRANCH}..."
if ! git -C "$ROOT" worktree add "$TARGET_DIR" -b "$BRANCH" "$BASE_BRANCH"; then
  echo "Error: git worktree add failed" >&2
  exit 1
fi

# --- Step 10: Sync files (macOS/Linux only) ---
# TODO: Windows symlink support deferred — MINGW/MSYS environments lack reliable symlink
# permissions. A cp-based fallback should be added when Windows support is needed.
OS="$(uname -s 2>/dev/null || echo "Unknown")"
if [[ "$OS" == "Darwin" || "$OS" == "Linux" ]]; then
  for entry in ${SYNC_FILES[@]+"${SYNC_FILES[@]}"}; do
    src="${ROOT}/${entry}"
    dst="${TARGET_DIR}/${entry}"
    [[ ! -e "$src" ]] && continue
    src_real="$(realpath "$src")"
    if [[ -L "$dst" ]]; then
      existing_target="$(readlink "$dst")"
      if [[ "$existing_target" == "$src_real" ]]; then
        continue # idempotent: already correctly symlinked
      fi
      echo "Warning: ${entry} is symlinked to ${existing_target}, expected ${src_real}. Skipped."
      continue
    fi
    if [[ -e "$dst" ]]; then
      echo "Warning: ${entry} already exists in worktree (tracked or local). Skipped."
      continue
    fi
    dst_parent="$(dirname "$dst")"
    mkdir -p "$dst_parent"
    ln -s "$src_real" "$dst"
    echo "Symlinked: ${entry}"
  done
else
  echo "Warning: Symlink step skipped on ${OS} (Windows symlinks not supported). Copy .env files manually."
fi

# --- Step 11: Port offset ---
# Write to .env.ddw (per-worktree, never in syncFiles). User's `commands.dev`
# is expected to source this file before launching dev servers.
slot=$((count + 1))
port_offset=$((slot * 100))
ENV_DDW="${TARGET_DIR}/.env.ddw"
echo "PORT_OFFSET=${port_offset}" > "$ENV_DDW"
echo "Slot ${slot}, PORT_OFFSET=${port_offset} (written to .env.ddw)"

# --- Step 12: Run install if dependency dir missing ---
if [[ -n "$INSTALL_CMD" ]]; then
  needs_install=false
  if [[ -f "${TARGET_DIR}/package.json" && ! -d "${TARGET_DIR}/node_modules" ]]; then
    needs_install=true
  elif [[ -f "${TARGET_DIR}/pyproject.toml" || -f "${TARGET_DIR}/requirements.txt" ]]; then
    if [[ ! -d "${TARGET_DIR}/.venv" && ! -d "${TARGET_DIR}/venv" ]]; then
      needs_install=true
    fi
  elif [[ -f "${TARGET_DIR}/go.mod" && ! -d "${TARGET_DIR}/vendor" ]]; then
    needs_install=true
  fi

  if [[ "$needs_install" == "true" ]]; then
    echo "Running install: ${INSTALL_CMD}"
    (cd "$TARGET_DIR" && bash -c "$INSTALL_CMD")
  fi
fi

# --- Step 13: Print success ---
echo "Worktree ready: ${TARGET_DIR} (branch: ${BRANCH}, slot ${slot})"
