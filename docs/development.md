# 开发与构建

VibeBar 现在以 SwiftPM 作为工程真相源。根目录的 `Package.swift` 管理 target、依赖和 Swift 语言模式；Xcode 只用于打开 package 后调试、调用编译器和后续签名能力。

## 常用命令

推荐通过 mise 运行项目任务。Swift toolchain 仍由 Xcode 提供，mise 在本项目里负责 Node.js 版本和常用任务入口。

安装项目工具：

```bash
mise trust .mise.toml
mise install
```

本地编译：

```bash
mise run build
```

生成可运行的 `.app`：

```bash
mise run app
```

构建并启动：

```bash
mise run run
```

验证进程能启动：

```bash
mise run verify
```

生成发布用通用架构 app：

```bash
mise run app:release
```

运行基础检查：

```bash
mise run check
```

## Xcode 使用方式

直接用 Xcode 打开根目录 `Package.swift`。不要重新引入 `VibeBar.xcodeproj` 或 `project.yml` 作为工程入口，否则 SwiftPM 与 Xcode 工程会重新分叉。

## 发布产物

发布 workflow 使用 `jdx/mise-action` 安装 `.mise.toml` 中声明的工具，并通过 `mise run app:release` 生成 `VibeBar.app`，再交给 `scripts/create_drag_dmg.sh` 打包。版本号仍从 `Config/Info.plist` 读取。
