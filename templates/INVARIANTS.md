# Project Invariants

Machine-testable rules that must never be violated.
Each invariant is checked by `/ddw:qa` during the Invariant Regression Sweep.

---

## Naming Convention

`INV-{category}-{yyyymmdd}-{slug}`

Categories:
- **S** — Structural (file count, layout, architecture)
- **B** — Behavioral (logic, scoring, state transitions)
- **D** — Data (counts, entries, configurations)

## Invariants

<!-- Add project-specific invariants here. Example: -->
<!-- ### INV-S-20260319-single-file -->
<!-- **Check:** code-grep -->
<!-- **Rule:** All game code lives in a single `index.html` file. -->
<!-- **Expected:** No `.js` or `.css` files in the project root. -->
