class_name CelestialBody
extends Node2D

## Distances are in km (1 world unit = 1 km). The root body (no parent) must sit at the world origin.

@export var radius := 600.0
## Gravitational parameter (G × mass), km³/s². 3531.6 gives 9.81 m/s² at a 600 km radius.
@export var mu := 3531.6
@export var atmosphere_height := 70.0
@export var surface_color := Color(0.22, 0.45, 0.7)
@export var atmosphere_color := Color(0.45, 0.7, 1.0, 0.15)

@export_group("Orbit")
## Leave empty for the root body.
@export var parent_body: CelestialBody
@export var orbit_radius := 0.0
## Where the body starts around its parent, in degrees.
@export var orbit_start_angle := 0.0
@export var orbit_ring: Ring
@export var sphere_of_influence_ring: Ring

## Circular orbit around parent_body, on rails. Null for the root body.
var orbit: Orbit
## Distance within which this body's gravity takes over from its parent's, in km.
var sphere_of_influence := INF
var satellites: Array[CelestialBody] = []


func _ready() -> void:
	setup()


## Separate from _ready so tests can build bodies without a scene tree.
func setup() -> void:
	if parent_body == null:
		return
	parent_body.satellites.append(self)
	var start := Vector2.from_angle(deg_to_rad(orbit_start_angle)) * orbit_radius
	var speed := sqrt(parent_body.mu / orbit_radius)
	orbit = Orbit.from_state(parent_body.mu, start, start.normalized().orthogonal() * speed, 0.0)
	sphere_of_influence = orbit_radius * pow(mu / parent_body.mu, 0.4)
	if orbit_ring:
		orbit_ring.radius = orbit_radius
	if sphere_of_influence_ring:
		sphere_of_influence_ring.radius = sphere_of_influence


func position_at(time: float) -> Vector2:
	if parent_body == null:
		return Vector2.ZERO
	return parent_body.position_at(time) + orbit.position_at(time)


func velocity_at(time: float) -> Vector2:
	if parent_body == null:
		return Vector2.ZERO
	return parent_body.velocity_at(time) + orbit.velocity_at(time)


func _process(_delta: float) -> void:
	if parent_body:
		global_position = position_at(Sim.time)


func _draw() -> void:
	if atmosphere_height > 0.0:
		draw_circle(Vector2.ZERO, radius + atmosphere_height, atmosphere_color, true, -1.0, true)
	draw_circle(Vector2.ZERO, radius, surface_color, true, -1.0, true)
