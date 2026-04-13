extends CharacterBody2D

# ═══════════════════════════════════════════════════════════
#  MAIN BOSS — Hard AI with Attack Patterns
#
#  Animation names (verified from screenshot):
#    "idle"      → LOOPING  — standing idle
#    "run"       → LOOPING  — moving toward player
#    "attack 1"  → one-shot — quick jab (shorter cooldown)
#    "attack 2"  → one-shot — heavy slam (more damage, knockback)
#    "hit"       → one-shot — stagger on damage
#    "death"     → one-shot — death sequence
#
#  Sprite faces RIGHT by default → flip_h = true means facing LEFT
# ═══════════════════════════════════════════════════════════

# ── Stats ──────────────────────────────────────────────────
const MAX_HP          : int   = 200

# Damage per attack type, per phase
const DMG_ATK1_P1     : int   = 20     # quick jab  - phase 1
const DMG_ATK1_P2     : int   = 28     # quick jab  - phase 2
const DMG_ATK2_P1     : int   = 35     # heavy slam - phase 1
const DMG_ATK2_P2     : int   = 48     # heavy slam - phase 2
const DMG_LUNGE       : int   = 40     # lunge dash - phase 2 only

# Ranges
const ACTIVATE_DIST   : float = 320.0  # boss starts chasing
const DETECT_RANGE    : float = 400.0  # max chase distance
const ATTACK_RANGE    : float = 95.0   # melee trigger
const LUNGE_RANGE     : float = 230.0  # lunge trigger (phase 2)

# Speeds
const SPEED_P1        : float = 90.0
const SPEED_P2        : float = 145.0  # enraged

# Attack cooldowns (ATK1 is faster, ATK2 is slower)
const CD_ATK1_P1      : float = 1.5
const CD_ATK1_P2      : float = 0.9
const CD_ATK2_P1      : float = 2.8
const CD_ATK2_P2      : float = 1.8

# Hit stun duration
const HIT_STUN_P1     : float = 0.55
const HIT_STUN_P2     : float = 0.28   # barely flinches when enraged

# Lunge
const LUNGE_CD_TIME   : float = 4.0
const LUNGE_DURATION  : float = 0.30
const LUNGE_FORCE     : float = 450.0

# ─────────────────────────────────────────────────────────
enum State { IDLE, CHASE, ATK1, ATK2, LUNGE, HIT, DEAD }
var state         : State = State.IDLE
var current_hp    : int   = MAX_HP
var phase2        : bool  = false
var facing_right  : bool  = true

# Attack pattern tracking
var atk_combo_count : int   = 0   # counts hits; every 3rd triggers ATK2
var last_atk_was_2  : bool  = false

# Delta timers
var atk1_cd      : float = 0.0
var atk2_cd      : float = 0.0
var lunge_cd     : float = 0.0
var hit_time     : float = 0.0
var lunge_timer  : float = 0.0

var player : Node2D = null

@onready var anim : AnimatedSprite2D = $AnimatedSprite2D

# ═══════════════════════════════════════════════════════════
func _ready() -> void:
	add_to_group("enemy")
	current_hp = MAX_HP
	anim.animation_finished.connect(_on_anim_finished)
	anim.play("idle")

