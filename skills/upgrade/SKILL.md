---
name: upgrade
description: Upgrade an existing DDW project to match the current plugin version. Non-destructive — only adds missing fields, patches templates, and backfills new features.
disable-model-invocation: false
---

**Invocation gate:** Only run this skill when (1) the user explicitly typed the `/ddw:upgrade` command, (2) a hook enforcement message demands it, or (3) you proposed running this skill and the user clearly confirmed. Never auto-invoke from ambiguous context.

Upgrade an existing DDW project's scaffolding to match the current plugin version. This skill is non-destructive — it only adds or updates, never deletes content.

---

## Step 1 — Read Config

Read `{workflowDir}/ddw.json` — search `workflows/ddw.json`, `.workflows/ddw.json`, then `.claude/ddw.json` (legacy). Use the first one found to get `workflowDir` and all current config fields. Resolve user identity via `git config user.name || whoami`.

---

## Step 2 — Scan for Differences

Compare the project's current state against what the latest plugin expects. Check each item and classify as UP-TO-DATE, NEEDS-UPDATE, or MISSING:

### 2.1 — Config (`ddw.json`)

Read `templates/ddw.json.example` from the plugin root. Compare every key — at every nesting level — against the project's `ddw.json`. Flag MISSING for any key present in the example but absent in the project config. Existing values are never overwritten.

This is the single source of truth for `ddw.json` shape — no need to enumerate individual fields here. New fields added to `ddw.json.example` are automatically caught without updating this skill.

### 2.2 — Templates

Compare each project template against the plugin's `templates/` version. Check for structural differences (missing columns, missing sections, outdated comments). Templates to check:

- `{workflowDir}/prds/PRD_TEMPLATE.md` — should have `Status:` field in header
- `{workflowDir}/logs/TASK_LOG.md` — should have updated sync comment (not "auto-rebuilt")
- `{workflowDir}/logs/DECISION_LOG.md` — should have updated sync comment
- `{workflowDir}/logs/PRD_LOG.md` — should have Status column and status reference table
- `{workflowDir}/logs/CHANGE_LOG.md` — should have updated sync comment
- `{workflowDir}/logs/RETRO_LOG.md` — should have updated sync comment
- `{workflowDir}/tasks/TASK_TEMPLATE.md` — check against plugin template

### 2.3 — Missing Files

Check for files that should exist but don't:
- `{workflowDir}/prds/` directory and `prds/archive/`
- `{workflowDir}/logs/PRD_LOG.md`

### 2.4 — Existing PRD Files

Scan all `PRD-*.md` files in `{workflowDir}/prds/` and `prds/archive/`. Check if they have a `Status:` field in their header.

### 2.5 — Current Spec

If `specPath` is set in config, check if the spec file follows the current template structure (has `> Shaped by:` reference lines, has all expected sections from `templates/CURRENT_SPEC_TEMPLATE.md`).

### 2.6 — CLAUDE.md

Check the DDW block in `CLAUDE.md` against the current expected content from the init skill's Step 8.

### 2.7 — Top-level `.ddw/` migration

Older DDW versions placed runtime/operational state at `${workflowRoot}/.ddw/` (top of the repo). Current versions place it under `${workflowDir}/.ddw/` so the require-active-task hook's `*/$DDW_WORKFLOW_DIR/*` skip rule covers it.

Check:
- If `${workflowRoot}/.ddw/` exists AND `${workflowRoot}/${workflowDir}/.ddw/` does NOT exist → mark NEEDS-MIGRATE.
- If both exist → mark MERGE-NEEDED (very rare; surface to owner).
- If only the new location exists → UP-TO-DATE.
- If neither exists → UP-TO-DATE (nothing to migrate; auto run will create on demand).

### 2.8 — `.gitignore`

Check that `${workflowRoot}/.gitignore` includes a pattern matching `${workflowDir}/.ddw/`. If absent → mark MISSING.

### 2.9 — Integration staging removal

Older DDW versions had `worktree.integrationDir` in `ddw.json` and `.ddw/integration.json` runtime state for the integration-staging worktree. Phase A drops this entirely.

