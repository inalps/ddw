---
name: qa
description: Run automated QA against acceptance criteria + invariants. Produces a structured report with PASS/FAIL/SKIP per check.
disable-model-invocation: false
---

**Invocation gate:** Only run this skill when (1) the user explicitly typed the `/ddw:qa` command, (2) a hook enforcement message demands it, or (3) you proposed running this skill and the user clearly confirmed. Never auto-invoke from ambiguous context.

Run automated QA for a task. Task: $ARGUMENTS (if not provided, ask the user which task).

## Invocation Modes

This skill runs in two modes:

**Standalone mode** (user runs `/ddw:qa` directly):
- Gathers all context itself (steps 0-6).
- Appends QA summary to the task's Review Log (step 12).

**Subagent mode** (spawned by `/ddw:review` via the Agent tool):
- All context (QA profile, task excerpts, spec, decision, invariants, guardrails) is already embedded in the prompt via XML tags.
- Skip steps 0-6. Begin directly at step 7 (Pass 1: Acceptance Criteria).
- Do NOT append to the Review Log (step 12) — the calling review skill handles that.
- Output ONLY the QA Report (steps 9-11).

**How to detect mode:** If the prompt contains `<qa-profile>` and `<task>` XML tags with embedded content, you are in subagent mode. Otherwise, you are in standalone mode.

---

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
   - Extract the `**Decision:**` field from the task header — needed for spec delta in step 5.5.

4. **Read project invariants** — read `{workflowDir}/guardrails/INVARIANTS.md` fully. These are compact, machine-testable rules and every one must be checked in Pass 2.

4.5. **Read guardrails (tiered)** — read `{workflowDir}/guardrails/GUARDRAILS.md` (if it exists): scan headings and rule names first, then read only sections relevant to the task's scope and AC checks.

5. **Read the codebase** — read the main code file(s) relevant to the task.

5.5. **Read the linked decision** — read the task's `**Decision:**` field. If it references a decision (not "none"), read `{workflowDir}/decisions/{decision-id}.md`. This is the **spec delta** — it describes intended new behavior that may override CURRENT_SPEC.md.

6. **Read the spec (tiered)** — if `specPath` is configured in ddw.json: this is the **baseline** behavior contract (CURRENT_SPEC.md). Where the linked decision (step 5.5) conflicts with the spec, the decision wins — that's the intended new behavior.
   - Read headings/section structure first.
   - Read only sections referenced by AC checks (spec-compare type) or relevant to the task's scope.
   - Skip unrelated domain areas.

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

12. **Append summary** (standalone mode only — skip in subagent mode) to the task's `## Review Log` section:
    ```
    #### QA Run — {UTC datetime}
    Verdict: CLEAR/BLOCKED
    AC: {pass}/{total} pass, {fail} fail, {skip} manual
    INV: {pass}/{total} pass, {regression} regression
    {If BLOCKED: list of failures}
    ```
