---
name: sync-spec
description: Update CURRENT_SPEC to reflect a merged task's changes. Run post-merge (after /ddw:close in local mode, or after PR merges in PR mode).
disable-model-invocation: false
---

**Invocation gate:** Only run this skill when (1) the user explicitly typed the `/ddw:sync-spec` command, (2) `/ddw:close` step 13.A.7 calls it inline, or (3) you proposed running this skill and the user clearly confirmed. Never auto-invoke from ambiguous context.

Update CURRENT_SPEC to reflect behavior introduced by a merged task. Run this after the task branch has been merged into base — never before.

Task: $ARGUMENTS (if not provided, ask the user which task).

---

1. **Read config** — read `{workflowDir}/ddw.json` (search `workflows/ddw.json`, `.workflows/ddw.json`, then `.claude/ddw.json` for legacy) to get `workflowDir`, `specPath`, and `autoUpdateSpec`. Resolve user identity by running `git config user.name || whoami`.

2. **Check opt-in** — spec update is opt-in. Proceed only if at least one of these is true:
   - The task file's `**Spec-affecting:**` field is `yes`
   - `ddw.json.autoUpdateSpec` is `true`
   - The task's `## Changes` section explicitly names spec sections

   If none are true: report "Spec update skipped — task not marked spec-affecting." and exit.

3. **Guard: merge must be done** — verify the task branch (`task/{task-id}`) has already been merged into base:
   - Run `git branch --merged {base}` and check if `task/{task-id}` appears.
   - If NOT merged: block with "Task branch not yet merged. Run `/ddw:sync-spec` after the merge completes."

4. **Read the task file** from `{workflowDir}/tasks/archive/TASK-{date}-{title}.md` (archived post-merge) or `{workflowDir}/tasks/TASK-{date}-{title}.md` if not yet archived. Read:
   - `## Changes` section — what changed, which files and behaviors
   - `**Decision:**` field — linked decision ID

5. **Read linked decision** — if a decision is referenced, read `{workflowDir}/decisions/{DEC-id}.md` (or `decisions/archive/`). This is the spec delta — where it conflicts with the current spec, the decision wins.

6. **Load spec (tiered)** — if `specPath` is configured and the file exists:
   - Read the spec's headings and section structure first.
   - Read only sections relevant to the task's changes — skip unrelated domain areas.
   - If `specPath` is null or file doesn't exist: warn "No spec configured — nothing to update. Run `/ddw:init` to set one up." and exit.

7. **Identify changes** — cross-reference task's `## Changes` and decision content against loaded spec sections. For each affected area, determine:
   - What the spec currently says
   - What it should say after this task
   - Which `> Shaped by:` attribution to set

8. **Apply updates**:
   - When `autoUpdateSpec` is `true`: apply updates silently, then report what changed.
   - When `false`: show proposed diffs and require confirmation before writing.
   - For each section updated, set or replace its `> Shaped by:` reference line with the current task and decision IDs (e.g., `> Shaped by: TASK-20260406-auth-flow | DEC-20260401-auth-redesign`).
   - Use `templates/CURRENT_SPEC_TEMPLATE.md` as reference for section format.

9. **Drift check** — after updating, run `/ddw:drift` logic to confirm spec and code are now consistent. If still **DRIFTED**, list remaining contradictions. The user decides whether to fix now or defer.

10. **Report**:
    ```
    Spec updated for {task-id}:
    - {section}: {what changed}
    - ...
    Drift: SYNCED / DRIFTED (details)
    ```
