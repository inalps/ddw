# Milestones — {project name}

Ordered list of development milestones. Each milestone groups related decisions.

Milestone membership is the single source of truth for planning order.
- New decision → add to the right milestone section below.
- Decision cancelled → remove from here; delete section if empty.
- Milestone assignment is **optional** at `proposed`, **required** before `decided`.
- **Opening / closing milestones is human-only.** No skill auto-appends or auto-strips ✅. To close a milestone, run `/ddw:milestone-close M{N}` — it verifies every listed DEC is archived, then appends ✅. To reopen, the owner edits this file by hand.

## Numbering convention — ordered vs standalone

- **Numbered phases/milestones** (`Phase 1`, `Phase 2`, … or `M1`, `M2`, `M3`, …) → ordered with implicit dependency. `/ddw:sendit` will ask before starting a task in `M{N}` while `M{N-1}` is still open.
- **Unnumbered phases/milestones** (e.g. `Crawler hardening`, `Brand onboarding polish`) → standalone, no dependency on other phases. The absence of a number is the signal that the section is independent and not gated by anything else.

Pick the form that matches the milestone's relationship to its neighbors. Mixed-mode is fine — number the dependent chain, leave the independent ones unnumbered.

---
