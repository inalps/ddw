---
name: drift
description: Check spec-code consistency. Compares CURRENT_SPEC.md against the codebase and reports contradictions, gaps, and deviations.
disable-model-invocation: false
---

**Invocation gate:** Only run this skill when (1) the user explicitly typed the `/ddw:drift` command, (2) a hook enforcement message demands it, or (3) you proposed running this skill and the user clearly confirmed. Never auto-invoke from ambiguous context.

Run a spec-code drift check. Compares the spec against the actual codebase to find contradictions and gaps.

0. **Read voice** — read `{workflowDir}/VOICE.md` (if it exists) and follow its communication style for all output during this skill.

1. **Read config** — read `{workflowDir}/ddw.json` (search `workflows/ddw.json`, `.workflows/ddw.json`, then `.claude/ddw.json` for legacy) to get `workflowDir` and `specPath`.

2. **Read the spec** — read the file at `specPath` (e.g., `docs/CURRENT_SPEC.md`). This is the behavior contract.

3. **Read the codebase** — read the main code file(s) relevant to the project.

4. **Section-by-section comparison** — go through the spec systematically, focusing on:

   **Numeric values:**
   - Scores, thresholds, multipliers, timings, durations
   - Array lengths, counts, limits
   - Grid dimensions, cell sizes, layout constants

   **Data structures:**
   - Array/object entries — count and verify names match
   - Field names, enum values, option keys
   - Menu items, character lists, pattern tables

   **Behavioral descriptions:**
   - Flow descriptions vs actual code logic
   - Condition checks (what triggers what)
   - State transitions (what changes state and when)
   - Edge cases described in spec vs handled in code

   **UI/UX descriptions:**
   - Layout descriptions vs CSS/HTML structure
   - Interaction descriptions vs event handler logic
   - Visual states described vs actually implemented

5. **Classify each finding:**

   - **Contradiction**: Spec says X, code says Y. Both are explicit but disagree.
   - **Spec gap**: Code implements behavior that the spec doesn't document.
   - **Code gap**: Spec describes behavior that the code doesn't implement.

6. **For each finding, determine fix direction:**
   - "Update spec" — code is correct, spec is outdated
   - "Update code" — spec is correct, code has a bug
   - "Clarify" — ambiguous, needs owner input

7. **Generate drift report:**

   ```
   ## Drift Report — {UTC datetime from `date -u`}

   ### Contradictions
   | # | Spec Says | Code Says | Location | Fix Direction |
   |---|-----------|-----------|----------|---------------|
   | 1 | {spec quote} | {code reality} | {spec section + code file:line} | Update spec/code/Clarify |

   ### Spec Gaps (code has it, spec doesn't)
   | # | What Code Does | Location | Recommendation |
   |---|----------------|----------|----------------|
   | 1 | {behavior} | {file:line} | Add to spec section X |

   ### Code Gaps (spec says it, code doesn't)
   | # | What Spec Says | Spec Section | Recommendation |
   |---|----------------|--------------|----------------|
   | 1 | {spec quote} | {section} | Implement / Remove from spec |

   ### Summary
   Contradictions: {count}
   Spec gaps: {count}
   Code gaps: {count}
   Status: SYNCED / DRIFTED
   ```

8. **Status determination:**
   - **SYNCED**: Zero contradictions AND zero code gaps. Spec gaps are informational (code can be ahead of spec).
   - **DRIFTED**: Any contradiction OR any code gap (spec promises something code doesn't deliver).

9. **If DRIFTED**: recommend specific fixes. For contradictions and code gaps, state clearly whether the spec or the code should change, and why.

10. **Output the report** to the user. Do not auto-fix — the owner decides which direction to resolve drift.
