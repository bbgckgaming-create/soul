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

# Character dimensions
const CHAR_W: float = 80.0
const CHAR_H: float = 158.0

# Physics / gameplay node refs
var attack_area:  Area2D            = null
var hurtbox_area: Area2D            = null
var attack_shape: CollisionShape2D  = null

# Visual nodes — 2-segment articulated limbs + head/torso details
var torso_node:  ColorRect = null
var head_node:   ColorRect = null
var hair_node:   ColorRect = null
var eye_node:    ColorRect = null
var pupil_node:  ColorRect = null
var belt_node:   ColorRect = null
var arm_fu_node: ColorRect = null   # front arm upper  (shoulder → elbow)
var arm_fl_node: ColorRect = null   # front arm lower  (elbow   → fist)
var arm_bu_node: ColorRect = null   # back  arm upper
var arm_bl_node: ColorRect = null   # back  arm lower
var leg_fu_node: ColorRect = null   # front leg upper  (hip → knee)
var leg_fl_node: ColorRect = null   # front leg lower  (knee → foot)
var leg_bu_node: ColorRect = null   # back  leg upper
var leg_bl_node: ColorRect = null   # back  leg lower

# Set by GameArena so each fighter always faces the other
var opponent: Fighter = null

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	torso_node  = get_node_or_null("Torso")
	head_node   = get_node_or_null("Head")
	hair_node   = get_node_or_null("Hair")
	eye_node    = get_node_or_null("Eye")
	pupil_node  = get_node_or_null("Pupil")
	belt_node   = get_node_or_null("Belt")
	arm_fu_node = get_node_or_null("FArmU")
	arm_fl_node = get_node_or_null("FArmL")
	arm_bu_node = get_node_or_null("BArmU")
	arm_bl_node = get_node_or_null("BArmL")
	leg_fu_node = get_node_or_null("FLegU")
	leg_fl_node = get_node_or_null("FLegL")
	leg_bu_node = get_node_or_null("BLegU")
	leg_bl_node = get_node_or_null("BLegL")
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
	# Immediately push fresh health/special values to the HUD
	_report_to_manager()

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
			var open:  float = attack_duration * HITBOX_OPEN
			var close: float = attack_duration * HITBOX_CLOSE
			hitbox_active = (attack_timer >= open and attack_timer < close)

			# Poll overlapping areas every frame — more reliable than area_entered
			if hitbox_active and not hit_landed and attack_area:
				attack_area.monitoring = true
				for area in attack_area.get_overlapping_areas():
					var target := area.get_parent() as Fighter
					if target and target != self:
						hit_landed    = true
						var dir: float = sign(target.position.x - position.x)
						target.take_damage(get_current_damage(), dir)
						special_meter = min(MAX_SPECIAL, special_meter + get_current_damage() * 0.9)
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

	# Always face the opponent (so attacks always go the correct direction)
	if opponent and current_state != State.DEAD:
		facing_right = position.x < opponent.position.x

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

# ─── Segment Helper ───────────────────────────────────────────────────────────
# Places one ColorRect limb segment with its pivot at the top-centre.
#   angle = 0   → segment hangs straight down.
#   angle > 0   → tilts clockwise  (= forward when facing right).
#   angle < 0   → tilts counter-clockwise (= backward when facing right).
# Returns the tip position so the next segment can be chained from it.
func _place_segment(node: ColorRect, px: float, py: float,
		angle: float, length: float, width: float) -> Vector2:
	var tip: Vector2 = Vector2(px + sin(angle) * length, py + cos(angle) * length)
	if not node:
		return tip
	node.size         = Vector2(width, length)
	node.pivot_offset = Vector2(width * 0.5, 0.0)
	node.position     = Vector2(px - width * 0.5, py)
	node.rotation     = angle
	return tip

