extends Control

const GAME_SCENE := "res://scenes/tile_map.tscn"

func _ready() -> void:
	# Animate the title pulsing
	var tween := create_tween().set_loops()
	tween.tween_property($TitleLabel, "modulate:a", 0.6, 1.2)
	tween.tween_property($TitleLabel, "modulate:a", 1.0, 1.2)

func _on_play_button_pressed() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)

func _on_quit_button_pressed() -> void:
	get_tree().quit()
