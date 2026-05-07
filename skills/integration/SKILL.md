---
name: integration
description: Manage the integration worktree. Subcommands: unstage <TASK-id>, reset.
disable-model-invocation: false
---

**Invocation gate:** Only run this skill when (1) the user explicitly typed the `/ddw:integration` command, (2) you proposed running this skill and the user clearly confirmed.

Manage the integration worktree. Subcommand: $ARGUMENTS.

Use this when the normal queue flow needs an exception: a staged task fails its smoke-test (unstage), or the integration worktree needs to be wiped back to `origin/main` (reset).

0. **Read voice** — read `{workflowDir}/VOICE.md` (if it exists) and follow its style.

1. **Read config** — read `{workflowDir}/ddw.json` to resolve `workflowRoot`. If no `ddw.json`, error: "Run `/ddw:init` first."

2. **Parse subcommand from $ARGUMENTS:**
   - `unstage <TASK-id>` → revert the currently-testing task
   - `reset` → wipe integration worktree back to `origin/main` (or local `main` fallback)
   - Anything else → error: "Unknown subcommand. Supported: `unstage <TASK-id>`, `reset`."

3. **Dispatch — `unstage <TASK-id>`:**
   - Run `bash ${CLAUDE_PLUGIN_DIR}/scripts/ddw-unstage {TASK-id} --root ${workflowRoot}` and print the output.
   - The script: verifies `testing` matches the given TASK-id (refuses if not), `git reset --hard HEAD~1` on the integration worktree, flips task `**Status:** ready_for_integration → in_progress`, and clears `.ddw/integration.json`.
   - **After unstage**, prompt: "Run `/ddw:queue tick` to stage the next ready task?" — only if `/ddw:queue list` shows other ready tasks. Otherwise, just say "Queue empty."

4. **Dispatch — `reset`:**
   - Confirmation: this is destructive — it discards every merge in integration since `main`. Ask the user to confirm: "Reset integration worktree to origin/main? All staged work will be lost. (y/N)"
   - Only if user types `y` (case-insensitive): run `bash ${CLAUDE_PLUGIN_DIR}/scripts/ddw-integration-reset --root ${workflowRoot} --yes` and print the output. Pass `--yes` because the skill already collected confirmation.
   - The script: `git fetch origin main` (warns and proceeds if no remote), `git reset --hard origin/main` (or local `main`), runs `commands.install` if configured, clears `.ddw/integration.json`.

5. **Authority note:** these scripts are the §13 authoritative writers for `.ddw/integration.json` (`unstage` clears `testing`; `reset` clears `testing`). `unstage` is also the authoritative writer for the `ready_for_integration → in_progress` flip — exception path documented in §13.
