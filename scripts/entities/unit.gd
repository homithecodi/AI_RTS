class_name Unit
extends Entity
# Heading convention shared by every unit and structure: rotation.y = yaw means
# the model's local +Z faces (sin yaw, 0, cos yaw), so a world direction becomes
# a yaw with atan2(dir.x, dir.z). UnitModels and BuildingModels both build their
# models pointing down local +Z to match.

enum Order { NONE, MOVE, ATTACK, ATTACK_MOVE }

# Order is the player's intent; target is whatever the unit decided to shoot back.
# NONE means idle (and defending itself), MOVE means go to move_target and ignore
# enemies, ATTACK means stay near target, ATTACK_MOVE is MOVE but fights on the way.
var velocity := Vector3.ZERO
var move_target := Vector3.ZERO
var slot := Vector3.ZERO
var order_mode: int = Order.NONE
var target: Entity = null
var facing: float = 0.0
var cooldown: float = 0.0

# Model handles, resolved by UnitModels.build(). body and turret can be the same
# node (infantry), and muzzle may be null, in which case shots start at center().
var model_root: Node3D = null
var body: Node3D = null
var turret: Node3D = null
var muzzle: Node3D = null
var wheels: Array = []

var _grid_cell := Vector2i(99999, 99999)
var _wheel_spin: float = 0.0
var _bob: float = 0.0
var _turret_yaw: float = 0.0
var _retarget_timer: float = 0.0
var _spawn_credit: float = 0.55

const SEPARATION := 2.6
const BUILDING_CLEARANCE := 1.8

## Factory rather than a constructor: the node is fully built before it enters the
## tree, so nothing it creates ever sees an unparented node.
static func spawn(unit_id: String, in_team: int, pos: Vector3, w: Node3D,
		heading: float = 0.0) -> Unit:
	var u := Unit.new()
	var d := Defs.unit_def(unit_id).duplicate()
	d["id"] = unit_id
	u.setup(d, in_team, w)
	u.position = pos
	u.facing = heading
	u._turret_yaw = heading
	u._build_model()
	u.build_health_bar(float(d.get("height", 3.0)) + 0.5,
		2.2 if String(d.get("kind", "")) == "infantry" else 3.0)
	u.build_selection_ring(float(d.get("radius", 1.0)) + 0.8)
	return u

func _build_model() -> void:
	var parts := UnitModels.build(def_id, team)
	model_root = parts["root"]
	body = parts.get("body", model_root)
	turret = parts.get("turret", model_root)
	muzzle = parts.get("muzzle")
	wheels = parts.get("wheels", [])
	add_child(model_root)
	model_root.rotation.y = facing

## Collision radius, also the spacing used by formations and separation.
func radius() -> float:
	return float(def.get("radius", 1.0))

## Current speed in units per second, already reduced by a power brownout.
func speed() -> float:
	var s := float(def.get("speed", 5.0))
	var f := Game.faction(team)
	if f != null and f.is_low_power():
		s *= f.power_ratio()
	return s

func attack_range() -> float:
	return float(def.get("range", 10.0))

## How far the unit looks for something to shoot on its own.
func sight() -> float:
	return float(def.get("sight", 30.0))

## Slightly lower than the entity default: units are tracked around their middle so
## tracers do not sail over infantry.
func aim_height() -> float:
	return float(def.get("height", 2.0)) * 0.42

func is_moving() -> bool:
	return Vector2(velocity.x, velocity.z).length_squared() > 0.5

# --- orders --------------------------------------------------------------
## Walk to a world point. `new_slot` is a formation offset in the caller's frame,
# assigned by PlayerController._formation_offsets().
func order_move(dest: Vector3, new_slot: Vector3 = Vector3.ZERO) -> void:
	move_target = Vector3(dest.x, global_position.y, dest.z)
	slot = new_slot
	order_mode = Order.MOVE
	target = null
	cooldown = minf(cooldown, 0.25)

## Walk to a point but engage anything met on the way.
func order_attack_move(dest: Vector3, new_slot: Vector3 = Vector3.ZERO) -> void:
	move_target = Vector3(dest.x, global_position.y, dest.z)
	slot = new_slot
	order_mode = Order.ATTACK_MOVE
	target = null

## Focus a specific target, moving to within weapon range.
func order_attack(t: Entity) -> void:
	order_mode = Order.ATTACK
	target = t

func order_stop() -> void:
	order_mode = Order.NONE
	move_target = global_position
	target = null
	velocity = Vector3.ZERO

## Being shot at while idle makes the unit fight back.
func on_damaged(source: Entity) -> void:
	if source == null or dead or source.team == team:
		return
	if order_mode == Order.NONE:
		order_mode = Order.ATTACK
		target = source

# --- main loop -----------------------------------------------------------
# Three separate passes, in this order: decide, move, then present. Keeping them
# apart means movement never reads a half-updated facing, and presentation can be
# skipped without affecting simulation.
func _physics_process(delta: float) -> void:
	if dead:
		return
	_think(delta)
	_move(delta)
	_apply(delta)

