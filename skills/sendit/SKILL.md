---
name: sendit
description: Set a planned task to in_progress and start implementing. Send it!
disable-model-invocation: false
---

**Invocation gate:** Only run this skill when (1) the user explicitly typed the `/ddw:sendit` command, (2) a hook enforcement message demands it, or (3) you proposed running this skill and the user clearly confirmed. Never auto-invoke from ambiguous context.

Send it! Start implementing a task. Task: $ARGUMENTS (if not provided, use the most recently created `planned` or `in_progress` task).

0. **Read voice** — read `{workflowDir}/VOICE.md` (if it exists) and follow its communication style for all output during this skill.

1. **Read config** — read `{workflowDir}/ddw.json` (search `workflows/ddw.json`, `.workflows/ddw.json`, then `.claude/ddw.json` for legacy) to get `workflowDir` (default: `workflows`). Resolve user identity by running `git config user.name || whoami`.

1.5. **Logs are derived views.** Do not sync inline — `ddw-index` is the canonical generator. The owner runs `node ${CLAUDE_PLUGIN_DIR}/scripts/ddw-index.mjs` (or via pre-commit hook) to refresh. Skill steps below reference data from source files, never from `logs/`.

2. **Find the task:**
   - If $ARGUMENTS names a task, use that.
   - Otherwise, scan `{workflowDir}/tasks/TASK-*.md` for the most recently created file with `**Status:** planned` or `**Status:** in_progress` where `**Owner:**` matches the resolved user identity (or Owner is empty — legacy tasks).
   - If no matching task exists, tell the user: "Nothing to send — no planned tasks for {resolved identity}. Run `/ddw:decision` first."

3. **Verify the linked decision is `decided`** — read the task's `**Decision:**` field. If it references a decision, confirm its status is `decided`. If not, block and explain.

4. **Check for session handoff** — read the task's `## Session Handoff` section. Parse the structured fields:
   - `**Status:**` — in_progress, blocked, or none
   - `**Completed ACs:**` — list of AC IDs already passed
   - `**Remaining ACs:**` — list of AC IDs still to do
   - `**Files touched:**` — files modified so far
   - `**Blockers:**` — any blockers or "none"
   - `**Next action:**` — what to do next
   - `**Context:**` — non-obvious state (e.g., "tried approach X, failed because Y")

   If Status is not "none" (handoff has content):
   - Display a structured resume summary:
     ```
     Resuming from previous session:
     ✅ Completed: {Completed ACs}
     🔲 Remaining: {Remaining ACs}
     📁 Files touched: {files list}
     ➡️  Next: {Next action}
     ```
   - If Blockers is not "none", flag prominently: "⚠️ Blockers: {blockers}"
   - If Context has content, display as advisory: "💡 Context: {context}"
   - Clear the handoff section — reset all fields to template defaults (Status: none, lists: [], others: empty).

   If Status is "none" or all fields are empty/placeholder, skip this step.

5. **Load developer profile** — read the `agents/developer.md` bundled with the DDW plugin (plugin root, not project directory). Adopt its mindset for implementation:
   - Spec-first: read all docs before coding
   - Minimal blast radius: change only what the task requires
   - Verify assumptions against spec and code
   - Regression awareness: check INVARIANTS.md before declaring done

6. **Get the actual current UTC datetime** by running:
   ```bash
   date -u +"%Y-%m-%dT%H:%M:%SZ"
   ```

7. **Activate the task** (skip if already `in_progress`):
   - If `**Owner:**` is empty, set it to the resolved user identity
   - Set `**Status:** in_progress` in the task file
   - Append a Work Log entry:
     ```
     ### {actual UTC datetime}
     Status → in_progress. Sending it! (Owner: {resolved identity})
     ```

