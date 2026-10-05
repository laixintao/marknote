"""Exercise real archive validation and simulate GitHub failure boundaries offline."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "Scripts"))
import release
import version


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.version = version.current()
        self.tag = "v" + self.version

    def archive(self, arch, *, app_version=None, cpu=None, legacy_paths=False):
        path = self.directory / f"Marknote-{self.version}-macos-{arch}.zip"
        info = {"CFBundleShortVersionString": app_version or self.version,
                "CFBundleIdentifier": "net.marknote.editor"}
        class DittoZipInfo(zipfile.ZipInfo):
            def _encodeFilenameFlags(self):
                return self.filename.encode("utf-8"), self.flag_bits & ~0x800

        def member(name):
            return DittoZipInfo(name) if legacy_paths else name

        with zipfile.ZipFile(path, "w") as bundle:
            bundle.writestr(member("墨笺.app/Contents/Info.plist"), plistlib.dumps(info))
            bundle.writestr(member("墨笺.app/Contents/MacOS/Marknote"), struct.pack("<II", 0xFEEDFACF, cpu or {"arm64": 0x0100000C, "x86_64": 0x01000007}[arch]))
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        path.with_suffix(".zip.sha256").write_text(f"{digest}  {path.name}\n")
        return path

    def pair(self):
        archives = [self.archive("arm64"), self.archive("x86_64")]
        self.installer("arm64")
        self.installer("x86_64")
        return archives

    def installer(self, arch):
        path = self.directory / f"Marknote-{self.version}-macos-{arch}.dmg"
        path.write_bytes(b"test image" + b"koly" + bytes(508))
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        path.with_suffix(".dmg.sha256").write_text(f"{digest}  {path.name}\n")
        return path

    def test_version_rejects_tag_and_shell_input(self):
        for value in ("v1.2.3", "1.2", "01.2.3", "1.2.3-beta", "1.2.3\n", "$(touch /tmp/x)"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                version.validate(value)

    def test_version_update_preserves_metadata_and_is_idempotent(self):
        path = self.directory / "Info.plist"
        path.write_bytes(plistlib.dumps({"CFBundleShortVersionString": "1.0.0", "CFBundleVersion": "2", "CFBundleIdentifier": "example"}))
        with patch.object(version, "INFO", path):
            version.set_version("1.2.0")
            version.set_version("1.2.0")
            info = plistlib.loads(path.read_bytes())
            self.assertEqual(info["CFBundleVersion"], "3")
            self.assertEqual(info["CFBundleIdentifier"], "example")
            self.assertEqual(version.check_tag("v1.2.0"), "1.2.0")
            with self.assertRaises(ValueError):
                version.check_tag("v1.1.0")

    def test_github_remote_formats(self):
        for url in ("git@github.com:owner/repo.git", "https://github.com/owner/repo.git", "https://github.com/owner/repo", "ssh://git@github.com/owner/repo.git"):
            self.assertEqual(release.repository(url), "owner/repo")
        for url in ("https://example.com/owner/repo", "https://token@github.com/owner/repo", "-bad", "git@github.com:owner/repo extra"):
            with self.assertRaises(ValueError):
                release.repository(url)

    def test_two_architectures_and_combined_checksums(self):
        archives = self.pair()
        assets = release.verify_assets(self.directory, self.version)
        self.assertEqual(assets[:2], archives)
        self.assertEqual(assets[-1].name, "SHA256SUMS")
        self.assertEqual(len(assets[-1].read_text().splitlines()), 4)

    def test_ditto_chinese_paths_can_be_verified_on_linux(self):
        self.archive("arm64", legacy_paths=True)
        self.archive("x86_64", legacy_paths=True)
        self.installer("arm64")
        self.installer("x86_64")
        self.assertEqual(len(release.verify_assets(self.directory, self.version)), 5)

    def test_missing_installer_blocks_publication(self):
        self.pair()
        next(self.directory.glob("*.dmg")).unlink()
        with self.assertRaisesRegex(ValueError, "Missing installer"):
            release.verify_assets(self.directory, self.version)

    def test_invalid_disk_image_is_rejected(self):
        path = self.installer("arm64")
        path.write_bytes(bytes(1024))
        path.with_suffix(".dmg.sha256").write_text(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n")
        with self.assertRaisesRegex(ValueError, "Invalid DMG"):
            release.verify_installer(path)

    def test_missing_intel_package_blocks_publication(self):
        self.archive("arm64")
        with self.assertRaisesRegex(ValueError, "Missing release asset"):
            release.verify_assets(self.directory, self.version)

    def test_tampered_checksum_blocks_publication(self):
        self.pair()
        next(self.directory.glob("*.sha256")).write_text("0" * 64)
        with self.assertRaisesRegex(ValueError, "Checksum mismatch"):
            release.verify_assets(self.directory, self.version)

    def test_matching_checksum_does_not_hide_wrong_version(self):
        self.archive("arm64", app_version="0.0.0")
        self.archive("x86_64")
        with self.assertRaisesRegex(ValueError, "Wrong application/version"):
            release.verify_assets(self.directory, self.version)

    def test_filename_does_not_hide_wrong_cpu(self):
        self.archive("arm64", cpu=0x01000007)
        self.archive("x86_64")
        with self.assertRaisesRegex(ValueError, "Wrong executable architecture"):
            release.verify_assets(self.directory, self.version)

    def publish_commands(self, *, existing=None, fail_upload=False):
        calls = []

        def fake(*args, **kwargs):
            calls.append(args)
            if args[:3] == ("gh", "release", "list"):
                return json.dumps([existing] if existing else [])
            if fail_upload and args[:3] == ("gh", "release", "upload"):
                raise RuntimeError("simulated upload failure")
            return "https://github.com/owner/repo/releases/tag/" + self.tag

        with patch.dict(os.environ, {"GH_REPO": "owner/repo"}), patch.object(release, "command", side_effect=fake):
            try:
                release.publish(self.tag, self.directory)
            except RuntimeError:
                return calls, False
        return calls, True

    def test_release_publishes_only_after_upload(self):
        self.pair()
        calls, success = self.publish_commands()
        self.assertTrue(success)
        create = next(i for i, call in enumerate(calls) if call[:3] == ("gh", "release", "create"))
        upload = next(i for i, call in enumerate(calls) if call[:3] == ("gh", "release", "upload"))
        publish = next(i for i, call in enumerate(calls) if "--draft=false" in call)
        self.assertIn("--verify-tag", calls[create])
        self.assertIn("--draft", calls[create])
        self.assertLess(create, upload)
        self.assertLess(upload, publish)
        self.assertTrue(any(str(part).endswith("SHA256SUMS") for part in calls[upload]))

    def test_failed_upload_never_publishes(self):
        self.pair()
        calls, success = self.publish_commands(fail_upload=True)
        self.assertFalse(success)
        self.assertFalse(any("--draft=false" in call for call in calls))

    def test_failed_draft_can_be_resumed(self):
        self.pair()
        calls, success = self.publish_commands(existing={"tagName": self.tag, "isDraft": True})
        self.assertTrue(success)
        self.assertFalse(any(call[:3] == ("gh", "release", "create") for call in calls))
        self.assertTrue(any("--draft=false" in call for call in calls))

    def test_public_release_is_never_changed(self):
        self.pair()
        calls, success = self.publish_commands(existing={"tagName": self.tag, "isDraft": False})
        self.assertFalse(success)
        self.assertEqual([call[2] for call in calls], ["list"])

    def test_bad_assets_stop_before_github_calls(self):
        with patch.dict(os.environ, {"GH_REPO": "owner/repo"}), patch.object(release, "command") as command:
            with self.assertRaises(ValueError):
                release.publish(self.tag, self.directory)
            command.assert_not_called()

    def test_dirty_worktree_fails_before_network_or_tagging(self):
        with patch.dict(os.environ, {"VERSION": self.version}), patch.object(release.shutil, "which", return_value="tool"), patch.object(release, "command", side_effect=["a" * 40, "?? file.md"]) as command:
            with self.assertRaisesRegex(RuntimeError, "working tree must be clean"):
                release.preflight()
        self.assertEqual(command.call_count, 2)

    def test_uninitialized_repository_fails_with_setup_guidance(self):
        with patch.dict(os.environ, {"VERSION": self.version}), patch.object(release.shutil, "which", return_value="tool"), patch.object(release, "command", return_value="") as command:
            with self.assertRaisesRegex(RuntimeError, "initial commit"):
                release.preflight()
        self.assertEqual(command.call_count, 1)

    def test_missing_changelog_entry_blocks_release(self):
        (self.directory / "CHANGELOG.md").write_text("# Changelog\n")
        with patch.object(release, "ROOT", self.directory), self.assertRaisesRegex(ValueError, "nonempty"):
            release.release_notes(self.tag)


class MakeReleaseTests(unittest.TestCase):
    """Exercise the public Make target against a disposable bare remote, never GitHub."""

    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="marknote-make-release-")
        self.addCleanup(temporary.cleanup)
        self.folder = Path(temporary.name)
        self.repo = self.folder / "work"
        self.repo.mkdir()
        (self.repo / "Resources").mkdir()
        shutil.copytree(release.ROOT / "Scripts", self.repo / "Scripts",
                        ignore=shutil.ignore_patterns("__pycache__"))
        shutil.copy2(release.ROOT / "Makefile", self.repo / "Makefile")
        shutil.copy2(release.ROOT / ".gitignore", self.repo / ".gitignore")
        self.info = self.repo / "Resources/Info.plist"
        self.info.write_bytes(plistlib.dumps({"CFBundleShortVersionString": "1.2.1",
                                            "CFBundleVersion": "7"}))
        (self.repo / "CHANGELOG.md").write_text("# Changelog\n\n## [1.2.1]\n\nPrevious release.\n")
        self.env = dict(os.environ, GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1")
        for key in ("VERSION", "REMOTE", "MAKEFLAGS", "MAKEOVERRIDES", "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"):
            self.env.pop(key, None)
        self.git("init", "-b", "main")
        self.git("config", "user.name", "Release Test")
        self.git("config", "user.email", "release@example.invalid")
        self.git("add", ".")
        self.git("commit", "-m", "Initial release")
        self.git("tag", "v1.2.1")
        self.git("commit", "--allow-empty", "-m", "Fix document rendering")
        self.remote = self.folder / "origin.git"
        self.git("init", "--bare", "--initial-branch=main", str(self.remote))
        self.git("remote", "add", "origin", str(self.remote))
        self.git("push", "origin", "main", "v1.2.1")
        self.before = self.git("rev-parse", "HEAD")

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.repo, env=self.env,
                                       text=True, stderr=subprocess.PIPE).strip()

    def make(self, *args):
        return subprocess.run(["make", *args], cwd=self.repo, env=self.env, text=True,
                              capture_output=True, timeout=30)

    def assert_unchanged(self):
        self.assertEqual(self.before, self.git("rev-parse", "HEAD"))
        self.assertEqual(self.before, self.git("ls-remote", "origin", "refs/heads/main").split()[0])

    def test_plain_make_release_bumps_commits_and_atomically_pushes(self):
        result = self.make("release")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        info = plistlib.loads(self.info.read_bytes())
        self.assertEqual(info["CFBundleShortVersionString"], "1.2.2")
        self.assertEqual(info["CFBundleVersion"], "8")
        self.assertIn("Fix document rendering", (self.repo / "CHANGELOG.md").read_text())
        head = self.git("rev-parse", "HEAD")
        self.assertEqual(self.git("cat-file", "-t", "v1.2.2"), "tag")
        self.assertEqual(head, self.git("ls-remote", "origin", "refs/heads/main").split()[0])
        self.assertEqual(head, self.git("ls-remote", "origin", "refs/tags/v1.2.2^{}").split()[0])
        self.assertEqual(self.git("status", "--porcelain"), "")
        self.assertNotEqual(self.make("release").returncode, 0)  # No changes since v1.2.2.

    def test_explicit_version_preserves_curated_changelog(self):
        path = self.repo / "CHANGELOG.md"
        text = path.read_text().replace("# Changelog", "# Changelog\n\n## [2.0.0]\n\nCurated notes.")
        path.write_text(text)
        self.git("add", "CHANGELOG.md")
        self.git("commit", "-m", "Prepare notes")
        result = self.make("release", "VERSION=2.0.0")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(path.read_text(), text)
        self.assertEqual(plistlib.loads(self.info.read_bytes())["CFBundleShortVersionString"], "2.0.0")

    def test_invalid_or_old_versions_leave_worktree_unchanged(self):
        for value in ("1.2.1", "0.1.0", "01.2.3", "v2.0.0", "1.2.3-rc.1"):
            with self.subTest(value=value):
                self.assertNotEqual(self.make("release", f"VERSION={value}").returncode, 0)
                self.assert_unchanged()
                self.assertEqual(self.git("status", "--porcelain"), "")

    def test_dirty_worktree_and_wrong_branch_fail_before_edits(self):
        path = self.repo / "unfinished.txt"
        path.write_text("work in progress")
        self.assertIn("working tree must be clean", self.make("release").stderr)
        self.assert_unchanged()
        path.unlink()
        self.git("switch", "-c", "feature")
        self.assertIn("main branch", self.make("release").stderr)
        self.assert_unchanged()

    def test_existing_remote_tag_is_not_replaced(self):
        self.git("tag", "v1.2.2")
        self.git("push", "origin", "v1.2.2")
        self.git("tag", "-d", "v1.2.2")
        self.assertIn("already exists on origin", self.make("release").stderr)
        self.assert_unchanged()
        self.assertEqual(self.git("status", "--porcelain"), "")

    def test_remote_ahead_fails_before_edits(self):
        other = self.folder / "other"
        self.git("clone", str(self.remote), str(other))
        self.git("-C", str(other), "-c", "user.name=Other", "-c", "user.email=other@example.invalid",
                 "commit", "--allow-empty", "-m", "Remote work")
        self.git("-C", str(other), "push")
        self.assertIn("Remote main has changes", self.make("release").stderr)
        self.assertEqual(self.before, self.git("rev-parse", "HEAD"))
        self.assertEqual(self.git("status", "--porcelain"), "")

    def test_preflight_does_not_edit_files_or_push(self):
        result = self.make("release-check")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_unchanged()
        self.assertEqual(self.git("status", "--porcelain"), "")
        self.assertEqual(self.git("tag", "--list", "v1.2.2"), "")

    def test_rejected_atomic_push_keeps_commit_and_tag_for_retry(self):
        hook = self.remote / "hooks/pre-receive"
        hook.write_text("#!/bin/sh\nexit 1\n")
        hook.chmod(0o755)
        result = self.make("release")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("git push --atomic origin HEAD:refs/heads/main refs/tags/v1.2.2", result.stderr)
        self.assertEqual(self.before, self.git("ls-remote", "origin", "refs/heads/main").split()[0])
        self.assertEqual(self.git("ls-remote", "origin", "refs/tags/v1.2.2"), "")
        self.assertEqual(self.git("rev-parse", "HEAD"), self.git("rev-parse", "v1.2.2^{}"))
        hook.unlink()
        self.git("push", "--atomic", "origin", "HEAD:refs/heads/main", "refs/tags/v1.2.2")
        self.assertEqual(self.git("rev-parse", "HEAD"), self.git("ls-remote", "origin", "refs/heads/main").split()[0])


if __name__ == "__main__":
    unittest.main()
