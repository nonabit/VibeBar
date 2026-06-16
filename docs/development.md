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
mise run dev
```

验证进程能启动：

```bash
mise run verify
```

生成发布用通用架构 app：

```bash
mise run app:release
```

`app` / `app:release` 会自动查找可用的代码签名身份：Release 优先使用 `Developer ID Application`，Debug 优先使用 `Apple Development`。如需显式指定或跳过签名：

```bash
CODE_SIGN_IDENTITY="Developer ID Application: Example (TEAMID)" mise run app:release
./scripts/build_app_bundle.sh --configuration release --sign none
```

运行基础检查：

```bash
mise run check
```

## Xcode 使用方式

直接用 Xcode 打开根目录 `Package.swift`。不要重新引入 `VibeBar.xcodeproj` 或 `project.yml` 作为工程入口，否则 SwiftPM 与 Xcode 工程会重新分叉。

## 发布产物

发布 workflow 使用 `jdx/mise-action` 安装 `.mise.toml` 中声明的工具，并通过 `mise run app:release` 生成 `VibeBar.app`，再交给 `scripts/create_drag_dmg.sh` 打包。版本号仍从 `Config/Info.plist` 读取。

GitHub Release 需要先配置以下仓库 secrets，否则 workflow 会拒绝发布 unsigned/ad-hoc app：

- `MACOS_CERTIFICATE_P12_BASE64`：Developer ID Application 证书的 `.p12` 文件 base64 内容。
- `MACOS_CERTIFICATE_PASSWORD`：导出 `.p12` 时设置的密码。
- `MACOS_KEYCHAIN_PASSWORD`：CI 临时 keychain 的密码。
