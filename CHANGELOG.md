# Changelog / 更新记录

## [Unreleased]

## [1.2.0] - 2026-09-18

### Added / 新增

- Add a bilingual command palette (`⇧⌘P`) and quick open (`⇧⌘O`) for open, recent, and nearby Markdown files. / 新增双语命令面板（`⇧⌘P`）及已打开、最近和同目录文稿的快速切换（`⇧⌘O`）。
- Paste, drop, or choose images and store them as relative assets beside the document. / 粘贴、拖入或选择图片，自动保存为文稿旁的相对路径附件。
- Add optional paragraph focus and typewriter scrolling, preserving Chinese input and selections. / 新增段落聚焦和打字机滚动，保留中文输入及选区。
- Format Markdown tables (`⌥⌘T`), navigate cells with Tab / Shift-Tab, and append rows with Tab. / 整理 Markdown 表格（`⌥⌘T`）、用 Tab / Shift-Tab 切换单元格及在末尾增行。
- Paste a URL onto selected words to create a link; add an explicit plain-text paste command. / 选中文字后粘贴网址生成链接，并新增纯文本粘贴命令。

### Improved / 改进

- Replace the toolbar switches with a single-choice Edit / Split / Preview button group. / 工具栏改为编辑、分栏、预览单选按钮组。
- Update English and Chinese guides with new shortcuts and six real product screenshots; document the feature choices with official sources and dated feedback from five Markdown tools. / 更新中英文指南、快捷键及六张真实产品截图，并补充五款 Markdown 工具的官方资料、用户反馈及功能选择依据。

### Fixed / 修复

- Keep the current view mode when navigating the outline, with preview scrolling and deferred navigation while loading. / 目录跳转保留当前模式，并支持预览滚动及加载期间的跳转。

## [1.1.0] - 2026-09-18

### Added / 新增

- DMG installers with an Applications shortcut for Apple Silicon and Intel. / 双架构 DMG 安装器，内含应用程序快捷方式。
- An app-menu command to make Marknote the default Markdown editor in Finder. / 可在应用菜单中设置为 Finder 的默认 Markdown 编辑器。
- English as the default README, with a separate Chinese overview. / 默认英文首页，保留独立中文介绍。

- English / 简体中文 interface, system language detection, and saved language preferences. / 中英文界面、跟随系统与语言偏好保存。
- Independent Edit and Preview switches with keyboard shortcuts and focus-mode integration. / 编辑与预览独立开关、快捷键及专注模式配合。
- Native AppKit Markdown editing, outline navigation, autosave, HTML and PDF exports. / 原生编辑、文档大纲、自动保存及 HTML / PDF 导出。
- Bilingual documentation, real product screenshots, and reproducible screenshot capture. / 双语文档、真实产品截图与可重复的截图生成命令。
- Apple Silicon / Intel CI and tag-based GitHub releases with versioned packages and SHA-256 checksums. / 双架构 CI、版本标签发布、版本化安装包及校验和。

### Improved / 改进

- Language and layout changes retain document content, selections, and undo history. / 语言和布局切换保留正文、选区及撤销历史。
- Fresh bundle staging prevents stale resources from entering packages. / 每次重新组装应用包，避免旧资源进入发布产物。
- Release uploads remain drafts until all artifacts are attached. / 全部产物上传成功后才公开 Release。
