#!/usr/bin/env python3
"""Fail CI if tracked files look like private game payloads or signing secrets."""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

FORBIDDEN_SUFFIXES = {".xex", ".rpf", ".iso", ".xiso", ".stfs", ".live", ".con", ".ipa", ".mobileprovision", ".p12", ".pfx", ".cer", ".der"}
FORBIDDEN_BASENAMES = {"aes_key.bin", "default.xex"}
FORBIDDEN_PATH_PARTS = {"local_game_payload", "private_game", "game_payload", "DerivedData"}
SECRET_MARKERS = ("-----BEGIN PRIVATE KEY-----", "-----BEGIN ENCRYPTED PRIVATE KEY-----", "-----BEGIN OPENSSH PRIVATE KEY-----")


def tracked_files(root: Path) -> list[Path]:
    proc = subprocess.run(["git", "-C", str(root), "ls-files", "-z"], check=True, stdout=subprocess.PIPE)
    return [root / p.decode("utf-8") for p in proc.stdout.split(b"\0") if p]


def find_violations(root: Path, files: list[Path] | None = None) -> list[str]:
    root = root.resolve()
    files = tracked_files(root) if files is None else files
    violations: list[str] = []
    marker_definition_paths = {Path("scripts/check-prohibited-assets.py"), Path("tests/test_prohibited_assets.py")}

    for file_path in files:
        try:
            rel = file_path.resolve().relative_to(root)
        except ValueError:
            violations.append(f"outside repository: {file_path}")
            continue

        lower_name = rel.name.lower()
        lower_suffix = rel.suffix.lower()
        if lower_name in FORBIDDEN_BASENAMES or lower_suffix in FORBIDDEN_SUFFIXES:
            violations.append(f"forbidden tracked payload/signing file: {rel.as_posix()}")
            continue
        if any(part in FORBIDDEN_PATH_PARTS for part in rel.parts):
            violations.append(f"forbidden tracked private/build directory: {rel.as_posix()}")
            continue
        if rel in marker_definition_paths:
            continue
        try:
            if file_path.stat().st_size <= 2 * 1024 * 1024:
                text = file_path.read_text(encoding="utf-8", errors="ignore")
                if any(marker in text for marker in SECRET_MARKERS):
                    violations.append(f"private-key material detected: {rel.as_posix()}")
        except (OSError, UnicodeError):
            pass

    return sorted(set(violations))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args(argv)
    violations = find_violations(args.root)
    if violations:
        print("Prohibited tracked files detected:", file=sys.stderr)
        for violation in violations:
            print(f" - {violation}", file=sys.stderr)
        return 1
    print("No prohibited game payloads or signing secrets are tracked.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
