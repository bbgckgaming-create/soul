## GameArena.gd
## Root scene script — builds the entire game world programmatically.
extends Node2D

class_name GameArena

# ─── Child References ────────────────────────────────────────────────────────
var player:    Player   = null
var enemy:     Enemy    = null
var hud = null
var joystick = null
var ui_layer:  CanvasLayer     = null

# ✅ CORRECT CODE: Load scenes as resources (not as classes)
var hud_scene = load("res://scenes/HUD.tscn")
var virtual_joystick_scene = load("res://scenes/VirtualJoystick.tscn")

# Arena geometry
var vp:        Vector2  = Vector2.ZERO
var floor_y:   float    = 0.0

# Buttons
var btn_punch:   Button = null
var btn_kick:    Button = null
var btn_special: Button = null

# Restart state
var game_over_pending: bool = false

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	vp      = get_viewport_rect().size
	floor_y = vp.y - 160.0

	GameManager.start_game()

	_build_background()
	_build_stage()
	_build_fighters()
	_build_ui()

	hud.setup(vp)
	hud.update_round_display()

	GameManager.round_ended.connect(_on_round_ended)
	GameManager.game_over.connect(_on_game_over)

	_start_round()

# ─── Background ──────────────────────────────────────────────────────────────
func _build_background() -> void:
	var sky_top := ColorRect.new()
	sky_top.color    = Color(0.04, 0.04, 0.08)
	sky_top.size     = Vector2(vp.x, vp.y * 0.6)
	sky_top.position = Vector2.ZERO
	add_child(sky_top)

	var sky_bot := ColorRect.new()
	sky_bot.color    = Color(0.07, 0.05, 0.12)
	sky_bot.size     = Vector2(vp.x, vp.y * 0.4)
	sky_bot.position = Vector2(0.0, vp.y * 0.6)
	add_child(sky_bot)

# ─── Stage ───────────────────────────────────────────────────────────────────
func _build_stage() -> void:
	var floor_rect := ColorRect.new()
	floor_rect.color    = Color(0.13, 0.10, 0.18)
	floor_rect.size     = Vector2(vp.x, 160.0)
	floor_rect.position = Vector2(0.0, floor_y)
	add_child(floor_rect)

	var line := ColorRect.new()
	line.color    = Color(0.45, 0.30, 0.65, 0.6)
	line.size     = Vector2(vp.x, 3.0)
	line.position = Vector2(0.0, floor_y)
	add_child(line)

	# Static floor body
	var static_body := StaticBody2D.new()
	static_body.position = Vector2(0.0, floor_y)
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(vp.x * 2.0, 40.0)
	col.shape  = shape
	col.position = Vector2(vp.x * 0.5, 20.0)
	static_body.add_child(col)
	add_child(static_body)

	# Left wall
	var wall_l := StaticBody2D.new()
	var col_l := CollisionShape2D.new()
	var shape_l := RectangleShape2D.new()
	shape_l.size = Vector2(20.0, vp.y * 2.0)
	col_l.shape  = shape_l
	col_l.position = Vector2(0.0, 0.0)
	wall_l.add_child(col_l)
	wall_l.position = Vector2(-10.0, 0.0)
	add_child(wall_l)

	# Right wall
	var wall_r := StaticBody2D.new()
	var col_r := CollisionShape2D.new()
	var shape_r := RectangleShape2D.new()
	shape_r.size = Vector2(20.0, vp.y * 2.0)
	col_r.shape  = shape_r
	col_r.position = Vector2(0.0, 0.0)
	wall_r.add_child(col_r)
	wall_r.position = Vector2(vp.x + 10.0, 0.0)
	add_child(wall_r)

# ─── Fighters ────────────────────────────────────────────────────────────────
func _build_fighters() -> void:
	player = _create_fighter(true)  as Player
	enemy  = _create_fighter(false) as Enemy
	enemy.set_target(player)

