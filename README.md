# VibeBar (MVP)

一个最小可用的 macOS Menubar 工具：支持 Kimi 与 Codex 两个 provider 的订阅/额度监控，并在菜单中通过 Tab 切换查看。

## MVP 能力

- 自动从已登录浏览器读取 `kimi-auth` JWT（通过 SweetCookieKit）。
- 调用 `POST https://www.kimi.com/apiv2/kimi.gateway.billing.v1.BillingService/GetUsages`。
- 从 `~/.codex/auth.json`（或 `$CODEX_HOME/auth.json`）读取 Codex 凭据。
- 调用 `GET https://chatgpt.com/backend-api/wham/usage` 获取 Codex 额度窗口。
- 菜单栏展示：
  - Kimi：周额度 + 5 小时窗口
  - Codex：Session + Weekly
  - 重置时间
  - 套餐名（Codex 来自 `plan_type`/`auth.json`，Kimi 来自 `GetSubscription`）
- 顶部 Tab 切换：`Kimi / Codex`
- token 缓存到本机钥匙串（`ThisDeviceOnly`，不走 iCloud 同步）。
- 5 分钟自动刷新，支持手动刷新。

## 运行环境

- macOS 14+
- Xcode 16+（或 Swift 6 工具链）

## Xcode 工程

仓库已包含可直接打开的工程文件：

- `VibeBar.xcodeproj`

使用方式：

1. 双击打开 `VibeBar.xcodeproj`
2. 选择 Scheme：`VibeBar`
3. Run Destination 选择 `My Mac`
4. 按 `⌘R` 运行

预览方式（卡片 UI）：

1. 切换 Scheme 到 `VibeBarUI`
2. 打开 `Sources/VibeBarUI/KimiUsageCardView+Preview.swift`
3. 打开 Canvas 并点击 `Resume`

如果修改了 `project.yml`，可重新生成工程：

```bash
xcodegen generate
```

### App Icon（分发用）

项目已包含 `Resources/Assets.xcassets/AppIcon.appiconset`，并已接入 target。

如需重新生成品牌图标（`AppIcon.appiconset` 必定更新；`Resources/AppIcon.icns` 仅在 `iconutil` 成功时生成）：

```bash
./scripts/generate_app_icon.sh
```

## 首次使用

1. 先在浏览器登录 Kimi（`https://www.kimi.com/code/console`）。
2. 先运行过 `codex` 并完成登录（确保本地存在 `~/.codex/auth.json`）。
3. 给应用必要权限（常见为 Full Disk Access / Keychain 提示，取决于浏览器）。
4. 编译运行：

```bash
swift run VibeBar
```

## 手动调试脚本

仓库包含两个探针脚本：

- `scripts/kimi_probe.sh`：测试 `kimi-auth` JWT 到 `GetUsages`
- `scripts/kimi_k2_probe.sh`：测试 `sk-kimi-*` 到 `kimi-k2` credits 接口
- `scripts/kimi_subscription_probe.sh`：测试 `GetSubscription` 并解析套餐名（支持离线解析 JSON）

示例：

```bash
KIMI_AUTH_TOKEN='eyJ...' ./scripts/kimi_probe.sh
```

## 安全说明

- 不要把 JWT 或 API Key 提交到仓库。
- 如截图/日志中暴露过 token，请立即失效并重新登录获取新 token。

或直接使用现成图片导入：

```bash
./scripts/import_app_icon_from_image.sh /path/to/your-icon.png
```
