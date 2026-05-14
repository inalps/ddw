---
name: pr
description: Push a done task's branch and open a GitHub PR (team-PR mode). Transitions Status → in_review.
disable-model-invocation: false
---

**Invocation gate:** Only run this skill when (1) the user explicitly typed the `/ddw:pr` command, (2) a hook enforcement message demands it, or (3) you proposed running this skill and the user clearly confirmed. Never auto-invoke from ambiguous context.

Push a done task's feature branch and open a GitHub PR. Task: $ARGUMENTS (if not provided, ask the user which task).

This skill is the team-PR mode counterpart to local-mode merge in `/ddw:close` step 13.A. It replaces step 13 of `/ddw:close` when `merge.mode: "github-pr"`. After the PR is merged on GitHub, the owner re-runs `/ddw:close` to verify the merge, archive, and tear down the worktree.

0. **Read voice** — read `{workflowDir}/VOICE.md` (if it exists) and follow its communication style for all output during this skill.

1. **Read config + mode gate** — read `{workflowDir}/ddw.json` (search `workflows/ddw.json`, `.workflows/ddw.json`, then `.claude/ddw.json` for legacy) to get `workflowDir`, `merge.mode`, `merge.baseBranch` (default `"main"`). Resolve user identity by running `git config user.name || whoami`.

   If `merge.mode !== "github-pr"`, bail with:
   > "This skill is for team-PR mode. Your `ddw.json` has `merge.mode: \"local\"` — use `/ddw:close` instead."

   (Treat missing/null `merge.mode` as `"local"`.)

2. **Read the task file** at `{workflowDir}/tasks/TASK-{task-id}.md`. Hard gates, both must pass:
   a. `**Status:**` must be `done`. If not (e.g., `review_and_bugfix`), block: "Task is not done yet. Run `/ddw:review`, then have the Owner set status to `done` before opening a PR."
   b. The `## Owner Review Checklist` section must have no unchecked items (`- [ ]`). If any remain, block: "Owner Review Checklist is incomplete. Complete the checklist before opening a PR."

3. **Verify the task branch exists** — run `git -C {workflowRoot} rev-parse --verify --quiet task/{task-id}`. If the branch does not exist, bail:
   > "Branch `task/{task-id}` does not exist. The task was likely developed without `/ddw:sendit`. Create the branch manually and re-run, or convert to local-mode close."

4. **Push the branch** — `git -C {workflowRoot} push -u origin task/{task-id}`.
   - If the push fails (non-fast-forward, rejected by remote hook, network error, etc.), surface the exact error and stop. **Do NOT force-push.** Tell the owner to resolve manually (rebase, pull --rebase, or owner-driven force-push if intended) and re-run.

5. **Get the actual current UTC datetime** by running:
   ```bash
   date -u +"%Y-%m-%dT%H:%M:%SZ"
   ```

6. **Find or create the PR.**

   First check for an existing open PR:
   ```bash
   gh pr view task/{task-id} --json url,state,number 2>/dev/null
   ```
   - If a PR exists and `state == "OPEN"`: reuse it. Capture `url` and `number`. Print: "Existing PR found: {url}". Skip to step 7.
   - If a PR exists and `state == "CLOSED"` (not merged): bail and ask the owner — reopening or replacing is an owner call.
   - If a PR exists and `state == "MERGED"`: the branch was already merged. Skip to step 7 with a note for the owner to run `/ddw:close` next.
   - If no PR exists: create one.

   **Create the PR:**
   - Title: `{task-title} (TASK-{task-id})` — extract task title from the task file's `## Goal` heading neighborhood or the filename slug if the title isn't obvious.
   - Base branch: `{merge.baseBranch || "main"}`.
   - Head branch: `task/{task-id}`.
   - Body: build from the template below.

   ```bash
   gh pr create \
     --base "{merge.baseBranch || main}" \
     --head "task/{task-id}" \
     --title "{task-title} (TASK-{task-id})" \
     --body "$(cat <<'EOF'
   ## Task
   - File: `{relative path to task file}`
   {if linked DEC: }- Decision: `{relative path to DEC file}`

   ## Summary
   {1-3 lines from the task's `## Changes` section if filled, else from `## Goal`}

   ## Acceptance Criteria
   {one checkbox row per AC from the task's `## Acceptance Criteria` table:}
   - [ ] AC-01 — {criterion text}
   - [ ] AC-02 — {criterion text}
   ...

   ## DDW
   This PR was opened by `/ddw:pr`. After merge, the owner runs `/ddw:close TASK-{task-id}` to archive and tear down the worktree.
   EOF
   )"
   ```

   Capture the returned PR URL. If `gh pr create` fails (auth, repo not configured, etc.), surface the exact error and stop.

7. **Update the task file:**
   - Set `**Status:** in_review` at the top of the file (replacing `**Status:** done`).
   - Append to the `## Work Log` section:
     ```
     ### {actual UTC datetime}
     Status → in_review. PR opened: {pr-url}
     ```

8. **Report a clear summary:**
   ```
   PR opened for TASK-{task-id}.
   URL: {pr-url}
   Base: {baseBranch} ← task/{task-id}
   Status: done → in_review

   Next: reviewer merges the PR on GitHub, then run `/ddw:close TASK-{task-id}` to archive the task and tear down the worktree.
   ```

**Final note:** logs (`TASK_LOG.md`, `DECISION_LOG.md`, `RETRO_LOG.md`, `PRD_LOG.md`) are derived views. Run `node ${CLAUDE_PLUGIN_DIR}/scripts/ddw-index.mjs` to refresh, or rely on a pre-commit hook if configured.
