class_name Ring
extends Node2D

## Circle outline that keeps the same on-screen thickness at any zoom level.

@export var radius := 8000.0
@export var color := Color(1.0, 1.0, 1.0, 0.2)
@export var screen_width := 1.5

var _zoom := 0.0


func _process(_delta: float) -> void:
	var zoom := get_viewport().get_canvas_transform().get_scale().x
	if zoom != _zoom:
		_zoom = zoom
		queue_redraw()


func _draw() -> void:
	if _zoom <= 0.0:
		return
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 512, color, screen_width / _zoom, true)
