#!/usr/bin/env python3
"""Prepare and push the next release, or publish verified CI assets."""
import argparse
from datetime import date
import hashlib
import html
import json
import os
from pathlib import Path
import plistlib
import re
import shlex
import shutil
import struct
import subprocess
import sys
import tempfile
import zipfile

import version

ROOT = Path(__file__).resolve().parent.parent


def command(*args, capture=True, allowed=(0,)):
    result = subprocess.run(args, cwd=ROOT, text=True, capture_output=capture)
    if result.returncode not in allowed:
        detail = result.stderr.strip() if capture else "See command output above."
        raise RuntimeError(f"{' '.join(args[:3])} failed: {detail}")
    return result.stdout.strip() if capture and result.returncode == 0 else ""


def repository(remote_url):
    patterns = [r"https://github\.com/([^/\s]+/[^/\s]+?)(?:\.git)?/?",
                r"git@github\.com:([^/\s]+/[^/\s]+?)(?:\.git)?",
                r"ssh://git@github\.com/([^/\s]+/[^/\s]+?)(?:\.git)?/?"]
    for pattern in patterns:
        match = re.fullmatch(pattern, remote_url)
        if match and re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", match[1]):
            return match[1]
    raise ValueError("The release remote must be a github.com HTTPS or SSH repository URL.")


def release_state(repo, tag):
    releases = json.loads(command("gh", "release", "list", "--repo", repo, "--limit", "1000", "--json", "tagName,isDraft"))
    return next((item for item in releases if item["tagName"] == tag), None)


def preflight():
    if not shutil.which("git"):
        raise RuntimeError("Install Git before releasing (see docs/en/releasing.md).")
    revision = command("git", "rev-parse", "--verify", "HEAD", allowed=(0, 128))
    if not revision:
        raise RuntimeError("Create an initial commit and push the project to GitHub before releasing.")
    if command("git", "status", "--porcelain"):
        raise RuntimeError("Commit all changes before releasing. The working tree must be clean.")
    if command("git", "branch", "--show-current") != "main":
        raise RuntimeError("Release from the main branch.")
    current = version.current()
    major, minor, patch = map(int, current.split("."))
    requested = version.validate(os.environ.get("VERSION") or f"{major}.{minor}.{patch + 1}")
    if tuple(map(int, requested.split("."))) <= (major, minor, patch):
        raise ValueError(f"The next version must be newer than {current}.")
    tag = f"v{requested}"
    remote = os.environ.get("REMOTE") or "origin"
    if remote.startswith("-"):
        raise ValueError("Invalid Git remote name.")
    remote_url = command("git", "remote", "get-url", remote)
    if command("git", "remote", "get-url", "--push", remote) != remote_url:
        raise RuntimeError("Fetch and push URLs must be identical for releases.")
    if command("git", "tag", "--list", tag):
        raise RuntimeError(f"{tag} already exists locally. Retry its push instead of bumping again.")
    # Check the remote before editing any version or changelog files.
    if command("git", "ls-remote", remote, f"refs/tags/{tag}"):
        raise RuntimeError(f"{tag} already exists on {remote}. Choose a new version.")
    command("git", "fetch", "--quiet", remote, "refs/heads/main", "--tags")
    remote_head = command("git", "rev-parse", "FETCH_HEAD")
    base = command("git", "merge-base", remote_head, "HEAD", allowed=(0, 1))
    if base != remote_head:
        raise RuntimeError("Remote main has changes you do not have. Pull/rebase before releasing.")
    previous = f"v{current}"
    has_base = command("git", "tag", "--list", previous)
    commits = command("git", "log", "--no-merges", "--format=%h%x09%s",
                      f"{previous}..HEAD" if has_base else "HEAD")
    if not commits:
        raise RuntimeError("There are no new commits since the current release.")
    changes = []
    for line in commits.splitlines():
        sha, subject = line.split("\t", 1)
        subject = re.sub(r"([\\`*_\[\]])", r"\\\1", html.escape(subject))
        changes.append(f"- {subject} (`{sha}`)")
    changelog = (ROOT / "CHANGELOG.md").read_text()
    entry = re.search(rf"^## \[{re.escape(requested)}\][^\n]*\n(.*?)(?=^## |\Z)", changelog, re.M | re.S)
    if entry and not entry[1].strip():
        raise ValueError(f"The prepared CHANGELOG.md entry for {requested} must be nonempty.")
    if not entry:
        heading, separator, remainder = changelog.partition("\n")
        changelog = (heading + separator + f"\n## [{requested}] - {date.today().isoformat()}\n\n"
                     "### Changes / 变更\n\n" + "\n".join(changes) + "\n" + remainder)
    command("git", "var", "GIT_AUTHOR_IDENT")
    command("git", "var", "GIT_COMMITTER_IDENT")
    print(f"Ready: {current} → {requested} · {remote}/main", flush=True)
    return requested, tag, remote, remote_url, changelog


