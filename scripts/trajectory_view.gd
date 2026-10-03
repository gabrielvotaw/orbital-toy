class_name TrajectoryView
extends Node2D

## Draws predicted trajectories, labeled markers, and "ghost" bodies at encounter positions,
## all at a constant on-screen size. Must sit at the world origin: everything is in world coordinates.

@export var screen_width := 1.5
@export var marker_font_size := 14

## Each: {"points": PackedVector2Array, "color": Color}
var _lines: Array[Dictionary] = []
## Each: {"position": Vector2, "label": String, "color": Color}
var _markers: Array[Dictionary] = []
## Each: {"position": Vector2, "radius": float, "sphere_of_influence": float, "color": Color}
var _ghosts: Array[Dictionary] = []


func show_contents(lines: Array[Dictionary], markers: Array[Dictionary], ghosts: Array[Dictionary]) -> void:
	_lines = lines
	_markers = markers
	_ghosts = ghosts
	queue_redraw()


func _draw() -> void:
	var zoom := get_viewport().get_canvas_transform().get_scale().x
	var width := screen_width / zoom

	for ghost in _ghosts:
		draw_circle(ghost.position, ghost.radius, ghost.color, false, width, true)
		var faded: Color = ghost.color
		faded.a *= 0.5
		draw_arc(ghost.position, ghost.sphere_of_influence, 0.0, TAU, 128, faded, width, true)

	for line in _lines:
		if line.points.size() >= 2:
			draw_polyline(line.points, line.color, width, true)

	var font := ThemeDB.fallback_font
	for marker in _markers:
		draw_set_transform(marker.position, 0.0, Vector2.ONE / zoom)
		draw_circle(Vector2.ZERO, 3.5, marker.color, true, -1.0, true)
		draw_string(font, Vector2(7, -5), marker.label, HORIZONTAL_ALIGNMENT_LEFT, -1, marker_font_size, marker.color)
	draw_set_transform(Vector2.ZERO)
