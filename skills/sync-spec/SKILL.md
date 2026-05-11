---
name: sync-spec
description: Update CURRENT_SPEC from recent decisions and codebase. Works as a post-merge inline call (local mode close), a manual refresh, or a scheduled cron job.
disable-model-invocation: false
---

**Invocation gate:** Only run this skill when (1) the user explicitly typed the `/ddw:sync-spec` command, (2) `/ddw:close` step 13.A.7 calls it inline after a local merge, (3) a cron job invokes it, or (4) you proposed running this skill and the user clearly confirmed. Never auto-invoke from ambiguous context.

Update CURRENT_SPEC to reflect the current state of the codebase and recent decisions.

Two modes depending on `$ARGUMENTS`:
- **Task mode**: `$ARGUMENTS` is a task ID (e.g. `TASK-20260511-auth`) — update only sections affected by that task. Used by `/ddw:close` step 13.A.7.
- **Full mode**: `$ARGUMENTS` is empty or `--full` — read all recent decisions since the last sync and update every affected section. Used by cron and manual runs.

---

1. **Read config** — read `{workflowDir}/ddw.json` (search `workflows/ddw.json`, `.workflows/ddw.json`, then `.claude/ddw.json` for legacy) to get `workflowDir`, `specPath`, and `autoUpdateSpec`. Resolve user identity by running `git config user.name || whoami`.

2. **Check spec exists** — if `specPath` is null or the file doesn't exist: warn "No spec configured — nothing to update. Run `/ddw:init` to set one up." and exit.

3. **Resolve scope:**

   **Task mode** (task ID provided):
   - Check opt-in: proceed only if the task file's `**Spec-affecting:**` field is `yes`, OR `ddw.json.autoUpdateSpec` is `true`, OR the task's `## Changes` section explicitly names spec sections. If none: report "Spec update skipped — task not marked spec-affecting." and exit.
   - Read the task file from `{workflowDir}/tasks/archive/TASK-{id}.md` (post-merge) or `tasks/TASK-{id}.md` if not yet archived.
   - Read `## Changes` section and `**Decision:**` field.
   - Read the linked decision file if present — this is the spec delta; where it conflicts with current spec, the decision wins.

   **Full mode** (no task ID or `--full`):
   - Find all decisions NOT yet reflected in the spec: scan `{workflowDir}/decisions/` and `decisions/archive/` for DEC-*.md files whose ID does not appear in any `> Shaped by:` line in the spec.
   - Also read decisions from `decisions/archive/` created since the spec's most recent `> Shaped by:` timestamp.
   - These decisions are the delta set. Process them in chronological order.

4. **Load spec (tiered):**
   - Read the spec's headings and section structure first.
   - For task mode: read only sections relevant to the task's changes.
   - For full mode: read the full spec (it's a living doc — all sections may need updating).

5. **Identify changes** — for each decision in scope, cross-reference its content against the loaded spec sections. For each affected area determine:
   - What the spec currently says
   - What it should say given the decision
   - Which `> Shaped by:` attribution to set (task ID + decision ID)

6. **Apply updates:**
   - When `autoUpdateSpec` is `true` or running in cron/full mode: apply updates silently, then report what changed.
   - When `false` and task mode: show proposed diffs and require confirmation before writing.
   - For each section updated, set or replace its `> Shaped by:` reference line (e.g., `> Shaped by: TASK-20260406-auth-flow | DEC-20260401-auth-redesign`).
   - Use `templates/CURRENT_SPEC_TEMPLATE.md` as reference for section format.

7. **Drift check** — after updating, run `/ddw:drift` logic. If still **DRIFTED**, list remaining contradictions. The user (or cron log) records them for follow-up.

8. **Report:**
   ```
   Spec synced ({task mode: TASK-id | full mode: N decisions processed}):
   - {section}: {what changed}
   - ...
   Drift: SYNCED / DRIFTED (details)
   ```
