-- ==========================================================================
-- LuCI 控制器 — WOL Remote (远程唤醒)
-- ==========================================================================
-- 在 LuCI 菜单 "服务" → "WOL Remote" 注册配置页面。
-- ==========================================================================

module("luci.controller.wolremote", package.seeall)

function index()
    -- 入口：Services → WOL Remote
    entry(
        {"admin", "services", "wolremote"},
        cbi("wolremote"),
        _("WOL Remote")
    ).dependent = false

    -- 注册 ACL（访问控制）
    entry(
        {"admin", "services", "wolremote", "status"},
        call("action_status"),
        nil
    ).leaf = true
end

-- 提供 JSON 状态接口，供前端 AJAX 调用
function action_status()
    local http = require("luci.http")
    local json = require("luci.jsonc")
    local util = require("luci.util")
    local sys = require("luci.sys")

    local enabled = util.trim(luci.sys.exec("uci -q get wolremote.settings.enabled") or "1")
    local last_log = util.trim(luci.sys.exec("logread -l 20 | grep wolremote | tail -3") or "")

    -- 检查服务是否运行
    local running = false
    local pid = luci.sys.call("pidof wol-poll.sh >/dev/null 2>&1")
    running = (pid == 0)

    local data = {
        enabled = (enabled == "1"),
        running = running,
        last_log_lines = last_log,
        timestamp = os.date("%Y-%m-%dT%H:%M:%S"),
    }

    http.prepare_content("application/json")
    http.write(json.stringify(data))
end
