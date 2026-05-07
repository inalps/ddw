---
name: task
description: Scaffold a new TASK file from template. Picks the date prefix automatically.
disable-model-invocation: false
---

**Invocation gate:** Only run this skill when (1) the user explicitly typed the `/ddw:task` command, (2) a hook enforcement message demands it, or (3) you proposed running this skill and the user clearly confirmed. Never auto-invoke from ambiguous context.

Create a new task file using the Decision-Driven Workflow.

1. **Read config** — read `{workflowDir}/ddw.json` (search `workflows/ddw.json`, `.workflows/ddw.json`, then `.claude/ddw.json` for legacy) to get `workflowDir` (default: `workflows`). Resolve user identity by running `git config user.name || whoami`.

1.5. **Logs are derived views.** Do not sync inline — `ddw-index` is the canonical generator. The owner runs `node ${CLAUDE_PLUGIN_DIR}/scripts/ddw-index.mjs` (or via pre-commit hook) to refresh. Skill steps below reference data from source files, never from `logs/`.

2. **Get today's UTC date** in `yyyymmdd` format for the file name prefix.

3. **Read the task template** at `{workflowDir}/tasks/TASK_TEMPLATE.md`.

4. **Ask the user** (via AskUserQuestion) for the following if not already provided in $ARGUMENTS:
   - **Title** (short, descriptive — becomes the filename slug, e.g. `auth-middleware`)
   - **Goal** (what must be implemented)
   - **Scope** (what is included)
   - **Non-Goals** (what must NOT be done)
   - **Related Decision** (DEC-{yyyymmdd}-{title}, or "none" for small bug fixes)
   - **Priority** (P1 = must do first, P2 = normal, P3 = nice to have; default P2)
   - **Estimated scope** — options: S (small, ~30min, single file), M (medium, 1-2hr), L (large, ≥2hr or multi-file architectural). Default S.
   - **Multi-session expected?** — yes/no. Default no.

5. **Verify the decision is `decided`** — if a related decision was given, read the decision file and confirm its status is `decided`. If it's still `proposed`, warn the user and do not create the task.

5.5. **Check milestone phase status** — if a related decision was given:
   - Read `{workflowDir}/MILESTONES.md`.
   - Find the `##` section that lists this decision ID.
   - If the section heading ends with `✅` (phase is complete): warn the user: "Decision {id} belongs to milestone '{name}' which is already complete. Are you sure you want to add a task to a completed phase? Consider creating a new decision in an active milestone instead."
   - Only proceed if the user explicitly confirms. If the user declines, stop — do not create the task.

6. **Get the actual current UTC datetime** by running:
   ```bash
   date -u +"%Y-%m-%dT%H:%M:%SZ"
   ```

7. **Create the task file** at `{workflowDir}/tasks/TASK-{yyyymmdd}-{slug}.md` using the template. Fill in:
   - Status: planned
   - Decision: the related decision ID (or "none")
   - Owner: `userName` from `ddw.json`
   - Date: the actual UTC datetime
   - Priority: from user input (default P2)
   - Depends-On: auto-fill from decision's `## Tasks` section (see 7.1), or "none"
   - Goal, Scope, Non-Goals from user input
   - Leave all other sections with their template placeholders

   After copying the template, remove OPTIONAL sections whose conditions are not met based on the user's scope and multi-session answers. Also remove their `<!-- OPTIONAL: ... -->` marker comments. Conditions:
   - scope == S → remove `## Constraints` and `## Non-Goals`
   - multi-session == no → remove `## Context Packing` and `## Session Handoff`
   Keep all non-optional sections unchanged.

7.1. **Auto-fill dependencies** — if a related decision was given, read its `## Tasks` section. Look for `(depends: slug-a, slug-b)` annotations on the current task's slug entry. For each dependency slug, find the matching TASK ID in TASK_LOG (e.g., `slug-a` → `TASK-{yyyymmdd}-slug-a`). Set `**Depends-On:**` to the comma-separated list of resolved TASK IDs. If no dependencies are annotated or no decision exists, set to `none`.

8. **Fill Acceptance Criteria** — populate the `## Acceptance Criteria` table with at least 2 machine-testable checks derived from the task's Goal and Scope. Each row needs:
   - **ID**: AC-01, AC-02, ...
   - **Criterion**: what must be true
   - **Check**: one of `code-grep`, `code-review`, `spec-compare`, `manual`
   - **Expected**: the specific expected result
   These will be scored by `/ddw:qa` during review.

9. Skip inline TASK_LOG row write — `ddw-index` is the canonical generator. The new task file IS the source of truth.

10. **If a related decision was given**, open the decision file and update its `## Tasks` section: find the matching slug entry (e.g. `- {slug} — ...`) and replace it with the full task ID (e.g. `- TASK-{yyyymmdd}-{slug} — {description}`). If no matching slug entry exists, append the task reference as a new line.

11. **Report**: the file path created and the task ID.

12. **Ask**: "Want me to start implementing now?" If the user confirms (yes / do it / go / start):
    - Get the actual current UTC datetime (`date -u +"%Y-%m-%dT%H:%M:%SZ"`)
    - Set `**Status:** in_progress` in the task file
    - Append a Work Log entry:
      ```
      ### {actual UTC datetime}
      Status → in_progress. Beginning implementation.
      ```
    - Read guardrails at `{workflowDir}/guardrails/GUARDRAILS.md` (if it exists)
    - Read the task's Scope, Constraints, and Files sections
    - Begin implementation

**Final note:** logs (`TASK_LOG.md`, `DECISION_LOG.md`, `RETRO_LOG.md`, `PRD_LOG.md`) are derived views. Run `node ${CLAUDE_PLUGIN_DIR}/scripts/ddw-index.mjs` to refresh, or rely on a pre-commit hook if configured.
