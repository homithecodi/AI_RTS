class_name Building
extends Entity
# A structure: something that sits still and does one job.
#
# Two families share this class:
#   * producers (barracks, war factory) run a build queue and spawn units at the exit
#     point
#   * gatherers (ore refinery) drain nearby ore fields into the faction's income
#   * defence towers are weapons, and use rotation.y as their aim reference
#
# `active` is the finished-construction flag; almost nothing works until it is true,
# and the power grid and the production UI both key off it.

var active: bool = false
var build_progress: float = 0.0
var queue: Array[Dictionary] = []
var rally_point := Vector3.ZERO
var rally_set: bool = false
var income: float = 0.0

var model_root: Node3D = null
var turret: Node3D = null
var muzzle: Node3D = null

var _ore_nodes: Array[OreNode] = []
var _cooldown: float = 0.0
var _grid_cell := Vector2i(99999, 99999)
var _scan_timer: float = 0.0

const DEFAULT_RALLY_DIST := 10.0

# The node must already be inside the tree before this runs: exit points and ore
# gathering both need a valid global transform.
## Build a structure from its id. This is the whole construction sequence in one
## place, and it runs after the node has been added to the scene tree.
##
## `heading` is the yaw used for the model's facing and, for weapons, as the datum
## the turret is measured against. `instant` skips the build-up animation and starts
## the structure fully operational.
func initialize(building_id: String, in_team: int, pos: Vector3, w: GameWorld,
		heading: float, instant: bool) -> void:
	var d := Defs.building_def(building_id).duplicate()
	d["id"] = building_id
	setup(d, in_team, w)
	Game.register_building(self)
	position = pos
	rotation.y = heading
	_build_model()
	build_health_bar(float(d.get("height", 5.0)) + 0.7,
		maxf(float(d.get("size_x", 6.0)), float(d.get("size_z", 6.0))) * 0.5)
	build_selection_ring(float(d.get("footprint", 6.0)) * 0.62)
	rally_point = default_rally_point()
	if instant:
		finish_construction()
	elif model_root != null:
		model_root.scale = Vector3(1.0, 0.12, 1.0)

func _build_model() -> void:
	var parts := BuildingModels.build(def_id, team)
	model_root = parts["root"]
	turret = parts.get("turret")
	muzzle = parts.get("muzzle")
	add_child(model_root)

## Circular radius used for spacing, placement checks and the selection ring.
func footprint_radius() -> float:
	return float(def.get("footprint", 6.0)) * 0.5

## World position just outside the door, where finished units appear. Rotated by the
## structure's heading.
func exit_point() -> Vector3:
	return global_position + _front_offset(float(def.get("size_z", 6.0)) * 0.5 + 4.0)

## Where freshly produced units walk to, and the fallback whenever no rally point
## has been set. The offset is rotated by the heading so it stays in front of the
## structure's door instead of drifting sideways on a rotated one.
func default_rally_point() -> Vector3:
	return exit_point() + _front_offset(DEFAULT_RALLY_DIST)

func _front_offset(distance: float) -> Vector3:
	return Vector3(0.0, 0.0, distance).rotated(Vector3.UP, rotation.y)

## Unit ids this structure can build, empty for everything else.
func produces() -> Array:
	return def.get("units", []) as Array

## True when this structure could start building `unit_id` right now: finished, able
## to build it, and the faction can pay for it.
func can_queue(unit_id: String) -> bool:
	if not active or not produces().has(unit_id):
		return false
	var f := Game.faction(team)
	return f != null and f.can_afford(float(Defs.unit_def(unit_id).get("cost", 0)))

## Add a unit to the build queue and pay for it up front. Refunds are handled by
## cancel_queue_entry().
func enqueue(unit_id: String) -> bool:
	if not can_queue(unit_id):
		return false
	var f := Game.faction(team)
	var ud := Defs.unit_def(unit_id)
	var cost := float(ud.get("cost", 0))
	if not f.spend(cost):
		return false
	f.units_built += 1
	queue.append({
		"id": unit_id,
		"cost": cost,
		"remaining": float(ud.get("build_time", 10.0)),
		"total": float(ud.get("build_time", 10.0)),
	})
	return true

