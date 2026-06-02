# AGENTS.MD

## 仓库定位

- 本仓库是 `VibeBar` 的 macOS App 开发与分发仓库。
- 目标是 App 分发，不做对外 Swift Package 发布。

## 协作语言

- 与维护者沟通统一使用中文。
- 新增或更新文档统一使用中文（README 中现有英文产品介绍可保留）。

## README 维护原则

- README 聚焦产品介绍：定位、价值、核心功能、截图、路线图。
- 不在 README 放置发布步骤、CI 流程、运维命令等操作手册内容。
- 发布流程说明应放在工作流文件或独立文档中。

## 工程与发布约束

- 以 SwiftPM 为工程真相源：根目录 `Package.swift` 管理 target、依赖和 Swift 语言模式。
- Xcode 只用于打开 package 后调试、调用编译器和签名相关能力。
- 以 mise 作为本地工具版本与常用任务入口；Swift toolchain 仍由当前 Xcode 提供。
- 发布产物为可分发的 `VibeBar.app` 压缩包（zip）及校验文件。
- 不重新引入 `VibeBar.xcodeproj` / `project.yml` 作为发布入口。

## 变更规范

- 优先做最小改动，避免引入无关重构。
- 提交前至少保证本地可构建（Release 或等价验证）。
- 提交信息清晰描述目的与范围。
