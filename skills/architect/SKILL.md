---
name: architect
description: Run an architectural design review for a feature, or bootstrap a project's guardrails and invariants. Produces system design, constraints, task breakdown, and risk analysis.
disable-model-invocation: false
---

**Invocation gate:** Only run this skill when (1) the user explicitly typed the `/ddw:architect` command, (2) a hook enforcement message demands it, or (3) you proposed running this skill and the user clearly confirmed. Never auto-invoke from ambiguous context.

Run an architectural review. Scope: $ARGUMENTS.

- If $ARGUMENTS describes a feature or change → **Design Review** (Mode A)
- If $ARGUMENTS is "bootstrap" → **Bootstrap Review** (Mode B)
- If $ARGUMENTS is empty → ask the user what they'd like reviewed

---

## Mode A: Design Review

Use when the user describes a feature, change, or enhancement they want.

0. **Read voice** — read `{workflowDir}/VOICE.md` (if it exists) and follow its communication style.

1. **Read config** — read `{workflowDir}/ddw.json` (search `workflows/ddw.json`, `.workflows/ddw.json`, then `.claude/ddw.json` for legacy) to get `workflowDir`, `specPath`.

2. **Load architect profile** — read the `agents/architect.md` bundled with the DDW plugin (plugin root, not project directory). Adopt its mindset for the duration of this skill.

3. **Tiered context load** — read strategically, not exhaustively:

   **Always read** (compact, essential context):
   - `{workflowDir}/guardrails/GUARDRAILS.md`
   - `{workflowDir}/guardrails/INVARIANTS.md`
   - `{workflowDir}/MILESTONES.md`
   - `{workflowDir}/logs/DECISION_LOG.md` (index table only — not individual decision files). Before reading, rebuild it by syncing from `DEC-*.md` files in `{workflowDir}/decisions/` (excluding `decisions/archive/`).

   **Scan selectively** (skim structure, read relevant parts):
   - Spec at `specPath`: read headings and structure first, then only sections related to the feature
   - `{workflowDir}/logs/RETRO_LOG.md`: scan for entries related to the area being changed

   **Drill into on relevance** (only if the feature relates):
   - Specific `DEC-*.md` files — only those listed in DECISION_LOG that interact with this feature
   - Source code — read entry points and directory structure first, then only files/modules the feature will touch or depend on

   **Rule:** Load proportional to feature scope. Small feature = small read. System-wide change = broader read. If in doubt, start narrow and widen only when you find connections.

4. **Design the approach:**
   - How does the requested feature fit the existing system?
   - What components/functions are affected?
   - What state management is needed?
   - What is the simplest design that works?
   - Should any part use AI (LLM, RAG, agents, embeddings)? If so, why and how? If not, say "Not applicable."

5. **Dependency analysis:**
   - Which existing decisions does this interact with?
   - Are there ordering constraints? (must ship before/after something)
   - Can this be built independently?

6. **Constraint discovery:**
   - Propose new guardrails for GUARDRAILS.md (if any emerge from the design)
   - Propose new invariants in full INV-* format (if any)
   - Flag conflicts with existing guardrails or invariants

7. **Task breakdown:**
   - Propose how to split the work into tasks
   - For each task: scope, files affected, key acceptance criteria
   - **Explicitly note dependencies** between tasks using `(depends: {slug})` notation. A task depends on another when it requires that task's output (e.g., can't build endpoints without the parser). Tasks with no dependencies omit the annotation.
   - Estimate: 1 task, 2-3 tasks, or 4+ tasks

8. **Risk flags:**
   - Cross-cutting concerns
   - Irreversible changes
   - Areas needing more investigation
   - Severity: LOW / MEDIUM / HIGH

