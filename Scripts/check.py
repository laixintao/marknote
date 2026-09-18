#!/usr/bin/env python3
"""Offline repository checks; suitable for a fresh macOS or Linux checkout."""
from pathlib import Path
import re
import shutil
import subprocess
from urllib.parse import unquote, urlsplit

import version

ROOT = Path(__file__).resolve().parent.parent


def main():
    version.current()
    scripts = sorted((ROOT / "Scripts").glob("*.sh"))
    for script in scripts:
        subprocess.run(["bash", "-n", str(script)], check=True)
    if shutil.which("shellcheck"):
        subprocess.run(["shellcheck", *map(str, scripts)], check=True)
    if shutil.which("actionlint"):
        subprocess.run(["actionlint"], cwd=ROOT, check=True)
    documents = list(ROOT.glob("*.md")) + list((ROOT / "docs").rglob("*.md"))
    checked = 0
    for document in documents:
        text = re.sub(r"```.*?```", "", document.read_text(), flags=re.S)
        for link in re.findall(r"!?\[[^\]]*\]\(([^)]+)\)", text):
            target = urlsplit(link.split(' "')[0].strip("<>"))
            if target.scheme or target.netloc or not target.path:
                continue
            resolved = (document.parent / unquote(target.path)).resolve()
            if not resolved.is_relative_to(ROOT) or not resolved.exists():
                raise ValueError(f"Broken local link in {document.relative_to(ROOT)}: {link}")
            checked += 1
    for screenshot in (ROOT / "docs/images").glob("*.png"):
        if screenshot.read_bytes()[:8] != b"\x89PNG\r\n\x1a\n":
            raise ValueError(f"Invalid PNG: {screenshot}")
    print(f"Repository checks passed: {len(scripts)} shell scripts, {checked} local documentation links.")


if __name__ == "__main__":
    main()