7.4. **Write the awaiting-go marker.** Pairs with the `require-explicit-implementation-go` PreToolUse hook to close the ambiguous-affirmation gap (an out-of-context "do it" / "go" / "yes" from a turn with multiple proposals on the table should NOT authorize implementation by itself). Run via Bash (NOT Write) so the marker write does not trigger the hook it's setting up:
   ```bash
   mkdir -p "{workflowDir}/.ddw" && touch "{workflowDir}/.ddw/awaiting-go-{task-id}.flag"
   ```
   Skip this step entirely when running under `/ddw:auto` — the orchestrator's `AUTO_RUN_ACTIVE` marker bypasses this gate by design (auto's own `auto.confirm_on` autonomy gate is the per-task check at that level).

   The marker is cleared automatically by `clear-awaiting-go.sh` (UserPromptSubmit) when the owner either (a) sends an unambiguous affirmative AND there is exactly one task awaiting, or (b) names the task ID/slug in their message. Multiple markers + bare affirmative = remains blocked, the owner must disambiguate.

7.5. **Set up task worktree** (git only — skip if not a git repo):
   - Check: `git rev-parse --git-dir 2>/dev/null`. If not a git repo, skip this step.
   - Branch name: `task/{task-id}` (e.g., `task/TASK-20260331-auth-middleware`)
   - **Detect current worktree**: run `git rev-parse --show-toplevel` and compare to the resolved `worktree.taskDir` template substituted with `{task-id}`. If they match, the user is already in this task's worktree → continue (resuming work), no further action.
   - **If `ddw.json.worktree` is configured** (default for new init): invoke `bash ${CLAUDE_PLUGIN_DIR}/scripts/setup-worktree.sh {task-id} --root ${workflowRoot}`. This creates `.worktrees/{task-id}/` on a fresh `task/{task-id}` branch, writes `PORT_OFFSET` to `.env.ddw`, symlinks `worktree.syncFiles`, and runs `commands.install` if needed. The script refuses if the branch already exists or `maxConcurrent` is reached — surface its error and stop.
   - **After creation**, all subsequent edits in this skill (and during implementation) MUST use absolute paths inside the new worktree directory. Tell the user once: "Worktree ready at `.worktrees/{task-id}/`. `cd` there in your terminal if you want to run dev/test commands locally — Claude will operate inside it via absolute paths."
   - **Fallback (no `worktree` config)**: plain branch checkout in current working tree. If branch exists but not checked out: `git checkout task/{task-id}`. If branch doesn't exist: `git checkout -b task/{task-id}`. If not on main/master when creating, warn but allow.

8. **Read guardrails (tiered):**
   - Read `{workflowDir}/guardrails/GUARDRAILS.md` (if it exists): scan headings and rule names first, then read only sections relevant to this task's scope and files.
   - Read `{workflowDir}/guardrails/INVARIANTS.md` fully — these are compact, machine-testable rules and must all be respected during implementation.

8.5. **Read spec (tiered)** — if `specPath` is configured in ddw.json:
   - Read headings/section names from the spec first.
   - Read only sections relevant to this task's scope and affected files.
   - Skip unrelated domain areas — they waste context without aiding implementation.

9. **Read the task** — Scope, Constraints, Files, Completion Criteria sections.

10. **Output the send-it message:**

    ```
    🧗 SENDING IT! 🏔️

    Task: {task ID}
    Route: {task title}

    Chalk up, no looking down — let's climb.
    ```

11. **Begin implementation** — start working on the task scope.

    **Gate behavior (when not running under `/ddw:auto`).** The first Edit/Write call will be blocked by the `require-explicit-implementation-go` PreToolUse hook, because step 7.4 wrote the awaiting-go marker. This is by design: the gate ensures the owner has *explicitly* authorized starting THIS task in the current session — not via a re-interpreted affirmation from an earlier turn.

    On the first block:
    1. Stop. Do NOT retry the edit.
    2. Print a short plan summary to the user: Goal in one sentence + the 3–5 concrete files/areas you intend to touch + any risks or open questions you want to flag before going.
    3. Wait for the owner's reply. Authorization clears the marker automatically (see step 7.4); after that, edits proceed normally.

    **Gate behavior (under `/ddw:auto`).** Step 7.4 is skipped, no marker exists, the hook passes through, and implementation proceeds without owner-confirm — as intended for autonomous overnight runs (the `auto.confirm_on` policy is the equivalent gate at that level).

12. **Write tests** — after implementation, before review:
    - Write **unit tests** for every new or changed function — verify individual logic in isolation.
    - Write **integration tests** for feature-level behavior — verify components work together end-to-end.
    - Tests must be runnable via the project's `testCommand` (from `ddw.json`).
    - Run all tests and confirm they pass.
    - Fill the task file's `## Tests` section with the test files created, their type (unit/integration), and what they cover.
    - If the project has no test infrastructure yet, set it up as part of this step.
    - A task is **not implementation-complete** until its tests exist and pass.

