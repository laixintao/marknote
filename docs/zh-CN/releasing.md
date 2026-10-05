# 构建与发布

[项目首页](../../README.zh-CN.md) · [使用文档](README.md) · [English](../en/releasing.md)

## 一次配置

1. 将项目提交到 Git，并推送到你自己的 GitHub 仓库。仓库默认分支必须包含 `.github/workflows/` 下的工作流。
2. 配置名为 `origin` 的 GitHub 远端，确保你可以推送标签。支持 github.com 的 HTTPS 与 SSH 地址；可用 `REMOTE=其他远端名` 指定远端。
3. 在仓库设置中启用 Actions。CI 仅需读取权限；Release 的发布 job 已单独声明 `contents: write`，使用内置 `GITHUB_TOKEN`，无需另配发布 token。
4. 安装 Make、Python 3 和 Git，Git 身份需要推送 `main` 和标签的权限。GitHub CLI 可用于查看 Actions，但 `make release` 不要求安装它。

初次接入时可使用下面的命令，其中仓库地址需要换成你自己的：

```sh
git remote add origin git@github.com:YOUR_ACCOUNT/YOUR_REPOSITORY.git
git add .
git commit -m "Prepare Marknote for release"
git push -u origin HEAD
```

如果已有远端或提交，请只执行尚未完成的步骤。`make release` 会生成发布提交和标签；应用代码修改需要事先提交。

## 一键发布下一版本

在干净且已同步远端的 `main` 分支上，运行：

```sh
make release
```

遵循统一的 [make release SOP](https://github.com/laixintao/homebrew-tap/blob/main/docs/RELEASE_STANDARD.md#maintainer-command)，无需手动修改版本或 changelog。命令依次执行：

1. 检查干净的 `main` 工作区、远端历史、新提交、版本标签和 Git 身份。
2. 自动递增 patch 版本和构建号，根据当前版本标签之后的提交生成更新记录（保留已准备好的条目），创建发布提交和注释标签，原子推送 `main` 与标签。例如 `1.2.1` 自动变为 `1.2.2`。
3. GitHub 在 `macos-15`（arm64）和 `macos-15-intel`（x86_64）上分别检查文档、运行核心和原生窗口测试、构建并验证签名、打包。
4. 发布 job 检查两个安装包的 SHA-256、内嵌版本及实际 Mach-O 架构；从更新记录生成双语发布说明。
5. 校验两个架构的全部 DMG / ZIP，生成 `SHA256SUMS` 和 GitHub 构建来源证明。
6. 创建 Release 草稿，全部附件上传成功后再公开发布。本地命令在推送成功后返回，并输出 Actions 和待发布 Release 的链接；在 Actions 中确认发布结果。

GitHub 官方的 [runner 列表](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)与 [Release CLI 文档](https://cli.github.com/manual/gh_release_create)说明了这里使用的平台与发布接口。

可先检查下一版本（不修改源文件或推送），也可以指定一个更高版本：

```sh
make release-check
make release VERSION=1.3.0
```

对于 `make release`，`VERSION` 指定下一版本，必须高于当前源文件版本，且采用稳定版 `X.Y.Z` 格式。对于 `make package`，它仍是已有版本的校验值。

## 日常 SOP

```sh
git switch main
git pull --ff-only
make release
```

原有 `make version` 保留用于开发，但发布前不再需要运行它。如果要精心编写更新说明，事先提交非空的 `## [<下一版本>]` 条目，脚本会保留它。Release 成功后，Tap 每六小时自动同步 cask，也可手动运行 Tap 的 Update casks 工作流。

## 本地命令与产物

| 命令 | 结果 |
| --- | --- |
| `make build` | `dist/墨笺.app`，默认 release 构建 |
| `make run` | 构建并打开应用 |
| `make test` | Markdown、Unicode、安全边界和语言资源测试 |
| `make check` | 脚本语法、文档链接及发布工具失败恢复测试；有安装时也运行 ShellCheck 和 actionlint |
| `make smoke` | 独立应用标识下的原生 AppKit / WebKit 测试 |
| `make verify` | 上述检查和测试全部执行 |
| `make package` | 当前机器架构的 DMG、ZIP 和各自 `.sha256`，位于 `dist/releases/` |
| `make installer` | 生成 DMG 和 ZIP；挂载检查应用签名、版本、架构及 Applications 快捷方式 |
| `make screenshots` | 生成 `docs/images/product-*.png` 的六张真实截图 |

截图和窗口测试需要当前登录用户的 macOS 图形会话，使用独立应用标识，不改动正式应用偏好。原始截图和日志在 `.build/screenshots-*/`；窗口测试结果在 `.build/smoke-*/`。

本地打包只构建当前 Mac 的架构；两个原生架构安装包由 GitHub 的两个 runner 生成，不依赖 Rosetta。CI 的下载产物保留 14 天，Release 附件供正式版本下载。

## 失败后恢复

- **代码未提交、版本不匹配或标签指向其他提交**：修正后重新运行；脚本不会强推或移动标签。
- **推送失败**：发布提交和标签保留在本地。网络或权限修复后，执行终端打印的完整 `git push --atomic ...` 命令；不要再次运行 `make release` 来重试同一版本。
- **构建 / 测试失败**：检查 Actions 日志及 `marknote-checks-*` 附件。环境瞬时故障可在 GitHub 点击 Re-run failed jobs。需要修改代码时使用新版本、新提交和新标签。
- **附件上传失败**：Release 保持草稿。重新运行失败的发布 job 会补传草稿附件；已公开版本不会被替换。
- **没有触发工作流**：确认 Actions 已启用、默认分支已有 Release 工作流、推送标签使用的是个人身份。也可在 Actions → Release → Run workflow 中输入已存在的标签，例如 `v1.1.0`。
- **本地命令结束**：云端仍在继续构建发布；推送成功不等于 Release 已公开，请在打印的 Actions 链接中确认结果。

Release 不会在测试失败时公开。已有公开版本需要改动时，请递增版本发布。

## Developer ID 签名与公证（可选）

默认构建使用 ad-hoc 临时签名，适合本地构建和测试，不等同于 Apple Developer ID 签名或公证。公共下载的首次运行可能被 Gatekeeper 拦截。

如果本地钥匙串已安装你的 Developer ID Application 证书、私钥，并已通过 `xcrun notarytool store-credentials` 配好公证凭据：

```sh
make package \
  SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
  NOTARY_PROFILE='marknote-notary'
```

脚本会启用 hardened runtime、签名、提交 Apple 公证、装订公证票据后重新生成 ZIP 和校验和，再对 DMG 安装包签名、公证及装订票据。所需的 JIT 权限用于内置 JavaScriptCore Markdown 解析器。密钥和凭据仅通过本地钥匙串使用。

当前 GitHub 工作流默认不导入证书，也不执行公证；上述变量控制本地打包，不会传到 GitHub。若要将 CI 改为公证发布，需要自行配置受保护的签名凭据，并同步修改工作流与发布说明。参考 [Apple 公证文档](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。
