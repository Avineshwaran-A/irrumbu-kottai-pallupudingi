extends Node

# ─────────────────────────────────────────────────────────
#  ENEMY SPAWNER — Dungeon Dash
#  Place on a Node in tile_map.tscn.
#  Spawns 50 KuttyKunjan enemies spread across the world.
# ─────────────────────────────────────────────────────────

const ENEMY_SCENE = preload("res://scenes/kuttykunjan.tscn")
const ENEMY_COUNT = 50

# 50 positions spread across the level (X, Y)
# Y=100 → ground level. Adjust if your floor is different.
const SPAWN_REGIONS : Array[Vector2] = [
	# Far left
	Vector2(-1200, 100), Vector2(-1050, 100), Vector2(-900, 100),
	Vector2(-800,  100), Vector2(-700,  100),
	# Left region
	Vector2(-600, 100), Vector2(-500, 100), Vector2(-400, 100),
	Vector2(-300, 100), Vector2(-200, 100),
	# Centre-left
	Vector2(-100, 100), Vector2(0,   100), Vector2(100, 100),
	Vector2(200,  100), Vector2(300, 100),
	# Centre
	Vector2(450,  100), Vector2(600, 100), Vector2(750, 100),
	Vector2(900,  100), Vector2(1050, 100),
	# Centre-right
	Vector2(1200, 100), Vector2(1350, 100), Vector2(1500, 100),
	Vector2(1650, 100), Vector2(1800, 100),
	# Right region
	Vector2(1950, 100), Vector2(2100, 100), Vector2(2250, 100),
	Vector2(2400, 100), Vector2(2550, 100),
	# Far right
	Vector2(2700, 100), Vector2(2850, 100), Vector2(3000, 100),
	Vector2(3150, 100), Vector2(3300, 100),
	# Upper platform row 1
	Vector2(-800, -200), Vector2(-400, -200), Vector2(0,    -200),
	Vector2(400,  -200), Vector2(800,  -200),
	# Upper platform row 2
	Vector2(1200, -200), Vector2(1600, -200), Vector2(2000, -200),
	Vector2(2400, -200), Vector2(2800, -200),
	# High platform row
	Vector2(-600, -450), Vector2(200,  -450), Vector2(800,  -450),
	Vector2(1500, -450), Vector2(2500, -450),
]

func _ready() -> void:
	for i in ENEMY_COUNT:
		var enemy : CharacterBody2D = ENEMY_SCENE.instantiate()
		enemy.position = SPAWN_REGIONS[i]
		enemy.name     = "KuttyKunjan_%d" % i
		add_child(enemy)
