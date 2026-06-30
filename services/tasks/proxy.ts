// services/tasks/proxy.ts
// Tailnet reverse proxy for holdco-tasks. Injects auth so the browser needs
// no login. Run: bun proxy.ts  (reads TASKS_OWNER_TOKEN, TASKS_AGENT_TOKEN from env)

const TARGET = process.env.TASKS_WORKER_URL ?? "https://your-tasks-worker.example.workers.dev";
const PORT   = 4747;

const OWNER_TOKEN = process.env.TASKS_OWNER_TOKEN ?? "";
const AGENT_TOKEN = process.env.TASKS_AGENT_TOKEN ?? "";

if (!OWNER_TOKEN) console.warn("TASKS_OWNER_TOKEN not set — browser paths will hit auth wall");
if (!AGENT_TOKEN) console.warn("TASKS_AGENT_TOKEN not set — /api/v1/* will be unauthorised");

Bun.serve({
  port: PORT,
  async fetch(req) {
    const url = new URL(req.url);
    url.hostname = new URL(TARGET).hostname;
    url.port = "";          // clear the source port (4747) before switching to https
    url.protocol = "https:";

    const headers = new Headers(req.headers);
    headers.delete("host");
    // Prevent upstream compression so we don't need to re-encode for the client
    headers.delete("accept-encoding");

    if (url.pathname.startsWith("/api/v1/")) {
      // For API paths inject Bearer so agents need no token from inside the tailnet
      headers.set("Authorization", `Bearer ${AGENT_TOKEN}`);
    } else {
      // For UI paths inject the session cookie — browser never needs to log in
      const existing = headers.get("Cookie") ?? "";
      const sessionCookie = `session=${encodeURIComponent(OWNER_TOKEN)}`;
      headers.set("Cookie", existing ? `${existing}; ${sessionCookie}` : sessionCookie);
    }

    const hasBody = req.body !== null && req.method !== "GET" && req.method !== "HEAD";
    const upstreamReq: RequestInit = {
      method:  req.method,
      headers,
    };
    if (hasBody) {
      upstreamReq.body = req.body;
      // @ts-ignore — Bun supports duplex for streaming request bodies
      upstreamReq.duplex = "half";
    }

    try {
      return await fetch(url.toString(), upstreamReq);
    } catch (err) {
      console.error("upstream fetch failed:", err);
      return new Response("proxy error", { status: 502 });
    }
  },
});

console.log(`proxy listening on :${PORT} → ${TARGET}`);
