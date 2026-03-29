## VirtualJoystick.gd
## On-screen analog stick for mobile touch input.
extends Control

signal direction_changed(direction: Vector2)

@export var dead_zone:  float = 18.0
@export var max_radius: float = 65.0

var _touch_id:   int    = -1
var _center:     Vector2 = Vector2.ZERO
var _direction:  Vector2 = Vector2.ZERO

var base_circle: Control = null
var knob_circle: Control = null

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	_center = size * 0.5
	base_circle = get_node_or_null("Base")
	knob_circle = get_node_or_null("Base/Knob")

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_id == -1:
			if get_global_rect().has_point(event.position):
				_touch_id = event.index
				_update(event.position)
		elif not event.pressed and event.index == _touch_id:
			_release()

	elif event is InputEventScreenDrag:
		if event.index == _touch_id:
			_update(event.position)

func _update(touch_global: Vector2) -> void:
	var local: Vector2 = touch_global - global_position - _center
	var dist:  float   = local.length()

	if dist < dead_zone:
		_direction = Vector2.ZERO
		_move_knob(Vector2.ZERO)
	else:
		var clamped: Vector2 = local.normalized() * min(dist, max_radius)
		_direction = clamped / max_radius
		_move_knob(clamped)

	direction_changed.emit(_direction)

func _release() -> void:
	_touch_id  = -1
	_direction = Vector2.ZERO
	_move_knob(Vector2.ZERO)
	direction_changed.emit(Vector2.ZERO)

func _move_knob(offset: Vector2) -> void:
	if knob_circle:
		knob_circle.position = _center + offset - knob_circle.size * 0.5

func get_direction() -> Vector2:
	return _direction
