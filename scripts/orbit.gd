class_name Orbit
extends RefCounted

## A Kepler orbit in the plane, relative to the center of the body being orbited.
## Positions are computed directly from time, so orbits never drift.
## Handles ellipses (eccentricity < 1) and hyperbolas (eccentricity > 1).
## Math uses 64-bit scalar floats; Vector2 is 32-bit and only used for input and output.

## Gravitational parameter of the central body, km³/s².
var mu: float
## Negative for hyperbolic orbits.
var semi_major_axis: float
var eccentricity: float
## Angle of periapsis from the +x axis, in radians.
var argument_of_periapsis: float
## +1 if the angle to the ship increases over time (clockwise on screen, since screen y points down), -1 otherwise.
var direction: float
var mean_anomaly_at_epoch: float
var epoch: float


static func from_state(mu: float, position: Vector2, velocity: Vector2, time: float) -> Orbit:
	var orbit := Orbit.new()
	orbit.mu = mu
	orbit.epoch = time

	var rx := position.x
	var ry := position.y
	var vx := velocity.x
	var vy := velocity.y
	var r := sqrt(rx * rx + ry * ry)
	var v2 := vx * vx + vy * vy
	var r_dot_v := rx * vx + ry * vy
	var angular_momentum := rx * vy - ry * vx

	orbit.direction = -1.0 if angular_momentum < 0.0 else 1.0
	orbit.semi_major_axis = 1.0 / (2.0 / r - v2 / mu)

	var ex := ((v2 - mu / r) * rx - r_dot_v * vx) / mu
	var ey := ((v2 - mu / r) * ry - r_dot_v * vy) / mu
	orbit.eccentricity = sqrt(ex * ex + ey * ey)

	var position_angle := atan2(ry, rx)
	if orbit.eccentricity < 1e-10:
		orbit.eccentricity = 0.0
		orbit.argument_of_periapsis = position_angle
	else:
		orbit.argument_of_periapsis = atan2(ey, ex)

	var true_anomaly := wrapf((position_angle - orbit.argument_of_periapsis) * orbit.direction, -PI, PI)
	orbit.mean_anomaly_at_epoch = orbit._true_to_mean_anomaly(true_anomaly)
	return orbit


func is_elliptic() -> bool:
	return eccentricity < 1.0


func semi_latus_rectum() -> float:
	return semi_major_axis * (1.0 - eccentricity * eccentricity)


## Closest distance to the body's center.
func periapsis() -> float:
	return semi_major_axis * (1.0 - eccentricity)


## Farthest distance from the body's center. INF if the orbit escapes.
func apoapsis() -> float:
	return semi_major_axis * (1.0 + eccentricity) if is_elliptic() else INF


func mean_motion() -> float:
	return sqrt(mu / absf(semi_major_axis * semi_major_axis * semi_major_axis))


## Time for one full orbit. INF if the orbit escapes.
func period() -> float:
	return TAU / mean_motion() if is_elliptic() else INF


func true_anomaly_at(time: float) -> float:
	return _mean_to_true_anomaly(mean_anomaly_at_epoch + mean_motion() * (time - epoch))


func position_at(time: float) -> Vector2:
	return position_at_true_anomaly(true_anomaly_at(time))


func velocity_at(time: float) -> Vector2:
	return _velocity_at_true_anomaly(true_anomaly_at(time))


## The first time at or after after_time when the orbit passes the given true anomaly.
## INF if an escape orbit has already passed it.
func next_time_at_true_anomaly(nu: float, after_time: float) -> float:
	var target := _true_to_mean_anomaly(nu)
	var n := mean_motion()
	if is_elliptic():
		var current := mean_anomaly_at_epoch + n * (after_time - epoch)
		return after_time + fposmod(target - current, TAU) / n
	var time := epoch + (target - mean_anomaly_at_epoch) / n
	return time if time >= after_time else INF


