# Changelog / 更新记录

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