# ═══════════════════════════════════════════════════════════
func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return

	# Gravity
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Tick all timers
	if atk1_cd   > 0.0: atk1_cd   -= delta
	if atk2_cd   > 0.0: atk2_cd   -= delta
	if lunge_cd  > 0.0: lunge_cd  -= delta

	# Hit stun
	if hit_time > 0.0:
		hit_time -= delta
		if hit_time <= 0.0 and state == State.HIT:
			anim.modulate = Color.WHITE
			state = State.CHASE
			_play("run")

	# Phase 2 transition at 50% HP
	if not phase2 and current_hp <= MAX_HP / 2:
		_enter_phase2()

	# Lunge burst — slide forward for lunge_timer seconds
	if state == State.LUNGE:
		lunge_timer -= delta
		if lunge_timer <= 0.0:
			_finish_lunge()
		move_and_slide()
		return

	# Locked states — slide to a stop
	if state == State.ATK1 or state == State.ATK2 or state == State.HIT:
		velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
		move_and_slide()
		return

	# Always refresh player reference
	_find_player()

	velocity.x = 0.0
	var spd := SPEED_P2 if phase2 else SPEED_P1

	match state:

		State.IDLE:
			_play("idle")
			if player != null and _dist() <= ACTIVATE_DIST:
				state = State.CHASE

		State.CHASE:
			if player == null or not is_instance_valid(player):
				state = State.IDLE
				_play("idle")
			else:
				var d := _dist()
				if d > DETECT_RANGE:
					state = State.IDLE
					_play("idle")
				elif _can_attack(d):
					_decide_attack()
				elif phase2 and d <= LUNGE_RANGE and lunge_cd <= 0.0 and atk1_cd > 0.5:
					# Only lunge when both melee attacks are on cooldown
					_do_lunge()
				else:
					# Walk toward player
					var dir_x : float = float(sign(player.global_position.x - global_position.x))
					velocity.x = dir_x * spd
					_set_facing(dir_x)
					_play("run")

	move_and_slide()

# ─────────────────────────────────────────────────────────
# Attack Pattern Decision
# ─────────────────────────────────────────────────────────

# Can we attack at all right now?
func _can_attack(dist: float) -> bool:
	if dist > ATTACK_RANGE:
		return false
	return atk1_cd <= 0.0 or atk2_cd <= 0.0

func _decide_attack() -> void:
	atk_combo_count += 1
	# Pattern: ATK1, ATK1, ATK2, ATK1, ATK1, ATK2 ...
	# In phase 2: ATK1, ATK2, ATK1, ATK2 ...
	var do_heavy := false
	if phase2:
		do_heavy = (atk_combo_count % 2 == 0)   # every other hit is heavy
	else:
		do_heavy = (atk_combo_count % 3 == 0)   # every third hit is heavy

	if do_heavy and atk2_cd <= 0.0:
		_do_attack2()
	elif atk1_cd <= 0.0:
		_do_attack1()
	elif atk2_cd <= 0.0:
		# Fallback if ATK1 is on cooldown
		_do_attack2()

# ── Attack 1 — quick jab ──────────────────────────────────
func _do_attack1() -> void:
	state      = State.ATK1
	velocity.x = 0.0
	last_atk_was_2 = false
	if player != null:
		_set_facing(player.global_position.x - global_position.x)
	anim.play("attack 1")

# ── Attack 2 — heavy slam ─────────────────────────────────
func _do_attack2() -> void:
	state      = State.ATK2
	velocity.x = 0.0
	last_atk_was_2 = true
	if player != null:
		_set_facing(player.global_position.x - global_position.x)
	anim.play("attack 2")

# ── Lunge — Phase 2 dash attack ──────────────────────────
func _do_lunge() -> void:
	state       = State.LUNGE
	lunge_cd    = LUNGE_CD_TIME
	lunge_timer = LUNGE_DURATION
	var dir_x : float = float(sign(player.global_position.x - global_position.x))
	velocity.x  = dir_x * LUNGE_FORCE
	velocity.y  = -80.0   # slight arc
	_set_facing(dir_x)
	anim.play("attack 1")   # reuse attack 1 anim for lunge

func _finish_lunge() -> void:
	# Check hit at landing point
	if player != null and is_instance_valid(player) and _dist() <= ATTACK_RANGE + 50.0:
		if player.has_method("take_damage"):
			player.take_damage(DMG_LUNGE)
	atk1_cd = CD_ATK1_P2 if phase2 else CD_ATK1_P1
	state   = State.CHASE
	_play("run")

# ─────────────────────────────────────────────────────────
# Phase 2 Enrage
# ─────────────────────────────────────────────────────────
func _enter_phase2() -> void:
	phase2 = true
	# Reset combo so phase 2 starts fresh
	atk_combo_count = 0
	# Triple red flash
	for _i in 3:
		anim.modulate = Color(2.2, 0.2, 0.2, 1.0)
		await get_tree().create_timer(0.15).timeout
		anim.modulate = Color.WHITE
		await get_tree().create_timer(0.1).timeout
	# Permanent red tint in phase 2
	anim.modulate = Color(1.3, 0.6, 0.6, 1.0)

