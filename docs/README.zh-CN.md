<p align="center">
  <img src="../Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" width="88" alt="VibeBar 图标" />
</p>

<h1 align="center">VibeBar</h1>

<p align="center">你的 AI Coding 订阅额度仪表盘，常驻 macOS 菜单栏。</p>

<p align="center"><a href="../README.md">English README</a></p>

## 系统要求

- macOS 14.0 或更高版本
- 通用构建（Universal）：支持 Apple Silicon（arm64）与 Intel（x86_64）

## 安装方式

1. 从 Releases 下载 `VibeBar-<version>-macOS-universal.dmg`。
2. 打开 DMG 窗口。
3. 将 `VibeBar.app` 拖拽到 `Applications`。
4. 在应用程序目录中启动 VibeBar。

## 产品简介

VibeBar 是一个轻量、原生、低干扰的 menubar 工具，用来实时查看 Kimi 与 Codex 的订阅使用状态。你不需要反复打开网页控制台，抬头就能看到当前额度、重置时间和套餐信息。

## 核心能力

- 双 Provider：`Kimi / Codex` 一键切换
- 多窗口监控：支持 `Session`、`Weekly`、`5 小时窗口` 等配额视图
- 倒计时展示：统一为 `Resets in 5d / 3h / 45m` 短格式
- 套餐识别：显示当前订阅套餐名称
- 原生体验：macOS 菜单栏交互，打开即看，不打断编码流
- 自动刷新：持续更新；也支持手动立即刷新

## 菜单界面

![VibeBar 菜单预览](../Resources/Screenshots/menu-ui.png)

## 首次打开（未签名版本）

当前发布包可能未包含 Apple Developer 签名。若首次打开被 macOS 拦截，可使用以下任一方式：

命令行方式：

```bash
xattr -dr com.apple.quarantine /Applications/VibeBar.app
```

图形界面方式：

1. 先双击 `VibeBar.app`，出现安全提示后关闭弹窗。
2. 打开 `系统设置 -> 隐私与安全性`。
3. 在安全性区域找到 `VibeBar` 被阻止提示，点击 `仍要打开`。
4. 再次确认打开即可。

## 路线图

- 更多 Provider 接入（统一额度视图）
- 更细粒度的提醒策略（阈值提醒、窗口重置提醒）
- 更完整的统计趋势（按天/周用量节奏）
- 更完善的分发体验（签名、公证、安装体验优化）
