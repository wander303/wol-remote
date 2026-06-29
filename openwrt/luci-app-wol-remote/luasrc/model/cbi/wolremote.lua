-- ==========================================================================
-- LuCI CBI 模型 — WOL Remote 配置页面
-- ==========================================================================
-- 提供完整的表单用于修改 UCI /etc/config/wolremote 中的各项参数，
-- 并显示运行状态和日志摘要。
-- ==========================================================================

local m = Map("wolremote", translate("WOL Remote"),
    translate("远程唤醒服务 — 定时轮询公网服务器，收到指令后通过 WoL 唤醒局域网主机。"))

-- ── 基本设置 ──────────────────────────────────────────────────────
local s = m:section(NamedSection, "settings", "wol-remote", translate("基本设置"))
s.anonymous = true

-- 启用开关
local enabled = s:option(Flag, "enabled", translate("启用"))
enabled.default = 1
enabled.description = translate("启用后，procd 守护进程将按设定的间隔轮询服务器。")

-- 服务器地址
local server_url = s:option(Value, "server_url", translate("服务器地址"))
server_url.description = translate("serverhost 的 API 地址，例如 https://wol.example.com")
server_url.datatype = "string"
server_url.placeholder = "https://your-server.com"
server_url.rmempty = false

-- API Token
local api_token = s:option(Value, "api_token", translate("API Token"))
api_token.description = translate("与 serverhost 约定的认证令牌，用于 API 请求鉴权")
api_token.datatype = "string"
api_token.password = true  -- 密码输入模式
api_token.rmempty = false

-- 主机标识
local host_name = s:option(Value, "host_name", translate("主机名称"))
host_name.description = translate("受控主机的标识名称，多设备时用于区分")
host_name.default = "homehost"
host_name.datatype = "string"

-- MAC 地址
local mac_addr = s:option(Value, "mac_address", translate("MAC 地址"))
mac_addr.description = translate("要唤醒的主机网卡 MAC 地址，格式：xx:xx:xx:xx:xx:xx")
mac_addr.datatype = "macaddr"
mac_addr.rmempty = false
mac_addr.placeholder = "xx:xx:xx:xx:xx:xx"

-- LAN 接口
local lan_iface = s:option(Value, "lan_interface", translate("LAN 接口"))
lan_iface.description = translate("homehost 所在的 LAN 接口名称，通常为 br-lan")
lan_iface.default = "br-lan"
lan_iface.datatype = "string"

-- 轮询间隔
local poll_interval = s:option(Value, "poll_interval", translate("轮询间隔（秒）"))
poll_interval.description = translate("每次轮询之间的等待时间，建议 15~30 秒")
poll_interval.default = 15
poll_interval.datatype = "range(5, 300)"

-- 启动时确认
local ack_boot = s:option(Flag, "ack_wake_on_boot", translate("启动时确认"))
ack_boot.default = 1
ack_boot.description = translate("服务启动时向 serverhost 发送一次确认，清除重启前的残留 pending 状态")

-- ── 操作按钮 ──────────────────────────────────────────────────────
local btn_section = m:section(TypedSection, "settings", translate("操作"))
btn_section.anonymous = true

-- 启动/停止/重启按钮
local btn_start = btn_section:option(Button, "_start", translate("启动服务"))
btn_start.inputstyle = "apply"
btn_start.description = translate("启动 wolremote 守护进程")
function btn_start.write(self, section)
    luci.sys.call("/etc/init.d/wolremote start 2>&1")
    luci.http.redirect(luci.dispatcher.build_url("admin/services/wolremote"))
end

local btn_stop = btn_section:option(Button, "_stop", translate("停止服务"))
btn_stop.inputstyle = "reset"
btn_stop.description = translate("停止 wolremote 守护进程")
function btn_stop.write(self, section)
    luci.sys.call("/etc/init.d/wolremote stop 2>&1")
    luci.http.redirect(luci.dispatcher.build_url("admin/services/wolremote"))
end

local btn_restart = btn_section:option(Button, "_restart", translate("重启服务"))
btn_restart.inputstyle = "apply"
btn_restart.description = translate("重启使新配置生效")
function btn_restart.write(self, section)
    luci.sys.call("/etc/init.d/wolremote restart 2>&1")
    luci.http.redirect(luci.dispatcher.build_url("admin/services/wolremote"))
end

-- ── 状态显示 ──────────────────────────────────────────────────────
local st = m:section(NamedSection, "settings", "wol-remote", translate("运行状态"))
st.anonymous = true

local status_dummy = st:option(DummyValue, "_status_text", translate("当前状态"))
function status_dummy.cfgvalue()
    local enabled = luci.sys.exec("uci -q get wolremote.settings.enabled 2>/dev/null") or "0"
    local running = (luci.sys.call("pidof wol-poll.sh >/dev/null 2>&1") == 0)
    local enabled_str = (enabled:match("^1$")) and "✓ 已启用" or "✗ 已禁用"
    local running_str = running and "● 运行中" or "○ 未运行"
    return string.format("%s / %s", enabled_str, running_str)
end

local log_dummy = st:option(TextValue, "_log_preview", translate("最近日志"))
log_dummy.rows = 8
log_dummy.wrap = "off"
function log_dummy.cfgvalue()
    local log = luci.sys.exec("logread -l 50 2>/dev/null | grep wolremote | tail -8")
    if log == "" then
        return translate("暂无日志")
    end
    return log
end

-- ── 保存回调 ──────────────────────────────────────────────────────
function m.on_after_save(map)
    -- 保存完成后自动重启服务使配置生效
    luci.sys.call("/etc/init.d/wolremote restart 2>&1")
end

return m