# ─────────────────────────────────────────────────────────
# Take Damage
# ─────────────────────────────────────────────────────────
func take_damage(amount: int) -> void:
	if state == State.DEAD:
		return
	current_hp = max(current_hp - amount, 0)
	if current_hp <= 0:
		_die()
		return
	# Shorter stun in phase 2 (boss barely flinches)
	state    = State.HIT
	hit_time = HIT_STUN_P2 if phase2 else HIT_STUN_P1
	velocity.x = 0.0
	anim.play("hit")

func _die() -> void:
	state    = State.DEAD
	velocity = Vector2.ZERO
	anim.modulate = Color.WHITE
	anim.play("death")
	set_collision_layer_value(1, false)
	set_collision_mask_value(1, false)

# ─────────────────────────────────────────────────────────
# Animation Finished Callbacks
# ─────────────────────────────────────────────────────────
func _on_anim_finished() -> void:
	match anim.animation:

		"attack 1":
			if state == State.LUNGE:
				pass   # lunge handled by timer, not animation
			elif state == State.ATK1 and not state == State.DEAD:
				# Deal damage at end of quick jab
				_apply_hit_damage(DMG_ATK1_P2 if phase2 else DMG_ATK1_P1)
				atk1_cd = CD_ATK1_P2 if phase2 else CD_ATK1_P1
				state   = State.CHASE
				_play("run")

		"attack 2":
			if state == State.ATK2 and state != State.DEAD:
				# Heavy slam — bigger hitbox (+25px) and more damage
				_apply_hit_damage(DMG_ATK2_P2 if phase2 else DMG_ATK2_P1, 25.0)
				atk2_cd = CD_ATK2_P2 if phase2 else CD_ATK2_P1
				state   = State.CHASE
				_play("run")

		"hit":
			# If hit_time already expired, recover immediately
			if state == State.HIT:
				hit_time = 0.0

		"death":
			await get_tree().create_timer(1.5).timeout
			queue_free()

		"idle", "run":
			pass   # these are looping — _on_anim_finished won't normally fire

# ─────────────────────────────────────────────────────────
# Helper — apply damage if player in range
func _apply_hit_damage(damage: int, extra_range: float = 0.0) -> void:
	if player == null or not is_instance_valid(player):
		return
	if _dist() <= ATTACK_RANGE + extra_range:
		if player.has_method("take_damage"):
			player.take_damage(damage)

# ─────────────────────────────────────────────────────────
# Area2D detection zone signals (if connected in editor)
# ─────────────────────────────────────────────────────────
func _on_area_2d_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player = body
		if state == State.IDLE:
			state = State.CHASE

func _on_area_2d_body_exited(body: Node2D) -> void:
	if body == player:
		player = null
		state  = State.IDLE
		_play("idle")

# ─────────────────────────────────────────────────────────
# Play animation safely (only if different)
func _play(anim_name: String) -> void:
	if anim.animation != anim_name or not anim.is_playing():
		anim.play(anim_name)

# Facing — sprite faces RIGHT by default
# flip_h = true → facing LEFT
func _set_facing(dir_x: float) -> void:
	if dir_x == 0.0:
		return
	facing_right = dir_x > 0.0
	anim.flip_h  = not facing_right   # flip when going LEFT

# Find player: group search + scene scan fallback
func _find_player() -> void:
	if player != null and is_instance_valid(player):
		return
	var arr := get_tree().get_nodes_in_group("player")
	if arr.size() > 0:
		player = arr[0]
		return
	# Scene scan fallback
	for child in get_tree().root.get_children():
		_scan_for_player(child)

func _scan_for_player(node: Node) -> void:
	if player != null: return
	if node is CharacterBody2D and not node.is_in_group("enemy"):
		player = node
		return
	for child in node.get_children():
		_scan_for_player(child)

func _dist() -> float:
	if player == null or not is_instance_valid(player):
		return 9999.0
	return global_position.distance_to(player.global_position)
