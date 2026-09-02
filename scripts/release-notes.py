#!/usr/bin/env python3
"""Extract the exact tagged version's notes; refuse an undocumented release."""
import re
import sys
from pathlib import Path

if len(sys.argv) != 2 or not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", sys.argv[1]):
    sys.exit("usage: release-notes.py vMAJOR.MINOR.PATCH")
version = sys.argv[1][1:]
changelog = (Path(__file__).resolve().parent.parent / "CHANGELOG.md").read_text()
match = re.search(r"^## " + re.escape(version) + r"(?: [^\n]*)?\n(.*?)(?=^## |\Z)", changelog, re.M | re.S)
if not match or not match[1].strip():
    sys.exit(f"No changelog entry for {version}")
print(match[1].strip())
print("\nRequires macOS 14 or newer. This archive contains an Apple Silicon build.")
print("\nDownload Upkeep.zip and verify it using Upkeep.zip.sha256 before installation.")
