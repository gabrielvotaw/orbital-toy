extends Node

## Run from the project folder: godot --headless --path . res://tests/run_tests.tscn
## Runs as a scene (not --script) so autoloads like Sim exist.

const SUITES := [
	preload("res://tests/test_orbit.gd"),
	preload("res://tests/test_trajectory.gd"),
	preload("res://tests/test_maneuver.gd"),
]


func _ready() -> void:
	var failures := 0
	for suite in SUITES:
		print("== %s" % suite.resource_path.get_file())
		failures += suite.new().run(self)
	print("ALL PASSED" if failures == 0 else "%d FAILED" % failures)
	get_tree().quit(1 if failures > 0 else 0)
