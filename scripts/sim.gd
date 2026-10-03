extends Node

## Simulation clock, available everywhere as `Sim`. Space pauses. Comma/Period change speed (dev tool).

## Game seconds that pass per real second at 1x speed.
const BASE_TIME_SCALE := 100.0
const SPEEDS := [0.25, 0.5, 1.0, 2.0, 4.0, 8.0]

## Game seconds since the simulation started.
var time := 0.0
var paused := false
var speed: float:
	get:
		return SPEEDS[_speed_index]

var _speed_index := 2


func _process(delta: float) -> void:
	if not paused:
		time += delta * BASE_TIME_SCALE * speed


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_SPACE:
				paused = not paused
			KEY_PERIOD:
				_speed_index = mini(_speed_index + 1, SPEEDS.size() - 1)
			KEY_COMMA:
				_speed_index = maxi(_speed_index - 1, 0)