## Target selection and firing. Retargeting is on a randomised timer so a crowd does
# not re-query on the same frame.
func _think(delta: float) -> void:
	if target != null and (target.dead or not is_instance_valid(target)):
		target = null
	if order_mode == Order.ATTACK and target == null:
		order_mode = Order.NONE

	_retarget_timer -= delta
	if _retarget_timer <= 0.0:
		_retarget_timer = 0.28 + randf() * 0.22
		if target == null or distance_to(target) > attack_range() * 1.3:
			_acquire_target()

	cooldown = maxf(cooldown - delta, 0.0)
	if target != null and cooldown <= 0.0 and distance_to(target) <= attack_range():
		_fire(target)

## Pick something to shoot, within a radius that depends on what the unit was told to
## do. An idle unit keeps a short leash so it defends its position rather than
## wandering off.
func _acquire_target() -> void:
	var scan := sight()
	match order_mode:
		Order.NONE:
			scan = minf(scan, 26.0)
		Order.MOVE:
			scan = attack_range() * 1.15
		_:
			scan = sight()
	var found := world.find_enemy_in_radius(global_position, scan, self)
	if found != null:
		target = found

## Fire at a target. Units with a "projectile" stat launch a travelling shell;
## everything else is hitscan, drawn as a tracer so the player can still read where
## the shot came from.
func _fire(t: Entity) -> void:
	cooldown = float(def.get("cooldown", 1.0))
	var dmg := float(def.get("damage", 10.0)) * _damage_vs(t)
	var muzzle_pos := muzzle.global_position if muzzle != null else center()
	var infantry := String(def.get("kind", "")) == "infantry"
	var flash := Color(1.0, 0.95, 0.72) if infantry else Color(1.0, 0.8, 0.42)
	var size := 0.7 if infantry else 1.25

	if bool(def.get("projectile", false)):
		Projectile.fire(world.effects, muzzle_pos, t, dmg,
			float(def.get("splash", 0.0)), team, world, self)
		Effects.muzzle_flash(world.effects, muzzle_pos, Color(1.0, 0.7, 0.3), 0.9)
	else:
		Effects.tracer(world.effects, muzzle_pos, t.center(), flash, 0.09)
		Effects.muzzle_flash(world.effects, muzzle_pos, flash, size)
		_apply_damage(t, dmg)

## Route one hit, either as area damage around the target or straight onto it. The
## attacker is always `self`, which is what the damage statistics and kill credit are
## attributed to.
func _apply_damage(t: Entity, dmg: float) -> void:
	var splash := float(def.get("splash", 0.0))
	if splash > 0.1:
		world.splash_damage(t.center(), splash, dmg, team, self)
	else:
		t.take_damage(dmg, team, self)

## Damage multiplier from the "vs_" stats: infantry trade well against infantry and
## badly against armour, and so on.
func _damage_vs(t: Entity) -> float:
	match String(t.def.get("kind", "")):
		"vehicle":
			return float(def.get("vs_vehicle", 1.0))
		"infantry":
			return float(def.get("vs_infantry", 1.0))
	return 1.0

# --- movement ------------------------------------------------------------
# Steering is deliberately not a pathfinder. Units drive straight at their goal and
# resolve conflicts by pushing apart, which is enough for the open maps here and keeps
# movement cheap at a few hundred units.
#
# The resulting velocity is smoothed rather than applied directly, so units lean into
# turns instead of snapping, and never exceed their top speed when forces combine.

## Decide where the unit wants to be and build a desired velocity for it.
func _move(delta: float) -> void:
	var destination := global_position
	var wants_to_go := false
	var hold := attack_range() * 0.82

	match order_mode:
		Order.MOVE, Order.ATTACK_MOVE:
			destination = move_target + slot
			wants_to_go = true
		Order.ATTACK, Order.NONE:
			if target != null and not target.dead:
				destination = target.global_position
				wants_to_go = distance_to(target) > hold

	# Units moving under a plain move order keep firing whatever they pass.
	if order_mode == Order.MOVE and target != null \
			and distance_to(target) <= attack_range():
		wants_to_go = false

	var to := destination - global_position
	to.y = 0.0
	var dist := to.length()
	if wants_to_go and dist <= 1.0:
		if order_mode == Order.MOVE or order_mode == Order.ATTACK_MOVE:
			order_mode = Order.NONE
			move_target = global_position
			slot = Vector3.ZERO
		wants_to_go = false

	var desired := Vector3.ZERO
	if wants_to_go and dist > 0.01:
		var ramp := clampf(dist / 5.0, 0.3, 1.0)
		desired = to / dist * speed() * ramp

	desired += _separation_force() * (1.0 if wants_to_go else 0.55)
	desired += _avoid_buildings()

	var limited := desired.limit_length(speed())
	velocity = velocity.lerp(limited, 1.0 - exp(-9.0 * delta))
	if velocity.length_squared() < 0.01:
		velocity = Vector3.ZERO

