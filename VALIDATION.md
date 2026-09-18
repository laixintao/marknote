# 验证记录

验证日期：2026-09-18。环境：Apple Silicon，macOS 15.7.9，Swift 6.1.2，Xcode Command Line Tools。

## 核心测试

`make test`：13 组测试、367 项断言，全部通过。

覆盖 Markdown / GFM、嵌套列表与引用链接、原始 HTML 和危险链接处理、本地图片目录边界、代码围栏外的文档大纲、Unicode 格式操作、选区边界、列表续写和退出、中英文字数、独立 HTML，以及系统语言解析、语言偏好持久化、通知去重、中英文资源完整性、格式占位符一致性和本地化指南。

## 发布版原生应用验证

`bash Scripts/smoke-test.sh release`：51 项检查全部通过。

覆盖真实 NSTextView 编辑、窗口响应链、撤销 / 重做及文档修改状态、列表续写、NSDocument 保存和重新打开、原位自动保存、中文输入法组合与提交、工具栏、显示与专注模式、WebKit 标题 / 表格 / 任务渲染、完整中文 PDF 导出、浅色 / 深色截图、未保存文稿关闭提示及取消后的内容保留。

新增验证包括：通过语言菜单切换中文 / English / 跟随系统；全部已打开窗口的菜单、工具栏、标题、侧栏、状态文案和空白预览更新；界面切换保留文稿、编辑器实例、选区、文件路径、修改状态和撤销 / 重做；英文插入占位文案及选区；独立 Edit / Preview 开关的各状态、最后一个可见区域的保护、响应链操作、菜单勾选、专注模式恢复及多窗口布局独立性。

本次报告和渲染产物位于 `.build/smoke-20260918-143231-LB8KB0/`。测试在独立应用标识下运行；测试副本与交付二进制的 Mach-O UUID 均为 `C60A118A-56F9-31AB-A5AF-44B5BEC149C7`，仅应用标识及签名元数据不同。

自动输入测试在保存前显式提交撤销分组，以模拟真实键盘事件结束，避免将尚未提交的模拟输入误判为保存后的修改。

## CI、发布与文档验证

- `make check`：5 个 Shell 脚本检查、70 个本地文档链接及 20 项发布工具测试全部通过。
- actionlint 1.7.12 校验全部 Actions 工作流通过；ShellCheck 与 YAML 解析通过。
- 发布工具测试覆盖版本幂等更新、GitHub 远端解析、未初始化 / 未提交工作区、远端标签冲突、精确提交标记、等待工作流、缺少架构产物、错误版本 / 架构、损坏校验和、公开版本保护、上传失败不公开、草稿恢复。
- 验证了 `ditto` 生成的中文 ZIP 路径兼容性：显式处理未设置 UTF-8 标志的文件名，确保 Ubuntu 发布 job 可读取中文应用包。
- `make package` 成功生成 Apple Silicon ZIP 和校验和；验证包内版本、真实 CPU 架构、CRC 和 SHA-256，再用 `ditto` 解压并通过 `codesign --verify --deep --strict`。
- 本机使用 `swift build -c release --arch x86_64`（构建缓存设于项目目录）交叉编译 Intel 版本成功；这只验证编译与链接，Intel 原生运行仍由 GitHub 的 Intel runner 验证。
- `make screenshots` 的底层截图脚本已运行，生成浅色 / 深色中文、英文双栏及英文只预览共四张真实截图，均已目视检查。产物在 `docs/images/`，原始记录在 `.build/screenshots-KT1G7P/`。

当前本地仓库尚无首次提交或 GitHub 远端；发布预检能明确拒绝此状态，未推送标签、未触发云端 Actions、未创建真实 GitHub Release。GitHub 双架构执行及实际上传需完成仓库接入后验证。Developer ID 签名与 Apple 公证需要维护者凭据，本次仅验证默认临时签名路径。

## 交付产物

- `dist/墨笺.app`：1.1.0 发布构建，arm64，最低系统版本声明为 macOS 13；实测系统为 macOS 15.7.9。
- `dist/releases/Marknote-1.1.0-macos-arm64.zip`：包含完整 `.app` 的版本化压缩包。
- 同目录的 `.zip.sha256`：对应安装包的 SHA-256 校验和。
- `codesign --verify --deep --strict` 和 Info.plist 检查通过。
- 同一发布二进制已通过隔离应用副本启动并完成原生窗口测试。

应用自己的界面实时切换语言；macOS 系统面板在重新启动应用后采用语言偏好。构建使用本地临时签名，尚未做 Developer ID 公证；分发要求见[发布指南](docs/zh-CN/releasing.md)，功能边界见[使用文档](docs/zh-CN/README.md)。
