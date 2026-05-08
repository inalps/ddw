---
name: init
description: Bootstrap the Decision-Driven Workflow into a project. Creates directory structure, templates, hooks, and CLAUDE.md instructions.
disable-model-invocation: false
---

**Invocation gate:** Only run this skill when (1) the user explicitly typed the `/ddw:init` command, (2) a hook enforcement message demands it, or (3) you proposed running this skill and the user clearly confirmed. Never auto-invoke from ambiguous context.

Initialize the Decision-Driven Workflow (DDW) for this project. The plugin provides skills, agents, and hook definitions. This skill scaffolds the project-specific files.

---

## Step 1 — Gather Basic Configuration

Use **AskUserQuestion** to collect configuration. Each call must have 1-4 questions, each with 2-4 options, a short `header` (max 12 chars), and `multiSelect: false`. The user can always select "Other" to provide custom input.

**First call** — ask questions 1-3 together:

1. **Project name?** — header: `"Project"`. Auto-detect a suggested name from the directory name, `package.json`, or similar. Options:
   - `"{detected name} (Recommended)"` — auto-detected project name
   - `"Use directory name"` — use the current directory's basename
   - (User selects "Other" to type a custom name)

2. **Workflow directory?** — header: `"Directory"`. Options:
   - `"workflows (Recommended)"` — standard default
   - `".workflows"` — hidden directory
   - (User selects "Other" to provide a custom path)

3. **Current spec?** — header: `"Spec"`. Options:
   - `"Create from codebase"` — analyze existing code and generate `docs/CURRENT_SPEC.md`. If the project is new/empty, create a skeleton instead.
   - `"I have one"` — user selects "Other" to provide the path
   - (User selects "Other" to provide a custom path)

   Regardless of choice, `specPath` is always set (defaults to `docs/CURRENT_SPEC.md`). The spec is mandatory — if the project is new/empty, a skeleton is created from the template (all `> Shaped by: init` placeholders) and `/ddw:close` populates it as tasks complete.

---

## Step 2 — Create Directory Structure

Create the project scaffolding **immediately** so all subsequent steps (including ideation) can write into it.

```
{workflowDir}/
├── prds/
│   └── archive/
├── tasks/
│   └── archive/
├── decisions/
│   └── archive/
├── logs/
└── guardrails/
```

---

## Step 3 — Initialize Project Files

Templates (`PRD_TEMPLATE.md`, `TASK_TEMPLATE.md`) and reference docs (`WORKFLOW.md`, `VOICE.md`) stay in the plugin — skills read them directly from the plugin's `templates/` directory at runtime. Only project-specific files are created here.

Read each template from the plugin's `templates/` directory and write to the project, replacing `{project name}` and `{workflowDir}` placeholders:

- `{workflowDir}/logs/TASK_LOG.md` ← from plugin `templates/logs/TASK_LOG.md`
- `{workflowDir}/logs/DECISION_LOG.md` ← from plugin `templates/logs/DECISION_LOG.md`
- `{workflowDir}/logs/CHANGE_LOG.md` ← from plugin `templates/logs/CHANGE_LOG.md`
- `{workflowDir}/logs/PRD_LOG.md` ← from plugin `templates/logs/PRD_LOG.md`
- `{workflowDir}/logs/RETRO_LOG.md` ← from plugin `templates/logs/RETRO_LOG.md`
- `{workflowDir}/MILESTONES.md` ← from plugin `templates/MILESTONES.md`
- `{workflowDir}/guardrails/GUARDRAILS.md` ← from plugin `templates/GUARDRAILS.md`
- `{workflowDir}/guardrails/INVARIANTS.md` ← from plugin `templates/INVARIANTS.md`

Do not overwrite files that already exist.

---

## Step 4 — Reference Documents & Ideation

Now that the directory structure exists, ask the user about reference documents using **AskUserQuestion**:

4. **Reference documents?** — header: `"References"`. "Do you have any reference documents (PRDs, idea notes, concept memos, design sketches)?" Options:
   - `"I have documents"` — user selects "Other" to provide file paths (comma-separated or directory path). Store them, proceed to Step 4a (Reference Assessment).
   - `"Brainstorm now"` — run a focused shaping session to produce a PRD. Proceed to Step 4b (Quick Ideation).
   - `"Skip for now"` — no references, no ideation. Continue to Step 5. User can run `/ddw:ideate` later.

