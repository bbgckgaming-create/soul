## Fighter.gd
## Base class for all fighters (Player and Enemy).
extends CharacterBody2D
class_name Fighter

signal took_damage(amount: float)
signal died()

var fighter_id: int = 0

enum State { IDLE, WALK, JUMP, CROUCH, PUNCH, KICK, SPECIAL, HIT, DEAD }
var current_state: State = State.IDLE
var facing_right: bool = true

const MAX_HEALTH:  float = 100.0
const MAX_SPECIAL: float = 100.0
var health:        float = MAX_HEALTH
var special_meter: float = 0.0

const SPEED:        float = 280.0
const JUMP_FORCE:   float = -680.0
const GRAVITY:      float = 1200.0
const CROUCH_SCALE: float = 0.55

const PUNCH_DURATION:   float = 0.35
const KICK_DURATION:    float = 0.50
const SPECIAL_DURATION: float = 0.65
const HIT_STUN:         float = 0.28
const HITBOX_OPEN:      float = 0.20
const HITBOX_CLOSE:     float = 0.70

var attack_timer:    float = 0.0
var attack_duration: float = 0.0
var hit_stun_timer:  float = 0.0
var can_attack:      bool  = true
var jump_queued:     bool  = false
var hitbox_active:   bool  = false
var hit_landed:      bool  = false

const PUNCH_DMG:    float = 8.0
const KICK_DMG:     float = 13.0
const SPECIAL_DMG:  float = 26.0
const SPECIAL_COST: float = 50.0

# Character dimensions — 10% larger than before
const CHAR_W: float = 80.0
const CHAR_H: float = 158.0

# Node refs
var sprite_node:  ColorRect = null
var limb_node:    ColorRect = null   # Visual for punches/kicks
var attack_area:  Area2D    = null
var hurtbox_area: Area2D    = null
var attack_shape: CollisionShape2D = null

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	sprite_node  = get_node_or_null("Sprite")
	limb_node    = get_node_or_null("Limb")
	attack_area  = get_node_or_null("AttackArea")
	hurtbox_area = get_node_or_null("Hurtbox")
	attack_shape = get_node_or_null("AttackArea/CollisionShape2D")

func reset() -> void:
	health        = MAX_HEALTH
	special_meter = 0.0
	current_state = State.IDLE
	velocity      = Vector2.ZERO
	can_attack    = true
	hitbox_active = false
	hit_landed    = false
	attack_timer  = 0.0
	_update_visual()

# ─── Main Physics Loop ────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if current_state == State.DEAD:
		return

	if not is_on_floor():
		velocity.y += GRAVITY * delta
	elif current_state == State.JUMP:
		_land()

	match current_state:
		State.HIT:
			hit_stun_timer -= delta
			if hit_stun_timer <= 0.0:
				current_state = State.IDLE
				can_attack    = true

		State.PUNCH, State.KICK, State.SPECIAL:
			attack_timer += delta
			var open  := attack_duration * HITBOX_OPEN
			var close := attack_duration * HITBOX_CLOSE
			hitbox_active = (attack_timer >= open and attack_timer < close)

			# ── Manual overlap check every frame during active window ──────────
			# Relying on area_entered misses already-overlapping enemies, so we
			# poll get_overlapping_areas() instead.
			if hitbox_active and not hit_landed and attack_area:
				attack_area.monitoring = true
				for area in attack_area.get_overlapping_areas():
					var target := area.get_parent() as Fighter
					if target and target != self:
						hit_landed    = true
						var dir: float = sign(target.position.x - position.x)
						target.take_damage(get_current_damage(), dir)
						special_meter = min(MAX_SPECIAL, special_meter + get_current_damage() * 0.3)
						break
			elif not hitbox_active and attack_area:
				attack_area.monitoring = false

			if attack_timer >= attack_duration:
				_end_attack()

	if jump_queued and is_on_floor():
		velocity.y    = JUMP_FORCE
		current_state = State.JUMP
		jump_queued   = false

	move_and_slide()

	var vp_w: float = get_viewport_rect().size.x
	position.x = clamp(position.x, CHAR_W * 0.5 + 10.0, vp_w - CHAR_W * 0.5 - 10.0)

	_update_visual()
	_report_to_manager()

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

	var w := CHAR_W
	var h := CHAR_H
	var dir := 1.0 if facing_right else -1.0

	# ── Body size & color ─────────────────────────────────────────────────────
	match current_state:
		State.CROUCH:
			sprite_node.size     = Vector2(w, h * CROUCH_SCALE)
			sprite_node.position = Vector2(-w * 0.5, -h * CROUCH_SCALE)
		_:
			sprite_node.size     = Vector2(w, h)
			sprite_node.position = Vector2(-w * 0.5, -h)

	# Body color reflects state
	match current_state:
		State.HIT:
			sprite_node.color = Color(1.0, 0.25, 0.25) if fighter_id == 0 else Color(1.0, 0.45, 0.1)
		State.PUNCH, State.KICK, State.SPECIAL:
			# Brighten body during attack so player can see they pressed something
			sprite_node.color = Color(0.55, 0.85, 1.0) if fighter_id == 0 else Color(1.0, 0.45, 0.45)
		_:
			sprite_node.color = Color(0.2, 0.55, 1.0) if fighter_id == 0 else Color(0.85, 0.15, 0.15)

	# ── Limb (attack visual) ──────────────────────────────────────────────────
	if limb_node:
		match current_state:
			State.PUNCH:
				# Fist extends forward at chest height, animates with attack_timer
				var progress := clamp(attack_timer / attack_duration, 0.0, 1.0)
				var extend   := sin(progress * PI) * 70.0   # arc: out and back
				limb_node.visible  = true
				limb_node.size     = Vector2(extend + 20.0, 22.0)
				limb_node.position = Vector2(dir * (w * 0.5), -h * 0.62)
				limb_node.color    = Color(0.3, 0.75, 1.0) if fighter_id == 0 else Color(1.0, 0.55, 0.2)

			State.KICK:
				# Leg extends diagonally downward
				var progress := clamp(attack_timer / attack_duration, 0.0, 1.0)
				var extend   := sin(progress * PI) * 90.0
				limb_node.visible  = true
				limb_node.size     = Vector2(extend + 20.0, 26.0)
				limb_node.position = Vector2(dir * (w * 0.5), -h * 0.28)
				limb_node.color    = Color(0.2, 0.9, 0.5) if fighter_id == 0 else Color(1.0, 0.8, 0.1)

			State.SPECIAL:
				# Full-body surge: large glowing rect
				var progress := clamp(attack_timer / attack_duration, 0.0, 1.0)
				var extend   := sin(progress * PI) * 130.0
				limb_node.visible  = true
				limb_node.size     = Vector2(extend + 30.0, 60.0)
				limb_node.position = Vector2(dir * (w * 0.5), -h * 0.5)
				limb_node.color    = Color(0.9, 0.4, 1.0, 0.9)

			_:
				limb_node.visible = false

