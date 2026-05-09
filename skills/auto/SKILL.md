---
name: auto
description: Overnight orchestrator. Loops through the DDW pipeline autonomously — implements, QA-checks, advances reviews, and closes tasks without waiting for owner input. Logs everything; queues anything that needs a human call for the morning inbox.
disable-model-invocation: false
---

**Invocation gate:** Only run this skill when the user explicitly typed `/ddw:auto`. Never auto-invoke from ambiguous context.

---

## What this does

The owner has gone to bed. Your job: work through as many tasks as possible without ever waiting on a human. When you hit something that needs owner judgment, log it and move to the next workable item. Never sit and wait. Never ask. Write a note and keep going.

## What this won't do

- Make architectural decisions. Decisions still in `proposed` stay that way — they go to the morning inbox.
- Reimplement any existing skill. You dispatch them via subagents using the Agent tool.

---

## 0. Read voice

Read `{workflowDir}/VOICE.md` (if it exists) and follow its communication style for any user-facing output.

## 1. Parse arguments and read config

`$ARGUMENTS` may contain any combination of:
- `--budget tasks=N,minutes=M` (defaults: 20 tasks, 480 minutes)
- `--level self-driving|co-pilot|advisor` (default: read from `ddw.json.auto.level`, fallback `self-driving`)
- `--dry-run` (default: false)

Read `{workflowDir}/ddw.json` (search `workflows/ddw.json`, `.workflows/ddw.json`, then `.claude/ddw.json` for legacy). Resolve:

- `workflowDir`, `workflowRoot` (repo root via `git rev-parse --show-toplevel`), plugin root (`${CLAUDE_PLUGIN_DIR}`)
- `paths.tasks`, `paths.decisions`, `paths.prds` (default: `tasks`, `decisions`, `prds`)
- `commands.test` (used in pre-close verification)
- `worktree.maxConcurrent` (default 3)

Read `auto.*` block (all optional, with defaults):
- `auto.maxConcurrent` — null → `min(worktree.maxConcurrent * 2, 4)`, minimum 1
- `auto.subagentTimeoutMinutes` — default 20
- `auto.consecutiveErrorLimit` — default 3
- `auto.confirm_on` — default `["destructive", "architecture", "external-side-effects"]`
- `auto.level` — default `"self-driving"` (overridden by `--level`)

Read `smoke.*` block (all optional):
- `smoke.command` — script to run (e.g. `"pnpm smoke"`); if absent, smoke is skipped silently
- `smoke.timeoutMinutes` — default 5
- `smoke.browser.mode` — default `"playwright-or-note"`; allowed: `"playwright"`, `"playwright-or-note"`, `"note-only"`
- `smoke.browser.checks` — list of `{url, expect}` objects; `expect` is `"status=NNN"` or `"selector=CSS"`

Set `level` from precedence: `--level` flag > `ddw.json.auto.level` > `"self-driving"`.

## 2. Resolve Playwright availability

Check whether you have access to any tool whose name starts with `playwright` or contains `_navigate`/`_screenshot` (e.g. `mcp__playwright__*`). If yes, set `playwright_available = true`. If no, set `playwright_available = false`.

If `smoke.browser.mode` is `"playwright"` and Playwright is unavailable: warn but continue with curl-only behavior (treat as `playwright-or-note`).

## 3. Set up run directory

Get current UTC datetime: `date -u +"%Y-%m-%dT%H:%M:%SZ"`. Call this `{run-start}`.

Derive `{run-id}` by replacing `:` with `-` in `{run-start}` (e.g. `2026-05-09T22-00-00Z`).

Create directories under `{workflowRoot}`:
```
{workflowDir}/.ddw/logs/auto/{run-id}/
{workflowDir}/.ddw/logs/auto/{run-id}/tasks/
{workflowDir}/.ddw/logs/auto/{run-id}/smoke/
```

