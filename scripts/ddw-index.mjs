#!/usr/bin/env node
/**
 * ddw-index — read-only index generator for Decision-Driven Workflow consumer repos.
 *
 * Reads task/DEC/PRD source files (under {workflowDir}/{tasks,decisions,prds}/)
 * and overwrites four derived view files in {workflowDir}/logs/:
 *   TASK_LOG.md, DECISION_LOG.md, PRD_LOG.md, RETRO_LOG.md
 *
 * Resolves workflowDir from ddw.json (searched in root, root/workflows,
 * root/.workflows, root/.claude — same as bash scripts).
 *
 * Strictly pure: never mutates source files, never moves or deletes files.
 * Zero npm dependencies — Node 20+ built-ins only.
 *
 * Usage:
 *   ddw-index [--root <path>] [--check] [--dry-run] [--help]
 */

import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

// ---------------------------------------------------------------------------
// CLI parsing
// ---------------------------------------------------------------------------

function parseArgs(argv) {
  const args = argv.slice(2);
  const opts = { root: process.cwd(), check: false, dryRun: false, help: false };
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === '--help' || a === '-h') { opts.help = true; }
    else if (a === '--check') { opts.check = true; }
    else if (a === '--dry-run') { opts.dryRun = true; }
    else if (a === '--root') {
      if (i + 1 >= args.length) { die('--root requires a path argument'); }
      opts.root = args[++i];
    } else {
      die(`Unknown argument: ${a}`);
    }
  }
  return opts;
}

function printHelp() {
  process.stdout.write(`\
ddw-index — regenerate DDW log views from source files

Usage:
  ddw-index [--root <path>] [--check] [--dry-run] [--help]

Options:
  --root <path>   Consumer repo root (default: cwd)
  --check         Read-only: exit 1 if any view is out of date, exit 0 if all match
  --dry-run       Print planned changes without writing files
  --help          Print this message and exit 0

Output files (written to <root>/logs/):
  TASK_LOG.md, DECISION_LOG.md, PRD_LOG.md, RETRO_LOG.md

Strictly pure: source files (tasks/, decisions/, prds/) are never modified.
`);
}

function die(msg) {
  process.stderr.write(`ERROR: ${msg}\n`);
  process.exit(1);
}

// ---------------------------------------------------------------------------
// File-system helpers
// ---------------------------------------------------------------------------

/** Read a glob pattern like dir/*.md — returns list of absolute file paths. */
function globMd(dir) {
  try {
    const entries = fs.readdirSync(dir, { withFileTypes: true });
    return entries
      .filter(e => e.isFile() && e.name.endsWith('.md'))
      .map(e => path.join(dir, e.name));
  } catch {
    return [];
  }
}

