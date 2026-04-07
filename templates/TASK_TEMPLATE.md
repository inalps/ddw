# Task Template

Copy this file and rename to `TASK-{yyyymmdd}-{title}.md` when creating a new task.

---

**Status:** planned
**Decision:** DEC-{yyyymmdd}-{title}
**Owner:** {userName}
**Date:** {actual UTC datetime}
**Priority:** P1 | P2 | P3
**Depends-On:** none

---

## Goal
What must be implemented.

## Scope
What is included in this task.

## Non-Goals
What must NOT be implemented in this task.

## Constraints
Relevant rules from guardrails or project conventions.

## Files
Expected files or systems affected.

## Verification
1. Step 1
2. Step 2
3. Step 3

## Completion Criteria
- [ ] Criterion 1
- [ ] Criterion 2
- [ ] All verification steps pass

## Acceptance Criteria
<!-- Machine-testable. Each row scored by /ddw:qa. -->

| ID | Criterion | Check | Expected |
|----|-----------|-------|----------|
| AC-01 | {what must be true} | code-grep | {pattern or value} |
| AC-02 | {what must be true} | code-review | {function + property} |
| AC-03 | {what must be true} | manual | {human instruction} |

## Context Packing
// Fill before writing any implementation code.
// - What I know: brief summary of relevant current state
// - Ambiguities: unclear requirements or missing info
// - Risk areas: what could break, which rules are at risk
// - Interpretation: any assumption made — state it for Owner to confirm

## Session Handoff
<!-- Fill when ending a session mid-task. Clear when resuming. -->

<!-- ### {UTC datetime} — Session paused -->
<!-- - **Completed:** what's been done so far -->
<!-- - **Next:** what to do next (specific, actionable) -->
<!-- - **Blocked:** any blockers or decisions needed from owner -->
<!-- - **Key context:** non-obvious state the next session needs to know -->
<!--   (e.g., "tried approach X, failed because Y — don't retry") -->

## Tests
// Fill when tests are written during implementation.
// List every test file created or modified and what it covers.
//
// | File | Type | What it covers |
// |---|---|---|
// | `path/to/test_file` | unit | What function/logic is tested |
// | `path/to/test_file` | integration | What feature/flow is tested |
//
// **Test count:** {N} unit, {N} integration
// **All passing:** yes / no

## Implementation Summary
// Fill when status → review_and_bugfix.
// List every file changed and what changed in it.
//
// | File | Change |
// |---|---|
// | `path/to/File` | What changed |
//
// **Key decision:** ...

## Changes
<!-- Fill during /ddw:close. Used to rebuild CHANGE_LOG.md. -->
<!-- **Summary:** 2-4 sentences: what changed, files affected, test count if applicable -->

## Owner Review Checklist
// Fill when status → review_and_bugfix.
// Tell the Owner exactly what to do to verify the task.
//
// **Manual verification:**
// - [ ] Action 1 — what to do and what to expect
// - [ ] Action 2
//
// **Automated tests:**
// - [ ] N tests pass, 0 failures
//
// **Spot-check in code:**
// - [ ] Open File → confirm X

## Review Log
// Whenever the Owner reports something wrong — even mid-task — add a PENDING entry immediately.
//
// #### Bug #N
// - **Found at**: UTC datetime
// - **Found by**: Owner or Claude
// - **Status**: pending | confirmed | not-a-bug
// - **Description**: what was reported
// - **Investigation**: what was checked
// - **Fix**: what was changed (omit if not-a-bug)
// - **Fixed by**: Owner or Claude
// - **Fixed at**: UTC datetime

## Retrospective
<!-- Fill during /ddw:close. Used to rebuild RETRO_LOG.md. -->
<!-- **Feedback:** owner's feedback, or "Clean run. No issues." -->
<!-- **Action:** what changes, if any — e.g., new invariant, guardrail update -->

## Work Log
// Append a timestamped entry whenever status changes or key decisions are made.
//
// ### {UTC datetime}
// Status → in_progress. Brief note.
