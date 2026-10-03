class_name Ship
extends Node2D

## W/S: prograde/retrograde. A/D: radial in/out. Shift: 10% thrust. R: reset.
## Planned maneuvers are flown automatically, each burn centered on its maneuver time.

## Longest stretch of game time one thrust step covers, in seconds. Keeps burns accurate at high sim speed.
const MAX_BURN_STEP := 0.5
const FINE_THRUST := 0.1
## Game seconds between prediction refreshes while coasting, so the encounter search window keeps moving forward.
const PREDICTION_REFRESH := 100.0
const LEG_COLORS: Array[Color] = [
	Color(0.4, 0.85, 1.0, 0.75),
	Color(1.0, 0.7, 0.3, 0.85),
	Color(0.8, 0.55, 1.0, 0.75),
]
## How visible the unplanned path stays while maneuvers are planned.
const DIMMED_ALPHA := 0.3

@export var home_body: CelestialBody
@export var trajectory_view: TrajectoryView
@export var periapsis_altitude := 100.0
@export var apoapsis_altitude := 400.0
## Engine acceleration in m/s².
@export var thrust_acceleration := 2.0
@export var color := Color(1.0, 0.85, 0.4)
@export var flame_color := Color(1.0, 0.5, 0.2)

## The body whose gravity the ship currently feels. `orbit` is relative to it.
var reference_body: CelestialBody
var orbit: Orbit
## Where the ship goes if nothing else is done. See Trajectory.predict for the patch format;
## patches here also carry "anchor_time" (see Maneuver.anchor_time).
var prediction: Array[Dictionary] = []
## Planned maneuvers in flight order. A burning maneuver always comes first.
var maneuvers: Array[Maneuver] = []
## The planned path, one prediction per stretch: plan[0] is `prediction`, and each later entry starts
## at a maneuver with its delta-v applied.
var plan: Array = []
## Set by the planner while the player is dragging a maneuver. Burns don't start mid-edit.
var maneuver_editing := false
var crashed := false
## Total speed change from burns so far, in m/s.
var delta_v_used := 0.0
## Manual engine command as (prograde, radial out), each -1..1. Zero when no keys are held.
var thrust := Vector2.ZERO
## World direction the engine pushed this frame, scaled by throttle. Zero when the engine is off.
var engine_output := Vector2.ZERO

var _last_time := 0.0
var _next_prediction_time := 0.0
var _crash_position := Vector2.ZERO


func _ready() -> void:
	reset()


func reset() -> void:
	reference_body = home_body
	var periapsis := home_body.radius + periapsis_altitude
	var semi_major_axis := periapsis + (apoapsis_altitude - periapsis_altitude) / 2.0
	var speed := sqrt(home_body.mu * (2.0 / periapsis - 1.0 / semi_major_axis))
	orbit = Orbit.from_state(home_body.mu, Vector2(periapsis, 0.0), Vector2(0.0, -speed), Sim.time)
	crashed = false
	delta_v_used = 0.0
	maneuvers = []
	_last_time = Sim.time
	_predict(Sim.time)


func add_maneuver(time: float) -> Maneuver:
	var maneuver := Maneuver.new()
	maneuver.time = time
	maneuvers.append(maneuver)
	update_plan()
	return maneuver


func remove_maneuver(maneuver: Maneuver) -> void:
	maneuvers.erase(maneuver)
	update_plan()


## Recomputes `plan` and each maneuver's place on it. Call after changing any maneuver.
func update_plan() -> void:
	plan = [prediction]
	maneuvers.sort_custom(func(a: Maneuver, b: Maneuver) -> bool:
		return a.burning if a.burning != b.burning else a.time < b.time)
	for maneuver in maneuvers:
		maneuver.valid = false
	if crashed:
		return

	for maneuver in maneuvers:
		var segment: Array[Dictionary] = plan.back()
		var patch := _patch_at(segment, maneuver.time)
		if patch.is_empty():
			break
		maneuver.valid = true
		maneuver.segment_index = plan.size() - 1
		maneuver.body = patch.body
		maneuver.orbit = patch.orbit
		maneuver.anchor_time = patch.anchor_time
		if maneuver.burning:
			continue
		var relative_position := maneuver.orbit.position_at(maneuver.time)
		var velocity := maneuver.orbit.velocity_at(maneuver.time)
		velocity += _local_to_world(maneuver.delta_v / 1000.0, relative_position, velocity)
		var after := Trajectory.predict(maneuver.body, Orbit.from_state(maneuver.body.mu, relative_position, velocity, maneuver.time), maneuver.time)
		_set_anchor_times(after, maneuver.anchor_time)
		plan.append(after)


