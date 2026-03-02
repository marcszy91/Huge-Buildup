#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PROJECT_FILE = ROOT / "project.godot"
VERSION_FILE = ROOT / "VERSION"


def update_project_version(version: str) -> None:
	text = PROJECT_FILE.read_text(encoding="utf-8")
	lines = text.splitlines()
	version_line = f'config/version="{version}"'
	in_application = False
	inserted = False
	for idx, line in enumerate(lines):
		if line.strip() == "[application]":
			in_application = True
			continue
		if in_application and line.startswith("[") and line.endswith("]"):
			lines.insert(idx, version_line)
			inserted = True
			break
		if in_application and line.startswith("config/version="):
			lines[idx] = version_line
			inserted = True
			break
	if not inserted:
		lines.append("")
		lines.append("[application]")
		lines.append(version_line)
	PROJECT_FILE.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
	if len(sys.argv) != 2:
		print("Usage: apply_version.py <version>", file=sys.stderr)
		return 1

	version = sys.argv[1].strip()
	if not version:
		print("Version must not be empty.", file=sys.stderr)
		return 1

	update_project_version(version)
	VERSION_FILE.write_text(version + "\n", encoding="utf-8")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
