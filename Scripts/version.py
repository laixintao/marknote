#!/usr/bin/env python3
"""Keep the app, tag, and archive versions in agreement. No external dependencies."""
import argparse
from pathlib import Path
import plistlib
import re

ROOT = Path(__file__).resolve().parent.parent
INFO = ROOT / "Resources/Info.plist"
VERSION_PATTERN = r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)"


def validate(value):
    if not re.fullmatch(VERSION_PATTERN, value):
        raise ValueError("Use a stable version such as 1.2.0 (no v prefix).")
    return value


def current():
    with INFO.open("rb") as stream:
        return validate(plistlib.load(stream)["CFBundleShortVersionString"])


def check_tag(tag):
    if not tag.startswith("v") or validate(tag[1:]) != current():
        raise ValueError(f"Tag {tag!r} must match Info.plist version v{current()}.")
    return tag[1:]


def set_version(value):
    validate(value)
    with INFO.open("rb") as stream:
        info = plistlib.load(stream)
    if info["CFBundleShortVersionString"] == value:
        return
    info["CFBundleShortVersionString"] = value
    info["CFBundleVersion"] = str(int(info["CFBundleVersion"]) + 1)
    with INFO.open("wb") as stream:
        plistlib.dump(info, stream, sort_keys=False)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["show", "check", "set"], nargs="?", default="show")
    parser.add_argument("value", nargs="?", default="")
    args = parser.parse_args()
    try:
        if args.command == "set":
            set_version(args.value)
        elif args.command == "check":
            check_tag(args.value)
        print(current())
    except (ValueError, KeyError) as error:
        parser.exit(1, f"Version error: {error}\n")
