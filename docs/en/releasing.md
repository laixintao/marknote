# Build and release

[Project home](../../README.en.md) · [User guide](README.md) · [简体中文](../zh-CN/releasing.md)

## One-time setup

1. Commit the project and push it to your own GitHub repository. The default branch must include the workflows under `.github/workflows/`.
2. Configure a GitHub remote named `origin` and make sure you can push tags. github.com HTTPS and SSH URLs are supported; use `REMOTE=another-name` to select another remote.
3. Enable Actions in repository settings. CI has read-only permissions. The Release publish job explicitly requests `contents: write` and uses the built-in `GITHUB_TOKEN`; no separate publishing token is needed.
4. Install [GitHub CLI](https://cli.github.com/) and run `gh auth login`. Your local identity needs repository write access and permission to view Actions runs.

For a new repository, replace the URL below with your own:

```sh
git remote add origin git@github.com:YOUR_ACCOUNT/YOUR_REPOSITORY.git
git add .
git commit -m "Prepare Marknote for release"
git push -u origin HEAD
gh auth login
```

Skip setup steps you have already completed. `make release` checks Git state and pushes a tag; it does not create a repository, commit changes, or overwrite published versions.

## Release with one command

Once the code and changelog are committed and the current commit is pushed:

```sh
make release
```

The command reads the version from `Resources/Info.plist` (currently `1.1.0`) and:

1. Checks a clean worktree, GitHub remote, pushed commit, active Release workflow, changelog entry, and version tags.
2. Creates and pushes an annotated `v1.1.0` tag, triggering the Release workflow.
3. Runs repository checks, core tests, and native window tests on `macos-15` (arm64) and `macos-15-intel` (x86_64), then builds, verifies signatures, and packages each architecture.
4. Verifies both ZIP checksums, embedded app versions, and actual Mach-O CPU types; generates bilingual notes from the changelog.
5. Creates a draft, uploads both ZIP files and `SHA256SUMS.txt`, and publishes only after all uploads succeed. The local command waits for CI and prints the Release URL.

See GitHub's [runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners) and [Release CLI documentation](https://cli.github.com/manual/gh_release_create) for the platforms and publishing interface used here.

Run a read-only preflight, or explicitly require a version match:

```sh
make release-check
make release VERSION=1.1.0
```

For publishing and packaging, `VERSION` is an assertion, not a silent source-file override. Stable `X.Y.Z` versions are supported.

## Prepare the next version

```sh
make version VERSION=1.2.0
# Add a nonempty ## [1.2.0] entry to CHANGELOG.md
make verify
git add Resources/Info.plist CHANGELOG.md
git commit -m "Release 1.2.0"
git push origin HEAD
make release
```

`make version` updates the app version and increments the build number. Repeating the same version does not increment it again. Commit any other source changes as well. The source version, tag, and app version inside the ZIP must agree.

## Local commands and output

| Command | Result |
| --- | --- |
| `make build` | `dist/墨笺.app`, using release configuration by default |
| `make run` | Build and open the app |
| `make test` | Markdown, Unicode, security-boundary, and localization tests |
| `make check` | Shell syntax, documentation links, release failure/recovery tests; ShellCheck and actionlint when installed |
| `make smoke` | Real AppKit / WebKit tests under an isolated bundle identifier |
| `make verify` | Run all the checks and tests above |
| `make package` | `dist/releases/Marknote-version-macos-architecture.zip` and `.zip.sha256` for this Mac |
| `make screenshots` | Four real window captures at `docs/images/product-*.png` |

Screenshots and window tests require a logged-in macOS graphical session. Separate bundle identifiers isolate preferences from the regular app. Screenshot originals and logs live in `.build/screenshots-*/`; native test results live in `.build/smoke-*/`.

Local packaging targets the current Mac architecture. GitHub's two native runners produce both packages without Rosetta. CI artifacts are retained for 14 days; Release attachments provide versioned downloads.

## Recover from a failure

- **Dirty worktree, wrong version, or tag at another commit:** fix the problem and retry. Tags are never force-pushed or moved.
- **Tag push failed:** the local tag remains; rerun `make release` after fixing connectivity or permissions.
- **Build or tests failed:** inspect Actions logs and `marknote-checks-*` artifacts. For a transient environment failure, use Re-run failed jobs. Code fixes require a new commit, version, and tag.
- **Asset upload failed:** the Release stays a draft. Rerun the failed publish job to upload the draft assets again; already published releases are never replaced.
- **No workflow started:** check Actions settings, the default-branch workflow, and that the tag was pushed with your own identity. You can also use Actions → Release → Run workflow with an existing tag such as `v1.1.0`.
- **Local wait was interrupted or failed:** follow the printed Actions URL. Stopping the local command does not cancel the cloud workflow.

Failed tests never publish a release. Use a new version to change an already published release.

## Optional Developer ID signing and notarization

Default builds use ad-hoc signatures for local development and testing. This is not Developer ID signing or Apple notarization; Gatekeeper may block downloaded builds on first launch.

With your Developer ID Application certificate and private key installed in the local Keychain, and notarization credentials stored using `xcrun notarytool store-credentials`:

```sh
make package \
  SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
  NOTARY_PROFILE='marknote-notary'
```

The script enables hardened runtime, signs, submits for notarization, staples the ticket, and regenerates the ZIP and checksum. The JIT entitlement supports the embedded JavaScriptCore Markdown parser. Keys and credentials stay in the local Keychain.

The GitHub workflow does not import certificates or notarize by default. These variables configure local packaging; they are not sent to GitHub. To notarize in CI, configure protected signing credentials and update both the workflow and release notes. See [Apple's notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
