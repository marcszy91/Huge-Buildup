#!/usr/bin/env python3
from __future__ import annotations

import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PROJECT_FILE = ROOT / "project.godot"
CHANGELOG_FILE = ROOT / "CHANGELOG.md"
VERSION_FILE = ROOT / "VERSION"

VERSION_RE = re.compile(r"^v?(\d+)\.(\d+)\.(\d+)(?:-alpha\.(\d+))?$")
CONVENTIONAL_RE = re.compile(r"^(?P<type>[a-z]+)(?:\([^)]+\))?(?P<breaking>!)?:\s+(?P<msg>.+)$")


@dataclass(frozen=True)
class Version:
	major: int
	minor: int
	patch: int
	alpha: int | None = None

	def stable_tuple(self) -> tuple[int, int, int]:
		return (self.major, self.minor, self.patch)

	def sortable(self) -> tuple[int, int, int, int, int]:
		return (
			self.major,
			self.minor,
			self.patch,
			0 if self.alpha is None else -1,
			self.alpha or 0,
		)

	def stable_string(self) -> str:
		return f"{self.major}.{self.minor}.{self.patch}"

	def tag(self) -> str:
		if self.alpha is None:
			return f"v{self.stable_string()}"
		return f"v{self.stable_string()}-alpha.{self.alpha}"

	def version_string(self) -> str:
		if self.alpha is None:
			return self.stable_string()
		return f"{self.stable_string()}-alpha.{self.alpha}"


@dataclass(frozen=True)
class Commit:
	sha: str
	subject: str
	body: str


def git(*args: str, check: bool = True) -> str:
	result = subprocess.run(
		["git", *args],
		cwd=ROOT,
		text=True,
		capture_output=True,
		check=False,
	)
	if check and result.returncode != 0:
		raise RuntimeError(result.stderr.strip() or result.stdout.strip())
	return result.stdout.strip()


def parse_version(tag: str) -> Version | None:
	match = VERSION_RE.match(tag.strip())
	if not match:
		return None
	major, minor, patch, alpha = match.groups()
	return Version(int(major), int(minor), int(patch), int(alpha) if alpha else None)


def get_reachable_tags() -> list[str]:
	output = git("tag", "--merged", "HEAD", check=False)
	if not output:
		return []
	return [line.strip() for line in output.splitlines() if line.strip()]


def latest_stable_tag(tags: list[str]) -> tuple[str | None, Version]:
	best_tag: str | None = None
	best_version = Version(0, 0, 0)
	for tag in tags:
		version = parse_version(tag)
		if version is None or version.alpha is not None:
			continue
		if version.sortable() > best_version.sortable():
			best_version = version
			best_tag = tag
	return best_tag, best_version


def latest_alpha_for_base(tags: list[str], base_version: Version) -> int:
	best_alpha = 0
	for tag in tags:
		version = parse_version(tag)
		if version is None or version.alpha is None:
			continue
		if version.stable_tuple() != base_version.stable_tuple():
			continue
		best_alpha = max(best_alpha, version.alpha)
	return best_alpha


def latest_reachable_tag() -> str | None:
	return git("describe", "--tags", "--abbrev=0", check=False) or None


def commits_in_range(revision_range: str | None) -> list[Commit]:
	args = ["log", "--format=%H%x1f%s%x1f%b%x1e"]
	if revision_range:
		args.append(revision_range)
	output = git(*args, check=False)
	if not output:
		return []
	commits: list[Commit] = []
	for record in output.split("\x1e"):
		record = record.strip()
		if not record:
			continue
		sha, subject, body = record.split("\x1f", 2)
		commits.append(Commit(sha=sha, subject=subject.strip(), body=body.strip()))
	return commits


