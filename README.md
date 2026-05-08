# DDW — Decision-Driven Workflow

**Ship code that never drifts.
No decision, no code. No task, no implementation.**

> A system that prevents bad development, not just fixes it.

DDW is not a PM tool.
It's a **development harness that enforces quality at the system level.**

---

## What it does

- **Stops bad code before it exists**
  Decisions → Tasks → Code. No shortcuts.

- **Makes every change provable**
  Small tasks with strict acceptance criteria.

- **Enforces rules, not suggestions**
  Hard hooks block violations. You can't "prompt" your way around it.

- **Keeps spec and code in sync**
  Drift detection catches inconsistencies automatically.

- **Turns development into a system**
  Decisions, tasks, QA, and retros — all logged, all connected.

---

## The Flow

Decision → Task → Implement → QA → Integrate → Close

Or full power:

```
/ddw:ideate → /ddw:decision → /ddw:task → /ddw:sendit → /ddw:review
                                              ↓
                                  ready_for_integration
                                              ↓
                                  ddw-queue tick → ddw-stage
                                              ↓
                                          /ddw:close
                                              ↓
                                       /ddw:prd close
```

---

## Why it matters

Most teams don't fail because they can't code.
They fail because:

- Decisions are vague
- Tasks are unclear
- QA is inconsistent
- Specs drift from reality

DDW fixes all of that — by **making it impossible to do it wrong.**

---

## Enforcement

Two layers:

- **Soft** — AI guidance (`CLAUDE.md`)
- **Hard** — Shell hooks that physically block invalid actions

If it breaks the rules, **it doesn't run.**

---

## Positioning

- PM tools manage work
- CI tools test code
- **DDW enforces how development happens**

---

## Install

```json
// .claude/settings.json
{
  "plugins": [
    { "path": "/path/to/ddw" }
  ]
}
```

Then run `/ddw:init`.

---

## Commands

Everything is a slash command. The bash scripts under `scripts/` are implementation details — skills wrap them.

| Command | Purpose |
|---|---|
| `/ddw:init` | Bootstrap DDW into a project |
| `/ddw:ideate` | Shape rough ideas into a PRD |
| `/ddw:decision` | Create decision with architect review |
| `/ddw:prd close PRD-id` | Close a PRD once its decisions exist |
| `/ddw:task` | Break decision into scoped tasks |
| `/ddw:sendit` | Auto-creates a per-task worktree, implements, runs review, queues for integration |
| `/ddw:qa` | Automated QA: acceptance criteria + invariants |
| `/ddw:review` | QA + tests + owner checklist |
| `/ddw:close` | Spec update, drift, retro, archive, **remove worktree**, advance queue |
| `/ddw:queue` | `list` / `tick` / `status` — inspect or advance the integration queue |
| `/ddw:integration` | `unstage <TASK-id>` / `reset` — exception paths for staged work |
| `/ddw:drift` | Check spec-code consistency |
| `/ddw:architect` | Design review or bootstrap constraints |
| `/ddw:upgrade` | Upgrade project to latest plugin version |
| `/ddw:auto` | Overnight orchestrator. Loops the pipeline autonomously; logs blockers to morning inbox |

In the happy path you only ever need: `/ddw:decision` → `/ddw:task` → `/ddw:sendit` → `/ddw:close`. The worktree, queue tick, and integration merge happen automatically.

---

## Tips for AI-Powered Dev

- **Run `/clear` after each task**
  Context builds up and slows things down. Fresh start = fast start.

- **Multitask, no fiddling**
  `/ddw:sendit` creates an isolated worktree per task automatically — port offset (`.env.ddw`), symlinked `.env*`, fresh `task/TASK-id` branch. `/ddw:close` removes the worktree when the task ships. `maxConcurrent` in `ddw.json` caps how many you can run in parallel.

- **Don't overthink Git early on**
  Manual is fine. When it gets tedious, let the AI handle it.

- **Stuck? Just type "next?"**
  DDW will scan your pipeline and tell you what to do.

- **AI asks you to verify something?**
  Check it, then say "confirmed" or "OK" to move on. (Do actually check though.)

- **Started in English but prefer Japanese?**
  Just ask "日本語で進めて" — it'll switch. Docs too. ([日本語 README](README.ja.md))

---

## Documentation

- [Detailed Guide](GUIDE.md) — full workflow reference, architecture, hook diagrams, agent profiles

## License

[MIT](LICENSE)
