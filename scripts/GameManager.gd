## GameManager.gd
## Autoloaded singleton — manages global game state, rounds, and signals.
extends Node

# ─── Signals ────────────────────────────────────────────────────────────────
signal health_changed(fighter_id: int, health: float, max_health: float)
signal special_changed(fighter_id: int, special: float)
signal round_ended(winner: int)          # 0 = player, 1 = enemy
signal game_over(winner: int)

# ─── Constants ───────────────────────────────────────────────────────────────
const ROUNDS_TO_WIN: int = 2

# ─── State ───────────────────────────────────────────────────────────────────
var player_wins: int = 0
var enemy_wins: int = 0
var current_round: int = 1
var game_active: bool = false

# ─── Public API ──────────────────────────────────────────────────────────────
func start_game() -> void:
	player_wins = 0
	enemy_wins = 0
	current_round = 1
	game_active = true

func end_round(winner: int) -> void:
	if not game_active:
		return
	game_active = false

	if winner == 0:
		player_wins += 1
	else:
		enemy_wins += 1

	round_ended.emit(winner)

	if player_wins >= ROUNDS_TO_WIN or enemy_wins >= ROUNDS_TO_WIN:
		var game_winner: int = 0 if player_wins >= ROUNDS_TO_WIN else 1
		game_over.emit(game_winner)
	else:
		current_round += 1

func report_health(fighter_id: int, health: float, max_health: float) -> void:
	health_changed.emit(fighter_id, health, max_health)

func report_special(fighter_id: int, special: float) -> void:
	special_changed.emit(fighter_id, special)