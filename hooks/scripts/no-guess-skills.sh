#!/usr/bin/env bash
# DDW Hook: no-guess-skills
# UserPromptSubmit hook — prevents Claude from auto-invoking any /ddw:* skill
# based on guessed intent. Skills require explicit invocation, hook enforcement,
# or clear user confirmation after a proposal.

set -euo pipefail

INPUT=$(cat)

# Only activate if a DDW project is initialised
source "$(dirname "$0")/_config.sh"

cat <<'HOOK_JSON'
{"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": "DDW GUARDRAIL — Do NOT auto-invoke any /ddw:* skill from ambiguous phrases. Valid triggers: (1) user explicitly typed the /ddw:* command, (2) a hook enforcement message instructs you to, (3) you proposed a specific skill and the user clearly confirmed (e.g. 'yeah go for it', 'yes', 'do it'). If intent is unclear, announce which skill you'd run and ask — never guess silently."}}
HOOK_JSON

exit 0
