## HUD.gd
## Heads-up display: health bars, special meters, round info, result text.
extends CanvasLayer

# ─── Node References ──────────────────────────────────────────────────────────
var player_hp_bar:   ProgressBar = null
var enemy_hp_bar:    ProgressBar = null
var player_sp_bar:   ProgressBar = null
var enemy_sp_bar:    ProgressBar = null
var round_label:     Label       = null
var result_label:    Label       = null
var win_dots_player: HBoxContainer = null
var win_dots_enemy:  HBoxContainer = null

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	GameManager.health_changed.connect(_on_health_changed)
	GameManager.special_changed.connect(_on_special_changed)
	GameManager.round_ended.connect(_on_round_ended)
	GameManager.game_over.connect(_on_game_over)

# ─────────────────────────────────────────────────────────────────────────────
func setup(vp: Vector2) -> void:
	var margin: float = 16.0
	var bar_h:  float = 18.0
	var bar_w:  float = (vp.x - margin * 3.0) * 0.5

	# ── Player health bar (left) ──
	player_hp_bar = _make_bar(
		Vector2(margin, margin),
		Vector2(bar_w, bar_h),
		Color(0.15, 0.85, 0.35),
		true
	)

	# ── Enemy health bar (right) ──
	enemy_hp_bar = _make_bar(
		Vector2(margin * 2.0 + bar_w, margin),
		Vector2(bar_w, bar_h),
		Color(0.9, 0.2, 0.2),
		false
	)

	# ── Player special bar ──
	player_sp_bar = _make_bar(
		Vector2(margin, margin + bar_h + 4.0),
		Vector2(bar_w, 8.0),
		Color(0.3, 0.6, 1.0),
		true
	)

	# ── Enemy special bar ──
	enemy_sp_bar = _make_bar(
		Vector2(margin * 2.0 + bar_w, margin + bar_h + 4.0),
		Vector2(bar_w, 8.0),
		Color(1.0, 0.5, 0.1),
		false
	)

	# ── Round label ──
	round_label = Label.new()
	round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	round_label.add_theme_font_size_override("font_size", 22)
	round_label.add_theme_color_override("font_color", Color.WHITE)
	round_label.position  = Vector2(vp.x * 0.5 - 60.0, margin)
	round_label.size      = Vector2(120.0, 30.0)
	round_label.text      = "Round 1"
	add_child(round_label)

	# ── Win dots ──
	win_dots_player = _make_win_dots(Vector2(margin, margin + bar_h + 16.0))
	win_dots_enemy  = _make_win_dots(Vector2(margin * 2.0 + bar_w, margin + bar_h + 16.0))

	# ── Result label ──
	result_label = Label.new()
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size", 48)
	result_label.add_theme_color_override("font_color", Color.WHITE)
	result_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	result_label.add_theme_constant_override("shadow_offset_x", 3)
	result_label.add_theme_constant_override("shadow_offset_y", 3)
	result_label.position = Vector2(0.0, vp.y * 0.35)
	result_label.size     = Vector2(vp.x, 80.0)
	result_label.visible  = false
	add_child(result_label)

func show_announcement(text: String, duration: float = 2.0) -> void:
	if result_label:
		result_label.text    = text
		result_label.visible = true
		await get_tree().create_timer(duration).timeout
		result_label.visible = false

func update_round_display() -> void:
	if round_label:
		round_label.text = "Round %d" % GameManager.current_round
	_refresh_win_dots()

# ─── Signal Handlers ──────────────────────────────────────────────────────────
func _on_health_changed(fighter_id: int, health: float, max_health: float) -> void:
	var pct := (health / max_health) * 100.0
	if fighter_id == 0 and player_hp_bar:
		player_hp_bar.value = pct
		_tint_bar(player_hp_bar, pct)
	elif fighter_id == 1 and enemy_hp_bar:
		enemy_hp_bar.value = pct
		_tint_bar(enemy_hp_bar, pct)

func _on_special_changed(fighter_id: int, special: float) -> void:
	if fighter_id == 0 and player_sp_bar:
		player_sp_bar.value = special
	elif fighter_id == 1 and enemy_sp_bar:
		enemy_sp_bar.value = special

func _on_round_ended(winner: int) -> void:
	var msg := "YOU WIN!" if winner == 0 else "ENEMY WINS!"
	show_announcement(msg, 2.5)
	update_round_display()

func _on_game_over(winner: int) -> void:
	var msg := "VICTORY!" if winner == 0 else "DEFEAT"
	if result_label:
		result_label.text    = msg
		result_label.visible = true

# ─── Builder Helpers ──────────────────────────────────────────────────────────
func _make_bar(pos: Vector2, sz: Vector2, color: Color, align_left: bool) -> ProgressBar:
	var bg := ColorRect.new()
	bg.position = pos
	bg.size     = sz
	bg.color    = Color(0.1, 0.1, 0.1, 0.8)
	add_child(bg)

	var border := ColorRect.new()
	border.position = pos - Vector2(1, 1)
	border.size     = sz + Vector2(2, 2)
	border.color    = Color(1, 1, 1, 0.4)
	border.z_index  = -1
	add_child(border)

	var bar := ProgressBar.new()
	bar.position = pos
	bar.size     = sz
	bar.max_value = 100.0
	bar.value     = 100.0
	bar.show_percentage = false

	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = color
	bar.add_theme_stylebox_override("fill", fill_style)

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.08, 0.08, 0.08, 0.0)
	bar.add_theme_stylebox_override("background", bg_style)

	if not align_left:
		bar.fill_mode = ProgressBar.FILL_END_TO_BEGIN

	add_child(bar)
	return bar

func _tint_bar(bar: ProgressBar, pct: float) -> void:
	var style := bar.get_theme_stylebox("fill") as StyleBoxFlat
	if not style:
		return
	if pct > 50.0:
		style.bg_color = Color(0.15, 0.85, 0.35)
	elif pct > 25.0:
		style.bg_color = Color(0.95, 0.8, 0.1)
	else:
		style.bg_color = Color(0.9, 0.2, 0.15)

func _make_win_dots(pos: Vector2) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.position = pos
	hbox.add_theme_constant_override("separation", 6)
	for i in range(GameManager.ROUNDS_TO_WIN):
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(14, 14)
		dot.color = Color(0.25, 0.25, 0.25)
		hbox.add_child(dot)
	add_child(hbox)
	return hbox

func _refresh_win_dots() -> void:
	_fill_dots(win_dots_player, GameManager.player_wins, Color(0.2, 0.85, 0.4))
	_fill_dots(win_dots_enemy,  GameManager.enemy_wins,  Color(0.9, 0.2, 0.2))

func _fill_dots(container: HBoxContainer, wins: int, color: Color) -> void:
	if not container:
		return
	for i in container.get_child_count():
		var dot := container.get_child(i) as ColorRect
		if dot:
			dot.color = color if i < wins else Color(0.25, 0.25, 0.25)