## Where a maneuver sits and which way its prograde and radial-out axes point, in world space.
func maneuver_frame(maneuver: Maneuver) -> Dictionary:
	var relative_position := maneuver.orbit.position_at(maneuver.time)
	var velocity := maneuver.orbit.velocity_at(maneuver.time)
	return {
		"position": anchor_position(maneuver.body, maneuver.anchor_time) + relative_position,
		"prograde": _local_to_world(Vector2(1, 0), relative_position, velocity),
		"radial_out": _local_to_world(Vector2(0, 1), relative_position, velocity),
	}


## World position a body's orbits are drawn around. NAN anchor_time means its current position.
func anchor_position(body: CelestialBody, anchor_time: float) -> Vector2:
	return body.position_at(Sim.time if is_nan(anchor_time) else anchor_time)


## The drawn, clickable stretches of the planned path, in time order. Each is a Dictionary:
## body, orbit, anchor_time, from_time, to_time, patch (the prediction patch it comes from).
## A stretch ends at the next maneuver or where its patch ends.
func path_windows() -> Array[Dictionary]:
	var windows: Array[Dictionary] = []
	for k in plan.size():
		var limit: float = plan[k + 1][0].start_time if k + 1 < plan.size() else INF
		windows.append_array(_segment_windows(k, limit))
	return windows


## Stretches a maneuver can slide along: its own segment, up to the next maneuver.
func windows_for_moving(maneuver: Maneuver) -> Array[Dictionary]:
	var index := maneuvers.find(maneuver)
	var limit := INF
	if index + 1 < maneuvers.size() and maneuvers[index + 1].valid:
		limit = maneuvers[index + 1].time
	return _segment_windows(maneuver.segment_index, limit)


## Game seconds needed to change speed by delta_v (m/s) at full thrust.
func burn_duration(delta_v: float) -> float:
	return delta_v / thrust_acceleration


## The next encounter in a prediction: {"body", "time", "closest_approach"} (closest approach is an
## altitude in km), or an empty Dictionary if there is none.
func next_encounter(patches: Array) -> Dictionary:
	for i in patches.size() - 1:
		if patches[i].end == "encounter":
			var flyby: Dictionary = patches[i + 1]
			var body: CelestialBody = flyby.body
			return {
				"body": body,
				"time": patches[i].end_time,
				"closest_approach": flyby.orbit.periapsis() - body.radius,
			}
	return {}


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		reset()


func _process(_delta: float) -> void:
	var now := Sim.time
	thrust = Vector2.ZERO if crashed else _read_thrust_input()
	engine_output = Vector2.ZERO

	var orbit_changed := false
	if thrust != Vector2.ZERO:
		var command := thrust
		_burn(_last_time, now, func(relative_position: Vector2, velocity: Vector2) -> Vector2:
			return _local_to_world(command, relative_position, velocity))
		delta_v_used += thrust.length() * thrust_acceleration * (now - _last_time)
		orbit_changed = true
	if not maneuvers.is_empty() and not crashed and _fly_maneuver(_last_time, now):
		orbit_changed = true
	if orbit_changed:
		_predict(now)
	_last_time = now

	if not crashed:
		_follow_prediction(now)
		if now >= _next_prediction_time:
			_predict(now)
		var relative_position := orbit.position_at(now)
		if relative_position.length() <= reference_body.radius:
			crashed = true
			maneuvers = []
			update_plan()
			_crash_position = relative_position.normalized() * reference_body.radius

	var body_position := reference_body.position_at(now)
	if crashed:
		engine_output = Vector2.ZERO
		global_position = body_position + _crash_position
	else:
		var relative_position := orbit.position_at(now)
		var velocity := orbit.velocity_at(now)
		global_position = body_position + relative_position
		if thrust != Vector2.ZERO:
			engine_output += _local_to_world(thrust, relative_position, velocity)
		rotation = (velocity if engine_output == Vector2.ZERO else engine_output).angle()

	scale = Vector2.ONE / get_viewport().get_canvas_transform().get_scale().x
	_update_trajectory_view()
	queue_redraw()


func _draw() -> void:
	if engine_output != Vector2.ZERO:
		var length := 6.0 + 10.0 * minf(engine_output.length(), 1.0)
		draw_colored_polygon(PackedVector2Array([
			Vector2(-4, 3.5), Vector2(-4 - length, 0), Vector2(-4, -3.5),
		]), flame_color)
	draw_colored_polygon(PackedVector2Array([
		Vector2(10, 0), Vector2(-7, 7), Vector2(-3, 0), Vector2(-7, -7),
	]), color)


func _predict(time: float) -> void:
	prediction = Trajectory.predict(reference_body, orbit, time)
	_set_anchor_times(prediction, NAN)
	_next_prediction_time = time + PREDICTION_REFRESH
	update_plan()