Check:
- If `ddw.json` contains a `worktree.integrationDir` key → mark NEEDS-CLEANUP.
- If `${workflowRoot}/.ddw/integration.json` exists OR `${workflowRoot}/${workflowDir}/.ddw/integration.json` exists → mark NEEDS-CLEANUP.
- If `${workflowRoot}/.worktrees/integration/` exists → mark NEEDS-CLEANUP-MANUAL (worktree removal is destructive; surface to owner, don't auto-remove).

---

## Step 3 — Present Upgrade Report

Show the user a summary of everything found:

```
DDW Upgrade Report for {project name}

Config (ddw.json):
  - references field: MISSING — will add as []
  - (other fields): UP-TO-DATE

Templates:
  - PRD_TEMPLATE.md: NEEDS-UPDATE — missing Status field
  - TASK_LOG.md: NEEDS-UPDATE — outdated sync comment
  - PRD_LOG.md: MISSING — will create
  - ...

Existing Files:
  - 3 PRD files without Status field — will backfill as "solid"
  - CURRENT_SPEC: NEEDS-UPDATE — missing Shaped-by references
  - CLAUDE.md: UP-TO-DATE

{count} items need updating. Proceed?
```

Wait for the user's confirmation before making any changes.

---

## Step 4 — Apply Upgrades

After user confirms, apply all changes:

### 4.1 — Patch `ddw.json`

Deep-merge `templates/ddw.json.example` from the plugin root into the project's `ddw.json`:
1. Read and parse both files as JSON.
2. For every key present in the example but absent in the project config — at any nesting depth — add it with the example's default value.
3. Never overwrite existing values. Never remove or rename existing fields.
4. Write the result back with 2-space indentation, preserving field ordering from the example where possible.

This subsumes all per-field checks (including `references`, `merge.mode`, `auto`, `smoke`, etc.) — new fields added to `ddw.json.example` are applied automatically without requiring edits to this skill.

### 4.2 — Patch Templates

For each template that needs updating:
- Read the current project template
- Read the plugin's latest template from `templates/`
- **Merge** — add missing structural elements (columns, sections, comments) without destroying existing data rows
- Specifically:
  - Log templates: replace the HTML comment line with the updated version. Do not touch data rows below the table header.
  - PRD_LOG: add the status reference table and Status column to the header row if missing. Do not touch existing data rows — add the Status column value for existing rows by reading the corresponding PRD file.
  - PRD_TEMPLATE: add `Status: draft` line after the title if missing.

### 4.3 — Create Missing Files/Directories

- Create `{workflowDir}/prds/` and `prds/archive/` if they don't exist
- Create `{workflowDir}/logs/PRD_LOG.md` from plugin template if it doesn't exist
- Copy `PRD_TEMPLATE.md` to `{workflowDir}/prds/` if it doesn't exist

### 4.4 — Backfill Existing PRD Files

For each `PRD-*.md` file missing a `Status:` field:
- Add `Status: solid` to the header (between the title and Date lines)
- Rationale: these PRDs were created before statuses existed and were presumably adequate at the time

### 4.5 — Patch Current Spec (optional)

If the spec exists but doesn't follow the new template structure:
- Ask the user: "Your current spec doesn't have the new `> Shaped by:` reference lines. Want me to add them? I'll set them to `> Shaped by: pre-upgrade` for existing sections."
- If yes: add `> Shaped by: pre-upgrade` reference lines to each major section
- If no: skip — the close skill will add references as sections get updated naturally

### 4.6 — Patch CLAUDE.md

If the DDW block is outdated:
- Replace the existing DDW block with the current version from init Step 5

### 4.7 — Migrate top-level `.ddw/`

If Step 2.7 reported NEEDS-MIGRATE:
- `mv ${workflowRoot}/.ddw ${workflowRoot}/${workflowDir}/.ddw`
- Verify the move with `ls ${workflowRoot}/${workflowDir}/.ddw/` and confirm `${workflowRoot}/.ddw/` is gone.
- If Step 2.7 reported MERGE-NEEDED, surface the conflict to the owner with the full file listing of both locations and ask for guidance — do NOT auto-merge.

### 4.8 — Patch `.gitignore`

If Step 2.8 reported MISSING:
- Append a `# DDW runtime state (per-developer, do not commit)` comment block at the end of `.gitignore` (or after the existing DDW-related section if one exists).
- Add the line `${workflowDir}/.ddw/` (e.g. `workflows/.ddw/`) on its own line.
- If `.gitignore` doesn't exist, create it with just this block.
- Never reorder or remove existing lines.
- Do not touch any other content in CLAUDE.md

### 4.9 — Remove integration staging artifacts

If Step 2.9 reported NEEDS-CLEANUP:
- Delete `worktree.integrationDir` key from `ddw.json` (preserve other worktree fields).
- Delete `${workflowRoot}/.ddw/integration.json` and `${workflowRoot}/${workflowDir}/.ddw/integration.json` if they exist.
- For NEEDS-CLEANUP-MANUAL (`.worktrees/integration/`): tell owner: "Found `.worktrees/integration/` — Phase A removed integration staging. Run `git worktree remove .worktrees/integration` to clean up when convenient."

---

## Step 5 — Verify

After all changes:
1. Re-run the scan from Step 2 to confirm everything is now UP-TO-DATE
2. If any items still need attention, report them

---

## Step 6 — Report

```
DDW upgraded for {project name}!

Changes applied:
  - {list each change made}

No changes needed:
  - {list items that were already up-to-date}

Skipped (user declined):
  - {list items user chose to skip, if any}
```