## Refund and drop a queued entry. The refund is deliberately partial so cancelling
## is a real decision rather than a free undo.
func cancel_queue_entry(index: int) -> void:
	if index < 0 or index >= queue.size():
		return
	var item: Dictionary = queue[index]
	var f := Game.faction(team)
	if f != null:
		f.ore += float(item["cost"]) * 0.75
	queue.remove_at(index)

func queue_head_id() -> String:
	if queue.is_empty():
		return ""
	return String(queue[0]["id"])

## Complete construction: become operational, pop the dust effect, claim nearby ore
## fields, and re-register so the power grid picks the structure up.
func finish_construction() -> void:
	build_progress = 1.0
	active = true
	if model_root != null:
		model_root.scale = Vector3.ONE
	if world != null:
		Effects.dust(world.effects, global_position + Vector3(0, 0.5, 0), footprint_radius())
		if def.has("gather_radius"):
			_collect_ore_nodes()
	# Re-register so the power grid picks this structure up.
	Game.register_building(self)

## True for structures with a weapon (defence towers).
func is_weapon() -> bool:
	return def.has("range")

# --- per-frame ------------------------------------------------------------
func _process(delta: float) -> void:
	if dead:
		return
	if active:
		_tick_queue(delta)
		_tick_income(delta)
		_tick_weapon(delta)
	else:
		_tick_construction(delta)
	_update_overlay()

## Raise the model out of the ground over the structure's build time.
func _tick_construction(delta: float) -> void:
	if build_progress >= 1.0:
		return
	build_progress += delta / maxf(float(def.get("build_time", 10.0)), 0.5)
	if model_root != null:
		var t := clampf(build_progress, 0.0, 1.0)
		model_root.scale = Vector3(1.0, lerpf(0.12, 1.0, t), 1.0)
	if build_progress >= 1.0:
		finish_construction()

## Advance the front of the build queue. A brownout slows production through
## power_ratio() rather than stopping it.
func _tick_queue(delta: float) -> void:
	if queue.is_empty():
		return
	var f := Game.faction(team)
	var rate := 1.0
	if f != null and f.is_low_power():
		rate = f.power_ratio()
	var head: Dictionary = queue[0]
	head["remaining"] = float(head["remaining"]) - delta * rate
	if float(head["remaining"]) <= 0.0:
		queue.remove_at(0)
		_deliver(String(head["id"]))

## Spawn the finished unit at the door and send it to the rally point.
##
## Units leave facing the structure's heading, so they march away from the door. The
## rally point is reset if the player parked it on top of the building, which makes it
## impossible to trap newly produced units.
func _deliver(unit_id: String) -> void:
	var exit := exit_point()
	exit.y = world.terrain.height_at(exit.x, exit.z)
	var u := world.spawn_unit(unit_id, team, exit, rotation.y)
	if u != null and not produces().is_empty():
		var dest := rally_point if rally_set else default_rally_point()
		dest.x = clampf(dest.x, -world.map_half() + 8.0, world.map_half() - 8.0)
		dest.z = clampf(dest.z, -world.map_half() + 8.0, world.map_half() - 8.0)
		dest.y = world.terrain.height_at(dest.x, dest.z)
		u.order_move(dest)
		u.slot = _rally_slot(u)
	if rally_set and rally_point.distance_to(global_position) < 3.0:
		rally_point = default_rally_point()

## Grid slot for the n-th unit heading to the rally point, so a barracks does not
## deliver its whole queue to the same spot.
func _rally_slot(_u: Unit) -> Vector3:
	var others := rally_members().size()
	if others <= 1:
		return Vector3.ZERO
	var idx := others - 1
	var cols := maxi(1, int(ceil(sqrt(float(others)))))
	var col := idx % cols
	var row := idx / cols
	var spacing := 3.4
	return Vector3((float(col) - (float(cols) - 1.0) * 0.5) * spacing, 0.0,
		float(row) * spacing * 0.8)

