## Fighter.gd
## Base class for all fighters (Player and Enemy).
## Handles physics, health, special meter, attack states, hitboxes.
extends CharacterBody2D
class_name Fighter

# ─── Signals ─────────────────────────────────────────────────────────────────
signal took_damage(amount: float)
signal died()

# ─── Identity ────────────────────────────────────────────────────────────────
var fighter_id: int = 0    # 0 = player, 1 = enemy

# ─── State Machine ───────────────────────────────────────────────────────────
enum State { IDLE, WALK, JUMP, CROUCH, PUNCH, KICK, SPECIAL, HIT, DEAD }
var current_state: State = State.IDLE
var facing_right: bool = true

# ─── Stats ───────────────────────────────────────────────────────────────────
const MAX_HEALTH:  float = 100.0
const MAX_SPECIAL: float = 100.0
var health:  float = MAX_HEALTH
var special_meter: float = 0.0

# ─── Physics Constants ───────────────────────────────────────────────────────
const SPEED:         float = 280.0
const JUMP_FORCE:    float = -680.0
const GRAVITY:       float = 1200.0
const CROUCH_SCALE:  float = 0.55

# ─── Combat Timing (seconds) ─────────────────────────────────────────────────
const PUNCH_DURATION:   float = 0.35
const KICK_DURATION:    float = 0.50
const SPECIAL_DURATION: float = 0.65
const HIT_STUN:         float = 0.28
const HITBOX_OPEN:      float = 0.20
const HITBOX_CLOSE:     float = 0.70

# ─── Combat State ─────────────────────────────────────────────────────────────
var attack_timer:    float = 0.0
var attack_duration: float = 0.0
var hit_stun_timer:  float = 0.0
var can_attack:      bool  = true
var jump_queued:     bool  = false
var hitbox_active:   bool  = false
var hit_landed:      bool  = false

# ─── Damage Values ────────────────────────────────────────────────────────────
const PUNCH_DMG:   float = 8.0
const KICK_DMG:    float = 13.0
const SPECIAL_DMG: float = 26.0
const SPECIAL_COST: float = 50.0

# ─── Node References (assigned in _ready) ────────────────────────────────────
var sprite_node:   ColorRect = null
var attack_area:   Area2D    = null
var hurtbox_area:  Area2D    = null
var attack_shape:  CollisionShape2D = null

# ─── Character visual dimensions ─────────────────────────────────────────────
const CHAR_W: float = 72.0
const CHAR_H: float = 144.0

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	sprite_node  = get_node_or_null("Sprite")
	attack_area  = get_node_or_null("AttackArea")
	hurtbox_area = get_node_or_null("Hurtbox")
	attack_shape = get_node_or_null("AttackArea/CollisionShape2D")

	if hurtbox_area:
		hurtbox_area.area_entered.connect(_on_hurtbox_entered)

# ─────────────────────────────────────────────────────────────────────────────
func reset() -> void:
	health         = MAX_HEALTH
	special_meter  = 0.0
	current_state  = State.IDLE
	velocity       = Vector2.ZERO
	can_attack     = true
	hitbox_active  = false
	hit_landed     = false
	attack_timer   = 0.0
	_update_visual()

# ─── Main Physics Loop ────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if current_state == State.DEAD:
		return

	# Gravity
	if not is_on_floor():
		velocity.y += GRAVITY * delta
	elif current_state == State.JUMP:
		_land()

	# State processing
	match current_state:
		State.HIT:
			hit_stun_timer -= delta
			if hit_stun_timer <= 0.0:
				current_state = State.IDLE
				can_attack = true

		State.PUNCH, State.KICK, State.SPECIAL:
			attack_timer += delta
			var open  = attack_duration * HITBOX_OPEN
			var close = attack_duration * HITBOX_CLOSE
			var should_be_active = (attack_timer >= open and attack_timer < close)

			if should_be_active != hitbox_active:
				hitbox_active = should_be_active
				if attack_area:
					attack_area.monitoring = hitbox_active

			if attack_timer >= attack_duration:
				_end_attack()

	# Jump queue
	if jump_queued and is_on_floor():
		velocity.y = JUMP_FORCE
		current_state = State.JUMP
		jump_queued   = false

	move_and_slide()

	# Clamp to arena
	var vp_w: float = get_viewport_rect().size.x
	position.x = clamp(position.x, CHAR_W * 0.5 + 10.0, vp_w - CHAR_W * 0.5 - 10.0)

	_update_visual()
	_report_to_manager()

# ─────────────────────────────────────────────────────────────────────────────
func _end_attack() -> void:
	attack_timer  = 0.0
	hitbox_active = false
	hit_landed    = false
	can_attack    = true
	if attack_area:
		attack_area.monitoring = false
	current_state = State.IDLE

