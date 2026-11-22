#!/usr/bin/env python3
"""Print a version's notes from CHANGELOG.md in the working tree; refuse an
undocumented release. Pass --not-notarized for a locally signed build."""
import re
import sys
from pathlib import Path

args = sys.argv[1:]
not_notarized = "--not-notarized" in args
if not_notarized:
    args.remove("--not-notarized")
if len(args) != 1 or not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", args[0]):
    sys.exit("usage: release-notes.py vMAJOR.MINOR.PATCH [--not-notarized]")
version = args[0][1:]
changelog = (Path(__file__).resolve().parent.parent / "CHANGELOG.md").read_text()
match = re.search(r"^## " + re.escape(version) + r"(?: [^\n]*)?\n(.*?)(?=^## |\Z)", changelog, re.M | re.S)
if not match or not match[1].strip():
    sys.exit(f"No changelog entry for {version}")
print(match[1].strip())
print("\nRequires macOS 14 or newer. This archive contains an Apple Silicon build.")
print("\nDownload Upkeep.zip and verify it using Upkeep.zip.sha256 before installation.")
if not_notarized:
    print("\nThis build is signed locally and not notarized by Apple, so macOS blocks the")
    print("first launch. After the checksum passes, Control-click Upkeep.app and choose Open.")
