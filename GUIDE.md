# DDW — Detailed Guide

Full workflow reference, architecture details, hook diagrams, and agent profiles.

For a quick overview, see [README.md](README.md).

---

## How It Works

```
                          ┌─────────────────────────────────────────┐
                          │           DDW Lifecycle                  │
                          └─────────────────────────────────────────┘

          ┌──────────┐        ┌────────────┐        ┌──────────┐
          │  IDEATE   │───────>│  DECISION  │───────>│   TASK   │
          │ (optional)│        │            │        │          │
          └──────────┘        └────────────┘        └──────────┘
           /ddw:ideate         /ddw:decision         /ddw:task
           Shaper agent        Architect agent        ─ scope
           ─ shape idea        ─ system design        ─ acceptance
           ─ produce PRD       ─ constraints          ─ criteria
                               ─ task breakdown       ─ dependencies
                               ─ risk assessment
                                      │
                          Status: proposed → decided
                                      │
                          ┌───────────┘
                          │  (all tasks created — hook enforced)
                          ▼
                    ┌──────────┐
                    │  SENDIT  │
                    │          │
                    └──────────┘
                     /ddw:sendit
                     Developer agent
                     ─ create feature branch
                     ─ implement spec-first
                     ─ minimal blast radius
                     ─ write unit + integration tests
                            │
                   Status: planned → in_progress
                            │
                            ▼
                    ┌──────────┐
                    │  TESTS   │
                    │          │
                    └──────────┘
                     ─ unit tests for functions
                     ─ integration tests for features
                     ─ all tests must pass
                            │
                            ▼
                    ┌──────────┐        ┌──────────────────┐
                    │    QA    │──BLOCKED──> Fix & re-run   │
                    │          │        └──────────────────┘
                    └──────────┘                │
                     /ddw:qa                    │
                     QA agent                   │
                     ─ score acceptance criteria │
                     ─ invariant regression sweep
                     ─ verdict: CLEAR or BLOCKED
                            │
                          CLEAR
                            │
                            ▼
                    ┌──────────┐
                    │  REVIEW  │
                    │          │
                    └──────────┘
                     /ddw:review
                     ─ run QA (if not done)
                     ─ run tests
                     ─ owner review checklist
                            │
                   Status: → review_and_bugfix
                            │
                     Owner verifies ✓
                            │
                   Status: → done
                            │
                            ▼
                    ┌──────────────┐
                    │ INTEGRATION  │
                    │              │
                    └──────────────┘
                     /ddw:sendit step 14 → ready_for_integration + Ready-At
                     ddw-queue tick     → FIFO stage into integration WT
                     ddw-stage          → git merge --no-ff
                     manual smoke-test   in .worktrees/integration/
                            │
                            ▼
                    ┌──────────┐
                    │  CLOSE   │
                    │          │
                    └──────────┘
                     /ddw:close
                     ─ update CURRENT_SPEC (opt-in)
                     ─ run drift detection
                     ─ retrospective (auto-skipped on clean+short+single-session)
                     ─ archive task / auto-close DEC if last task
                     ─ clear integration.json + ddw-queue tick
                     ─ ddw-index regenerates 4 log views
```

**PRD lifecycle (parallel track):** `/ddw:ideate` creates a PRD → `/ddw:decision` references it and appends DEC IDs to the PRD's `Decisions:` array → owner runs `/ddw:prd close PRD-id` once all relevant DECs exist (sets `Status: closed`, moves to `prds/archive/`).

## Status State Machine

```
  PRD:       draft ──→ solid ──→ closed ──→ (archived)
               │           │
               └──→ parked │
                           └──→ /ddw:decision links a DEC
                                /ddw:prd close marks closed

  Decision:  proposed ──→ decided ──→ in_progress ──→ closed ──→ (archived)
                  │           │            (auto-flips when      │
                  │           │             first task created)  │
                  │           └──→ cancelled / parked            │
                  └──→ rejected                                  │
                                                                 │
                                              (auto-closes when last
                                               linked task closes)

  Task:      planned ──→ in_progress ──→ ready_for_integration ──→ closed ──→ (archived)
                  │            │                  │
                  │            │           queued by ddw-queue,
                  │            │           merged by ddw-stage
                  │            │
                  └──→ abandoned (via /ddw:close --abandon)
```

