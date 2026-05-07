---
name: queue
description: Inspect or advance the integration queue. Subcommands: list, tick, status.
disable-model-invocation: false
---

**Invocation gate:** Only run this skill when (1) the user explicitly typed the `/ddw:queue` command, (2) you proposed running this skill and the user clearly confirmed.

Inspect or advance the integration queue. Subcommand: $ARGUMENTS (default: `status`).

The integration queue is the FIFO of tasks with `**Status:** ready_for_integration`, sorted ascending by `**Ready-At:**`. Only one task tests at a time — `.ddw/integration.json.testing` records the current occupant.

0. **Read voice** — read `{workflowDir}/VOICE.md` (if it exists) and follow its style.

1. **Read config** — read `{workflowDir}/ddw.json` to resolve `workflowRoot`. If no `ddw.json`, error: "Run `/ddw:init` first."

2. **Parse subcommand:**
   - `list` → enumerate ready tasks
   - `tick` → if integration is idle, stage the head (lowest Ready-At)
   - `status` (or no args) → full snapshot: testing + queue + recent integration commits
   - Anything else → error: "Unknown subcommand: {arg}. Supported: list, tick, status."

3. **Dispatch:**
   - `list` → run `bash ${CLAUDE_PLUGIN_DIR}/scripts/ddw-queue list --root ${workflowRoot}` and print the output as-is.
   - `tick` → run `bash ${CLAUDE_PLUGIN_DIR}/scripts/ddw-queue tick --root ${workflowRoot}` and print the output. If a task was staged, mention which one. If integration was busy, mention which task is testing.
   - `status` → run `bash ${CLAUDE_PLUGIN_DIR}/scripts/ddw-queue status --root ${workflowRoot}` (which internally delegates to `ddw-integration-status`) and print the output.

4. **Authority note:** this skill never writes task frontmatter or `.ddw/integration.json` directly — it only invokes the bash scripts, which are the §13 authoritative writers for `testing`. `tick` may transitively trigger `ddw-stage` (which sets `testing`).
