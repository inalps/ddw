---
name: decision
description: Create a new decision file and add it to the DECISION_LOG. Status defaults to proposed.
disable-model-invocation: false
---

**Invocation gate:** Only run this skill when (1) the user explicitly typed the `/ddw:decision` command, (2) a hook enforcement message demands it, or (3) you proposed running this skill and the user clearly confirmed. Never auto-invoke from ambiguous context.

Create a new decision file using the Decision-Driven Workflow.

0. **Read voice** — read `{workflowDir}/VOICE.md` (if it exists) and follow its communication style for all output during this skill.

1. **Read config** — read `{workflowDir}/ddw.json` (search `workflows/ddw.json`, `.workflows/ddw.json`, then `.claude/ddw.json` for legacy) to get `workflowDir` (default: `workflows`). Resolve user identity by running `git config user.name || whoami`.

1.5. **Logs are derived views.** Do not sync inline — `ddw-index` is the canonical generator. The owner runs `node ${CLAUDE_PLUGIN_DIR}/scripts/ddw-index.mjs` (or via pre-commit hook) to refresh. Skill steps below reference data from source files, never from `logs/`.

2. **Get today's UTC date** in `yyyymmdd` format for the file name prefix.

3. **Ask the user** (via AskUserQuestion) for the following if not already provided in $ARGUMENTS:
   - **Title** (short, descriptive — becomes the filename slug, e.g. `push-semantics`)
   - **Summary** (what is being decided and why — can be a rough draft)
   - **Milestone** (which milestone this belongs to — optional at proposed stage; check `{workflowDir}/MILESTONES.md` for existing milestones)

3.2. **Check for existing PRDs** —
   - Scan `{workflowDir}/prds/PRD-*.md` (excluding `prds/archive/`) for PRD files.
   - If any PRDs exist, present them to the user with their status: "Found PRDs: {list with IDs, titles, and status}. Would you like to reference one for this decision?"
   - If the user selects a PRD:
     - Read the full PRD file
     - If the PRD status is `draft`, warn: "This PRD is still a draft — some sections may be thin. The architect review may be less thorough as a result. Proceed anyway, or finalize it first with `/ddw:ideate`?" Let the user decide.
     - If the PRD status is `parked`, block: "This PRD is parked. Reactivate it first before referencing it in a decision."
     - Store the PRD ID for inclusion in the decision file header
     - The PRD content will be passed as context to the architect review in step 3.6
   - If the user declines or no PRDs exist, proceed normally. No PRD is required.
   - **PRD is read-only.** Do not modify the PRD's core sections (Problem Statement through Prior Art & Alternatives). Architect findings will be appended to the PRD's `## Feedback Log` in step 3.8.
   - **Also check `ddw.json` for `references` array.** If references exist and no PRD was selected above, read the reference files and present a summary: "Found reference documents in config: {list}. Would you like me to use these as additional context for the architect review?" If yes, include them in the context loaded in step 3.6.

3.5. **Load architect profile** — read the `agents/architect.md` bundled with the DDW plugin (plugin root, not project directory). Adopt its mindset for the design phase.

3.6. **Run architect analysis** using tiered context loading:

   **Always read** (compact, essential):
   - `{workflowDir}/guardrails/GUARDRAILS.md`
   - `{workflowDir}/guardrails/INVARIANTS.md`
   - `{workflowDir}/MILESTONES.md`
   - `{workflowDir}/logs/DECISION_LOG.md` (index only)
   - Referenced PRD file (if selected in step 3.2)
   - Reference documents from `ddw.json` `references` array (if not already covered by the selected PRD)

   **Scan selectively:**
   - Spec at `specPath`: headings first, then relevant sections
   - `{workflowDir}/logs/RETRO_LOG.md`: entries related to this area

   **Drill into on relevance:**
   - Specific DEC-* files that interact with this feature
   - Source code: entry points first, then affected files/modules

   Based on the user's summary and the context loaded, produce an Architect Review covering:
   - System Design (how the feature fits)
   - AI Considerations (if relevant, otherwise "Not applicable")
   - Dependencies (related decisions, ordering constraints)
   - Proposed Constraints (new guardrails and/or invariants)
   - Blast Radius (files, invariants at risk)
   - Task Breakdown (scope, files, AC per task)
   - Risks (with severity and mitigation)
   - Verdict: SOUND / NEEDS-DISCUSSION / RETHINK

