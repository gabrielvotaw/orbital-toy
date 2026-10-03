extends RefCounted

const HAVEN_MU := 3531.6
const PALE_ORBIT := 8000.0

var _failures := 0
var _haven: CelestialBody
var _pale: CelestialBody


## Runs every test and returns the number of failures.
func run(_host: Node) -> int:
	_test_next_time_at_true_anomaly()
	_test_low_orbit_has_no_events()
	_test_transfer_finds_pale_encounter()
	_test_frame_change_preserves_world_state()
	_test_flyby_leaves_at_sphere_edge()
	_test_impact_is_detected()
	_free_system()
	return _failures


func _free_system() -> void:
	if _haven:
		_pale.free()
		_haven.free()
		_haven = null
		_pale = null


func _build_system(pale_start_angle: float) -> void:
	_free_system()
	_haven = CelestialBody.new()
	_haven.radius = 600.0
	_haven.mu = HAVEN_MU
	_pale = CelestialBody.new()
	_pale.radius = 200.0
	_pale.mu = 65.138
	_pale.parent_body = _haven
	_pale.orbit_radius = PALE_ORBIT
	_pale.orbit_start_angle = pale_start_angle
	_pale.setup()


## A transfer from a 700 km circular orbit whose apoapsis is `apoapsis_offset` km beyond Pale's orbit,
## timed so Pale is right there when the ship reaches apoapsis.
func _transfer_orbit(apoapsis_offset: float) -> Orbit:
	var start_radius := 700.0
	var a := (start_radius + PALE_ORBIT + apoapsis_offset) / 2.0
	var transfer_time := PI * sqrt(a * a * a / HAVEN_MU)
	var pale_rate := sqrt(HAVEN_MU / pow(PALE_ORBIT, 3))
	_build_system(rad_to_deg(-PI + pale_rate * transfer_time))
	var speed := sqrt(HAVEN_MU * (2.0 / start_radius - 1.0 / a))
	return Orbit.from_state(HAVEN_MU, Vector2(start_radius, 0), Vector2(0, -speed), 0.0)


func _test_next_time_at_true_anomaly() -> void:
	var orbit := Orbit.from_state(HAVEN_MU, Vector2(700, 0), Vector2(0.2, -2.6), 0.0)
	var time := orbit.next_time_at_true_anomaly(2.0, 500.0)
	_check("next time lands on the requested true anomaly", absf(orbit.true_anomaly_at(time) - 2.0) < 1e-6)
	_check("next time is within one period", time >= 500.0 and time < 500.0 + orbit.period())


func _test_low_orbit_has_no_events() -> void:
	_build_system(90.0)
	var r := 700.0
	var orbit := Orbit.from_state(HAVEN_MU, Vector2(r, 0), Vector2(0, -sqrt(HAVEN_MU / r)), 0.0)
	var patches := Trajectory.predict(_haven, orbit, 0.0)
	_check("low orbit: single patch with no events", patches.size() == 1 and patches[0].end == "none")


func _test_transfer_finds_pale_encounter() -> void:
	var patches := Trajectory.predict(_haven, _transfer_orbit(-700.0), 0.0)
	_check("transfer: first patch ends in an encounter", patches[0].end == "encounter" and patches[0].next_body == _pale)
	_check("transfer: second patch is around Pale", patches.size() >= 2 and patches[1].body == _pale)
	var t: float = patches[0].end_time
	var distance: float = (patches[0].orbit.position_at(t) - _pale.orbit.position_at(t)).length()
	_check("transfer: encounter happens at the sphere of influence edge", absf(distance - (_pale.sphere_of_influence - Trajectory.ENTRY_MARGIN)) < 0.05)


func _test_frame_change_preserves_world_state() -> void:
	var orbit := _transfer_orbit(-700.0)
	var t: float = Trajectory.predict(_haven, orbit, 0.0)[0].end_time
	var around_pale := Trajectory.change_frame(orbit, _haven, _pale, t)
	var world_before := orbit.position_at(t)
	var world_after := _pale.position_at(t) + around_pale.position_at(t)
	var velocity_before := orbit.velocity_at(t)
	var velocity_after := _pale.velocity_at(t) + around_pale.velocity_at(t)
	_check("frame change keeps position", world_before.distance_to(world_after) < 0.01)
	_check("frame change keeps velocity", velocity_before.distance_to(velocity_after) < 1e-5)


func _test_flyby_leaves_at_sphere_edge() -> void:
	var patches := Trajectory.predict(_haven, _transfer_orbit(-700.0), 0.0)
	var flyby: Dictionary = patches[1]
	_check("flyby: misses Pale and leaves its sphere of influence", flyby.end == "escape" and flyby.next_body == _haven)
	var exit_distance: float = flyby.orbit.position_at(flyby.end_time).length()
	_check("flyby: exits exactly at the sphere of influence", absf(exit_distance - _pale.sphere_of_influence) < 0.01)
	_check("flyby: continues around Haven afterward", patches.size() == 3 and patches[2].body == _haven)


func _test_impact_is_detected() -> void:
	var patches := Trajectory.predict(_haven, _transfer_orbit(0.0), 0.0)
	_check("dead-center transfer hits Pale", patches.size() == 2 and patches[1].end == "impact")


func _check(name: String, passed: bool) -> void:
	print(("PASS  " if passed else "FAIL  ") + name)
	if not passed:
		_failures += 1
