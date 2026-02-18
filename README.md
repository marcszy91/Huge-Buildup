# Huge Buildup

3D multiplayer Tag game in Godot 4.x.

Current status: MVP-0 Bootstrap (project + tooling baseline).

## Prerequisites

- Godot 4.x
- Python 3.10+ (for dev tooling)
- PowerShell 7 (`pwsh`) on Windows

## Open and Run the Project

### Option A: Godot directly

1. Open project in editor:

```powershell
$env:GODOT4="C:\tmp\godot\Godot_v4.x-stable_win64.exe"
& $env:GODOT4 --editor --path .
```

2. Run project:

```powershell
& $env:GODOT4 --path .
```

### Option B: VS Code

- Use `Run and Debug`:
  - `Godot: Open Editor`
  - `Godot: Run Project`
- Ensure `GODOT4` points to your Godot executable.

## Dev Tooling (gdtoolkit)

### Install

```powershell
python -m venv .venv
.venv\Scripts\python -m pip install -r requirements-dev.txt
```

### Lint / Format

Windows:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/dev/lint.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/dev/format.ps1
```

macOS/Linux:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements-dev.txt
bash scripts/dev/lint.sh
bash scripts/dev/format.sh
```

You can also run the VS Code tasks:

- `gdtoolkit: lint`
- `gdtoolkit: format`

## Repository Structure

```text
assets/
docs/
scenes/
scripts/
  autoload/
  dev/
  game/
  net/
  ui/
  util/
.vscode/
project.godot
requirements-dev.txt
```

## Notes

- Architecture rule: keep UI and game logic separated (autoloads + signals).
- MVP-0 intentionally has no gameplay implementation yet.
