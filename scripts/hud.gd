extends CanvasLayer

@export var ship: Ship

@onready var _info_label: Label = $InfoLabel


func _process(_delta: float) -> void:
	var zoom := get_viewport().get_canvas_transform().get_scale().x
	var view_width_km := get_viewport().get_visible_rect().size.x / zoom
	var camera: Variant = get_viewport().get_camera_2d()
	var following := " (following %s)" % camera.focus_name() if camera.has_method("focus_name") else ""
	var lines := PackedStringArray([
		"View width: %s km%s" % [_format_thousands(roundi(view_width_km)), following],
		"Sim speed: %s    T+ %s" % ["PAUSED" if Sim.paused else "%sx" % String.num(Sim.speed), _format_duration(Sim.time)],
	])

	if ship and ship.crashed:
		lines.append("")
		lines.append("CRASHED on %s - press R to reset" % ship.reference_body.name)
	elif ship and ship.orbit:
		var orbit := ship.orbit
		var radius := ship.reference_body.radius
		var altitude := orbit.position_at(Sim.time).length() - radius
		var speed := orbit.velocity_at(Sim.time).length() * 1000.0
		var apoapsis := "escaping" if not orbit.is_elliptic() else "%s km" % _format_thousands(roundi(orbit.apoapsis() - radius))
		var period := "-" if not orbit.is_elliptic() else _format_duration(orbit.period())
		var engine := "off"
		if not ship.maneuvers.is_empty() and ship.maneuvers[0].burning:
			engine = "maneuver burn"
		elif ship.thrust != Vector2.ZERO:
			engine = "%d%%" % roundi(ship.thrust.length() * 100.0)
		lines.append("")
		lines.append("Orbiting: %s" % ship.reference_body.name)
		lines.append("Altitude: %s km    Speed: %s m/s" % [_format_thousands(roundi(altitude)), _format_thousands(roundi(speed))])
		lines.append("Apoapsis: %s    Periapsis: %s km    Period: %s" % [apoapsis, _format_thousands(roundi(orbit.periapsis() - radius)), period])
		lines.append("Engine: %s    Delta-v used: %s m/s" % [engine, _format_thousands(roundi(ship.delta_v_used))])

		var encounter := _encounter_text(ship.next_encounter(ship.prediction))
		if encounter != "":
			lines.append(encounter)

		if not ship.maneuvers.is_empty():
			lines.append("")
			lines.append_array(_maneuver_lines())

	_info_label.text = "\n".join(lines)


func _maneuver_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	var next := ship.maneuvers[0]
	if next.burning:
		lines.append("Executing maneuver: %s m/s remaining" % _format_thousands(roundi(next.remaining)))
	else:
		var dv := next.delta_v
		var burn_time := ship.burn_duration(dv.length())
		lines.append("Next maneuver: %s m/s (prograde %s, radial %s)" % [
			_format_thousands(roundi(dv.length())), _format_thousands(roundi(dv.x)), _format_thousands(roundi(dv.y))])
		lines.append("Burn: %s, starts in %s" % [_format_duration(burn_time), _format_duration(maxf(0.0, next.time - burn_time / 2.0 - Sim.time))])

	var total := 0.0
	var invalid := 0
	for maneuver in ship.maneuvers:
		total += maneuver.remaining if maneuver.burning else maneuver.delta_v.length()
		if not maneuver.valid:
			invalid += 1
	if ship.maneuvers.size() > 1:
		lines.append("Planned maneuvers: %d, total %s m/s" % [ship.maneuvers.size(), _format_thousands(roundi(total))])
	if invalid > 0:
		lines.append("%d maneuver(s) past the end of the predicted path" % invalid)

	if ship.plan.size() > 1:
		var final_segment: Array = ship.plan.back()
		var final_orbit: Orbit = final_segment[0].orbit
		var final_body: CelestialBody = final_segment[0].body
		var apoapsis := "escaping" if not final_orbit.is_elliptic() else "%s km" % _format_thousands(roundi(final_orbit.apoapsis() - final_body.radius))
		lines.append("After all maneuvers: orbiting %s, Apoapsis %s, Periapsis %s km" % [
			final_body.name, apoapsis, _format_thousands(roundi(final_orbit.periapsis() - final_body.radius))])
		var encounter := _encounter_text(ship.next_encounter(final_segment))
		lines.append("After all maneuvers: " + (encounter if encounter != "" else "no encounter"))
	return lines


func _encounter_text(encounter: Dictionary) -> String:
	if encounter.is_empty():
		return ""
	var approach: float = encounter.closest_approach
	var approach_text := "impact" if approach < 0.0 else "closest approach %s km" % _format_thousands(roundi(approach))
	return "%s encounter in %s, %s" % [encounter.body.name, _format_duration(encounter.time - Sim.time), approach_text]


func _format_thousands(value: int) -> String:
	var digits := str(absi(value))
	var result := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			result += ","
		result += digits[i]
	return "-" + result if value < 0 else result


func _format_duration(seconds: float) -> String:
	var days := floori(seconds / 86400.0)
	var hours := floori(seconds / 3600.0) % 24
	var minutes := floori(seconds / 60.0) % 60
	var secs := floori(seconds) % 60
	if days > 0:
		return "%dd %02dh %02dm" % [days, hours, minutes]
	if hours > 0:
		return "%dh %02dm %02ds" % [hours, minutes, secs]
	return "%dm %02ds" % [minutes, secs]
