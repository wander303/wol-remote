# 修订记录

## 2026-06-30 — fix: SDK toolchain + full buildroot hybrid (v3)
- **分支**: `codex/fix-lua-sdk-build-20260630-0200`
- **变更文件**: `.github/workflows/build-ipk.yml`
- **原因**: SDK 缺少 lua/ucode 等核心包源码；完整 buildroot 默认 x86_64 目标，需要 aarch64 交叉工具链
- **修复**: 
  1. 克隆完整 ImmortalWrt buildroot（v24.10.5）获取全部包源码
  2. 下载 SDK 获取预编译 aarch64 工具链（staging_dir）和正确的 .config
  3. 将 SDK 的 staging_dir 和 .config 复制到 buildroot
  4. 在完整 buildroot 中编译 luci-app，依赖链自动解析
  5. 支持 actions/cache 加速后续构建
- **影响范围**: GitHub Actions CI 构建流程
- **验证**: 手动触发 workflow_dispatch，查看 .ipk 是否上传为 artifact
- **回滚**: 使用 `git revert` 回退或切回 `main` 分支
