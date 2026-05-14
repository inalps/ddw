---
name: prd
description: Manage PRD lifecycle. Subcommands: close PRD-id, defer PRD-id slug, reject PRD-id slug.
disable-model-invocation: false
---

**Invocation gate:** Only run this skill when (1) the user explicitly typed the `/ddw:prd` command, (2) a hook enforcement message demands it, or (3) you proposed running this skill and the user clearly confirmed. Never auto-invoke from ambiguous context.

Manage the PRD lifecycle using the Decision-Driven Workflow.

0. **Read voice** — read `{workflowDir}/VOICE.md` (if it exists) and follow its communication style for all output during this skill.

1. **Read config** — read `{workflowDir}/ddw.json` (search `workflows/ddw.json`, `.workflows/ddw.json`, then `.claude/ddw.json` for legacy) to get `workflowDir` (default: `workflows`). Resolve user identity by running `git config user.name || whoami`.

2. **Parse $ARGUMENTS** — extract subcommand and arguments.
   - Supported formats:
     - `close <PRD-id>` (or just `<PRD-id>` — default subcommand is `close`)
     - `defer <PRD-id> <slug>` — mark a backlog entry as `(deferred)`
     - `reject <PRD-id> <slug>` — mark a backlog entry as `(rejected)`
   - If the subcommand is unrecognised, error: "Unknown subcommand: {subcommand}. Supported: close <PRD-id>, defer <PRD-id> <slug>, reject <PRD-id> <slug>."

3. **Find the PRD file** at `{workflowDir}/prds/{PRD-id}.md`.
   - If not found and only a slug was given (no full `PRD-{yyyymmdd}-{slug}` form), scan `{workflowDir}/prds/PRD-*.md` for a file whose name contains the slug.
   - If still not found, error: "PRD not found: {input}."

3.5. **Dispatch — `defer` or `reject`:**
   - Read the PRD's `## Decision Backlog` section.
   - Find the line whose slug matches `<slug>`. If not found, error: "No backlog entry with slug `{slug}` in PRD-{id}."
   - If the entry is already `(decided → ...)`, refuse: "This entry is already decided as DEC-X. Won't overwrite — if you want to retract the DEC, run `/ddw:decision` cancel/park flow instead."
   - Get the actual current UTC datetime.
   - Replace the entry's trailing `(proposed)` with `(deferred)` (for `defer`) or `(rejected)` (for `reject`).
   - Append to `## Feedback Log`: `- {actual UTC datetime} — [owner:{userName}] Backlog entry "{slug}" marked {deferred|rejected}.`
   - Report: "PRD-{id} backlog entry `{slug}` marked {deferred|rejected}."
   - **Authority note:** `/ddw:prd defer` and `/ddw:prd reject` are the ONLY writers for these flips on a `## Decision Backlog` entry (per §13).
   - Stop here — do not run the close-flow steps below.

4. **Dispatch — `close`. Hard gate — check current status:**
   - Read the PRD file's `Status:` frontmatter field.
   - If status is already `closed`, block: "PRD-{id} is already closed. Run nothing."
   - If the `Decisions:` frontmatter array is empty (`Decisions: []`), warn the user: "PRD has no linked decisions — close anyway? (y/n)". Proceed only if the user confirms with `y`.

4.5. **Hard gate — Decision Backlog must be resolved.**
   - Read the PRD's `## Decision Backlog` section.
   - Count entries whose trailing marker is `(proposed)`.
   - If count > 0: **refuse to close.** Print:
     ```
     PRD-{id} has {N} unresolved backlog entries:
       - {slug-1} — {question}
       - {slug-2} — {question}

     Each must be one of:
       - decided    → run `/ddw:decision PRD-{id}` (or `/ddw:decision PRD-{id} <slug>`)
       - deferred   → run `/ddw:prd defer PRD-{id} <slug>`
       - rejected   → run `/ddw:prd reject PRD-{id} <slug>`

     Resolve all entries, then re-run `/ddw:prd close PRD-{id}`.
     ```
   - Stop here on refusal — do not flip status.
   - If count == 0: proceed.

5. **Get the actual current UTC datetime** by running:
   ```bash
   date -u +"%Y-%m-%dT%H:%M:%SZ"
   ```
   Use the exact output. Never use a placeholder like `T00:00:00Z`.

6. **Update the PRD frontmatter** — set `Status: closed` in the frontmatter. Preserve all other frontmatter fields exactly as-is (`id`, `title`, `created_at`, `Owner`, `Decisions:`, etc.). Do NOT touch those fields.
   - **Authority note:** `/ddw:prd close` is the ONLY writer for `status: closed` on a PRD (per §13 frontmatter authority matrix). No other skill sets this value.

7. **Append to the PRD's `## Feedback Log` section:**
   ```
   - {actual UTC datetime} — [owner:{userName}] PRD closed. Backlog: {N decided}, {M deferred}, {K rejected}.
   ```

8. **Archive the PRD file** — move the file from `{workflowDir}/prds/{PRD-id}.md` to `{workflowDir}/prds/archive/{PRD-id}.md`.
   - Create the `{workflowDir}/prds/archive/` directory if it does not exist.
   - After writing the updated content (steps 6–7), move the file using the shell: `mkdir -p {workflowDir}/prds/archive && mv {workflowDir}/prds/{PRD-id}.md {workflowDir}/prds/archive/{PRD-id}.md`.

9. Skip inline sync. Owner runs `ddw-index` to refresh `logs/PRD_LOG.md`.

10. **Report:** "PRD-{id} closed and archived. Backlog: {N decided}, {M deferred}, {K rejected}."

**Final note:** logs (`TASK_LOG.md`, `DECISION_LOG.md`, `RETRO_LOG.md`, `PRD_LOG.md`) are derived views. Run `node ${CLAUDE_PLUGIN_DIR}/scripts/ddw-index.mjs` to refresh, or rely on a pre-commit hook if configured.
