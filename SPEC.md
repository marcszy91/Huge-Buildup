# SPEC.md — Huge Buildup (Godot 4) — Full Spec (MVP → Steam)

## 0) Purpose
Build a lightweight 3D multiplayer "Tag" (Fangen) game for LAN + Internet (via host), exportable to Windows/macOS/Linux, with a clear path to Steam release and Steam features (Steam usernames + lobbies/invites).

Primary goals:
- Fun LAN-party gameplay, quick to iterate, stable networking.
- Clean architecture: UI and game logic separated.
- Minimal dependencies; start simple, improve incrementally.

Non-goals (for MVP):
- Anti-cheat hardening (beyond authoritative host checks).
- Complex physics, fancy graphics, large content pipeline.
- True NAT traversal without Steam (MVP uses IP/port).

---

## 1) Defaults & Constraints
### 1.1 Engine & Language
- Engine: Godot 4.x (latest stable recommended).
- Language: Typed GDScript.
- Use Godot built-ins as much as possible.

### 1.2 Platforms
- Windows, macOS, Linux (x86_64).
- Repo and tooling must stay cross-platform.

### 1.3 Networking
- MVP: Godot High-Level Multiplayer (ENet).
- Authoritative host (server) decides truth.
- Steam phase: Steam display names + Steam lobbies/invites (GodotSteam or equivalent).

### 1.4 Gameplay Defaults
- Max players: 16
- Default port: 24567
- Default match duration: 180 seconds
- Tag radius: 1.2 meters (host validated)
- Perspective: third-person behind player
- Controls: WASD + mouse look
- Jump: OFF by default
- Sprint: ON by default (no stamina) (optional to implement early or later)

### 1.5 Tie Rules
- Winners are **all players** with the lowest `times_caught`.
- Same placement for ties (no tie-breaker in MVP).

---

## 2) MVP-0 Bootstrap (Repository + Tooling)
Goal: create a clean baseline so development is comfortable in VS Code.

Deliverables:
1) Godot project scaffold:
   - `project.godot` exists (Godot 4.x)
   - folders: `scenes/`, `scripts/`, `assets/`, `docs/`
   - scripts subfolders:
     - `scripts/autoload/`
     - `scripts/game/`
     - `scripts/net/`
     - `scripts/ui/`
     - `scripts/util/`
     - `scripts/dev/`

2) Git hygiene:
   - `.gitignore` suitable for Godot 4 + VS Code + exports
   - optional `.gitattributes` for consistent line endings

3) VS Code:
   - `.vscode/settings.json`
   - `.vscode/extensions.json`
   - `.vscode/launch.json` (run project / open editor via GODOT4 env var)
   - `.vscode/tasks.json` for lint/format

4) Lint/Format:
   - Use `gdtoolkit` (gdlint + gdformat) via Python venv OR pipx.
   - Add `requirements-dev.txt` (or `pyproject.toml`) for dev tooling.
   - Add cross-platform scripts or instructions:
     - `scripts/dev/lint.*`
     - `scripts/dev/format.*`

5) Documentation:
   - `README.md` explains:
     - prerequisites (Godot, Python)
     - how to open/run project
     - how to lint/format
     - repo structure overview

Rules:
- Keep tooling cross-platform; do NOT require Docker.
- Avoid complex CI initially. (Optional later.)

Acceptance for MVP-0:
- Repo opens in VS Code without noise.
- Godot opens the project.
- Lint/format commands are documented.

---

## 3) Core Game Loop
### 3.1 High-level Flow
1) Player opens game → Main Menu
2) Host creates lobby OR joins lobby
3) Lobby shows players + ready state
4) Host starts match
5) Match in a 3D arena: one player is "It"
6) Tagging switches "It"
7) Track `times_caught` (victim increments on tag)
8) Timer ends match
9) Results screen shows ranking and winners
10) Return to lobby or main menu

### 3.2 Tagging Rules
- Exactly one player is "It".
- If "It" touches another player:
  - target becomes "It" immediately
  - target `times_caught += 1`
- Tagging is validated by host:
  - only current "It" can tag
  - host checks distance <= `tag_radius_m` + epsilon

### 3.3 Win Condition
- After match duration ends:
  - compute minimal `times_caught`
  - all players with that minimal value are winners

---

## 4) Arena Design (Balanced)
Requirements:
- Not too easy to run forever, not too hard to catch.
- Provide line-of-sight breaks and multiple routes.

Recommended initial arena:
- playable area around ~35m x 35m
- boundary walls / colliders
- obstacles (8–12):
  - several pillars/blocks (LoS breaks)
  - 1–2 bigger structures (ring, U-wall, central cover)
  - some low cover
