class_name ManeuverPlanner
extends Node2D

## Left-click anywhere on the planned path to add a maneuver: on any leg, and after other maneuvers.
## Click a node to select it. Drag the selected node's handles to set its burn (Shift: fine control),
## or drag the node to slide it along the path. X or Delete removes the selected node.
## Must sit at the world origin: it draws in world coordinates.

## How close the mouse must be to grab something, in screen pixels.
const PICK_RADIUS := 10.0
## Distance from the node to each handle, in screen pixels.
const HANDLE_DISTANCE := 50.0
const PICK_SAMPLES := 360
## Dragging d pixels changes delta-v by |d| + DRAG_GROWTH·d² m/s, so small drags are precise and big drags are fast.
const DRAG_GROWTH := 0.02
const FINE_DRAG := 0.1
const NODE_COLOR := Color(1.0, 0.85, 0.4)
const FONT_SIZE := 13
const HANDLES := [
	{"axis": Vector2(1, 0), "label": "pro", "color": Color(0.55, 1.0, 0.4)},
	{"axis": Vector2(-1, 0), "label": "retro", "color": Color(0.55, 1.0, 0.4)},
	{"axis": Vector2(0, 1), "label": "out", "color": Color(0.35, 0.8, 1.0)},
	{"axis": Vector2(0, -1), "label": "in", "color": Color(0.35, 0.8, 1.0)},
]

enum Drag { NONE, NODE, HANDLE }

@export var ship: Ship

