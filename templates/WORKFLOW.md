# Decision-Driven Workflow (DDW)

This document defines the end-to-end development cycle for this project.
No implementation without a TASK. No TASK without a DECISION.

---

## Full Cycle

```
User request / feature idea
    ↓ (optional)
PRD via /ddw:ideate (shape the idea, produce structured requirements)
    ↓
Architect review (system design, constraints, task breakdown — part of /ddw:decision)
    ↓
Discussion on the design (Owner adjusts, agrees)
    ↓
Decision file in {workflowDir}/decisions/ (DEC-{yyyymmdd}-{title}.md)
    ↓ [Must have status: decided + milestone assignment]
TASK file in {workflowDir}/tasks/ (TASK-{yyyymmdd}-{title}.md)
    ↓ [Must have status: planned]
Implementation (set status → in_progress)
    ↓
review_and_bugfix (fill Implementation Summary + Owner Review Checklist)
    ↓
Owner verification (Owner runs checklist items)
    ↓
done (Owner sets status → done)
    ↓
Post-done updates (run /ddw:close — mandatory)
```

---

## Step-by-Step Rules

### Step 0 — Ideation (optional)
If the feature is not well-defined, run `/ddw:ideate` to produce a PRD.
- PRD files live in `{workflowDir}/prds/`
- File name format: `PRD-{yyyymmdd}-{slug}.md`
- The shaper agent guides you through structured thinking: problem, users, solution, scope, success criteria
- Anyone can create a PRD — no technical knowledge required
- When done, the PRD can be referenced by `/ddw:decision`
- **Skip this step** if you already have clear requirements, existing docs, or can explain your idea directly

**PRD-as-bible principle:** Once created, the PRD's core sections are never modified by downstream processes. All commentary from later phases (architect review, decisions) goes into the PRD's `## Feedback Log` — an append-only section that preserves the original vision while tracking how thinking evolves around it.

### Step 1 — Discussion
Talk through the feature or change. No implementation yet.

### Step 2 — Decision file
Every feature starts as a decision file in `{workflowDir}/decisions/`.
- File name format: `DEC-{yyyymmdd}-{slug}.md`
- One decision can produce multiple tasks (1:N).
- Add to the index in `{workflowDir}/logs/DECISION_LOG.md`.
- Milestone assignment is **optional** at `proposed`, **required** before `decided`.
- A decision may not be set to `decided` until the Owner has confirmed its milestone.
- When status changes, update **both** the decision file **and** the index row.

### Step 3 — TASK file
Break the decision into small tasks using `{workflowDir}/tasks/TASK_TEMPLATE.md`.
- File name format: `TASK-{yyyymmdd}-{slug}.md`
- Tasks must be: small, safe, independently verifiable.

### Step 4 — Implementation
Before implementing:
1. Read the TASK file
2. Read guardrails (if any exist in `{workflowDir}/guardrails/`)
3. Set task status to `in_progress` + Work Log entry
4. `/ddw:sendit` creates a `task/{task-id}` feature branch (git only)
5. Implement only what is in Scope. Non-Goals are off-limits.
6. Write **unit tests** for new/changed functions and **integration tests** for feature-level behavior
7. Run all tests and confirm they pass before moving to QA

**Testing is mandatory.** Every implementation must include corresponding test code (unit and integration). Tests serve as the regression safety net for future tasks. A task is not implementation-complete until its tests exist and pass.

### Step 5 — Automated QA Gate
Before requesting review, run `/ddw:qa` (or its logic runs automatically via `/ddw:review`):
1. Scores each Acceptance Criterion → PASS / FAIL / SKIP
2. Runs Invariant Regression Sweep (all INV-* rules) → PASS / REGRESSION
3. Produces a QA Report with verdict: CLEAR or BLOCKED

If **BLOCKED**: fix failures, re-run. Do not enter `review_and_bugfix` until QA is CLEAR.

### Step 6 — Review and Bug Fix
When QA is CLEAR, set status to `review_and_bugfix` and:
1. Fill in `## Implementation Summary`
2. Fill in `## Owner Review Checklist`
3. Append Work Log entry

**Review Log rule:** Any issue reported by the Owner → immediate `pending` entry in Review Log, then investigate. All pending entries must be resolved before `done`.

