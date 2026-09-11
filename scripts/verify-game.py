#!/usr/bin/env python3
"""Validate a private extracted GTA IV Xbox 360 game folder.

This tool never copies, modifies, uploads, or redistributes game data.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import sys
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Any

EXIT_OK = 0
EXIT_MISSING = 2
EXIT_UNSUPPORTED = 3
EXIT_STORAGE = 4
EXIT_CONFIG = 5


@dataclass
class VerificationResult:
    ok: bool
    supported: bool
    status: str
    game_root: str
    executable_sha256: str | None
    matched_revision_id: str | None
    total_bytes: int
    available_bytes: int | None
    missing_files: list[str]
    messages: list[str]


def sha256_file(path: Path, chunk_size: int = 1024 * 1024) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(chunk_size), b""):
            digest.update(chunk)
    return digest.hexdigest()


def folder_size(path: Path) -> int:
    total = 0
    for current_root, _, filenames in os.walk(path):
        base = Path(current_root)
        for name in filenames:
            file_path = base / name
            try:
                total += file_path.stat().st_size
            except FileNotFoundError:
                pass
    return total


def load_manifest(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"cannot read manifest {path}: {exc}") from exc

    if data.get("schemaVersion") != 1:
        raise ValueError("unsupported game manifest schemaVersion")
    if not isinstance(data.get("requiredFiles"), list):
        raise ValueError("manifest requiredFiles must be a list")
    if not isinstance(data.get("supportedRevisions"), list):
        raise ValueError("manifest supportedRevisions must be a list")
    return data


def verify_game(game_root: Path, manifest: dict[str, Any], *, destination: Path | None = None, allow_unpinned: bool = False) -> tuple[VerificationResult, int]:
    game_root = game_root.expanduser().resolve()
    messages: list[str] = []

    if not game_root.is_dir():
        result = VerificationResult(False, False, "missing-game-root", str(game_root), None, None, 0, None, [], [f"Game root does not exist or is not a directory: {game_root}"])
        return result, EXIT_MISSING

    required_paths: list[str] = []
    for entry in manifest["requiredFiles"]:
        if not isinstance(entry, dict) or not isinstance(entry.get("path"), str):
            raise ValueError("each requiredFiles entry must contain a string path")
        rel = entry["path"].replace("\\", "/").lstrip("/")
        if ".." in Path(rel).parts:
            raise ValueError(f"manifest contains unsafe relative path: {rel}")
        required_paths.append(rel)

    missing = [rel for rel in required_paths if not (game_root / rel).is_file()]
    if missing:
        result = VerificationResult(False, False, "missing-required-files", str(game_root), None, None, folder_size(game_root), None, missing, ["Required game files are missing."])
        return result, EXIT_MISSING

    xex_path = game_root / "default.xex"
    xex_hash = sha256_file(xex_path)

    matched_revision: dict[str, Any] | None = None
    for revision in manifest["supportedRevisions"]:
        if not isinstance(revision, dict):
            raise ValueError("supportedRevisions entries must be objects")
        expected = str(revision.get("xexSha256", "")).strip().lower()
        if len(expected) == 64 and expected == xex_hash.lower():
            matched_revision = revision
            break

    supported = matched_revision is not None
    if supported:
        messages.append(f"Supported executable revision: {matched_revision.get('id', matched_revision.get('name', 'unnamed'))}")
    elif manifest["supportedRevisions"]:
        messages.append("Executable SHA-256 does not match any supported static-recomp revision.")
    else:
        messages.append("No supported executable hash is configured yet; this repository refuses to invent one.")

    total = folder_size(game_root)
    available: int | None = None
    storage_ok = True
    if destination is not None:
        destination = destination.expanduser().resolve()
        probe = destination if destination.exists() else destination.parent
        while not probe.exists() and probe != probe.parent:
            probe = probe.parent
        usage = shutil.disk_usage(probe)
        available = usage.free
        required_free = total + (256 * 1024 * 1024)
        storage_ok = available >= required_free
        if not storage_ok:
            messages.append(f"Insufficient free storage at {probe}: need at least {required_free} bytes, found {available}.")

    accepted_revision = supported or allow_unpinned
    if not storage_ok:
        code = EXIT_STORAGE
        status = "insufficient-storage"
    elif not accepted_revision:
        code = EXIT_UNSUPPORTED
        status = "unsupported-executable"
    else:
        code = EXIT_OK
        status = "supported" if supported else "unverified-development-mode"
        if allow_unpinned and not supported:
            messages.append("Unpinned executable accepted only because --allow-unpinned was supplied.")

    result = VerificationResult(
        ok=(code == EXIT_OK),
        supported=supported,
        status=status,
        game_root=str(game_root),
        executable_sha256=xex_hash,
        matched_revision_id=(str(matched_revision.get("id")) if matched_revision is not None and matched_revision.get("id") is not None else None),
        total_bytes=total,
        available_bytes=available,
        missing_files=[],
        messages=messages,
    )
    return result, code


def build_parser() -> argparse.ArgumentParser:
    default_manifest = Path(__file__).resolve().parents[1] / "config" / "game_versions" / "gta4_x360_supported.json"
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("game_root", type=Path, help="Extracted private Xbox 360 game folder")
    parser.add_argument("--manifest", type=Path, default=default_manifest, help=f"Compatibility manifest (default: {default_manifest})")
    parser.add_argument("--destination", type=Path, help="Optional destination volume used for import free-space preflight")
    parser.add_argument("--allow-unpinned", action="store_true", help="Development-only: accept an unknown XEX after reporting its SHA-256")
    parser.add_argument("--dry-run", action="store_true", help="Explicitly request validation only. This tool never copies files.")
    parser.add_argument("--json", action="store_true", help="Emit machine-readable JSON")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        manifest = load_manifest(args.manifest)
        result, code = verify_game(args.game_root, manifest, destination=args.destination, allow_unpinned=args.allow_unpinned)
    except ValueError as exc:
        if args.json:
            print(json.dumps({"ok": False, "status": "manifest-error", "error": str(exc)}))
        else:
            print(f"Manifest error: {exc}", file=sys.stderr)
        return EXIT_CONFIG

    if args.json:
        print(json.dumps(asdict(result), indent=2, sort_keys=True))
    else:
        print("LIBERTY RECOMPILED — GAME VERIFICATION")
        print(f"Game root: {result.game_root}")
        for rel in result.missing_files:
            print(f"✗ {rel}")
        if result.executable_sha256:
            print(f"default.xex SHA-256: {result.executable_sha256}")
        print(f"Content bytes: {result.total_bytes}")
        if result.available_bytes is not None:
            print(f"Available destination bytes: {result.available_bytes}")
        for message in result.messages:
            print(message)
        print(f"Result: {result.status}")

    return code


if __name__ == "__main__":
    raise SystemExit(main())