12.5. **Maintain ignore files** — after implementation and tests, ensure `.gitignore` and `.dockerignore` reflect the current project state. This keeps ignore files in sync as the project evolves across tasks.

   1. **Scan project root** for stack markers and existing artifacts:
      - `package.json`, `yarn.lock`, or `pnpm-lock.yaml` → Node (ignore `node_modules/`, `dist/`, `.next/`, `coverage/`, `.turbo/`, `.nuxt/`, `.output/`)
      - `requirements.txt`, `pyproject.toml`, `setup.py`, or `Pipfile` → Python (ignore `__pycache__/`, `.venv/`, `venv/`, `*.pyc`, `.mypy_cache/`, `.pytest_cache/`, `*.egg-info/`, `.ruff_cache/`)
      - `go.mod` → Go (ignore `vendor/`, `*.exe`, `*.test`, `*.out`)
      - `Cargo.toml` → Rust (ignore `target/`, `*.pdb`)
      - Always include common patterns: `.DS_Store`, `Thumbs.db`, `.env`, `.env.*`, `*.log`, `.idea/`, `.vscode/`, `*.swp`, `*.swo`

   2. **`.gitignore`:**
      - If it doesn't exist → create it with all detected patterns, grouped by stack under comments (e.g., `# Node`, `# Python`, `# Common`).
      - If it exists → read it, identify missing patterns from the detected stacks. Append only new patterns under a `# DDW-managed` comment block at the end. Never remove or reorder existing entries.

   3. **`.dockerignore`** (only if `Dockerfile`, `docker-compose.yml`, `docker-compose.yaml`, or `compose.yml` exists):
      - Generate or refresh with: `.git`, `{workflowDir}/`, `*.md` (except README.md), `test/`, `tests/`, `__tests__/`, `coverage/`, `.env`, `.env.*`, `node_modules/` (if Node), `__pycache__/` (if Python), `target/` (if Rust), plus any stack-specific build/test artifacts.
      - Same merge logic as `.gitignore` — append missing patterns under `# DDW-managed`, never remove existing entries.

   4. If no changes are needed, skip silently. Only log to the Work Log when files are created or updated: `Refreshed .gitignore` / `Created .dockerignore` / etc.

12.6. **Companion-test gate** — after step 12's tests are written and pass (or after determining no tests are applicable), enforce this gate before auto-review:
   1. Read `ddw.json.testFilePattern`. If absent, fall back to common patterns: `*.test.ts`, `*.test.js`, `*_test.py`, `*_test.go`, `*_test.rs`.
   2. Glob for test files matching the pattern in directories that contain files modified during this task. Use the task's `## Files` section and `## Tests` section as the source of modified directories.
   3. If ≥1 test file exists matching the pattern → proceed to step 13.
   4. If 0 test files match → check the task file for a `**No-Test-Justification:**` field:
      - Present and non-empty → append to Work Log: "Sendit gate: no test, justified — {reason}" and proceed to step 13.
      - Absent or empty → **BLOCK** with: "No companion test detected matching `{testFilePattern}`. Either (a) add a test, or (b) add `**No-Test-Justification:** <reason>` to the task file frontmatter, then re-run /ddw:sendit."

13. **Auto-review** — when implementation and tests are complete, immediately run `/ddw:review` logic against this task. Do not wait for the user to trigger it. The owner should receive a fully reviewed task, not a half-finished handoff. After `/ddw:review` runs it sets `**Status:** review_and_bugfix` (or leaves the task at its current status if open blockers remain). The owner — or `/ddw:auto`'s advance-review row — flips `review_and_bugfix → done` once the review is clear, and `/ddw:close` handles rebase + merge. No queue tick, no integration staging.

**Final note:** logs (`TASK_LOG.md`, `DECISION_LOG.md`, `RETRO_LOG.md`, `PRD_LOG.md`) are derived views. Run `node ${CLAUDE_PLUGIN_DIR}/scripts/ddw-index.mjs` to refresh, or rely on a pre-commit hook if configured.
