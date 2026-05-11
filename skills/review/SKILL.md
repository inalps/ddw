---
name: review
description: Review a task's completion criteria, run tests, walk through the owner checklist, and batch-tick results.
disable-model-invocation: false
---

**Invocation gate:** Only run this skill when (1) the user explicitly typed the `/ddw:review` command, (2) a hook enforcement message demands it, or (3) you proposed running this skill and the user clearly confirmed. Never auto-invoke from ambiguous context.

Run a combined review and owner checklist for a task. Task: $ARGUMENTS (if not provided, ask the user which task).

This skill merges pre-done verification with the owner checklist walkthrough.

1. **Read config** — read `{workflowDir}/ddw.json` (search `workflows/ddw.json`, `.workflows/ddw.json`, then `.claude/ddw.json` for legacy) to get `workflowDir`, `commands.test`, and `specPath`.

1.3. **Detect auto mode** — check if `{workflowDir}/.ddw/AUTO_RUN_ACTIVE` exists. If yes, set `auto_mode = true`. In auto mode the owner checklist walkthrough (steps 7–9) is skipped — `/ddw:auto` Row 2 handles checklist advancement and the `done` transition. ALL CLEAR in auto mode = QA CLEAR + tests pass.

1.5. **Logs are derived views.** Do not sync inline — `ddw-index` is the canonical generator. The owner runs `node ${CLAUDE_PLUGIN_DIR}/scripts/ddw-index.mjs` (or via pre-commit hook) to refresh.

2. **Read the task file** at `{workflowDir}/tasks/TASK-{date}-{title}.md`.

3. **Run QA checks via isolated subagent** — spawn QA as a separate agent with scoped context. This ensures QA cannot see the developer's Context Packing, Implementation Summary, or Work Log.

   **3a. Gather scoped context** — read the following documents and hold them for prompt construction:

   1. **QA profile** — read `agents/qa.md` from the DDW plugin root.
   2. **Task excerpts** — from the task file read in step 2, extract ONLY:
      - `## Goal`
      - `## Scope`
      - `## Acceptance Criteria` (the full table)
      - `## Files` (so QA knows which source files to inspect)
      Do NOT include: `## Context Packing`, `## Implementation Summary`, `## Work Log`, `## Session Handoff`, `## Owner Review Checklist`.
   3. **Linked decision file** — read the task's `**Decision:**` field. If it references a decision (e.g., `DEC-20260401-feature-x`), read that file at `{workflowDir}/decisions/{decision-id}.md`. This is the **spec delta** — it describes intended new behavior.
   4. **CURRENT_SPEC.md (tiered)** — if `specPath` is configured: scan headings/section structure first, then read only sections relevant to the task's scope and AC table. Embed only those sections — skip unrelated domain areas.
   5. **INVARIANTS.md** — read `{workflowDir}/guardrails/INVARIANTS.md` fully (compact, every one must be checked).
   6. **GUARDRAILS.md (tiered)** — if `{workflowDir}/guardrails/GUARDRAILS.md` exists: scan headings and rule names first, then read only sections relevant to the task's scope. Embed only those sections.

   **3b. Construct the subagent prompt** — assemble the prompt below. Embed the actual document contents (not file paths) so the subagent has no access to excluded sections:

   ```
   You are the QA agent. Your profile and mindset:

   <qa-profile>
   {contents of agents/qa.md}
   </qa-profile>

   Your job: run a full QA pass on the task below. Produce a QA Report with verdict CLEAR or BLOCKED.

   ## Spec Hierarchy
   CURRENT_SPEC.md is the baseline behavior contract. The linked decision is the spec delta — where they conflict, the decision wins because it describes the intended new behavior.

   <current-spec>
   {contents of CURRENT_SPEC.md, or "No spec configured." if specPath is absent}
   </current-spec>

   <decision>
   {contents of linked decision file, or "No linked decision." if Decision field is "none"}
   </decision>

   ## Task Under Review

   <task>
   {extracted Goal, Scope, Acceptance Criteria table, and Files sections}
   </task>

   ## Project Invariants

   <invariants>
   {contents of INVARIANTS.md}
   </invariants>

   ## Project Guardrails

   <guardrails>
   {contents of GUARDRAILS.md, or "No guardrails configured." if file doesn't exist}
   </guardrails>

   ## Instructions

   You have access to Read, Grep, Glob, and Bash (read-only) tools. Use them to inspect the actual source code.

   1. **Pass 1 — Acceptance Criteria**: For each row in the AC table, run the appropriate check type (code-grep, code-review, spec-compare, or manual). Record result as PASS/FAIL/SKIP with specific evidence (file, line, value).

   2. **Pass 2 — Invariant Regression Sweep**: For every INV-* in the invariants document, run the check. Record result as PASS/REGRESSION with specific evidence.

   3. **Output the QA Report** in this exact format:

      ## QA Report — {task ID}
      Date: {run `date -u` to get current UTC datetime}

      ### Acceptance Criteria
      | ID | Result | Evidence |
      |----|--------|----------|
      | AC-01 | PASS/FAIL/SKIP | {specific evidence} |

      ### Invariant Sweep
      | ID | Result | Evidence |
      |----|--------|----------|
      | INV-... | PASS/REGRESSION | {specific evidence} |

      ### Summary
      AC: {pass}/{total} pass, {fail} fail, {skip} manual
      INV: {pass}/{total} pass, {regression} regression
      Verdict: CLEAR / BLOCKED

   4. If BLOCKED: list all failures with what's wrong, where (file + line), what it should be, and suggested fix (do NOT auto-fix).

   5. If CLEAR: list any SKIP items for manual verification.

   Output ONLY the QA Report. No preamble, no commentary outside the report.
   ```

   **3c. Spawn the QA subagent** — invoke the Agent tool with the prompt from 3b, using `model: "sonnet"` (from `agents/qa.md`). Wait for the result.

   **3d. Process the QA result** — parse the returned QA Report:
   - Extract the `Verdict:` line.
   - If verdict is **BLOCKED**, display the full QA Report to the user and stop the review. Do not proceed to the owner checklist until all BLOCKED items are resolved.
   - If verdict is **CLEAR**, display a brief summary (AC pass/total, INV pass/total, verdict) and continue to step 4.
   - If the subagent output doesn't match the expected format, treat as BLOCKED and display the full output for the user.

   **3e. Append QA summary to Review Log** — append to the task's `## Review Log`:
   ```
   #### QA Run — {UTC datetime}
   Verdict: CLEAR/BLOCKED
   AC: {pass}/{total} pass, {fail} fail, {skip} manual
   INV: {pass}/{total} pass, {regression} regression
   {If BLOCKED: list of failures}
   ```