func _create_fighter(is_player: bool) -> Fighter:
	var fighter: Fighter
	if is_player:
		fighter = load("res://scenes/player.tscn").instantiate()
	else:
		fighter = Enemy.new()

	# Main body collision shape
	var body_col := CollisionShape2D.new()
	var body_shape := RectangleShape2D.new()
	body_shape.size  = Vector2(Fighter.CHAR_W - 8.0, Fighter.CHAR_H)
	body_col.shape   = body_shape
	body_col.position = Vector2(0.0, -Fighter.CHAR_H * 0.5)
	fighter.add_child(body_col)

	# Sprite (colored rectangle)
	var sprite := ColorRect.new()
	sprite.name     = "Sprite"
	sprite.size     = Vector2(Fighter.CHAR_W, Fighter.CHAR_H)
	sprite.position = Vector2(-Fighter.CHAR_W * 0.5, -Fighter.CHAR_H)
	sprite.color    = Color(0.2, 0.55, 1.0) if is_player else Color(0.85, 0.15, 0.15)
	fighter.add_child(sprite)

	# Hurtbox (receives incoming hits)
	var hurtbox := Area2D.new()
	hurtbox.name        = "Hurtbox"
	hurtbox.collision_layer = 0b0010
	hurtbox.collision_mask  = 0b0001
	var hb_col := CollisionShape2D.new()
	var hb_shape := RectangleShape2D.new()
	hb_shape.size   = Vector2(Fighter.CHAR_W, Fighter.CHAR_H)
	hb_col.shape    = hb_shape
	hb_col.position = Vector2(0.0, -Fighter.CHAR_H * 0.5)
	hurtbox.add_child(hb_col)
	fighter.add_child(hurtbox)

	# Attack area (deals outgoing hits)
	var atk_area := Area2D.new()
	atk_area.name             = "AttackArea"
	atk_area.monitoring       = false
	atk_area.collision_layer  = 0b0001
	atk_area.collision_mask   = 0b0010
	var atk_col := CollisionShape2D.new()
	atk_col.name = "CollisionShape2D"
	var atk_shape := RectangleShape2D.new()
	atk_shape.size  = Vector2(60.0, 50.0)
	atk_col.shape   = atk_shape
	atk_area.add_child(atk_col)
	fighter.add_child(atk_area)

	add_child(fighter)
	return fighter

# ─── UI / Controls ────────────────────────────────────────────────────────────
func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 10
	add_child(ui_layer)

	# HUD
	hud = hud_scene.instantiate()
	ui_layer.add_child(hud)

	# Controls panel
	var ctrl_panel := Control.new()
	ctrl_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(ctrl_panel)

	# Virtual Joystick (bottom-left)
	joystick = virtual_joystick_scene.instantiate()
	joystick.name     = "Joystick"
	joystick.position = Vector2(20.0, vp.y - 220.0)
	joystick.size     = Vector2(180.0, 180.0)

	var base_panel := Panel.new()
	base_panel.name = "Base"
	base_panel.size = Vector2(160.0, 160.0)
	base_panel.position = Vector2(10.0, 10.0)
	var base_style := StyleBoxFlat.new()
	base_style.bg_color         = Color(0.15, 0.15, 0.2, 0.55)
	base_style.corner_radius_top_left     = 80
	base_style.corner_radius_top_right    = 80
	base_style.corner_radius_bottom_left  = 80
	base_style.corner_radius_bottom_right = 80
	base_style.border_color = Color(0.5, 0.4, 0.7, 0.6)
	base_style.set_border_width_all(2)
	base_panel.add_theme_stylebox_override("panel", base_style)

	var knob := Panel.new()
	knob.name = "Knob"
	knob.size = Vector2(62.0, 62.0)
	knob.position = Vector2(49.0, 49.0)
	var knob_style := StyleBoxFlat.new()
	knob_style.bg_color         = Color(0.55, 0.42, 0.85, 0.9)
	knob_style.corner_radius_top_left     = 31
	knob_style.corner_radius_top_right    = 31
	knob_style.corner_radius_bottom_left  = 31
	knob_style.corner_radius_bottom_right = 31
	knob.add_theme_stylebox_override("panel", knob_style)
	base_panel.add_child(knob)

	joystick.add_child(base_panel)
	joystick.direction_changed.connect(player.set_joystick)
	ctrl_panel.add_child(joystick)

	# Action buttons (bottom-right)
	var btn_size := Vector2(90.0, 90.0)
	var btn_margin := 18.0
	var btn_base_x := vp.x - btn_size.x - btn_margin
	var btn_base_y := vp.y - btn_size.y - btn_margin

	btn_punch   = _make_button("P", Color(0.2, 0.7, 1.0),
		Vector2(btn_base_x - (btn_size.x + btn_margin), btn_base_y + 30.0),
		btn_size, ctrl_panel)
	btn_kick    = _make_button("K", Color(0.95, 0.45, 0.1),
		Vector2(btn_base_x, btn_base_y + 30.0),
		btn_size, ctrl_panel)
	btn_special = _make_button("SP", Color(0.7, 0.2, 1.0),
		Vector2(btn_base_x - (btn_size.x + btn_margin) * 0.5, btn_base_y - btn_size.y - btn_margin * 0.5),
		btn_size, ctrl_panel)

	btn_punch.button_down.connect(player.input_punch)
	btn_kick.button_down.connect(player.input_kick)
	btn_special.button_down.connect(player.input_special)