def determine_bump(commits: list[Commit]) -> str:
	bump = "patch"
	for commit in commits:
		match = CONVENTIONAL_RE.match(commit.subject)
		is_breaking = "BREAKING CHANGE" in commit.body
		if match:
			if match.group("breaking"):
				is_breaking = True
			kind = match.group("type")
		else:
			kind = ""
		if is_breaking:
			return "major"
		if kind == "feat":
			bump = "minor"
		elif kind in {"fix", "perf", "refactor", "docs", "test", "build", "ci", "chore"}:
			bump = max_bump(bump, "patch")
	return bump


def max_bump(current: str, candidate: str) -> str:
	order = {"patch": 0, "minor": 1, "major": 2}
	return candidate if order[candidate] > order[current] else current


def bump_version(version: Version, bump: str) -> Version:
	if bump == "major":
		return Version(version.major + 1, 0, 0)
	if bump == "minor":
		return Version(version.major, version.minor + 1, 0)
	return Version(version.major, version.minor, version.patch + 1)


def release_notes(commits: list[Commit]) -> str:
	sections: dict[str, list[str]] = {
		"Features": [],
		"Fixes": [],
		"Maintenance": [],
	}
	for commit in commits:
		match = CONVENTIONAL_RE.match(commit.subject)
		if match:
			kind = match.group("type")
			message = match.group("msg").strip()
		else:
			kind = "other"
			message = commit.subject.strip()
		short_sha = commit.sha[:7]
		line = f"- {message} ({short_sha})"
		if kind == "feat":
			sections["Features"].append(line)
		elif kind == "fix":
			sections["Fixes"].append(line)
		else:
			sections["Maintenance"].append(line)

	lines: list[str] = []
	for section, items in sections.items():
		if not items:
			continue
		lines.append(f"### {section}")
		lines.extend(items)
		lines.append("")
	return "\n".join(lines).strip() or "### Maintenance\n- No user-facing changes."


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


def prepend_changelog(version: str, notes: str) -> None:
	header = "# Changelog\n\n"
	existing = CHANGELOG_FILE.read_text(encoding="utf-8") if CHANGELOG_FILE.exists() else header
	if not existing.startswith(header):
		existing = header + existing.lstrip()
	entry_header = f"## {version}\n\n"
	if entry_header in existing:
		return
	body = f"{entry_header}{notes.strip()}\n\n"
	CHANGELOG_FILE.write_text(header + body + existing[len(header) :].lstrip(), encoding="utf-8")


def write_outputs(values: dict[str, str]) -> None:
	output_file = os.environ.get("GITHUB_OUTPUT")
	if output_file:
		with open(output_file, "a", encoding="utf-8") as handle:
			for key, value in values.items():
				handle.write(f"{key}={value}\n")


def main() -> int:
	tags = get_reachable_tags()
	stable_tag, stable_version = latest_stable_tag(tags)
	stable_range = f"{stable_tag}..HEAD" if stable_tag else None
	commits_since_stable = commits_in_range(stable_range)
	if not commits_since_stable:
		print("No commits found for release calculation.", file=sys.stderr)
		return 1

	bump = determine_bump(commits_since_stable)
	base_version = bump_version(stable_version, bump)
	next_alpha = latest_alpha_for_base(tags, base_version) + 1
	version = Version(base_version.major, base_version.minor, base_version.patch, next_alpha)

	previous_tag = latest_reachable_tag()
	changelog_range = f"{previous_tag}..HEAD" if previous_tag else None
	release_commits = commits_in_range(changelog_range)
	notes = release_notes(release_commits)

	update_project_version(version.version_string())
	prepend_changelog(version.version_string(), notes)
	VERSION_FILE.write_text(version.version_string() + "\n", encoding="utf-8")

	notes_path = ROOT / "release-notes.md"
	notes_path.write_text(notes + "\n", encoding="utf-8")

	write_outputs(
		{
			"version": version.version_string(),
			"tag": version.tag(),
			"release_name": f"Huge Buildup {version.version_string()}",
			"notes_path": str(notes_path),
		}
	)
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