## Orbits around a body the ship isn't in yet are drawn around where that body will be when the ship
## arrives. The first patch inherits the anchor of the stretch it continues.
func _set_anchor_times(patches: Array[Dictionary], first_anchor_time: float) -> void:
	for i in patches.size():
		var patch := patches[i]
		var body: CelestialBody = patch.body
		if i == 0:
			patch["anchor_time"] = first_anchor_time
		elif body == reference_body or body.parent_body == null:
			patch["anchor_time"] = NAN
		else:
			patch["anchor_time"] = patch.start_time


func _patch_at(patches: Array[Dictionary], time: float) -> Dictionary:
	for patch in patches:
		if time >= patch.start_time and time < patch.end_time:
			return patch
	return {}


func _segment_windows(k: int, limit: float) -> Array[Dictionary]:
	var windows: Array[Dictionary] = []
	var segment: Array[Dictionary] = plan[k]
	for i in segment.size():
		var patch := segment[i]
		var from_time: float = Sim.time if k == 0 and i == 0 else patch.start_time
		if from_time >= limit:
			break
		windows.append({
			"body": patch.body, "orbit": patch.orbit, "anchor_time": patch.anchor_time,
			"from_time": from_time, "to_time": minf(patch.end_time, limit), "patch": patch,
		})
	return windows


## Switches gravity at exactly the moments the prediction says, so the ship always does what was drawn.
func _follow_prediction(now: float) -> void:
	for i in 8:
		if prediction.is_empty():
			return
		var patch: Dictionary = prediction[0]
		if patch.next_body == null or patch.end_time > now:
			return
		orbit = Trajectory.change_frame(orbit, reference_body, patch.next_body, patch.end_time)
		reference_body = patch.next_body
		_predict(patch.end_time)


## Flies the part of the first maneuver's burn that falls between from_time and to_time.
## The burn holds its direction relative to prograde and radial (not fixed in space), which keeps
## long burns close to the plan. Returns true if the orbit changed.
func _fly_maneuver(from_time: float, to_time: float) -> bool:
	var maneuver := maneuvers[0]
	if not maneuver.burning:
		var start := maneuver.time - burn_duration(maneuver.delta_v.length()) / 2.0
		if to_time < start or maneuver_editing:
			return false
		_start_maneuver_burn(maneuver)
		from_time = maxf(from_time, start)

	var local_direction := maneuver.delta_v.normalized()
	var direction := func(relative_position: Vector2, velocity: Vector2) -> Vector2:
		return _local_to_world(local_direction, relative_position, velocity)
	var steps := maxi(1, ceili((to_time - from_time) / MAX_BURN_STEP))
	var step := (to_time - from_time) / steps
	var burned := false
	for i in steps:
		if _maneuver_burn_done(maneuver):
			break
		var duration := step if maneuver.energy_guided else minf(step, burn_duration(maneuver.remaining))
		var t := from_time + step * i
		_burn(t, t + duration, direction)
		maneuver.remaining -= duration * thrust_acceleration
		delta_v_used += duration * thrust_acceleration
		burned = true

	if burned:
		engine_output += direction.call(orbit.position_at(to_time), orbit.velocity_at(to_time))
	if _maneuver_burn_done(maneuver):
		maneuvers.erase(maneuver)
		update_plan()
	return burned


func _start_maneuver_burn(maneuver: Maneuver) -> void:
	var t := maneuver.time
	var relative_position := orbit.position_at(t)
	var velocity := orbit.velocity_at(t)
	velocity += _local_to_world(maneuver.delta_v / 1000.0, relative_position, velocity)
	maneuver.target_energy = _orbital_energy(Orbit.from_state(reference_body.mu, relative_position, velocity, t))
	maneuver.energy_guided = absf(maneuver.delta_v.x) >= absf(maneuver.delta_v.y)
	maneuver.remaining = maneuver.delta_v.length()
	maneuver.burning = true
	update_plan()


func _maneuver_burn_done(maneuver: Maneuver) -> bool:
	if not maneuver.energy_guided:
		return maneuver.remaining <= 1e-6
	var energy := _orbital_energy(orbit)
	var reached := energy >= maneuver.target_energy if maneuver.delta_v.x > 0.0 else energy <= maneuver.target_energy
	var over_budget := maneuver.remaining <= -0.5 * maneuver.delta_v.length()
	return reached or over_budget


func _orbital_energy(of_orbit: Orbit) -> float:
	return -of_orbit.mu / (2.0 * of_orbit.semi_major_axis)


func _read_thrust_input() -> Vector2:
	var command := Vector2(_key(KEY_W) - _key(KEY_S), _key(KEY_D) - _key(KEY_A))
	if command == Vector2.ZERO:
		return command
	return command.normalized() * (FINE_THRUST if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)