func _make_button(label_text: String, color: Color, pos: Vector2, sz: Vector2, parent: Control) -> Button:
	var btn := Button.new()
	btn.position = pos
	btn.size     = sz
	btn.text     = label_text

	var normal := StyleBoxFlat.new()
	normal.bg_color         = Color(color.r, color.g, color.b, 0.75)
	normal.corner_radius_top_left     = int(sz.x * 0.5)
	normal.corner_radius_top_right    = int(sz.x * 0.5)
	normal.corner_radius_bottom_left  = int(sz.x * 0.5)
	normal.corner_radius_bottom_right = int(sz.x * 0.5)
	normal.border_color = Color(1, 1, 1, 0.35)
	normal.set_border_width_all(2)

	var pressed := StyleBoxFlat.new()
	pressed.bg_color         = Color(color.r * 1.3, color.g * 1.3, color.b * 1.3, 0.95)
	pressed.corner_radius_top_left     = int(sz.x * 0.5)
	pressed.corner_radius_top_right    = int(sz.x * 0.5)
	pressed.corner_radius_bottom_left  = int(sz.x * 0.5)
	pressed.corner_radius_bottom_right = int(sz.x * 0.5)

	btn.add_theme_stylebox_override("normal",  normal)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("hover",   normal)
	btn.add_theme_font_size_override("font_size", 22)
	btn.add_theme_color_override("font_color", Color.WHITE)

	parent.add_child(btn)
	return btn

# ─── Round Management ─────────────────────────────────────────────────────────
func _start_round() -> void:
	player.position = Vector2(vp.x * 0.28, floor_y)
	player.reset()
	player.facing_right = true

	enemy.position = Vector2(vp.x * 0.72, floor_y)
	enemy.reset()
	enemy.facing_right = false

	GameManager.game_active = false
	game_over_pending = false

	if hud.result_label:
		hud.result_label.visible = false

	_do_countdown()

func _do_countdown() -> void:
	if hud.result_label:
		hud.result_label.visible = true
		hud.result_label.text    = "Round %d" % GameManager.current_round
		await get_tree().create_timer(1.0).timeout
		hud.result_label.text = "FIGHT!"
		await get_tree().create_timer(0.7).timeout
		hud.result_label.visible = false
		GameManager.game_active  = true

func _on_round_ended(_winner: int) -> void:
	if game_over_pending:
		return
	await get_tree().create_timer(2.8).timeout
	if not game_over_pending:
		_start_round()
		hud.update_round_display()

func _on_game_over(_winner: int) -> void:
	game_over_pending = true
	await get_tree().create_timer(3.5).timeout
	GameManager.start_game()
	hud.update_round_display()
	_start_round()
