---
name: milestone-close
description: Close a milestone in MILESTONES.md. Verifies every DEC listed under the milestone is archived; if all complete, appends a ✅ to the milestone heading. Human-invoked only.
disable-model-invocation: false
---

**Invocation gate:** Only run this skill when (1) the user explicitly typed the `/ddw:milestone-close` command, (2) a hook enforcement message demands it, or (3) you proposed running this skill and the user clearly confirmed. Never auto-invoke from ambiguous context.

**Scope:** This skill is the *only* sanctioned mechanism for the AI to touch a milestone's ✅ marker in `MILESTONES.md`. Outside this skill, milestone open/close is human-only — see the user's milestone-discipline policy. This skill exists to make the human-initiated close fast and verifiable.

Milestone to close: `$ARGUMENTS` (e.g. `M2`). If not provided, ask the user which milestone.

0. **Read voice** — read `{workflowDir}/VOICE.md` (if it exists) and follow its style for all output.

1. **Read config** — read `{workflowDir}/ddw.json` (search `workflows/ddw.json`, `.workflows/ddw.json`, then `.claude/ddw.json` for legacy) to resolve `{workflowDir}`.

2. **Locate the milestone section** in `{workflowDir}/MILESTONES.md`. Match a heading line of the form `### {milestone}:` (e.g. `### M2: Admin approval surface`). The check is case-sensitive on the milestone token.
   - **Not found** → abort: "Milestone `{arg}` not found in MILESTONES.md." Stop.
   - **Heading already ends with ✅** → abort: "Milestone `{arg}` is already closed." Stop.

3. **Collect DEC IDs** listed under the section. Decisions are typically under a `Decisions:` sub-list as bullets `- DEC-YYYYMMDD-slug — short title`. Take every line in the section matching `^- DEC-`.
   - **No DECs listed** → abort: "Milestone `{arg}` has no DECs listed; nothing to verify. If this is intentional, close it manually." Stop.

4. **Verify each DEC is complete.** A DEC is complete iff its file exists at `{workflowDir}/decisions/archive/{DEC-ID}.md` (i.e. it has been moved to the archive directory). Active DECs at `{workflowDir}/decisions/{DEC-ID}.md` count as incomplete.
   - For each ID: check archive path first, then active path.
   - Classify each DEC as `archived` / `active` / `missing`.

5. **If any DEC is `active` or `missing`** → abort with a tight blocker:
   ```
   Cannot close {milestone}. {N} of {total} DECs not archived:
   - {DEC-ID}  ({active|missing})
   - {DEC-ID}  ({active|missing})
   Archive these (set Status: decided + complete tasks + move to decisions/archive/) and re-run /ddw:milestone-close {milestone}.
   ```
   Do not propose actions, do not offer to fix anything, do not ask follow-up questions. Just stop.

6. **All DECs archived** → edit the milestone heading in `MILESTONES.md` to append ` ✅`:
   ```
   ### M2: Admin approval surface ✅
   ```
   - Use Edit to change the single heading line. Preserve everything else byte-for-byte.
   - Do not modify body, bullets, or other milestones.

7. **Report** — one line:
   ```
   ✅ {milestone} closed. {N} DECs verified.
   ```

**Non-goals:**

- Do not commit. The owner commits if they want.
- Do not run `ddw-index` or any log regeneration. Logs are derived views regenerated separately.
- Do not modify any other file (DEC files, task files, CURRENT_SPEC.md). This skill touches `MILESTONES.md` only.
- Do not propose opening the next milestone, re-opening a closed one, or any other follow-up. Closing is the end of the operation.
- Do not infer phase boundaries from DEC state outside the explicit milestone listing. Only DECs listed under the section count.
