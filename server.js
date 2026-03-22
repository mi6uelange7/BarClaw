#!/usr/bin/env node
// ClawPanel server — thin proxy over openclaw CLI
const http = require('http');
const { exec } = require('child_process');
const fs = require('fs');
const path = require('path');

const PORT = 3999;
const STATIC_DIR = __dirname;
const OPENCLAW_HOME = path.join(process.env.HOME, '.openclaw');
const WORKSPACE = path.join(OPENCLAW_HOME, 'workspace');

function run(cmd, timeout = 12000) {
  return new Promise((resolve, reject) => {
    exec(cmd, { timeout, maxBuffer: 1024 * 512 }, (err, stdout, stderr) => {
      if (err && !stdout) return reject(err);
      resolve(stdout || '');
    });
  });
}

function json(res, data, status = 200) {
  const body = JSON.stringify(data);
  res.writeHead(status, {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET,POST,DELETE,OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
  });
  res.end(body);
}

function parseBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', d => (body += d));
    req.on('end', () => {
      try { resolve(JSON.parse(body || '{}')); }
      catch { resolve({}); }
    });
    req.on('error', reject);
  });
}

function parseSkillsTable(raw) {
  const skills = [];
  const lines = raw.split('\n');
  for (const line of lines) {
    // Match table rows: │ ✓/✗ status │ emoji name │ description │ source │
    const m = line.match(/[│|]\s*(✓ ready|✗ missing)\s*[│|]\s*(.+?)\s*[│|]\s*(.*?)\s*[│|]/);
    if (m) {
      const statusStr = m[1].trim();
      const namePart = m[2].trim();
      const desc = m[3].trim();
      // Extract emoji + name (emoji is first char(s) before space)
      const nm = namePart.match(/^([\p{Emoji}\u200d]+\s*)?(.+)$/u);
      skills.push({
        ready: statusStr === '✓ ready',
        icon: nm ? (nm[1] || '🔧').trim() : '🔧',
        name: nm ? nm[2].trim() : namePart,
        description: desc,
      });
    }
  }
  // Extract summary line "Skills (X/Y ready)"
  const summary = (raw.match(/Skills \((\d+\/\d+) ready\)/) || [])[1] || '';
  return { summary, skills };
}

async function handle(req, res) {
  const url = new URL(req.url, `http://localhost:${PORT}`);
  const pathname = url.pathname;

  // CORS preflight
  if (req.method === 'OPTIONS') {
    res.writeHead(204, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET,POST,DELETE,OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    });
    return res.end();
  }

  // Serve static files (index.html)
  if (req.method === 'GET' && (pathname === '/' || pathname === '/index.html')) {
    const file = fs.readFileSync(path.join(STATIC_DIR, 'index.html'));
    res.writeHead(200, { 'Content-Type': 'text/html' });
    return res.end(file);
  }

  try {
    // ── API ─────────────────────────────────────────────────

    if (req.method === 'GET' && pathname === '/api/status') {
      const [statusOut, healthOut] = await Promise.all([
        run('openclaw status --json').catch(() => '{}'),
        run('openclaw health 2>/dev/null').catch(() => ''),
      ]);
      let status = {};
      try { status = JSON.parse(statusOut); } catch {}
      return json(res, { ...status, healthRaw: healthOut.trim() });
    }

    if (req.method === 'GET' && pathname === '/api/sessions') {
      const out = await run('openclaw sessions --json');
      let data = {};
      try { data = JSON.parse(out); } catch {}
      return json(res, data);
    }

    if (req.method === 'GET' && pathname === '/api/logs') {
      const limit = url.searchParams.get('limit') || '120';
      const out = await run(`openclaw logs --limit ${limit} --plain --timeout 6000`).catch(() => '');
      const lines = out.split('\n').filter(Boolean);
      return json(res, { lines });
    }

    if (req.method === 'GET' && pathname === '/api/skills') {
      const out = await run('openclaw skills list').catch(() => '');
      return json(res, parseSkillsTable(out));
    }

    if (req.method === 'GET' && pathname === '/api/channels') {
      const out = await run('openclaw channels list').catch(() => '');
      return json(res, { raw: out.trim() });
    }

    if (req.method === 'GET' && pathname === '/api/cron') {
      const out = await run('openclaw cron list').catch(() => '');
      // Try JSON, else return raw
      try { return json(res, { jobs: JSON.parse(out) }); } catch {}
      return json(res, { raw: out.trim() });
    }

    if (req.method === 'GET' && pathname === '/api/workspace') {
      const files = fs.readdirSync(WORKSPACE).filter(f => f.endsWith('.md')).sort();
      // Also list memory files
      const memDir = path.join(WORKSPACE, 'memory');
      const memFiles = fs.existsSync(memDir)
        ? fs.readdirSync(memDir).filter(f => f.endsWith('.md')).map(f => 'memory/' + f)
        : [];
      return json(res, { files: [...files, ...memFiles] });
    }

    if (req.method === 'GET' && pathname.startsWith('/api/workspace/')) {
      const filename = decodeURIComponent(pathname.replace('/api/workspace/', ''));
      // Prevent path traversal
      const filePath = path.resolve(WORKSPACE, filename);
      if (!filePath.startsWith(WORKSPACE)) return json(res, { error: 'Forbidden' }, 403);
      if (!fs.existsSync(filePath)) return json(res, { error: 'Not found' }, 404);
      const content = fs.readFileSync(filePath, 'utf8');
      return json(res, { filename, content });
    }

    if (req.method === 'POST' && pathname === '/api/chat') {
      const body = await parseBody(req);
      if (!body.message) return json(res, { error: 'message required' }, 400);
      const escaped = body.message.replace(/"/g, '\\"').replace(/\$/g, '\\$').replace(/`/g, '\\`');
      const out = await run(`openclaw agent -m "${escaped}" --json`, 90000).catch(e => `{"error":"${e.message}"}`);
      let data = {};
      try { data = JSON.parse(out); } catch { data = { raw: out.trim() }; }
      return json(res, data);
    }

    if (req.method === 'POST' && pathname === '/api/heartbeat') {
      // Send a heartbeat ping to the main session
      await run('openclaw agent -m "/heartbeat" --json', 30000).catch(() => {});
      return json(res, { ok: true });
    }

    if (req.method === 'POST' && pathname === '/api/cron/add') {
      const body = await parseBody(req);
      if (!body.schedule || !body.message) return json(res, { error: 'schedule and message required' }, 400);
      const escaped = body.message.replace(/"/g, '\\"');
      const out = await run(`openclaw cron add --every "${body.schedule}" --message "${escaped}" --label "${body.label || 'ClawPanel task'}"`)
        .catch(e => e.message);
      return json(res, { ok: true, output: out });
    }

    if (req.method === 'DELETE' && pathname.startsWith('/api/cron/')) {
      const jobId = pathname.replace('/api/cron/', '');
      const out = await run(`openclaw cron rm "${jobId}"`).catch(e => e.message);
      return json(res, { ok: true, output: out });
    }

    // 404
    json(res, { error: 'Not found' }, 404);

  } catch (err) {
    json(res, { error: err.message }, 500);
  }
}

const server = http.createServer(handle);
server.listen(PORT, '127.0.0.1', () => {
  console.log(`\n🦞 ClawPanel running at http://localhost:${PORT}/\n`);
});