var _selected: Maneuver
var _drag := Drag.NONE
var _drag_axis := Vector2.ZERO
var _drag_screen_direction := Vector2.ZERO
var _drag_start_mouse := Vector2.ZERO
var _drag_start_delta_v := Vector2.ZERO
## {"time", "position", "distance"} of the path point under the mouse, or empty.
var _hover := {}


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			_drag = Drag.NONE
		elif _start_drag(event.position):
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _drag != Drag.NONE:
		_continue_drag(event.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		if (event.physical_keycode == KEY_X or event.physical_keycode == KEY_DELETE) and _selected:
			ship.remove_maneuver(_selected)
			_selected = null


func _process(_delta: float) -> void:
	if _selected and not ship.maneuvers.has(_selected):
		_selected = null
	ship.maneuver_editing = _drag != Drag.NONE

	_hover = {}
	var mouse := get_viewport().get_mouse_position()
	if not ship.crashed and _drag == Drag.NONE and _node_at(mouse) == null and _handle_at(mouse).is_empty():
		_hover = _pick(mouse, ship.path_windows(), PICK_RADIUS)
	queue_redraw()


func _start_drag(mouse: Vector2) -> bool:
	if ship.crashed:
		return false

	var handle := _handle_at(mouse)
	if not handle.is_empty():
		_drag = Drag.HANDLE
		_drag_axis = handle.axis
		_drag_screen_direction = handle.direction
		_drag_start_mouse = mouse
		_drag_start_delta_v = _selected.delta_v
		return true

	var node := _node_at(mouse)
	if node:
		_selected = node
		_drag = Drag.NONE if node.burning else Drag.NODE
		return true

	var pick := _pick(mouse, ship.path_windows(), PICK_RADIUS)
	if pick.is_empty():
		return false
	_selected = ship.add_maneuver(pick.time)
	_drag = Drag.NODE
	return true


func _continue_drag(mouse: Vector2) -> void:
	if _selected == null or _selected.burning or not ship.maneuvers.has(_selected):
		_drag = Drag.NONE
		return
	match _drag:
		Drag.NODE:
			var pick := _pick(mouse, ship.windows_for_moving(_selected), INF)
			if not pick.is_empty():
				_selected.time = pick.time
				ship.update_plan()
		Drag.HANDLE:
			var d := (mouse - _drag_start_mouse).dot(_drag_screen_direction)
			var amount := signf(d) * (absf(d) + DRAG_GROWTH * d * d)
			if Input.is_physical_key_pressed(KEY_SHIFT):
				amount *= FINE_DRAG
			_selected.delta_v = _drag_start_delta_v + _drag_axis * amount
			ship.update_plan()


func _node_at(mouse: Vector2) -> Maneuver:
	for maneuver in ship.maneuvers:
		if maneuver.valid and mouse.distance_to(_to_screen(ship.maneuver_frame(maneuver).position)) < PICK_RADIUS:
			return maneuver
	return null


## {"axis", "direction"} of the selected node's handle under the mouse, or empty.
func _handle_at(mouse: Vector2) -> Dictionary:
	if _selected == null or not _selected.valid or _selected.burning:
		return {}
	var frame := ship.maneuver_frame(_selected)
	var node_screen := _to_screen(frame.position)
	for handle in HANDLES:
		var direction := _handle_direction(frame, handle.axis)
		if mouse.distance_to(node_screen + direction * HANDLE_DISTANCE) < PICK_RADIUS:
			return {"axis": handle.axis, "direction": direction}
	return {}


## The path point closest to the mouse across the given windows (see Ship.path_windows), as
## {"time", "position", "distance"}, or empty if nothing is within max_distance screen pixels.
func _pick(mouse: Vector2, windows: Array[Dictionary], max_distance: float) -> Dictionary:
	var best := {}
	var best_distance := max_distance
	for window in windows:
		var result := _pick_in_window(mouse, window, best_distance)
		if not result.is_empty():
			best = result
			best_distance = result.distance
	return best


func _pick_in_window(mouse: Vector2, window: Dictionary, max_distance: float) -> Dictionary:
	var orbit: Orbit = window.orbit
	var from_time: float = window.from_time
	var to_time: float = window.to_time
	var from_nu := orbit.true_anomaly_at(from_time)
	var to_nu: float
	if orbit.is_elliptic() and (is_inf(to_time) or to_time - from_time >= orbit.period()):
		to_nu = from_nu + TAU
	elif is_inf(to_time):
		to_nu = orbit.true_anomaly_at_radius(Trajectory.ESCAPE_RADIUS)
		if is_nan(to_nu) or to_nu <= from_nu:
			return {}
	else:
		to_nu = orbit.true_anomaly_at(to_time)
		if orbit.is_elliptic() and to_nu < from_nu:
			to_nu += TAU

	var anchor := ship.anchor_position(window.body, window.anchor_time)
	var screen_distance := func(nu: float) -> float:
		return mouse.distance_to(_to_screen(anchor + orbit.position_at_true_anomaly(nu)))

	var step := (to_nu - from_nu) / PICK_SAMPLES
	var best_nu := NAN
	var best_distance := max_distance
	for i in PICK_SAMPLES + 1:
		var nu := from_nu + step * i
		var distance: float = screen_distance.call(nu)
		if distance < best_distance:
			best_distance = distance
			best_nu = nu
	if is_nan(best_nu):
		return {}

	# Refine between the neighboring samples so the result doesn't depend on where the samples
	# fall (they shift every frame as the ship moves, which made the pick jitter).
	var low := maxf(best_nu - step, from_nu)
	var high := minf(best_nu + step, to_nu)
	for i in 30:
		var a := lerpf(low, high, 1.0 / 3.0)
		var b := lerpf(low, high, 2.0 / 3.0)
		if screen_distance.call(a) < screen_distance.call(b):
			high = b
		else:
			low = a
	var nu := (low + high) / 2.0
	return {
		"time": orbit.next_time_at_true_anomaly(nu, from_time),
		"position": anchor + orbit.position_at_true_anomaly(nu),
		"distance": screen_distance.call(nu),
	}


func _handle_direction(frame: Dictionary, axis: Vector2) -> Vector2:
	return frame.prograde * axis.x + frame.radial_out * axis.y


func _to_screen(world_position: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world_position


func _draw() -> void:
	var zoom := get_viewport().get_canvas_transform().get_scale().x
	var font := ThemeDB.fallback_font

	if not _hover.is_empty():
		draw_set_transform(_hover.position, 0.0, Vector2.ONE / zoom)
		draw_circle(Vector2.ZERO, 6.0, NODE_COLOR, false, 1.5, true)
		draw_string(font, Vector2(10, -8), "Click to add maneuver", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, NODE_COLOR)

	if not ship.crashed:
		for maneuver in ship.maneuvers:
			if not maneuver.valid:
				continue
			var frame := ship.maneuver_frame(maneuver)
			var selected := maneuver == _selected
			draw_set_transform(frame.position, 0.0, Vector2.ONE / zoom)
			if selected and not maneuver.burning:
				for handle in HANDLES:
					var end: Vector2 = _handle_direction(frame, handle.axis) * HANDLE_DISTANCE
					var faded: Color = handle.color
					faded.a = 0.4
					draw_line(Vector2.ZERO, end, faded, 1.5, true)
					draw_circle(end, 6.0, handle.color, true, -1.0, true)
					draw_string(font, end + Vector2(8, 4), handle.label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 2, handle.color)
			draw_circle(Vector2.ZERO, 7.0, NODE_COLOR, false, 3.0 if selected else 1.5, true)
			var label := "%d m/s left" % roundi(maneuver.remaining) if maneuver.burning else "%d m/s" % roundi(maneuver.delta_v.length())
			draw_string(font, Vector2(10, -10), label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, NODE_COLOR)

	draw_set_transform(Vector2.ZERO)
