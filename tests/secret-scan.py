#!/usr/bin/env python3
"""Fail CI when common high-confidence secret formats are committed."""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
THIS_FILE = pathlib.Path(__file__).resolve()
EXCLUDED_PARTS = {".git", ".venv", "node_modules"}
PRIVATE_KEY_PREFIX = "-----BEGIN "
PRIVATE_KEY_SUFFIX = " PRIVATE KEY-----"
PATTERNS = {
    "private key": re.compile(re.escape(PRIVATE_KEY_PREFIX) + r"(?:RSA |EC |OPENSSH )?" + re.escape(PRIVATE_KEY_SUFFIX)),
    "GitHub token": re.compile(r"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}\b"),
    "AWS access key": re.compile(r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"),
    "Slack token": re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{20,}\b"),
}
TEXT_SUFFIXES = {".ps1", ".psd1", ".psm1", ".sh", ".json", ".yml", ".yaml", ".md", ".txt", ".py"}

findings: list[str] = []
for path in ROOT.rglob("*"):
    if not path.is_file() or path.resolve() == THIS_FILE or path.suffix.lower() not in TEXT_SUFFIXES:
        continue
    if any(part in EXCLUDED_PARTS for part in path.parts):
        continue
    text = path.read_text(encoding="utf-8", errors="ignore")
    for name, pattern in PATTERNS.items():
        if pattern.search(text):
            findings.append(f"{path.relative_to(ROOT)}: possible {name}")

if findings:
    print("Potential secrets found:", file=sys.stderr)
    print("\n".join(findings), file=sys.stderr)
    raise SystemExit(1)

print("Secret-format scan passed.")