# ─── Visual Update ────────────────────────────────────────────────────────────
func _update_visual() -> void:
	if not torso_node:
		return

	var sc:  float = CROUCH_SCALE if current_state == State.CROUCH else 1.0
	var bh:  float = CHAR_H * sc
	var dir: float = 1.0 if facing_right else -1.0

	# ── Proportional section heights ──────────────────────────────────────────
	var head_h:  float = bh * 0.316
	var hair_h:  float = bh * 0.089
	var torso_h: float = bh * 0.329
	var leg_h:   float = bh - head_h - torso_h
	var arm_h:   float = torso_h * 0.96

	var ul_len: float = leg_h * 0.54   # upper-leg segment length
	var ll_len: float = leg_h * 0.52   # lower-leg segment length
	var ua_len: float = arm_h * 0.52   # upper-arm segment length
	var la_len: float = arm_h * 0.52   # lower-arm segment length

	# Fixed widths (don't squish during crouch)
	const TW: float = 38.0   # torso width
	const AW: float = 17.0   # arm segment width
	const LW: float = 17.0   # leg segment width
	const HW: float = 50.0   # head width

	# ── Y anchors (feet = 0, upward is negative) ──────────────────────────────
	var y_hip:  float = -leg_h                          # top of legs / bottom of torso
	var y_tors: float = -leg_h - torso_h               # top of torso
	var y_shl:  float = y_tors + torso_h * 0.08        # shoulder level
	var y_hair: float = y_tors - head_h                # very top of hair
	var y_face: float = y_hair + hair_h                # top of face skin

	# ── X anchors (direction-aware: positive dir = facing-right side) ─────────
	var shl_fx: float = dir *  (TW * 0.5 + 1.0)   # front shoulder pivot X
	var shl_bx: float = dir * -(TW * 0.5 + 1.0)   # back  shoulder pivot X
	var hip_fx: float = dir *  8.0                 # front hip pivot X  (wider stance)
	var hip_bx: float = dir * -8.0                 # back  hip pivot X  (wider stance)

	# ── Colour palette based on state ─────────────────────────────────────────
	var col:      Color
	var col_dark: Color
	var col_hi:   Color
	match current_state:
		State.HIT:
			col      = Color(1.0, 0.25, 0.25) if fighter_id == 0 else Color(1.0, 0.45, 0.1)
			col_dark = col.darkened(0.22)
			col_hi   = col.lightened(0.15)
		State.PUNCH, State.KICK, State.SPECIAL:
			col      = Color(0.55, 0.85, 1.0) if fighter_id == 0 else Color(1.0, 0.45, 0.45)
			col_dark = col.darkened(0.22)
			col_hi   = col.lightened(0.15)
		_:
			if fighter_id == 0:
				col      = Color(0.20, 0.55, 1.00)
				col_dark = Color(0.14, 0.38, 0.82)
				col_hi   = Color(0.32, 0.68, 1.00)
			else:
				col      = Color(0.85, 0.15, 0.15)
				col_dark = Color(0.62, 0.09, 0.09)
				col_hi   = Color(0.96, 0.26, 0.26)

	# ── MK-style animation curve: fast snap → freeze at peak → controlled retract ─
	# Three distinct phases replace the old symmetric sin() arc:
	#   0%–35%  Extend  — ease-out power curve (explosive snap to peak)
	#   35%–62% Hold    — frozen at full extension (hit is readable / "frame data")
	#   62%–100% Retract — ease-in pull-back (deliberate, weighted recovery)
	var progress: float = clamp(attack_timer / max(attack_duration, 0.001), 0.0, 1.0)
	var ef: float = 0.0
	if progress < 0.35:
		ef = 1.0 - pow(1.0 - progress / 0.35, 2.8)   # ease-out: explosive start
	elif progress < 0.62:
		ef = 1.0                                        # hold: frozen at peak
	else:
		ef = 1.0 - pow((progress - 0.62) / 0.38, 1.6) # ease-in: weighted retract
	ef = clamp(ef, 0.0, 1.0)

	# ── Guard stance ──────────────────────────────────────────────────────────
	# RULE: all angles stay between 0.0 and ~1.6 so both segments always point
	# FORWARD (never wrap behind the elbow/knee), keeping limbs visually joined.
	#
	# Arms: upper arm reaches forward at ~80°; forearm then bends DOWNWARD from
	# the elbow (la_f < ua_f), so the arm has a natural hook-shaped droop.
	# At punch peak both angles converge to ~1.57 (horizontal) = straight jab.
	#
	# Legs: very slight spread so feet stay close together — no bowlegging.
	# Front arm: classic boxing L-guard.
	#   ua_f ≈ 1.10 → elbow reaches forward and slightly down.
	#   la_f ≈ 2.00 → forearm angles up from elbow, fist near chin/shoulder height.
	# Back forearm is hidden (see placement section below).
	# Legs: both thighs lean toward the opponent; lower leg follows at a slightly
	# smaller angle for a gentle natural knee bend (no S-curve).
	# Guard stance — angles match user sketch:
	# Front arm: upper arm pushes forward ~52°, forearm droops forward-down ~32°.
	# Small angle difference (20°) means the two rects meet cleanly; an elbow-cap
	# square (arm_bl_node, repurposed) fills any remaining corner gap.
	var ua_f: float =  0.90   # front upper arm  — 52° forward from vertical
	var la_f: float =  0.55   # front lower arm  — 32° forward, forearm angles down
	var ua_b: float = -0.18   # back  upper arm  — slightly behind torso
	var la_b: float =  0.00   # back  lower arm  — repurposed as elbow cap; value unused
	# Legs — from the sketch: front thigh sweeps forward, shin nearly vertical
	# so the knee visibly pokes forward. Back thigh sweeps backward, same logic.
	var ul_f: float =  0.55   # front upper leg  — thigh sweeps toward opponent
	var ll_f: float =  0.05   # front lower leg  — shin nearly vertical, knee pokes fwd
	var ul_b: float = -0.48   # back  upper leg  — thigh sweeps away from opponent
	var ll_b: float =  0.05   # back  lower leg  — shin nearly vertical, knee pokes back

	var torso_rot: float = 0.0

	# ── Attack animations ──────────────────────────────────────────────────────
	match current_state:
		State.PUNCH:
			# Guard → horizontal jab.
			# ua_f: 1.10 → 1.57 (+0.47), la_f: 0.68 → 1.57 (+0.89)
			ua_f      += ef * 0.47    # upper arm drives to horizontal
			la_f      += ef * 0.89    # forearm straightens to match
			ua_b      -= ef * 0.20    # back arm pulls back (weight transfer)
			torso_rot  = ef * 0.24    # body commits hard into the punch

		State.KICK:
			# Both leg segments swing upward together until near-horizontal = high kick.
			ul_f      += ef * 1.35    # thigh: 0.22 → 1.57 (horizontal)
			ll_f      += ef * 1.45    # shin:  0.12 → 1.57 (leg fully extended)
			ua_f      -= ef * 0.15    # front arm drops slightly for balance
			la_f      -= ef * 0.12    # forearm opens slightly with the lean
			torso_rot  = -(ef * 0.20) # body rocks back on the kick

		State.SPECIAL:
			# Front arm unfolds to jab; back upper arm sweeps forward for surge.
			ua_f      += ef * 0.47    # front upper arm drives to horizontal
			la_f      += ef * 0.89    # front forearm straightens to match
			ua_b      += ef * 1.55    # back upper arm sweeps from behind → front
			torso_rot  = ef * 0.15
			col_hi     = Color(0.90, 0.40, 1.00, 0.95)  # purple energy glow
			col_dark   = Color(0.70, 0.28, 1.00, 0.80)

	# ── Torso (leans with torso_rot) ──────────────────────────────────────────
	torso_node.size         = Vector2(TW, torso_h)
	torso_node.position     = Vector2(-TW * 0.5, y_tors)
	torso_node.pivot_offset = Vector2(TW * 0.5, torso_h * 0.1)
	torso_node.rotation     = dir * torso_rot
	torso_node.color        = col

	# ── Belt (follows torso lean) ──────────────────────────────────────────────
	if belt_node:
		belt_node.size         = Vector2(TW, max(5.0, 7.0 * sc))
		belt_node.position     = Vector2(-TW * 0.5, y_tors + torso_h * 0.70)
		belt_node.pivot_offset = Vector2(TW * 0.5, 0.0)
		belt_node.rotation     = dir * torso_rot
		belt_node.color        = Color(0.10, 0.08, 0.30) if fighter_id == 0 else Color(0.30, 0.05, 0.05)

	# ── Hair ──────────────────────────────────────────────────────────────────
	if hair_node:
		hair_node.size     = Vector2(HW, hair_h)
		hair_node.position = Vector2(-HW * 0.5, y_hair)
		hair_node.rotation = 0.0
		hair_node.color    = Color(0.12, 0.07, 0.02) if fighter_id == 0 else Color(0.68, 0.08, 0.04)

	# ── Head / Face ───────────────────────────────────────────────────────────
	var face_h: float = head_h - hair_h
	if head_node:
		head_node.size     = Vector2(HW, face_h)
		head_node.position = Vector2(-HW * 0.5, y_face)
		head_node.rotation = 0.0
		head_node.color    = Color(0.95, 0.78, 0.60)

	if eye_node:
		var ex: float = 6.0 if facing_right else -20.0
		eye_node.size     = Vector2(14.0, max(6.0, face_h * 0.28))
		eye_node.position = Vector2(ex, y_face + face_h * 0.42)
		eye_node.rotation = 0.0
		eye_node.color    = Color.WHITE

	if pupil_node:
		var epx: float = 13.0 if facing_right else -20.0
		pupil_node.size     = Vector2(7.0, max(6.0, face_h * 0.28))
		pupil_node.position = Vector2(epx, y_face + face_h * 0.42)
		pupil_node.rotation = 0.0
		pupil_node.color    = Color(0.05, 0.03, 0.01)

	# ── Back leg (behind everything) ──────────────────────────────────────────
	if leg_bu_node:
		leg_bu_node.color = col_dark
	if leg_bl_node:
		leg_bl_node.color = col_dark
	var bknee: Vector2 = _place_segment(leg_bu_node, hip_bx, y_hip, dir * ul_b, ul_len, LW)
	_place_segment(leg_bl_node, bknee.x, bknee.y, dir * ll_b, ll_len, LW)

	# ── Back arm — upper segment only; forearm hidden for cleaner silhouette ────
	if arm_bu_node:
		arm_bu_node.color = col_dark
	if arm_bl_node:
		arm_bl_node.size = Vector2.ZERO   # forearm hidden intentionally
	_place_segment(arm_bu_node, shl_bx, y_shl, dir * ua_b, ua_len, AW)

	# ── Front leg ─────────────────────────────────────────────────────────────
	if leg_fu_node:
		leg_fu_node.color = col
	if leg_fl_node:
		leg_fl_node.color = col
	var fknee: Vector2 = _place_segment(leg_fu_node, hip_fx, y_hip, dir * ul_f, ul_len, LW)
	_place_segment(leg_fl_node, fknee.x, fknee.y, dir * ll_f, ll_len, LW)

	# ── Front arm (topmost layer) ──────────────────────────────────────────────
	if arm_fu_node:
		arm_fu_node.color = col_hi
	if arm_fl_node:
		arm_fl_node.color = col_hi
	var felbow: Vector2 = _place_segment(arm_fu_node, shl_fx, y_shl, dir * ua_f, ua_len, AW)
	# Small overlap to ensure the two segments always meet flush at the elbow.
	var arm_overlap: float = 4.0
	var elbow_ox: float = sin(dir * ua_f) * arm_overlap
	var elbow_oy: float = cos(dir * ua_f) * arm_overlap
	_place_segment(arm_fl_node, felbow.x - elbow_ox, felbow.y - elbow_oy, dir * la_f, la_len + arm_overlap, AW)

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

func _position_hitbox(offset: Vector2, sz: Vector2) -> void:
	if not attack_area or not attack_shape: return
	var dir: float = 1.0 if facing_right else -1.0
	attack_area.position = Vector2(offset.x * dir, offset.y)
	if attack_shape.shape is RectangleShape2D:
		(attack_shape.shape as RectangleShape2D).size = sz

# ─── Damage Reception ─────────────────────────────────────────────────────────
func take_damage(amount: float, knockback_dir: float) -> void:
	if current_state == State.DEAD: return
	health        = max(0.0, health - amount)
	special_meter = min(MAX_SPECIAL, special_meter + amount * 1.2)
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
