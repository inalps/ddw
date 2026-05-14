---
name: ideate
description: Guide structured thinking to produce a PRD document. Iterative shaping session that helps anyone — technical or not — crystallize rough ideas into a clear product requirements document.
disable-model-invocation: false
---

**Invocation gate:** Only run this skill when (1) the user explicitly typed the `/ddw:ideate` command, (2) a hook enforcement message demands it, or (3) you proposed running this skill and the user clearly confirmed. Never auto-invoke from ambiguous context.

Shape a rough idea into a structured PRD (Product Requirements Document) through guided conversation.

0. **Read voice** — read `{workflowDir}/VOICE.md` (if it exists) and follow its communication style for all output during this skill.

1. **Read config** — read `{workflowDir}/ddw.json` (search `workflows/ddw.json`, `.workflows/ddw.json`, then `.claude/ddw.json` for legacy) to get `workflowDir` (default: `workflows`). Resolve user identity by running `git config user.name || whoami`.

1.5. **Logs are derived views.** Do not sync inline — `ddw-index` is the canonical generator. The owner runs `node ${CLAUDE_PLUGIN_DIR}/scripts/ddw-index.mjs` (or via pre-commit hook) to refresh.

2. **Get today's UTC date** in `yyyymmdd` format for the file name prefix.

3. **Load shaper profile** — read the `agents/shaper.md` bundled with the DDW plugin (plugin root, not project directory). Adopt its mindset for the entire session.