func _report_to_manager() -> void:
	GameManager.report_health(fighter_id, health, MAX_HEALTH)
	GameManager.report_special(fighter_id, special_meter)

# ─── Attack Methods ───────────────────────────────────────────────────────────
func do_punch() -> void:
	if not _can_start_attack(): return
	current_state   = State.PUNCH
	attack_duration = PUNCH_DURATION
	attack_timer    = 0.0
	can_attack      = false
	hit_landed      = false
	_position_hitbox(Vector2(CHAR_W * 0.5 + 35.0, -CHAR_H * 0.38), Vector2(70.0, 50.0))

func do_kick() -> void:
	if not _can_start_attack(): return
	current_state   = State.KICK
	attack_duration = KICK_DURATION
	attack_timer    = 0.0
	can_attack      = false
	hit_landed      = false
	_position_hitbox(Vector2(CHAR_W * 0.5 + 45.0, -CHAR_H * 0.24), Vector2(90.0, 58.0))

func do_special() -> void:
	if not _can_start_attack(): return
	if special_meter < SPECIAL_COST: return
	special_meter   -= SPECIAL_COST
	current_state   = State.SPECIAL
	attack_duration = SPECIAL_DURATION
	attack_timer    = 0.0
	can_attack      = false
	hit_landed      = false
	_position_hitbox(Vector2(CHAR_W * 0.5 + 55.0, -CHAR_H * 0.5), Vector2(130.0, 90.0))

func queue_jump() -> void:
	if is_on_floor() and current_state != State.DEAD and current_state != State.HIT:
		jump_queued = true

func _can_start_attack() -> bool:
	return can_attack and current_state not in [State.HIT, State.DEAD]

func _position_hitbox(offset: Vector2, size: Vector2) -> void:
	if not attack_area or not attack_shape: return
	var dir := 1.0 if facing_right else -1.0
	attack_area.position = Vector2(offset.x * dir, offset.y)
	if attack_shape.shape is RectangleShape2D:
		(attack_shape.shape as RectangleShape2D).size = size

# ─── Damage Reception ─────────────────────────────────────────────────────────
func take_damage(amount: float, knockback_dir: float) -> void:
	if current_state == State.DEAD: return
	health        = max(0.0, health - amount)
	special_meter = min(MAX_SPECIAL, special_meter + amount * 0.4)
	took_damage.emit(amount)
	if health <= 0.0:
		_die()
	else:
		current_state  = State.HIT
		hit_stun_timer = HIT_STUN
		can_attack     = false
		velocity.x     = knockback_dir * 220.0
		velocity.y     = -130.0

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
