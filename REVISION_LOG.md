# 修订记录

## 2026-06-30 — v1.0.0 Release
- **标签**: `v1.0.0`
- **变更**: 合并 `codex/fix-lua-sdk-build-20260630-0200` 到 `main`
- **发布**: [GitHub Release v1.0.0](https://github.com/wander303/wol-remote/releases/tag/v1.0.0)
- **内容**: luci-app-wol-remote_1.0.0-r1_all.ipk（ImmortalWrt 24.10.5, mediatek/filogic）
- **验证**: workflow 28418996207 构建成功 ✅

## 2026-06-30 — fix: CLI workflow 混合方案（SDK 工具链 + buildroot）
- **分支**: `codex/fix-lua-sdk-build-20260630-0200`
- **变更文件**: `.github/workflows/build-ipk.yml`
- **原因**: SDK 缺少 lua/ucode 等核心包源码；完整 buildroot 默认 x86_64 目标，需 aarch64 工具链
- **最终方案**:
  1. 克隆完整 ImmortalWrt buildroot（v24.10.5）获取全部包源码
  2. 下载 SDK 获取预编译 aarch64 交叉工具链（staging_dir）
  3. 将 SDK 的 staging_dir 和 .config 复制到 buildroot，设置正确目标架构
  4. 完整 buildroot 中编译，依赖链自动解析
  5. 上传路径使用 `**` glob 匹配
- **影响范围**: GitHub Actions CI 构建流程
- **验证**: 最终构建 5m57s ✅，artifact 正确上传
- **回滚**: 使用 `git revert` 回退

## 2026-06-30 — fix: 修复 init.d 和 poll 脚本权限（644→755）
- **分支**: `main`（直接提交）
- **变更文件**: `openwrt/luci-app-wol-remote/root/etc/init.d/wolremote`, `openwrt/luci-app-wol-remote/root/usr/bin/wol-poll.sh`
- **原因**: git 中文件权限为 644，打包进 ipk 后 init 脚本无执行权限，安装时 `postinst` 调用 `/etc/init.d/wolremote enable` 失败（Permission denied）
- **影响范围**: LuCI 包安装流程
- **验证**: git ls-files --stage 显示 100755 ✅，需 CI 重新构建后验证安装
- **回滚**: `git revert` 回退

## 2026-07-01 — fix: 修复 LuCI 控制器 Lua 语法错误（尾逗号 + 注释）
- **分支**: `main`
- **变更文件**: `openwrt/luci-app-wol-remote/luasrc/controller/wolremote.lua`
- **原因**: `entry()` 调用第三参数 `_("WOL Remote")` 后有多余逗号和注释行，Lua 5.1 将注释视为空白，逗号后紧跟 `)` 导致语法错误 `unexpected symbol near ')'`，LuCI 页面 500 错误
- **影响范围**: LuCI 管理页面 → 服务 → WOL Remote
- **验证**: 修复后在 LuCI 页面刷新不再报错 ✅
- **回滚**: `git revert` 回退

## 2026-07-01 — fix: ACK 请求 Token 认证方式错误导致无限唤醒循环
- **分支**: `main`
- **变更文件**: `openwrt/luci-app-wol-remote/root/usr/bin/wol-poll.sh`
- **原因**: `wol-poll.sh` 对 `/api/ack` 调用将 Token 放在 JSON body 中（`{"token":"..."}`），但 Worker `checkAuth()` 只检查 `X-API-Token` Header 和 `?token=` Query Param，不解析 JSON body。ACK 始终返回 401，pending 状态保持 "WAKE"，下次 polling 又拿到 "WAKE" → 一直发 etherwake → 死循环
- **影响范围**: WOL Remote 轮询唤醒功能
- **验证**: ACK 使用 query param 后认证通过，pending 正确重置为 IDLE ✅
- **回滚**: `git revert` 回退