3.7. **Present the architect review to the owner.** This is the discussion surface. The owner may:
   - Agree with the design
   - Adjust scope, approach, or task breakdown
   - Ask questions or raise concerns
   - Push back on specific points

   Do NOT proceed until the owner is satisfied with the design direction.

3.8. **Record discussion summary.** Track what was discussed:
   - What the owner adjusted or disagreed with
   - What was clarified
   - What the final agreement is
   This summary will be included in the DEC file's `## Discussion` section.

3.9. **Append to PRD Feedback Log and update Decisions array** (only if a PRD was referenced in step 3.2):
   - Get the actual current UTC datetime.
   - **Action A — Append architect-verdict entry** to the PRD's `## Feedback Log` section:
     ```
     - {actual UTC datetime} — [decision:DEC-{yyyymmdd}-{slug}] Architect review verdict: {verdict}. Key findings: {1-2 sentence summary of constraints, risks, or design notes surfaced during review}.
     ```
   - **Action B — Append decision-created entry** to the PRD's `## Feedback Log` section (immediately after the architect-verdict entry above):
     ```
     - {actual UTC datetime} — [decision-created:DEC-{yyyymmdd}-{slug}] Decision created from this PRD. Owner: close this PRD via `/ddw:prd close` once all relevant decisions exist.
     ```
   - **Action C — Update the PRD's `Decisions:` frontmatter array** — append the new DEC ID.
     - If currently `Decisions: []`, change to `Decisions: [DEC-{yyyymmdd}-{slug}]`.
     - If non-empty (e.g. `Decisions: [DEC-existing]`), append: `Decisions: [DEC-existing, DEC-{yyyymmdd}-{slug}]`.
   - **Authority note:** `/ddw:decision` is the ONLY writer for the PRD's `Decisions:` array (per §13 frontmatter authority matrix). No other skill may modify this field.
   - Do NOT modify any other section of the PRD. The PRD's core sections are the bible — read-only to all downstream processes.

4. **Get the actual current UTC datetime** by running:
   ```bash
   date -u +"%Y-%m-%dT%H:%M:%SZ"
   ```
   Use the exact output. Never use a placeholder like `T00:00:00Z`.

5. **Create the decision file** at `{workflowDir}/decisions/DEC-{yyyymmdd}-{slug}.md` where slug is the title lowercased with spaces replaced by hyphens. Use this exact format:

   ```
   # DEC-{yyyymmdd}-{slug} — {Title}

   Status: proposed
   Date: {actual UTC datetime}
   Owner: {userName from ddw.json}
   PRD: {PRD-id if referenced, or "none"}

   ## Summary
   {summary text}

   ## Architect Review
   {embed the architect review output from step 3.6 — System Design,
   AI Considerations, Dependencies, Proposed Constraints, Blast Radius,
   Task Breakdown, Risks, Verdict}

   ## Discussion

   - {actual UTC datetime} — Initial draft.
   - {actual UTC datetime} — Architect review completed. Verdict: {verdict}.
   - {actual UTC datetime} — Discussion summary: {brief record of what was
     raised, what changed, what was agreed during steps 3.7-3.8}

   ## Status Log

   - {actual UTC datetime} — proposed (initial draft with architect review)

   ## Tasks
   {If architect proposed tasks, list them here:}
   - {slug} — {description} (not yet created)
   {Or if single task: "- (single task — to be created)"}
   ```