See [§13 of `enhancement.md`](enhancement.md#13-frontmatter-authority-matrix) for the full frontmatter authority matrix — every field has exactly one writer.

## Enforcement Layer

DDW has two layers of enforcement:

```
  ┌─────────────────────────────────────────────────────┐
  │  SOFT ENFORCEMENT (instructions)                     │
  │  CLAUDE.md tells Claude: "follow the workflow"       │
  │  ─ Can be persuaded with enough effort               │
  ├─────────────────────────────────────────────────────┤
  │  HARD ENFORCEMENT (hooks)                            │
  │  Shell scripts that exit 2 → write blocked           │
  │  ─ Cannot be bypassed through conversation           │
  │  ─ No amount of prompt engineering changes this      │
  └─────────────────────────────────────────────────────┘
```

### Hook Flow Diagram

```
  User/Claude attempts a Write or Edit
           │
           ▼
  ┌─ PreToolUse ─────────────────────────────────────┐
  │                                                    │
  │  validate-datetime ──── placeholder? ── exit 2 ──> BLOCKED
  │         │ ok                                       │
  │  require-active-task ── no task? ───── exit 2 ──> BLOCKED
  │         │ ok                                       │
  │  require-all-tasks ──── missing? ───── exit 2 ──> BLOCKED
  │         │ ok                                       │
  │  check-deps-done ────── deps not done? exit 2 ──> BLOCKED
  │         │ ok                                       │
  │  require-review ──────── no review? ── exit 2 ──> BLOCKED
  │         │ ok                                       │
  └─────────┼──────────────────────────────────────────┘
            │
            ▼
       Write/Edit executes
            │
            ▼
  ┌─ PostToolUse ────────────────────────────────────┐
  │                                                    │
  │  check-task-complete ── all AC done? ── prompt close
  │  create-decided-tasks ─ decided? ────── prompt tasks
  │                                                    │
  └────────────────────────────────────────────────────┘
```

## Agent Profiles

Four role-separated mindsets. Each is loaded at the right phase — they define **how to think**, not what to check.

```
  ┌────────────┐   ┌────────────┐   ┌────────────┐   ┌────────────┐
  │   SHAPER   │   │  ARCHITECT │   │  DEVELOPER │   │     QA     │
  │            │   │            │   │            │   │            │
  │ Thinking   │   │ System     │   │ Spec-first │   │ Adversarial│
  │ partner    │   │ designer   │   │ implementer│   │ evaluator  │
  │            │   │            │   │            │   │            │
  │ Draws out  │   │ Reads      │   │ Reads task │   │ Does NOT   │
  │ ideas      │   │ broadly:   │   │ guardrails │   │ read dev's │
  │ Identifies │   │ codebase,  │   │ invariants │   │ Context    │
  │ gaps       │   │ decisions, │   │ spec       │   │ Packing or │
  │ No jargon  │   │ retro log, │   │            │   │ Impl       │
  │            │   │ spec       │   │ Minimal    │   │ Summary    │
  │            │   │            │   │ blast      │   │            │
  │ /ideate    │   │ /decision  │   │ radius     │   │ Judges     │
  │            │   │ /architect │   │            │   │ code vs    │
  │            │   │            │   │ /sendit    │   │ spec only  │
  │            │   │            │   │            │   │            │
  │            │   │            │   │            │   │ /qa        │
  │            │   │            │   │            │   │ /review    │
  └────────────┘   └────────────┘   └────────────┘   └────────────┘
```

**Key design: information separation.** QA never reads the developer's justifications — it judges the code against the spec independently. This prevents confirmation bias.

## Automated QA

Two-pass evaluation runs before every review:

```
  /ddw:qa
     │
     ├── Pass 1: Acceptance Criteria
     │      │
     │      ├── code-grep ──── grep for pattern in code
     │      ├── code-review ── read & reason about code
     │      ├── spec-compare ─ compare code vs spec value
     │      └── manual ─────── SKIP (flagged for human)
     │      │
     │      └── Each AC: PASS / FAIL / SKIP
     │
     ├── Pass 2: Invariant Regression Sweep
     │      │
     │      └── Every INV-* rule in INVARIANTS.md
     │             │
     │             └── PASS / REGRESSION
     │
     └── Verdict
            │
            ├── All pass ──→ CLEAR (proceed to review)
            └── Any fail ──→ BLOCKED (fix, re-run)
```

### Invariants

Machine-testable rules that must hold true after every task. They grow with the project.

```
INV-{category}-{yyyymmdd}-{slug}

Categories:  S = Structural    B = Behavioral    D = Data
Check types: code-grep | code-review | spec-compare | manual
```

New invariants are proposed during implementation, approved during review. Stale ones are pruned when intentional changes make them obsolete.

## Drift Detection

`/ddw:drift` compares CURRENT_SPEC against the codebase section-by-section:

```
  CURRENT_SPEC  ←──compare──→  Codebase
       │                            │
       ▼                            ▼
  ┌──────────────────────────────────────┐
  │  Contradiction: spec says X, code Y  │ ← must fix
  │  Spec gap: code has it, spec doesn't │ ← acceptable (code ahead)
  │  Code gap: spec says it, code doesn't│ ← must fix
  └──────────────────────────────────────┘
       │
       ▼
  SYNCED ── no contradictions, no code gaps
  DRIFTED ─ any contradiction or code gap
```

Runs automatically at `/ddw:close`. If DRIFTED, you decide: fix the spec or fix the code.

## Team Development

DDW supports multiple developers working in parallel — and a single integration worktree as the merge point.

```
  main branch ──────────────────────────────────────────────────────>
       │                    │
       │ /ddw:decision      │ /ddw:task
       │ /ddw:task          │ (planning stays on main)
       │                    │
       ├── task/feat-a ─────┤──── Dev A: /ddw:sendit → qa → review → ready_for_integration
       │                    │                                              │
       └── task/feat-b ─────┘──── Dev B: /ddw:sendit → qa → review → ready_for_integration
                                                                           │
                                                  ddw-queue tick (FIFO)    │
                                                          ▼                │
                                                 ┌───────────────────┐     │
                                                 │  integration WT   │ ←───┘
                                                 │  (merged via       │
                                                 │   ddw-stage        │
                                                 │   --no-ff)         │
                                                 └───────────────────┘
                                                          │
                                                  manual smoke-test
                                                          │
                                                  /ddw:close → PR
```

- **Identity**: `git config user.name` at runtime — no per-user config
- **Planning on main**: Decisions and tasks on `main` so everyone sees them
- **Implementation in worktrees**: `setup-worktree.sh TASK-id` creates `.worktrees/TASK-id/` on a fresh `task/TASK-id` branch
- **Integration is serial**: only one task tests at a time (hard-gated by `.ddw/integration.json.testing`)
- **Owner-aware hooks**: `require-active-task` checks *your* user — parallel work is fine
- **Close on branch**: Then merge via PR

## Integration Loop

Phase A's integration loop moves a finished task from "ready" → "merged into integration" → "closed". **The user-facing surface is slash commands** — the bash scripts are implementation details that skills invoke.

### Setup (one-time)

Create the integration worktree from `main`:

```bash
git worktree add .worktrees/integration -b integration main
```

Configure `ddw.json`:

```json
{
  "worktree": {
    "taskDir": ".worktrees/{TASK_NAME}",
    "integrationDir": ".worktrees/integration",
    "syncFiles": [".env"],
    "maxConcurrent": 3
  },
  "commands": {
    "install": "pnpm install",
    "dev": "pnpm dev",
    "migrate": null
  }
}
```

`syncFiles` are symlinked from the main repo into each new worktree (existing files are left alone). `commands.install` runs automatically when a worktree is missing `node_modules` / `.venv` / `vendor`. `commands.migrate` runs automatically when staging detects a migration file in the merged diff (configure `worktree.migrationGlob`).

### Per-task flow (slash commands only)

```
/ddw:task                  ← author the task
/ddw:sendit TASK-id        ← creates worktree, implements, runs review,
                              flips status: ready_for_integration,
                              calls queue tick → auto-merges into integration
                              if integration was idle
   (manual smoke-test in .worktrees/integration/)
/ddw:close TASK-id         ← archives task, clears integration.json,
                              advances queue, removes worktree
```

Exception paths:

```
/ddw:queue list            ← what's in the FIFO?
/ddw:queue status          ← what's currently testing?
/ddw:queue tick            ← manually advance (rare; auto-called by sendit/close)

/ddw:integration unstage   ← smoke-test failed, revert and flip back to in_progress
/ddw:integration reset     ← something went sideways, wipe integration to origin/main
```

### Scripts (under the hood — invoked by skills)

| Script | Invoked by |
|---|---|
| `setup-worktree.sh TASK-id [--base TASK-id]` | `/ddw:sendit` step 7.5 |
| `ddw-stage TASK-id` | `ddw-queue tick` (transitively from `/ddw:sendit` step 14, `/ddw:close` step 13d, `/ddw:queue tick`) |
| `ddw-unstage TASK-id` | `/ddw:integration unstage` |
| `ddw-queue tick \| list \| status` | `/ddw:queue` |
| `ddw-integration-status` | `/ddw:queue status` (delegate) |
| `ddw-integration-reset [--yes]` | `/ddw:integration reset` |
| `ddw-index.mjs` | Owner runs manually or via pre-commit hook |

You can still call any script directly from a shell — the skill layer is for ergonomics, not gatekeeping.

### `.env.ddw` and port offsets

`setup-worktree.sh` writes `PORT_OFFSET=<slot * 100>` to `.env.ddw` in the new worktree (slot = count of existing task worktrees + 1). `.env.ddw` is **never** in `syncFiles` — it's per-worktree by design. Source it from your `commands.dev`:

```bash
# pnpm dev wrapper, for example:
set -a; source .env.ddw 2>/dev/null; set +a; pnpm dev
```

### Derived Logs (via `ddw-index`)

4 log files — `TASK_LOG.md`, `DECISION_LOG.md`, `PRD_LOG.md`, `RETRO_LOG.md` — are **derived views**, regenerated from task/DEC/PRD source files by:

```bash
node ${CLAUDE_PLUGIN_DIR}/scripts/ddw-index.mjs --root .
```

Source files in `tasks/`, `decisions/`, `prds/` (including `archive/`) are the canonical truth. The script never mutates them. Modes:

- **Default**: regenerate all 4 logs.
- `--check`: exit 1 if any log is out of date (use as a pre-commit hook).
- `--dry-run`: print row-level diff without writing.

Run it after closing a task, or wire it into `pre-commit` so logs never drift.

### Archive

Completed tasks → `tasks/archive/`. Completed decisions → `decisions/archive/`. Completed PRDs → `prds/archive/`. Archived files stay in log sync. Active working set stays small.

## Plugin Structure

```
ddw/
├── .claude-plugin/
│   └── plugin.json                Plugin manifest
├── skills/                        14 skills (Claude Code slash commands)
│   ├── init/SKILL.md              Bootstrap DDW into a project
│   ├── ideate/SKILL.md            Shape ideas → PRD (Shaper agent)
│   ├── decision/SKILL.md          Create decisions (Architect agent)
│   ├── prd/SKILL.md               PRD lifecycle helpers (close)
│   ├── task/SKILL.md              Create tasks with acceptance criteria
│   ├── sendit/SKILL.md            Auto-worktree, implement, review, queue (Developer agent)
│   ├── qa/SKILL.md                Automated QA (QA agent)
│   ├── review/SKILL.md            QA + owner checklist
│   ├── close/SKILL.md             Spec, drift, retro, archive, worktree cleanup, queue tick
│   ├── queue/SKILL.md             Inspect/advance integration queue (list, tick, status)
│   ├── integration/SKILL.md       Exception paths (unstage, reset)
│   ├── drift/SKILL.md             Spec-code consistency check
│   ├── architect/SKILL.md         Design review / bootstrap
│   └── upgrade/SKILL.md           Upgrade project scaffolding
├── scripts/                       Worktree + integration runtime
│   ├── ddw-index.mjs              Regenerate log views from source files
│   ├── setup-worktree.sh          Create per-task git worktree
│   ├── ddw-stage                  Merge a task branch into integration
│   ├── ddw-unstage                Revert the staged task (HEAD~1)
│   ├── ddw-queue                  tick / list / status — FIFO by Ready-At
│   ├── ddw-integration-status     Print testing + queue + recent commits
│   ├── ddw-integration-reset      Reset integration worktree to origin/main
│   └── _ddw_read_config.mjs       Internal config-reader helper
├── hooks/
│   ├── hooks.json                 Hook wiring (4 event types)
│   └── scripts/                   Enforcement scripts (validate-datetime, etc.)
├── agents/                        4 agent profiles (role mindsets)
│   ├── shaper.md                  Thinking partner for ideation
│   ├── architect.md               System designer
│   ├── developer.md               Spec-first implementer
│   └── qa.md                      Adversarial evaluator
└── templates/                     Project scaffolding
    ├── PRD_TEMPLATE.md
    ├── TASK_TEMPLATE.md
    ├── CURRENT_SPEC_TEMPLATE.md
    ├── GUARDRAILS.md
    ├── INVARIANTS.md
    ├── WORKFLOW.md
    ├── MILESTONES.md
    ├── VOICE.md
    └── ddw.json.example
```

## What `/ddw:init` Creates

```
{workflowDir}/
├── ddw.json               Config (paths, commands.{install,dev,typecheck,test,lint,migrate}, worktree)
├── prds/                  Product requirement documents
│   └── archive/           Closed PRDs (moved here by /ddw:prd close)
├── decisions/             Decision files (architect review + task list)
│   └── archive/
├── tasks/                 Task files (scoped work with acceptance criteria)
│   └── archive/
├── guardrails/
│   ├── GUARDRAILS.md      Architecture rules (fill this in)
│   └── INVARIANTS.md      Machine-testable rules (grows over time)
├── logs/                  Derived views — regenerated by ddw-index, never hand-edited
│   ├── TASK_LOG.md        Status table for all tasks
│   ├── DECISION_LOG.md    Index of all decisions
│   ├── PRD_LOG.md         Index of all PRDs
│   └── RETRO_LOG.md       Retrospective entries per task
├── hooks/                 Hook scripts (copied from plugin)
├── agents/                Role profiles (copied from plugin)
├── MILESTONES.md          Planning priority order
├── WORKFLOW.md            Full workflow reference
└── VOICE.md               Communication style

.ddw/                      Per-machine runtime state (gitignored)
└── integration.json       { "testing": "TASK-..." | null }
```

## Session Handoff

When a session ends mid-task, the `## Session Handoff` section preserves context:

- **Completed:** what's done
- **Next:** specific next actions
- **Blocked:** any blockers
- **Key context:** non-obvious state ("tried X, failed because Y")

`/ddw:sendit` detects handoff content on resume and displays a summary before continuing.

## Learning Loop

```
  /ddw:close
     │
     └── Retrospective: "Anything surprising, difficult, or wrong?"
            │
            ├──→ GUARDRAILS.md     (new architecture rules)
            ├──→ INVARIANTS.md     (new regression checks)
            └──→ RETRO_LOG.md      (permanent record)
```

DDW gets smarter over time. Every task completion is a chance to tighten the harness.

## Caveats

### What holds
- Hard hooks (`exit 2`) cannot be bypassed through conversation
- Even if Claude is persuaded to skip process, the write physically fails

### What can be persuaded
- `CLAUDE.md` instructions are soft — an LLM can be talked out of them
- But hard hooks still block the actual write, limiting the damage

### The real risk
A user asking Claude to delete the hook scripts. Mitigations:
- Hook scripts are git-tracked — `git checkout` restores them
- Code review catches unauthorized hook removal in PRs

### What's truly unbreakable
**Git history.** Every decision, task, and change is a committed file. The absence of a decision file for a code change is visible in the log. The audit trail outlives the harness.

## Philosophy

DDW adds a thin layer of discipline to AI-assisted development:

1. **Write down what you're deciding** before you decide it
2. **Write down what you're building** before you build it
3. **Verify it works** before you call it done
4. **Record what changed** after it ships

This prevents scope creep, ensures nothing is half-finished, and creates a searchable history of every decision and change in your project.
