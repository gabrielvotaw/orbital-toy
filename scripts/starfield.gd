extends ColorRect

## Feeds the camera position to the starfield shader so the stars drift slightly as the view moves.

## Background pixels moved per km of camera movement, for the nearest star layer. Kept small and
## independent of zoom so the stars feel very far away and don't stream past while zooming.
@export var parallax_per_km := 0.02


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_2d()
	var shader := material as ShaderMaterial
	shader.set_shader_parameter("screen_size", size)
	if camera:
		shader.set_shader_parameter("offset", camera.get_screen_center_position() * parallax_per_km)
