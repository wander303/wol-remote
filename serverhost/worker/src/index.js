// Cloudflare Workers - WOL Remote API
// 部署: npm install -g wrangler && wrangler deploy

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;

    // ── CORS ──
    if (request.method === "OPTIONS") {
      return new Response(null, {
        headers: { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "GET,POST", "Access-Control-Allow-Headers": "Content-Type,X-API-Token" },
      });
    }

    // ── 认证（API_TOKEN 通过 wrangler secret 设置）──
    function checkAuth(req) {
      const token = req.headers.get("X-API-Token") || url.searchParams.get("token");
      if (token !== env.API_TOKEN) return false;
      return true;
    }

    // ── API 路由 ──

    // POST /api/wake — 用户触发唤醒
    if (path === "/api/wake" && request.method === "POST") {
      if (!checkAuth(request)) return new Response("Unauthorized", { status: 401 });
      const pending = await env.WOL_KV.get("pending", "text");
      if (pending === "WAKE") {
        return Response.json({ status: "already_queued" });
      }
      await env.WOL_KV.put("pending", "WAKE");
      await env.WOL_KV.put("last_wake", new Date().toISOString());
      return Response.json({ status: "queued" });
    }

    // GET /api/poll — 路由器轮询
    if (path === "/api/poll" && request.method === "GET") {
      if (!checkAuth(request)) return new Response("Unauthorized", { status: 401 });
      const pending = await env.WOL_KV.get("pending", "text");
      return new Response(pending === "WAKE" ? "WAKE" : "IDLE", {
        headers: { "Content-Type": "text/plain" },
      });
    }

    // POST /api/ack — 路由器确认已唤醒
    if (path === "/api/ack" && request.method === "POST") {
      if (!checkAuth(request)) return new Response("Unauthorized", { status: 401 });
      await env.WOL_KV.put("pending", "IDLE");
      await env.WOL_KV.put("last_ack", new Date().toISOString());
      return Response.json({ status: "ok" });
    }

    // GET /api/status — 查询状态
    if (path === "/api/status" && request.method === "GET") {
      if (!checkAuth(request)) return new Response("Unauthorized", { status: 401 });
      const [pending, last_wake, last_ack] = await Promise.all([
        env.WOL_KV.get("pending", "text"),
        env.WOL_KV.get("last_wake", "text"),
        env.WOL_KV.get("last_ack", "text"),
      ]);
      return Response.json({ pending: pending === "WAKE", last_wake, last_ack });
    }

    // GET /api/health — 健康检查
    if (path === "/api/health") {
      return Response.json({ status: "ok", service: "wol-remote" });
    }

    return new Response("Not Found", { status: 404 });
  },
};
