---
name: audit
description: Adversarial security audit (OWASP Top 10 + STRIDE). Standalone — invoke when you need a real security review, not spec-compliance check. Backed by the security agent profile (Opus).
disable-model-invocation: false
---

**Invocation gate:** Only run this skill when (1) the user explicitly typed the `/ddw:audit` command, (2) a hook enforcement message demands it, or (3) you proposed running this skill and the user clearly confirmed. Never auto-invoke from ambiguous context.

Run an adversarial security audit. Scope: $ARGUMENTS.

## Scope

This skill is **standalone only**. Unlike `/ddw:qa`, it is NOT invoked as a subagent of `/ddw:review`, `/ddw:close`, or `/ddw:pr`. It always runs in the main thread, dispatched by the owner.

`$ARGUMENTS` may be:
- **Empty** → whole-codebase audit (sampled across auth, admin surfaces, API routes, DB layer, middleware)
- **`TASK-{id}`** → scope to the files listed in that task's `## Files` section plus their direct dependencies
- **`<path>`** → scope to a specific directory or file

## How this skill executes

This skill **must dispatch the audit work to a subagent with `model: "opus"`** (as declared in `agents/security.md`). The main thread only orients, dispatches, and persists results. The actual adversarial reasoning runs on Opus regardless of the main thread's model — this is non-negotiable for security audits.

---

## Main-thread steps

0. **Read voice** — read `{workflowDir}/VOICE.md` (if it exists) and follow its communication style for any console output from this skill.

1. **Read config** — read `{workflowDir}/ddw.json` (search `workflows/ddw.json`, `.workflows/ddw.json`, then `.claude/ddw.json` for legacy) to get `workflowDir`, `specPath`, and `paths.audits` (default `audits`). Resolve absolute paths. Auto-create `{workflowDir}/{auditsDir}/` if missing.

2. **Load security profile content** — read the full contents of `agents/security.md` bundled with the DDW plugin (plugin root, not project directory). You will embed this verbatim into the subagent prompt in step 4. Confirm its frontmatter has `model: opus`.

3. **Resolve scope:**
   - **Empty `$ARGUMENTS`** → scope label = `whole-codebase`. Plan a sampling strategy: list top-level directories of the project; identify candidate attack surfaces (auth/session code, admin/ routes, API route handlers, DB query layer, middleware, file-upload endpoints, deserialization sites, anything calling external services). Pass this directory tree + the sampling guidance to the subagent.
   - **`TASK-{id}`** → read `{workflowDir}/tasks/TASK-{id}.md`, extract the `## Files` list. If `## Files` is missing or empty, abort with: "Task has no `## Files` section — re-invoke `/ddw:audit` with an explicit path argument instead."
   - **Path argument** → resolve to absolute path. Verify it exists. Scope label = the path string.