### Step 4a — Reference Assessment

If the user provided reference document paths:

1. **Resolve paths** — expand directories (non-recursive, top-level `.md`/`.txt`/`.pdf` files only), deduplicate, and verify each file exists. Warn on missing files and continue with what's available.

2. **Read all documents.**

3. **Assess quality** against PRD template sections. For each core section, rate coverage as STRONG, PARTIAL, or MISSING:

   | Section | STRONG | PARTIAL | MISSING |
   |---------|--------|---------|---------|
   | Problem Statement | Clear problem + impact of inaction | Problem mentioned but vague or no impact | Not mentioned |
   | Users & Stakeholders | Named user types + their pain points | Users mentioned generically | Not mentioned |
   | Proposed Solution | Conceptual approach with user-facing flow | Hints but no coherent approach | Not described |
   | Success Criteria | ≥1 measurable outcome | Qualitative goals only | Not discussed |
   | Scope | Explicit list of what's included | Implicit from solution description | No boundaries |
   | Non-Goals | Explicit exclusions stated | "Future work" mentions | None |
   | Constraints | Technical/timeline/resource limits noted | Implied only | None |
   | Open Questions | Unknowns acknowledged | Uncertainty hinted at | None |

   Be generous — rough notes should get PARTIAL, not MISSING, if they contain relevant material. Assess across all provided documents collectively, not per-file.

4. **Present assessment** to the user:
   ```
   Reference Document Assessment:

   | Section             | Coverage | Notes                          |
   |---------------------|----------|--------------------------------|
   | Problem Statement   | STRONG   | Clear problem articulated      |
   | Users & Stakeholders| MISSING  | No user identification         |
   | Proposed Solution   | PARTIAL  | Concept exists, vague on scope |
   | ...                 | ...      | ...                            |
   ```

5. **Branch on quality:**
   - If all sections are STRONG → "Your documents cover the key areas well. I'll store these as references." Store paths and proceed to Step 5.
   - If any section is PARTIAL or MISSING → proceed to Step 4a-i.

### Step 4a-i — Focused Brush-Up

If the assessment found PARTIAL or MISSING sections:

1. **Offer brush-up:** "Your documents have good material but are thin on: {list PARTIAL/MISSING sections}. Would you like to brush them up? I'll run a focused shaping session on just the weak areas and produce a consolidated PRD."
   - If "no" / "skip" → store the reference paths as-is and continue to Step 5
   - If "yes" → continue

2. **Load shaper profile** — read `agents/shaper.md` from the DDW plugin root. Adopt its mindset for this session.

