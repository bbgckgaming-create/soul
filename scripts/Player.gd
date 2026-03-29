## Player.gd
## Human-controlled fighter. Reads input from VirtualJoystick and action buttons.
## Also supports keyboard input for desktop testing.
class_name Player
extends Fighter

# Input state set by VirtualJoystick and ActionButtons
var joystick_dir: Vector2 = Vector2.ZERO

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	fighter_id    = 0
	facing_right  = true
	super._ready()

# ─── Input Triggers (called by UI buttons) ───────────────────────────────────
func input_punch()   -> void: do_punch()
func input_kick()    -> void: do_kick()
func input_special() -> void: do_special()

func set_joystick(direction: Vector2) -> void:
	joystick_dir = direction

# ─────────────────────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if not GameManager.game_active:
		super._physics_process(delta)
		return

	# ── Keyboard fallback (useful for desktop testing) ──
	var kb_dir := Vector2.ZERO
	if Input.is_action_pressed("move_left"):  kb_dir.x -= 1.0
	if Input.is_action_pressed("move_right"): kb_dir.x += 1.0
	if Input.is_action_pressed("jump"):       kb_dir.y -= 1.0
	if Input.is_action_pressed("crouch"):     kb_dir.y += 1.0

	if Input.is_action_just_pressed("punch"):   do_punch()
	if Input.is_action_just_pressed("kick"):    do_kick()
	if Input.is_action_just_pressed("special"): do_special()

	# Merge joystick + keyboard
	var dir := joystick_dir
	if kb_dir != Vector2.ZERO:
		dir = kb_dir

	# ── Movement (skip if in attack/hit state) ──
	if current_state not in [State.PUNCH, State.KICK, State.SPECIAL, State.HIT, State.DEAD]:
		# Horizontal
		if dir.x > 0.25:
			velocity.x    = SPEED
			current_state = State.WALK
			facing_right  = true
		elif dir.x < -0.25:
			velocity.x    = -SPEED
			current_state = State.WALK
			facing_right  = false
		else:
			velocity.x = 0.0
			if current_state == State.WALK:
				current_state = State.IDLE

		# Crouch (ground only)
		if dir.y > 0.5 and is_on_floor():
			current_state = State.CROUCH
			velocity.x    = 0.0
		elif current_state == State.CROUCH and dir.y <= 0.5:
			current_state = State.IDLE

		# Jump
		if dir.y < -0.5:
			queue_jump()

	super._physics_process(delta)
