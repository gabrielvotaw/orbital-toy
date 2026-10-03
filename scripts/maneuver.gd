class_name Maneuver
extends RefCounted

## A planned burn: at `time`, change velocity by `delta_v`, measured as (prograde, radial out) in m/s
## relative to the orbit at that moment.

var time: float
var delta_v := Vector2.ZERO

## Filled in by Ship.update_plan(): where along the planned path this maneuver happens.
## Invalid maneuvers are past the end of the predicted path (for example after an impact).
var valid := false
## Which stretch of Ship.plan this maneuver lies on (the path before its own burn).
var segment_index := 0
var body: CelestialBody
## The orbit, relative to `body`, that the maneuver is applied to.
var orbit: Orbit
## Time whose body position the orbit is drawn around; NAN means "the body's current position".
var anchor_time := NAN

## Set when the burn starts.
var burning := false
## Delta-v still to apply during the burn, in m/s. Can go slightly negative for energy-guided burns.
var remaining := 0.0
## Mostly prograde/retrograde burns stop when the orbit reaches the planned energy rather than
## when the delta-v budget runs out. That compensates for long burns not being instant.
var energy_guided := false
## Planned orbital energy after the burn, in km²/s².
var target_energy := 0.0