def start():
    requested, tag, remote, remote_url, changelog = preflight()
    version.set_version(requested)
    (ROOT / "CHANGELOG.md").write_text(changelog)
    release_notes(tag)
    command("git", "add", "--", "Resources/Info.plist", "CHANGELOG.md")
    command("git", "commit", "-m", f"Release {tag}")
    command("git", "tag", "-a", tag, "-m", f"Marknote {requested}")
    push = ("git", "push", "--atomic", remote, "HEAD:refs/heads/main", f"refs/tags/{tag}")
    try:
        command(*push, capture=False)
    except RuntimeError as error:
        raise RuntimeError(f"Commit and tag are kept locally. After fixing the push error, retry:\n"
                           f"  {shlex.join(push)}\n"
                           "Do not run make release again to retry this version.") from error
    print(f"Pushed {tag}. GitHub Actions will build, test, package, attest, and publish.")
    try:
        repo = repository(remote_url)
    except ValueError:
        return  # Local Git remotes are useful for exercising the release transaction.
    print(f"Follow progress: https://github.com/{repo}/actions/workflows/release.yml\n"
          f"Release (available after CI): https://github.com/{repo}/releases/tag/{tag}")


def verify_archive(archive, release_version, arch):
    """Accept standard ZIPs and the UTF-8 paths emitted by Apple's ditto."""
    version.validate(release_version)
    archive = Path(archive)
    cpu_type = {"arm64": 0x0100000C, "x86_64": 0x01000007}[arch]
    checksum = archive.with_suffix(".zip.sha256")
    if not archive.is_file() or not checksum.is_file():
        raise ValueError(f"Missing release asset or checksum: {archive.name}")
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    expected = f"{digest}  {archive.name}"
    if checksum.read_text().strip() != expected:
        raise ValueError(f"Checksum mismatch: {archive.name}")
    with zipfile.ZipFile(archive) as bundle:
        # ditto stores UTF-8 bytes without setting ZIP's UTF-8 flag. Decode these
        # paths explicitly so Ubuntu can inspect a bundle named 墨笺.app as well.
        members = {(item.filename if item.flag_bits & 0x800 else item.filename.encode("cp437").decode("utf-8")): item
                   for item in bundle.infolist()}
        prefix = "墨笺.app/Contents/"
        info = plistlib.loads(bundle.read(members[prefix + "Info.plist"]))
        if info.get("CFBundleShortVersionString") != release_version or info.get("CFBundleIdentifier") != "net.marknote.editor":
            raise ValueError(f"Wrong application/version in {archive.name}")
        with bundle.open(members[prefix + "MacOS/Marknote"]) as executable:
            header = executable.read(8)
        if len(header) != 8 or struct.unpack("<II", header) != (0xFEEDFACF, cpu_type):
            raise ValueError(f"Wrong executable architecture in {archive.name}")
        if bundle.testzip() is not None:
            raise ValueError(f"Corrupt archive: {archive.name}")
    return expected


def verify_installer(installer):
    installer = Path(installer)
    checksum = installer.with_suffix(".dmg.sha256")
    if not installer.is_file() or not checksum.is_file():
        raise ValueError(f"Missing installer or checksum: {installer.name}")
    expected = f"{hashlib.sha256(installer.read_bytes()).hexdigest()}  {installer.name}"
    if checksum.read_text().strip() != expected:
        raise ValueError(f"Checksum mismatch: {installer.name}")
    # UDIF disk images have a 512-byte trailer beginning with 'koly'. The macOS
    # packaging job additionally mounts the image and verifies its app signature.
    with installer.open("rb") as stream:
        if installer.stat().st_size < 512:
            raise ValueError(f"Invalid DMG: {installer.name}")
        stream.seek(-512, 2)
        if stream.read(4) != b"koly":
            raise ValueError(f"Invalid DMG: {installer.name}")
    return expected


