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

### Delivery mechanism — `@import` directive

Plugin ships `templates/CLAUDE_RULES.md` (the 6 rules, verb-form so language-agnostic). `/ddw:init` writes a single import line into the consumer's CLAUDE.md:

```
@${CLAUDE_PLUGIN_DIR}/templates/CLAUDE_RULES.md
```

Claude Code's CLAUDE.md import resolves at load time. The plugin **never edits consumer CLAUDE.md again** after `/ddw:init`. Plugin-side rule changes propagate automatically; user-side rules and team conventions live above/below the import line, owned entirely by the consumer.

Uninstall = remove the line. No string-surgery, no marker blocks, no merge protocol to maintain.

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

### `setup-worktree.sh` contract (Phase A — minimal)

```
scripts/setup-worktree.sh TASK-A [--base TASK-X]
```

Steps:

1. Compute target dir from `ddw.json.worktree.taskDir` (default `.worktrees/{TASK_NAME}`).
2. **Branch collision check:** if `task-a` already exists, exit 1 — never reuse a stranger's branch.
3. `git worktree add <dir> -b task-a <base>` — base = `main` by default, or `task-x` if `--base` given (for dependency tasks).
4. **Port offset:** count existing `.worktrees/TASK-*/` dirs (n), set `PORT_OFFSET=$((n * 100))` in the new worktree's `.env.ddw` (a per-worktree DDW-owned file, never in `syncFiles`). Project's `commands.dev` is expected to source `.env.ddw` before launching servers. If `n+1 > worktree.maxConcurrent`, warn but don't block.
5. **Sync files:** `ln -s` each entry in `worktree.syncFiles` from main repo into the new worktree. macOS/Linux only for now.
6. Run `commands.install` if dependency dir missing.

**Deferred until needed (post-onboarding):**
- Slot tracking (currently just count-based; collision possible if a worktree is deleted out-of-order)
- Windows `cp` fallback
- `worktree.maxConcurrent` hard enforcement

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

### Queue mechanics contract

**Locality decision: per-machine.**

`.ddw/integration.json` is **gitignored**. Each developer's integration worktree is local to their machine; the queue is local to their machine. This sidesteps cross-machine race conditions entirely. If shared integration ever becomes desirable, that's a future feature with its own locking design — not a default.

**State storage (consumer repo):**
- `.ddw/integration.json` → `{"testing": "TASK-X" | null}`. Single tiny file, single writer (the staging scripts), gitignored.
- Queue itself = derived: glob task files in `paths.tasks`, filter `status: ready_for_integration`, sort by `ready_at` ASC.
- `ready_at` lives in task frontmatter (committed) — that's a durable record of "was ready at time T," not queue state.

**Branch convention:** `task-{id-lowercased}`. TASK-A → branch `task-a`. Created by `setup-worktree.sh`.

**`ready_at` write point:** `/ddw:sendit` writes ISO timestamp to task frontmatter when flipping `status → ready_for_integration`. Single point of write — no ambiguity.

**`ddw-stage TASK-X` steps:**
1. Verify `integration.json.testing == null`. Else error.
2. **Refuse if integration worktree has uncommitted changes** — don't merge over WIP.
3. cd to integration worktree → `git merge task-x`.
4. Conflict → abort merge, exit non-zero, integration stays idle.
5. **Migration detection:** if `ddw.json.migrationGlob` matches files in the diff and `commands.migrate` is defined → run migration. Else warn and skip.
6. Write `{"testing": "TASK-X"}` to `.ddw/integration.json`.

**`ddw-unstage TASK-X` steps:**
1. Verify `integration.json.testing == "TASK-X"`.
2. cd to integration worktree → `git reset --hard HEAD~1`.
3. Flip task status `ready_for_integration → in_progress` in task frontmatter.
4. Clear `integration.json.testing`.
5. Call `ddw-queue tick`.

**Priority override:** `ddw-stage TASK-C` while TASK-X is testing → prompts "TASK-X is testing; unstage it? (y/n)". On yes, unstages X (X keeps its original `ready_at` so it returns to its FIFO position, head of queue), stages C. No auto-restart of X — user explicitly displaced it.

**Dependency tasks (B based on A):** `setup-worktree.sh TASK-B --base TASK-A` branches from `task-a` instead of `main`. When A closes (merges to main), `ddw-stage TASK-B` works because B already contains A's commits.

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

Both files use Claude Code subagent format: YAML frontmatter (`name`, `description`, `tools`) on top, system prompt body underneath. Existing `agents/qa.md` and `agents/developer.md` (profile-style, no frontmatter) are renamed and gain frontmatter — the body content is the system prompt.

`ddw-` prefix avoids collision with consumer-project subagents — applied to **all** plugin agents: `ddw-shaper`, `ddw-architect`, `ddw-dev`, `ddw-qa`.

**Provider portability — recommend models in body, don't pin in frontmatter.**

Claude Code can be backed by Anthropic API, Amazon Bedrock, or Google Vertex AI. Full model IDs (`claude-opus-4-7`) are provider-specific and break across backends. Aliases (`opus`/`sonnet`/`haiku`) are portable but resolve to *different versions* per provider. The plugin's portable default: **omit `model:` from frontmatter** so the subagent inherits the parent session's model.

Each agent body documents a recommended alias as guidance for users who want to override via `/agents`:

| Agent | Recommended | Rationale |
|---|---|---|
| `ddw-shaper` | `opus` | Problem-shaping needs deepest reasoning |
| `ddw-architect` | `opus` | Architectural decisions benefit from capability |
| `ddw-dev` | `sonnet` | Implementation throughput at balanced cost |
| `ddw-qa` | `sonnet` | Adversarial review effective at sonnet tier |

Recommendations live in agent body markdown (not frontmatter) — advisory only; the user's `/agents` config wins. Never use full model IDs in any plugin-shipped agent file.

### QA agent constraints:

- **Tools (frontmatter-enforced):** `Read, Grep, Glob, Bash`. **No Edit, Write, Task, TodoWrite.**
- **No memory access** — instruction-based, not enforced (Claude Code subagents still load CLAUDE.md). The agent body includes one explicit line: *"You operate as a fresh reader. Do not consult or apply any memory of prior conversations or per-user preferences."* Bias separation is a cognitive goal, not a security boundary.
- **Returns structured feedback** per the contract below.