## Cap on how hard separation and obstacle avoidance can push, so a crowd cannot
## launch a unit across the map.
func _max_force() -> float:
	return maxf(speed() * 1.2, 2.0)

## Push away from crowded neighbours. Weighted by how much closer than the combined
## radii the pair already is, and applied even when stationary so idle formations do
## not overlap.
func _separation_force() -> Vector3:
	var push := Vector3.ZERO
	for other: Unit in world.query_units(global_position, SEPARATION + radius()):
		if other == self or other.dead:
			continue
		var away := global_position - other.global_position
		away.y = 0.0
		var d := away.length()
		var want := SEPARATION + radius() + other.radius()
		if d < want and d > 0.001:
			push += away / d * (want - d) * 3.4
	return push.limit_length(_max_force())

## Push out of structures the unit has walked into. Tested against the rectangle
## rather than a radius, so units slide along walls instead of sticking to them.
func _avoid_buildings() -> Vector3:
	var push := Vector3.ZERO
	for b: Building in world.query_buildings(global_position, 15.0):
		var half := Vector2(float(b.def.get("size_x", 6.0)), float(b.def.get("size_z", 6.0))) * 0.5
		var center := Vector2(b.global_position.x, b.global_position.z)
		var here := Vector2(global_position.x, global_position.z)
		var delta := here - center
		var nearest := center + Vector2(
			clampf(delta.x, -half.x, half.x),
			clampf(delta.y, -half.y, half.y))
		var away := here - nearest
		var d := away.length()
		var margin := BUILDING_CLEARANCE + radius()
		if d < margin:
			if d < 0.01:
				away = delta if delta.length_squared() > 0.001 else Vector2(1, 0)
				d = 0.01
			push += Vector3(away.x, 0.0, away.y) / d * (margin - d) * 7.0
	return push.limit_length(_max_force())

## Commit the frame: integrate the velocity, sit on the terrain, refresh the spatial
## grid, then update every animated part of the model.
func _apply(delta: float) -> void:
	global_position += velocity * delta
	if world.terrain != null:
		global_position.y = world.terrain.height_at(global_position.x, global_position.z)
	world.refresh_unit_grid(self)

	var flat_speed := Vector3(velocity.x, 0.0, velocity.z)
	var speed_len := flat_speed.length()
	if speed_len > 0.35:
		facing = _turn_toward(facing, atan2(flat_speed.x, flat_speed.z), delta * 7.0)

	# The turret tracks its target (or straight ahead) in world space, then stores the
	# difference from the hull so it inherits the body's turn for free.
	var aim := facing
	if target != null and not target.dead:
		aim = atan2(target.global_position.x - global_position.x,
			target.global_position.z - global_position.z)
	_turret_yaw = _turn_toward(_turret_yaw, aim, delta * 6.0)

	if model_root != null:
		model_root.rotation.y = facing
	if turret != null:
		turret.rotation.y = wrapf(_turret_yaw - facing, -PI, PI)

	# Vehicles roll their wheels; infantry bob instead. Spin is about X because
	# MeshKit.wheel lays the cylinder's axle along local X.
	if wheels.size() > 0:
		if speed_len > 0.2:
			_wheel_spin += speed_len * delta / 0.42
		for w in wheels:
			# MeshKit.wheel builds a cylinder whose axis ends up along local X
			# (it is rotated PI/2 about Z), so the wheel rolls about X. Spinning
			# about Y would swing the axle around instead of turning the wheel.
			w.rotation.x = _wheel_spin
	elif body != null and body != turret:
		_bob += speed_len * delta * 2.2
		var amp := clampf(speed_len / maxf(speed(), 0.1), 0.0, 1.0) * 0.07
		body.position.y = absf(sin(_bob)) * amp
		body.rotation.x = sin(_bob * 2.0) * amp * 0.6

	# Spawn pop: the model grows from a quarter size over half a second.
	if _spawn_credit > 0.0:
		_spawn_credit -= delta
		if model_root != null:
			var t := 1.0 - clampf(_spawn_credit / 0.55, 0.0, 1.0)
			model_root.scale = Vector3.ONE * (0.25 + 0.75 * t)

	_update_overlay()

# Unwrapped turning avoids visible snapping when crossing +/-PI.
func _turn_toward(from: float, to: float, max_step: float) -> float:
	var diff := wrapf(to - from, -PI, PI)
	if absf(diff) <= max_step:
		return from + diff
	return from + signf(diff) * max_step

## Infantry die in a puff; vehicles leave a wreck. Deliberately asymmetric so the
## player can read what was lost from across the map.
func die(killer: Entity = null) -> void:
	if dead:
		return
	var size := 0.65 if String(def.get("kind", "infantry")) == "infantry" else 1.5
	if world != null:
		Effects.explosion(world.effects, center(), size)
		Effects.wreck(world.effects, global_position, size * 0.75)
	_finish_death(killer)