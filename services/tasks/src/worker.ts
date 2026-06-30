/**
 * holdco-tasks — Cloudflare Worker
 *
 * /api/v1/* → JSON REST API (AGENT_TOKEN Bearer or OWNER_TOKEN session cookie)
 * /login    → owner auth form + cookie issuance
 * /*        → static kanban UI (ASSETS binding — public/)
 *
 * Secrets (set via `wrangler secret put`, NOT in git):
 *   OWNER_TOKEN  — browser session; submit at /login to get cookie
 *   AGENT_TOKEN  — Bearer token for agents and bin/holdco CLI
 */

export interface Env {
  DB: D1Database;
  ASSETS: Fetcher;
  OWNER_TOKEN: string;
  AGENT_TOKEN: string;
}

type Row = Record<string, unknown>;

const SESSION_COOKIE = "session";
const COOKIE_MAX_AGE = 86400 * 30; // 30 days

// ---- auth -------------------------------------------------------------------

function getCookie(request: Request, name: string): string | null {
  const header = request.headers.get("Cookie") ?? "";
  const m = header.match(new RegExp(`(?:^|;\\s*)${name}=([^;]*)`));
  return m ? decodeURIComponent(m[1]) : null;
}

/** Accept Bearer (agents) or session cookie (owner). */
function checkAuth(request: Request, env: Env): boolean {
  const auth = request.headers.get("Authorization") ?? "";
  if (auth.startsWith("Bearer ")) {
    const tok = auth.slice(7).trim();
    if (tok === env.AGENT_TOKEN || tok === env.OWNER_TOKEN) return true;
  }
  return getCookie(request, SESSION_COOKIE) === env.OWNER_TOKEN;
}

function checkOwnerCookie(request: Request, env: Env): boolean {
  return getCookie(request, SESSION_COOKIE) === env.OWNER_TOKEN;
}

// ---- response helpers -------------------------------------------------------

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8" },
  });
}

// ---- login page -------------------------------------------------------------

const LOGIN_HTML = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>holdco tasks — sign in</title>
<style>
*{box-sizing:border-box}
body{font-family:system-ui,-apple-system,sans-serif;background:#0d0d0d;color:#e8e8e8;
  display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0}
.card{background:#1a1a1a;border:1px solid #2a2a2a;border-radius:10px;padding:32px;
  width:320px;box-shadow:0 4px 20px rgba(0,0,0,.5)}
