#!/usr/bin/env python3
"""Tag a clean commit, or publish verified CI assets without exposing partial releases."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import time
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
    for tool in ("git", "gh"):
        if not shutil.which(tool):
            raise RuntimeError(f"Install {tool} before releasing (see docs/en/releasing.md).")
    current = version.current()
    requested = os.environ.get("VERSION") or current
    version.check_tag(f"v{requested}")
    tag = f"v{current}"
    revision = command("git", "rev-parse", "--verify", "HEAD", allowed=(0, 128))
    if not revision:
        raise RuntimeError("Create an initial commit and push the project to GitHub before releasing.")
    if command("git", "status", "--porcelain"):
        raise RuntimeError("Commit all changes before releasing. The working tree must be clean.")
    remote = os.environ.get("REMOTE") or "origin"
    if remote.startswith("-"):
        raise ValueError("Invalid Git remote name.")
    repo = repository(command("git", "remote", "get-url", remote))
    if repository(command("git", "remote", "get-url", "--push", remote)) != repo:
        raise RuntimeError("Fetch and push URLs must refer to the same GitHub repository.")
    command("gh", "auth", "status", "--hostname", "github.com")
    if command("gh", "api", f"repos/{repo}/commits/{revision}", "--jq", ".sha") != revision:
        raise RuntimeError("Push this commit to the GitHub repository before releasing.")
    # The workflow must be registered on GitHub before a tag is pushed.
    workflow = json.loads(command("gh", "api", f"repos/{repo}/actions/workflows/release.yml"))
    if workflow.get("state") != "active":
        raise RuntimeError("Enable Release Actions on the default branch before releasing.")
    existing = release_state(repo, tag)
    if existing and not existing["isDraft"]:
        raise RuntimeError(f"{tag} is already published. Choose a new version; releases are never overwritten.")
    local_revision = command("git", "rev-parse", "--verify", f"refs/tags/{tag}^{{commit}}", allowed=(0, 128))
    if local_revision and local_revision != revision:
        raise RuntimeError(f"Local tag {tag} points to another commit; it will not be moved.")
    refs = command("git", "ls-remote", "--tags", remote, f"refs/tags/{tag}", f"refs/tags/{tag}^{{}}")
    lines = [line.split() for line in refs.splitlines()]
    target = next((sha for sha, name in lines if name.endswith("^{}")), lines[0][0] if lines else "")
    if target and target != revision:
        raise RuntimeError(f"Remote tag {tag} points to another commit; it will not be moved.")
    release_notes(tag)  # Fail before pushing when the changelog entry is missing.
    print(f"Ready: {repo} · {tag} · {revision[:12]}", flush=True)
    return repo, remote, tag, revision, bool(local_revision), bool(target)


def start():
    repo, remote, tag, revision, local_exists, remote_exists = preflight()
    if not remote_exists:
        if not local_exists:
            command("git", "tag", "-a", tag, "-m", f"Marknote {tag}", revision)
        command("git", "push", remote, f"refs/tags/{tag}:refs/tags/{tag}", capture=False)
    print(f"Waiting for https://github.com/{repo}/actions/workflows/release.yml", flush=True)
    for _ in range(30):
        runs = json.loads(command("gh", "run", "list", "--repo", repo, "--workflow", "release.yml",
                                 "--branch", tag, "--commit", revision, "--event", "push", "--json", "databaseId"))
        if runs:
            run_id = str(runs[0]["databaseId"])
            print(f"Release run: https://github.com/{repo}/actions/runs/{run_id}", flush=True)
            command("gh", "run", "watch", run_id, "--repo", repo, "--exit-status", capture=False)
            print(command("gh", "release", "view", tag, "--repo", repo, "--json", "url", "--jq", ".url"))
            return
        time.sleep(3)
    raise RuntimeError(f"No Release run found for {tag}. Check Actions permissions. The tag is preserved; "
                       f"start Release manually with tag={tag} after resolving the issue.")


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


def verify_assets(directory, release_version):
    """Check digests, bundled versions, and actual Mach-O CPU types before publishing."""
    directory = Path(directory)
    assets, checksums = [], []
    for arch in ("arm64", "x86_64"):
        archive = directory / f"Marknote-{release_version}-macos-{arch}.zip"
        expected = verify_archive(archive, release_version, arch)
        assets.append(archive)
        checksums.append(expected)
    manifest = directory / "SHA256SUMS.txt"
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
        "- **Apple Silicon (M series):** `macos-arm64.zip`\n"
        "- **Intel:** `macos-x86_64.zip`\n"
        "- **macOS 13+** · Verify downloads with `SHA256SUMS.txt`.\n\n"
        "Extract the ZIP and move 墨笺.app to Applications. / 解压后将 墨笺.app 拖入应用程序。\n\n"
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
    parser.add_argument("command", choices=["check", "start", "publish", "verify"])
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
        elif args.command == "publish":
            publish(args.tag, args.artifacts)
        else:
            if not args.archive or not args.architecture:
                raise ValueError("verify requires --archive and --architecture")
            print("Verified: " + verify_archive(args.archive, version.current(), args.architecture))
    except (RuntimeError, ValueError, OSError, KeyError, zipfile.BadZipFile) as error:
        sys.exit(f"Release stopped: {error}")