### Step 7 — Owner Verification
Owner verifies Completion Criteria and checklist. Owner sets status to `done`.

### Step 8 — Post-Task Updates (mandatory)
After Owner sets `done`, run `/ddw:close`. All updates must complete:
- Task file status + Work Log
- Task file `## Changes` section (used to rebuild CHANGE_LOG)
- CURRENT_SPEC (if configured and behavior changed)
- Drift check (`/ddw:drift`) — if DRIFTED after spec update, warn and fix
- Decision file status update
- Retrospective — ask Owner: "Anything surprising, difficult, or wrong?" → fill task file `## Retrospective` section
- Archive task file to `tasks/archive/` (and decision if all tasks complete)
- Self-healing sync rebuilds all four log files from source files

### Step 9 — Bug Found After Done
A task marked `done` is never reopened.
- Small bug → new TASK only
- Design-level bug → new DECISION first, then TASK

---

## Task Status Values

| Status | Set by | Meaning |
|---|---|---|
| `planned` | Owner / Claude | Task defined, not started |
| `in_progress` | Claude | Implementation started |
| `review_and_bugfix` | Claude | Implementation complete, under review |
| `done` | Owner | Verification passed |
| `cancelled` | Owner | Task dropped |

---

## Datetime Convention

All dates and times use **UTC ISO 8601**: `2026-03-16T14:30:00Z`

**Always use the actual current UTC datetime** when recording new entries.
Run `date -u +"%Y-%m-%dT%H:%M:%SZ"` and use the exact output.
Never use `T00:00:00Z` as a placeholder for new entries.

File names use date-only (`20260316`).

---

## Milestone Rules

- Milestone membership lives **only** in `{workflowDir}/MILESTONES.md`
- Milestone identity is a **name**, never a number
- `MILESTONES.md` order is the single source of truth for planning priority
- Milestone assignment is a blocking gate before `decided`
- When a decision is cancelled: remove from MILESTONES.md; if section empty, delete section
- When all decisions in a milestone are archived, `/ddw:close` marks the heading with ✅
- Creating a decision in a completed (✅) milestone reopens it (removes the marker)
- Creating a task for a decision in a completed milestone triggers a warning — user must confirm

---

## Automated QA (`/ddw:qa`)

Runs two passes against a task:
1. **Acceptance Criteria** — scores each AC row (PASS / FAIL / SKIP)
2. **Invariant Regression Sweep** — checks all INV-* rules in `{workflowDir}/guardrails/INVARIANTS.md`

Produces a QA Report appended to the task's Review Log. Verdict: **CLEAR** (proceed) or **BLOCKED** (fix first).

Check types: `code-grep`, `code-review`, `spec-compare`, `manual` (SKIP — flagged for human).

## Drift Detection (`/ddw:drift`)

Compares `docs/CURRENT_SPEC.md` against the codebase section-by-section:
- **Contradictions** — spec says X, code says Y
- **Spec Gaps** — code has it, spec doesn't mention it
- **Code Gaps** — spec describes it, code doesn't implement it

Verdict: **SYNCED** or **DRIFTED**. Runs automatically during `/ddw:close`.

## Architectural Review (`/ddw:arch`)

System design review that runs as part of `/ddw:decision` or standalone:

- **Design Review** (default) — analyzes how a feature fits the system, maps dependencies, discovers constraints, proposes task breakdown. Produces an Architect Review with verdict: **SOUND**, **NEEDS-DISCUSSION**, or **RETHINK**.
- **Bootstrap** (`/ddw:arch bootstrap`) — for new projects, scans the codebase and proposes initial guardrails, invariants, and milestone structure.

The architect uses tiered context loading: indexes and compact files first, then drills into specific files based on feature scope. This keeps context usage proportional to the change.

The architect advises but does not block. All proposed changes require owner approval. Discussion during the review is recorded in the DEC file.

## Agent Profiles

Three role-separated profiles in `{workflowDir}/agents/`:

| Profile | Role | Key principle | Timing |
|---|---|---|---|
| `shaper.md` | Thinking partner | Draw out ideas, challenge assumptions, guide anyone to a clear PRD | Before decision (optional) |
| `architect.md` | System designer | System coherence, dependency awareness, constraint discovery | Before implementation |
| `developer.md` | Implementer | Spec-first, minimal blast radius, regression awareness | During implementation |
| `qa.md` | Evaluator | Adversarial, independent, evidence-based | After implementation |

