---
name: close
description: Run the mandatory post-done checklist after Owner sets a task to done. Updates all logs and the spec.
disable-model-invocation: false
---

**Invocation gate:** Only run this skill when (1) the user explicitly typed the `/ddw:close` command, (2) a hook enforcement message demands it, or (3) you proposed running this skill and the user clearly confirmed. Never auto-invoke from ambiguous context.

Run the post-task close checklist. The Owner has already set the task to `done`. Your job is to complete all mandatory updates.

Task to close: $ARGUMENTS (if not provided, ask the user which task).

0. **Read voice** — read `{workflowDir}/VOICE.md` (if it exists) and follow its communication style for all output during this skill.

1. **Read config** — read `{workflowDir}/ddw.json` (search `workflows/ddw.json`, `.workflows/ddw.json`, then `.claude/ddw.json` for legacy) to get `workflowDir`, `specPath`, `autoUpdateSpec`, and `testCommand`. Resolve user identity by running `git config user.name || whoami`.

1.5. **Logs are derived views.** Do not sync inline — `ddw-index` is the canonical generator. The owner runs `node ${CLAUDE_PLUGIN_DIR}/scripts/ddw-index.mjs` (or via pre-commit hook) to refresh. Skill steps below reference data from source files, never from `logs/`.

2. **Read the task file** at `{workflowDir}/tasks/TASK-{date}-{title}.md` to understand what was implemented.

3. **Hard gate** — two checks, both must pass:
   a. Check the task's `**Status:**` field. If it is NOT `done`, block: "Task is not done yet. Run `/ddw:review` first, then set the task to `done` before closing."
   b. Check the `## Owner Review Checklist` section. If any items are unchecked (`- [ ]`), block: "Owner Review Checklist is not complete. Run `/ddw:review` first."
   Do not proceed if either check fails.

4. **Get the actual current UTC datetime** by running:
   ```bash
   date -u +"%Y-%m-%dT%H:%M:%SZ"
   ```

5. **Task file — status + Work Log:**
   - Set `**Status:** done` at the top of the file.
   - Append a final entry to the `## Work Log` section:
     ```
     ### {actual UTC datetime}
     Status → done. Owner verification passed.
     ```

6. **TASK_LOG.md** — skip direct update. `ddw-index` derives the log from task source files.

7. **Task file — Changes section** — fill the `## Changes` section in the task file:
   ```
   **Summary:** {2-4 sentences: what changed, what files/systems affected, test count if applicable}
   ```

8. **CURRENT_SPEC (opt-in, tiered)** — spec review is opt-in; skip silently unless at least one of these conditions is true:
   - The task file's frontmatter declares `**Spec-affecting:** yes`
   - `ddw.json.autoUpdateSpec` is `true`
   - The task's `## Changes` section explicitly mentions spec sections

   For purely internal tasks (refactor, tests, tooling, bug fix without visible-behavior change) where none of the above conditions are true: skip silently and append to Work Log: "Spec review: skipped (no spec-affecting changes declared)."

   When ANY condition is true, run the tiered logic:
   - If `specPath` is null or the spec file doesn't exist, skip and warn: "No spec configured. Consider running `/ddw:init` to set one up."
   - Read the spec's headings/section structure first.
   - Read the task's `## Changes` section (from step 7) to identify what behavior changed.
   - Read only the spec sections affected by those changes — skip unrelated domain areas.
   - Update the relevant sections of the spec to reflect the new reality. Use `templates/CURRENT_SPEC_TEMPLATE.md` as reference for section format. For each section updated, set or replace the `> Shaped by:` reference line with the current task and decision IDs (e.g., `> Shaped by: TASK-20260406-auth-flow | DEC-20260401-auth-redesign`).
   - When `autoUpdateSpec` is `true`, apply updates silently and report what changed afterward. When `false`, show the proposed updates and require confirmation before applying.
   - The "purely internal — owner must confirm" branch from the previous mandatory flow is removed: by entering this block at all, the task has already opted into spec review via one of the three conditions above.

9. **Drift check** — run `/ddw:drift` logic. If the status is **DRIFTED** after the spec update, warn the user and list remaining contradictions. The user decides whether to fix now or defer.

10. **CLAUDE.md status line** — skip. Hooks read task files directly; the CLAUDE.md status line is no longer used.

11. **DECISION_LOG + decision files** — if the task has a linked decision:
    - Update the decision file status to `decided` (if not already).
    - Skip direct DECISION_LOG row update — `ddw-index` derives the log from DEC source files.

