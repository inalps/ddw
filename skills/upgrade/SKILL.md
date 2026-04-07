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

Check for missing fields that the current plugin expects:
- `references` (array) — added for reference document tracking
- Any other fields present in the init skill's Step 2 schema but absent in the project's config

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

Add missing fields with sensible defaults:
- `references`: `[]`

Do not remove or rename existing fields. Preserve all existing values.

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
- Do not touch any other content in CLAUDE.md

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
