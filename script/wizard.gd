extends CharacterBody2D

# ═══════════════════════════════════════════════════════════
#  Dungeon Dash — ULTRA ELITE WIZARD BOSS (GOD MODE)
#
#  Fixes: 
#    - Removed long stagger (stun-lock prevention)
#    - Added Hyper Armor (cannot be interrupted during attacks)
#    - Increased DMG (Base 65, Enraged 100)
#    - Faster Teleportation
# ═══════════════════════════════════════════════════════════

# ── God Stats ──────────────────────────────────────────────
const MAX_HP            : int   = 1200
const DAMAGE_P1         : int   = 65
const DAMAGE_P2         : int   = 100
const SPEED_P1          : float = 180.0
const SPEED_P2          : float = 260.0

const ATK_CD_P1         : float = 0.1
const ATK_CD_P2         : float = 0.05
const TELEPORT_CD_TIME  : float = 2.5
const HIT_STUN_TIME     : float = 0.1
const STUN_RESIST_CD    : float = 1.0

const DETECT_RANGE      : float = 500.0
const ATTACK_RANGE      : float = 130.0
const WAVE_INTERVAL     : float = 12.0

# ─────────────────────────────────────────────────────────
const MINION_SCENE = preload("res://scenes/kuttykunjan.tscn")

enum State { IDLE, CHASE, ATK1, HIT, DEAD, TELEPORT }
var state       : State = State.IDLE
var current_hp  : int   = MAX_HP
var phase2      : bool  = false
var facing_right: bool  = true

# Timers
var atk_cd       : float = 0.0
var teleport_cd  : float = 0.0
var stun_resi_cd : float = 0.0
var wave_timer   : float = 3.0
var hit_time     : float = 0.0
var walk_cd      : float = 0.0
var attack_state_timer : float = 0.0 # To finish attack state even if loop=true

var player : Node2D = null

@onready var anim   : AnimatedSprite2D = $AnimatedSprite2D
@onready var hp_bar : ProgressBar      = $HealthBar

# ═══════════════════════════════════════════════════════════
func _ready() -> void:
	add_to_group("enemy")
	current_hp = MAX_HP
	if hp_bar:
		hp_bar.max_value = MAX_HP
		hp_bar.value     = MAX_HP
	anim.animation_finished.connect(_on_anim_finished)

func _physics_process(delta: float) -> void:
	if state == State.DEAD or state == State.TELEPORT: return

	if not is_on_floor(): velocity += get_gravity() * delta

	# Ticking
	if atk_cd       > 0.0: atk_cd       -= delta
	if teleport_cd  > 0.0: teleport_cd  -= delta
	if stun_resi_cd > 0.0: stun_resi_cd -= delta
	if walk_cd      > 0.0: walk_cd      -= delta
	if hit_time     > 0.0: hit_time     -= delta
	if attack_state_timer > 0.0:
		attack_state_timer -= delta
		if attack_state_timer <= 0:
			_apply_dmg()
			state = State.CHASE
	
	_find_player()
	
	if player and _dist() < DETECT_RANGE:
		wave_timer -= delta
		if wave_timer <= 0:
			_spawn_minions()
			wave_timer = WAVE_INTERVAL

	# Reset hit state
	if state == State.HIT and hit_time <= 0:
		state = State.CHASE
		anim.modulate = Color.WHITE

	# Phase 2
	if not phase2 and current_hp <= MAX_HP/2:
		phase2 = true
		anim.modulate = Color(2, 0.5, 0.5, 1) # Red glow

	# Hyper Armor: Don't allow Hit state during attacks
	if state == State.ATK1:
		velocity.x = move_toward(velocity.x, 0, 400*delta) # Graceful slide forward
		move_and_slide()
		return

	if state == State.HIT:
		velocity.x = move_toward(velocity.x, 0, 400*delta)
		move_and_slide()
		return

	# Logic
	velocity.x = 0
	if player:
		var d = _dist()
		if d < DETECT_RANGE:
			if d <= ATTACK_RANGE and atk_cd <= 0:
				_do_attack()
			elif d > ATTACK_RANGE and d < 400 and teleport_cd <= 0:
				_teleport()
			else:
				var spd = SPEED_P2 if phase2 else SPEED_P1
				var dir = float(sign(player.global_position.x - global_position.x))
				velocity.x = dir * spd
				_set_facing(dir)
				if walk_cd <= 0:
					anim.play("run ")
					walk_cd = 0.3
		else:
			_play("idle")
	
	move_and_slide()

