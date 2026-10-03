extends RefCounted

const MU := 3531.6

var _failures := 0


## Runs every test and returns the number of failures.
func run(_host: Node) -> int:
	_test_circular_orbit_does_not_drift()
	_test_apsides_match_construction()
	_test_round_trip_elliptic()
	_test_round_trip_clockwise()
	_test_round_trip_hyperbolic()
	_test_energy_is_conserved()
	_test_matches_numerical_integration()
	_test_true_anomaly_at_radius()
	return _failures


func _test_circular_orbit_does_not_drift() -> void:
	var r := 700.0
	var orbit := Orbit.from_state(MU, Vector2(r, 0), Vector2(0, -sqrt(MU / r)), 0.0)
	var start := orbit.position_at(0.0)
	var after := orbit.position_at(orbit.period() * 1000.0)
	_check("circular orbit returns to start after 1000 orbits", start.distance_to(after) < 1e-3)
	_check("circular orbit keeps its radius", absf(orbit.position_at(12345.6).length() - r) < 1e-3)


func _test_apsides_match_construction() -> void:
	var periapsis := 700.0
	var apoapsis := 1000.0
	var a := (periapsis + apoapsis) / 2.0
	var orbit := Orbit.from_state(MU, Vector2(periapsis, 0), Vector2(0, -sqrt(MU * (2.0 / periapsis - 1.0 / a))), 0.0)
	_check("periapsis matches", absf(orbit.periapsis() - periapsis) < 1e-3)
	_check("apoapsis matches", absf(orbit.apoapsis() - apoapsis) < 1e-3)
	_check("apoapsis reached after half an orbit", absf(orbit.position_at(orbit.period() / 2.0).length() - apoapsis) < 1e-3)


func _test_round_trip_elliptic() -> void:
	_check_round_trip("elliptic round trip", Orbit.from_state(MU, Vector2(800, 150), Vector2(-0.4, -2.3), 10.0))


func _test_round_trip_clockwise() -> void:
	_check_round_trip("clockwise round trip", Orbit.from_state(MU, Vector2(800, 150), Vector2(0.4, 2.3), 10.0))


func _test_round_trip_hyperbolic() -> void:
	var r := 700.0
	var orbit := Orbit.from_state(MU, Vector2(r, 0), Vector2(0, -1.5 * sqrt(2.0 * MU / r)), 0.0)
	_check("hyperbolic orbit is not elliptic", not orbit.is_elliptic())
	_check_round_trip("hyperbolic round trip", orbit)


func _test_energy_is_conserved() -> void:
	var orbit := Orbit.from_state(MU, Vector2(700, 0), Vector2(0.3, -2.6), 0.0)
	var expected := -MU / (2.0 * orbit.semi_major_axis)
	var ok := true
	for i in 20:
		var t := i * 397.0
		var energy := orbit.velocity_at(t).length_squared() / 2.0 - MU / orbit.position_at(t).length()
		ok = ok and absf(energy - expected) < 1e-5
	_check("orbital energy is constant", ok)


func _test_matches_numerical_integration() -> void:
	var position := Vector2(700, 0)
	var velocity := Vector2(0.2, -2.5)
	var orbit := Orbit.from_state(MU, position, velocity, 0.0)

	var x := float(position.x)
	var y := float(position.y)
	var vx := float(velocity.x)
	var vy := float(velocity.y)
	var dt := 0.25
	var steps := 8000
	for i in steps:
		var k1 := _acceleration(x, y)
		var k2 := _acceleration(x + vx * dt / 2, y + vy * dt / 2)
		var k3 := _acceleration(x + (vx + k1.x * dt / 2) * dt / 2, y + (vy + k1.y * dt / 2) * dt / 2)
		var k4 := _acceleration(x + (vx + k2.x * dt / 2) * dt, y + (vy + k2.y * dt / 2) * dt)
		x += dt * (vx + dt / 6 * (k1.x + k2.x + k3.x))
		y += dt * (vy + dt / 6 * (k1.y + k2.y + k3.y))
		vx += dt / 6 * (k1.x + 2 * k2.x + 2 * k3.x + k4.x)
		vy += dt / 6 * (k1.y + 2 * k2.y + 2 * k3.y + k4.y)

	var predicted := orbit.position_at(steps * dt)
	_check("matches step-by-step simulation", predicted.distance_to(Vector2(x, y)) < 0.05)


func _test_true_anomaly_at_radius() -> void:
	var periapsis := 500.0
	var apoapsis := 1000.0
	var a := (periapsis + apoapsis) / 2.0
	var orbit := Orbit.from_state(MU, Vector2(periapsis, 0), Vector2(0, -sqrt(MU * (2.0 / periapsis - 1.0 / a))), 0.0)
	var nu := orbit.true_anomaly_at_radius(600.0)
	_check("finds where the orbit crosses a radius", absf(orbit.position_at_true_anomaly(nu).length() - 600.0) < 1e-3)
	_check("crossing is symmetric", absf(orbit.position_at_true_anomaly(-nu).length() - 600.0) < 1e-3)
	_check("no crossing beyond apoapsis", is_nan(orbit.true_anomaly_at_radius(1200.0)))


func _acceleration(x: float, y: float) -> Vector2:
	var r := sqrt(x * x + y * y)
	var k := -MU / (r * r * r)
	return Vector2(k * x, k * y)


func _check_round_trip(name: String, orbit: Orbit) -> void:
	var t := 777.0
	var rebuilt := Orbit.from_state(MU, orbit.position_at(t), orbit.velocity_at(t), t)
	var later := t + 1234.5
	_check(name, orbit.position_at(later).distance_to(rebuilt.position_at(later)) < 0.05)


func _check(name: String, passed: bool) -> void:
	print(("PASS  " if passed else "FAIL  ") + name)
	if not passed:
		_failures += 1
