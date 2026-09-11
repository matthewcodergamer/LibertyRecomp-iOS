#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DESTINATION="${1:-${RUNNER_TEMP:-${ROOT_DIR}/.cache}/LibertyRecomp-reference}"

"${SCRIPT_DIR}/fetch-upstream.sh" --destination "${DESTINATION}"

python3 - "${ROOT_DIR}/UPSTREAM.lock" "${DESTINATION}" <<'PY'
import json, pathlib, subprocess, sys

lock = json.loads(pathlib.Path(sys.argv[1]).read_text())
upstream = pathlib.Path(sys.argv[2])
actual = subprocess.check_output(["git", "-C", str(upstream), "rev-parse", "HEAD"], text=True).strip()
if actual != lock["commit"]:
    raise SystemExit(f"upstream pin mismatch: {actual} != {lock['commit']}")

required = ["CMakeLists.txt", "CMakePresets.json", "toolchains/ios.cmake", "LibertyRecomp/CMakeLists.txt", "glue/CMakeLists.txt"]
missing = [p for p in required if not (upstream / p).exists()]
if missing:
    raise SystemExit("missing pinned upstream build files: " + ", ".join(missing))

print("Pinned macOS reference source verified at", actual)
print("A complete upstream macOS build is intentionally a separate device/developer gate")
print("because the upstream reference has a large nested dependency graph.")
PY