**Information separation:**
- Shaper reads nothing from future phases (no decisions, tasks, or code). It operates purely on user input.
- Architect reads Context Packing (mentoring relationship) but NOT Implementation Summary (reviews happen before implementation). Architect reads referenced PRDs as context.
- QA does NOT read Context Packing or Implementation Summary (adversarial — judges code against spec, not developer explanation).
- Architect reads RETRO_LOG (learns from past issues). QA and Developer do not.

Profiles define **how to think**, not **what to check**. Domain-specific checks come from INVARIANTS.md and GUARDRAILS.md.

## Session Handoff

When a session ends mid-task, fill the task's `## Session Handoff` section:
- **Completed:** what's been done
- **Next:** specific next actions
- **Blocked:** any blockers for the owner
- **Key context:** non-obvious state (e.g., "tried X, failed because Y")

`/ddw:sendit` checks for handoff content on resume and displays a summary before continuing.

## Retrospective

After every `/ddw:close`, ask: "Anything surprising, difficult, or wrong?"

Feedback → `{workflowDir}/logs/RETRO_LOG.md` → may feed back into GUARDRAILS.md, INVARIANTS.md, or skill updates. This is how the workflow gets smarter over time.

## Team Workflow

DDW supports multiple developers working in parallel on the same project.

### Identity

DDW resolves developer identity at runtime via `git config user.name || whoami`. No stored config needed. Every task and decision file has an `Owner:` field.

### Planning on Main

Decision and task creation happens on the `main` branch. This keeps planning artifacts visible to all team members immediately.

- `/ddw:decision` — run on main
- `/ddw:task` — run on main
- Commit the new `DEC-*.md` or `TASK-*.md` to main before starting implementation

### Implementation on Feature Branches

When `/ddw:sendit` activates a task, it creates a feature branch (git only):
- Branch name: `task/{task-id}` (e.g., `task/TASK-20260331-auth-middleware`)
- All implementation work happens on this branch
- Multiple developers can work on different branches simultaneously
- No file collision risk because each branch is isolated

### Closing and Merging

`/ddw:close` runs on the feature branch:
1. Completes all post-done updates (changes, spec, retrospective)
2. Archives the task file (moves to `tasks/archive/`)
3. Archives the decision file if all its tasks are done
4. Reminds the developer to merge or create a PR

After close: merge the feature branch to main (or create a PR for review).

### Self-Healing Logs

The four log files (`TASK_LOG`, `DECISION_LOG`, `CHANGE_LOG`, `RETRO_LOG`) are derived caches. Task and decision files are the source of truth.

Every DDW skill that reads a log first rebuilds it by scanning non-archived task/decision files. This means:
- After a merge, logs self-correct on the next skill invocation
- No manual sync command needed
- No merge conflicts in log files (they are overwritten, not appended)
- Logs only reflect active (non-archived) work

### Archive

Completed tasks are moved to `tasks/archive/`. When all tasks for a decision are archived, the decision moves to `decisions/archive/`.

Archived files:
- Are NOT scanned by self-healing sync (keeps sync fast)
- Are NOT shown in log files (keeps logs focused on active work)
- Are still accessible for reference (look in the `archive/` directory)
- Scale to thousands without impacting performance

### Owner-Aware Hooks

The `require-active-task` hook checks that the **current user** (from `ddw.json`) has an `in_progress` task, not that any task exists globally. This allows multiple developers to work simultaneously.

### Edge Cases

**Task reassignment:** If developer A creates a task but developer B needs to pick it up, developer B runs `/ddw:sendit {task-id}`. The Owner field is updated to developer B's username.

**Merge conflicts in task files:** Rare, because each developer works on different task files. If it happens, resolve manually — task files are small and human-readable.

**Two developers closing tasks at the same time:** Each runs `/ddw:close` on their own branch. When branches merge to main, the next skill invocation rebuilds logs from the merged state.

**Without git:** Everything works except branch isolation. Identity comes from config, sync from file scanning, archive from file moves.

## Session Hygiene

- One task per session. Do not carry unresolved work across task boundaries.
- If context fills past ~60%, use `/compact` before continuing.
