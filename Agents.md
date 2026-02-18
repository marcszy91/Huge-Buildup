# AGENTS.md — Codex Instructions (Source of Truth)

You must follow the specification in @SPEC.md.

## Work Mode (very important)
- Work step-by-step. Before making changes:
  1) explain what you will do in the current step,
  2) wait for my confirmation ("go ahead"),
  3) implement,
  4) tell me exactly how to run/test it,
  5) then propose the next small step.

## Milestones
Start with **MVP-0 Bootstrap** (repository + tooling + project structure) before any gameplay.
Then proceed with MVP-1..MVP-4 as defined in @SPEC.md.

## Coding & Repo Standards
- Godot 4.x, typed GDScript.
- Keep UI and logic separated (autoloads, signals, scenes).
- Prefer small commits and reviewable diffs.
- Do not add heavy dependencies. Use minimal tooling that works cross-platform.
