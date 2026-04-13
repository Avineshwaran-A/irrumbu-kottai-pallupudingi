extends CharacterBody2D

# -------------------------
# STATES
# -------------------------
enum State { IDLE, ROAM, CHASE, ATTACK, HIT, DEAD }
var current_state = State.ROAM

# -------------------------
# SETTINGS
# -------------------------
@export var speed          = 120
@export var roam_speed     = 60
@export var roam_steps_min = 3
@export var roam_steps_max = 4

# -------------------------
# STATS
# -------------------------
const MAX_HP       : int   = 30
const DAMAGE       : int   = 8
const ATTACK_RANGE : float = 55.0
const ATTACK_CD    : float = 1.3
const HIT_STUN     : float = 0.5

# -------------------------
# VARIABLES
# -------------------------
var player       = null
var roam_target  = Vector2.ZERO
var roam_steps   = 0
var facing_right = true
var current_hp   = MAX_HP

# Delta timers (no child Timer nodes needed)
var attack_cd : float = 0.0
var hit_time  : float = 0.0

@onready var anim = $AnimatedSprite2D

# -------------------------
# READY
# -------------------------
func _ready():
	add_to_group("enemy")
	randomize()
	current_hp = MAX_HP
	anim.animation_finished.connect(_on_anim_finished)
	# Play spawn intro → _on_anim_finished switches to roam
	anim.play("spawn")

# -------------------------
# MAIN LOOP
# -------------------------
func _physics_process(delta):
	if current_state == State.DEAD:
		return

	# Gravity
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Tick timers
	if attack_cd > 0.0: attack_cd -= delta
	if hit_time  > 0.0:
		hit_time -= delta
		if hit_time <= 0.0 and current_state == State.HIT:
			anim.modulate = Color.WHITE
			current_state = State.ROAM
			anim.play("idle")

	# Locked states
	if current_state == State.ATTACK or current_state == State.HIT:
		velocity.x = 0.0
		move_and_slide()
		return

	# ── Distance-based detection (works even without Area2D) ──
	_fallback_detect()

	match current_state:

		State.CHASE:
			if player and is_instance_valid(player):
				var dist = global_position.distance_to(player.global_position)
				if dist <= ATTACK_RANGE and attack_cd <= 0.0:
					_do_attack()
				else:
					var dir = (player.global_position - global_position).normalized()
					velocity.x   = dir.x * float(speed)   # only X — let gravity handle Y
					_set_facing(dir.x)
					anim.play("idle")
			else:
				current_state = State.ROAM
				_start_roam()

		State.ROAM:
			roam()

		State.IDLE:
			velocity.x = 0.0
			anim.play("idle")

	move_and_slide()

# -------------------------
# DETECTION (Area2D — "DetectionZone")
# -------------------------
func _on_detection_zone_body_entered(body):
	if body.is_in_group("player"):
		player        = body
		current_state = State.CHASE

func _on_detection_zone_body_exited(body):
	if body == player:
		player        = null
		current_state = State.ROAM
		_start_roam()

# Distance-based fallback — runs every frame as a backup
const DETECT_RANGE : float = 150.0
func _fallback_detect() -> void:
	# If we already have a valid player reference, keep it
	if player != null and is_instance_valid(player):
		var dist = global_position.distance_to(player.global_position)
		# Lost player — go back to roaming
		if dist > DETECT_RANGE * 1.6 and current_state == State.CHASE:
			player        = null
			current_state = State.ROAM
			_start_roam()
		return
	# Try to find player by group
	var arr := get_tree().get_nodes_in_group("player")
	if arr.is_empty():
		return
	var p = arr[0]
	if global_position.distance_to(p.global_position) <= DETECT_RANGE:
		player        = p
		current_state = State.CHASE

# -------------------------
# ROAM
# -------------------------
func _start_roam():
	current_state = State.ROAM
	roam_steps    = randi_range(roam_steps_min, roam_steps_max)
	pick_new_roam_target()

func roam():
	var dir = roam_target - global_position

	if dir.length() < 5:
		roam_steps -= 1
		if roam_steps <= 0:
			current_state = State.IDLE
			velocity.x    = 0.0
			anim.play("idle")
			_idle_pause()
			return
		pick_new_roam_target()
	else:
		var n = dir.normalized()
		velocity.x = n.x * float(roam_speed)
		_set_facing(n.x)
		anim.play("idle")

func _idle_pause():
	await get_tree().create_timer(1.5).timeout
	if current_state != State.DEAD and current_state != State.CHASE:
		_start_roam()

func pick_new_roam_target():
	roam_target = global_position + Vector2(
		float(randi_range(-100, 100)),
		0.0   # stay on same Y to avoid walking into air
	)

# -------------------------
# ATTACK
# -------------------------
func _do_attack():
	current_state = State.ATTACK
	velocity.x    = 0.0
	if player:
		_set_facing(player.global_position.x - global_position.x)
	anim.play("attack ")   # ← trailing space, exactly as in SpriteFrames

# ── Facing helper ──────────────────────────────────────────
# The skeleton sprite sheet faces LEFT by default.
# So flip_h = false → faces LEFT, flip_h = true → faces RIGHT.
func _set_facing(dir_x: float) -> void:
	if dir_x == 0.0:
		return
	facing_right = dir_x > 0.0
	anim.flip_h  = facing_right   # flip when going RIGHT (sprite default is LEFT)

# -------------------------
# TAKE DAMAGE  (called by player)
# -------------------------
func take_damage(amount: int):
	if current_state == State.DEAD:
		return
	current_hp = max(current_hp - amount, 0)
	if current_hp <= 0:
		_die()
		return
	# No "hit" animation exists — use red flash
	current_state = State.HIT
	hit_time      = HIT_STUN
	velocity.x    = 0.0
	anim.modulate = Color(2.2, 0.2, 0.2, 1.0)

# -------------------------
# DIE
# -------------------------
func _die():
	current_state = State.DEAD
	velocity      = Vector2.ZERO
	anim.modulate = Color.WHITE
	anim.play("death")
	set_collision_layer_value(1, false)
	set_collision_mask_value(1, false)

# -------------------------
# ANIMATION FINISHED
# "spawn", "attack ", "death" are all one-shot
# "idle" is looping (never triggers this)
# -------------------------
func _on_anim_finished():
	match anim.animation:

		"spawn":
			# Intro done → start roaming
			_start_roam()

		"attack ":   # trailing space matches SpriteFrames name
			# Deal damage at end of swing
			if player and is_instance_valid(player) and current_state != State.DEAD:
				if global_position.distance_to(player.global_position) <= ATTACK_RANGE + 15.0:
					if player.has_method("take_damage"):
						player.take_damage(DAMAGE)
			attack_cd     = ATTACK_CD
			current_state = State.IDLE
			anim.play("idle")

		"death":
			await get_tree().create_timer(0.5).timeout
			queue_free()