func _key(keycode: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(keycode) else 0.0


## Applies full thrust between the two times. `direction` maps (relative position, velocity) to a
## world-space thrust vector whose length is the throttle.
func _burn(from_time: float, to_time: float, direction: Callable) -> void:
	var steps := maxi(1, ceili((to_time - from_time) / MAX_BURN_STEP))
	var step := (to_time - from_time) / steps
	var acceleration := thrust_acceleration / 1000.0
	for i in steps:
		var t := from_time + step * (i + 0.5)
		var relative_position := orbit.position_at(t)
		var velocity := orbit.velocity_at(t)
		velocity += direction.call(relative_position, velocity) * acceleration * step
		orbit = Orbit.from_state(reference_body.mu, relative_position, velocity, t)


## Converts (prograde, radial out) into a world direction for the given orbital state.
func _local_to_world(local: Vector2, relative_position: Vector2, velocity: Vector2) -> Vector2:
	var prograde := velocity.normalized()
	var radial_out := prograde.orthogonal()
	if radial_out.dot(relative_position) < 0.0:
		radial_out = -radial_out
	return prograde * local.x + radial_out * local.y


func _update_trajectory_view() -> void:
	var lines: Array[Dictionary] = []
	var markers: Array[Dictionary] = []
	var ghosts: Array[Dictionary] = []
	if crashed:
		trajectory_view.show_contents(lines, markers, ghosts)
		return

	if plan.size() > 1:
		for window in _segment_windows(0, INF):
			var faded := LEG_COLORS[0]
			faded.a *= DIMMED_ALPHA
			lines.append({"points": _window_points(window), "color": faded})

	var leg := 0
	var previous_body: CelestialBody = null
	for window in path_windows():
		if previous_body != null and window.body != previous_body:
			leg += 1
		previous_body = window.body
		_add_window(window, LEG_COLORS[leg % LEG_COLORS.size()], lines, markers, ghosts)
	trajectory_view.show_contents(lines, markers, ghosts)


func _add_window(window: Dictionary, line_color: Color,
		lines: Array[Dictionary], markers: Array[Dictionary], ghosts: Array[Dictionary]) -> void:
	var body: CelestialBody = window.body
	var window_orbit: Orbit = window.orbit
	var patch: Dictionary = window.patch
	var from_time: float = window.from_time
	var to_time: float = window.to_time
	var anchor := anchor_position(body, window.anchor_time)

	lines.append({"points": _window_points(window), "color": line_color})

	if not is_nan(window.anchor_time) and window.anchor_time == patch.start_time and from_time == patch.start_time:
		ghosts.append({
			"position": anchor, "radius": body.radius,
			"sphere_of_influence": body.sphere_of_influence, "color": line_color,
		})

	for apsis in [[0.0, "Pe"], [PI, "Ap"]]:
		if apsis[1] == "Ap" and not window_orbit.is_elliptic():
			continue
		if window_orbit.next_time_at_true_anomaly(apsis[0], from_time) < to_time:
			var distance := window_orbit.position_at_true_anomaly(apsis[0]).length()
			markers.append({
				"position": anchor + window_orbit.position_at_true_anomaly(apsis[0]),
				"label": "%s %d km" % [apsis[1], roundi(distance - body.radius)],
				"color": line_color,
			})

	if to_time != patch.end_time:
		return
	var end_label := ""
	match patch.end:
		"impact":
			end_label = "Impact"
		"encounter":
			end_label = "%s encounter" % patch.next_body.name
		"escape":
			end_label = "Leaving %s" % body.name
	if end_label != "":
		markers.append({"position": anchor + window_orbit.position_at(to_time), "label": end_label, "color": line_color})


func _window_points(window: Dictionary) -> PackedVector2Array:
	var points := _orbit_points(window.orbit, window.from_time, window.to_time)
	var anchor := anchor_position(window.body, window.anchor_time)
	for p in points.size():
		points[p] += anchor
	return points


func _orbit_points(of_orbit: Orbit, from_time: float, to_time: float) -> PackedVector2Array:
	var from_nu := of_orbit.true_anomaly_at(from_time)
	if is_inf(to_time):
		if of_orbit.is_elliptic():
			return of_orbit.sample_points()
		var escape_nu := of_orbit.true_anomaly_at_radius(Trajectory.ESCAPE_RADIUS)
		return of_orbit.sample_arc(from_nu, escape_nu) if escape_nu > from_nu else PackedVector2Array()
	if of_orbit.is_elliptic() and to_time - from_time >= of_orbit.period():
		return of_orbit.sample_points()
	var to_nu := of_orbit.true_anomaly_at(to_time)
	if of_orbit.is_elliptic() and to_nu < from_nu:
		to_nu += TAU
	return of_orbit.sample_arc(from_nu, to_nu)