3. **Run focused shaping rounds** — only for sections rated PARTIAL or MISSING. For each gap section, run one mini-round:
   - Present what the existing documents say about this area (if PARTIAL) or note that nothing was found (if MISSING)
   - Ask 1-2 targeted questions (mapped from the ideate skill's corresponding round):
     - Problem Statement → ideate Round 1 questions
     - Users & Stakeholders → ideate Round 2 questions
     - Proposed Solution → ideate Round 3 questions
     - Scope / Non-Goals / Constraints → ideate Round 4 questions
     - Success Criteria / Open Questions → ideate Round 5 questions
   - Synthesize the user's response into the PRD section
   - Show the draft and ask if they want to refine or move on
   - User can say "skip" on any section or "done" to stop early

4. **Merge content** — combine the STRONG sections extracted from the original documents with the newly shaped sections.

5. **Get UTC datetime** via `date -u +"%Y-%m-%dT%H:%M:%SZ"`.

6. **Determine status** — assess the consolidated PRD. If all core sections have substance, recommend `solid`; if gaps remain, recommend `draft`. Ask the owner: "I'd mark this PRD as `{recommended}`. Does that feel right?" The owner decides.

7. **Save consolidated PRD** — write to `{workflowDir}/prds/PRD-{yyyymmdd}-{slug}.md` using the PRD template from the plugin's `templates/PRD_TEMPLATE.md`. Set the `Status:` field to the owner's choice. The slug is derived from the project name or a title the user provides. The Feedback Log starts with:
   ```
   - {actual UTC datetime} — [owner] PRD consolidated from reference documents during /ddw:init. Brush-up covered: {list of sections shaped}.
   ```

8. **Add PRD to PRD_LOG** — add the row to `{workflowDir}/logs/PRD_LOG.md` (include Status column).

9. **Store results** — add both the original reference paths and the generated PRD path to the references list. Continue to Step 5.

### Step 4b — Quick Ideation (no documents)

If the user has no reference documents but wants to brainstorm:

1. **Load shaper profile** — read `agents/shaper.md` from the DDW plugin root.

2. **Run full shaping session** — follow the ideate skill's shaping loop (all 5 rounds) exactly as described in the ideate skill. The user can say "skip" or "done" at any point.

3. **Get UTC datetime** via `date -u +"%Y-%m-%dT%H:%M:%SZ"`.

4. **Determine status** — assess the PRD. If all core sections have substance, recommend `solid`; if gaps remain, recommend `draft`. Ask the owner to confirm.

5. **Save PRD** — write to `{workflowDir}/prds/PRD-{yyyymmdd}-{slug}.md` using the PRD template. Set the `Status:` field to the owner's choice. Feedback Log:
   ```
   - {actual UTC datetime} — [owner] Initial PRD created during /ddw:init ideation.
   ```

6. **Add PRD to PRD_LOG** — add the row to `{workflowDir}/logs/PRD_LOG.md` (include Status column).

7. **Store the PRD path** in references and continue to Step 5.

---

## Step 5 — Gather Remaining Configuration

Use **AskUserQuestion** to collect remaining config (questions 5-6 together):

5. **Test command?** — header: `"Tests"`. Auto-detect from the project (look for `package.json` scripts, `Makefile`, `pytest.ini`, etc.). Options:
   - `"{detected command} (Recommended)"` — if a test command was detected
   - `"None"` — no test command configured
   - (User selects "Other" to provide a custom command)
   - If nothing detected, offer common options for the project's language/framework instead.

6. **Auto-update spec on close?** — header: `"Auto-spec"`. Options:
   - `"Yes (Recommended)"` — always update the spec when a task finishes
   - `"No"` — manual spec updates only

---

## Step 6 — Write Config

Create the config file at `{workflowDir}/ddw.json` (git-tracked, shared by team).

**Source of truth:** `templates/ddw.json.example` in the plugin root. Read it, parse it as JSON, then override only the user-collected fields. This way the canonical schema lives in one place — when fields like `worktree`, `commands`, `auto`, `smoke`, etc. are added to the example, new projects get them automatically via init without this skill needing edits.

**Procedure:**

1. Read `templates/ddw.json.example` from the plugin root.
2. Parse as JSON.
3. **Add** a top-level `"project"` field set to the user-selected project name (the example doesn't carry a project-specific name).
4. **Override** these fields with user-collected values:
   - `workflowDir` ← user-selected workflow directory
   - `specPath` ← user-selected spec path (default `docs/CURRENT_SPEC.md`)
   - `testCommand` ← user-selected test command, or `null`
   - `autoUpdateSpec` ← user-selected boolean
5. **Set** `references` to an array of paths gathered during Step 4 (empty `[]` if none).
6. Write the merged JSON to `{workflowDir}/ddw.json` with 2-space indentation.

The resulting file should contain ALL keys from `ddw.json.example` (`schemaVersion`, `worktree`, `commands`, `auto`, `smoke`, `paths`, `userName`, `testFilePattern`, etc.) plus the project-specific overrides — not a stripped subset.

**User identity** is resolved at runtime, not stored in config:
```bash
git config user.name || whoami
```

---

## Step 7 — Inject CLAUDE.md Block

Read `CLAUDE.md` in the project root (create if it doesn't exist). Add the following block. If there's already DDW content, replace it.

```markdown
## DDW (mandatory)
Config: `{workflowDir}/ddw.json`. Flow: `/ddw:ideate` → `/ddw:decision` → `/ddw:task` → `/ddw:sendit` → code → `/ddw:review` → `/ddw:close`. On session start, scan `{workflowDir}/` for active work and report status.

When the user asks "what's next?" or similar, scan the full workflow pipeline and list everything not done:
- Draft PRDs (`prds/PRD-*.md` with `Status: draft`) → suggest `/ddw:ideate` to refine or `/ddw:decision` to proceed
- Proposed decisions (`decisions/DEC-*.md` with `Status: proposed`) → suggest reviewing and setting to `decided`
- Decided decisions with uncreated tasks (`## Tasks` has `(not yet created)`) → suggest `/ddw:task`
- Planned tasks (`tasks/TASK-*.md` with `Status: planned`) → suggest `/ddw:sendit`
- In-progress tasks (`Status: in_progress`) → suggest continuing implementation
- Tasks in review (`Status: review_and_bugfix`) → suggest completing review
- Milestone progress from `MILESTONES.md` — show done/total per active milestone
```

---

## Step 8 — Create Current Spec

The spec file is always created. The approach depends on whether there's existing code:

### If the project has existing code:

1. Read the spec template from the plugin's `templates/CURRENT_SPEC_TEMPLATE.md`.
2. Explore the project's source code, README, and any existing documentation.
3. Generate `{specPath}` by filling in the template sections based on the current implemented behavior:
   - **Purpose** — the problem the system solves and current phase objective
   - **Design Principles** — core architectural principles observed in the code
   - **Scope / Non-Goals** — what the system does and explicitly doesn't do
   - **System Overview** — components and high-level data flow
   - **Domain Model** — entities, relationships, source of truth, state transitions
   - **Module sections** — one `## 6. Module: {Name}` section per major module. For each: why it exists, current use cases/business rules/edge cases, constraints, and future direction hints
   - **Interfaces** — APIs, events, external integrations
   - **Data & Ownership** — who owns what data, write responsibility, sync strategy
   - **Open Gaps** — unknowns or unimplemented areas
   - **Related** — link to FUTURE_SPEC.md, DECISION_LOG.md, INVARIANTS.md
4. Document what the system **does**, not what it **should** do. Keep it concise — aim for a living document that stays accurate, not exhaustive.
5. Leave sections blank (with the template placeholder) if the codebase doesn't have enough information to fill them. Don't fabricate.
6. For the initial generation, set all `> Shaped by:` reference lines to `> Shaped by: init` — there are no tasks or decisions yet. The `/ddw:close` skill will replace these with actual task/decision IDs as sections get updated.

### If the project is new/empty (no meaningful code to analyze):

1. Read the spec template from the plugin's `templates/CURRENT_SPEC_TEMPLATE.md`.
2. Write a skeleton spec to `{specPath}` with all `> Shaped by: init` placeholders.
3. If a PRD was created during Step 4 (ideation), populate the **Purpose** and **Scope / Non-Goals** sections from the PRD content.
4. The `/ddw:close` skill will fill in remaining sections as tasks are completed — the spec grows with the project.

---

## Step 9 — Report

Output a summary:

```
DDW initialized for {project name}!

Workflow directory: {workflowDir}/
  ├── prds/           (PRDs)
  │   └── archive/
  ├── tasks/          (task files)
  │   └── archive/
  ├── decisions/      (decision files)
  │   └── archive/
  ├── logs/           (TASK_LOG, DECISION_LOG, PRD_LOG, CHANGE_LOG, RETRO_LOG)
  ├── guardrails/     (GUARDRAILS.md + INVARIANTS.md)
  └── MILESTONES.md

Plugin-provided (always up to date):
  Skills:    /ddw:ideate, /ddw:decision, /ddw:task, /ddw:sendit, /ddw:review,
             /ddw:close, /ddw:qa, /ddw:drift, /ddw:architect, /ddw:upgrade
  Hooks:     validate-datetime, require-active-task, require-all-tasks,
             require-review-before-close, check-task-complete,
             enforce-review-after-impl, no-guess-skills, check-deps-done
  Agents:    shaper, developer, qa, architect
  Templates: PRD_TEMPLATE, TASK_TEMPLATE, WORKFLOW, VOICE (read at runtime)

Config: {workflowDir}/ddw.json (git-tracked)
Identity: git config user.name || whoami
Spec: {specPath or "not configured"}
References: {count} document(s) — {list paths, or "none configured"}
Tests: {testCommand or "not configured"}

Next steps:
1. Run /ddw:architect bootstrap — seed guardrails and invariants from your codebase
2. {If PRD was created during init: "Review your PRD at {prdPath} — refine it or start: /ddw:decision"}
   {If no PRD: "Start your first feature: /ddw:ideate (shape an idea) or /ddw:decision (if you already know what to build)"}
```