h1{margin:0 0 6px;font-size:1.1rem;font-weight:600;color:#e8e8e8}
p{margin:0 0 20px;font-size:.85rem;color:#888}
label{display:block;font-size:.8rem;color:#aaa;margin-bottom:6px}
input[type=password]{width:100%;padding:10px 12px;border:1px solid #333;border-radius:6px;
  background:#111;color:#e8e8e8;font-size:.95rem;outline:none;transition:border-color .15s}
input[type=password]:focus{border-color:#4a9eff}
button{width:100%;margin-top:12px;padding:10px;border:none;border-radius:6px;
  background:#4a9eff;color:#fff;font-size:.95rem;font-weight:500;cursor:pointer;transition:background .15s}
button:hover{background:#6ab4ff}
.err{margin-top:12px;padding:10px;background:#2d1515;border:1px solid #5c2020;
  border-radius:6px;color:#ff8888;font-size:.85rem;text-align:center}
</style>
</head>
<body>
<div class="card">
  <h1>holdco tasks</h1>
  <p>Owner access required</p>
  <form method="post" action="/login">
    <label for="tok">Owner token</label>
    <input type="password" id="tok" name="token" placeholder="••••••••••••" autofocus>
    <button type="submit">Sign in</button>
    {{ERROR}}
  </form>
</div>
</body>
</html>`;

async function handleLogin(request: Request, env: Env): Promise<Response> {
  if (request.method === "GET") {
    return new Response(LOGIN_HTML.replace("{{ERROR}}", ""), {
      headers: { "Content-Type": "text/html; charset=utf-8" },
    });
  }
  if (request.method === "POST") {
    const form = await request.formData();
    const token = (form.get("token") ?? "").toString().trim();
    if (token === env.OWNER_TOKEN) {
      const cookieVal = encodeURIComponent(token);
      const cookie = `${SESSION_COOKIE}=${cookieVal}; HttpOnly; Secure; SameSite=Strict; Max-Age=${COOKIE_MAX_AGE}; Path=/`;
      return new Response(null, {
        status: 302,
        headers: { Location: "/", "Set-Cookie": cookie },
      });
    }
    return new Response(LOGIN_HTML.replace("{{ERROR}}", '<div class="err">Invalid token — try again.</div>'), {
      status: 401,
      headers: { "Content-Type": "text/html; charset=utf-8" },
    });
  }
  return new Response("Method Not Allowed", { status: 405 });
}

// ---- api routes -------------------------------------------------------------

async function handleAPI(request: Request, env: Env, path: string, url: URL): Promise<Response> {
  const method = request.method;

  // GET /ventures  POST /ventures
  if (path === "/ventures") {
    if (method === "GET") {
      const { results } = await env.DB.prepare(
        "SELECT * FROM ventures ORDER BY title"
      ).all<Row>();
      return json(results);
    }
    if (method === "POST") {
      const body = await request.json<{ id: string; title: string; tagline?: string }>();
      if (!body.id || !body.title) return json({ error: "id and title required" }, 400);
      // Upsert so re-registering a venture refreshes its canonical title/tagline,
      // correcting any stub auto-created by an early task post (see POST /tasks).
      await env.DB.prepare(
        "INSERT INTO ventures (id, title, tagline) VALUES (?, ?, ?) " +
        "ON CONFLICT(id) DO UPDATE SET title = excluded.title, tagline = excluded.tagline"
      ).bind(body.id, body.title, body.tagline ?? null).run();
      return json(body, 201);
    }
  }

  // GET /tasks  POST /tasks
  if (path === "/tasks") {
    if (method === "GET") {
      const clauses = [
        "SELECT t.*, v.title AS venture_title,",
        "  (SELECT COUNT(*) FROM comments c WHERE c.task_id = t.id) AS comment_count",
        "FROM tasks t LEFT JOIN ventures v ON t.venture_id = v.id",
        "WHERE 1=1",
      ];
      const binds: unknown[] = [];
      const q = (k: string) => url.searchParams.get(k);

      if (q("venture") === "__inbox__") { clauses.push("AND t.venture_id IS NULL"); }
      else if (q("venture")) { clauses.push("AND t.venture_id = ?"); binds.push(q("venture")); }
      if (q("status"))   { clauses.push("AND t.status = ?");     binds.push(q("status")); }
      if (q("priority")) { clauses.push("AND t.priority = ?");   binds.push(q("priority")); }
      if (q("kind"))     { clauses.push("AND t.kind = ?");       binds.push(q("kind")); }
      if (q("assignee")) { clauses.push("AND t.assignee = ?");   binds.push(q("assignee")); }
      if (q("blocked_on_user") === "1") clauses.push("AND t.blocked_on_user = 1");
      clauses.push("ORDER BY CASE t.priority WHEN 'P0' THEN 0 WHEN 'P1' THEN 1 ELSE 2 END, t.created_at");

      const { results } = await env.DB.prepare(clauses.join(" ")).bind(...binds).all<Row>();
      return json(results);
    }
    if (method === "POST") {
      const b = await request.json<{
        id?: string; venture_id?: string; title: string; description?: string;
        priority?: string; status?: string; domain?: string; assignee?: string;
        blocked_on_user?: boolean | number; kind?: string;
      }>();
      if (!b.title) return json({ error: "title required" }, 400);

      const id = b.id ?? b.title.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 60);
      const priority = b.priority ?? "P2";
      const status   = b.status   ?? "open";
      const kind     = b.kind     ?? "task";

      // Self-heal venture linkage: a task may be filed against a venture before
      // holdco has registered it in D1. Auto-create a stub (INSERT OR IGNORE) so
      // the FK to ventures(id) holds; a later venture import refreshes the title.
      if (b.venture_id) {
        await env.DB.prepare(
          "INSERT OR IGNORE INTO ventures (id, title) VALUES (?, ?)"
        ).bind(b.venture_id, b.venture_id).run();
      }

      try {
        await env.DB.prepare(`
          INSERT INTO tasks (id, venture_id, title, description, priority, status, domain, assignee, blocked_on_user, kind)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        `).bind(
          id, b.venture_id ?? null, b.title, b.description ?? null,
          priority, status, b.domain ?? null, b.assignee ?? null,
          b.blocked_on_user ? 1 : 0, kind
        ).run();
      } catch (err: unknown) {
        const msg = err instanceof Error ? err.message : String(err);
        if (msg.includes("UNIQUE")) return json({ error: `Task id '${id}' already exists` }, 409);
        throw err;
      }

      const row = await env.DB.prepare("SELECT * FROM tasks WHERE id = ?").bind(id).first<Row>();
      return json(row, 201);
    }
  }

  // /tasks/:id
  const taskMatch = path.match(/^\/tasks\/([^/]+)$/);
  if (taskMatch) {
    const id = decodeURIComponent(taskMatch[1]);

    if (method === "GET") {
      const row = await env.DB.prepare("SELECT * FROM tasks WHERE id = ?").bind(id).first<Row>();
      return row ? json(row) : json({ error: "Not found" }, 404);
    }

    if (method === "PATCH") {
      const b = await request.json<Row>();
      const allowed = ["title", "description", "priority", "status", "domain", "assignee", "blocked_on_user", "kind", "venture_id"];
      const sets = ["updated_at = datetime('now')"];
      const binds: unknown[] = [];
      for (const key of allowed) {
        if (key in b) {
          sets.push(`${key} = ?`);
          binds.push(key === "blocked_on_user" ? (b[key] ? 1 : 0) : b[key]);
        }
      }
      if (sets.length === 1) return json({ error: "No updatable fields" }, 400);
      binds.push(id);
      await env.DB.prepare(`UPDATE tasks SET ${sets.join(", ")} WHERE id = ?`).bind(...binds).run();
      const row = await env.DB.prepare("SELECT * FROM tasks WHERE id = ?").bind(id).first<Row>();
      return row ? json(row) : json({ error: "Not found" }, 404);
    }

    if (method === "DELETE") {
      const exists = await env.DB.prepare("SELECT id FROM tasks WHERE id = ?").bind(id).first();
      if (!exists) return json({ error: "Not found" }, 404);
      await env.DB.prepare("DELETE FROM tasks WHERE id = ?").bind(id).run();
      return json({ deleted: id });
    }
  }

  // GET /comments?undelivered=1[&venture=<id>]  — comments not yet pushed to an
  // operator session, joined with their task's venture + title. Powers the
  // board→operator delivery loop (bin/holdco comments), mirroring the email inbox.
  if (path === "/comments" && method === "GET") {
    const clauses = [
      "SELECT c.*, t.venture_id, t.title AS task_title",
      "FROM comments c JOIN tasks t ON c.task_id = t.id",
      "WHERE 1=1",
    ];
    const binds: unknown[] = [];
    if (url.searchParams.get("undelivered") === "1") clauses.push("AND c.delivered_at IS NULL");
    const venture = url.searchParams.get("venture");
    if (venture) { clauses.push("AND t.venture_id = ?"); binds.push(venture); }
    clauses.push("ORDER BY c.created_at ASC");
    const { results } = await env.DB.prepare(clauses.join(" ")).bind(...binds).all<Row>();
    return json(results);
  }

  // POST /comments/:id/delivered  — stamp a comment delivered (exactly-once guard).
  const deliveredMatch = path.match(/^\/comments\/(\d+)\/delivered$/);
  if (deliveredMatch && method === "POST") {
    const id = Number(deliveredMatch[1]);
    await env.DB.prepare(
      "UPDATE comments SET delivered_at = datetime('now') WHERE id = ? AND delivered_at IS NULL"
    ).bind(id).run();
    const row = await env.DB.prepare("SELECT * FROM comments WHERE id = ?").bind(id).first<Row>();
    return row ? json(row) : json({ error: "Not found" }, 404);
  }

  // /tasks/:id/comments  — must come before taskMatch (different suffix)
  const commentsMatch = path.match(/^\/tasks\/([^/]+)\/comments$/);
  if (commentsMatch) {
    const taskId = decodeURIComponent(commentsMatch[1]);
    const taskExists = await env.DB.prepare("SELECT id FROM tasks WHERE id = ?").bind(taskId).first();
    if (!taskExists) return json({ error: "Task not found" }, 404);

    if (method === "GET") {
      const { results } = await env.DB.prepare(
        "SELECT * FROM comments WHERE task_id = ? ORDER BY created_at ASC"
      ).bind(taskId).all<Row>();
      return json(results);
    }

    if (method === "POST") {
      const b = await request.json<{ author?: string; body: string }>();
      if (!b.body?.trim()) return json({ error: "body required" }, 400);
      const author = (b.author?.trim() || "owner");
      const row = await env.DB.prepare(
        "INSERT INTO comments (task_id, author, body) VALUES (?, ?, ?) RETURNING *"
      ).bind(taskId, author, b.body.trim()).first<Row>();
      return json(row, 201);
    }
  }

  // GET /asks — blocked_on_user tasks across all ventures
  if (path === "/asks" && method === "GET") {
    const { results } = await env.DB.prepare(`
      SELECT t.*, v.title AS venture_title,
        (SELECT COUNT(*) FROM comments c WHERE c.task_id = t.id) AS comment_count
      FROM   tasks t
      JOIN   ventures v ON t.venture_id = v.id
      WHERE  t.blocked_on_user = 1
        AND  t.status != 'done'
      ORDER  BY CASE t.priority WHEN 'P0' THEN 0 WHEN 'P1' THEN 1 ELSE 2 END, t.updated_at DESC
    `).all<Row>();
    return json(results);
  }

  return json({ error: "Not found" }, 404);
}

// ---- main entry point -------------------------------------------------------

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      const url = new URL(request.url);
      const { pathname } = url;

      // Login page (unauthenticated)
      if (pathname === "/login") return handleLogin(request, env);

      // REST API — Bearer or cookie auth
      if (pathname.startsWith("/api/v1/")) {
        if (!checkAuth(request, env)) return json({ error: "Unauthorized" }, 401);
        return await handleAPI(request, env, pathname.slice("/api/v1".length), url);
      }

      // Static kanban UI — owner cookie required
      if (!checkOwnerCookie(request, env)) {
        return Response.redirect(new URL("/login", request.url).href, 302);
      }
      return env.ASSETS.fetch(request);
    } catch (err) {
      // Error boundary: a leaked exception becomes Cloudflare error 1101 (opaque
      // 500). Always return structured JSON so failures stay debuggable.
      const detail = err instanceof Error ? err.message : String(err);
      return json({ error: "Internal error", detail }, 500);
    }
  },
};
