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

Decision → Task → Implement → QA → Close

Or full power:

```
/ddw:ideate → /ddw:decision → /ddw:task → /ddw:sendit → /ddw:review → /ddw:close
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

| Command | Purpose |
|---|---|
| `/ddw:init` | Bootstrap DDW into a project |
| `/ddw:ideate` | Shape rough ideas into a PRD |
| `/ddw:decision` | Create decision with architect review |
| `/ddw:task` | Break decision into scoped tasks |
| `/ddw:sendit` | Start implementation on feature branch |
| `/ddw:qa` | Automated QA: acceptance criteria + invariants |
| `/ddw:review` | QA + tests + owner checklist |
| `/ddw:close` | Spec update, drift check, retro, archive |
| `/ddw:drift` | Check spec-code consistency |
| `/ddw:architect` | Design review or bootstrap constraints |
| `/ddw:upgrade` | Upgrade project to latest plugin version |

---

## Tips for AI-Powered Dev

- **Run `/clear` after each task**
  Context builds up and slows things down. Fresh start = fast start.

- **Working on multiple tasks? Use `git worktree`**
  Or just tell the AI "work on these in parallel" — it'll figure it out.

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
