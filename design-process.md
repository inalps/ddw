# DDW Design Process

**Date:** 2026-05-07
**Frame:** Cross-functional development in one repo. Designer + PdM + engineer share the same artifacts. Pre-AI: each role had separate tools (Figma / Notion / Jira / GitHub) and integration was manual handoff. Post-AI: AI bridges role boundaries — every artifact lives in the repo as a markdown/code file, AI propagates changes across artifacts, role-specific tools become optional.

Figma (or any visual exploration tool) remains useful for early divergent design; this framework is the canonical home once direction is committed. Designers commit to git via AI like everyone else — whether they "understand" git or JSX is incidental, just as engineers don't need to understand every line of generated code.

This document captures the **design-process leg only.** The engineering process (worktrees, integration staging, QA loops, ddw-index) is in `enhancement.md`. The two are parallel initiatives, not nested.

---

## 1. Foundation Principle

**Two artifacts per screen. One source of truth at a time. Ownership flips on first designer touch.**

For every screen in the product:
- The **design artifact** lives in `designs/screens/{name}/`
- The **implemented screen** lives in the application code (e.g. `apps/web/src/app/{name}/page.tsx`)

These are always separated, always synced, and have explicit ownership.

### Mode A — Engineer-owned (default)

- Source of truth: code
- Design artifact = projection extracted from code
- Re-extracted automatically when code changes
- Designer can read but hasn't claimed
- Status values: `extracted` | `hypothesis`

### Mode B — Designer-owned (after claim)

- Source of truth: design artifact
- Code is expected to follow
- Extraction is **off** — design file protected from auto-overwrite
- Status values: `claimed` (designer working) | `reviewed` (approved)

### Claim trigger

**Implicit:** any human edit to a `status: extracted` design file flips it to `status: claimed`. Frontmatter records `claimed_by`, `claimed_at` automatically via the same write.

**Explicit:** `/ddw:design claim SCREEN-X` for clarity / pre-emptive ownership.

**Once claimed, never reverts.** Designer remains owner of that screen forever.

---

## 2. Sync Mechanisms

### Mode A: Impl → Design (extract)

