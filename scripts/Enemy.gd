## Enemy.gd
## CPU-controlled fighter with simple state-based AI.
extends Fighter

var player: Fighter = null

# AI timers
var action_timer:    float = 0.0
var action_interval: float = 0.55
var reaction_delay:  float = 0.0

# AI tuning
const ATTACK_RANGE:   float = 160.0
const APPROACH_DIST:  float = 200.0
const RETREAT_DIST:   float = 75.0
const JUMP_CHANCE:    float = 0.12
const SPECIAL_CHANCE: float = 0.18

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	fighter_id   = 1
	facing_right = false
	super._ready()

func set_target(target: Fighter) -> void:
	player = target

# ─────────────────────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if not GameManager.game_active or player == null:
		super._physics_process(delta)
		return

	if current_state in [State.DEAD, State.HIT, State.PUNCH, State.KICK, State.SPECIAL]:
		super._physics_process(delta)
		return

	# Always face the player
	facing_right = position.x < player.position.x

	var dist: float = abs(position.x - player.position.x)
	var dir:  float = sign(player.position.x - position.x)

	# ── Movement AI ──────────────────────────────────────────────────────────
	if dist > APPROACH_DIST:
		velocity.x    = dir * SPEED * 0.75
		current_state = State.WALK
	elif dist < RETREAT_DIST:
		velocity.x    = -dir * SPEED * 0.5
		current_state = State.WALK
	else:
		velocity.x = 0.0
		if current_state == State.WALK:
			current_state = State.IDLE

	# ── Attack AI ────────────────────────────────────────────────────────────
	action_timer += delta
	if action_timer >= action_interval:
		action_timer     = 0.0
		action_interval  = randf_range(0.35, 0.85)

		if dist <= ATTACK_RANGE:
			var roll := randf()
			if roll < 0.38:
				do_punch()
			elif roll < 0.65:
				do_kick()
			elif roll < 0.65 + SPECIAL_CHANCE and special_meter >= SPECIAL_COST:
				do_special()
			elif roll < 0.65 + SPECIAL_CHANCE + JUMP_CHANCE:
				queue_jump()

	super._physics_process(delta)