**Write the auto-run-active bypass marker.** This signals the `require-explicit-implementation-go` PreToolUse hook that per-task owner-go confirmation is suppressed for the duration of this orchestration — `auto.confirm_on` is the per-task gate at this level instead.

```bash
touch "{workflowDir}/.ddw/AUTO_RUN_ACTIVE"
```

The marker is removed in step 6.2 (Finalize). If the auto run crashes hard before step 6.2, a stale marker can linger; see step 4 for the safety check that mitigates it.

If `--dry-run`: print to user once: `"DRY RUN — no files will be modified, no subagents will run."` All actions in step 5 are logged with a `[DRY RUN]` prefix instead of executed; subagents are not spawned. Also skip the AUTO_RUN_ACTIVE marker write — dry runs should not weaken the per-task gate.

## 4. Write run.json and initialize logs

**Stale-AUTO_RUN_ACTIVE check.** Before assuming the marker we just wrote is the only one, scan for any pre-existing `awaiting-go-*.flag` markers in `{workflowDir}/.ddw/`. If any exist, those tasks were left mid-handoff by a previous (non-auto) sendit invocation. Decision rule:
   - If the user explicitly told auto to pick up those tasks (their IDs appear in the `$ARGUMENTS` parsed in step 1), keep the markers — auto's autonomy gate will handle them per `auto.confirm_on`. The markers are removed when those tasks transition out of `in_progress`.
   - If the markers reference tasks NOT mentioned in arguments, log to inbox under "Stuck" with reason `"awaiting-go marker present from prior session — owner intent unclear"` and skip those tasks for this run.

Write `{workflowDir}/.ddw/logs/auto/{run-id}/run.json`:
```json
{
  "run_id": "{run-id}",
  "started_at": "{run-start}",
  "ended_at": null,
  "level": "{resolved level}",
  "playwright_available": true|false,
  "budget": { "tasks": N, "minutes": M },
  "config": {
    "maxConcurrent": N,
    "subagentTimeoutMinutes": N,
    "consecutiveErrorLimit": N,
    "confirm_on": [...]
  },
  "exit_reason": null,
  "counters": {
    "shipped": 0,
    "blocked": 0,
    "hard_errors": 0,
    "consecutive_errors": 0,
    "tasks_dispatched": 0
  }
}
```

Write `{workflowDir}/.ddw/logs/auto/{run-id}/tick.log` header:
```
# DDW Auto Run {run-id} | level={level} | budget=tasks:{N},minutes:{M}
# timestamp | action | task-or-dec-id | result | reason
```

Write `{workflowDir}/.ddw/logs/auto/{run-id}/inbox.md` with header only:
```markdown
# DDW Auto Run — {run-start} | {level}

(in progress…)
```

Maintain in-memory state for this run:
- `seen_proposed_decs` (set of DEC IDs already logged to inbox)
- `qa_block_count` (map of TASK-id → count of QA blocks; for one-retry rule)
- `smoke_retry_count` (map of TASK-id → count)
- `inflight_tasks` (set of TASK-ids currently being processed)
- `inbox_sections` (in-memory accumulator for shipped, browser_verify, decisions_pending, stuck, hard_errors)

## 5. Main loop — repeat steps 5.1–5.10 until exit

**Loop discipline:**
- Do NOT pause between iterations to report progress to the user.
- Keep your context lean: read only frontmatter / status / specific sections, never full task bodies, unless a step explicitly requires it.
- Each subagent gets its own context; do not absorb subagent output into your own beyond the report file.

### 5.1 Check exit conditions

Stop the loop and jump to step 6 if any of these are true:

- **Time budget exhausted:** elapsed minutes since `{run-start}` ≥ `budget.minutes`.
- **Task budget exhausted:** `counters.tasks_dispatched ≥ budget.tasks`.
- **Consecutive errors:** `counters.consecutive_errors ≥ config.consecutiveErrorLimit`.
- **Kill switch:** file `{workflowRoot}/{workflowDir}/.ddw/STOP` exists.
- **Queue empty:** previous iteration of step 5.3 returned no workable item AND no in-flight subagents remain.
- **Advisor mode:** `level == advisor` — write the planned action list to inbox and exit (see step 5.A).