- no infinite safe loops; avoid perfect circular loop around a single obstacle

MVP content:
- single arena: `Arena.tscn`
Later:
- multiple arenas selected by host.

---

## 5) Architecture (Required)
Use layered, event-driven architecture with Autoload singletons.
UI must be separated from game logic.

### 5.1 Autoloads (Singletons)
- `App`: high-level state machine and scene transitions
- `Net`: networking wrapper (host/join, peer management, RPC facade, errors)
- `Game`: session state (players, config, timer, it, stats)
- `Settings`: user settings persisted to `user://`

### 5.2 Separation Rules
- UI scripts must NOT directly mutate game state dictionaries.
- UI calls `App` requests (e.g. `App.request_host(config)`)
- `Game` emits signals; UI listens and updates.
- Scenes should not hardcode deep node paths.

### 5.3 Signals (recommended)
- `Net.connection_state_changed(state: int)`
- `Net.error(message: String)`
- `Game.player_list_changed()`
- `Game.lobby_config_changed()`
- `Game.match_state_changed()`
- `Game.score_changed()`
- `Game.timer_changed(time_remaining_s: int)`
- `Game.it_changed(it_peer_id: int)`

### 5.4 Scene Layout
- `scenes/MainMenu.tscn`
- `scenes/Lobby.tscn`
- `scenes/Match.tscn`
- `scenes/Results.tscn`
- `scenes/world/Arena.tscn`
- `scenes/player/Player.tscn`
- UI components under `scenes/ui/components/`

Gameplay nodes (arena + players) belong to Match scene only.

---

## 6) Data Models (Typed GDScript)
### 6.1 Protocol
- `const PROTOCOL_VERSION: int = 1`

### 6.2 MatchConfig
Fields:
- `max_players: int = 16`
- `match_duration_s: int = 180`
- `port: int = 24567`
- `tag_radius_m: float = 1.2`
- `arena_id: String = "default"`

Host-controlled. Broadcast to all at match start.

### 6.3 PlayerInfo
Fields:
- `peer_id: int`
- `display_name: String`
- `is_ready: bool`
- `join_index: int` (host = 0, then increment for new joiners)

Steam phase optional:
- `steam_id: String` (empty in MVP)

### 6.4 PlayerMatchStats
Fields:
- `times_caught: int = 0`
- `time_as_it_ms: int = 0` (optional future metric)

### 6.5 MatchState
Fields:
- `config: MatchConfig`
- `players: Dictionary[int, PlayerInfo]`
- `stats: Dictionary[int, PlayerMatchStats]`
- `it_peer_id: int`
- `match_start_unix_ms: int`
- `time_remaining_s: int`
- `is_running: bool`

---

## 7) Networking Model (MVP)
### 7.1 Topology
- Host runs server using `ENetMultiplayerPeer.create_server(port, max_players)`
- Client connects using `ENetMultiplayerPeer.create_client(ip, port)`
- Host is authoritative; clients send intents.

### 7.2 Connection UX
- Friendly errors for timeout/refused/version mismatch.
- If host leaves, clients return to Main Menu with message.

### 7.3 Version Check
- During join request, client sends `client_version`.
- Host rejects if mismatch with `PROTOCOL_VERSION`.

---

## 8) Room Code (MVP Convenience)
### 8.1 Purpose
Room Code is a human-friendly share token to avoid typing IP:port.
It does NOT solve NAT traversal.

### 8.2 Encoding
Encode:
- `protocol_version` (int)
- `host_string` (IP or DNS name as string)
- `port` (int)
- `checksum` (CRC32 or Adler32)

Format:
- Base32 groups with prefix:
  - `TAG-XXXX-XXXX-XXXX` (groups may vary length)
- Provide copy button in Lobby.

### 8.3 Decoding
- If protocol mismatch → error.
- If checksum mismatch → error.
- On success, join using decoded host:port.

---

## 9) Match Networking: Replication Strategy (MVP)
### 9.1 Transform Replication (simple & stable)
Approach:
- Each client controls its own movement locally for responsiveness.
- Client sends its transform to host at fixed rate (10–20/s).
- Host re-broadcasts to other clients.
- Remote players are interpolated.

Security:
- Host validates tagging via distance checks.
- (Optional later) Host validates max speed / teleport prevention.

### 9.2 Tagging Validation
- Only "It" can tag.
- Client may propose tag attempt:
  - Host checks: distance(it, target) <= tag_radius_m + epsilon
- Host applies and broadcasts result.

---

## 10) RPC Contract (Must match implementation)
Conventions:
- Host -> clients: `rpc_sync_*`
- Client -> host: `rpc_req_*`