4. **Ask the user for starting context** via AskUserQuestion (if not already provided in $ARGUMENTS):

   Start warm and open. Ask:
   - **What are you trying to build or solve?** (can be vague — that's fine)
   - **Who is it for?** (users, team, customers — or "I'm not sure yet")
   - **What triggered this?** (pain point, opportunity, request, curiosity)

   If the user has existing docs, notes, or references, ask them to share the path or paste the content. Incorporate that material into the shaping rounds below.

   **Auto-load references:** After gathering the user's starting context, check `ddw.json` for a `references` array. If it contains paths, read each file silently and use their content as additional context for the shaping rounds. For sections the reference documents already cover well, pre-fill the draft and confirm with the user: "Your reference documents already cover {section} well. Here's what I extracted: {synthesized content}. Does this look right, or do you want to revise it?" Skip the corresponding round's questions for sections confirmed as adequate — only shape the gaps.

   **Tone:** "There are no wrong answers here. We're just getting the shape of the idea down. We can refine everything as we go."

5. **Iterative shaping loop** — Walk through 5 rounds. Each round:
   - Ask 2-3 focused questions
   - Wait for the user's answer
   - Synthesize their response into the corresponding PRD section (use clear, actionable language — not just echoing what they said)
   - Show the draft section back to the user
   - Ask if they want to refine it or move on

   The user can say **"skip"** to move past any round, or **"done"** at any point to finalize with whatever is filled in. Never force a round — but gently note what will be missing.

   **Round 1 — Problem Statement**
   Explore the problem space. Why does this matter? What happens if nothing is done?
   - "Can you describe the problem in one or two sentences?"
   - "What's the cost of not solving this?" (time, money, frustration, risk)
   - "Has anyone tried to solve this before? What happened?"

   If the user struggles, offer an example: "A problem statement might look like: 'Customer support spends 3 hours/day manually categorizing tickets. This delays response times and frustrates the team.'"

   **Round 2 — Users & Stakeholders**
   Who benefits? What are their pain points today?
   - "Who will use this day-to-day?"
   - "What do they do today without this? What's their workaround?"
   - "Is there anyone else affected — even indirectly?" (managers, ops, customers)

   **Round 3 — Proposed Solution**
   Help the user articulate their approach at a conceptual level. No technical architecture — that's the architect's job later.
   - "If this existed tomorrow, what would the user experience look like?"
   - "Walk me through the happy path — what happens step by step?"
   - "What's the simplest version that still solves the core problem?"

   Challenge if the solution seems disconnected from the problem: "Interesting — how does this connect to the problem we described in Round 1?"

   **Round 4 — Scope & Non-Goals**
   Draw boundaries. This is where the shaper is strict.
   - "What's definitely included in this effort?"
   - "What are you explicitly NOT building? What's tempting but out of scope?"
   - "Are there constraints — timeline, budget, technology, team size?"

   Push back on vague scope: "That's broad. If you had to ship something in two weeks, which parts would you keep and which would you cut?"

   **Round 5 — Success Criteria & Open Questions**
   How will you know it worked? What don't you know yet?
   - "If this ships and works perfectly, what's different? How would you measure it?"
   - "What are you most uncertain about?"
   - "What would you need to research or test before committing?"

   If the user can't define success criteria, offer patterns: "Success criteria might look like: 'Ticket categorization takes under 30 seconds instead of 5 minutes' or '80% of users complete onboarding without contacting support.'"

   **After all rounds (or when user says "done"):**
   - Review the Prior Art & Alternatives section — ask if they considered other approaches: "Before we lock this in — were there other ways you thought about solving this? Even if you rejected them, it's worth capturing why."
   - Show the complete draft PRD to the user for a final pass.
   - Ask: "Anything you want to change, add, or remove?"

5.5. **Round 6 — Decision Backlog (decompose into ADR-sized DECs).** This step forces the PRD to spawn small, narrow decisions instead of one monolithic DEC.

   - Tell the user: "Now we'll list the **architectural decisions** this PRD will need. Each should be narrow — one specific question, ADR-sized. Better to have 5 small DECs than 1 big one."
   - Walk through the proposed solution and identify decision-points. Look for:
     - Technology choices ("which queue?", "which DB?")
     - Behavior contracts ("delivery semantics?", "retry policy?")
     - Boundary questions ("client- or server-side?", "sync vs. async?")
     - Schema/interface questions ("what does the public API look like?")
     - Operational questions ("how do we deploy this?", "how do we observe failures?")
   - For each, propose a slug + one-line question. Show the user:
     ```
     I see these decisions for this PRD:
       1. push-semantics — at-least-once vs. exactly-once delivery?
       2. queue-choice — SQS vs. Redis Streams vs. Kafka?
       3. retry-policy — bounded vs. unbounded backoff?
     Add any I missed, remove any that are too small to be a DEC, or merge duplicates.
     ```
   - Iterate until the owner confirms the list. Each entry must be **answerable with a single architect review** — if a slug feels like it needs multiple reviews, split it. If it feels like a configuration knob (not an architectural choice), drop it.
   - Capture the confirmed list — these will populate the PRD's `## Decision Backlog` section in step 8.
   - **Skip rule:** if the user says "skip" or "I don't know yet," accept it but warn: "We can ship the PRD with an empty backlog, but `/ddw:prd close` will refuse until you've at least listed the decisions or marked them deferred. Add them later via `/ddw:ideate` re-run."

6. **Assess completeness** — Before writing the file, honestly assess:
   - Are all core sections filled with substance?
   - Are there contradictions between sections?
   - Are open questions manageable or are they blockers?

   If critical sections are thin, say so: "The PRD captures the direction well, but the success criteria are still vague. Want to sharpen them, or note it as an open question and move on?"

   **Determine status** based on the assessment:
   - If all core sections are filled with substance and no critical gaps remain → recommend `solid`
   - If any sections are thin, skipped, or have unresolved blockers → recommend `draft`
   
   Present the recommendation: "Based on what we've covered, I'd mark this as `{recommended status}`. Does that feel right, or would you like to change it?" The owner decides the final status.

7. **Get the actual current UTC datetime** by running:
   ```bash
   date -u +"%Y-%m-%dT%H:%M:%SZ"
   ```
   Use the exact output. Never use a placeholder like `T00:00:00Z`.

8. **Create the PRD file** at `{workflowDir}/prds/PRD-{yyyymmdd}-{slug}.md` where slug is the title lowercased with spaces replaced by hyphens. Use the template from `{workflowDir}/prds/PRD_TEMPLATE.md` (or the plugin's `templates/PRD_TEMPLATE.md` if not found in the project).

   Fill in all sections from the shaping session. Replace placeholder text with the synthesized content. For sections that were skipped, leave the template placeholder text as a reminder. Set the `Status:` field to the status confirmed by the owner in step 6.

   **Populate `## Decision Backlog`** with the list confirmed in step 5.5. Each entry:
   ```
   - {slug} — {one-line decision question} (proposed)
   ```
   If the user skipped step 5.5, leave the template placeholder lines and add a Feedback Log entry: "Decision Backlog deferred during ideation — populate before `/ddw:prd close`."

   The `## Feedback Log` starts with:
   ```
   - {actual UTC datetime} — [owner] Initial PRD created via /ddw:ideate.
   ```

9. **Skip inline PRD_LOG update** — `ddw-index` derives the log from PRD source files. The new PRD file IS the source of truth; the log will be refreshed on the next `ddw-index` run.

10. **Guide the user on next steps:**
    - If status is `solid`: "Your PRD is solid at `{file path}`. When you're ready to turn this into a technical decision, run `/ddw:decision` — the architect will use this PRD as the foundation."
    - If status is `draft`: "Your PRD is saved as a draft at `{file path}`. You can revisit it anytime — run `/ddw:ideate` again to refine, or jump straight to `/ddw:decision` if you're comfortable moving forward."
    - If there are significant open questions: "You might want to resolve the open questions first, or bring them into the decision discussion where the architect can help assess technical feasibility."

11. **Report**: the PRD file path, PRD ID, and a one-line summary.

---

## PRD-as-Bible Principle

Once the PRD is created, its core sections (Problem Statement through Prior Art & Alternatives) are **never modified by downstream processes**. The decision skill, architect review, and all other DDW phases treat the PRD as read-only.

All commentary, refinements, and findings from later phases go into the `## Feedback Log` at the bottom of the PRD — an append-only section where entries are tagged with their source:

- `[owner]` — the PRD author's own notes
- `[architect]` — findings from the architect review during `/ddw:decision`
- `[decision:DEC-{yyyymmdd}-{slug}]` — notes tied to a specific decision

This preserves the original vision while creating a paper trail of how thinking evolved around it.