Set `run.json.exit_reason` accordingly when one fires.

### 5.A Advisor mode (one pass, then exit)

If `level == advisor`, do this once instead of looping:

1. Run step 5.2 (scan pipeline).
2. For each candidate identified by step 5.3 logic, write what you *would* do to the inbox `## Plan` section: which row, which skill, which task or DEC id, in what order.
3. List all `proposed` decisions in the inbox `## Decisions waiting on you` section.
4. Skip dispatch entirely. Jump to step 6.

### 5.2 Scan pipeline state

Read frontmatter / minimal sections only.

**Tasks:** glob `{workflowDir}/{paths.tasks}/TASK-*.md`. For each, parse:
- `**Status:**` value
- `**Owner:**` value
- `**Decision:**` value
- `**Spec-affecting:**` (if present)
- `created_at` from filename or frontmatter
- `ready_at` (if present)
- Whether `## Implementation Summary` section is non-empty (post-implementation marker — Row 3)
- Whether `## Review Log` contains a QA verdict line, and if so, the latest verdict (`CLEAR` / `BLOCKED`)
- Whether `## Owner Review Checklist` contains any unchecked items (`- [ ]`)

**Decisions:** glob `{workflowDir}/{paths.decisions}/DEC-*.md`. For each, parse `status:` and `id:` fields.

Build sets keyed by status. Exclude any task in `inflight_tasks`.

### 5.3 Pick the next action

Walk the rows in order. Take the **first** row with a workable candidate. Within a row, pick the oldest by `created_at`. Skip candidates already in `inflight_tasks`.

**Row 1 — Auto-close** (requires `level == self-driving`)
- Trigger: a task has `**Status:** done` and is not yet archived.
- Action: pre-verify (step 5.5a), then dispatch `/ddw:close` subagent.

**Row 2 — Advance review** (requires `level == self-driving`)
- Trigger: a task has `**Status:** review_and_bugfix` AND its Review Log shows the latest QA verdict is `CLEAR` AND running `commands.test` (if configured) succeeds.
- Action: state flip directly (step 5.5b — no subagent).

**Row 3 — QA**
- Trigger: a task has `**Status:** in_progress`, its `## Implementation Summary` is non-empty, AND its Review Log has no QA verdict yet.
- Cap: at most 1 QA subagent at a time (sequential).
- Action: dispatch `/ddw:qa` subagent.

**Row 4 — Sendit**
- Trigger: a task has `**Status:** planned` AND the count of in-flight sendit subagents is `< config.maxConcurrent`.
- Action: dispatch `/ddw:sendit` subagent.

**Row 5 — Task creation** (requires `level == self-driving`)
- Trigger: a decision has `status: decided` AND no task references it via `**Decision:** {DEC-id}`.
- Cap: at most 1 task-creation subagent at a time.
- Action: dispatch `/ddw:task` subagent with the DEC id pre-filled.

**Row 6 — Proposed decisions** (always)
- Trigger: a decision has `status: proposed` AND its id is not in `seen_proposed_decs`.
- Action: append to `inbox_sections.decisions_pending`, add id to `seen_proposed_decs`. No dispatch.

If no row applies after walking all six, set exit reason "queue empty" and continue to step 5.1 (which will fire the exit if no in-flight subagents remain).

### 5.4 Autonomy gate

Before any dispatch (rows 1, 3, 4, 5) or direct action (row 2), check whether the action triggers any item in `auto.confirm_on`.

