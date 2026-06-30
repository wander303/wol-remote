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