## Units on their way to this structure's rally point. Used only to size the rally
## grid, so it matches loosely (still heading there, roughly close).
func rally_members() -> Array[Unit]:
	var out: Array[Unit] = []
	var f := Game.faction(team)
	if f == null:
		return out
	for u in f.units:
		if not u.dead and u.order_mode == Unit.Order.MOVE \
				and u.move_target.distance_to(rally_point) < 6.0:
			out.append(u)
	return out

## Claim the ore fields this refinery will draw from, nearest first, capped by
## max_nodes. Run once on completion; fields never move, so no re-scan is needed.
func _collect_ore_nodes() -> void:
	_ore_nodes.clear()
	var radius := float(def.get("gather_radius", 50.0))
	var limit := int(def.get("max_nodes", 4))
	var found := world.ore_nodes_in_radius(global_position, radius)
	found.sort_custom(func(a: OreNode, b: OreNode) -> bool:
		return a.global_position.distance_to(global_position) \
			< b.global_position.distance_to(global_position))
	for n in found:
		if _ore_nodes.size() >= limit:
			break
		if n.active:
			_ore_nodes.append(n)

## Drain the claimed ore fields and publish the per-second rate, which is what the
## HUD shows and what Faction.tick_economy() banks.
func _tick_income(delta: float) -> void:
	if _ore_nodes.is_empty() or delta <= 0.0:
		income = 0.0
		return
	var rate := float(def.get("gather_rate", 2.0))
	var gained := 0.0
	for n in _ore_nodes:
		if not is_instance_valid(n) or not n.active:
			continue
		gained += n.take(rate * delta)
	income = gained / delta

## Turret behaviour. Target scanning is throttled to 4 Hz independently of firing, so
## a field full of towers does not re-query every frame; the turret keeps tracking
## between shots.
##
## The aim is converted from a world yaw into the structure's local frame, since the
## turret hangs under a node that is already rotated by rotation.y.
## Turret behaviour. Target scanning is throttled to 4 Hz independently of firing, so
## a field full of towers does not re-query every frame; the turret keeps tracking
## between shots.
##
## The aim is converted from a world yaw into the structure's local frame, since the
## turret hangs under a node that is already rotated by rotation.y.
func _tick_weapon(delta: float) -> void:
	if not is_weapon() or turret == null:
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	var reach := float(def.get("range", 30.0))
	_scan_timer -= delta
	if _scan_timer > 0.0:
		return
	_scan_timer = 0.25
	var found := world.find_enemy_in_radius(global_position, reach + 6.0, self)
	if found == null:
		return
	var aim := atan2(found.global_position.x - global_position.x,
		found.global_position.z - global_position.z)
	turret.rotation.y = wrapf(aim - rotation.y, -PI, PI)
	if _cooldown > 0.0 or distance_to(found) > reach:
		return
	_cooldown = float(def.get("cooldown", 1.2))
	var dmg := float(def.get("damage", 50.0))
	var muzzle_pos := muzzle.global_position if muzzle != null else center()
	Effects.tracer(world.effects, muzzle_pos, found.center(), Color(1.0, 0.75, 0.35), 0.1)
	Effects.muzzle_flash(world.effects, muzzle_pos, Color(1.0, 0.7, 0.3), 1.3)
	found.take_damage(dmg, team, self)

## Big structure explosion: a central blast, a scorch mark and a wreck, plus two
## offset fireballs so it does not read as a single sphere.
func die(killer: Entity = null) -> void:
	if dead:
		return
	var size := maxf(footprint_radius() * 0.55, 1.0)
	if world != null:
		Effects.explosion(world.effects, center(), size * 1.6)
		Effects.wreck(world.effects, global_position, size)
		Effects.explosion(world.effects, global_position + Vector3(1.5, 0.5, 0), size)
		Effects.explosion(world.effects, global_position + Vector3(-1.5, 0.5, 1.0), size)
	_finish_death(killer)