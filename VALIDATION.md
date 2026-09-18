# Local validation

Validated on 2026-09-18 with Apple Silicon, macOS 15.7.9, Swift 6.1.2, and Xcode Command Line Tools. Cloud results are recorded separately in [GitHub Actions](https://github.com/laixintao/marknote/actions).

## Core behavior

`make test`: **18 tests, 515 assertions, no failures**.

Coverage includes CommonMark / GFM, nested lists, reference links, HTML and unsafe links, local image containment, outlines, Unicode formatting, selection boundaries, list continuation, CJK and Latin word counts, standalone HTML, system language resolution, persisted language preferences, notifications, and complete English / Chinese translations.

Writing-tool checks cover fuzzy search ranking, safe smart links with Unicode selections, table alignment / escaped pipes / CRLF / ragged rows / cell navigation / code-block exclusion, and local image storage with unique names, batch validation, and symlink containment.

## Native application

`bash Scripts/smoke-test.sh release`: **99 checks passed** using a separate test application identifier.

The checks exercise real AppKit windows, editing, undo / redo, document modification state, UTF-8 save and reopen, in-place autosave, Chinese input composition, the single-choice Edit / Split / Preview button group and outline navigation in each mode, focus mode, multiple windows, language changes, WebKit rendering, readable Chinese PDF export, appearance screenshots, and the unsaved-document close prompt.

New native checks exercise smart URL paste, independent table-row undo, named-pasteboard image import and real WebKit image loading, retained assets on undo / redo, image-file reading, cancelling the save-before-insert prompt, paragraph dimming, caret centring, Chinese composition in the editor and command search, keyboard command execution / cancellation, and opening a nearby Markdown file. Tests use a private pasteboard and do not overwrite the user's clipboard. Drag/drop and the file chooser share the verified image reader; physical drag gestures and completing the first-save file chooser remain manual checks.

Default-editor checks verify the Markdown-only type selection, current application URL, sequential requests, and error propagation. They inject the system setter so the tests do not change the machine's file associations. Completing the macOS default-app confirmation is a manual integration step.

The latest local native report and captures are in `.build/smoke-20260918-160310-UtBIlr/`. Synthetic editing dispatches an AppKit event before saving and between separate undoable commands so document editing activities can finish even on an idle CI desktop. A watchdog captures process stacks if a native test times out.

## Installer and release tooling

- `make check` validates shell syntax, local documentation links, screenshot signatures, and release-tool unit tests.
- The release-tool suite covers version updates, GitHub remote parsing, dirty worktrees, immutable tags, workflow waiting, architecture and version mismatches, checksum failures, missing installers, malformed disk images, draft recovery, and interrupted uploads.
- actionlint validates all GitHub workflows. ShellCheck runs when installed.
- `make package` successfully built the Apple Silicon ZIP and DMG, with individual SHA-256 checksums. Verification checks the ZIP's embedded version, Mach-O CPU type, CRC, and signature after extraction. It mounts the DMG read-only and verifies the application signature, version, CPU architecture, installation instructions, and Applications shortcut.
- Chinese ZIP paths created by `ditto` are handled even when the ZIP does not set the UTF-8 filename flag, allowing the Linux publishing job to inspect them.
- `make screenshots` generated six real product window captures in `docs/images/`, including the command palette and paragraph focus / typewriter view; each was visually inspected.

The local artifacts are `dist/墨笺.app` and `dist/releases/Marknote-1.2.0-macos-arm64.{dmg,zip}`, with adjacent `.sha256` files. Native Intel execution and both release architectures are checked by the separate macOS GitHub runners.

The core and native results above were collected before the 1.2.0 version bump. The release workflow repeats these checks for the tagged commit on both architectures before publishing its packages.

The declared minimum is macOS 13; local runtime validation used macOS 15.7.9. Developer ID signing and Apple notarization require maintainer credentials and were not exercised. Default builds use ad-hoc signatures. See the [release guide](docs/en/releasing.md) and [user guide](docs/en/README.md).
