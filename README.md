# Huge Buildup

Lightweight 3D multiplayer tag game built with Godot 4.x and typed GDScript.

Current status: MVP-2 complete, MVP-3 partially implemented.

## Prerequisites

- Godot 4.x
- Python 3.10+ for dev tooling
- PowerShell 7 (`pwsh`) on Windows

## Open and Run

### Option A: Godot directly

Open the editor:

```powershell
$env:GODOT4="C:\path\to\Godot_v4.x-stable_win64.exe"
& $env:GODOT4 --editor --path .
```

Run the project:

```powershell
& $env:GODOT4 --path .
```

### Option B: VS Code

Use `Run and Debug` with:

- `Godot: Open Editor`
- `Godot: Run Project`

`GODOT4` must point to your Godot executable.

## Current Feature Set

- Main menu with host/join flow via IP and port
- Lobby with player list, ready state, character selection, and catcher count
- Match scene with third-person movement and transform replication
- Host-validated catch attempts, score tracking, timer sync, and results screen
- Persistent local settings for display name, mouse sensitivity, and character choice

## Dev Tooling

`gdtoolkit` is used for linting and formatting.

Install:

```powershell
python -m venv .venv
.venv\Scripts\python -m pip install -r requirements-dev.txt
```

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

- UI and game logic are separated through autoload singletons and signals.
- The current implementation already goes beyond MVP-0.
- The current codebase supports multiple catchers, which differs from the original single-"It" wording in `SPEC.md`.
- See `docs/STATUS.md` for the current milestone audit and known spec deviations.
