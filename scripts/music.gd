extends AudioStreamPlayer

## Background music. M mutes and unmutes.


func _ready() -> void:
	(stream as AudioStreamOggVorbis).loop = true
	play()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_M:
		stream_paused = not stream_paused