def verify_assets(directory, release_version):
    """Check digests, bundled versions, and actual Mach-O CPU types before publishing."""
    directory = Path(directory)
    assets, checksums = [], []
    for arch in ("arm64", "x86_64"):
        archive = directory / f"Marknote-{release_version}-macos-{arch}.zip"
        expected = verify_archive(archive, release_version, arch)
        assets.append(archive)
        checksums.append(expected)
    for arch in ("arm64", "x86_64"):
        installer = directory / f"Marknote-{release_version}-macos-{arch}.dmg"
        checksums.append(verify_installer(installer))
        assets.append(installer)
    manifest = directory / "SHA256SUMS"
    manifest.write_text("\n".join(checksums) + "\n")
    return assets + [manifest]


def release_notes(tag):
    current = version.check_tag(tag)
    changelog = (ROOT / "CHANGELOG.md").read_text()
    match = re.search(rf"^## \[{re.escape(current)}\][^\n]*\n(.*?)(?=^## |\Z)", changelog, re.M | re.S)
    if not match or not match[1].strip():
        raise ValueError(f"Add a nonempty ## [{current}] entry to CHANGELOG.md before releasing.")
    return match[1].strip() + "\n\n" + (
        "### Downloads / 下载\n\n"
        "- **Apple Silicon (M series):** `macos-arm64.dmg` (installer), `.zip` (portable archive)\n"
        "- **Intel:** `macos-x86_64.dmg` (installer), `.zip` (portable archive)\n"
        "- **macOS 13+** · Verify downloads with `SHA256SUMS`.\n\n"
        "Open the DMG and drag 墨笺.app to Applications, then eject the installer. / 打开 DMG，将 墨笺.app 拖入应用程序，然后推出安装磁盘。\n\n"
        "In Marknote, choose **Set as Default Markdown Editor…** to open .md files by double-clicking. / 在墨笺菜单选择“设为默认 Markdown 编辑器…”即可通过双击打开 .md 文件。\n\n"
        "CI builds use ad-hoc signatures and are not Apple-notarized. / CI 构建使用临时签名，未经 Apple 公证。\n"
    )


def publish(tag, directory):
    repo = os.environ.get("GH_REPO", "")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repo):
        raise ValueError("GH_REPO must be OWNER/REPO.")
    assets = verify_assets(directory, version.check_tag(tag))
    notes = release_notes(tag)
    existing = release_state(repo, tag)
    if existing and not existing["isDraft"]:
        raise RuntimeError(f"{tag} is already public; refusing to replace published assets.")
    with tempfile.TemporaryDirectory(prefix="marknote-release-") as temporary:
        notes_file = Path(temporary) / "notes.md"
        notes_file.write_text(notes)
        if not existing:
            command("gh", "release", "create", tag, "--repo", repo, "--verify-tag", "--draft",
                    "--title", f"Marknote {tag}", "--notes-file", str(notes_file))
        else:
            command("gh", "release", "edit", tag, "--repo", repo, "--notes-file", str(notes_file))
        # Only drafts can reach this point. A failed upload leaves the draft unpublished.
        command("gh", "release", "upload", tag, *[str(asset) for asset in assets], "--repo", repo, "--clobber")
        command("gh", "release", "edit", tag, "--repo", repo, "--draft=false", "--latest")
    print(command("gh", "release", "view", tag, "--repo", repo, "--json", "url", "--jq", ".url"))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["check", "start", "prepare", "publish", "verify"])
    parser.add_argument("--tag", default="")
    parser.add_argument("--artifacts", type=Path, default=ROOT / "dist/releases")
    parser.add_argument("--archive", type=Path)
    parser.add_argument("--architecture", choices=["arm64", "x86_64"])
    args = parser.parse_args()
    try:
        if args.command == "check":
            preflight()
        elif args.command == "start":
            start()
        elif args.command == "prepare":
            assets = verify_assets(args.artifacts, version.check_tag(args.tag))
            print(f"Verified {len(assets) - 1} release assets and wrote {assets[-1].name}.")
        elif args.command == "publish":
            publish(args.tag, args.artifacts)
        else:
            if not args.archive or not args.architecture:
                raise ValueError("verify requires --archive and --architecture")
            print("Verified: " + verify_archive(args.archive, version.current(), args.architecture))
    except (RuntimeError, ValueError, OSError, KeyError, zipfile.BadZipFile) as error:
        sys.exit(f"Release stopped: {error}")