func _land() -> void:
	current_state = State.IDLE
	velocity.y    = 0.0

# ─── Visual Update ────────────────────────────────────────────────────────────
func _update_visual() -> void:
	if not sprite_node:
		return

	var h: float = CHAR_H
	var w: float = CHAR_W
	var crouch: bool = (current_state == State.CROUCH)

	if crouch:
		sprite_node.size     = Vector2(w, h * CROUCH_SCALE)
		sprite_node.position = Vector2(-w * 0.5, -h * CROUCH_SCALE)
	else:
		sprite_node.size     = Vector2(w, h)
		sprite_node.position = Vector2(-w * 0.5, -h)

	# Flash red on hit
	if current_state == State.HIT:
		sprite_node.color = Color(1.0, 0.3, 0.3, 1.0) if fighter_id == 0 else Color(1.0, 0.5, 0.2, 1.0)
	elif fighter_id == 0:
		sprite_node.color = Color(0.2, 0.55, 1.0, 1.0)
	else:
		sprite_node.color = Color(0.85, 0.15, 0.15, 1.0)

	sprite_node.scale.x = 1.0

func _report_to_manager() -> void:
	GameManager.report_health(fighter_id, health, MAX_HEALTH)
	GameManager.report_special(fighter_id, special_meter)

# ─── Attack Methods ───────────────────────────────────────────────────────────
func do_punch() -> void:
	if not _can_start_attack():
		return
	current_state  = State.PUNCH
	attack_duration = PUNCH_DURATION
	attack_timer   = 0.0
	can_attack     = false
	hit_landed     = false
	_position_hitbox(Vector2(70, -20), Vector2(60, 48))

func do_kick() -> void:
	if not _can_start_attack():
		return
	current_state  = State.KICK
	attack_duration = KICK_DURATION
	attack_timer   = 0.0
	can_attack     = false
	hit_landed     = false
	_position_hitbox(Vector2(75, 10), Vector2(80, 55))

func do_special() -> void:
	if not _can_start_attack():
		return
	if special_meter < SPECIAL_COST:
		return
	special_meter  -= SPECIAL_COST
	current_state  = State.SPECIAL
	attack_duration = SPECIAL_DURATION
	attack_timer   = 0.0
	can_attack     = false
	hit_landed     = false
	_position_hitbox(Vector2(80, -15), Vector2(100, 80))

func queue_jump() -> void:
	if is_on_floor() and current_state != State.DEAD and current_state != State.HIT:
		jump_queued = true

func _can_start_attack() -> bool:
	if not can_attack:
		return false
	if current_state in [State.HIT, State.DEAD]:
		return false
	return true

func _position_hitbox(offset: Vector2, size: Vector2) -> void:
	if not attack_area or not attack_shape:
		return
	var dir: float = 1.0 if facing_right else -1.0
	attack_area.position = Vector2(offset.x * dir, offset.y)
	if attack_shape.shape is RectangleShape2D:
		(attack_shape.shape as RectangleShape2D).size = size

# ─── Damage Reception ─────────────────────────────────────────────────────────
func take_damage(amount: float, knockback_dir: float) -> void:
	if current_state == State.DEAD:
		return

	health = max(0.0, health - amount)
	special_meter = min(MAX_SPECIAL, special_meter + amount * 0.4)
	took_damage.emit(amount)

	if health <= 0.0:
		_die()
	else:
		current_state  = State.HIT
		hit_stun_timer = HIT_STUN
		can_attack     = false
		velocity.x     = knockback_dir * 200.0
		velocity.y     = -120.0

func get_current_damage() -> float:
	match current_state:
		State.PUNCH:   return PUNCH_DMG
		State.KICK:    return KICK_DMG
		State.SPECIAL: return SPECIAL_DMG
	return 0.0

func _die() -> void:
	current_state = State.DEAD
	velocity      = Vector2.ZERO
	died.emit()
	GameManager.end_round(1 - fighter_id)

# ─── Hurtbox Hit Detection ────────────────────────────────────────────────────
func _on_hurtbox_entered(area: Area2D) -> void:
	var attacker = area.get_parent() as Fighter
	if attacker == null or attacker == self:
		return
	if attacker.hitbox_active and not attacker.hit_landed:
		attacker.hit_landed = true
		var dir: float = sign(position.x - attacker.position.x)
		take_damage(attacker.get_current_damage(), dir)
		attacker.special_meter = min(MAX_SPECIAL, attacker.special_meter + attacker.get_current_damage() * 0.3)