function readFile(filePath) {
  try {
    return fs.readFileSync(filePath, 'utf8');
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Frontmatter parsers
// ---------------------------------------------------------------------------

/**
 * Parse TASK file frontmatter (bold-markdown style).
 * Reads **Key:** value lines at the top before first `---` or first `## ` heading.
 */
function parseTaskFrontmatter(content, filePath) {
  const lines = content.split('\n');
  const fm = {};
  for (const line of lines) {
    // Stop at first `---` or `## ` heading (start of body)
    if (line.startsWith('---') || line.startsWith('## ')) break;
    const m = line.match(/^\*\*([A-Za-z][A-Za-z0-9 _-]*):\*\*\s*(.*)$/);
    if (m) {
      fm[m[1].trim().toLowerCase()] = m[2].trim();
    }
  }
  return fm;
}

/**
 * Parse DEC or PRD file frontmatter (plain Key: value style after H1 heading).
 * Returns { fm, title }.
 */
function parsePlainFrontmatter(content, filePath) {
  const lines = content.split('\n');
  let title = '';
  const fm = {};
  let inFm = false;

  for (const line of lines) {
    if (!inFm) {
      // Find the H1 heading — title comes from text after "— "
      if (line.startsWith('# ')) {
        const dashIdx = line.indexOf(' — ');
        title = dashIdx >= 0 ? line.slice(dashIdx + 3).trim() : line.slice(2).trim();
        inFm = true;
        continue;
      }
    } else {
      // Stop at first `## ` heading
      if (line.startsWith('## ')) break;
      // Skip blank lines
      if (line.trim() === '') continue;
      const m = line.match(/^([A-Za-z][A-Za-z0-9 _-]*):\s*(.*)$/);
      if (m) {
        fm[m[1].trim().toLowerCase()] = m[2].trim();
      }
    }
  }
  return { fm, title };
}

/**
 * Extract last Work Log timestamp from task content.
 * Looks for `### YYYY-MM-DDThh:mm:ssZ` lines inside `## Work Log` section.
 */
function extractLastWorkLogTimestamp(content) {
  const lines = content.split('\n');
  let inWorkLog = false;
  let lastTs = '';

  for (const line of lines) {
    if (line.startsWith('## Work Log')) {
      inWorkLog = true;
      continue;
    }
    if (inWorkLog && line.startsWith('## ')) break; // end of section
    if (inWorkLog) {
      const m = line.match(/^### (\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)/);
      if (m) lastTs = m[1];
    }
  }
  return lastTs;
}

/**
 * Extract retrospective body from task content.
 * Returns text between `## Retrospective` and the next `## ` heading.
 */
function extractRetrospective(content) {
  const lines = content.split('\n');
  let inRetro = false;
  const retroLines = [];

  for (const line of lines) {
    if (line.startsWith('## Retrospective')) {
      inRetro = true;
      continue;
    }
    if (inRetro && line.startsWith('## ')) break;
    if (inRetro) retroLines.push(line);
  }

  const body = retroLines.join('\n').trim();
  // Skip empty or placeholder-only retrospectives
  if (!body || isPlaceholderRetro(body)) return '';
  return body;
}

const PLACEHOLDER_PATTERNS = [
  /^_.*_$/,                    // _placeholder_
  /^<!--.*-->$/,               // <!-- comment -->
  /^\(none\)$/i,
  /^none\.?$/i,
  /^n\/a\.?$/i,
  /^todo\.?$/i,
  /^\{.*\}$/,                  // {template placeholder}
];

function isPlaceholderRetro(body) {
  return PLACEHOLDER_PATTERNS.some(p => p.test(body));
}

/**
 * Parse the `Decisions:` array from a PRD frontmatter field.
 * e.g. "[DEC-20260507-x, DEC-20260508-z]" → ["DEC-20260507-x", "DEC-20260508-z"]
 */
function parsePrdDecisionsArray(raw) {
  if (!raw) return [];
  const inner = raw.replace(/^\[/, '').replace(/\]$/, '').trim();
  if (!inner) return [];
  return inner.split(',').map(s => s.trim()).filter(Boolean);
}

// ---------------------------------------------------------------------------
// Source file loaders
// ---------------------------------------------------------------------------

function loadTaskFiles(root) {
  const dirs = [
    path.join(root, 'tasks'),
    path.join(root, 'tasks', 'archive'),
  ];
  const tasks = [];
  const errors = [];

  for (const dir of dirs) {
    for (const filePath of globMd(dir)) {
      const name = path.basename(filePath, '.md');
      if (!name.startsWith('TASK-')) continue;

      const content = readFile(filePath);
      if (content === null) continue;

      const fm = parseTaskFrontmatter(content, filePath);

      if (!fm['status']) {
        errors.push(`${filePath} missing required field 'status'`);
        continue;
      }

      const lastUpdate = extractLastWorkLogTimestamp(content);
      const retro = extractRetrospective(content);

      // Title: from H1 heading if present, else filename
      let title = name;
      const h1 = content.match(/^# (.+)$/m);
      if (h1) title = h1[1].trim();

      tasks.push({
        id: name,
        title,
        owner: fm['owner'] || '',
        priority: fm['priority'] || '',
        status: fm['status'],
        date: fm['date'] || '',
        lastUpdate,
        retro,
        filePath,
      });
    }
  }

  return { tasks, errors };
}

function loadDecisionFiles(root) {
  const dirs = [
    path.join(root, 'decisions'),
    path.join(root, 'decisions', 'archive'),
  ];
  const decisions = [];
  const errors = [];

  for (const dir of dirs) {
    for (const filePath of globMd(dir)) {
      const name = path.basename(filePath, '.md');
      if (!name.startsWith('DEC-')) continue;

      const content = readFile(filePath);
      if (content === null) continue;

      const { fm, title } = parsePlainFrontmatter(content, filePath);

      if (!fm['status']) {
        errors.push(`${filePath} missing required field 'status'`);
        continue;
      }

      decisions.push({
        id: name,
        title: title || name,
        owner: fm['owner'] || '',
        status: fm['status'],
        date: fm['date'] || '',
        filePath,
      });
    }
  }

  return { decisions, errors };
}

function loadPrdFiles(root) {
  const dirs = [
    path.join(root, 'prds'),
    path.join(root, 'prds', 'archive'),
  ];
  const prds = [];
  const errors = [];

  for (const dir of dirs) {
    for (const filePath of globMd(dir)) {
      const name = path.basename(filePath, '.md');
      if (!name.startsWith('PRD-')) continue;

      const content = readFile(filePath);
      if (content === null) continue;

      const { fm, title } = parsePlainFrontmatter(content, filePath);

      if (!fm['status']) {
        errors.push(`${filePath} missing required field 'status'`);
        continue;
      }

      const decisions = parsePrdDecisionsArray(fm['decisions'] || '');

      prds.push({
        id: name,
        title: title || name,
        owner: fm['owner'] || '',
        status: fm['status'],
        date: fm['date'] || '',
        decisions,
        filePath,
      });
    }
  }

  return { prds, errors };
}

// ---------------------------------------------------------------------------
// Sorting helpers
// ---------------------------------------------------------------------------

function cmpDateDesc(a, b) {
  if (a < b) return 1;
  if (a > b) return -1;
  return 0;
}

const PRD_STATUS_ORDER = ['draft', 'solid', 'parked', 'closed'];

function prdStatusRank(status) {
  const idx = PRD_STATUS_ORDER.indexOf(status.toLowerCase());
  return idx >= 0 ? idx : PRD_STATUS_ORDER.length;
}

// ---------------------------------------------------------------------------
// View generators
// ---------------------------------------------------------------------------

function autoHeader(datetime) {
  return (
    `<!-- AUTO-GENERATED by ddw-index. Do not edit. Edit task/DEC/PRD files instead. -->\n` +
    `<!-- Last regenerated: ${datetime} -->\n`
  );
}

/**
 * Generate TASK_LOG.md content.
 * Sort: non-closed rows (by lastUpdate desc) ABOVE closed rows (by lastUpdate desc).
 */
function genTaskLog(tasks, datetime) {
  const sorted = [...tasks].sort((a, b) => {
    const aClosed = a.status.toLowerCase() === 'closed' || a.status.toLowerCase() === 'done';
    const bClosed = b.status.toLowerCase() === 'closed' || b.status.toLowerCase() === 'done';
    if (aClosed !== bClosed) return aClosed ? 1 : -1;
    return cmpDateDesc(a.lastUpdate || a.date, b.lastUpdate || b.date);
  });

  const rows = sorted.map(t =>
    `| ${t.id} | ${t.owner} | ${t.priority} | ${t.status} | ${t.lastUpdate || ''} |`
  );

  return [
    `# Task Log`,
    ``,
    autoHeader(datetime),
    `Quick overview of all tasks — status and last update only.`,
    `Detail lives in each task file's Work Log section.`,
    ``,
    `| Task | Owner | Priority | Status | Last Update |`,
    `|---|---|---|---|---|`,
    ...rows,
  ].join('\n') + '\n';
}

/**
 * Generate DECISION_LOG.md content.
 * Sort: by Date descending.
 */
function genDecisionLog(decisions, datetime) {
  const sorted = [...decisions].sort((a, b) => cmpDateDesc(a.date, b.date));

  const rows = sorted.map(d =>
    `| ${d.id} | ${d.title} | ${d.owner} | ${d.status} | ${d.date} |`
  );

  return [
    `# Decision Log`,
    ``,
    autoHeader(datetime),
    `Index of all decisions. Individual decision files are in \`decisions/\`.`,
    ``,
    `**Decision status values:**`,
    ``,
    `| Status | Meaning | TASK creation |`,
    `|---|---|---|`,
    `| \`proposed\` | Under discussion — not yet confirmed | **Not allowed** |`,
    `| \`decided\` | Owner has explicitly confirmed | Allowed |`,
    `| \`rejected\` | Will not be implemented | Not applicable |`,
    `| \`parked\` | Deferred indefinitely | Not applicable |`,
    ``,
    `---`,
    ``,
    `| ID | Title | Owner | Status | Datetime |`,
    `|---|---|---|---|---|`,
    ...rows,
  ].join('\n') + '\n';
}

/**
 * Generate PRD_LOG.md content.
 * Sort: by status group (draft, solid, parked, closed), then Date desc within group.
 */
function genPrdLog(prds, datetime) {
  const sorted = [...prds].sort((a, b) => {
    const rankDiff = prdStatusRank(a.status) - prdStatusRank(b.status);
    if (rankDiff !== 0) return rankDiff;
    return cmpDateDesc(a.date, b.date);
  });

  const rows = sorted.map(p =>
    `| ${p.id} | ${p.title} | ${p.owner} | ${p.status} | ${p.date} |`
  );

  return [
    `# PRD Log`,
    ``,
    autoHeader(datetime),
    `Index of all PRDs. Individual PRD files are in \`prds/\`.`,
    ``,
    `**PRD status values:**`,
    ``,
    `| Status | Meaning |`,
    `|---|---|`,
    `| \`draft\` | Still being shaped — gaps may remain |`,
    `| \`solid\` | Owner confirmed adequate — ready for \`/ddw:decision\` |`,
    `| \`parked\` | On hold — not being pursued right now |`,
    `| \`closed\` | Decisions created; PRD's job is done |`,
    ``,
    `| ID | Title | Owner | Status | Datetime |`,
    `|---|---|---|---|---|`,
    ...rows,
  ].join('\n') + '\n';
}

/**
 * Generate RETRO_LOG.md content.
 * Sort: by task Date descending. Skip tasks with empty/placeholder retrospectives.
 */
function genRetroLog(tasks, datetime) {
  const withRetro = tasks
    .filter(t => t.retro)
    .sort((a, b) => cmpDateDesc(a.date, b.date));

  const entries = withRetro.map(t =>
    `### ${t.date} — ${t.id}\n${t.retro}`
  );

  return [
    `# Retrospective Log`,
    ``,
    autoHeader(datetime),
    `Learnings captured after each task. Fed back into guardrails, invariants, and workflow improvements.`,
    ``,
    `---`,
    ``,
    `## Entries`,
    ``,
    ...entries.flatMap(e => [e, '']),
  ].join('\n').trimEnd() + '\n';
}

// ---------------------------------------------------------------------------
// --check mode: diff ignoring the "Last regenerated:" line
// ---------------------------------------------------------------------------

function stripTimestampLine(content) {
  return content
    .split('\n')
    .filter(line => !line.startsWith('<!-- Last regenerated:'))
    .join('\n');
}

function checkDrift(viewFiles, logsDir) {
  const drifted = [];
  for (const [name, planned] of Object.entries(viewFiles)) {
    const filePath = path.join(logsDir, name);
    const existing = readFile(filePath);
    if (existing === null) {
      drifted.push(`logs/${name} (file does not exist)`);
      continue;
    }
    if (stripTimestampLine(planned) !== stripTimestampLine(existing)) {
      drifted.push(`logs/${name} needs regeneration`);
    }
  }
  return drifted;
}

// ---------------------------------------------------------------------------
// --dry-run: compute row-level diff
// ---------------------------------------------------------------------------

function dryRunDiff(name, planned, logsDir) {
  const filePath = path.join(logsDir, name);
  const existing = readFile(filePath);
  if (existing === null) {
    process.stdout.write(`${name}: NEW file (${planned.split('\n').length} lines)\n`);
    return;
  }

  const newLines = new Set(planned.split('\n').filter(l => l.startsWith('|')));
  const oldLines = new Set(existing.split('\n').filter(l => l.startsWith('|')));

  const added = [...newLines].filter(l => !oldLines.has(l));
  const removed = [...oldLines].filter(l => !newLines.has(l));

  if (added.length === 0 && removed.length === 0) {
    process.stdout.write(`${name}: no data row changes (timestamp differs)\n`);
  } else {
    process.stdout.write(`${name}:\n`);
    for (const r of removed) process.stdout.write(`  - ${r}\n`);
    for (const a of added)   process.stdout.write(`  + ${a}\n`);
  }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main() {
  const opts = parseArgs(process.argv);

  if (opts.help) {
    printHelp();
    process.exit(0);
  }

  const root = path.resolve(opts.root);

  // Locate ddw.json (try root first, then standard workflowDir locations)
  // and resolve workflowDir from it. This determines the base path for
  // tasks/, decisions/, prds/, and logs/ — matching the bash scripts'
  // discovery rules so multi-location installs work consistently.
  const ddwJsonCandidates = [
    root,
    path.join(root, 'workflows'),
    path.join(root, '.workflows'),
    path.join(root, '.claude'),
  ];
  let ddwJsonDir = null;
  for (const dir of ddwJsonCandidates) {
    if (fs.existsSync(path.join(dir, 'ddw.json'))) {
      ddwJsonDir = dir;
      break;
    }
  }

  let workflowDir = '';
  if (ddwJsonDir) {
    try {
      const cfg = JSON.parse(fs.readFileSync(path.join(ddwJsonDir, 'ddw.json'), 'utf8'));
      // workflowDir is relative to root. Default to whichever subdir we
      // found ddw.json in (legacy: root → ''; standard: 'workflows').
      if (typeof cfg.workflowDir === 'string') {
        workflowDir = cfg.workflowDir;
      } else {
        workflowDir = path.relative(root, ddwJsonDir);
      }
    } catch {
      workflowDir = path.relative(root, ddwJsonDir);
    }
  }
  // base = where tasks/, decisions/, prds/, logs/ live
  const base = workflowDir ? path.join(root, workflowDir) : root;
  const logsDir = path.join(base, 'logs');

  // Load all source files (using base, not root)
  const { tasks, errors: taskErrors } = loadTaskFiles(base);
  const { decisions, errors: decErrors } = loadDecisionFiles(base);
  const { prds, errors: prdErrors } = loadPrdFiles(base);

  const allErrors = [...taskErrors, ...decErrors, ...prdErrors];
  if (allErrors.length > 0) {
    for (const e of allErrors) process.stderr.write(`ERROR: ${e}\n`);
    process.stderr.write(
      `\nView files were NOT written due to the above errors.\n` +
      `Would have written:\n` +
      `  ${path.join(logsDir, 'TASK_LOG.md')}\n` +
      `  ${path.join(logsDir, 'DECISION_LOG.md')}\n` +
      `  ${path.join(logsDir, 'PRD_LOG.md')}\n` +
      `  ${path.join(logsDir, 'RETRO_LOG.md')}\n`
    );
    process.exit(1);
  }

  const datetime = new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');

  const viewFiles = {
    'TASK_LOG.md':     genTaskLog(tasks, datetime),
    'DECISION_LOG.md': genDecisionLog(decisions, datetime),
    'PRD_LOG.md':      genPrdLog(prds, datetime),
    'RETRO_LOG.md':    genRetroLog(tasks, datetime),
  };

  // --check mode
  if (opts.check) {
    const drifted = checkDrift(viewFiles, logsDir);
    if (drifted.length > 0) {
      for (const d of drifted) process.stdout.write(`DRIFT: ${d}\n`);
      process.exit(1);
    }
    process.exit(0);
  }

  // --dry-run mode
  if (opts.dryRun) {
    for (const name of Object.keys(viewFiles)) {
      dryRunDiff(name, viewFiles[name], logsDir);
    }
    process.exit(0);
  }

  // Default: write files
  try {
    fs.mkdirSync(logsDir, { recursive: true });
  } catch (e) {
    die(`Could not create logs/ directory: ${e.message}`);
  }

  for (const [name, content] of Object.entries(viewFiles)) {
    const filePath = path.join(logsDir, name);
    try {
      fs.writeFileSync(filePath, content, 'utf8');
    } catch (e) {
      die(`Could not write ${filePath}: ${e.message}`);
    }
  }

  process.stdout.write(
    `ddw-index: wrote 4 view files to ${logsDir}\n` +
    `  TASK_LOG.md (${tasks.length} task${tasks.length !== 1 ? 's' : ''})\n` +
    `  DECISION_LOG.md (${decisions.length} decision${decisions.length !== 1 ? 's' : ''})\n` +
    `  PRD_LOG.md (${prds.length} PRD${prds.length !== 1 ? 's' : ''})\n` +
    `  RETRO_LOG.md (${tasks.filter(t => t.retro).length} entr${tasks.filter(t => t.retro).length !== 1 ? 'ies' : 'y'})\n`
  );
}

main().catch(e => die(e.message));
