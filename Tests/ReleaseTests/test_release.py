"""Exercise real archive validation and simulate GitHub failure boundaries offline."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import struct
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
        self.assertEqual(assets[-1].name, "SHA256SUMS.txt")
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
        self.assertTrue(any(str(part).endswith("SHA256SUMS.txt") for part in calls[upload]))

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

    def test_one_command_tags_explicit_commit_then_waits(self):
        args = ("owner/repo", "origin", self.tag, "a" * 40, False, False)
        calls = []

        def fake(*command, **kwargs):
            calls.append(command)
            return '[{"databaseId": 42}]' if command[:3] == ("gh", "run", "list") else ""

        with patch.object(release, "preflight", return_value=args), patch.object(release, "command", side_effect=fake):
            release.start()
        self.assertEqual(calls[0], ("git", "tag", "-a", self.tag, "-m", f"Marknote {self.tag}", "a" * 40))
        self.assertEqual(calls[1], ("git", "push", "origin", f"refs/tags/{self.tag}:refs/tags/{self.tag}"))
        self.assertTrue(any(command[:3] == ("gh", "run", "watch") and "--exit-status" in command for command in calls))

    def test_existing_remote_tag_is_not_pushed_again(self):
        args = ("owner/repo", "origin", self.tag, "a" * 40, True, True)
        with patch.object(release, "preflight", return_value=args), patch.object(release, "command", side_effect=['[{"databaseId": 42}]', "", ""]) as command:
            release.start()
        self.assertFalse(any(call.args[0] == "git" for call in command.call_args_list))

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

    def test_remote_tag_on_another_commit_is_not_moved(self):
        revision = "a" * 40

        def fake(*args, **kwargs):
            if args[:3] == ("git", "rev-parse", "--verify"):
                return revision if args[3] == "HEAD" else ""
            if args[:3] == ("git", "remote", "get-url"):
                return "git@github.com:owner/repo.git"
            if args[:2] == ("gh", "api"):
                return revision if "/commits/" in args[2] else '{"state":"active"}'
            if args[:3] == ("gh", "release", "list"):
                return "[]"
            if args[:2] == ("git", "ls-remote"):
                return f"{'b' * 40}\trefs/tags/{self.tag}\n{'c' * 40}\trefs/tags/{self.tag}^{{}}"
            return ""

        with patch.dict(os.environ, {"VERSION": self.version, "REMOTE": "origin"}), patch.object(release.shutil, "which", return_value="tool"), patch.object(release, "command", side_effect=fake) as command:
            with self.assertRaisesRegex(RuntimeError, "Remote tag .* another commit"):
                release.preflight()
        self.assertFalse(any(call.args[:2] in (("git", "push"), ("git", "tag")) for call in command.call_args_list))

    def test_missing_changelog_entry_blocks_release(self):
        (self.directory / "CHANGELOG.md").write_text("# Changelog\n")
        with patch.object(release, "ROOT", self.directory), self.assertRaisesRegex(ValueError, "nonempty"):
            release.release_notes(self.tag)


if __name__ == "__main__":
    unittest.main()
