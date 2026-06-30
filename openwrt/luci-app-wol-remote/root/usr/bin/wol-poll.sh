#!/bin/sh
# wol-poll.sh - WOL Remote 轮询守护脚本
#
# 由 /etc/init.d/wolremote 通过 procd 启动。
# 循环执行：读取 UCI 配置 → 轮询 serverhost → 如有任务则 etherwake → 确认。
#
# 依赖：curl, etherwake
# 配置源：/etc/config/wolremote (UCI)

set -e

# ── 读取 UCI 配置 ────────────────────────────────────────────────
read_config() {
    ENABLED=$(uci -q get wolremote.settings.enabled || echo "1")
    SERVER_URL=$(uci -q get wolremote.settings.server_url || echo "")
    API_TOKEN=$(uci -q get wolremote.settings.api_token || echo "")
    HOST_NAME=$(uci -q get wolremote.settings.host_name || echo "homehost")
    MAC_ADDR=$(uci -q get wolremote.settings.mac_address || echo "")
    LAN_IF=$(uci -q get wolremote.settings.lan_interface || echo "br-lan")
    POLL_SEC=$(uci -q get wolremote.settings.poll_interval || echo "15")
    ACK_BOOT=$(uci -q get wolremote.settings.ack_wake_on_boot || echo "1")
}

# ── 轮询一次 ──────────────────────────────────────────────────────
poll_once() {
    read_config

    # 检查是否启用
    [ "$ENABLED" = "1" ] || return 0

    # 检查必填项
    if [ -z "$SERVER_URL" ] || [ -z "$API_TOKEN" ] || [ -z "$MAC_ADDR" ]; then
        logger -t "wolremote" "配置不完整：请设置 server_url / api_token / mac_address"
        return 0
    fi

    # 轮询 serverhost API
    RESPONSE=$(curl -s --connect-timeout 10 --max-time 15 \
        "${SERVER_URL}/api/poll?token=${API_TOKEN}&host=${HOST_NAME}" 2>/dev/null)

    if [ "$RESPONSE" = "WAKE" ]; then
        logger -t "wolremote" "收到唤醒指令，开始唤醒 ${HOST_NAME} (${MAC_ADDR})"

        if etherwake -i "${LAN_IF}" "${MAC_ADDR}" 2>/dev/null; then
            logger -t "wolremote" "WoL 魔法包已发送至 ${MAC_ADDR}"

            # 确认执行
            curl -s --connect-timeout 10 --max-time 15 \
                -X POST "${SERVER_URL}/api/ack" \
                -H "Content-Type: application/json" \
                -d "{\"token\":\"${API_TOKEN}\", \"host\":\"${HOST_NAME}\"}" \
                >/dev/null 2>&1 || logger -t "wolremote" "确认回执发送失败"

            logger -t "wolremote" "唤醒确认已提交"
        else
            logger -t "wolremote" "ERROR: etherwake 执行失败（接口: ${LAN_IF}, MAC: ${MAC_ADDR}）"
        fi
    elif [ -n "$RESPONSE" ]; then
        # 正常返回 IDLE，什么也不做
        :
    else
        logger -t "wolremote" "轮询失败：无法连接到 ${SERVER_URL}"
    fi
}

# ── 主循环 ────────────────────────────────────────────────────────
main() {
    logger -t "wolremote" "WOL Remote 轮询守护进程启动"

    # 启动时发送一次 ACK（清空 serverhost 上重启前的 pending 残留）
    read_config
    if [ "$ACK_BOOT" = "1" ] && [ -n "$SERVER_URL" ] && [ -n "$API_TOKEN" ]; then
        curl -s --connect-timeout 10 --max-time 15 \
            -X POST "${SERVER_URL}/api/ack" \
            -H "Content-Type: application/json" \
            -d "{\"token\":\"${API_TOKEN}\", \"host\":\"${HOST_NAME}\"}" \
            >/dev/null 2>&1 || true
    fi

    while true; do
        poll_once
        # 重新读取间隔（允许运行时修改）
        eval "$(uci -q show wolremote.settings.poll_interval | sed 's/wolremote\.settings\./POLL_SEC=/;s/=/ /')" 2>/dev/null || POLL_SEC=15
        [ "${POLL_SEC:-15}" -gt 0 ] 2>/dev/null || POLL_SEC=15
        sleep "${POLL_SEC}"
    done
}

main "$@"
