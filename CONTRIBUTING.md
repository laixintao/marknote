# Contributing / 参与开发

[中文使用文档](docs/zh-CN/README.md) · [English user guide](docs/en/README.md)

需要 macOS 13+、Swift 6.1+、Python 3.9+。 / Requires macOS 13+, Swift 6.1+, and Python 3.9+.

```sh
make run
make verify
```

`make verify` runs offline repository checks, release-tool tests, Markdown / localization tests, and integration tests in real AppKit and WebKit windows. A logged-in macOS graphical session is required. Test applications use separate bundle identifiers and write logs to `.build/smoke-*/`. The Swift core tests use a standalone runner, so full Xcode and XCTest are not required.

`make verify` 会执行仓库检查、发布工具测试、Markdown / 语言资源测试与真实窗口集成测试，需要已登录的 macOS 图形会话。测试应用使用独立标识，结果保存在 `.build/smoke-*/`。核心测试无需完整 Xcode 或 XCTest。

## Layout / 代码结构

| Path | Responsibility / 职责 |
| --- | --- |
| `Sources/Marknote/` | Native windows, documents, editing, integration checks / 原生窗口、文稿、编辑与集成验证 |
| `Sources/MarknoteCore/` | Markdown, text operations, localization / Markdown、文本操作与语言资源 |
| `Tests/MarknoteCoreTests/` | Portable Swift test runner / Swift 核心测试 |
| `Tests/ReleaseTests/` | Offline release failure/recovery tests / 发布失败与恢复测试 |
| `Scripts/` | Build, package, screenshots, release / 构建、打包、截图与发布 |
| `.github/workflows/` | Shared dual-architecture CI and release / 共用双架构 CI 与发布流程 |
| `docs/` | Bilingual guides and product screenshots / 双语指南与产品截图 |

For UI changes, update both `en.lproj/Localizable.strings` and `zh-Hans.lproj/Localizable.strings`, and preserve selections, IME composition, and undo history. Add tests for behavior that could regress. Update both language guides when a feature changes, and run `make screenshots` when screenshots need refreshing.

界面改动请同步更新两种语言资源，保留选区、输入法组合状态及撤销记录。对可能回归的行为补充测试；功能变化时同步更新双语文档，必要时执行 `make screenshots`。

Include the problem, resulting behavior, and validation in pull requests. Never include personal documents, credentials, or build output. Release instructions: [English](docs/en/releasing.md) / [中文](docs/zh-CN/releasing.md).
