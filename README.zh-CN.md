# 墨笺 · Marknote

**留一点空间，给思考。** 一个轻盈的 macOS 原生 Markdown 编辑器。

[English](README.md) · [中文文档](docs/zh-CN/README.md) · [English documentation](docs/en/README.md) · [发布指南](docs/zh-CN/releasing.md)

![墨笺浅色界面：文档大纲、Markdown 编辑器与实时预览](docs/images/product-light.png)

用 Swift、AppKit 和 WebKit 构建。文件保存在你的 Mac 上，打开即可写作，无需账号、Electron 或在线服务。

## 写作所需，恰到好处

- **原生编辑体验**：中文输入、语法着色、查找与替换、撤销 / 重做、字号调整。
- **键盘快速导航**：搜索命令，以及快速打开已打开、最近使用和同目录 Markdown 文稿。
- **减少编辑步骤**：粘贴或拖入图片、相对路径附件、选中文字粘贴网址生成链接，以及表格整理和 Tab 导航。
- **舒适的长文写作**：可分别开启段落聚焦和打字机滚动。
- **选择自己的布局**：编辑 / 分栏 / 预览单选按钮组，以及专注模式。
- **看清文稿结构**：可跳转的大纲，中英文混排字数、字符数和光标位置。
- **完整的日常 Markdown**：标题、列表、代码块、引用、图片、表格、任务列表和删除线。
- **文件由你掌握**：普通 UTF-8 文件、多窗口、自动保存，导出 HTML 或 PDF。
- **中文与 English**：即时切换界面语言并记住选择；跟随系统浅色 / 深色外观。

| 深色写作 | 英文阅读模式 |
| --- | --- |
| ![墨笺深色双栏界面](docs/images/product-dark.png) | ![Marknote English preview-only view](docs/images/product-preview.png) |

截图来自真实 AppKit 窗口，可通过 `make screenshots` 重新生成。

新增写作工具已进入 `main`，记录在 [Unreleased](CHANGELOG.md) 中；下次正式发布前，可从源码体验。[五款产品调研摘要](docs/zh-CN/market-research.md)说明了用户反馈和功能选择。

## 安装与运行

需要 **macOS 13+**。在 [**Releases** 页面](https://github.com/laixintao/marknote/releases)选择与你的 Mac 匹配的 DMG 安装包：Apple Silicon 使用 `macos-arm64`，Intel 使用 `macos-x86_64`。打开 DMG，将 `墨笺.app` 拖入“应用程序”，推出安装磁盘，再打开已安装的应用。也提供 ZIP 压缩包。默认 CI 构建使用临时签名、未经 Apple 公证；[安装说明](docs/zh-CN/README.md)介绍首次打开与源码构建。

从源码运行需要 Swift 6.1+（Xcode 或 Xcode Command Line Tools）和 Python 3.9+：

```sh
make run
```

应用生成于 `dist/墨笺.app`。Markdown 解析器和语言资源均已随源码提供，构建不需要下载 Swift 依赖。

## 常用操作

| 操作 | 入口 / 快捷键 |
| --- | --- |
| 默认打开 `.md` | 墨笺 → 设为默认 Markdown 编辑器… |
| 切换界面语言 | 墨笺 / Marknote → 语言 / Language |
| 命令面板 / 快速打开 | `⇧⌘P` / `⇧⌘O` |
| 插入图片 / 整理表格 | `⇧⌘I` / `⌥⌘T` |
| 段落聚焦 / 打字机滚动 | 显示菜单 |
| 切换编辑 / 分栏 / 预览 | 工具栏按钮组，或 `⌃⌘1` / `⌃⌘2` / `⌃⌘3` |
| 专注模式 | `⌘⇧F` |
| 保存 / 查找 | `⌘S` / `⌘F` |
| 加粗 / 斜体 / 链接 | `⌘B` / `⌘I` / `⌘K` |
| 导出 PDF | `⌘⇧E` |

语言和布局切换保留文稿、选区及撤销记录。点击目录会在当前可见区域跳转，保留显示模式。完整快捷键、文件行为与功能边界见[中文使用文档](docs/zh-CN/README.md)。

## 开发、验证与发布

```sh
make help         # 查看全部命令
make verify       # 文档 / 发布工具检查、核心测试、真实窗口测试
make installer    # 生成并验证拖放安装的 DMG
make package      # 当前 Mac 架构的 DMG + ZIP + SHA-256
make release      # 推送版本标签，等待 GitHub CI 创建 Release 并上传产物
```

[CI](.github/workflows/ci.yml) 在每次分支推送与 PR 时验证 Apple Silicon、Intel 两种构建，并保留安装包、测试报告及截图。[Release 工作流](.github/workflows/release.yml)只在两个平台都通过后发布两个架构的 DMG、ZIP 和 `SHA256SUMS.txt`；上传失败保留草稿，可重试。

首次发布需先将仓库提交并推送到 GitHub、配置 `origin`、启用 Actions，并登录 `gh`。日常升级、失败恢复及 Developer ID 签名 / 公证方式见[中文发布指南](docs/zh-CN/releasing.md) / [English release guide](docs/en/releasing.md)。

## 项目文档

- [中文使用文档](docs/zh-CN/README.md) / [English user guide](docs/en/README.md)
- [中文发布指南](docs/zh-CN/releasing.md) / [English release guide](docs/en/releasing.md)
- [五款 Markdown 工具调研](docs/zh-CN/market-research.md) / [English research report](docs/research/markdown-tools-2026.md)
- [更新记录](CHANGELOG.md) · [贡献指南](CONTRIBUTING.md) · [本地验证记录](VALIDATION.md)

Markdown 解析使用内置 [Marked 15.0.12](https://github.com/markedjs/marked/tree/v15.0.12)，其 [MIT 许可证](Sources/MarknoteCore/Resources/marked-LICENSE.md)随应用分发。原始 HTML 按文字显示；预览不执行文稿脚本。远程图片会联网加载，本地图片受文稿目录边界限制。暂不支持数学公式、Mermaid 或插件。