12. **Retrospective** — check skip conditions first. Skip the prompt entirely when ALL three are true:
    - **Clean QA:** No `## Review Log` entries with `status: confirmed`. (Pending or not-a-bug entries don't count.)
    - **Short task:** Duration from first "Status → in_progress" Work Log entry to the current "Status → done" entry is < 2 hours.
    - **Single session:** Only one "Status → in_progress" entry in Work Log (no resume entries).

    When ALL three conditions are true: silently fill the `## Retrospective` section with:
       ```
       **Feedback:** Clean run. No issues. (auto-skipped — clean QA, <2hr, single session)
       **Action:** None.
       ```
    Then proceed to step 12.5.

    When ANY condition fails: ask the user:
    "Anything surprising, difficult, or wrong in this task?"

    If the user provides feedback:
    a. Fill the `## Retrospective` section in the task file:
       ```
       **Feedback:** {user's feedback}
       **Action:** {what changes, if any — e.g., "Added INV-B-20260326-x", "Updated GUARDRAILS.md rule Y"}
       ```
    b. If the feedback implies a new invariant → propose it (owner approves)
    c. If the feedback implies a guardrail change → update GUARDRAILS.md
    d. If the feedback implies a workflow improvement → note it for WORKFLOW.md

    If the user says "nothing" or skips → fill the section:
       ```
       **Feedback:** Clean run. No issues.
       **Action:** None.
       ```

    After filling the section (whether auto-skipped or prompted): the retrospective body in the task file is the source of truth. `ddw-index` derives `RETRO_LOG.md` — no inline sync needed.

12.5. **Verify proposed constraints** — check that constraints from the linked decision weren't lost:
   - Read the task's `**Decision:**` field. If it references a decision, read that decision file.
   - Find the `## Architect Review → Proposed Constraints` section.
   - Check each proposed constraint for its disposition:
     - If marked **added** → verify it actually exists in GUARDRAILS.md or INVARIANTS.md. If missing (e.g., lost in a session break), write it now and report.
     - If marked **rejected** → skip, already resolved.
     - If unmarked (no disposition) → surface to the owner: "This constraint was proposed in {DEC-id} but never resolved: {constraint}. Add, reject, or defer?" Update the decision file with the owner's choice.
   - If no decision is linked, or no constraints were proposed, skip this step.

13. **Archive** — move the completed task file:
    a. Move `{workflowDir}/tasks/TASK-{date}-{title}.md` to `{workflowDir}/tasks/archive/`
    b. Check if the linked decision has any remaining non-archived tasks:
       - Scan `{workflowDir}/tasks/TASK-*.md` (non-archive) for files where `**Decision:**` matches this task's decision
       - If none remain: move the decision file to `{workflowDir}/decisions/archive/`
       - **Do NOT auto-move PRDs.** PRD closure is the owner's call via `/ddw:prd close` (§13 authority matrix). If the just-archived decision references a PRD that is not yet closed, REMIND the owner: "DEC-{id} archived. PRD-{id} is still active — run `/ddw:prd close PRD-{id}` if all relevant decisions exist."
    c. Logs are derived views — `ddw-index` regenerates them on demand. Skip inline sync.
    d. **Queue tick** — after archival:
       - If the closing task's status was `ready_for_integration` (queued but not yet staged) or `testing-complete` (came through staging): check `.ddw/integration.json`. If `testing` matches this task's ID, clear it by writing `{"testing": null}` to `.ddw/integration.json`. (This handles `/ddw:close` running on the currently-testing task.)
       - Invoke `bash ${CLAUDE_PLUGIN_DIR}/scripts/ddw-queue tick --root ${workflowRoot}`. The tick advances the queue: if the integration worktree is now idle and another task is ready, the next head will be staged.
       - Print the result: "Queue advanced. Next staged: TASK-Y." or "Queue empty." (the ddw-queue tick output will indicate which).

13.5. **Milestone phase completion** — check if archiving this decision completed a milestone:
   - Only run this step if a decision was archived in step 13b.
   - Read `{workflowDir}/MILESTONES.md`.
   - Find the `##` section that lists the just-archived decision ID (e.g., `DEC-20260406-auth-redesign`).
   - If the section heading already has `✅`, skip (already marked complete).
   - If found, collect every decision ID listed in that section (lines starting with `- DEC-`).
   - For each decision ID, check if it exists in `{workflowDir}/decisions/archive/`. A decision is "phase-done" only if its file is in the archive directory.
   - If **ALL** decisions in the section are archived → append `✅` to the section heading (e.g., `## Phase 1 — MVP` becomes `## Phase 1 — MVP ✅`).
   - Report: "Milestone '{name}' is now complete — all decisions archived."
   - If some decisions are NOT archived → report progress: "Milestone '{name}': {done}/{total} decisions complete."

14. **Merge guidance** (git only — skip if not a git repo):
    Remind the user: "Task archived. To merge your work: create a PR or `git checkout main && git merge {branch}`."

15. **Report** a checklist confirming each item was completed or explicitly skipped with reason:
    - [ ] Task file status + Work Log
    - [ ] Changes section filled
    - [ ] CURRENT_SPEC (updated / skipped — reason)
    - [ ] Drift check (SYNCED / DRIFTED — details)
    - [ ] DECISION_LOG + decision file (updated / N/A)
    - [ ] Retrospective (logged / skipped)
    - [ ] Proposed constraints (all resolved / N/A)
    - [ ] Archived (task / task + decision)
    - [ ] Logs synced

**Final note:** logs (`TASK_LOG.md`, `DECISION_LOG.md`, `RETRO_LOG.md`, `PRD_LOG.md`) are derived views. Run `node ${CLAUDE_PLUGIN_DIR}/scripts/ddw-index.mjs` to refresh, or rely on a pre-commit hook if configured.
