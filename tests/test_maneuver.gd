extends RefCounted

var _failures := 0


## Runs every test and returns the number of failures.
func run(host: Node) -> int:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	host.add_child(main)
	var ship: Ship = main.get_node("Ship")
	var planner: ManeuverPlanner = main.get_node("ManeuverPlanner")
	var pale: CelestialBody = main.get_node("Pale")

	_test_orbit_picking_is_stable(ship, planner)
	_test_plan_applies_delta_v(ship)
	_test_executed_burn_matches_plan(ship)
	_test_long_burn_stays_close_to_plan(ship)
	_test_maneuver_on_future_leg(ship, pale)
	_test_chained_transfer_and_capture(ship, pale)

	host.remove_child(main)
	main.free()
	return _failures


func _test_orbit_picking_is_stable(ship: Ship, planner: ManeuverPlanner) -> void:
	ship.reset()
	var start := Sim.time
	var anchor := ship.reference_body.position_at(start)
	var mouse := planner._to_screen(anchor + ship.orbit.position_at(start + ship.orbit.period() * 0.4)) + Vector2(3, 2)
	var picks: Array[Vector2] = []
	for i in 10:
		Sim.time = start + i * 3.7
		ship.update_plan()
		picks.append(planner._pick(mouse, ship.path_windows(), ManeuverPlanner.PICK_RADIUS).position)
	Sim.time = start
	var spread := 0.0
	for pick in picks:
		spread = maxf(spread, planner._to_screen(pick).distance_to(planner._to_screen(picks[0])))
	_check("picked orbit point stays put while the ship moves (spread %.3f px)" % spread, spread < 0.05)


func _test_plan_applies_delta_v(ship: Ship) -> void:
	ship.reset()
	var t := Sim.time + ship.orbit.period() / 2.0
	var maneuver := ship.add_maneuver(t)
	maneuver.delta_v = Vector2(100, 0)
	ship.update_plan()
	var planned: Orbit = ship.plan[1][0].orbit
	var expected_speed := ship.orbit.velocity_at(t).length() + 0.1
	_check("plan adds prograde delta-v at the maneuver time", absf(planned.velocity_at(t).length() - expected_speed) < 1e-4)
	_check("prograde burn at apoapsis raises periapsis", planned.periapsis() > ship.orbit.periapsis() + 50.0)


func _test_executed_burn_matches_plan(ship: Ship) -> void:
	ship.reset()
	var start := Sim.time
	var maneuver := ship.add_maneuver(start + ship.orbit.period() / 2.0)
	maneuver.delta_v = Vector2(100, 20)
	ship.update_plan()
	var planned: Orbit = ship.plan[1][0].orbit
	_fly_all(ship, start, start + ship.orbit.period())
	_check("maneuver finishes and is removed", ship.maneuvers.is_empty())
	_check("maneuver uses about its planned delta-v", absf(ship.delta_v_used - Vector2(100, 20).length()) < 3.0)
	_check("finished burn lands close to the planned periapsis", absf(ship.orbit.periapsis() - planned.periapsis()) < 2.0)
	_check("finished burn lands close to the planned apoapsis", absf(ship.orbit.apoapsis() - planned.apoapsis()) < 2.0)


func _test_long_burn_stays_close_to_plan(ship: Ship) -> void:
	ship.reset()
	var start := Sim.time
	var maneuver := ship.add_maneuver(start + ship.orbit.period() / 2.0)
	maneuver.delta_v = Vector2(830, 0)
	ship.update_plan()
	var planned: Orbit = ship.plan[1][0].orbit
	_fly_all(ship, start, start + 2.0 * ship.orbit.period())
	var error := absf(ship.orbit.apoapsis() - planned.apoapsis()) / planned.apoapsis()
	_check("long transfer burn lands within 5% of the planned apoapsis", error < 0.05)


func _test_maneuver_on_future_leg(ship: Ship, pale: CelestialBody) -> void:
	ship.reset()
	_put_on_transfer(ship, pale)
	_check("transfer orbit is headed for Pale", ship.next_encounter(ship.prediction).body == pale)
	var flyby: Dictionary = ship.prediction[1]
	var capture := _add_capture(ship, flyby)
	_check("maneuver on a future leg is placed around Pale", capture.valid and capture.body == pale)
	_check("capture burn on a future leg ends in orbit around Pale", _ends_in_orbit_around(ship, pale))


func _test_chained_transfer_and_capture(ship: Ship, pale: CelestialBody) -> void:
	ship.reset()
	var transfer := _find_transfer(ship, pale)
	_check("found a transfer maneuver from low orbit", transfer != null)
	if transfer == null:
		return
	var flyby: Dictionary = ship.plan[1][1]
	var capture := _add_capture(ship, flyby)
	_check("second maneuver lies on the first maneuver's planned path", capture.valid and capture.segment_index == 1 and capture.body == pale)
	_check("chained transfer and capture end in orbit around Pale", _ends_in_orbit_around(ship, pale))


func _ends_in_orbit_around(ship: Ship, body: CelestialBody) -> bool:
	var final_patch: Dictionary = ship.plan.back()[0]
	return final_patch.body == body and final_patch.orbit.is_elliptic() and final_patch.orbit.apoapsis() < body.sphere_of_influence


## Retrograde burn at the flyby's closest approach that leaves a circular orbit.
func _add_capture(ship: Ship, flyby: Dictionary) -> Maneuver:
	var flyby_orbit: Orbit = flyby.orbit
	var periapsis_time := flyby_orbit.next_time_at_true_anomaly(0.0, flyby.start_time)
	var speed := flyby_orbit.velocity_at(periapsis_time).length()
	var circular_speed := sqrt(flyby_orbit.mu / flyby_orbit.periapsis())
	var capture := ship.add_maneuver(periapsis_time)
	capture.delta_v = Vector2(-(speed - circular_speed) * 1000.0, 0)
	ship.update_plan()
	return capture


func _put_on_transfer(ship: Ship, pale: CelestialBody) -> void:
	var now := Sim.time
	var mu := ship.home_body.mu
	var a := (700.0 + 7300.0) / 2.0
	var transfer_time := PI * sqrt(a * a * a / mu)
	var direction := Vector2.from_angle(pale.orbit.position_at(now + transfer_time).angle() + PI)
	var speed := sqrt(mu * (2.0 / 700.0 - 1.0 / a))
	ship.orbit = Orbit.from_state(mu, direction * 700.0, direction.orthogonal() * speed, now)
	ship._predict(now)


func _find_transfer(ship: Ship, pale: CelestialBody) -> Maneuver:
	var now := Sim.time
	var period := ship.orbit.period()
	for step in 130:
		var maneuver := ship.add_maneuver(now + 300.0 + step * (period - 400.0) / 130.0)
		for dv in range(700, 900, 10):
			maneuver.delta_v = Vector2(dv, 0)
			ship.update_plan()
			var encounter := ship.next_encounter(ship.plan[1])
			if not encounter.is_empty() and encounter.body == pale and encounter.closest_approach > 100.0:
				return maneuver
		ship.remove_maneuver(maneuver)
	return null


func _fly_all(ship: Ship, from_time: float, to_time: float) -> void:
	var t := from_time
	while not ship.maneuvers.is_empty() and t < to_time:
		ship._fly_maneuver(t, t + 1.0)
		t += 1.0


func _check(name: String, passed: bool) -> void:
	print(("PASS  " if passed else "FAIL  ") + name)
	if not passed:
		_failures += 1
