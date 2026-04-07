---
name: review
description: Review a task's completion criteria, run tests, walk through the owner checklist, and batch-tick results.
disable-model-invocation: false
---

**Invocation gate:** Only run this skill when (1) the user explicitly typed the `/ddw:review` command, (2) a hook enforcement message demands it, or (3) you proposed running this skill and the user clearly confirmed. Never auto-invoke from ambiguous context.

Run a combined review and owner checklist for a task. Task: $ARGUMENTS (if not provided, ask the user which task).

This skill merges pre-done verification with the owner checklist walkthrough.

1. **Read config** — read `{workflowDir}/ddw.json` (search `workflows/ddw.json`, `.workflows/ddw.json`, then `.claude/ddw.json` for legacy) to get `workflowDir`, `testCommand`, and `specPath`.

1.5. **Sync TASK_LOG** — Sync `{workflowDir}/logs/TASK_LOG.md` from all `TASK-*.md` files in both `{workflowDir}/tasks/` and `tasks/archive/`. Extract Owner, Status, Date, last Work Log timestamp. Add missing rows and update existing rows. **Never delete rows** — logs are a permanent record.

2. **Read the task file** at `{workflowDir}/tasks/TASK-{date}-{title}.md`.

3. **Run QA checks** — execute `/ddw:qa` logic against this task:
   - Run all Acceptance Criteria checks (AC table)
   - Run the Invariant Regression Sweep
   - If verdict is **BLOCKED**, stop the review and report failures. Do not proceed to the owner checklist until all BLOCKED items are resolved.
   - If verdict is **CLEAR**, continue to the next step.

4. **Review Log** — check `## Review Log`. If any entries have `Status: pending`, flag them. All pending entries must be resolved before done.

5. **Verify tests were written** — check the task file's `## Tests` section:
   - If the section is empty or contains only the template placeholder, **BLOCK** the review: "No tests documented. Every implementation must include unit and integration tests. Write tests and fill the ## Tests section before re-running review."
   - If populated, confirm the listed test files exist in the codebase.

6. **Run tests** — if `testCommand` is configured (not "none"):
   - Run the test command.
   - Report pass/fail and test count.
   - If failing: list the failing tests and stop — do not proceed.

7. **Owner Review Checklist** — locate the `## Owner Review Checklist` section:
   - Parse all unchecked items.
   - **Pre-check automated items silently**: run tests, read code for spot-checks, note results.
   - **Present ALL unchecked items at once** in a single response:
     - Number each item (1, 2, 3 ...).
     - Show item text in bold.
     - For automated items: show result inline (✅ auto-passed or ❌ auto-failed).
     - For manual items: give concrete specific advice — what to open, what to check, what to expect.
     - End with: "Reply with the numbers of items that **passed** (e.g. `1 3 4`), or `all` / `none`. Type `skip N` to skip an item without failing it."

8. **Wait for one reply from the user.**

9. **Process the reply:**
   - Auto-passed items are ticked regardless.
   - Items the user listed as passed → tick `[x]`.
   - Items listed as `skip N` → leave `[ ]`.
   - Items not mentioned and not auto-passed → leave `[ ]`.
   - Write all ticks in **one single edit**.

10. **Summary** — output a table: each item with status ✅ passed / ❌ failed / ⏭ skipped / ⬜ not reached.
    - Overall verdict: ALL CLEAR or INCOMPLETE (with blockers).

11. **If ALL CLEAR**:
    - Set task status to `review_and_bugfix` in the task file.
    - Append a review entry to `## Review Log`:
      ```
      #### Review — {actual UTC datetime}
      Verdict: ALL CLEAR
      QA: {pass}/{total} AC pass, {invariant pass}/{invariant total} INV pass
      Tests: {pass count} pass, {fail count} fail
      Checklist: {checked}/{total} items passed
      ```
    - Append a Work Log entry:
      ```
      ### {actual UTC datetime}
      Status → review_and_bugfix. {test results if applicable}. Manual verification pending.
      ```

12. **If INCOMPLETE**: list what blocks and what needs to be fixed before re-running review.

13. **Manual Verification Checklist** — ALWAYS output this section at the end, regardless of ALL CLEAR or INCOMPLETE verdict. Collect every item that requires the user's eyes or hands:
    - All QA checks with result `SKIP` (manual type)
    - Any Owner Review Checklist items that were not auto-verified
    - Any test failures the user should inspect

    Present as a numbered checklist with a brief procedure for each:

    ```
    ## What You Need to Verify

    1. **{item description}**
       How: {what to open/run, what to look for, what the expected result is}

    2. **{item description}**
       How: {brief procedure}

    ...
    ```

    - Keep each "How" to 1-2 lines — actionable, not verbose.
    - If there are zero manual items, output: "No manual verification needed — all checks were automated."
    - End with: "Once verified, set the task to `done` and run `/ddw:close`."
