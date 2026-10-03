extends Camera2D

## Scroll to zoom toward the cursor. Pan with right/middle mouse drag or arrow keys.
## F cycles which target the camera follows (panning offsets from it).

@export var min_zoom := 0.02
@export var max_zoom := 4.0
@export var zoom_step := 1.2
@export var zoom_smoothing := 14.0
## Screen pixels per second, so panning feels the same at every zoom level.
@export var pan_speed := 900.0
@export var focus_targets: Array[Node2D] = []

var _target_zoom := 1.0
var _dragging := false
var _focus_index := 0
var _pan_offset := Vector2.ZERO


func _ready() -> void:
	_target_zoom = zoom.x


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_zoom_by(zoom_step)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_zoom_by(1.0 / zoom_step)
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		_pan_offset -= event.relative / zoom.x
	elif event is InputEventMagnifyGesture:
		_zoom_by(event.factor)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F and not focus_targets.is_empty():
			_focus_index = (_focus_index + 1) % focus_targets.size()
			_pan_offset = Vector2.ZERO


## Name of the node the camera is following, for the HUD.
func focus_name() -> String:
	return focus_targets[_focus_index].name if not focus_targets.is_empty() else ""


func _process(delta: float) -> void:
	_update_zoom(delta)

	var direction := Vector2(
		float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_UP))
	)
	_pan_offset += direction.normalized() * pan_speed * delta / zoom.x
	position = _focus_position() + _pan_offset


func _focus_position() -> Vector2:
	return focus_targets[_focus_index].global_position if not focus_targets.is_empty() else Vector2.ZERO


func _zoom_by(factor: float) -> void:
	_target_zoom = clampf(_target_zoom * factor, min_zoom, max_zoom)


func _update_zoom(delta: float) -> void:
	var current := zoom.x
	if current == _target_zoom:
		return

	var t := 1.0 - exp(-zoom_smoothing * delta)
	var next := exp(lerpf(log(current), log(_target_zoom), t))
	if absf(next / _target_zoom - 1.0) < 0.001:
		next = _target_zoom

	var cursor := get_viewport().get_mouse_position() - get_viewport().get_visible_rect().size * 0.5
	var world_under_cursor := position + cursor / current
	zoom = Vector2(next, next)
	_pan_offset += world_under_cursor - cursor / next - position
