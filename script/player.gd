extends CharacterBody2D

# ── Signals ──────────────────────────────────────────────
signal health_changed(new_health: int)
signal died

# ── Constants ────────────────────────────────────────────
const SPEED          := 200.0
const JUMP_VELOCITY  := -350.0
const ATTACK_RANGE   := 120.0
const ATTACK_DAMAGE  := 10
const MAX_HP         := 200

# ── State vars ───────────────────────────────────────────
var current_hp   : int  = MAX_HP
var is_dead      : bool = false
var is_attacking : bool = false
var is_hit       : bool = false
var facing_right : bool = true

# ── Node refs ────────────────────────────────────────────
@onready var anim          : AnimatedSprite2D = $AnimatedSprite2D
@onready var attack_timer  : Timer            = $AttackTimer
@onready var hit_timer     : Timer            = $HitTimer

# ─────────────────────────────────────────────────────────
func _ready() -> void:
	add_to_group("player")
	current_hp = MAX_HP

	# Register input actions if missing
	_register_action("jump",    KEY_SPACE)
	_register_action("attack1", KEY_F)
	_register_action("attack2", KEY_G)

	# Connect timers
	attack_timer.wait_time = 0.55
	attack_timer.one_shot  = true
	attack_timer.timeout.connect(_on_attack_finished)

	hit_timer.wait_time = 0.45
	hit_timer.one_shot  = true
	hit_timer.timeout.connect(_on_hit_finished)

	anim.play("Idle")
	anim.animation_finished.connect(_on_anim_finished)

func _register_action(action: String, key: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.keycode = key
	InputMap.action_add_event(action, ev)

# ─────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# Gravity
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Attack input (locks movement)
	if Input.is_action_just_pressed("attack1") and not is_attacking and not is_hit:
		_perform_attack("Attack 1")
	elif Input.is_action_just_pressed("attack2") and not is_attacking and not is_hit:
		_perform_attack("Attack 2")

	# Jump
	if Input.is_action_just_pressed("jump") and is_on_floor() and not is_attacking:
		velocity.y = JUMP_VELOCITY

	# Horizontal movement
	var dir := Input.get_axis("ui_left", "ui_right")
	if not is_attacking and not is_hit:
		if dir != 0:
			# Instant target speed — feels responsive
			velocity.x   = dir * SPEED
			facing_right = dir > 0
			# Flip: sprite faces RIGHT by default → flip when going LEFT
			anim.flip_h  = not facing_right
		else:
			# Smooth stop scaled by delta
			velocity.x = move_toward(velocity.x, 0.0, SPEED * 8.0 * delta)
	else:
		# Slide to stop during attack/hit
		velocity.x = move_toward(velocity.x, 0.0, SPEED * 6.0 * delta)

	move_and_slide()
	_update_anim(dir)

# ─────────────────────────────────────────────────────────
func _update_anim(dir: float) -> void:
	if is_dead or is_attacking or is_hit:
		return

	var target_anim : String
	if not is_on_floor():
		target_anim = "Jump" if velocity.y < 0 else "Fall"
	elif dir != 0:
		target_anim = "run"
	else:
		target_anim = "Idle"

	# Only call play() when the animation actually needs to change
	# (prevents per-frame restart glitch)
	if anim.animation != target_anim or not anim.is_playing():
		anim.play(target_anim)

# ─────────────────────────────────────────────────────────
func _perform_attack(anim_name: String) -> void:
	is_attacking = true
	anim.play(anim_name)
	attack_timer.start()

	# Hit enemies immediately on swing
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(enemy) and \
		   global_position.distance_to(enemy.global_position) <= ATTACK_RANGE:
			if enemy.has_method("take_damage"):
				enemy.take_damage(ATTACK_DAMAGE)

func _on_attack_finished() -> void:
	is_attacking = false
	if not is_dead:
		anim.play("Idle")

func _on_anim_finished() -> void:
	# Non-looping animations snap back to idle
	match anim.animation:
		"Attack 1", "Attack 2":
			if not is_attacking:
				anim.play("Idle")
		"hit":
			if not is_dead and not is_attacking:
				anim.play("Idle")

# ─────────────────────────────────────────────────────────
func take_damage(amount: int) -> void:
	if is_dead or is_hit:
		return
	current_hp = max(current_hp - amount, 0)
	health_changed.emit(current_hp)

	if current_hp <= 0:
		_die()
		return

	is_hit = true
	anim.play("hit")
	hit_timer.start()

func _on_hit_finished() -> void:
	is_hit = false
	if not is_dead and not is_attacking:
		anim.play("Idle")

# ─────────────────────────────────────────────────────────
func _die() -> void:
	if is_dead:
		return
	is_dead      = true
	velocity     = Vector2.ZERO
	is_attacking = false
	is_hit       = false
	died.emit()
	anim.play("Death")
	set_collision_layer_value(1, false)
	set_collision_mask_value(1, false)

	# Wait for death animation then show YOU DIED screen
	await get_tree().create_timer(1.8).timeout
	_show_death_screen()

func _show_death_screen() -> void:
	var death_scene = load("res://scenes/death_screen.tscn")
	if death_scene == null:
		# Fallback: just reload the scene
		get_tree().reload_current_scene()
		return
	var death_ui = death_scene.instantiate()
	# MUST add to tree BEFORE calling methods that use tweens/tree
	get_tree().root.add_child(death_ui)
	death_ui.show_death_screen()
	# Pause the game world (death screen runs in PROCESS_MODE_ALWAYS)
	get_tree().paused = true