**Detection (read the task file's `## Goal`, `## Scope`, `## Acceptance Criteria` and `## Files` sections — only these — for keywords):**

- `destructive`: `migration`, `db:push`, `db:migrate`, `DROP TABLE`, `rm -rf`, `force-push`, `git reset --hard`, `secret rotation`, `delete user`, `truncate`, `purge`.
- `architecture`: the task's linked decision is still `proposed` (defensive — should never happen at Row 4 since DEC must be `decided` for tasks to exist).
- `external-side-effects`: `stripe`, `sendgrid`, `twilio`, `openai`, `anthropic`, `s3 upload`, `s3 delete`, `production`, `prod-`, real `email send`, `payment`, `charge`, `refund`. Suppress if any of these are also present: `dry_run`, `mock_`, `MOCK_EXTERNAL`, `test mode`, `staging`.

If a keyword matches and the corresponding category is in `auto.confirm_on`:
1. Append a "Stuck" entry to `inbox_sections.stuck`: TASK id, reason category, the keyword that triggered it, the line of the AC/scope where it appeared.
2. Append to tick.log: `{timestamp} | autonomy-block | {TASK-id} | skipped | {category}: {keyword}`.
3. Do NOT increment `tasks_dispatched`.
4. Do NOT mark task as in-flight.
5. Continue to next loop iteration.

### 5.5a Pre-close verification (Row 1)

Without a subagent:
1. Read the task's `## Owner Review Checklist`. Confirm every item has `[x]`. If any are unchecked, treat as blocked: log to `inbox_sections.stuck` with reason `"checklist incomplete"` and continue loop.
2. Read the task's Review Log. Confirm latest QA verdict is `CLEAR`. If not, log `"QA not CLEAR"` and continue.
3. If `commands.test` is configured: run it in `{workflowRoot}` with timeout `subagentTimeoutMinutes`. If non-zero exit, log `"tests red on close"` and continue.
4. Run smoke (step 5.7). If smoke fails, log `"smoke red on close"` and continue.
5. If all pass, proceed to step 5.6 (dispatch `/ddw:close`).

### 5.5b Advance review (Row 2 — direct, no subagent)

1. Read the task's full file once.
2. Confirm latest QA verdict in Review Log is `CLEAR`. If not, abort (defensive — step 5.3 should have filtered).
3. Run `commands.test` (if configured). If red, log to inbox `"tests red, cannot advance review"` and continue loop.
4. Edit the task file:
   - Change `**Status:** review_and_bugfix` → `**Status:** done`.
   - In `## Owner Review Checklist`, replace any `- [ ]` with `- [x]` and append a marker line at the top of the section (or as the first checklist line if no marker exists yet):
     ```
     > Auto-advanced by /ddw:auto on {UTC datetime} (level: self-driving) — QA CLEAR + tests pass verified.
     ```
   - Append to `## Work Log`:
     ```
     ### {UTC datetime}
     Status → done. Auto-advanced by /ddw:auto (run {run-id}): QA CLEAR + tests pass.
     ```
5. Append to `inbox_sections.shipped` (subtype `review-advanced`).
6. Append to tick.log: `review-advance | {TASK-id} | success`.
7. Increment `tasks_dispatched`. Reset `consecutive_errors`. Continue loop.

### 5.6 Dispatch subagent

For Row 1, 3, 4, or 5: spawn a subagent via the Agent tool.

**Before dispatching:** add the TASK or DEC id to `inflight_tasks`.

**Use the Agent tool with:**
- `description`: `"DDW auto: {skill-name} for {id}"` (under 50 chars)
- `subagent_type`: `"general-purpose"`
- `prompt`: build using the template below

**Subagent prompt template:**

```
You are a worker in a DDW auto session (run-id: {run-id}, level: {level}).

Your ONLY job: run /{ddw-skill-name} for {id} in the project at {workflowRoot}, then write a report.

## How to run the skill

1. Use the Skill tool with: skill='ddw:{ddw-skill-name}', args='{id}'.
2. Follow the skill exactly as you would if the owner had typed the command.
3. Do NOT ask the owner any questions. The owner is not available.
4. If you encounter an ambiguity, blocker, or destructive operation that needs owner judgment:
   - Stop the skill cleanly (don't force through).
   - Skip to step 5 below and write a "stopped-for-human" report.

## How to write the report (REQUIRED, even on failure)

After the skill finishes (or you stop it), write this file:
{workflowRoot}/{workflowDir}/.ddw/logs/auto/{run-id}/tasks/{id}.md

With this exact frontmatter and body:
---
task: {id}
skill: {ddw-skill-name}
result: success | blocked | error | stopped-for-human
final_status: {the final **Status:** value of the task file, or "n/a"}
---

## What happened
{1–3 sentences: what the skill did, what state the task is now in.}

## Reason (if not success)
{Specific reason. For "blocked": which gate stopped you (e.g., "QA verdict BLOCKED on AC-03"). For "stopped-for-human": what decision the owner needs to make. For "error": what failed.}

## Files changed
{One line per file path, or "none".}

## Working directory and config
- workflowRoot: {workflowRoot}
- workflowDir: {workflowDir}
- DDW plugin: ${CLAUDE_PLUGIN_DIR}

Return a one-line summary at the end of your output: "DONE | {result} | {1-line note}".
```

**Substitute `{ddw-skill-name}` and `{id}`:**

| Row | ddw-skill-name | id source |
|---|---|---|
| 1 | `close` | TASK id |
| 4 | `qa` | TASK id |
| 5 | `sendit` | TASK id |
| 6 | `task` | DEC id (subagent uses delegated mode — see `/ddw:task` skill) |

For Row 5, append this extra paragraph to the prompt:
```
You are running /ddw:task in DELEGATED mode. Read the decision file {DEC-id} at {workflowDir}/decisions/{DEC-id}.md and use its body to fill in title/goal/scope/non-goals automatically. Skip the AskUserQuestion step (step 4) entirely. If the decision body is too sparse to extract those fields confidently, return result=stopped-for-human with reason "DEC body too sparse for delegated task creation".
```

### 5.7 Smoke check (called from 5.5a)

If `smoke.command` is null/absent: return `pass = true` immediately, write a smoke result file with `script_smoke: "skipped"`.

Otherwise:

**Step A — script smoke:**
1. Run `bash -c "{smoke.command}"` from `{workflowRoot}` with timeout `smoke.timeoutMinutes` minutes.
2. Capture exit code, stdout (last 50 lines), stderr (last 50 lines).
3. `script_smoke = "pass"` if exit 0, else `"fail"`.

**Step B — browser checks** (only if `smoke.browser.checks` is non-empty):
- For each `{url, expect}`:
  - If `expect` starts with `status=`:
    - Parse expected code N.
    - Run `curl -s -o /dev/null -w "%{http_code}" --max-time 10 {url}`.
    - Pass if response equals N.
  - If `expect` starts with `selector=`:
    - If `playwright_available && smoke.browser.mode != "note-only"`:
      - Use the available Playwright tool to navigate to `{url}` and check the selector.
      - Pass if the element exists.
      - On pass: optionally capture screenshot to `{workflowDir}/.ddw/logs/auto/{run-id}/smoke/{TASK-id}-{idx}.png`.
    - Else:
      - Mark this check as `note-only` (neither pass nor fail).
      - Add a "Check in Chrome" entry to `inbox_sections.browser_verify`: TASK id, URL, selector, "verify the element renders correctly".

**Overall result:**
- If any check is `fail`: overall = `fail`.
- Else if `script_smoke == "pass"` (or `"skipped"`): overall = `pass`.
- A `note-only` browser check does NOT cause failure — the orchestrator proceeds and the task is added to the browser-verify list.

Write `{workflowDir}/.ddw/logs/auto/{run-id}/smoke/{TASK-id}.json`:
```json
{
  "task": "{TASK-id}",
  "timestamp": "{UTC}",
  "script_smoke": "pass|fail|skipped",
  "browser_checks": [
    { "url": "...", "expect": "...", "result": "pass|fail|note-only", "detail": "..." }
  ],
  "overall": "pass|fail"
}
```

Return overall result.

### 5.8 Read subagent result

After the Agent tool returns (success, error, or timeout):

1. **Check timeout:** if elapsed > `subagentTimeoutMinutes`, treat as `hard_error` with reason `"subagent timeout"`.
2. **Read the report file** at `{workflowDir}/.ddw/logs/auto/{run-id}/tasks/{id}.md`. If missing: `hard_error`, reason `"report file missing"`.
3. **Parse the frontmatter** for `result` and `final_status`.
4. **Read the task file's current `**Status:**` field** to verify it matches `final_status`.

**Outcome classification:**

| Subagent result | Status check | Outcome |
|---|---|---|
| `success` | matches expected post-skill state (e.g., sendit → `review_and_bugfix` or `in_progress`+impl, qa → review_and_bugfix or in_progress, close → `closed`/archived) | `shipped` |
| `success` | unchanged or unexpected | `hard_error` (skill claimed success but didn't move state) |
| `blocked` | any | `blocked` |
| `stopped-for-human` | any | `blocked` |
| `error` | any | `hard_error` |

### 5.9 Apply outcome

**On `shipped`:**
- `counters.shipped += 1`
- `counters.consecutive_errors = 0`
- `counters.tasks_dispatched += 1`
- Append to `inbox_sections.shipped`: `{id} — {title} → {action} at {time}`.
- Append to tick.log: `{timestamp} | {action} | {id} | shipped | {1-line note}`.

**On `blocked`:**
- `counters.blocked += 1`
- `counters.consecutive_errors = 0`  (blocker is informative, not a system failure)
- `counters.tasks_dispatched += 1`
- **QA-block retry rule (Row 3 only):**
  - Increment `qa_block_count[id]`.
  - If `qa_block_count[id] == 1`: re-dispatch as Row 4 (sendit) with the QA findings appended to the subagent prompt under a `## QA Findings From Previous Pass` header. Do NOT log to inbox yet — give the dev one shot to fix.
  - If `qa_block_count[id] >= 2`: log to `inbox_sections.stuck` with reason `"QA failed twice"`, link to both report files.
- For other rows: append to `inbox_sections.stuck` with the reason from the report.
- Append to tick.log: `{timestamp} | {action} | {id} | blocked | {reason}`.

**On `hard_error`:**
- `counters.hard_errors += 1`
- `counters.consecutive_errors += 1`
- `counters.tasks_dispatched += 1`
- Append to `inbox_sections.hard_errors`: `{id} — {error summary}`. Link to report file.
- Append to tick.log: `{timestamp} | {action} | {id} | error | {reason}`.

Remove the id from `inflight_tasks`.

### 5.10 Update run.json

Rewrite `{workflowDir}/.ddw/logs/auto/{run-id}/run.json` with current `counters`. (Atomic — write to a tmp file, then rename.)

Continue back to step 5.1.

---

## 6. Finalize and exit

### 6.1 Wait for in-flight subagents

If any subagents are still in flight when an exit condition fires (other than queue-empty), wait for them to finish. For each, run step 5.8 → 5.9.

### 6.2 Update run.json + remove auto-active marker

Set on `run.json`:
- `ended_at`: current UTC datetime
- `exit_reason`: the exit condition that fired
- `counters`: final values

Remove the bypass marker so the per-task owner-go gate is restored for the next non-auto session:
```bash
rm -f "{workflowDir}/.ddw/AUTO_RUN_ACTIVE"
```

This must run regardless of exit reason — even on hard errors. If the marker is left in place across sessions, the require-explicit-implementation-go hook becomes a no-op. (Re-running `/ddw:auto` would heal the state since step 6.2 always runs at the end of the new run; the worry is the gap *before* the next auto run.)

### 6.3 Write final inbox.md

Replace `{workflowDir}/.ddw/logs/auto/{run-id}/inbox.md` contents with:

```markdown
# DDW Auto Run — {run-start} | {level} | {duration HhMm}

Exit reason: {exit_reason}

## Shipped ({count})
{for each entry in inbox_sections.shipped, oldest first:}
- {id} — {title} → {action} at {time}

## Check in Chrome ({count})
{for each entry in inbox_sections.browser_verify:}
- {TASK-id} — {title}: open {url}, verify {what}

## Decisions waiting on you ({count})
{for each entry in inbox_sections.decisions_pending:}
- {DEC-id} — {title} (proposed)
  Why blocked: still in `proposed`. Run `/ddw:decision` when you're ready.

## Stuck ({count})
{for each entry in inbox_sections.stuck:}
- {id} — {title} → {reason}
  Last tried: {action}
  Details: {workflowDir}/.ddw/logs/auto/{run-id}/tasks/{id}.md

## Hard errors ({count})
{for each entry in inbox_sections.hard_errors:}
- {id} — {title}: {error summary}
  Details: {workflowDir}/.ddw/logs/auto/{run-id}/tasks/{id}.md
```

If a section has count 0, still include the heading with `(0)` — empty sections are informative.

### 6.4 Symlink latest

```bash
mkdir -p {workflowRoot}/{workflowDir}/.ddw/inbox
ln -sf ../logs/auto/{run-id}/inbox.md {workflowRoot}/{workflowDir}/.ddw/inbox/latest.md
```

(Relative symlink so the link survives if `{workflowDir}/.ddw` is moved.)

### 6.5 Print summary

Print one concise block to the conversation:

```
Auto run complete.
  Run id: {run-id}
  Level: {level} | Duration: {Xh Ym}
  Shipped: {N} | Stuck: {N} | Errors: {N} | Decisions waiting: {N}
  Browser-verify items: {N}
  Morning inbox: {workflowDir}/.ddw/inbox/latest.md
  Exit reason: {exit_reason}
```

If `--dry-run`: replace "Auto run complete" with "Dry run complete — no changes made, no subagents spawned." Show the planned action list as well.

---

## Reference: Never-wait conditions

If any of these arise, log to inbox and move on. Never block on a prompt:

- Architectural ambiguity (subagent reports `stopped-for-human` with architecture reason)
- Destructive operation detected by autonomy gate (step 5.4) or by subagent
- External API call without dry-run / mock / staging marker
- QA blocked twice for the same task in this run (one-retry rule)
- Smoke red after one retry on the same task in this run
- Subagent exceeded `subagentTimeoutMinutes`
- Subagent report file missing → hard error
- `commands.test` red on a Row 1 or Row 2 verification

## Reference: Frontmatter writes

This skill writes to:
- `{workflowDir}/.ddw/logs/auto/{run-id}/run.json` (sole writer)
- `{workflowDir}/.ddw/logs/auto/{run-id}/tick.log` (sole writer)
- `{workflowDir}/.ddw/logs/auto/{run-id}/inbox.md` (sole writer)
- `{workflowDir}/.ddw/logs/auto/{run-id}/tasks/{id}.md` (written by spawned subagents)
- `{workflowDir}/.ddw/logs/auto/{run-id}/smoke/{id}.json` (sole writer)
- `{workflowDir}/.ddw/inbox/latest.md` (symlink)

**Direct task-file writes (Row 2 only):**
- `**Status:**` flip from `review_and_bugfix` → `done` (self-driving level only)
- `## Owner Review Checklist` auto-tick + marker line
- `## Work Log` append

These three writes are scoped to `level == self-driving` and gated by QA CLEAR + tests pass. No other direct task-file writes — all other state changes happen via the existing skill subagents.
