export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;

    // ── 静态页面 ──
    if (path === "/" || path === "/index.html") {
      return new Response(HTML, { headers: { "Content-Type": "text/html; charset=utf-8" } });
    }

    // ── CORS ──
    if (request.method === "OPTIONS") {
      return new Response(null, {
        headers: { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "GET,POST", "Access-Control-Allow-Headers": "Content-Type,X-API-Token" },
      });
    }

    // ── Auth ──
    function checkAuth() {
      const token = request.headers.get("X-API-Token") || url.searchParams.get("token");
      if (token !== env.API_TOKEN) return false;
      return true;
    }

    // ── API 路由 ──
    if (path === "/api/wake" && request.method === "POST") {
      if (!checkAuth()) return new Response("Unauthorized", { status: 401 });
      const pending = await env.WOL_KV.get("pending", "text");
      if (pending === "WAKE") return Response.json({ status: "already_queued" });
      await env.WOL_KV.put("pending", "WAKE");
      await env.WOL_KV.put("last_wake", new Date().toISOString());
      return Response.json({ status: "queued" });
    }

    if (path === "/api/poll" && request.method === "GET") {
      if (!checkAuth()) return new Response("Unauthorized", { status: 401 });
      const pending = await env.WOL_KV.get("pending", "text");
      return new Response(pending === "WAKE" ? "WAKE" : "IDLE", { headers: { "Content-Type": "text/plain" } });
    }

    if (path === "/api/ack" && request.method === "POST") {
      if (!checkAuth()) return new Response("Unauthorized", { status: 401 });
      await env.WOL_KV.put("pending", "IDLE");
      await env.WOL_KV.put("last_ack", new Date().toISOString());
      return Response.json({ status: "ok" });
    }

    if (path === "/api/status" && request.method === "GET") {
      if (!checkAuth()) return new Response("Unauthorized", { status: 401 });
      const [pending, last_wake, last_ack] = await Promise.all([
        env.WOL_KV.get("pending", "text"), env.WOL_KV.get("last_wake", "text"), env.WOL_KV.get("last_ack", "text"),
      ]);
      return Response.json({ pending: pending === "WAKE", last_wake, last_ack });
    }

    if (path === "/api/health") {
      return Response.json({ status: "ok", service: "wol-remote" });
    }

    return new Response("Not Found", { status: 404 });
  },
};

const HTML = `<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>WOL Remote</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:system-ui,-apple-system,sans-serif;background:#f0f2f5;color:#333;min-height:100vh;display:flex;align-items:center;justify-content:center}
.card{background:#fff;border-radius:16px;box-shadow:0 2px 12px rgba(0,0,0,0.08);padding:32px;width:100%;max-width:420px;margin:20px}
h1{font-size:24px;font-weight:600;margin-bottom:4px;color:#1a1a2e}
.subtitle{font-size:13px;color:#888;margin-bottom:24px}
.field{margin-bottom:16px}
label{display:block;font-size:13px;font-weight:500;color:#555;margin-bottom:4px}
input{width:100%;padding:10px 12px;border:1.5px solid #ddd;border-radius:8px;font-size:14px;outline:none;transition:border .2s}
input:focus{border-color:#4f46e5}
.row{display:flex;gap:8px;margin-top:4px}
.btn{flex:1;padding:11px;border:none;border-radius:8px;font-size:14px;font-weight:500;cursor:pointer}
.btn-primary{background:#4f46e5;color:#fff}
.btn-primary:disabled{background:#a5a0e8;cursor:not-allowed}
.btn-outline{background:#f0f2f5;color:#555;border:1.5px solid #ddd}
.status-box{margin-top:20px;padding:14px;border-radius:10px;font-size:13px;line-height:1.6;display:none}
.status-box.show{display:block}
.status-idle{background:#ecfdf5;color:#065f46}
.status-wake{background:#fef3c7;color:#92400e}
.badge{display:inline-block;padding:2px 10px;border-radius:20px;font-size:12px;font-weight:500}
.badge-idle{background:#d1fae5;color:#065f46}
.badge-wake{background:#fde68a;color:#92400e}
.msg{font-size:13px;margin-top:12px;padding:8px 12px;border-radius:6px;display:none}
.msg.show{display:block}
.msg-ok{background:#ecfdf5;color:#065f46}
.msg-err{background:#fef2f2;color:#991b1b}
</style>
</head>
<body>
<div class="card">
  <h1>[ WOL Remote ] 远程唤醒</h1>
  <div class="subtitle">Cloudflare Worker - 控制面板</div>
  <div class="field">
    <label for="token">API Token</label>
    <input type="password" id="token" placeholder="输入 API Token" autocomplete="off">
  </div>
  <div class="row">
    <button class="btn btn-primary" id="btnWake" onclick="doWake()">[ 触发唤醒 ]</button>
    <button class="btn btn-outline" onclick="doRefresh()">[ 刷新 ]</button>
  </div>
  <div class="status-box" id="statusBox"></div>
  <div class="msg" id="msg"></div>
</div>
<script>
const BASE = window.location.origin;
function $(id){return document.getElementById(id)}
function msg(text,type){var el=$('msg');el.textContent=text;el.className='msg show msg-'+type;setTimeout(function(){el.classList.remove('show')},3000)}
function token(){return $('token').value.trim()}
function qs(){var t=token();return t?'?token='+encodeURIComponent(t):''}
async function api(path,opts){var t=token();if(!t){msg('请先输入 Token','err');return null}
var res=await fetch(BASE+path+qs(),{headers:t?{'X-API-Token':t}:{},...opts});if(res.status===401){msg('Token 无效','err');return null};return res}
async function doRefresh(){var res=await api('/api/status');if(!res)return;var d=await res.json()
var box=$('statusBox');box.className='status-box show '+(d.pending?'status-wake':'status-idle')
box.innerHTML=d.pending?'[ 有待唤醒 ]':'[ 空闲 ]'
box.innerHTML+='<br><br>';if(d.last_wake)box.innerHTML+='上次唤醒: '+new Date(d.last_wake).toLocaleString()+'<br>'
if(d.last_ack)box.innerHTML+='上次确认: '+new Date(d.last_ack).toLocaleString()+'<br>'
if(!d.last_wake&&!d.last_ack)box.innerHTML+='暂无记录'}
async function doWake(){var btn=$('btnWake');btn.disabled=true;var res=await api('/api/wake',{method:'POST'});btn.disabled=false
if(!res)return;var d=await res.json()
if(d.status==='queued'){msg('唤醒请求已发送','ok');doRefresh()}
else if(d.status==='already_queued'){msg('已有待处理的唤醒','ok');doRefresh()}}
document.getElementById('token').addEventListener('input',function(){if(token())doRefresh()})
document.getElementById('token').addEventListener('keydown',function(e){if(e.key==='Enter')doWake()})
</script>
</body>
</html>`;