> **Phase scope:** Phase B ships the **agent rename + frontmatter** so subagents are invokable. The structured-findings JSON contract, 3-iteration loop, dispute mechanism, and `qa_iterations` frontmatter accumulation below are **deferred to post-onboarding** — they're documented intent, not week-1 code. Until then, dev subagent invokes QA, parses prose response, and surfaces findings to the human. Iterate based on real failure modes the team hits.

### Invocation contract (Dev → QA):

Dev calls QA via the Task tool, `subagent_type: ddw-qa`, with this prompt shape:

```
Review TASK-X (file: tasks/TASK-X.md).
Iteration: <n>
Changed files (git diff vs base): <list>
Prior findings + dispute resolutions: <embedded from iteration n-1, if any>
Run commands.test from ddw.json before reporting.
Return prose report + JSON findings block per the ddw-qa contract.
```

### Return contract (QA → Dev):

QA's final message has three sections, in this order:

```markdown
## QA Report
[evidence-based prose, existing qa.md style]

## Findings
\```json
[
  {
    "id": "qa-{iteration}-{index}",
    "severity": "critical | high | low",
    "category": "AC | invariant | owasp-A01 | a11y | perf | bug",
    "file": "<path>",
    "line": <int>,
    "problem": "<description>",
    "suggestion": "<actionable fix>",
    "evidence": "<INV-ref or AC-ref or quoted code>"
  }
]
\```

## Scope Applied
- AC: yes/no
- Invariants: yes/no
- OWASP: <subset> (skipped: <subset> — reason)
- a11y: yes/skipped — <reason>
- Perf: yes/skipped — <reason>
```

Dev parses the JSON block (fenced) for routing. `id` enables the dispute mechanism. `category` lets dev triage fixes.

### Loop policy (decided):