9. **Output the Architect Review:**

   ```
   ## Architect Review — {feature/change title}
   Date: {UTC datetime from `date -u`}

   ### System Design
   {How the feature fits the system. What to build, where it goes,
   how it connects to existing components. Keep it concrete.}

   ### AI Considerations
   {Whether/how AI should be used — or "Not applicable."}

   ### Dependencies
   - Relates to: {DEC-* list, or "None — independent"}
   - Ordering: {constraints, or "None"}

   ### Proposed Constraints
   #### New Guardrails
   {proposed rules for GUARDRAILS.md, or "None proposed."}

   #### New Invariants
   {proposed INV-* entries, or "None proposed."}
   - INV-{cat}-{date}-{slug}: {description} / Check: {type} / Assert: {what}

   #### Conflicts
   {existing guardrails/invariants this may conflict with, or "None detected."}

   ### Blast Radius
   - Files: {list of files affected}
   - Existing invariants at risk: {list, or "None"}
   - Features affected: {list of existing features that could change behavior}

   ### Task Breakdown
   1. {slug} — {description} (files: X, Y)
      AC: {key acceptance criteria}
   2. {slug} — {description} (depends: {slug-from-step-1}) (files: A, B)
      AC: {key acceptance criteria}
   {or "Single task is sufficient."}

   Note: Include `(depends: {slug})` for tasks that require another task to be done first. Omit for independent tasks.

   ### Risks
   | # | Risk | Severity | Mitigation |
   |---|------|----------|------------|
   | 1 | {description} | LOW/MEDIUM/HIGH | {what to do about it} |
   {or "No significant risks identified."}

   ### Verdict
   **SOUND** / **NEEDS-DISCUSSION** / **RETHINK**
   {1-2 sentence summary of the overall assessment}
   ```

10. **Present to owner for discussion.** Do NOT auto-create any files. The architect's review is a discussion surface — the owner may adjust, push back, or ask questions.

11. **During discussion**, track what changes:
    - What the owner adjusted or disagreed with
    - What was clarified or added
    - What the final agreement is
    
    This discussion will be recorded as a summary in the DEC file when `/ddw:decision` creates it.

12. **Once the owner agrees with the design**, offer to proceed:
    - "Ready to create the decision file from this design?"
    - If yes: run `/ddw:decision` to create the DEC-*.md file embedding the architect review and discussion summary. The decision starts at `proposed` — the owner must move it to `decided` before tasks can be created via `/ddw:task`.
    - If no: the review stands as a reference for whenever the owner is ready.

---

## Mode B: Bootstrap Review

Use for new projects that don't have guardrails or invariants yet. Run with `/ddw:arch bootstrap`.

0. **Read voice** — read `{workflowDir}/VOICE.md` (if it exists).

1. **Read config** — read `{workflowDir}/ddw.json` (search `workflows/ddw.json`, `.workflows/ddw.json`, then `.claude/ddw.json` for legacy).

2. **Load architect profile** — read the `agents/architect.md` bundled with the DDW plugin (plugin root, not project directory).

3. **Scan the codebase strategically:**
   - Read directory structure and entry points first
   - Identify major modules/subsystems from file organization
   - Read representative files per module (not every file)
   - For large projects: focus on public APIs, main entry points, config files, and shared utilities
   - Read existing docs (README, any existing spec)

4. **Produce System Overview:**
   - Major subsystems and their responsibilities
   - Data flow: where information enters, transforms, and exits
   - Key abstractions and design patterns in use
   - Shared state and potential coupling points

5. **Propose initial GUARDRAILS.md content:**
   - **Architecture Rules**: patterns the codebase already follows (cite evidence: "Observed in {file}")
   - **Implementation Rules**: coding conventions visible in the code
   - **Anti-Patterns**: things the codebase avoids (and should keep avoiding)

6. **Propose initial INVARIANTS.md content** (~10 to start):
   - Structural invariants (file organization, module boundaries)
   - Behavioral invariants (key algorithms, state machines, formulas)
   - Data invariants (counts, schemas, configurations)
   - Each must be verifiable against the CURRENT code — no aspirational rules
   - Use standard format: `INV-{S|B|D}-{yyyymmdd}-{slug}`

7. **Propose milestone structure** for MILESTONES.md (if empty).

8. **Advise on AI opportunities** (if relevant):
   - "This project could benefit from X" — only if genuinely applicable
   - "No AI components recommended" is a valid output

9. **Output Bootstrap Report.** Do NOT auto-write to any files. Present the full report and wait for the owner to approve each section before applying changes.

10. **Apply approved changes** — only after owner confirms:
    - Write approved guardrails to GUARDRAILS.md
    - Write approved invariants to INVARIANTS.md
    - Write approved milestones to MILESTONES.md