## The positive true anomaly where the orbit is at distance r from the center
## (the other crossing is at minus this value). NAN if the orbit never reaches r.
func true_anomaly_at_radius(r: float) -> float:
	if eccentricity < 1e-9:
		return NAN
	var cos_nu := (semi_latus_rectum() / r - 1.0) / eccentricity
	if absf(cos_nu) > 1.0:
		return NAN
	return acos(cos_nu)


## Points around the whole ellipse, for drawing. Empty for escape orbits.
func sample_points(count := 256) -> PackedVector2Array:
	var points := PackedVector2Array()
	if not is_elliptic():
		return points
	var e := eccentricity
	for i in count + 1:
		var eccentric_anomaly := TAU * i / count
		var nu := 2.0 * atan2(sqrt(1.0 + e) * sin(eccentric_anomaly / 2.0), sqrt(1.0 - e) * cos(eccentric_anomaly / 2.0))
		points.append(position_at_true_anomaly(nu))
	return points


## Points between two true anomalies, for drawing part of an orbit.
func sample_arc(from_true_anomaly: float, to_true_anomaly: float, count := 128) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in count + 1:
		points.append(position_at_true_anomaly(lerpf(from_true_anomaly, to_true_anomaly, float(i) / count)))
	return points


func position_at_true_anomaly(nu: float) -> Vector2:
	var r := semi_latus_rectum() / (1.0 + eccentricity * cos(nu))
	var angle := argument_of_periapsis + direction * nu
	return Vector2(r * cos(angle), r * sin(angle))


func _velocity_at_true_anomaly(nu: float) -> Vector2:
	var k := sqrt(mu / semi_latus_rectum())
	var radial := k * eccentricity * sin(nu)
	var tangential := k * (1.0 + eccentricity * cos(nu)) * direction
	var angle := argument_of_periapsis + direction * nu
	var c := cos(angle)
	var s := sin(angle)
	return Vector2(radial * c - tangential * s, radial * s + tangential * c)


func _true_to_mean_anomaly(nu: float) -> float:
	var e := eccentricity
	if is_elliptic():
		var eccentric_anomaly := atan2(sqrt(1.0 - e * e) * sin(nu), e + cos(nu))
		return eccentric_anomaly - e * sin(eccentric_anomaly)
	var sinh_f := sqrt(e * e - 1.0) * sin(nu) / (1.0 + e * cos(nu))
	return e * sinh_f - _asinh(sinh_f)


func _mean_to_true_anomaly(mean_anomaly: float) -> float:
	var e := eccentricity
	if is_elliptic():
		var eccentric_anomaly := _solve_kepler_elliptic(wrapf(mean_anomaly, -PI, PI))
		return 2.0 * atan2(sqrt(1.0 + e) * sin(eccentric_anomaly / 2.0), sqrt(1.0 - e) * cos(eccentric_anomaly / 2.0))
	var hyperbolic_anomaly := _solve_kepler_hyperbolic(mean_anomaly)
	return 2.0 * atan(sqrt((e + 1.0) / (e - 1.0)) * tanh(hyperbolic_anomaly / 2.0))


func _solve_kepler_elliptic(mean_anomaly: float) -> float:
	var e := eccentricity
	var x := mean_anomaly if e < 0.8 else PI * signf(mean_anomaly)
	for i in 50:
		var step := (x - e * sin(x) - mean_anomaly) / (1.0 - e * cos(x))
		x -= step
		if absf(step) < 1e-12:
			break
	return x


func _solve_kepler_hyperbolic(mean_anomaly: float) -> float:
	var e := eccentricity
	var x := _asinh(mean_anomaly / e)
	for i in 100:
		var step := (e * sinh(x) - x - mean_anomaly) / (e * cosh(x) - 1.0)
		x -= step
		if absf(step) < 1e-12:
			break
	return x


static func _asinh(x: float) -> float:
	return signf(x) * log(absf(x) + sqrt(x * x + 1.0))
