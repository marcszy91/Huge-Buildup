#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
cd "${REPO_ROOT}"

targets=("scripts" "scenes")

if [[ -x ".venv/bin/python" ]]; then
  .venv/bin/python -m gdformat "${targets[@]}"
  exit $?
fi

if command -v gdformat >/dev/null 2>&1; then
  gdformat "${targets[@]}"
  exit $?
fi

echo "gdformat not found. Install with 'python -m pip install -r requirements-dev.txt' (venv) or 'pipx install gdtoolkit'." >&2
exit 1