- `ddw-designer` agent reads the code (JSX/HTML/Vue/etc.), writes markdown spec — layout, components, states, copy
- Runs automatically on `/ddw:close` for tasks that touched the screen
- Skipped entirely in Mode B (designer's work is sacred)
- Manual: `/ddw:design extract SCREEN-X`

### Mode B: Design → Impl (align)

- Hook on `designs/screens/*/*.md` writes detects diff vs prior committed version
- Auto-creates `TASK-align-{screen}` with the design diff embedded
- Goes through standard `/ddw:sendit → qa → review → close`
- Engineer (or `ddw-dev` subagent) reconciles preview changes into production while preserving wiring (data fetching, state, routing)

### Mode B: Engineer code edits to a designer-owned screen

- Warn: "SCREEN-X is designer-owned; this code change will drift"
- **Don't block** — bugs and data-fetching fixes still need to ship
- Drift surfaces in `/ddw:drift SCREEN-X`

### Concurrent edits

If designer revises design while engineer pushes a code change:
- Alignment task carries **both diffs** (designer's design change + engineer's code change since last extract)
- Human resolves
- No auto-merge

### Drift detection

`/ddw:drift SCREEN-X` per-screen check:
- Mode A → re-extract silently (impl is canonical, design follows)
- Mode B → surface diff, auto-create alignment task

---

## 3. Per-Screen Artifacts

```
designs/screens/checkout/
├── checkout.md              # canonical spec (markdown + frontmatter)
├── checkout.preview.html    # rendered preview (pre-stack) or
├── checkout.preview.tsx     # rendered preview (post-stack)
├── checkout.notes.md        # optional: designer's reasoning
└── references/              # optional, non-canonical
    ├── figma-export-2026-05-07.png
    └── moodboard.png
```

`references/` holds external source material (Figma exports, screenshots, sketches) that informed the canonical spec. Non-canonical, not synced, preserved as historical context.

Frontmatter on `checkout.md` is the load-bearing piece — see schemas in §11.

---

## 4. Live Preview & Propagation

The preview is the sharing mechanism. Designer (with Claude) edits both `*.md` and `*.preview.{html|tsx|...}` together. Hot reload + git push = everyone sees the same preview.

### Preview routing

App ships a `/preview/[screen]` route in dev that mounts each screen's preview file. Production builds exclude this route. PdM/engineer opens `localhost:3000/preview/checkout` to see designer's current state without leaving the project.

Pre-stack (no dev server yet): designers and stakeholders open `*.preview.html` directly via `file://` in any browser. `SCREEN_INDEX.md` provides clickable links.

### Propagation to actual

Because preview is a real component (post-stack — see §5), propagation isn't "rebuild from spec" — it's **wire the preview to production:**
- Swap mock data for real data fetching
- Add state management
- Hook up navigation

Two flavors:
- **Automatic (Mode A or hypothesis):** Engineer's `/ddw:sendit` for a screen with no production yet — AI takes the preview, wires it to data, ships
- **Alignment (Mode B, after production exists):** Designer revises preview → alignment task → engineer reconciles

---

## 5. Stack-Agnostic to Stack-Specific

Designer can start work in repo before tech stack is decided.

### Stage 1 — Pre-stack (default)

- `framework: null` in `ddw.json`
- Preview is plain HTML/CSS: `checkout.preview.html`
- Anyone (designer, PdM, Claude) can edit
- Open in browser via `file://` — no toolchain, no framework knowledge required
- Commit and share via git

This stage supports PdM/design-only projects: ideate → decision → design → clickable HTML prototype, all without an engineering decision.

### Stage 2 — Stack chosen

Recorded in `ddw.json`:
```json
{
  "framework": "react-tsx" | "vue-sfc" | "svelte" | "..."
}
```

One-time skill: **`/ddw:design migrate-framework`**
- AI reads every `*.preview.html`
- Rewrites as `*.preview.tsx` (or chosen format)
- Deletes the HTML files (git history preserves them)

From here on, all design work happens in that format. `/preview/[screen]` route serves framework-native files.

### If stack changes later

Re-run `/ddw:design migrate-framework`. AI ports from old format to new. Same skill, same one-commit-per-step guarantee per enhancement.md §12.

### Decision: delete HTML on migration (vs keep both formats)

Picked: **delete.** Single source of truth post-migration. Continuously syncing two formats has cost (sync bugs, drift). A designer who only knows HTML uses Claude as their tool — same as everyone else. Revisit only if a real designer hits this friction.

---

## 6. Screen Index — Shared Product Map

`designs/SCREEN_INDEX.md` — auto-generated by `ddw-index`, like `TASK_LOG.md`. Read-only. Same artifact, three lenses:

- **PdM:** product surface inventory — what exists, what's planned, what's a hole
- **Designer:** workbench prioritization — what's claimed, what needs review, what's ahead/behind impl
- **Engineer:** context for the task at hand

### Structure

```markdown
## By Section

### Checkout
- SCREEN-cart           [reviewed]   built          
- SCREEN-checkout-pay   [hypothesis] in TASK-A      → flows to SCREEN-confirmation
- SCREEN-confirmation   [claimed]    not built yet  

### Onboarding
- SCREEN-signup         [reviewed]   built
- SCREEN-verify         [claimed]    built

## Misalignments

- **Implemented but not designed (extracted, no review):** SCREEN-profile, SCREEN-settings — designer queue
- **Designed but not built:** SCREEN-confirmation, SCREEN-receipts — PdM/eng plan tasks
- **Hypothesis awaiting review:** SCREEN-checkout-pay — designer review
```

### Decision: no `Counts` section

Counts (`14 reviewed · 5 extracted · 3 hypothesis`) decorate without informing. **Misalignments are the only actionable signal** — they tell each role what *they* need to do without manual tracking.

### `impl_status` is derived, not stored

- `impl_path` file exists in repo → `built`
- Open task references this screen → `in_progress`
- Neither → `not_built`

Pure transformation, no state to manage. Same purity rule as `ddw-index` elsewhere.

### Pre-stack mode

When `framework: null`, `SCREEN_INDEX.md` includes `file://` links to each `*.preview.html` so non-engineering teammates can navigate the prototype from one entry point.

---

## 7. Discoverability — No Memorized Screen Names

Engineer never has to know canonical screen IDs.

### Two-phase linkage

**Phase 1 — `/ddw:task` captures intent, not ID:**

```yaml
screen_intent: "checkout payment step"   # free text from author
screens: []                                # empty — not resolved yet
```

Optionally link an ID at task creation if there's an unambiguous match. But intent is enough; resolution can wait.

**Phase 2 — `/ddw:sendit` resolves at the latest possible moment:**

- Re-query registry against `screen_intent` + any prior `screens` ref
- Compare to state at task creation, surface changes:
  - "SCREEN-checkout-payment was missing at task creation; designer has since created it (claimed). Linking to designer's version."
  - "SCREEN-checkout-payment was claimed at task creation but has been revised since. Diff: [...]. Continue?"
  - "Original SCREEN-checkout-payment was renamed to SCREEN-checkout-cc + SCREEN-checkout-paypal. Pick one or split task."
- Lock in: `screens: [SCREEN-X]`, `screens_resolved_at: <now>`

**Hypothesis creation also moves here.** Only created if designer hasn't filled in the screen by sendit time. Maximizes designer's window to preempt the AI guess.

### Why lazy resolution > eager resolution

- Designer might create the real screen between task creation and impl
- No drift between "what task said" and "what existed at impl time"
- Aligns with rest of DDW's pattern — `ready_at`, queue tick at boundaries, not at every event

### During impl

`ddw-dev` subagent re-checks on session-handoff resume (per enhancement.md §5 resume hook). If a designer change landed mid-impl, surface it. Engineer decides: continue and align later, or pause and incorporate now.

---

## 8. Four Paths Into the Registry

A screen can enter `designs/screens/` four ways. All four end up in `SCREEN_INDEX.md` indistinguishably; engineer never has to know which path produced any given screen.

1. **Designer pre-creates** — screen exists `claimed` before any task references it
2. **AI creates hypothesis** — engineer's task references something missing at sendit time; AI generates from policy + similar existing screens; status `hypothesis`
3. **AI extracts** — engineer impl closes; AI auto-extracts spec from code; status `extracted`
4. **Designer brings external reference** — designer drops a Figma frame, screenshot, or sketch into conversation. Claude reads the reference, applies design policy, produces preview + spec in repo. The reference itself is preserved in `references/` as non-canonical history. Status: `claimed` (designer authored it via AI) or `extracted` (designer wanted it as-is for engineer to absorb)

---

## 9. Design Policy

Lives in `designs/policy/`:

```
designs/policy/
├── DESIGN_POLICY.md     # voice, patterns, accessibility rules, interaction conventions
├── tokens.json          # colors, typography, spacing scale
└── components.md        # component library spec
```

Per-screen files **reference** policy by ID, never duplicate. Same way tasks reference DECs.

Bootstrapped via `/ddw:design init` — separate from `/ddw:init` so engineering teams can start without designer onboarding.

---

## 10. Skills, Agents, Hooks

### New skill: `/ddw:design`

| Subcommand | Purpose |
|---|---|
| `init` | Bootstrap `designs/policy/` |
| `extract SCREEN-X` | Manual re-extract from code (auto runs on close in Mode A) |
| `claim SCREEN-X` | Explicit version of the implicit flip |
| `review` | List `status: extracted` + screens with pending alignment tasks |
| `drift SCREEN-X` | Per-screen drift check |
| `rename SCREEN-old SCREEN-new` | Update registry + all task refs in one pass |
| `migrate-framework` | One-time port: HTML → chosen stack (or stack → new stack) |

### New agent: `ddw-designer`

- Mindset: visual systems, accessibility, brand consistency, ergonomics
- Read-only on code (symmetric with `ddw-qa`)
- Body documents recommended model (`opus` for visual systems thinking)
- Per the `ddw-` prefix convention from enhancement.md §5
- Tools (frontmatter): `Read, Grep, Glob, Bash, Edit, Write` (Edit/Write scoped to `designs/` paths only — code is read-only)

### Hooks

- **PreToolUse on `designs/screens/*/*.md`:**
  - If writer is human and current `status: extracted` → flip to `claimed` in same write
- **PostToolUse on `designs/screens/*/*.md`:**
  - If status is `claimed` and content changed → enqueue alignment task creation
- **PreToolUse on impl files matching `impl_path`:**
  - If linked screen is `claimed` and writer is engineer → warn (don't block) about drift

---

## 11. Frontmatter Schemas

### Screen file (`designs/screens/{name}/{name}.md`)

```yaml
---
id: SCREEN-checkout-payment
title: "Checkout — Payment Step"
section: "checkout"                # for index grouping
purpose: "User picks payment method and confirms"   # one-line, shown in index
status: extracted | hypothesis | claimed | reviewed
created_by: ai | <user>
created_at: 2026-05-07T...
claimed_by: <designer>             # if claimed
claimed_at: ...
reviewed_at: ...
based_on: [SCREEN-cart]            # traceability for hypotheses
impl_path: apps/web/src/app/checkout/payment/page.tsx   # load-bearing for sync
flows_to: [SCREEN-confirmation]    # optional sitemap edges
flows_from: [SCREEN-cart]
policy_refs: [POLICY-color, POLICY-checkout-pattern]
---
```

### Task additions (extends enhancement.md §13)

```yaml
screen_intent: "checkout payment step"   # author's free-text intent
screens: [SCREEN-checkout-payment]       # populated at /ddw:sendit
screens_resolved_at: 2026-05-07T...      # for staleness detection on resume
```

### `ddw.json` additions

```jsonc
{
  "framework": "react-tsx" | "vue-sfc" | "svelte" | null,
  "paths": {
    "designs": "designs"
  },
  "designSystem": {
    "source": null | "<package-or-git-url>",   // null = self-contained (monorepo or single product)
    "version": "<semver-range>"                  // when source is set
  },
  "integration": {
    "enabled": true | false                       // default true for solo, false for team
  },
  "ci": {
    "auth": "oauth" | "api-key" | "bedrock" | "vertex"   // determines workflow YAML generation
  }
}
```

`framework: null` is a legitimate state (Stage 1, pre-stack).
`designSystem.source: null` is a legitimate state (monorepo or single-product).
`integration.enabled: false` is the team-mode default (see §21).
`ci.auth` drives generated GitHub Actions workflows (see §22).

---

## 12. Frontmatter Authority Matrix (Design)

Extends enhancement.md §13.

### Screen frontmatter

| Field | Writer | Notes |
|---|---|---|
| `id`, `title`, `section`, `purpose`, `created_at`, `created_by` | `/ddw:design` (creation) or `ddw-designer` (extract/hypothesis) | At creation |
| `status: extracted` | `ddw-designer` (extract pass) | Mode A |
| `status: hypothesis` | `ddw-designer` (hypothesis pass) | Generated from policy |
| `status: claimed`, `claimed_by`, `claimed_at` | PreToolUse hook (implicit) or `/ddw:design claim` (explicit) | First human edit, or explicit claim |
| `status: reviewed`, `reviewed_at` | `/ddw:design review` flip | Designer-driven |
| `impl_path`, `flows_to`, `flows_from`, `policy_refs` | Designer-authored or AI-suggested at creation; subsequently human-edited | Manual / advisory |
| `based_on` | `ddw-designer` (hypothesis only) | Traceability record, never re-written |

### Task frontmatter (additions)

| Field | Writer | Notes |
|---|---|---|
| `screen_intent` | `/ddw:task` | Free text at task creation |
| `screens` | `/ddw:sendit` | Resolved at sendit time |
| `screens_resolved_at` | `/ddw:sendit` | Same write |

Read-only consumers: `ddw-index`, `/ddw:design`, `ddw-dev`, `/ddw:doctor`.

---

## 13. Open Decisions

These need answers before the framework can be scripted:

1. **Engineer code edits in Mode B:** warn-only confirmed (§2). Open: what's the warn surface — terminal print only, or also a frontmatter-recorded "drift acknowledged" log on the screen file?
2. **Concurrent-edit alignment task UI:** how does the alignment task present both diffs — single review pane, or side-by-side?
3. **Granularity post-launch:** screen-only at start (decided). Open: when does a component file appear — first time a designer reuses a region across two screens, or only when explicitly extracted?
4. **`/preview/[screen]` route in pre-stack mode:** plain `file://` open + a static `INDEX.html` generated by `ddw-index`? Or a tiny static server in `/ddw:design init`?
5. **Migrating partial stacks:** what if `framework: react-tsx` but design uses non-React elements (web components, iframes)? Skip those, fail-closed, or migrate with annotation?
6. **Designer identity in a multi-designer team:** `claimed_by` is single-valued. Multi-designer claim — list-valued, or first-claimer wins and the other adds via `co_claimed_by`?
7. **Bootstrap order:** does `/ddw:design init` require `/ddw:init` first, or stand alone (for design-only repos)?
8. **`references/` lifecycle:** keep all external references forever, or prune after preview lands and is approved? Cheap to keep, but accumulates over years.
9. **CI auth strategy** (per §22): per-developer OAuth, designated CI-only Max account, or API key for CI? Affects cost and quota contention with interactive use.
10. **Multi-repo architecture choice** (per §23): monorepo, design-system + product split, or federated? Affects how the framework is configured.
11. **Mode A/B binarity** — designer fixing a typo currently flips the screen to `claimed` forever. Allow `extracted-edited` substate for typo-level fixes that don't trigger ownership? Or accept the binary model as a feature, not a bug?

---

## 14. What's Out of Scope

- **Figma integration / MCP bridge** — explicitly rejected (Option C from the original design conversation). Stays "tools fragmentation"; design lives in repo.
- **PdM workflow beyond screens** — user research notes, success metrics, stakeholder loop. PdM is partially served today by `/ddw:ideate → PRD`. Bigger PdM scope is a future initiative; this doc only covers the design leg of cross-functional flow.
- **Visual designer tooling (drawing canvas, animation prototyping)** — designers use Claude as their drawing-into-code tool; this doc doesn't try to replace Figma's drawing canvas, only its handoff role.
- **Automated visual regression testing** — defer to `ddw-qa` evolution. Could read screenshots of `/preview/[screen]` over time but not in scope here.
- **Realtime collaborative editing across designers** — not addressed; git is the collab substrate.

---

## 15. Reversibility

Per enhancement.md §12 conventions.

### Trivially reversible
- All `designs/` files (markdown + preview) — `git revert`
- New `ddw.json.framework` field — additive, old configs still parse
- New skill, agent, hooks — `git revert`
- `SCREEN_INDEX.md` (generated, regenerated from sources)

### Reversible with minor cleanup
- Migration step (HTML → framework or framework→framework) — single commit per migration step, `git revert HEAD` clean
- Extract operations — re-runnable, idempotent
- Alignment tasks — same lifecycle as any task

### Effectively irreversible
None at code level. Behavioral cost of teaching designers a new flow is the only sunk cost; offset by the freedom of starting design work pre-stack.

---

## 16. Implementation Notes

This is a separate initiative from `enhancement.md`. Suggested ordering — D-prefix to distinguish from enhancement.md's Phase A/B/C:

- **D1.** `/ddw:design init` + policy scaffolding + screen file template + frontmatter schema
- **D2.** Stage 1 HTML preview workflow (no migration needed; just file conventions + browser open)
- **D3.** `ddw-designer` agent + extract pass (Mode A automation)
- **D4.** Hooks for claim flip + alignment task creation
- **D5.** `SCREEN_INDEX.md` generation in `ddw-index` (reuse existing pure-transformation infra)
- **D6.** `/ddw:sendit` lazy resolution against registry
- **D7.** `/ddw:design migrate-framework` skill
- **D8.** `/preview/[screen]` route convention (per-stack docs)

D1–D2 are the smallest viable starting point — design happens in repo as plain HTML, no AI sync yet, no impl coupling. From that base, layer in the rest as friction surfaces actually demand them.

---

## 17. Industry Context (2026)

This framework lands in the middle of an emerging shift in design-engineering coordination. Worth naming what's mainstream, what's leading-edge, and where this sits.

### The mainstream (still dominant)

Most teams use Figma → Linear/Jira → GitHub with handoff bundles between them. Designer finishes, exports specs, engineer rebuilds in code. Handoff is a translation step. **This is what the framework replaces, not extends.**

### Leading-edge categories

**1. Visual-canvas-first AI tools.** Anthropic's Claude Design (launched 2026), Vercel's v0, Figma Make. Designer prompts/refines in a canvas, exports a "handoff bundle" to Claude Code. Designs aren't repo-native; they live in the canvas tool until export.

**2. Agent-on-codebase tools.** AutonomyAI and similar — operate on whole codebases, produce PRs directly. Industry framing: *"handoff isn't translation anymore, it's collaboration continuation."*

**3. Design-system-as-substrate.** Shared design tokens (W3C Design Tokens spec, Style Dictionary), shadcn/ui, Storybook. Designer and engineer work against a shared component library. Most adopted pattern across mature teams.

### Where this framework sits

More radical than category 1 (no visual canvas — repo *is* the canvas). More structured than category 2 (explicit Mode A/B ownership, claim semantics, generated index). Aligned with Anthropic's harness-design philosophy but extends it into the design seam.

### Anthropic's own internal practice (per published material)

- Product Design team uses **Figma + Claude Code 80% of the time** — Figma is still in the loop for early exploration
- Claude Design productizes their internal workflow: design system read at onboarding, applied automatically
- Their handoff bundle pattern matches our alignment-task idea, but at file/export level rather than continuous repo sync

### What's novel here

- **Mode A/B ownership flip with claim semantics** — bidirectional sync with explicit ownership transitions. Not in Claude Design, AutonomyAI, or Storybook.
- **Lazy resolution at sendit** — extends DDW's existing pattern.
- **Pre-stack HTML stage** — design before tech-stack decision is unique to this framework.

### What's borrowed from existing patterns

- Generated screen index = Storybook for screens
- Design policy / tokens = standard W3C design tokens / Style Dictionary
- AI extraction from existing code = Claude Design's "import from website," reversed

### Reference points

The closest commercial equivalent is **Claude Design + Claude Code combined**, but those keep design in a separate canvas tool with a discrete handoff. This framework's "repo as the only canvas, AI as the bridge" is one step further down the same road. **Bleeding-edge territory.**

---

## 18. Honest Technical Risks

This framework is **solid as a direction, not yet solid as a spec to ship.** The spine is sound; AI-translation seams carry real risk. Worth being explicit about what's load-bearing on AI capability.

### Risk seam 1: AI extract impl → design

JSX/Vue has conditionals, server components, suspense, prop drilling, fetched data. Extracting a "spec" without lossy translation is hard. Most likely outcome: spec is too high-level to be useful, or too verbose to be readable.

**Mitigation:** scope what extract captures (component tree + visible states + static copy); accept lossiness for dynamic parts. Don't oversell as lossless.

### Risk seam 2: AI propagation design → production

"Wire preview to production" undersells the work — data fetching, auth state, error/loading, navigation, server/client boundaries. AI gets you 60-70% there; the rest is engineering judgment.

**Honest framing:** alignment task is "AI-generated starting point, engineering completion." **Designer is non-blocking; engineer is not effortless.**

### Risk seam 3: migrate-framework

AI-rewriting 50 HTML files into JSX deterministically is wishful. Failure rate compounds. CSS migration (inline → Tailwind / modules / styled-components) varies by target.

**Mitigation:** migrate screen-by-screen with review, not bulk. Define a "DDW HTML conventions" subset that ports cleanly; reject HTML outside it.

### Risk seam 4: `/preview/[screen]` route

Per-framework gotchas (Next.js app router vs pages, Vite vs Webpack, route groups, layouts). This becomes a per-framework adapter problem like enhancement.md §6's audit adapters.

**Mitigation:** pre-stack `file://` mode dodges this entirely. Post-stack ships per-framework recipes; no single convention.

### AI-confidence-bound, top to bottom

Every sync mechanism (extract, hypothesis, alignment, migrate) depends on a non-trivial AI transformation. If state-of-the-art Claude does the work, plausible. If the AI is mediocre, every artifact requires human cleanup and the "non-blocking" pitch collapses.

**Honest scope:** this works for AI-native teams using top-tier models. Not a general-purpose framework for all teams.

### What's underspecified

- **Multi-designer claim** — `claimed_by` is single-valued; pairing or co-ownership not modeled
- **`policy_refs` IDs** — how individual policies have IDs is undefined; likely delete or specify
- **Mode A/B is too binary** — designer fixing a typo claims forever; could allow `extracted-edited` substate
- **`ddw-designer` read scope** — full codebase, just `impl_path`, or task-derived? affects cost

### Prototype before commit

Before building D3+ phases, prototype:
1. Extract pass on 2-3 real screens — see what the spec looks like
2. `migrate-framework` on 5 HTML files — measure failure rate
3. Decide multi-designer claim model
4. Specify or delete `policy_refs`

Phase D1-D2 (init + Stage 1 HTML workflow) is genuinely low-risk and gives you the cross-functional repo benefit immediately. D3+ (AI sync) is where prototype evidence is needed before committing.

---

## 19. PR Authority & Decision Flow

Design changes flow through standard PRs. Decision authority is unambiguous.

### On design PR creation

Reviewers and their roles:
- **PdM** — product fit + priority. PdM's approval is the decision to ship.
- **Engineer** — feasibility check. Non-blocking unless there's a real impossibility ("backend can't do this").
- **Designer review** — optional, for teams with multiple designers.

PdM authority is symmetric with `/ddw:decision` today.

### Exploratory design changes

Designer opens **draft PR**. Hooks treat draft PRs as no-op — no alignment task triggered. When designer marks "ready for review," normal flow kicks in.

This uses git's built-in primitive (draft PR) instead of inventing new state.

### Auto-trigger logic on PR merge

```
Hook checks: does SCREEN-X's impl_path exist as built code?
  YES → drift detected → auto-create TASK-align-{screen}, status: decided, into FIFO queue
  NO  → no task created (design ahead of impl is fine; future /ddw:task picks it up)
```

Handles both scenarios cleanly:
- **Updating a shipped screen** → immediate alignment task, queued, picked up next
- **Iterating ahead of impl** → design accumulates in repo, no stale task pile-up

### Engineer feasibility check is load-bearing on PR review

Without an engineer flagging real impossibilities **before merge**, alignment tasks get auto-created for things engineering can't actually do. Engineer comments "this needs DEC discussion first" → designer converts to DEC flow instead of merging.

### Decision authority summary

| Question | Decider |
|---|---|
| Is this design good? | Designer (+ optional second designer review) |
| Should we ship this design? | PdM (PR approval) |
| Can we ship this design? | Engineer (feasibility flag on PR) |
| Who implements? | `ddw-dev` subagent (no human in this row) |
| Did AI's impl pass quality? | `ddw-qa` subagent first, human engineer final |
| When does it ship vs wait? | PdM (queue priority) |

---

## 20. AI as Implementer

The role split: **designer directs, AI implements, engineer reviews.** Same model as enhancement.md §5, applied consistently to design-driven work.

### The pipeline

```
TASK-align-{screen} (decided)
        │
        ▼
ddw-dev subagent runs in task worktree
        │
        ▼
ddw-qa loops until PASS (max 3 iterations per enhancement.md §5)
        │
        ▼
status: ready_for_integration
        │
        ▼
Human engineer reviews, accepts or rejects
        │
        ▼
Merge
```

### Engineer's actual roles

| When | What |
|---|---|
| Design PR review | Feasibility flag — block obvious impossibilities |
| After AI dev/QA loop | Final review — quality, system fit, edge cases AI may have missed |
| Novel/architectural work | DEC-level discussion before any task — when patterns aren't enough |

### What engineer doesn't do

- Hand-code alignment from scratch
- Watch the queue
- Manually resolve trivial drift

### Mode B drift hook update (replaces §10's framing)

The "engineer code edits in Mode B → warn" hook framing is wrong-shaped — engineer barely edits code directly anymore. **The check should be: is this edit happening as part of an alignment task?** Not "who's the editor?"

Hook fires when *anyone* (human or `ddw-dev`) edits impl files for a designer-claimed screen outside of an alignment task flow.

---

## 21. Integration Worktree Opt-In for Team Mode

The FIFO queue from enhancement.md §4 is a **solo-machine convenience**, not a team-coordination requirement.

### What the FIFO queue actually orders

Just one specific local action: which finished task gets merged into your local integration worktree next for manual testing. It does not order:
- Implementation (parallel by design — each task has its own worktree per enhancement.md §3)
- QA (per-task in same worktree)
- Engineer review (just PRs)

### Solo vs team

**Solo-local:** integration worktree useful as "see all my parallel work running together." FIFO queue picks next finished task. Saves manual choosing.

**Team-using-git:** integration worktree is per-machine (gitignored `.ddw/integration.json` per enhancement.md §4 *"Locality decision: per-machine"*). Team coordination happens via PRs, CI, staging environments. **Local FIFO is invisible to teammates and unused for coordination.**

### Make integration worktree opt-in via `ddw.json`

```json
{
  "integration": {
    "enabled": true | false   // default true for solo, false for team
  }
}
```

When disabled:
- `ready_for_integration` flips directly to "ready for PR review"
- No `ddw-stage` calls, no `.ddw/integration.json` written
- Push branch + open PR is the next step

Both modes use the same task statuses and worktree setup. Only the integration step toggles.

### Cross-reference

This is also an enhancement.md §4 update — should be reflected back into that doc. Documented here because it materially affects how alignment tasks flow in team mode.

---

## 22. CI Authentication Strategy

When CI runs `ddw-dev` and `ddw-qa` (e.g., on PR merge for alignment tasks), it needs Claude Code access. Authentication strategy affects cost, rate limits, and team dynamics.

### Three viable paths

**1. OAuth subscription (Pro / Max).** Run `claude setup-token`, store as `CLAUDE_CODE_OAUTH_TOKEN` GitHub secret. Action consumes from the subscription's rate limits, no API charges.

| Tier | Realistic CI usage |
|---|---|
| Pro (~$20/mo) | Light occasional reviews only |
| Max (~$100-200/mo) | ~5× Pro rate limits — viable for solo or small team |

**2. API key.** Pay per token. Predictable scaling, no rate-limit ceiling, separate from interactive subscription quota.

**3. Bedrock / Vertex.** Enterprise OIDC, billed via cloud provider. For cloud-mature orgs.

### The critical gotcha

OAuth token is tied to an individual's subscription. **Heavy automated workflows draw from the same rate-limit pool as that person's interactive Claude Code.**

Concrete: 3 design PRs in an hour → ddw-dev + ddw-qa runs (up to 3 iterations each per enhancement.md §5) → ~18 Claude invocations from one subscription. That person trying to use Claude Code interactively hits the wall mid-conversation.

### Recommended patterns

**For 1-2 person teams:**
*Per-developer Max + scoped triggers.* Each dev's CI uses their own token. Limit triggers to `@claude` mention or labeled PRs. Conservative `--max-turns 5`.

**For 2-5 person AI-native teams:**
*Designated CI account.* One Max subscription dedicated to CI only; nobody uses it interactively. ~$200/mo, no quota contention with humans. **Recommended default.**

**For larger teams or heavy automation:**
*API key for CI, OAuth for interactive.* Predictable bill, no rate-limit ceiling.

### `ddw.json` config drives generated workflows

```json
{
  "ci": {
    "auth": "oauth" | "api-key" | "bedrock" | "vertex"
  }
}
```

Skills generate appropriate workflow YAML based on this field. Hooks and skills don't bake in auth assumptions. Switching auth modes = update `ddw.json`, regenerate workflows, rotate secrets.

---

## 23. Multi-Repo Architecture

Real teams often work across multiple repos: marketing site + customer dashboard + admin panel + mobile app, all sharing brand and components. The framework handles this without breaking the "canonical artifacts in repo" principle.

### Three architectures

#### A. Monorepo (cleanest, recommended default)

All products + design system in one repo. `designs/policy/` and `designs/components/` are shared; per-product screens in `apps/{product}/designs/screens/`. Designer works in one place, AI navigates one tree.

```
monorepo/
├── designs/
│   ├── policy/                       # shared
│   └── components/                   # shared
├── apps/
│   ├── product-a/
│   │   └── designs/screens/          # product A specific
│   └── product-b/
│       └── designs/screens/          # product B specific
└── packages/ui/                      # shared component library
```

**If your team can choose this, choose this.** Modern AI-native teams (Vercel, mid-stage startups) converge here.

#### B. Design system repo + product repos (workable)

Two layers, two repo classes.

```
design-system-repo/                   # tokens, components, policy — DDW-managed
└── designs/policy/, designs/components/
        (published as npm package or git tag)

product-repo-A/                       # one product, its own DDW
├── ddw.json                          # references design-system-repo
└── designs/screens/                  # product-specific only

product-repo-B/                       # another product, same setup
```

- **Shared changes** (tokens, components): PR in design-system-repo, version bump propagates to consumers
- **Product-specific changes**: PR in that product's repo

#### C. Federated DDW (painful)

Each repo runs DDW independently, shared policy lives at a known URL. Cross-repo updates require AI to manually run in each repo. **Avoid unless hard isolation required** (legal, contractor work).

### `ddw.json` design system reference

```json
{
  "designSystem": {
    "source": null | "<package-or-git-url>",
    "version": "<semver-range>"
  }
}
```

`source: null` = self-contained (architecture A or single-product). Set when the policy lives elsewhere (architecture B).

DDW skills resolve `policy_refs` against the shared package when configured.

### Default recommendation

| Situation | Architecture |
|---|---|
| New project, team can choose | A — monorepo |
| Legacy multi-repo, can't consolidate | B — shared design system repo |
| Hard isolation constraints (legal, contractor) | C — federated |

### Why splitting costs more than monorepo for small teams

Same-repo coordination is uniquely simple **because git already does what cross-repo coordination tries to recreate**:
- Atomic commits across design + impl
- Single git history
- Diff-driven hooks just work (PreToolUse on file write)
- AI reads files directly, no clone/auth/API

Cross-repo requires webhooks, CI bots, cross-repo PR coordination, version pin updates. **For 2-5 person teams, monorepo wins outright.**

---

## 24. Designer Workflows for Multi-Repo

When a designer needs to update screens or components across multiple repos, three workflows handle the realistic cases. AI bridges multi-repo coordination so designer doesn't manually `cd` between clones.

### Workflow 1 — Local: deep iterative work

Designer has the relevant repo cloned. Opens Claude Code in that workspace. Works iteratively — multiple prompts, visual review of `/preview/[screen]`, refinements. AI handles git/gh:

```
cd ~/repos/product-repo-A
# claude code does its thing
git push -u origin task-align-checkout
gh pr create
```

Realistic for ~3-5 active repos. Designer doesn't type git commands; AI does.

### Workflow 2 — GitHub-issue-driven: quick changes

Designer never opens a terminal. Goes to product-repo-A in browser, creates issue:

> Update SCREEN-checkout to add saved cards step. Use the design pattern from SCREEN-cart. @claude implement this.

GitHub Action picks up `@claude`, runs Claude Code in CI for that repo, opens PR. Designer reviews PR in browser, comments to iterate, merges. **The repo is the workspace; GitHub UI is the interface.**

### Workflow 3 — Cross-repo orchestration: coordinated changes

Designer says to Claude (in any local context): *"Bump primary button color in design-system, propagate to product-A and product-B."*

AI's concrete steps:
1. cd to design-system-repo (clone if missing) → edit tokens, commit, push, `gh pr create`
2. cd to product-repo-A → bump dependency, run drift detection, commit, push, `gh pr create`
3. cd to product-repo-B → same
4. Returns 3 PR URLs to designer

Designer reviews 3 PRs in browser, merges in order. **AI does the multi-repo dance; designer never `cd`s.**

### Workflow selection

| Change type | Path |
|---|---|
| Quick fix (one screen, single iteration) | Workflow 2 — GitHub issue |
| Iterative design work (multiple prompts, visual review) | Workflow 1 — local Claude Code |
| Cross-repo change (token bump propagating to N consumers) | Workflow 3 — AI orchestration |

### Required infrastructure

- **gh CLI authenticated with org-level access** — so AI can `gh pr create` in any of the org's repos
- **GitHub Action with `@claude` trigger** in each consumer repo (for Workflow 2)
- **Clone access to all relevant repos** — org SSH key or token (for Workflows 1 and 3)
- **Per §22 CI auth strategy** wired into each consumer repo

### Default recommendation

For a multi-repo design team, default to Workflow 2 (GitHub-issue-driven) for most changes. Removes "where am I working" friction entirely. Fall back to Workflow 1 (local) only when the change needs heavy iteration or visual review.

**Without GitHub Actions + AI, multi-repo design coordination is awful.** With them, it becomes the realistic mode and the multi-repo penalty (vs monorepo) shrinks substantially.