4. **Dispatch audit subagent.** Invoke the Agent tool with these parameters:

   - `subagent_type`: `"general-purpose"`
   - `model`: `"opus"` (this is required — read from `agents/security.md` frontmatter, do not substitute)
   - `description`: `"Security audit: {scope-label}"`
   - `prompt`: assembled as below — embed the literal contents of `agents/security.md` (the part below its frontmatter) at the top, then the audit task instructions, then the scope context.

   **Subagent prompt skeleton:**

   ```
   You are running as a security audit subagent for DDW. Adopt the following profile in full for the duration of this task:

   <security-profile>
   {literal contents of agents/security.md body — everything after the frontmatter}
   </security-profile>

   You will produce a single deliverable: a markdown security audit report following the exact format in the "Report format" section below. Do not produce conversational output, intermediate summaries, or status updates — only the final report.

   ## Inputs

   <scope>
   Scope label: {scope-label}
   Scope type: {whole-codebase | task | path}
   Scope details: {for task: task file content + files list; for path: absolute path; for whole-codebase: top-level dir tree + sampling guidance}
   </scope>

   <guardrails>
   {full contents of {workflowDir}/guardrails/GUARDRAILS.md if it exists, else "(none)"}
   </guardrails>

   <invariants>
   {full contents of {workflowDir}/guardrails/INVARIANTS.md if it exists, else "(none)"}
   </invariants>

   Mandatory: any invariant whose ID starts with `INV-S-` (structural/security) is checked regardless of scope. Verify each `INV-S-*` still holds for the in-scope code.

   ## What to do

   Execute four passes against the in-scope code. Use Read, Grep, Glob, Bash (for `git`, `ls`, `wc`, dependency-manifest reads). Do NOT modify any files. Do NOT run network calls.

   **Pass 1: OWASP Top 10 sweep.** For each category below, scan the in-scope code for vulnerable patterns. For each candidate finding, record: category, file:line, code excerpt, attack scenario (concrete attacker steps), severity, mitigation (specific fix).
   - A01 Broken access control — IDOR, missing authz checks, forced browsing, privilege escalation
   - A02 Cryptographic failures — weak algorithms, hardcoded keys, missing TLS, weak RNG, plaintext secrets
   - A03 Injection — SQL/NoSQL/command/LDAP/template/log injection, raw string concatenation into queries
   - A04 Insecure design — missing rate limits, no anti-automation, dangerous defaults
   - A05 Security misconfiguration — verbose errors, debug flags, permissive CORS, missing security headers, default creds
   - A06 Vulnerable / outdated components — handled in Pass 3
   - A07 Identification & authentication failures — weak session handling, credential stuffing exposure, missing MFA paths, predictable tokens
   - A08 Software & data integrity failures — unsigned updates, insecure deserialization, supply-chain trust assumptions
   - A09 Security logging & monitoring failures — auth events not logged, no audit trail for privileged actions
   - A10 SSRF — unvalidated outbound URL fetches, request forgery to internal services

   **Pass 2: STRIDE per-component.** Identify significant components in scope (auth flow, admin route, DB query path, external API call, file upload, deserialization site, etc.). For each component, enumerate STRIDE threats and check whether mitigations exist:
   - S Spoofing — can identity be forged?
   - T Tampering — can data in transit / at rest / in messages be altered without detection?
   - R Repudiation — can a privileged action be denied later (no audit trail)?
   - I Information disclosure — can a non-privileged actor read sensitive data?
   - D Denial of service — can a small input cause disproportionate work?
   - E Elevation of privilege — can a low-priv actor become high-priv?

   Record any unmitigated threat as a finding with the same evidence shape as Pass 1.

   **Pass 3: Dependency scan.** Read dependency manifests in scope: `package.json`, `requirements.txt`, `pyproject.toml`, `Gemfile`, `go.mod`, `Cargo.toml`, etc. List dependencies + pinned versions. Flag known-vulnerable versions ONLY if you are confident (recognized CVE, version below known-patched). Do NOT fabricate CVE numbers. When unsure, record as INFO with: "version not verified against advisory DB — recommend `npm audit` / `pip-audit` / equivalent."

   **Pass 4: Configuration scan.** Check for, across in-scope code:
   - Hardcoded secrets (API keys, passwords, tokens, JWT secrets in source)
   - Missing security headers (CSP, HSTS, X-Frame-Options, X-Content-Type-Options, Referrer-Policy)
   - Cookie flags missing (`Secure`, `HttpOnly`, `SameSite`)
   - Permissive CORS (`*` origin with credentials, reflected origin)
   - Debug flags / verbose error pages reachable in production code paths
   - `dangerouslySetInnerHTML` (React) / `v-html` (Vue) / `innerHTML` (vanilla) fed user input
   - Raw SQL string concatenation / template interpolation into queries
   - `eval` / `Function()` / `exec` / `system` with non-static input

   ## Report format

   Return ONLY this markdown, nothing before or after:

   ```
   # Security Audit Report — {scope-label}
   **Date:** {UTC datetime}
   **Scope:** {scope description}
   **Files audited:** {count}

   ## Summary
   - BLOCKER: {count}
   - WARNING: {count}
   - INFO: {count}

   ## Findings

   ### BLOCKER

   #### {short-finding-title}
   - **Category:** {OWASP A0X — name / STRIDE-{letter}}
   - **Location:** {file}:{line}
   - **Code:**
     ```
     {excerpt}
     ```
   - **Attack scenario:** {concrete attacker steps}
   - **Mitigation:** {specific fix}

   ### WARNING
   ... (same structure)

   ### INFO
   ... (same structure)

   ## Categories with no findings
   - {category-id — name}: clean
   - ...
   ```

   Severity guidance (also defined in the profile above — repeated for emphasis):
   - **BLOCKER** = exploitable in the current state in production
   - **WARNING** = exploitable under specific conditions or post-deploy
   - **INFO** = defense-in-depth observation, not exploitable

   Bug ≠ vulnerability. If you cannot write the attack scenario concretely, do not record it as a finding.
   ```

   Use the actual UTC datetime via `date -u +"%Y-%m-%dT%H:%M:%SZ"` when constructing the prompt's scope context (the subagent will record its own UTC datetime in the report).

5. **Receive subagent report.** The subagent returns a single message containing the markdown report. Validate it minimally:
   - Starts with `# Security Audit Report`
   - Contains a `## Summary` section
   - Contains BLOCKER/WARNING/INFO counts

   If the report is malformed (no summary, conversational fluff, etc.), do NOT silently retry. Report to console: "Audit subagent returned malformed output. Re-invoke `/ddw:audit` to retry." Save the raw output to `{workflowDir}/{auditsDir}/AUDIT-{timestamp}-MALFORMED.md` for triage.

6. **Write report to disk:**
   - **Whole-codebase or path-scoped:** write to `{workflowDir}/{auditsDir}/AUDIT-{YYYY-MM-DD-HHMM}-{scope-slug}.md`. `{scope-slug}` is `whole-codebase` for empty arguments, or a slugified version of the path otherwise.
   - **Task-scoped:** append a `## Security Audit` subsection to the TASK file's `## Review Log` section (use the standard log entry shape — datetime header + content), AND save a full copy to `{workflowDir}/{auditsDir}/AUDIT-{YYYY-MM-DD-HHMM}-{TASK-id}.md`.
   - Use `date -u +"%Y-%m-%d-%H%M"` for the timestamp.

7. **Console summary** — print only:
   - The `## Summary` section parsed from the subagent's report
   - Path to the saved report file
   - The owner action prompt (step 8)

   Do NOT dump the full findings list to console — it's already on disk.

8. **Owner action prompt:**
   - If `BLOCKER` count > 0: "{N} BLOCKER findings. These are exploitable in the current state and should be fixed before the next deploy / merge. Want me to create remediation tasks via `/ddw:task`, or hand them back as a list?"
   - If only `WARNING` / `INFO`: "{N} findings, all WARNING or INFO. Review per-finding and decide which to address. No automatic next step."
   - If zero findings: "Clean run. Report saved for the audit trail."

---

## Why dispatched, not inline

Standalone skills run in the user's main-thread model. Security audits demand Opus's adversarial reasoning regardless of what the user happens to be on. Dispatching to a subagent with explicit `model: "opus"` (read from `agents/security.md`) guarantees the audit always runs on the right model. This mirrors how `/ddw:sendit` dispatches developer work with `model: "sonnet"` from `agents/developer.md`.
