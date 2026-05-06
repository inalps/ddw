# DDW Enhancement Plan

**Date:** 2026-04-28
**Source:** Refinement decisions from `ddw-refine.md` retrospective + design conversation
**Frame:** Fast + team (2-5 people, ~6 month horizon). Accurate as a watch-item — not yet team-tested. Security and consistency as enterprise baselines.

This document captures decisions only. Reasoning is included where the *why* changes how the decision should be applied.

---

## 1. Foundation — Memory → Repo (do first)

**The single highest-leverage move.** Rules that govern fast-and-accurate work currently live in per-user memory (Claude's memory files). Teammates onboarding will not inherit them; a memory reset wipes them. They must move into repo-tracked artifacts.

### Port to `CLAUDE.md` (project-tracked):

1. **Always write tests with implementation.** Every route/service ships with a companion test file (per the project's `testFilePattern` — see §2).
2. **Verify routes and ports before linking.** Grep target route, check internal vs external, verify port defaults.
3. **Worktree convention.** DDW orchestration runs from main repo on `main`; code work happens in `.worktrees/TASK-name`.
4. **Dev scripts must use `--env-file .env`** (or language equivalent — declared per project).
5. **Migration workflow** (declared per project — for Node+Drizzle: always `db:generate` + `migrate`; never hand-write SQL).
6. **Verification before "done".** Before claiming a task complete, run typecheck on the affected package and the companion test, and report the result inline.

### Rejected from the retro doc (wrong for team/enterprise frame):

- **Inline DECs** — DEC files are read by people not in the room. Don't scatter into task headers.
- **Auto-spawn worktrees without confirmation** — filesystem actions in shared/team contexts need explicit gates.
- **Spec splitting (CURRENT_SPEC by domain)** — treats symptom; the root cause is `autoUpdateSpec: true` running on every close. Fix that instead (see §8).

---

## 2. Framework Abstraction — Language-Agnostic

DDW must work for any project (next one may be Python). The skill code must not contain `pnpm`, `tsc`, or any toolchain reference. The project declares its commands in `ddw.json`.

### `ddw.json` schema additions:

```jsonc
{
  "commands": {
    "install": "pnpm install",
    "dev": "pnpm -F './apps/*' --parallel dev",
    "typecheck": "pnpm typecheck",
    "test": "pnpm test",
    "lint": "pnpm lint",
    "audit": "pnpm audit --prod"
  },
  "lockfile": "pnpm-lock.yaml",
  "testFilePattern": "*.test.ts",
  "services": "docker compose -f infra/compose.yml",
  "worktree": {
    "maxConcurrent": 3,
    "integrationDir": ".worktrees/integration",
    "taskDir": ".worktrees/{TASK_NAME}",
    "syncFiles": [".env", ".env.local", "secrets/**", "*.pem"]
  },
  "audit": {
    "severityThreshold": "high",
    "allowlistFile": ".ddw/audit-allowlist.json"
  }
}
```

### Principles:

- DDW knows about **verbs** (install, dev, typecheck, test, lint, audit, stage, unstage). Projects map verbs to commands.
- DDW knows about **workflow events** (task started, ready for integration, closed). It does not know about toolchains.
- Process orchestration (multi-process dev): framework recommends `mprocs` (language-agnostic). Does not bake `pnpm --parallel` or `turbo` into anything.

---

## 3. Worktree Topology

### Pattern:

```
~/repo/                            # main repo, on `main` — orchestrator
~/repo/.worktrees/TASK-A/          # agent works here on `task-a`
~/repo/.worktrees/TASK-B/          # parallel agent on `task-b`
~/repo/.worktrees/integration/     # persistent, on `integration` branch
                                    # full stack runs here for manual testing
```

### Rules:

- **Integration worktree runs the full stack** (all apps via `commands.dev`). Always present; runs hot once team lands, lazy-start when solo.
- **Task worktrees run only the apps they're touching** — usually 1, sometimes 2. Avoids the N×N process explosion.
- **Backend services (Postgres, OpenSearch, etc.) are shared at repo level** via root `docker-compose.yml`. Single instance, all worktrees connect.
- **Concurrent task worktree cap: 3** for the current monorepo+5apps topology. Higher counts contend for RAM/CPU and lose the parallelism gain. Tunable via `worktree.maxConcurrent`.
- **Port strategy:** integration uses canonical ports (e.g., 3000–3004); task worktrees use slot offsets (+100, +200, +300) determined by `worktree.maxConcurrent`. Codified in setup script — never thought about manually.

### Periodic reset:

Integration branch is disposable scratch. Reset it from `main` after each round of PRs lands (or weekly, whichever comes first). Script the reset.

### Secrets and dotfiles across worktrees:

`.env*` files, PEM keys, and other gitignored secrets don't follow `git worktree add` — each new worktree starts without them. Manually copying them is annoying *and* expands the secret surface (more copies = more exposure).

**Pattern: symlink at worktree creation, not copy.**

`setup-worktree.sh` reads `worktree.syncFiles` from `ddw.json` and symlinks each entry from the main repo into the new worktree:

```
.worktrees/TASK-A/.env       → ../../.env
.worktrees/TASK-A/secrets/   → ../../secrets/
.worktrees/integration/.env  → ../../.env
```

One canonical source. Edit once, all worktrees see the change. Delete a worktree → only the symlink dies; the canonical file is untouched.

**What to symlink:** secret/dotfile inputs (`.env*`, PEM keys, `secrets/`, optionally `.husky/_/`).
**What NOT to symlink:** `node_modules/` (pnpm content-addressed store handles dedup), build outputs, branch-specific configs, anything that needs to diverge per worktree.

**Caveats:**
- macOS / Linux native; Windows has symlink permission issues. If a teammate is on Windows, `setup-worktree.sh` needs a `cp` fallback (accepts the trade-off of more secret copies).
- Don't symlink things meant to be per-worktree (e.g., per-task DB configs).

---

## 4. Staging — Auto-Stage with FIFO Queue

### State machine:

```
Integration:  idle | testing TASK-X
Queue:        tasks where status == ready_for_integration ORDER BY ready_timestamp ASC
```

### Transitions:

1. Agent finishes a task, gates pass → status becomes `ready_for_integration`. Terminal prints `TASK-A queued`.
2. If integration is `idle` and queue is non-empty → stage head of queue. Integration becomes `testing TASK-A`. Terminal prints `TASK-A staged, ready for manual test`.
3. Human runs `/ddw:close TASK-A` → integration becomes `idle` → queue tick fires → next task stages.

### Trigger points (no Claude Code hooks — modify skill markdown):

- End of `/ddw:sendit` (or wherever agent emits `ready_for_integration`)
- End of `/ddw:close`

Both call standalone script: `ddw-queue tick`. Deterministic, can also be invoked manually for diagnosis.

### Scripts to create:

| Script | Purpose |
|---|---|
| `ddw-stage TASK-X` | Merge task branch into integration, surface conflicts, hot-reload picks up |
| `ddw-unstage TASK-X` | Revert that merge, hot reload picks up |
| `ddw-queue tick` | Advance queue: scan task statuses, stage head if integration idle |
| `ddw-integration-status` | Print what's currently staged + queue contents |
| `ddw-integration-reset` | Reset integration branch from main; re-install if lockfile changed |

### Edge cases (decided):

- **Stage conflict:** stop, surface to terminal, do not auto-resolve.
- **Reject during testing:** `ddw-unstage` returns task to `in_progress`; queue advances to next.
- **Priority override:** `ddw-stage TASK-C` directly bypasses the queue when human wants to test something specific.
- **Dependency (B needs A):** B queues; when A closes, B stages on top of A's accepted state. Correct by construction.
- **Notification mechanism:** terminal print only. (No macOS notifications, no status files for now.)

### Team consideration (deferred):

If integration ever becomes shared across machines, need real cross-machine locking. Per-machine integration is the current model — defer that complexity until it's actually painful.

---

## 5. Dev / QA Subagent Loop

### Architecture:

```
Main session (orchestrator on `main`)
  └─ Dev subagent (per task, in its worktree)
        ├─ implement
        ├─ self-loop: typecheck + unit tests until green
        ├─ spawn QA subagent (read-only, no memory access)
        │     └─ returns PASS or [structured issues]
        ├─ if FAIL: fix, re-spawn QA
        └─ if PASS: emit ready_for_integration → ddw-queue tick
```

### Files (in DDW plugin's `agents/` folder, not `.claude/agents/`):

- `agents/ddw-dev.md` — Dev role, includes loop logic
- `agents/ddw-qa.md` — QA role: read-only, fresh reader, structured feedback

### QA agent constraints:

- **Tools:** Read, Grep, Glob, Bash (for running tests). **No Edit, no Write.**
- **No memory access** — fresh reader is the entire point. Bias separation collapses if QA carries dev's context.
- **Returns structured feedback:** `[{file, line, severity, problem, suggestion}]`.

### Loop policy (decided):

| Setting | Value |
|---|---|
| Max iterations | **3** — then escalate to human with outstanding issues |
| Fail-closed | **Yes** — crash, malformed output, timeout → block + escalate |
| Each iteration | Prints summary to terminal (visibility + audit trail) |
| Dev disputes QA | Must justify in task file. 2+ disputes in one iteration → escalate (signal that AC isn't crisp enough) |

### Severity tiers:

| Severity | Examples | Effect |
|---|---|---|
| **Critical** | AC not met, concrete security vuln, keyboard-inaccessible interactive element | Blocks |
| **High** | Invariant violation, obvious bug, a11y violation excluding user groups, vulnerable dep newly introduced | Blocks |
| **Low** | Minor suggestion, theoretical risk, polish | Logged in feedback list, doesn't block |

Dev↔QA loop iterates only on Critical + High. Low items become comments or future tasks.

### QA scope (what to check):

- **Acceptance Criteria** met
- **Invariants (DDW INV)** preserved
- **Obvious bugs** — concrete from diff, not theoretical (allowed even outside AC)
- **OWASP Top 10** — scoped by diff relevance (UI? backend? auth? config?)
- **Tenant isolation (OWASP A01)** — first-class named check, given the project's recurring failure mode
- **Accessibility (WCAG 2.1 AA basics)** — only when diff touches UI files (`.tsx`/`.jsx`/templates)
- **Performance regression** — only when concrete and identifiable from diff (see below)

QA must explicitly state which categories were applied and which were skipped + why. Skipping with reasons > pretending to check.

### Performance regression — concrete heuristics only:

QA flags Critical/High when identifiable from diff:
- Loops containing `await db.*` / `await fetch` (N+1 indicator)
- Full-library imports where subpath exists (`import _ from 'lodash'` vs `import get from 'lodash/get'`)
- New synchronous `fs.*Sync` / blocking I/O on request paths
- Removed memoization without justification
- New unbounded list rendering (no pagination/virtualization where list could be large)
- New unindexed DB queries on identifiable large tables

Skip speculation ("might be slow under load"). Static analysis only — runtime profiling is out of scope.

### Parked for later (note kept):

- **i18n** (untranslated strings, missing locale handling)
- **Observability** (new code without logs/metrics)

Revisit once team is onboarded and we have data on which class of bugs is slipping through.

---

## 6. `/ddw:audit` Skill (Framework-Level)

### Purpose:

Dependency vulnerability audit (OWASP A06). Defined at framework level, **not** per task. Per-task audit is wasteful (same result 50× a day).

### Behavior:

1. Run `commands.audit` from `ddw.json`
2. Parse output, filter against allowlist
3. Write structured entry to `AUDIT_LOG.md` (date, lockfile hash, vulns by severity, allowlisted, expired, action taken)
4. Return: pass / fail (vulns ≥ threshold) / no-op (lockfile unchanged since last audit)

### When it runs:

- **Manually** — `/ddw:audit` invoked any time
- **Stage-time guard** — `ddw-stage` checks if `ddw.json.lockfile` hash differs from last `AUDIT_LOG.md` entry. If yes, runs audit before staging. If audit fails above threshold, stage blocked.
- **Scheduled** — framework documents *how* (cron, GitHub Action, launchd) but does not impose. Skill is idempotent and fast on no-op.

### Severity policy: strict + allowlist (decided)

```
audit.severityThreshold: "high"
audit.allowlistFile: ".ddw/audit-allowlist.json"
```

Allowlist entry shape:

```json
{
  "id": "GHSA-xxxx-yyyy-zzzz",
  "package": "axios",
  "reason": "affected method not used in this codebase",
  "mitigation": "code path verified absent in apps/* via grep",
  "expiry": "2026-07-28"
}
```

### Rules:

- `expiry` is **required**, max 90 days from add date.
- Expired entries = blocking (treated same as new vulns).
- Allowlist changes go through PR review — that's the human gate on accepted risk.
- `/ddw:audit` output explicitly shows: `blocking: N`, `allowlisted: M (X expiring in <14d)`, `expired: K`.
- **Fail-closed**: audit crash, parse error, timeout → block + escalate.

### One-time onboarding cost (flagged):

First `/ddw:audit` against current lockfile will likely surface dozens of transitive vulns. Plan a focused 30–60 min triage session: fix-now (upgrade), allowlist-with-reason-and-expiry, or block-until-upstream-patches. After that, audit goes quiet because lockfile-hash check skips re-runs when deps haven't changed.

---

## 7. Verification Gates

### `/ddw:sendit` changes:

- Refuses to proceed if companion test file is missing per `testFilePattern`.
- "No unit test applicable: <reason>" is a valid completion state — recorded in task file as an explicit, reviewable statement (not a silent skip).
- After "ready" status, calls `ddw-queue tick`.

### `/ddw:review` (now QA's recipe):

- Runs `commands.typecheck` + `commands.test`
- Runs Invariant scan
- Runs the QA scope items from §5

### Optional hook (belt-and-suspenders):

PostToolUse on Edit → background `commands.typecheck` on the affected package. Add only if the sendit gate fails to stick in practice.

---

## 8. Other DDW Framework Changes

### One task template, conditional sections (no explicit tiers):

There is **one** task template. Sections render conditionally based on task properties — the "micro" state emerges naturally when none of the heavyweight conditions trigger. Author never picks a tier; the system never asks "is this micro or standard?"

**Sections that always render:**
- Goal
- Acceptance Criteria
- Changes (what files, what conceptually changed)
- Review Log (QA outcome — auto-populated by the dev/QA loop)

**Sections that render conditionally:**
- **Decision link** — only if a DEC exists. Orphan tasks (the 15% pattern from the retro) simply have no DEC field, no friction.
- **Scope / Non-Goals / Constraints** — only when scope is non-trivial (multi-file, architectural touch, or estimated ≥ 2hr). Trivial tasks omit these; they're meaningless on a one-line fix.
- **Context Packing / Session Handoff** — only when task is expected to span sessions, or has been resumed.
- **Retrospective** — per skip rule below (clean QA + < 2hr + single session = no prompt).
- **Work Log** — only when task spans multiple sessions.

**Why this is simpler than tiers:**
- One mental model, one template — teaches in a sentence.
- No promotion/demotion ceremony when scope grows mid-task: a section just starts rendering when its trigger condition becomes true.
- Reviewers see exactly what was relevant for the task, no boilerplate "N/A" noise.
- Metrics still derivable: "tasks where retro was skipped" + "tasks with no DEC linked" gives the same view a `tier: micro` field would give.

The audit trail (who, what, when, why, what changed, QA outcome) is preserved in every task file regardless of which sections rendered.

### Skip retro prompt when nothing happened:

62 of ~80 retro entries said "Clean run. No issues." That's not consistency — it's compliance theater that buries the few retros with actual content (e.g., the studio-intent-axis policy redesign).

**Skip retro prompt when all of:**
- QA passed on first iteration (no failure cycles)
- Implementation < 2hr
- Task did not span work days

**Otherwise, prompt for retro — as the first step of `/ddw:close`, before any other action.**

Ordering matters: retro happens *before* archiving, log updates, spec updates, and queue tick. Reasons:
- Details are still fresh; reflection quality is highest at the start of close
- If retro is at the end, by then the user is in "done" headspace and rubber-stamps it
- Forces the reflection moment before the bookkeeping carries you past it

Task file always records the metadata (QA iteration count, duration, session boundaries), so the absence of a retro is auditable from the task itself — anyone can see *why* it was skipped. The signal-to-noise ratio of `RETRO_LOG.md` improves directly: every entry that exists is one worth reading.

### Make CURRENT_SPEC update opt-in per close:

Currently `autoUpdateSpec: true` triggers a full 1,254-line spec rewrite on every close, including 5-min bug fixes. Change so spec update is conditional (e.g., only when scope spans architectural boundaries). This is the real fix; spec splitting is unnecessary if the rewrite isn't on the hot path.

### Logs become derived views from canonical task files:

Today `/ddw:close` writes to 6-8 files: task file, `TASK_LOG.md`, `CHANGE_LOG.md`, `RETRO_LOG.md`, `CURRENT_SPEC.md`, `MILESTONES.md`, parent DEC. Most of these are **redundant** — same information in 3-4 places — and are append-only single-writer files that break under team concurrent closes (Insight 4).

**The wiser pattern: task files are the only source of truth. Logs are generated.**

Same model as `git log` — you don't write to a "git log file"; the log is computed from commit objects on demand.

| File | New role | Close-time cost |
|---|---|---|
| Task file | **Canonical source** — all metadata in frontmatter (status, dates, dec, qa, duration, files changed) | 1 write (move to archive/) |
| `TASK_LOG.md` | **Generated** by `ddw-index` from task file frontmatter | 0 writes on close |
| `CHANGE_LOG.md` | **Eliminated.** Git is the change log. Conventional commits + `git log --grep` covers any curated view. | 0 writes |
| `RETRO_LOG.md` | **Generated** by `ddw-index` — retros live in task files; aggregate computed | 0 writes on close |
| `MILESTONES.md` | **Generated** from DEC files | 0 writes on close |
| `CURRENT_SPEC.md` | Conditional rewrite (see above) | 0 writes most closes |
| Parent DEC | Update only when archiving the DEC itself | 1 write (rare) |

**Result:** `/ddw:close` writes 1 file in the common case, 2 if archiving a DEC. Down from 6-8.

**Generation trigger: on-demand only (no daemon, no skill-triggered regen).**

Skills never write to view files. `ddw-index` runs only when someone explicitly invokes it — manually before reading, via a pre-commit hook so PRs include fresh views, or via a CI step. This avoids the team-concurrency race entirely: only one coordinator (the human running the command, or CI) ever writes views.

The view files are **read-only artifacts**: humans never edit them; `ddw-index` always overwrites. Stale views between regenerations are acceptable — these are human-readable artifacts, not real-time dashboards.

**Where the actual speedup comes from (honest accounting):**

The win isn't reduced disk writes — write count is roughly unchanged. The win is **reduced agent reasoning time** per close: with logs derived from task file frontmatter, the agent fills in the task file once and views are deterministic transformations of that. No per-log "what summary should I write here?" reasoning step, repeated across 4 different log formats.

Combined with conditional `CURRENT_SPEC` rewrite (above) and conditional template sections, close becomes meaningfully faster — but the savings come from skipped reasoning, not skipped writes.

**Regeneration model: full rebuild from scratch, idempotent.**

`ddw-index` is a pure transformation: `task files → view files`. No memory of prior runs. No incremental updates. Running it twice in a row produces identical output.

At ~150 task files, full rebuild takes well under a second. At 10x growth, ~5-10 seconds. Don't pre-optimize with incremental updates or caching — they add state-tracking bugs and drift risks for sub-second savings. If `ddw-index` ever exceeds ~5 seconds in practice, the right fix is a parsed-frontmatter cache (cache *inputs* keyed by mtime; outputs still rebuild from scratch) — but only after measurement, not preemptively.

**Two consequences worth naming:**

1. **No concurrent-write race.** Each task writes only to its own task file (different paths per close). View files have a single coordinator. The Insight 4 team-scaling problem dissolves without locks or fragments.
2. **Views can't drift from sources.** Today, `RETRO_LOG.md` can disagree with the retro section in a task file. With derived views, the output is always correct by construction.

**Eliminations (explicit):**

- `CHANGE_LOG.md` — deleted, never regenerated. Git is the source of truth.
- `TASK_LOG.md`, `RETRO_LOG.md`, `MILESTONES.md` — repurposed as generated read-only mirrors.

This subsumes the original "Insight 4 fragment + lock" approach. Single-writer per file is the simpler primitive — achieved by giving each task its own file.

### PRD lifecycle and archival path:

Currently `templates/logs/PRD_LOG.md` defines three PRD statuses: `draft`, `solid`, `parked`. There's no path for what happens after `solid` once a DEC is decided, and no archival mechanism — PRDs accumulate indefinitely.

**Three new statuses added:**

| Status | Meaning | Transition | Archives? |
|---|---|---|---|
| `building` | At least one linked DEC is in progress | Auto from `solid` when first linked DEC is created. Auto → `done` when all linked DECs close. | No |
| `done` | All linked DECs closed; work shipped | Auto-archive immediately on entry | **Yes** → `prds/archive/` |
| `cancelled` | Rejected or abandoned | Manual; auto-archives at transition | **Yes** → `prds/archive/` |

**Existing statuses unchanged:** `draft`, `solid`, `parked`.

**Status transitions are derived by `ddw-index`** (same model as the log views). The owner manually drives only:
- `draft → solid` (shaping complete)
- `* → parked` / `parked → solid` (explicit pause/resume)
- `* → cancelled` (explicit kill)

Everything else (`solid → building → done → archive`) is automatic and inferred from DEC states.

**Linkage:**
- PRD frontmatter: `decisions: [DEC-A, DEC-B]` — the DECs implementing this PRD
- DEC frontmatter: `prd: PRD-X` — the PRD that spawned this DEC
- Bidirectional and `ddw-index`-readable

**Skill changes:**
- `/ddw:ideate` (existing): unchanged creation flow; produces PRDs that fit the new lifecycle.
- `/ddw:decision` (existing): when a DEC is created from a PRD, sets the DEC's `prd:` field. `ddw-index` then flips PRD `solid → building`.
- `/ddw:close` (DEC close): when the last DEC linked to a PRD closes, `ddw-index` flips PRD `building → done` and archives the file.
- **New:** `/ddw:prd cancel PRD-X` for explicit cancellation.

**Edge cases:**
- **Multi-DEC PRD:** status is `building` while *any* linked DEC is in progress; flips to `done` only when *all* close.
- **A linked DEC gets cancelled, others remain:** PRD stays in `building`. If *all* linked DECs end up cancelled with no replacement, PRD reverts to `solid` so the owner can re-architect or cancel manually.
- **Externally-sourced PRDs (Notion, Linear, etc.):** captured via `/ddw:ideate` with an external reference link in the PRD body. The DDW-side artifact is the canonical lifecycle holder regardless of where the original document lives.

### Triage stale items from current state (one-off cleanup):

- Park or cancel the 10 stale `proposed` DECs from Apr 14 (sitting >2 weeks).
- Triage `kiosk-tenant-switcher` (in_progress since Apr 15).

---

## 9. Tracking the Refinement Itself

### Use DDW for DDW (lightly):

- One umbrella DEC: **"DDW Refinement Initiative"** with the items from this doc as child tasks.
- Tier 1 items (memory→repo, /ddw:audit skill, ddw.json schema) become the **first dogfood test** of the lighter task pattern.
- **Cap:** no more than 1 DDW-refinement task open at a time alongside product work. Meta-work must not crowd out real work.

### Baseline metrics (capture before changes):

- Tasks completed per day (current avg: 7.8)
- % retro entries with content (current: ~22%)
- % closes touching `CURRENT_SPEC.md` (currently: 100%)
- % tasks shipping a companion test file
- Time from "agent done" → "human accepted" (manual estimate)

### Kill criterion:

If after **2 weeks** of the new flow, throughput hasn't moved or quality is the same/worse, revert and look at task selection or other bottlenecks instead. Don't let sunk-cost defend the framework changes.

---

## 10. Open Questions

These need answers before some of the above can be scripted:

1. **Turbo / nx / plain pnpm?** Affects orchestration script in the *current* repo (framework stays agnostic regardless).
2. **Are backend services already in a root `docker-compose.yml`?** If per-worktree compose files exist, fix that first — it's the bigger resource problem than dev servers. Verify before implementation order item 5.
3. **Integration worktree visibility:** `.worktrees/integration` (consistent) or sibling directory (more visible to teammates)?
4. **Default scheduling for `/ddw:audit`:** weekly via launchd? In CI? Both? (Framework documents options; project picks one.)
5. **`/ddw:upgrade` migration logic for this enhancement plan:** existing DDW-using projects need to adopt the new `ddw.json` fields, PRD statuses, directory layout, and skill behavior. What does the upgrade flow do — auto-migrate, prompt-then-migrate, or print a manual checklist?

**Migration policy for the current Neu project (decided):** existing artifacts (143 tasks, 44 decisions) are **grandfathered** in their current format. New artifacts use the new framework. Active artifacts (open DECs, `CURRENT_SPEC.md`) migrate incrementally as work continues. No big-bang migration.

---

## 11. Implementation Order

Suggested sequencing (each is one DDW refinement task, cap of 1 open at a time):

1. Port memory rules → CLAUDE.md *(foundation; unblocks team)*
2. Add `commands.*`, `lockfile`, `testFilePattern` to `ddw.json` schema + skill code refactor *(removes language assumptions)*
3. Create `agents/ddw-qa.md` and `agents/ddw-dev.md` *(unblocks the loop architecture)*
4. Create `/ddw:audit` skill + allowlist mechanism + initial triage session
5. Create staging scripts (`ddw-stage`, `ddw-unstage`, `ddw-queue tick`, `ddw-integration-status`, `ddw-integration-reset`)
6. Update `/ddw:task` skill: single template with conditional section rendering based on task properties
7. Update `/ddw:sendit` skill: companion-test gate, queue tick at end
8. Update `/ddw:close` skill in this order: **(a) conditional retro prompt first**, then archive + log updates, then conditional CURRENT_SPEC update, then queue tick at end
9. Stabilization gate after phase-level work (typecheck + grep for known failure modes)
10. One-time triage of stale `proposed` DECs and `kiosk-tenant-switcher`
11. Migrate logs to derived views: build `ddw-index` script, eliminate `CHANGE_LOG.md`, convert `TASK_LOG.md` / `RETRO_LOG.md` / `MILESTONES.md` to generated mirrors, wire skills to call `ddw-index` at end
12. PRD lifecycle: add `building` / `done` / `cancelled` statuses, PRD ↔ DEC bidirectional linkage in frontmatter, `prds/archive/` directory, `/ddw:prd cancel` skill, status transition inference in `ddw-index`
13. Update `GUIDE.md` to reflect the new framework: integration worktree workflow, dev/QA loop, `/ddw:audit`, PRD lifecycle, derived views. Without this, the team-onboarding goal of item 1 is half-done.

i18n, observability, and notification upgrades stay parked.