4. **Review Log** — check `## Review Log`. If any entries have `Status: pending`, flag them. All pending entries must be resolved before done.

5. **Verify tests were written** — check the task file's `## Tests` section:
   - If the section is empty or contains only the template placeholder, **BLOCK** the review: "No tests documented. Every implementation must include unit and integration tests. Write tests and fill the ## Tests section before re-running review."
   - If populated, confirm the listed test files exist in the codebase.

6. **Run tests** — if `commands.test` is configured (not null):
   - Run the test command.
   - Report pass/fail and test count.
   - If failing: list the failing tests and stop — do not proceed.

7. **Owner Review Checklist** — locate the `## Owner Review Checklist` section and parse all unchecked items.

   **Auto mode** (`auto_mode = true`): attempt to verify every item without human input:
   - For each item, read its text and classify:
     - **Test count** (e.g. "N tests pass") → run `commands.test`, check output matches.
     - **Code spot-check** (e.g. "Open File → confirm X") → read the file, check the condition.
     - **Grep/pattern** (e.g. "confirm function Y exists") → grep the codebase.
     - **Behavior/UI/browser** (e.g. "open the app and verify") → cannot automate; mark SKIP.
   - Tick `[x]` for every item that passes verification. Leave `[ ]` for SKIP items.
   - Write all ticks in one single edit.
   - If any item FAILS verification (not just SKIP) → treat as INCOMPLETE, log failure, stop.
   - Proceed to step 10.

   **Human mode**: present all unchecked items at once in a single response:
   - Number each item (1, 2, 3 ...).
   - Show item text in bold.
   - For automated items: show result inline (✅ auto-passed or ❌ auto-failed).
   - For manual items: give concrete specific advice — what to open, what to check, what to expect.
   - End with: "Reply with the numbers of items that **passed** (e.g. `1 3 4`), or `all` / `none`. Type `skip N` to skip an item without failing it."

8. **Wait for one reply from the user.** (human mode only — skipped in auto mode)

9. **Process the reply:** (human mode only — skipped in auto mode)
   - Auto-passed items are ticked regardless.
   - Items the user listed as passed → tick `[x]`.
   - Items listed as `skip N` → leave `[ ]`.
   - Items not mentioned and not auto-passed → leave `[ ]`.
   - Write all ticks in **one single edit**.

10. **Summary** — output a table: each item with status ✅ passed / ❌ failed / ⏭ skipped / ⬜ not reached.
    - Overall verdict: ALL CLEAR or INCOMPLETE (with blockers).
    - In auto mode: ALL CLEAR if QA CLEAR + tests pass + no checklist item FAILED (SKIP items are allowed).

11. **If ALL CLEAR**:
    - Set task status to `review_and_bugfix` in the task file.
    - Append a review entry to `## Review Log`:
      ```
      #### Review — {actual UTC datetime}
      Verdict: ALL CLEAR
      QA: {pass}/{total} AC pass, {invariant pass}/{invariant total} INV pass
      Tests: {pass count} pass, {fail count} fail
      Checklist: {checked}/{total} items verified ({skip} skipped — needs human)
      ```
    - Append a Work Log entry:
      ```
      ### {actual UTC datetime}
      Status → review_and_bugfix. {test results}. {N checklist items auto-verified, M need human review}.
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
