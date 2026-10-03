class_name CelestialBody
extends Node2D

## Distances are in km (1 world unit = 1 km). The root body (no parent) must sit at the world origin.

@export var radius := 600.0
## Gravitational parameter (G × mass), km³/s². 3531.6 gives 9.81 m/s² at a 600 km radius.
@export var mu := 3531.6
## Visual only: how far the atmosphere glow extends above the surface, in km.
@export var atmosphere_height := 70.0
## Rotation speed in radians per game second. The look comes from the planet shader in `material`.
@export var spin_rate := 0.0

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

static var _white_texture: ImageTexture


func _ready() -> void:
	setup()
	if material is ShaderMaterial:
		material.set_shader_parameter("body_fraction", radius / (radius + atmosphere_height))


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
	if material is ShaderMaterial:
		material.set_shader_parameter("spin", fmod(Sim.time * spin_rate, TAU))


func _draw() -> void:
	if _white_texture == null:
		var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		_white_texture = ImageTexture.create_from_image(image)
	var extent := radius + atmosphere_height
	draw_texture_rect(_white_texture, Rect2(-extent, -extent, 2.0 * extent, 2.0 * extent), false)
