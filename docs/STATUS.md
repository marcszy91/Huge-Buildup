# Project Status

## Milestone Summary

- MVP-0: mostly complete
- MVP-1: complete
- MVP-2: complete
- MVP-3: partially complete
- MVP-4: not started

## Implemented

- Godot 4 project scaffold with autoloads and scene flow
- VS Code settings, launch config, tasks, and `gdtoolkit` scripts
- Main menu, lobby, match, and results scenes
- Third-person player controller and placeholder HUD
- ENet host/join flow with lobby sync
- Ready state, character selection, and persistent local settings
- Match timer, score tracking, catch validation, and results ranking

## Missing Or Incomplete

- `docs/STEAM.md`
- Room code support from MVP-4
- Export and release documentation
- Typed standalone data models from the spec (`MatchConfig`, `PlayerInfo`, `PlayerMatchStats`, `MatchState`)
- Arena selection wired from config into match scene loading

## Known Spec Deviations

- The spec says there is exactly one "It". The current implementation supports multiple catchers.
- The spec names tag RPCs as `rpc_req_tag_attempt` and `rpc_sync_it_changed`. The current code uses `rpc_req_catch_attempt` and `rpc_sync_catch_applied`.
- The spec describes `scripts/net/` and `scripts/util/` as active structure, but current runtime code is concentrated in `scripts/autoload/`, `scripts/game/`, and `scripts/ui/`.
- The old `README.md` claimed the project was still at MVP-0; that was out of date and is now corrected.

## Recommended Next Decisions

1. Decide whether the game should stay with multiple catchers or return to exactly one "It".
2. Align the spec and RPC contract with the chosen ruleset.
3. After that, implement the next missing milestone feature set rather than adding more surface area.
