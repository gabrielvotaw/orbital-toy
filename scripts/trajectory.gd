class_name Trajectory
extends RefCounted

## Patched-conic prediction: follows an orbit forward through sphere-of-influence changes.
## A prediction is a list of patches, each a Dictionary:
##   body, orbit, start_time, end_time (INF if nothing happens),
##   end ("encounter", "escape", "impact" or "none"), next_body (body after an encounter or escape).

const MAX_PATCHES := 3
## Escape trajectories from the root body are followed out to this distance, in km.
const ESCAPE_RADIUS := 30000.0
## Entering a sphere of influence means getting this far inside it (km), so float error
## right after leaving one can't immediately count as entering it again.
const ENTRY_MARGIN := 0.1
const MIN_SEARCH_STEP := 2.0
const MAX_SEARCH_STEPS := 2000


static func predict(body: CelestialBody, orbit: Orbit, start_time: float) -> Array[Dictionary]:
	var patches: Array[Dictionary] = []
	var time := start_time
	for i in MAX_PATCHES:
		var patch := {
			"body": body, "orbit": orbit, "start_time": time,
			"end_time": INF, "end": "none", "next_body": null,
		}
		patches.append(patch)

		var impact := impact_time(body, orbit, time)
		var exit := exit_time(body, orbit, time)
		var entry := find_entry(body, orbit, time, minf(horizon(orbit, time), minf(impact, exit)))

		if not entry.is_empty():
			patch["end_time"] = entry.time
			patch["end"] = "encounter"
			patch["next_body"] = entry.body
		elif impact < INF and impact <= exit:
			patch["end_time"] = impact
			patch["end"] = "impact"
			return patches
		elif exit < INF:
			patch["end_time"] = exit
			patch["end"] = "escape"
			patch["next_body"] = body.parent_body
		else:
			return patches

		orbit = change_frame(orbit, body, patch.next_body, patch.end_time)
		body = patch.next_body
		time = patch.end_time
	return patches


## Re-expresses an orbit relative to a neighboring body (a satellite or the parent) at the given time.
static func change_frame(orbit: Orbit, from_body: CelestialBody, to_body: CelestialBody, time: float) -> Orbit:
	var position := orbit.position_at(time)
	var velocity := orbit.velocity_at(time)
	if to_body.parent_body == from_body:
		position -= to_body.orbit.position_at(time)
		velocity -= to_body.orbit.velocity_at(time)
	elif from_body.parent_body == to_body:
		position += from_body.orbit.position_at(time)
		velocity += from_body.orbit.velocity_at(time)
	return Orbit.from_state(to_body.mu, position, velocity, time)


## How far ahead to look for encounters: one full orbit, or until reaching ESCAPE_RADIUS.
static func horizon(orbit: Orbit, time: float) -> float:
	if orbit.is_elliptic():
		return time + orbit.period()
	var nu := orbit.true_anomaly_at_radius(ESCAPE_RADIUS)
	return INF if is_nan(nu) else orbit.next_time_at_true_anomaly(nu, time)


static func impact_time(body: CelestialBody, orbit: Orbit, time: float) -> float:
	var nu := orbit.true_anomaly_at_radius(body.radius)
	return INF if is_nan(nu) else orbit.next_time_at_true_anomaly(-nu, time)


static func exit_time(body: CelestialBody, orbit: Orbit, time: float) -> float:
	if body.parent_body == null:
		return INF
	var nu := orbit.true_anomaly_at_radius(body.sphere_of_influence)
	return INF if is_nan(nu) else orbit.next_time_at_true_anomaly(nu, time)


## Earliest entry into any satellite's sphere of influence between from_time and to_time.
## Returns {"time", "body"}, or an empty Dictionary if there is none.
static func find_entry(body: CelestialBody, orbit: Orbit, from_time: float, to_time: float) -> Dictionary:
	var result := {}
	var earliest := to_time
	for satellite in body.satellites:
		var time := _first_entry_time(orbit, satellite, from_time, earliest)
		if time < earliest:
			earliest = time
			result = {"time": time, "body": satellite}
	return result


static func _first_entry_time(orbit: Orbit, satellite: CelestialBody, from_time: float, to_time: float) -> float:
	var entry_radius := satellite.sphere_of_influence - ENTRY_MARGIN
	var satellite_orbit := satellite.orbit
	if orbit.apoapsis() < satellite_orbit.periapsis() - entry_radius:
		return INF
	if orbit.periapsis() > satellite_orbit.apoapsis() + entry_radius:
		return INF

	# The distance can't shrink faster than this, so stepping by (distance - entry_radius) / max_closing_speed
	# can never jump over the sphere of influence.
	var max_closing_speed := _max_speed(orbit) + _max_speed(satellite_orbit)
	var time := from_time
	var distance := _distance(orbit, satellite_orbit, time)
	if distance < entry_radius:
		return time
	for i in MAX_SEARCH_STEPS:
		if time >= to_time:
			return INF
		var next_time := minf(time + maxf((distance - entry_radius) / max_closing_speed, MIN_SEARCH_STEP), to_time)
		var next_distance := _distance(orbit, satellite_orbit, next_time)
		if next_distance < entry_radius:
			return _bisect_entry(orbit, satellite_orbit, entry_radius, time, next_time)
		time = next_time
		distance = next_distance
	return INF


static func _bisect_entry(orbit: Orbit, satellite_orbit: Orbit, entry_radius: float, outside_time: float, inside_time: float) -> float:
	for i in 60:
		if inside_time - outside_time < 1e-4:
			break
		var middle := (outside_time + inside_time) / 2.0
		if _distance(orbit, satellite_orbit, middle) < entry_radius:
			inside_time = middle
		else:
			outside_time = middle
	return inside_time


static func _distance(orbit: Orbit, satellite_orbit: Orbit, time: float) -> float:
	return (orbit.position_at(time) - satellite_orbit.position_at(time)).length()


static func _max_speed(orbit: Orbit) -> float:
	return sqrt(orbit.mu * (2.0 / orbit.periapsis() - 1.0 / orbit.semi_major_axis))