| Setting | Value |
|---|---|
| Max iterations | **3** — then escalate to human with outstanding issues |
| Fail-closed | **Yes** — crash, malformed output, timeout → block + escalate |
| Each iteration | Prints summary to terminal (visibility + audit trail) |
| Dev disputes QA | Must justify in task file. 2+ disputes in one iteration → escalate (signal that AC isn't crisp enough) |

### Iteration state — task file frontmatter

Iteration history lives in the task file (source-of-truth aligned with §8). Frontmatter holds the index; the full findings JSON is appended to the task body's Review Log.

```yaml
qa_iterations:
  - n: 1
    result: fail
    counts: { critical: 2, high: 1, low: 3 }
    summary: "AC item 3 unmet; INV-B-...-score violated"
    disputes: []
  - n: 2
    result: fail
    counts: { critical: 0, high: 1, low: 3 }
    summary: "scoring fixed; layout still off"
    disputes:
      - finding_id: "qa-2-1"
        justification: "constraint X documented in DEC-42 §Y"
```

Survives crash, audit-trail in one place, no separate state file.

### Escalation handoff (loop exit)

Triggered when iteration count = 3 with unresolved Critical/High, OR fail-closed condition (QA crash, malformed output, timeout), OR ≥2 disputes in one iteration. Dev's final message to main session is plain text:

```
QA escalation — TASK-X
Iterations: <n>
Outstanding: <C> critical, <H> high
Reason: <max-iterations | fail-closed | excessive-disputes>
See: tasks/TASK-X.md (Review Log)
Status: ready_for_integration NOT emitted. Queue not advanced.
```

`ready_for_integration` is **not** emitted; `ddw-queue tick` is **not** called. Human takes over.

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

> **Phase scope:** **Deferred to post-onboarding.** Manual `pnpm audit` (or equivalent) suffices until first vuln triage demands the framework. The full design below is preserved as future reference. Plugin ships **one** reference adapter at most when this lands; long-tail ecosystems (npm, pip, cargo, bun, deno, gradle, …) are community contributions, never bundled.

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

### Parser strategy — normalized JSON contract

Different ecosystems emit different audit formats (`pnpm audit --json` vs `cargo audit --json` vs `pip-audit --format=json`). Plugin **does not** parse N tools — that leaks toolchain knowledge into the framework (against §2 principle).

Instead, `commands.audit` is expected to emit this normalized JSON on stdout:

```json
{
  "vulnerabilities": [
    {
      "id": "GHSA-xxxx-yyyy-zzzz",
      "package": "axios",
      "severity": "critical | high | moderate | low",
      "advisory_url": "https://...",
      "vulnerable_versions": "<1.6.0",
      "current_version": "1.5.0"
    }
  ]
}
```

`/ddw:audit` consumes this format directly — applies allowlist, severity threshold, writes `AUDIT_LOG.md`.

**Reference adapters shipped with the plugin:**

`adapters/audit-pnpm.mjs`, `adapters/audit-npm.mjs`, `adapters/audit-pip.mjs`, `adapters/audit-cargo.mjs` — each takes native tool output on stdin, emits normalized JSON on stdout. Project's `commands.audit` typically becomes:

```jsonc
"audit": "pnpm audit --json | node ${CLAUDE_PLUGIN_DIR}/adapters/audit-pnpm.mjs"
```

Unsupported ecosystem? Project writes its own adapter, same contract. Plugin maintenance scales with ecosystems we choose to bless, not with every audit tool that exists.

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

### No Claude Code hooks for verification (decided):

Earlier drafts considered a PostToolUse hook running `commands.typecheck` after every Edit as a belt-and-suspenders. **Rejected** — §4 establishes "no Claude Code hooks for workflow events; modify skill markdown instead" and that rule applies here too. Verification is a skill responsibility (the `/ddw:sendit` gate). If the gate proves unreliable in practice, revisit then — don't pre-emptively scatter logic.

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

**Rendering: at task-creation time (not view-time).**

`/ddw:task` skill emits only the conditional sections that apply, based on the author's answers (DEC linked? scope ≥ 2hr? multi-session expected?). Mid-task scope growth: `/ddw:task add-section <name>` inserts a missing section in place. View-time rendering rejected because it leaves placeholder/conditional content in raw task files — confusing in source form, and breaks `ddw-index`'s deterministic frontmatter consumption.

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
- `TASK_LOG.md`, `RETRO_LOG.md`, `MILESTONES.md`, `DECISION_LOG.md`, `PRD_LOG.md` — repurposed as generated read-only mirrors.

This subsumes the original "Insight 4 fragment + lock" approach. Single-writer per file is the simpler primitive — achieved by giving each task its own file.

### `ddw-index` contract

**Language & location:** Node, single file `scripts/ddw-index.mjs` in the plugin repo. Zero npm deps (hand-rolled YAML frontmatter parser; only string/number/array/date — no anchors, no deep nesting). Skills paper over the path via `${CLAUDE_PLUGIN_DIR}`.

**Inputs (consumer repo, paths configurable in `ddw.json`):**

```json
"paths": {
  "tasks":     "tasks",
  "decisions": "decisions",
  "prds":      "prds",
  "logs":      "logs"
}
```

Reads from both live and `archive/` subdirs of each path.

**Outputs (consumer repo, in `paths.logs`):**

Each view file gets an auto-generated header:

```markdown
<!-- AUTO-GENERATED by ddw-index. Do not edit. Edit task/DEC/PRD files instead. -->
<!-- Last regenerated: 2026-05-07T12:34:56+09:00 -->
```

| File | Source | Sort |
|---|---|---|
| `TASK_LOG.md` | task files | `closed_at desc`; in-progress at top |
| `RETRO_LOG.md` | task Retrospective sections | `closed_at desc` |
| `MILESTONES.md` | DEC files | `closed_at desc` |
| `DECISION_LOG.md` | DEC files | `decided_at desc` |
| `PRD_LOG.md` | PRD files | by status, then `created_at desc` |

**Frontmatter schemas consumed (additional fields ignored for forward-compat):**

```yaml
# task
id: TASK-A
status: in_progress | ready_for_integration | closed | abandoned
created_at: ...
started_at: ...
ready_at: ...                       # for §4 queue ordering
closed_at: ...
dec: DEC-12                         # optional
files_changed: [...]
qa_iterations: [...]                # deferred per §5 Phase scope; tolerated when present

# DEC
id: DEC-12
status: proposed | decided | in_progress | closed | parked | cancelled
prd: PRD-X                          # optional, back-link
title: "..."
created_at: ..., decided_at: ..., closed_at: ...

# PRD
id: PRD-X
status: draft | solid | parked | closed
decisions: [DEC-12, DEC-13]         # forward-link
title: "..."
created_at: ...
```

**`ddw-index` is strictly pure — no source mutations.**

`ddw-index` only reads frontmatter and writes view files. It does **not** mutate task/DEC/PRD frontmatter, does **not** move files, does **not** archive. Pure transformation. Pre-commit `--check` mode never has surprising side effects.

Task, DEC, and PRD archival is **not** ddw-index's job — `/ddw:close` and `/ddw:prd close` do that at close time.

**CLI surface:**

```
ddw-index                  # full rebuild from scratch
ddw-index --check          # exit 1 if any view file would change (pre-commit/CI gate)
ddw-index --root <path>    # consumer repo root (default: cwd)
ddw-index --dry-run        # print planned changes, write nothing
```

`--check` is the linchpin for git/CI integration: diffs planned output against on-disk and exits non-zero on drift.

**Trigger model — on-demand only:**

The plugin **does not** install hooks automatically. `/ddw:init` offers (with explicit confirmation) to add a `.git/hooks/pre-commit` running `ddw-index --check`. CI integration is a documented snippet, not pushed config. Skills never call `ddw-index` themselves.

**Error handling — fail-closed:**

Malformed frontmatter (unparseable YAML, missing required `id`/`status`) → exit 1, print file path + reason to stderr, **write no views**. No silent skips.

**Idempotency:** N runs in a row produce identical output (and identical PRD mutations once converged).

### PRD lifecycle — manual close on DEC creation

Earlier drafts had `building`/`done`/`cancelled` automation with `ddw-index` inferring status from linked DECs. **Cut.** The simpler design:

**Statuses (unchanged from today):** `draft`, `solid`, `parked`, `closed`.

**Lifecycle:** when a DEC is created from a PRD:
1. `/ddw:decision` records "DEC-X created from PRD-Y" on the PRD body
2. Owner manually sets PRD `status: closed` and moves the file to `prds/archive/`

That's it. No auto-inference, no `building` intermediate state, no `ddw-reconcile` script, no automatic file moves. PRD's job is to capture intent until a decision exists; once the decision exists, the PRD is historical.

**Linkage (still useful for `ddw-index` views):**
- PRD frontmatter: `decisions: [DEC-A, DEC-B]` — DECs that came out of this PRD
- DEC frontmatter: `prd: PRD-X` — the PRD that spawned this DEC

`ddw-index` reads these to render relationships in `PRD_LOG.md` and `DECISION_LOG.md`. It does **not** mutate them.

**Multi-DEC PRD:** owner closes the PRD when *they* decide it's done — typically after the first DEC, sometimes after several. Manual judgment, no rule.

**Skill changes:**
- `/ddw:ideate` (existing): unchanged.
- `/ddw:decision` (existing): when a DEC is created from a PRD, appends "DEC-X created" line to the PRD body and sets the DEC's `prd:` field.
- `/ddw:prd close PRD-X`: new helper that sets `status: closed` and moves the file to `prds/archive/`. Owner-invoked.

**Externally-sourced PRDs** (Notion, Linear, etc.): captured via `/ddw:ideate` with an external reference link. DDW-side artifact is the canonical lifecycle holder.

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

**`/ddw:upgrade` migration framework — deferred until first real migration exists.**

For Phase B and team-onboarding, version skew is prevented by `pluginVersion` pin + version-check on every `/ddw:*` invocation (refuses to run on mismatch). The full migration framework is only needed when the plugin actually ships a breaking schema change; build it then, not preemptively.

**When it does land, the design is:**

- `ddw.json.schemaVersion: <n>` is the canonical version pin in the consumer repo.
- Plugin ships migrations under `migrations/v{from}-to-v{to}.mjs`. Sequential only — no cross-version jumps in a single step (skipped versions run sequentially).
- **Transactional:** each step stages all changes in a temp tree, validates, then commits atomically. Mid-step crash = abort, restore working tree. No partial application.
- **Per-file frontmatter migrations are idempotent** — re-running on same file is a no-op.
- **Each upgrade step produces exactly one commit** so `git revert HEAD` is a clean rollback.
- **Downgrade is unsupported.** Rollback path = `git revert` of the upgrade commit + reinstall older plugin version. Documented, not automated.

**Migration policy for the current Neu project (decided):** existing artifacts (143 tasks, 44 decisions) are **grandfathered** in their current format. New artifacts use the new framework. Active artifacts (open DECs, `CURRENT_SPEC.md`) migrate incrementally as work continues. No big-bang migration. Archived task/DEC/PRD files are **never** touched by `/ddw:upgrade`.

---

## 11. Implementation Roadmap (Phased)

Team starts ~1 week from this plan landing. Roadmap is anchored to that.

### Phase A — Solo "nicer" test (2-3 days realistic)

Close-path wins + worktree + integration + minimal pure `ddw-index`. Solo-tested before any team scaffolding lands.

1. **Close-path wins** *(skill markdown edits, ~4h)*
   - Eliminate `CHANGE_LOG.md` from `/ddw:close` writes
   - Opt-in `CURRENT_SPEC` rewrite (default off)
   - Skip-retro rule (clean QA + < 2hr + single session)
   - Conditional task template (single file, sections deletable)
   - `/ddw:sendit` companion-test gate

2. **`ddw-index` minimal — strictly pure** *(~4-6h)*
   - Node single-file script `scripts/ddw-index.mjs`, zero deps
   - Reads task/DEC/PRD frontmatter from `paths.*`
   - Writes: `TASK_LOG.md`, `RETRO_LOG.md`, `DECISION_LOG.md`, `MILESTONES.md`, `PRD_LOG.md`
   - **No** mutations of source files. **No** auto-archive. `--check` mode for pre-commit.

3. **PRD lifecycle simplified** *(~1h)*
   - `/ddw:decision` appends "DEC-X created" line to PRD body, sets `prd:` field on DEC
   - New `/ddw:prd close PRD-X` helper: sets `status: closed`, moves to `prds/archive/`
   - Drop `building`/`done`/`cancelled` statuses entirely

4. **Worktree + integration scripts** *(~6-8h)*
   - `scripts/setup-worktree.sh` minimal: `git worktree add`, symlinks, `PORT_OFFSET` count-based, `--base` flag
   - `scripts/ddw-stage`, `scripts/ddw-unstage`, `scripts/ddw-queue` (tick subcommand), `scripts/ddw-integration-status`, `scripts/ddw-integration-reset`
   - `.ddw/integration.json` gitignored, per-machine
   - `ready_at` field written by `/ddw:sendit`

5. **Frontmatter authority matrix** *(~30min, doc only)*
   - Written into new §13 of this doc; no enforcement code yet

### Phase B — Team build (1 day target, ~1.5 realistic)

Layers team-essential structure on top of Phase A:

6. **Memory → CLAUDE.md via `@import`** — write the import line into consumer's CLAUDE.md from `/ddw:init`
7. **`ddw.json` verbs** — `commands.{install,dev,typecheck,test,lint}`, `testFilePattern`, `lockfile`. Refactor every skill that hardcodes `pnpm`/`tsc` to read from `ddw.json`.
8. **`ddw-` agent rename + frontmatter** — rename `qa.md`→`ddw-qa.md` etc., add YAML frontmatter (name, description, tools), embed recommended-model annotation in body
9. **JSON schema files** — `schemas/ddw-task.schema.json`, `ddw-dec.schema.json`, `ddw-prd.schema.json`, `ddw.json.schema.json`. Minimal but real. `ddw-index` validates against them.
10. **`pluginVersion` field + version-check** — `/ddw:*` skills check `ddw.json.pluginVersion` against installed plugin version at start; refuse on mismatch (with `DDW_SKIP_VERSION_CHECK=1` escape hatch)
11. **Repo-level model pins** — `ddw.json.agents.{shaper,architect,dev,qa}.model` overrides; agent body reads from ddw.json first, then `/agents`, then inherit

### Phase C — Team-mode solo test (2-3 days)

Hit Phase B alone in team-mode workflow. Find sharp edges. Fix. Update GUIDE.md and write a short ONBOARDING.md walkthrough.

12. **GUIDE.md update** — reflect the new framework end-to-end
13. **ONBOARDING.md** — day-1 walkthrough for a new teammate
14. **One-time triage of stale `proposed` DECs and `kiosk-tenant-switcher`**
15. Stabilization gate before onboarding (typecheck + grep for known failure modes)

### Deferred — build post-onboarding when triggered

Not in the team-launch scope. Documented in earlier sections as future reference:

- `/ddw:audit` framework (§6) — manual `pnpm audit` until first vuln triage
- `/ddw:doctor` diagnostic — when team hits opaque weirdness
- Plugin CI + golden-file tests + fixture repo
- Migration framework (§10) — built with first real migration
- Dev/QA structured-findings JSON contract, 3-iteration loop, dispute mechanism (§5) — basic prose-response QA suffices for now
- Long-tail audit adapters (npm/pip/cargo/bun/deno/gradle/…) — community contributions, never bundled
- Plugin-side observability/metrics

### Cut — don't build

- Marker-block CLAUDE.md surgery (replaced by `@import`)
- Worktree slot/port assignment math (count-based for now)
- Windows `cp` fallback for syncFiles (macOS/Linux only)
- `worktree.syncFiles` complex orchestration — keep simple symlink only
- PRD `building`/`done`/`cancelled` automation + `ddw-reconcile`
- DEC dispute path — revisit only if team friction surfaces it

i18n, observability, and notification upgrades stay parked.

---

## 12. Reversibility & Safeguards

Every decision in this plan must be rewindable — at the code level and, within reason, at the operational level. The honest accounting:

### Trivially reversible (just `git revert`)

- All plugin code edits (scripts, agents, skills, templates)
- Agent file rename (`qa.md` → `ddw-qa.md`)
- New `ddw.json` fields (additive — old configs still parse)
- Generated views (`TASK_LOG.md` etc. — regenerated from source on next ddw-index run)
- Branch convention (`task-{id}` — old branches keep working; new ones just follow the rule)
- State files (`.ddw/integration.json` — delete = reset)

### Reversible with minor cleanup

- **PRD archive moves** — `git mv` back, or just `mv` if uncommitted. Files always exist at *some* path.
- **Task frontmatter additions** (`ready_at`, etc.) — strictly additive. ddw-index tolerates missing fields.
- **CLAUDE.md `@import` line** — single line, removable in one edit.

### Reversible with operational friction

- **`CHANGE_LOG.md` elimination** — file-level reversible (re-add template, re-add write to `/ddw:close`). Team-shared consumer repos where everyone deleted theirs need coordinated rollback. Friction is social, not technical.
- **Plugin schema upgrade** (v_n → v_{n+1}) — no first-class **down**-migration. Rollback path is `git revert` of the upgrade commit in the consumer repo. Works cleanly because each upgrade step is a single commit.

### Effectively irreversible

None at the code level. The only honest cost is **behavioral memory**: once a team has internalized the new flow, reverting means re-training. The §9 kill criterion (2-week window) is calibrated against this — short window, low people-cost on revert.

### Safeguards baked into the design

To keep "rewindable" honest, these constraints apply across all picks:

1. **`/ddw:upgrade` refuses dirty trees.** Before mutating frontmatter or moving files, require a clean working tree (or `--force` with explicit confirmation).
2. **`ddw-index` writes only via explicit invocation.** Pre-commit `--check` exits 1 on drift; user runs `ddw-index` manually, sees the diff, commits. View regen never sneaks in unobserved.
3. **`setup-worktree.sh` checks branch collisions.** If `task-{id}` already exists, error out — never reuse a stranger's branch.
4. **`ddw-stage` warns before destructive merge.** If integration worktree has uncommitted changes, refuse.
5. **Plugin migrations are commit-isolated.** Each `/ddw:upgrade` step produces one commit. `git revert HEAD` is a clean rollback.

---

## 13. Frontmatter Authority Matrix

Every mutable frontmatter field has exactly **one writer**. All other code paths read only. Violations are bugs.

### Task frontmatter

| Field | Writer | Notes |
|---|---|---|
| `id`, `title`, `created_at` | `/ddw:task` (creation) | Never re-written |
| `dec`, `files_changed` (initial) | `/ddw:task` | At creation |
| `touches_db` | task author (manual at creation) | Read by `/ddw:auto` for sendit serialization (Row 4); see §14 |
| `started_at` | dev subagent | When work begins in worktree |
| `status: in_progress` | `/ddw:task` | At creation |
| `status: ready_for_integration` | `/ddw:sendit` | Gate-passed flip |
| `status: review_and_bugfix` | `/ddw:review` / `/ddw:sendit` | After implementation + review handoff |
| `status: done`, `closed_at` | `/ddw:close` (local mode) | At close |
| `status: in_review` | `/ddw:pr` | **github-pr mode only.** Set after `gh pr create` succeeds. Local-mode tasks skip this state entirely. Flow: `done → in_review` |
| `status: archived` | `/ddw:close` (post-PR-merge re-run) | github-pr mode: terminal after PR merged on GitHub |
| `status: abandoned` | `/ddw:close --abandon` | Explicit |
| `ready_at` | `/ddw:sendit` | Same write as `status: ready_for_integration` |
| `files_changed` (updates) | dev subagent / `/ddw:close` | Append-on-edit |

**Full status flow:**
- **Local mode** (`merge.mode: "local"`): `planned → in_progress → review_and_bugfix → done → archived`
- **GitHub-PR mode** (`merge.mode: "github-pr"`): `planned → in_progress → review_and_bugfix → done → in_review → archived` (the `done → in_review` transition is the only mode-conditional state in the flow; `/ddw:pr` is the sole writer)

Read-only consumers: `ddw-index`, `ddw-stage`, `ddw-unstage`, `ddw-queue`, `/ddw:doctor`.

### Task body sections (treated as authoritative state)

| Field | Writer | Notes |
|---|---|---|
| `**PR:** <url>` | `/ddw:pr` | github-pr mode only. Written after `gh pr create` returns. Used as the audit-trail link by `/ddw:close` on the post-merge re-run. Body line, not frontmatter — mirrors the PRD `## Decision Backlog` pattern below. |
| `## Implementation Summary` | dev subagent | Non-empty triggers Row 3 review in `/ddw:auto` |
| `## Review Log` (QA verdict) | `/ddw:review` / `qa` agent | Latest verdict gates Row 2 advancement in `/ddw:auto` |
| `## Owner Review Checklist` | task author (creation) / `/ddw:auto` Row 2 (auto-tick) / owner (manual ticks) | Must be fully `[x]` before `/ddw:close` or `/ddw:pr` |
| `## Work Log` | dev subagent / `/ddw:sendit` / `/ddw:review` / `/ddw:close` / `/ddw:pr` / `/ddw:auto` Row 2 | Append-only; every state-transitioning writer appends a timestamped entry |

### DEC frontmatter

| Field | Writer | Notes |
|---|---|---|
| `id`, `title`, `created_at`, `prd` | `/ddw:decision` (creation) | At creation |
| `status: proposed → decided` | `/ddw:decision` | When confirmed |
| `decided_at` | `/ddw:decision` | Same write as `decided` |
| `status: decided → in_progress` | `/ddw:task` (first task linked) | Auto-flip on first task creation |
| `status: in_progress → closed` | `/ddw:close` (last task) | When last linked task closes |
| `closed_at` | `/ddw:close` | Same write |
| `status: parked / cancelled` | `/ddw:decision park / cancel` | Owner-driven |

Read-only consumers: `ddw-index`, all task skills, `/ddw:doctor`.

### PRD frontmatter

| Field | Writer | Notes |
|---|---|---|
| `id`, `title`, `created_at` | `/ddw:ideate` (creation) | Never re-written |
| `status: draft / solid / parked` | Owner via `/ddw:prd` helpers | Manual transitions |
| `status: closed` | `/ddw:prd close` | Owner-invoked; refuses if `## Decision Backlog` has `(proposed)` entries |
| `decisions: [...]` | `/ddw:decision` | Append-on-DEC-creation |

### PRD `## Decision Backlog` (body section, but treated as authoritative state)

| Entry state | Writer | Notes |
|---|---|---|
| Initial population (entries with `(proposed)`) | `/ddw:ideate` step 5.5 + step 8 | One narrow decision per entry — ADR-sized |
| `(proposed) → (decided → DEC-id)` | `/ddw:decision` action D | Auto-flip when matching DEC is created (From-PRD or standalone with append-fallback) |
| `(proposed) → (deferred)` | `/ddw:prd defer <PRD-id> <slug>` | Owner-driven |
| `(proposed) → (rejected)` | `/ddw:prd reject <PRD-id> <slug>` | Owner-driven |

`/ddw:prd close` is the gatekeeper — refuses to close while any entry is still `(proposed)`. This forces every decision-question to reach a resolution (decided / deferred / rejected) before the PRD's job is considered done.

Read-only consumers: `ddw-index`, `/ddw:doctor`. **`ddw-index` does not mutate PRD frontmatter** — pure reader.

### `ddw.json`

| Field | Writer | Notes |
|---|---|---|
| All fields | Owner / `/ddw:init` / `/ddw:upgrade` | Manual or skill-driven; never written by runtime scripts |

### `.ddw/integration.json`

| Field | Writer | Notes |
|---|---|---|
| `testing` | `ddw-stage` (set), `ddw-unstage` (clear) | Gitignored; per-machine; only these two scripts ever write |

### The rule

If you find yourself wanting to write a frontmatter field from a script not listed here, **stop**. Either: extend this table with a new authoritative writer, or refactor so the existing writer owns the change. Two writers on the same field is a coupling bug regardless of whether it shows up in testing.

---

## 14. Overnight Mode — `/ddw:auto`

**The idea:** You make a few decisions, go to bed. Claude does the implementation work all night. You wake up to a list of what shipped and a short list of things that needed your call. No prompts waiting at 3am.

### What it does

Looks at the project state, finds work that's ready to do, does it, picks the next thing, repeats. When something needs your judgment (a real architectural call, anything destructive, a third-party API), it writes a note for the morning and moves on. Never sits and waits for you.

### What it won't do

- Make architectural decisions for you. If a decision is still in `proposed`, it stays there until you weigh in.
- Replace `/ddw:sendit`, `/ddw:qa`, `/ddw:close`, etc. It runs those in turn, doesn't reinvent them.
- Auto-merge to `main`. Stops at the integration worktree. Final merge is always you.

### How to run it

```
/ddw:auto [--budget tasks=N,minutes=M] [--level self-driving|co-pilot|advisor] [--dry-run]
```

Defaults: 20 tasks max, 8 hours max, `self-driving`.

One long session — not a cron job. Cron means re-loading everything every time, which is slow and wasteful.

### How it picks what to do next

Each round, it looks at the whole project and asks: "what's the most valuable thing I can do right now?" The answer follows this order — finish what's almost done before starting new work:

| Order | When this is true… | …do this |
|---|---|---|
| 1 | A task passed review, just needs closing | `/ddw:close` (if tests + smoke green) |
| 2 | A task is ready for integration | Stage it, run smoke |
| 3 | A task is in `review_and_bugfix` and QA already passed | Move to `done` (only on `self-driving`) |
| 4 | A task is built but QA hasn't run | `/ddw:qa` |
| 5 | A task is `planned` and there's free capacity | `/ddw:sendit` |
| 6 | A decision is `decided` but no tasks yet | `/ddw:task` |
| 7 | A decision is still `proposed` | **Skip** — write a note for you |

Ties break by oldest first.

Each task runs in its own helper agent so the main orchestrator stays focused. Same idea as `/clear` between tasks during the day.

### Three speed settings

- **`advisor`** — picks the next thing, writes it down, stops. You drive. (Closest to today's flow.) No rows in the §5.3 table fire for dispatch.
- **`co-pilot`** — runs the build-and-test work (rows 3 review, 4 sendit) and surfaces pending decisions (row 6). Stops short of anything that closes a task (row 1), advances a task to `done` (row 2), or creates new tasks from decisions (row 5).
- **`self-driving`** — runs everything: rows 1–6, with the safety rules below.

The authoritative gating table lives in `skills/auto/SKILL.md` step 5.3 — keep both in sync if either moves.

### Never wait — write a note instead

If any of these come up, the task gets dropped to the morning list and the loop moves on:

- **Real architectural choice** — helper says it can't resolve a spec/code conflict on its own.
- **Destructive operation** — schema migration, `rm -rf`, force-push, secret rotation, removing a dependency, or anything else listed in `auto.confirm_on`.
- **Third-party API call** — anything that hits external services without a recorded dry-run.
- **QA failed twice** — first fail, retry with the QA notes. Second fail, drop to morning.
- **Tests or smoke still red after one fix attempt** — same one-retry rule.
- **Helper takes too long** — over `auto.subagentTimeoutMinutes` (20 by default).

Every drop writes: task id, why, last thing it tried, link to the helper's transcript.

### Smoke test + browser check

After a task ships, run a smoke test. Required for anything touching app or service code.

```jsonc
// ddw.json additions
{
  "smoke": {
    "command": "pnpm smoke",
    "timeoutMinutes": 5,
    "browser": {
      "mode": "playwright-or-note",   // "playwright" | "playwright-or-note" | "note-only"
      "checks": [
        { "url": "http://localhost:3000/health", "expect": "status=200" },
        { "url": "http://localhost:3000/", "expect": "selector=#app" }
      ]
    }
  }
}
```

For browser checks, try this in order:

1. If Playwright is hooked up, drive Chrome through the checks. Pass/fail is final.
2. Otherwise, use `curl` for any HTTP status checks (still final). Things that need to look at the page get pushed to step 3.
3. Otherwise, mark the task `done` but add a "check this in Chrome" line to the morning list — URL, what to look for, screenshot if there is one.

`mode: "note-only"` skips 1 and 2 — for projects with no web UI.

If smoke fails: unstage the task, put it back at the front of the integration line, log it.

### How many at once

```jsonc
// ddw.json additions
{
  "auto": {
    "maxConcurrent": null,            // null → min(worktree.maxConcurrent * 2, 4)
    "subagentTimeoutMinutes": 20,
    "consecutiveErrorLimit": 3,
    "confirm_on": ["destructive", "architecture", "external-side-effects"],
    "level": "self-driving"
  }
}
```

Daytime cap is 3 worktrees on the reference setup. Doubling to 6 starves CPU and ports, so hard cap at 4 overnight. Tunable. Only `/ddw:sendit` runs in parallel; QA, close, and architect run one at a time (they're fast).

### When it stops

Any of these and the orchestrator writes a final summary and exits:

- Hit the task count or time budget.
- No more workable items (queue empty, nothing `planned`, no `decided`-without-tasks).
- 3 hard errors in a row.
- A `.ddw/STOP` file appears at the repo root.
- You hit Ctrl-C.

### Logs (full trail, no exceptions)

```
.ddw/logs/auto/<run-id>/
  run.json         # settings, start/end time, why it stopped
  tick.log         # one line per round: timestamp, action, task id, result
  inbox.md         # the morning summary (this is what you read first)
  tasks/
    TASK-id.md     # what the helper agent did, full transcript
  smoke/
    TASK-id.json   # smoke result, browser checks, screenshots if any
```

`run-id` is the start timestamp (e.g. `2026-05-09T22-00-00Z`). Gitignored, kept forever locally.

### Morning summary

`.ddw/logs/auto/<run-id>/inbox.md`, also linked at `.ddw/inbox/latest.md` so it's easy to find.

```markdown
# DDW Auto Run — 2026-05-09 (8h12m)

## Shipped (12)
- TASK-A1 — auth refactor → closed at 23:14
- TASK-A2 — rate-limiter middleware → closed at 23:48
- ...

## Check in Chrome (3)
- TASK-B1 — login form: open http://localhost:3000/login, check error toast renders red
- ...

## Decisions waiting on you (2)
- DEC-014 (proposed) — caching strategy for the search index
  Why: architectural — Redis vs in-memory needs your call
- DEC-015 (proposed) — error tracking vendor

## Stuck (4)
- TASK-C1 — schema migration → destructive op
  Last tried: stopped before `db:push`
- TASK-C2 — payment integration → hits Stripe (no dry-run set up)
- TASK-D1 — QA failed twice (acceptance criterion #3); see tasks/TASK-D1.md
- TASK-D2 — smoke red after one fix attempt; see smoke/TASK-D2.json

## Hard errors (0)
```

That file is the only thing you have to read with coffee. Everything else is there if you want to dig.

### Frontmatter & schema changes

No new task or DEC fields. The orchestrator only reads existing state and writes to its own log directory.

### What ships when

**Phase A (week 1):** `/ddw:auto` itself, rows 4–5 only (qa + sendit), `co-pilot` only, browser `note-only` mode, full logs and morning summary. **No** auto-close, **no** auto-stage, **no** Playwright. Goal: prove the loop works on a real overnight run.

**Phase B:** Add row 1 (auto-close) and row 2 (auto-stage), the `self-driving` level, the `playwright-or-note` browser mode, the `.ddw/STOP` file.

**Phase C:** Add row 3 (auto-advance review) and row 6 (auto-create tasks from decisions), full Playwright with screenshots.

Phase A is most of the value on its own: ten tasks ship overnight, you wake up to a summary.

### Rejected ideas

- **Cron loop.** Reloads everything each round — slow and expensive. One long session wins.
- **Auto-decide architecture.** Defeats the whole point of DDW. Decisions stay yours.
- **Auto-merge to main.** Last step is always a human.
- **Slack or email notifications.** Out of scope. The morning summary file is enough. Add later if it isn't.

---

## 15. Trunk-based merge — drop integration staging

**Status:** done (commit 9c52492 — 2026-05-09; surfaced from gearscrape end-to-end run)

The integration-staging machinery (`worktree.integrationDir`, `ddw-stage`, `ddw-unstage`, `ddw-queue`, `ready_for_integration` status, auto Row 2 auto-stage) is overengineered for the realistic DDW user profile and adds maintenance surface that produced ~5 bugs in a single overnight run (none of which were the user's fault).

### What we ran tonight that exposed the problem

A real overnight `/ddw:auto` run on a project with `smoke.command: null`. Five tasks, four success-shipped, one autonomy-blocked. Issues encountered:

1. `setup-worktree.sh` had the same `ddw.json` discovery bug as queue scripts — silently fell back to plain branch checkout for every task. Fixed.
2. `ddw-queue tick` failed with "integration worktree not found" because no skill bootstrapped `.worktrees/integration` automatically.
3. The `require-active-task` hook blocks writes to `.worktrees/<task-id>/` because `DDW_PROJECT_DIR` resolves to the main repo and the worktree's task-status flip is invisible to it.
4. The queue script reads task status from main's working tree, which is stale until merge — making the staging flow effectively useless until you merge first (defeating the point).
5. After successful staging + smoke green, there's no defined transition from `staged` to `done`. Owner has to flip manually.
6. `.env.ddw` (per-worktree PORT_OFFSET) and `.worktrees/` were not gitignored in the project's gitignore. Both leaked into commits.

Most of these are bugs in the staging story itself, not in the per-task worktree concept. Per-task worktrees worked fine once the discovery fix landed.

### The simpler model

Adopt **trunk-based development with rebase-and-merge** (the prevailing pattern at Google, Meta, Stripe, Vercel, Linear, and most modern startups). The orchestrator becomes the merge sequencer:

```
sendit → review_and_bugfix → review CLEAR → done
close →
  rebase task branch onto base (origin/base if remote, else local)
  re-run tests in worktree (alignment-after-rebase guard)
  → if local mode: merge --no-ff into base → smoke if configured → revert if smoke red → archive
  → if pr mode:    print 2 manual commands (git push + gh pr create) and stop.
                   Owner runs them via their preferred tooling (gh, IDE, GitHub Desktop, shell alias).
                   Re-run /ddw:close after PR merges → close detects task branch is in base → archive.
```

Per-task worktrees stay (they're the parallelism + isolation story, distinct from integration staging).

### Configuration — one knob

```json
"merge": { "mode": "local" }   // or "pr". Default "local".
```

That's it. No `baseBranch` (default to `main`, override via gitconfig), no `rebaseBeforeMerge` (always rebase — when would you not?), no `smokeAfterMerge` (`smoke.command`'s null-check already covers this), no `squash` flag (solo: `--no-ff`; PR: GitHub button decides), no `tool` flag (gh CLI hardcoded; ~95% of users; YAGNI for glab/tea), no `auto_merge` flag (set on the GitHub repo, not in DDW), no `draft`/`labels`/`reviewers` (every team has conventions; encoding them in `ddw.json` becomes a maintenance burden — let teams wrap close in their own shell function).

### Status semantics — no new states

Keep the existing pipeline: `planned → in_progress → review_and_bugfix → done → archived`. **No new states for PR mode.**

In PR mode, `done` just means "ready to ship via PR." The task file stays in `tasks/` (not `tasks/archive/`) until the PR merges. Archival is delayed, not state-machine-augmented. The PR URL lives in task frontmatter:

```
**PR:** https://github.com/owner/repo/pull/123
```

### No new directories, no new skills

- No `tasks/in_review/`. Use existing `tasks/` for "done with PR pending."
- No `ddw:check-prs` skill. The `auto` skill's pipeline scan adds ~10 lines to: for each task with `Status: done` + `**PR:**` URL, run `gh pr view <url> --json mergedAt`. If merged → archive + delete branch. If not → leave alone.

### Auto skill behavior per mode

| Mode | Auto behavior |
|---|---|
| `local` | Full pipeline, runs to queue empty. Each `done` task is closed (rebase + merge) before next dispatches. |
| `pr` | sendit → review → close (rebase + test, then print push + `gh pr create` instructions). Stops there. Owner pushes/PRs manually. Re-running `/ddw:close` after PR merges archives the task. No `gh pr view` polling — by design (see "What's NOT in this design" below). |

### What gets deleted from the plugin

- `worktree.integrationDir` config key
- `.ddw/integration.json` (integration state file)
- `scripts/ddw-stage`, `scripts/ddw-unstage`, `scripts/ddw-queue`, `scripts/ddw-integration-status`, `scripts/ddw-integration-reset`
- `skills/integration/`, `skills/queue/`
- `auto` skill Row 2 (auto-stage) and the `staged` shipped subtype
- `sendit` skill step 14's `ready_for_integration` status flip and queue tick
- `close` skill step 13d's integration.json clear (replaced by the new step 13 Merge)

### What gets added (small, additive)

- `merge.mode` config key (one line in `ddw.json.example`)
- `close` skill: rebase + merge in local mode; rebase + push + record PR URL in PR mode (~30 lines added; ~50 lines deleted from the dropped integration handlers)
- (no auto-skill changes for PR mode — see "What's NOT in this design" below)

Net (actual): ~940 lines deleted, ~232 added. Plugin shrinks ~700 lines.

### What's NOT in this design (and why)

The first draft of this proposal had a "Phase B" for full PR automation: close runs `git push` + `gh pr create` for the user, stores the PR URL, and an `auto`-time poll of `gh pr view` archives the task when GitHub reports merged.

Cut. Reasons:

- It saves the user **two commands per task** (push + pr-create) at the cost of ~30 lines of code + maintenance forever (gh CLI auth, error handling, tooling skew when teams use Graphite/Sapling/`hub`/IDE pickers).
- Most modern teams already have IDE / shell-alias / GitHub-Desktop helpers for opening PRs. DDW doing it too is the 6th tool fighting the other 5.
- The poll-and-archive loop adds an `auto`-skill responsibility that runs on every invocation, even for solo projects that never set `merge.mode: "pr"`.
- The current PR-mode (print 2 commands, stop, archive on re-run) is **already a working PR mode**. It's not pretty, but it works and stays out of teams' way.

If a real team-mode user shows up and asks "make this automatic," the change is local: ~30 lines in `close`, no new state. Add it then. Until then, no Phase B. The plan is the plan.

### Rejected ideas (the slop the first draft had)

The first iteration of this proposal had **11 config keys** (`baseBranch`, `rebaseBeforeMerge`, `smokeAfterMerge`, `squash`, `auto_merge`, `draft`, `labels`, `reviewers`, `team_reviewers`, `tool`, `delete_branch_after_merge`), **2 new status states** (`pr_open`, `merged`), **1 new directory** (`tasks/in_review/`), and **1 new skill** (`ddw:check-prs`). Hard-thinking review cut it to **1 config key, 0 new states, 0 new directories, 0 new skills.**

What got rejected and why:

- **`tool: "gh" | "glab"` abstraction**: ~95% of DDW users are on GitHub. No GitLab user has asked. Hardcode `gh`, add `glab` in 20 lines if/when someone needs it. Designing the abstraction now is speculation.
- **`auto_merge: true/false`**: GitHub's repo settings or `gh pr merge --auto` already cover this. DDW doesn't need a parallel switch.
- **`labels`, `reviewers`, `team_reviewers`**: Every team has conventions, those conventions change as people join/leave. Encoding them in `ddw.json` becomes a maintenance burden. Let teams wrap `close` in a shell alias.
- **`draft: true/false`**: Niche. Default false is fine; if needed, owner can `gh pr ready` after the fact.
- **`squash: true/false`**: Local mode uses `--no-ff` (clean history). PR mode: GitHub's "Squash and merge" button decides, not gh CLI. The flag was meaningless.
- **`rebaseBeforeMerge: true/false`**: When would anyone not rebase before merge? Never. Drop the flag, always rebase.
- **`smokeAfterMerge: true/false`**: `smoke.command: null` already disables smoke. A second flag duplicates.
- **`baseBranch`**: Defaults to `main`. Override path via git config (`init.defaultBranch`) or future `merge.baseBranch` if a real user shows up with a non-main convention. Today: hardcode.
- **New status states `pr_open`, `merged`**: Adds forks in every skill that touches state. Not necessary — `done` already means "implementation complete; archival pending merge confirmation." PR-merge transition is data-driven (poll `gh pr view`), not state-machine-driven.
- **`tasks/in_review/` directory**: The task is `done`, just not yet archived. Same directory it was in. Don't introduce new locations to encode "waiting" — the data (PR URL + merge status) is enough.
- **`ddw:check-prs` skill**: Polling logic is 10 lines inside `auto`'s pipeline scan. Doesn't need its own skill, doesn't need its own invocation.

The simplicity test for any DDW config key: **"would anyone realistically set this to the non-default value?"** If the honest answer is "maybe one team in 50," cut it.

### Frontmatter & schema changes

One optional addition in PR mode: `**PR:** <url>` line in task frontmatter, written by `close` after `gh pr create` succeeds. Ignored in local mode.

No changes to DEC, PRD, or `ddw.json` schema beyond `merge.mode`.

### Status

Shipped 2026-05-09 in plugin commit `9c52492`. Net diff: +232 / −940 lines. The plugin is ~700 lines smaller. Pipeline simplifies to `planned → in_progress → review_and_bugfix → done → archived`. No new states. No new directories. No new skills. One config key (`merge.mode`).

Local mode is fully automated end-to-end. PR mode prints two manual commands and stops, with archive-on-re-run handling the rest. There is no follow-on phase.
