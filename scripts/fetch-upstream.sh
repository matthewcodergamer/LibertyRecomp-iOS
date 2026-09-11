#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOCK_FILE="${ROOT_DIR}/UPSTREAM.lock"
DESTINATION="${ROOT_DIR}/.cache/LibertyRecomp"
RECURSIVE=0

usage() {
    cat <<'EOF'
Usage: scripts/fetch-upstream.sh [--destination PATH] [--recursive]

Fetch the exact LibertyRecomp commit recorded in UPSTREAM.lock.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --destination)
            [[ $# -ge 2 ]] || { echo "error: --destination requires a path" >&2; exit 2; }
            DESTINATION="$2"
            shift 2
            ;;
        --recursive)
            RECURSIVE=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "error: unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

[[ -f "${LOCK_FILE}" ]] || { echo "error: missing ${LOCK_FILE}" >&2; exit 2; }

# Keep this compatible with the Bash 3.2 that ships on many macOS/Xcode hosts;
# readarray/mapfile were added in later Bash versions.
UPSTREAM_REPO="$(python3 - "${LOCK_FILE}" <<'PY'
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    print(json.load(f)["repository"])
PY
)"
UPSTREAM_COMMIT="$(python3 - "${LOCK_FILE}" <<'PY'
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    print(json.load(f)["commit"])
PY
)"

[[ -n "${UPSTREAM_REPO}" ]] || { echo "error: upstream repository is empty in ${LOCK_FILE}" >&2; exit 2; }
[[ "${UPSTREAM_COMMIT}" =~ ^[0-9a-fA-F]{40}$ ]] || { echo "error: upstream commit in ${LOCK_FILE} is not a 40-character Git SHA" >&2; exit 2; }

mkdir -p "$(dirname "${DESTINATION}")"

if [[ ! -d "${DESTINATION}/.git" ]]; then
    rm -rf "${DESTINATION}"
    git clone --filter=blob:none --no-checkout "${UPSTREAM_REPO}" "${DESTINATION}"
else
    EXISTING_REMOTE="$(git -C "${DESTINATION}" remote get-url origin 2>/dev/null || true)"
    if [[ "${EXISTING_REMOTE}" != "${UPSTREAM_REPO}" ]]; then
        echo "error: ${DESTINATION} points at ${EXISTING_REMOTE}, expected ${UPSTREAM_REPO}" >&2
        exit 3
    fi
fi

git -C "${DESTINATION}" fetch --depth=1 origin "${UPSTREAM_COMMIT}"
git -C "${DESTINATION}" checkout --detach --force FETCH_HEAD

ACTUAL_COMMIT="$(git -C "${DESTINATION}" rev-parse HEAD)"
if [[ "${ACTUAL_COMMIT}" != "${UPSTREAM_COMMIT}" ]]; then
    echo "error: checkout mismatch: expected ${UPSTREAM_COMMIT}, got ${ACTUAL_COMMIT}" >&2
    exit 4
fi

if [[ "${RECURSIVE}" -eq 1 ]]; then
    git -C "${DESTINATION}" submodule sync --recursive
    git -C "${DESTINATION}" submodule update --init --recursive --depth 1
fi

echo "LibertyRecomp upstream ready:"
echo "  repository: ${UPSTREAM_REPO}"
echo "  commit:     ${ACTUAL_COMMIT}"
echo "  path:       ${DESTINATION}"
