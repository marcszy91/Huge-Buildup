#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
cd "${REPO_ROOT}"

targets=("scripts" "scenes")

if [[ -x ".venv/bin/python" ]]; then
  .venv/bin/python -m gdlint "${targets[@]}"
  exit $?
fi

if command -v gdlint >/dev/null 2>&1; then
  gdlint "${targets[@]}"
  exit $?
fi

echo "gdlint not found. Install with 'python -m pip install -r requirements-dev.txt' (venv) or 'pipx install gdtoolkit'." >&2
exit 1
