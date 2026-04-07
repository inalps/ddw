---
name: qa
description: Run automated QA against acceptance criteria + invariants. Produces a structured report with PASS/FAIL/SKIP per check.
disable-model-invocation: false
---

**Invocation gate:** Only run this skill when (1) the user explicitly typed the `/ddw:qa` command, (2) a hook enforcement message demands it, or (3) you proposed running this skill and the user clearly confirmed. Never auto-invoke from ambiguous context.

Run automated QA for a task. Task: $ARGUMENTS (if not provided, ask the user which task).

0. **Read voice** — read `{workflowDir}/VOICE.md` (if it exists) and follow its communication style for all output during this skill.

1. **Read config** — read `{workflowDir}/ddw.json` (search `workflows/ddw.json`, `.workflows/ddw.json`, then `.claude/ddw.json` for legacy) to get `workflowDir` and `specPath`.

2. **Load QA profile** — read the `agents/qa.md` bundled with the DDW plugin (plugin root, not project directory). Adopt its mindset for the duration of this skill. Key principles:
   - Adversarial: assume bugs exist until proven otherwise
   - Independent: do NOT read Context Packing or Implementation Summary
   - Evidence-based: every result needs specific evidence (file, line, value)
   - Severity honesty: BLOCKER / WARNING / INFO — don't inflate or deflate

3. **Read the task file** at `{workflowDir}/tasks/TASK-{id}.md`. Extract:
   - `## Acceptance Criteria` table (task-specific checks)
   - `## Goal` and `## Scope` (for context only — don't let developer framing bias evaluation)
   - Do NOT read `## Context Packing` or `## Implementation Summary`

4. **Read project invariants** at `{workflowDir}/guardrails/INVARIANTS.md`.

5. **Read the codebase** — read the main code file(s) relevant to the task.

6. **Read the spec** — read the file at `specPath` from ddw.json (if configured).

7. **Pass 1: Acceptance Criteria** — execute each check in the AC table:

   For each row:
   - **code-grep**: Grep/read the code for the expected pattern or value.
     - PASS: pattern found, value matches expected.
     - FAIL: pattern not found, or value differs.
   - **code-review**: Read the relevant function/section, reason about the structural property.
     - PASS: the property holds, with evidence (function name, line, logic).
     - FAIL: the property does not hold, with evidence of what's wrong.
   - **spec-compare**: Compare a value/behavior in code against what the spec says.
     - PASS: code matches spec.
     - FAIL: code and spec disagree (state both values).
   - **manual**: Cannot automate.
     - SKIP: flag for human verification.

   Record: `| AC-{id} | PASS/FAIL/SKIP | {specific evidence} |`

8. **Pass 2: Invariant Regression Sweep** — execute every INV-* check in INVARIANTS.md:

   Same check types as above. Any failure here is a REGRESSION — something that used to work is now broken.

   Record: `| INV-{id} | PASS/REGRESSION | {specific evidence} |`

9. **Generate QA Report** — output the full report:

   ```
   ## QA Report — {task ID}
   Date: {UTC datetime from `date -u`}

   ### Acceptance Criteria
   | ID | Result | Evidence |
   |----|--------|----------|
   | AC-01 | PASS/FAIL/SKIP | {specific evidence} |
   ...

   ### Invariant Sweep
   | ID | Result | Evidence |
   |----|--------|----------|
   | INV-S-20260319-single-file | PASS/REGRESSION | {specific evidence} |
   ...

   ### Summary
   AC: {pass}/{total} pass, {fail} fail, {skip} manual
   INV: {pass}/{total} pass, {regression} regression
   Verdict: CLEAR / BLOCKED
   ```

10. **If BLOCKED**: list all failures with:
    - What's wrong (specific)
    - Where it is (file + line)
    - What it should be (reference to AC/invariant)
    - Suggested fix (but do NOT auto-fix)

11. **If CLEAR**: list any remaining manual checks (SKIP items) for the owner to verify.

12. **Append summary** to the task's `## Review Log` section:
    ```
    #### QA Run — {UTC datetime}
    Verdict: CLEAR/BLOCKED
    AC: {pass}/{total} pass, {fail} fail, {skip} manual
    INV: {pass}/{total} pass, {regression} regression
    {If BLOCKED: list of failures}
    ```
