"""远程开机系统 - Flask 主应用

提供三组 API 端点：
  - POST /api/wake     用户触发唤醒（需要 Token 认证）
  - GET  /api/poll     OpenWrt 轮询（检查是否有待处理唤醒）
  - POST /api/ack      OpenWrt 确认已执行唤醒

以及 WebUI 前端页面。
"""
import json
import os
import time
import logging
from datetime import datetime, timezone
from functools import wraps
from threading import Lock

from flask import (
    Flask,
    abort,
    jsonify,
    render_template,
    request,
    send_from_directory,
)

import config

# ── 初始化 ──────────────────────────────────────────────────────────
app = Flask(__name__, static_folder="static", template_folder="templates")

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
log = logging.getLogger("wol")

# 确保 data 目录存在
os.makedirs(config.DATA_DIR, exist_ok=True)

# 线程锁，保护 state.json 并发读写
_state_lock = Lock()

# ── 辅助函数 ────────────────────────────────────────────────────────


def _load_state() -> dict:
    """从磁盘加载状态文件，不存在则返回默认结构。"""
    if not os.path.isfile(config.STATE_FILE):
        return {"homehost": {"pending": False, "last_wake": None, "last_ack": None}}
    try:
        with open(config.STATE_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError):
        return {"homehost": {"pending": False, "last_wake": None, "last_ack": None}}


def _save_state(state: dict) -> None:
    """原子写入状态文件。"""
    tmp = config.STATE_FILE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(state, f, ensure_ascii=False, indent=2)
    os.replace(tmp, config.STATE_FILE)


def _append_log(entry: str) -> None:
    """追加一条唤醒日志。"""
    try:
        with open(config.LOG_FILE, "a", encoding="utf-8") as f:
            f.write(entry + "\n")
    except OSError:
        pass


def _now_iso() -> str:
    """返回当前 UTC 时间的 ISO 格式字符串。"""
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


# ── 认证装饰器 ──────────────────────────────────────────────────────


def require_token(f):
    """校验 API Token 的装饰器（支持 Header 或查询参数 ?token=xxx）。"""

    @wraps(f)
    def wrapper(*args, **kwargs):
        token = request.headers.get(config.TOKEN_HEADER) or request.args.get(
            "token"
        ) or (request.is_json and request.json.get("token"))
        if not token or token != config.API_TOKEN:
            abort(401, description="无效或缺失 Token")
        return f(*args, **kwargs)

    return wrapper


# ── API 端点 ────────────────────────────────────────────────────────


@app.route("/api/wake", methods=["POST"])
@require_token
def api_wake():
    """用户请求唤醒 homehost。"""
    state = _load_state()
    host = "homehost"

    with _state_lock:
        if state.get(host, {}).get("pending"):
            return jsonify({"status": "already_queued"}), 200

        if host not in state:
            state[host] = {"pending": False, "last_wake": None, "last_ack": None}
        state[host]["pending"] = True
        state[host]["last_wake"] = _now_iso()
        _save_state(state)

    msg = f"唤醒请求已排队 [{host}]"
    _append_log(f"[{_now_iso()}] WAKE_QUEUED  host={host}")
    log.info(msg)
    return jsonify({"status": "queued"})


@app.route("/api/poll", methods=["GET"])
@require_token
def api_poll():
    """OpenWrt 轮询接口：返回 'WAKE' 或 'IDLE'。"""
    host = request.args.get("host", "homehost")
    state = _load_state()

    if state.get(host, {}).get("pending"):
        return "WAKE", 200, {"Content-Type": "text/plain; charset=utf-8"}
    return "IDLE", 200, {"Content-Type": "text/plain; charset=utf-8"}


@app.route("/api/ack", methods=["POST"])
@require_token
def api_ack():
    """OpenWrt 确认已执行唤醒。"""
    host = request.json.get("host", "homehost") if request.is_json else "homehost"
    state = _load_state()

    with _state_lock:
        if host in state:
            state[host]["pending"] = False
            state[host]["last_ack"] = _now_iso()
        _save_state(state)

    _append_log(f"[{_now_iso()}] WAKE_ACK  host={host}")
    log.info("收到唤醒确认 [%s]", host)
    return jsonify({"status": "ok"})


@app.route("/api/status", methods=["GET"])
@require_token
def api_status():
    """查询 homehost 当前状态。"""
    host = request.args.get("host", "homehost")
    state = _load_state()
    info = state.get(host, {})
    return jsonify(
        {
            "host": host,
            "pending": info.get("pending", False),
            "last_wake": info.get("last_wake"),
            "last_ack": info.get("last_ack"),
        }
    )


@app.route("/api/history", methods=["GET"])
@require_token
def api_history():
    """返回最近的唤醒记录（最多 50 条）。"""
    if not os.path.isfile(config.LOG_FILE):
        return jsonify({"entries": []})
    try:
        with open(config.LOG_FILE, "r", encoding="utf-8") as f:
            lines = f.readlines()
        # 取最后 50 条
        tail = [l.strip() for l in lines if l.strip()][-50:]
        return jsonify({"entries": tail})
    except OSError:
        return jsonify({"entries": []})


@app.route("/api/health", methods=["GET"])
def api_health():
    """健康检查（不需要 Token）。"""
    return jsonify({"status": "ok", "service": "wol-remote"})


# ── WebUI 前端 ──────────────────────────────────────────────────────


@app.route("/")
def index():
    """渲染主页面。"""
    return render_template("index.html")


@app.route("/static/<path:filename>")
def static_files(filename):
    """静态资源服务。"""
    return send_from_directory(config.STATIC_FOLDER or "static", filename)


# ── 错误处理 ────────────────────────────────────────────────────────


@app.errorhandler(401)
def unauthorized(e):
    return jsonify({"error": "未授权", "detail": str(e.description)}), 401


@app.errorhandler(404)
def not_found(e):
    return jsonify({"error": "接口不存在"}), 404


@app.errorhandler(500)
def server_error(e):
    log.exception("服务器内部错误")
    return jsonify({"error": "服务器内部错误"}), 500


# ── 入口 ────────────────────────────────────────────────────────────

if __name__ == "__main__":
    log.info("启动 WOL 远程开机服务 -> %s:%s", config.HOST, config.PORT)
    app.run(host=config.HOST, port=config.PORT, debug=config.DEBUG)
