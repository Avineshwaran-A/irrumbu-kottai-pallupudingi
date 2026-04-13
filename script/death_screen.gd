extends CanvasLayer

# ─────────────────────────────────────────────────────────
# Death Screen — shown when player dies
# Call show_death_screen() from player.gd
# ─────────────────────────────────────────────────────────

const GAME_SCENE := "res://scenes/tile_map.tscn"

func _ready() -> void:
	# Pause only the game world, not this UI
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

func show_death_screen() -> void:
	visible = true
	# Fade the screen in
	var panel := $Panel
	var tween := create_tween()
	panel.modulate.a = 0.0
	tween.tween_property(panel, "modulate:a", 1.0, 0.8)

func _on_restart_button_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(GAME_SCENE)