### 10.1 Lobby RPCs
Client -> Host:
- `rpc_req_join(display_name: String, client_version: int)`
- `rpc_req_set_ready(is_ready: bool)`

Host -> Client (targeted):
- `rpc_sync_join_result(ok: bool, message: String, assigned_peer_id: int)`
- `rpc_sync_lobby_state(players: Array[Dictionary], config: Dictionary)`

Host -> All:
- `rpc_sync_player_ready(peer_id: int, is_ready: bool)`
- `rpc_sync_player_left(peer_id: int)`
- `rpc_sync_config(config: Dictionary)`

### 10.2 Match Start & Loading
Host -> All:
- `rpc_sync_start_match(config: Dictionary, it_peer_id: int, seed: int)`

Client -> Host:
- `rpc_req_match_loaded()`

Host -> All:
- `rpc_sync_match_begin(match_start_unix_ms: int)`

### 10.3 Transform Updates
Client -> Host:
- `rpc_req_player_transform(pos: Vector3, yaw: float)`

Host -> All:
- `rpc_sync_player_transform(peer_id: int, pos: Vector3, yaw: float)`

Rate:
- 10–20 updates/s max.

### 10.4 Tag Attempts
Client -> Host:
- `rpc_req_tag_attempt(target_peer_id: int, my_pos: Vector3)` (optional but recommended)

Host -> All:
- `rpc_sync_it_changed(new_it_peer_id: int, victim_peer_id: int, victim_times_caught: int)`

### 10.5 Timer & End
Host -> All (once per second or on change):
- `rpc_sync_time_remaining(time_remaining_s: int)`

Host -> All (match end):
- `rpc_sync_match_end(results: Array[Dictionary])`

Result dict fields:
- `peer_id`, `display_name`, `times_caught`, `rank`, `is_winner`

Ranking:
- Sort by `times_caught` ascending.
- Equal `times_caught` → same `rank`, all are winners if rank==1.

---

## 11) Player Scene & Tag Trigger
### 11.1 Player.tscn Components
- CharacterBody3D (or similar)
- Camera rig (only enabled for local player)
- `TagArea` as Area3D (sphere/capsule)
  - radius approx `tag_radius_m`
  - only active for local player if local player is "It"
- Visual: simple capsule/mesh placeholder

### 11.2 Tag Detection
Local "It" detects overlap and requests tag:
- On overlap begin, call `rpc_req_tag_attempt(target_peer_id, my_pos)`
- Host validates and broadcasts `rpc_sync_it_changed`

---

## 12) Milestones (Implementation Order)
### MVP-0 Bootstrap
Tooling + structure + docs (see section 2)

### MVP-1 Local Prototype
- Arena + one player movement + camera
- HUD placeholder

### MVP-2 Networking Basics
- Host and Join via IP:port
- Lobby player list + ready toggles
- Start match loads Match for all peers

### MVP-3 Tagging + Score + Timer
- Deterministic initial "It" (host)
- Host validates tags, switches "It"
- Track times_caught and show scoreboard
- Timer ends match, show Results with tie support

### MVP-4 Room Code Convenience
- Encode/decode room code for host_string + port
- Join via room code
- UI copy/paste + errors

---

## 13) Steam Phase (Document first; implement later)
### 13.1 Goals
- Use Steam display names automatically (no manual name input needed).
- Use Steam lobbies and invites (no IP typing).
- Keep IP join as fallback (optional).

### 13.2 Approach
- Use GodotSteam (GDExtension) or equivalent.
- Add a feature flag: `STEAM_ENABLED`.
- When enabled:
  - Create Steam lobby on host
  - Join lobby on clients via invite/join code
  - Show Steam friend invite option
  - Use Steam name for display_name
- Networking transport can remain ENet for gameplay, or migrate to Steam P2P later.
  - Start with Steam lobbies for discovery + ENet for gameplay if feasible.
  - Document tradeoffs in `docs/STEAM.md`.

Deliverables:
- `docs/STEAM.md` describing:
  - export presets and depots
  - Steam Direct checklist
  - implementation plan for lobbies/invites/names
  - testing plan using Steam App ID (spacewar 480 for local dev if allowed) — document only, don't hardcode.

---

## 14) Acceptance Criteria
MVP Acceptance:
- Two machines can host/join and play on LAN.
- Tagging is consistent across peers; "It" changes correctly.
- Score + timer consistent across peers.
- Results show correct ranking with ties.
- Exports run on Windows/macOS/Linux.

Quality Acceptance:
- UI and logic separated via Autoloads + signals.
- Repo includes lint/format and VS Code settings.
- Basic docs exist and match reality.