# ─────────────────────────────────────────────────────────
func _do_attack() -> void:
	state = State.ATK1
	atk_cd = ATK_CD_P2 if phase2 else ATK_CD_P1
	attack_state_timer = 0.5 # Faster attack duration
	
	var dir = sign(player.global_position.x - global_position.x)
	_set_facing(dir)
	# Aggressive lunge forward!
	velocity.x = dir * (SPEED_P2 if phase2 else SPEED_P1) * 1.5 
	anim.play("attack 2" if randf() > 0.3 else "attack 1")

func _teleport() -> void:
	state = State.TELEPORT
	teleport_cd = TELEPORT_CD_TIME
	anim.modulate.a = 0.1
	await get_tree().create_timer(0.2).timeout
	
	# Aggressive: Teleport right next to / behind the player
	var dir = sign(player.global_position.x - global_position.x)
	if dir == 0: dir = 1
	# Teleport slightly past the player to backstab
	global_position.x = player.global_position.x + (dir * 60.0)
	global_position.y = player.global_position.y - 5.0
	
	anim.modulate.a = 1.0
	state = State.CHASE

func _spawn_minions() -> void:
	for i in (5 if phase2 else 3):
		var m = MINION_SCENE.instantiate()
		m.position = global_position + Vector2(randf_range(-100, 100), -20)
		get_parent().add_child(m)

# ─────────────────────────────────────────────────────────
func take_damage(amount: int) -> void:
	if state == State.DEAD: return
	current_hp -= amount
	
	if hp_bar:
		var t = create_tween()
		t.tween_property(hp_bar, "value", float(current_hp), 0.2)

	if current_hp <= 0:
		_die()
		return

	# STUN RESISTANCE / HYPER ARMOR
	# Wizard only flinches if NOT attacking and stun is not on cooldown
	if state != State.ATK1 and stun_resi_cd <= 0:
		state = State.HIT
		hit_time = HIT_STUN_TIME
		stun_resi_cd = STUN_RESIST_CD
		anim.play("hit")
	else:
		# Just flash red but continue attacking/moving
		var t = create_tween()
		anim.modulate = Color.RED
		t.tween_property(anim, "modulate", Color.WHITE if not phase2 else Color(2, 0.5, 0.5, 1), 0.1)

func _die() -> void:
	state = State.DEAD
	if hp_bar: hp_bar.visible = false
	anim.play("death")
	collision_layer = 0
	collision_mask = 0

func _on_anim_finished() -> void:
	if anim.animation.begins_with("attack"):
		_apply_dmg()
		state = State.CHASE
	elif anim.animation == "death":
		await get_tree().create_timer(1.2).timeout
		queue_free()

func _apply_dmg() -> void:
	if player and _dist() <= ATTACK_RANGE + 20:
		player.take_damage(DAMAGE_P2 if phase2 else DAMAGE_P1)

func _set_facing(d: float) -> void:
	if d != 0: anim.flip_h = d > 0 # Evil Wizard faces LEFT natively by default. d>0 means player is right -> flip_h=true to face right.

func _play(n: String) -> void:
	if anim.animation != n: anim.play(n)

func _find_player() -> void:
	var p = get_tree().get_nodes_in_group("player")
	if p.size() > 0: player = p[0]

func _dist() -> float:
	return global_position.distance_to(player.global_position) if player else 9999.0
