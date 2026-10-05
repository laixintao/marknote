# Build and release

[Project home](../../README.md) · [User guide](README.md) · [简体中文](../zh-CN/releasing.md)

## One-time setup

1. Commit the project and push it to your own GitHub repository. The default branch must include the workflows under `.github/workflows/`.
2. Configure a GitHub remote named `origin` and make sure you can push tags. github.com HTTPS and SSH URLs are supported; use `REMOTE=another-name` to select another remote.
3. Enable Actions in repository settings. CI has read-only permissions. The Release publish job explicitly requests `contents: write` and uses the built-in `GITHUB_TOKEN`; no separate publishing token is needed.
4. Install Make, Python 3, and Git. Your Git identity needs permission to push `main` and tags. GitHub CLI is optional for watching Actions; it is not required by `make release`.

For a new repository, replace the URL below with your own:

```sh
git remote add origin git@github.com:YOUR_ACCOUNT/YOUR_REPOSITORY.git
git add .
git commit -m "Prepare Marknote for release"
git push -u origin HEAD
```

Skip setup steps you have already completed. The command creates a release commit and tag; commit your application changes first.

## Release with one command

From a clean, up-to-date `main` branch containing the changes you want to publish:

```sh
make release
```

This follows the shared [make release SOP](https://github.com/laixintao/homebrew-tap/blob/main/docs/RELEASE_STANDARD.md#maintainer-command). No manual version bump or changelog edit is required. The command:

1. Checks a clean `main` worktree, remote history, new commits, version tags, and Git identity.
2. Bumps the patch version and build number, generates a changelog entry from commits since the current version tag (preserving a prepared entry), creates a release commit and annotated tag, and atomically pushes `main` and the tag. For example, `1.2.1` becomes `1.2.2`.
3. Runs repository checks, core tests, and native window tests on `macos-15` (arm64) and `macos-15-intel` (x86_64), then builds, verifies signatures, and packages each architecture.
4. Verifies all download checksums, ZIP-embedded app versions, actual Mach-O CPU types, and DMG trailers; generates bilingual notes from the changelog.
5. Verifies all four DMG / ZIP files, writes `SHA256SUMS`, and creates GitHub build-provenance attestations.
6. Creates a draft and publishes it only after every upload succeeds. The local command returns after pushing and prints the Actions and future Release URLs; follow Actions to confirm publication.

See GitHub's [runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners) and [Release CLI documentation](https://cli.github.com/manual/gh_release_create) for the platforms and publishing interface used here.

Check the next release without editing source files or pushing, or choose a specific newer version:

```sh
make release-check
make release VERSION=1.3.0
```

For `make release`, `VERSION` selects the next stable `X.Y.Z` version and must be newer than the source version. For `make package`, it remains an assertion of the already-recorded version.

## Daily SOP

```sh
git switch main
git pull --ff-only
make release
```

The existing `make version` command remains available for development, but is not a prerequisite for publication. If you want curated notes, commit a nonempty `## [<next-version>]` entry before releasing; it will be preserved. After Release succeeds, this app's Homebrew cask updates through the tap's six-hour schedule or its manually triggered Update casks workflow.

## Local commands and output

| Command | Result |
| --- | --- |
| `make build` | `dist/墨笺.app`, using release configuration by default |
| `make run` | Build and open the app |
| `make test` | Markdown, Unicode, security-boundary, and localization tests |
| `make check` | Shell syntax, documentation links, release failure/recovery tests; ShellCheck and actionlint when installed |
| `make smoke` | Real AppKit / WebKit tests under an isolated bundle identifier |
| `make verify` | Run all the checks and tests above |
| `make package` | Versioned DMG + ZIP with `.sha256` files in `dist/releases/` for this Mac |
| `make installer` | Build the DMG (also produces the companion ZIP); mount and verify the app, version, architecture, and Applications shortcut |
| `make screenshots` | Six real window captures at `docs/images/product-*.png` |

Screenshots and window tests require a logged-in macOS graphical session. Separate bundle identifiers isolate preferences from the regular app. Screenshot originals and logs live in `.build/screenshots-*/`; native test results live in `.build/smoke-*/`.

Local packaging targets the current Mac architecture. GitHub's two native runners produce both packages without Rosetta. CI artifacts are retained for 14 days; Release attachments provide versioned downloads.

## Recover from a failure

- **Dirty worktree, wrong version, or tag at another commit:** fix the problem and retry. Tags are never force-pushed or moved.
- **Push failed:** the release commit and tag remain locally. Fix connectivity or permissions, then run the exact `git push --atomic ...` command printed by the helper. Do not run `make release` again to retry the same version.
- **Build or tests failed:** inspect Actions logs and `marknote-checks-*` artifacts. For a transient environment failure, use Re-run failed jobs. Code fixes require a new commit, version, and tag.
- **Asset upload failed:** the Release stays a draft. Rerun the failed publish job to upload the draft assets again; already published releases are never replaced.
- **No workflow started:** check Actions settings, the default-branch workflow, and that the tag was pushed with your own identity. You can also use Actions → Release → Run workflow with an existing tag such as `v1.1.0`.
- **Local command finished:** publication continues in Actions; successful push alone does not mean the release is public yet.

Failed tests never publish a release. Use a new version to change an already published release.

## Optional Developer ID signing and notarization

Default builds use ad-hoc signatures for local development and testing. This is not Developer ID signing or Apple notarization; Gatekeeper may block downloaded builds on first launch.

With your Developer ID Application certificate and private key installed in the local Keychain, and notarization credentials stored using `xcrun notarytool store-credentials`:

```sh
make package \
  SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
  NOTARY_PROFILE='marknote-notary'
```

The script enables hardened runtime, signs, submits for notarization, staples the ticket, and regenerates the ZIP and checksum, then signs, notarizes, and staples the DMG installer. The JIT entitlement supports the embedded JavaScriptCore Markdown parser. Keys and credentials stay in the local Keychain.

The GitHub workflow does not import certificates or notarize by default. These variables configure local packaging; they are not sent to GitHub. To notarize in CI, configure protected signing credentials and update both the workflow and release notes. See [Apple's notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