6. **DECISION_LOG.md is a derived view** (`ddw-index` regenerates from DEC files). The new DEC file IS the source of truth — no manual log row needed.

7. **If a milestone was provided**, add the decision ID to the appropriate section in `{workflowDir}/MILESTONES.md`. If the milestone section doesn't exist yet, create it.

7.5. **Check milestone phase status** — if a milestone was provided and the section already exists:
   - If the section heading ends with `✅` (phase is complete): warn the user: "Milestone '{name}' is already marked complete. Adding a new decision will reopen it. Proceed?"
   - If the user confirms → remove the `✅` marker from the section heading (reopening the phase) and add the decision ID.
   - If the user declines → ask which milestone to use instead, or skip milestone assignment (can be assigned later before `decided`).

8. **Remind the user**: The architect review is complete and embedded in the decision file. A TASK may only be created once the Owner changes status to `decided`. Milestone assignment is required before `decided`.

9. **Multi-phase gate** (when the Owner later confirms `decided` and you update the status):
   - Ask: "How many tasks will this decision need? If more than one, list all planned tasks now."
   - If the answer is > 1: Update the `## Tasks` section with all planned task entries using the format:
     ```
     - {slug} — {description} (not yet created)
     - {slug} — {description} (depends: {dep-slug}) (not yet created)
     ```
     Include `(depends: {slug-a}, {slug-b})` when a task requires other tasks to be completed first. Derive ordering from the Architect Review's Task Breakdown. Tasks with no dependencies omit the annotation.
   - If the answer is 1 or unclear: Leave `## Tasks` as-is (the single task will be added by `/ddw:task`).
   - **After updating status to `decided`:** the `create-decided-tasks` hook will fire and list all uncreated tasks. Invoke `/ddw:task` for **each** listed task immediately, passing the decision ID, slug, and details from the Architect Review's Task Breakdown (goal, scope, non-goals, priority). Do not stop after creating only one task.
   - **Why:** The `create-decided-tasks` hook ensures all planned tasks are created together when a decision becomes `decided`. The `require-all-tasks` hook blocks `in_progress` on any task until ALL tasks listed in the decision's `## Tasks` section exist in TASK_LOG. The `check-deps-done` hook additionally blocks `in_progress` on any task whose `Depends-On` tasks aren't `done` yet. This prevents phases from being forgotten or started out of order across sessions.

9.5. **Commit proposed constraints** — after status is updated to `decided`:
   - Read the `## Architect Review` section of this decision file. Extract any items under **Proposed Constraints** (new guardrails and/or invariants).
   - If no constraints were proposed, skip this step.
   - Present each proposed constraint to the owner:
     ```
     The architect proposed these constraints for this decision:

     Guardrails:
       1. {proposed guardrail} — approve / reject?
       2. ...

     Invariants:
       1. {proposed invariant in INV-* format} — approve / reject?
       2. ...
     ```
   - For each approved guardrail: append it to `{workflowDir}/guardrails/GUARDRAILS.md`.
   - For each approved invariant: append it to `{workflowDir}/guardrails/INVARIANTS.md` using the standard `INV-{category}-{yyyymmdd}-{slug}` format.
   - Update the decision file's `## Architect Review → Proposed Constraints` section to mark each item's disposition:
     ```
     - {constraint} — **added** (written to GUARDRAILS.md)
     - {constraint} — **added** (written to INVARIANTS.md as INV-S-20260406-x)
     - {constraint} — **rejected** (reason: {owner's reason})
     ```
   - This creates a clear audit trail of which constraints were accepted and which were not.

10. **Report**: the decision file path, decision ID, and current status.

**Final note:** logs (`TASK_LOG.md`, `DECISION_LOG.md`, `RETRO_LOG.md`, `PRD_LOG.md`) are derived views. Run `node ${CLAUDE_PLUGIN_DIR}/scripts/ddw-index.mjs` to refresh, or rely on a pre-commit hook if configured.
