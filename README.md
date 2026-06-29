# 远程开机 (WOL Remote)

通过公网服务器远程唤醒家中主机的完整方案。

## 架构概览

```
用户 → serverhost:443 (Flask WebUI + API) ──HTTPS──→ OpenWrt (轮询) ──etherwake──→ homehost 唤醒
```

| 组件 | 角色 | 公网可达 |
|------|------|---------|
| **serverhost** | Flask Web 服务 + API | ✅ 是 |
| **OpenWrt** | 轮询 + 执行 WoL | ❌ 否（主动出站） |
| **homehost** | 被唤醒的 Windows PC | ❌ 否 |

**工作方式**：OpenWrt 每 N 秒轮询 serverhost API → 有任务则 `etherwake` → 确认。

## 项目结构

```
远程开机/
├── serverhost/                        # 公网服务器端
│   ├── app.py                         # Flask 主应用（3 个 API + WebUI）
│   ├── config.py                      # 配置（端口/Token/路径）
│   ├── requirements.txt               # Python 依赖
│   ├── templates/index.html           # WebUI 前端页面
│   └── static/style.css               # 页面样式
│
├── openwrt/luci-app-wol-remote/       # OpenWrt 插件包源码
│   ├── Makefile                       # OpenWrt 编译 Makefile
│   ├── root/etc/config/wolremote      # UCI 配置文件
│   ├── root/etc/init.d/wolremote      # procd 服务脚本
│   ├── root/etc/uci-defaults/99-wolremote  # 首次安装初始化
│   ├── root/usr/bin/wol-poll.sh       # 轮询守护脚本
│   ├── luasrc/controller/wolremote.lua   # LuCI 菜单入口
│   └── luasrc/model/cbi/wolremote.lua    # LuCI 配置页面
│
└── README.md                          # 本文
```

## 快速开始

### 1. serverhost 部署

```bash
# 安装依赖
cd serverhost
pip install -r requirements.txt

# 配置 Token
export WOL_API_TOKEN="your-random-token-here"
export WOL_PORT=5000

# 开发模式启动
python app.py

# 生产模式（gunicorn + nginx）
# 详见下方部署说明
```

**API 端点：**

| 端点 | 方法 | 说明 | 认证 |
|------|------|------|------|
| `/api/health` | GET | 健康检查 | 否 |
| `/api/wake` | POST | 请求唤醒 | Token |
| `/api/poll` | GET | 轮询检查 | Token |
| `/api/ack` | POST | 确认唤醒 | Token |
| `/api/status` | GET | 设备状态 | Token |
| `/api/history` | GET | 唤醒记录 | Token |
| `/` | GET | WebUI 首页 | — |

### 2. OpenWrt 安装插件

#### 方式 A：编译 .ipk 安装

```bash
# 将源码放入 OpenWrt SDK 的 package/ 目录
cp -r luci-app-wol-remote /path/to/sdk/package/

# 编译
make package/luci-app-wol-remote/compile

# 安装到路由器
scp bin/packages/*/luci-app-wol-remote_*.ipk root@openwrt:/tmp/
ssh root@openwrt "opkg install /tmp/luci-app-wol-remote_*.ipk"
```

#### 方式 B：手动部署（快速验证）

```bash
# 上传文件到 OpenWrt
scp -r root/* root@openwrt:/

# 设置脚本权限
ssh root@openwrt "chmod 755 /etc/init.d/wolremote /usr/bin/wol-poll.sh"

# 配置 UCI 参数
ssh root@openwrt << 'EOF'
uci set wolremote.settings.server_url="https://your-server.com"
uci set wolremote.settings.api_token="your-api-token"
uci set wolremote.settings.mac_address="xx:xx:xx:xx:xx:xx"
uci commit wolremote
EOF

# 启动服务
ssh root@openwrt "/etc/init.d/wolremote enable && /etc/init.d/wolremote start"
```

### 3. homehost 配置

| 项目 | 位置 | 设置 |
|------|------|------|
| BIOS | Power Management | **Power On By PCI-E** / **Wake on LAN** → Enabled |
| 网卡驱动 | 设备管理器 → 网卡 → 高级 | **唤醒魔包** → 启用 |
| 网卡电源 | 设备管理器 → 网卡 → 电源管理 | 允许此设备唤醒计算机 ☑️ |
| 快速启动 | 控制面板 → 电源选项 | **关闭**（干扰 WoL） |

## 生产部署（serverhost）

### Nginx + Gunicorn + Systemd

```bash
# 安装 gunicorn
pip install gunicorn

# systemd 服务单元 /etc/systemd/system/wol-web.service
cat > /etc/systemd/system/wol-web.service << 'SERVICE'
[Unit]
Description=WOL Remote Web Service
After=network.target

[Service]
Type=simple
User=www-data
WorkingDirectory=/opt/wol-remote/serverhost
Environment=WOL_API_TOKEN=your-token
Environment=WOL_PORT=5000
ExecStart=/usr/local/bin/gunicorn -w 2 -b 127.0.0.1:5000 app:app
Restart=always

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable --now wol-web
```

### Nginx 反向代理

```nginx
server {
    listen 443 ssl;
    server_name wol.example.com;

    ssl_certificate     /etc/letsencrypt/live/wol.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/wol.example.com/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}

# 可选：HTTP → HTTPS 跳转
server {
    listen 80;
    server_name wol.example.com;
    return 301 https://$host$request_uri;
}
```

## 安全性

- **API Token 认证** — 所有 API 请求需携带 Token（Header 或参数）
- **HTTPS 传输** — Let's Encrypt 加密，防中间人攻击
- **OpenWrt 零入站** — 不开放任何入站端口，攻击面为零
- **UCI 权限控制** — 脚本只读读取配置，Token 不写日志

## 验证

```bash
# 健康检查
curl https://your-server.com/api/health

# 触发唤醒
curl -X POST https://your-server.com/api/wake \
  -H "X-API-Token: your-token" \
  -H "Content-Type: application/json" \
  -d '{}'

# OpenWrt 日志
logread | grep wolremote
```

## License

GPLv2
