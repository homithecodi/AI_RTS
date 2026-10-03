class_name EnemyAI
extends Node
# A classic Generals-style opponent: it builds an economy, keeps a production
# line running, garrisons its base and periodically launches attack waves.

signal ai_event(text: String)

const DEFEND_RADIUS := 105.0
const STAGING_DISTANCE := 34.0
const BUILD_COOLDOWN := 11.0
const MAX_BUILDINGS := 15
const MAX_ARMY := 22
const MIN_ARMY := 6

var world: GameWorld = null
var team: int = Defs.TEAM_ENEMY
var difficulty: float = 1.0
var reserve: float = 400.0

var _attack_group: Array[Unit] = []
var _attacking: bool = false
var _wave_number: int = 0
var _next_wave_in: float = 55.0
var _wave_cooldown: float = 0.0
var _last_build_at: float = -99.0
var _think_econ: float = 0.0
var _think_prod: float = 0.0
var _think_army: float = 0.0
var _think_garrison: float = 0.0

func setup(w: GameWorld, level: float = 1.0) -> void:
	world = w
	team = Defs.TEAM_ENEMY
	difficulty = level
	var f := Game.faction(team)
	if f != null:
		f.income_bonus = 0.9 + 0.3 * level
	reserve = 700.0 - 300.0 * level
	_next_wave_in = 50.0 - 10.0 * level

func base() -> Vector3:
	return world.base_pos(team)

func staging_point() -> Vector3:
	var b := base()
	var out := Vector3(-b.x, 0.0, -b.z)
	if out.length() < 0.01:
		out = Vector3(0, 0, -1)
	return b + out.normalized() * STAGING_DISTANCE

func _process(delta: float) -> void:
	if world == null or Game.match_over or Game.paused:
		return
	if not Game.started:
		return
	var f := Game.faction(team)
	if f == null or not f.is_alive():
		return

	_think_econ -= delta
	if _think_econ <= 0.0:
		_think_econ = 0.9
		_build_structure()
	_think_prod -= delta
	if _think_prod <= 0.0:
		_think_prod = 0.6
		_produce_units()
	_think_army -= delta
	if _think_army <= 0.0:
		_think_army = 0.5
		_manage_army()
	_think_garrison -= delta
	if _think_garrison <= 0.0:
		_think_garrison = 4.0
		_garrison()
	if _attacking:
		_wave_cooldown += delta

func _count(def_id: String) -> int:
	var n := 0
	var f := Game.faction(team)
	if f == null:
		return 0
	for b in f.buildings:
		if b.def_id == def_id and not b.dead:
			n += 1
	return n

func _total_buildings() -> int:
	var f := Game.faction(team)
	return 0 if f == null else f.buildings.size()

func _unit_count(def_id: String) -> int:
	var n := 0
	var f := Game.faction(team)
	if f == null:
		return 0
	for u in f.units:
		if u.def_id == def_id and not u.dead:
			n += 1
	return n

func _total_units() -> int:
	var f := Game.faction(team)
	return 0 if f == null else f.units.size()

# --- base building -------------------------------------------------------
func _build_structure() -> void:
	var f := Game.faction(team)
	if f == null:
		return
	if Game.elapsed - _last_build_at < BUILD_COOLDOWN:
		return
	var wanted := _next_structure()
	if wanted == "":
		return
	var cost := float(Defs.building_def(wanted).get("cost", 0))
	if f.ore < cost + reserve:
		return
	var spot := _structure_spot(wanted)
	if spot == Vector3.INF:
		return
	if not f.spend(cost):
		return
	_last_build_at = Game.elapsed
	world.spawn_building(wanted, team, spot, _facing_for(wanted, spot), false)
	ai_event.emit("Enemy built %s" % String(Defs.building_def(wanted).get("name", wanted)))

func _next_structure() -> String:
	var f := Game.faction(team)
	if f == null:
		return ""
	if _total_buildings() >= MAX_BUILDINGS:
		return ""
	if f.is_low_power():
		return "power_plant"
	if _under_attack() and _count("defense_tower") < 2 and f.ore > 1500.0:
		return "defense_tower"
	if _count("refinery") < 1:
		return "refinery"
	if _count("barracks") < 1:
		return "barracks"
	if _count("refinery") < 2:
		return "refinery"
	if _count("war_factory") < 1:
		return "war_factory"
	if _count("refinery") < 3:
		return "refinery"
	if _count("barracks") < 2:
		return "barracks"
	if _count("war_factory") < 2:
		return "war_factory"
	if _count("refinery") < 5:
		return "refinery"
	if f.income_rate > 16.0 and _count("defense_tower") < 2 + int(difficulty):
		return "defense_tower"
	if f.ore > 4000.0 and _count("power_plant") < 3:
		return "power_plant"
	return ""

func _under_attack() -> bool:
	return _threat_position() != Vector3.INF

func _threat_position() -> Vector3:
	var b := base()
	var f := Game.faction(team)
	if f == null:
		return Vector3.INF
	for u in f.units:
		if u.dead:
			continue
		if u.global_position.distance_to(b) < DEFEND_RADIUS \
				and _is_enemy_near(u.global_position, 22.0):
			return u.global_position
	return Vector3.INF

func _is_enemy_near(pos: Vector3, radius: float) -> bool:
	for other in world.query_units(pos, radius):
		if other.team != team and not other.dead:
			return true
	return false

func _structure_spot(building_id: String) -> Vector3:
	var b := base()
	var forward := Vector3(-b.x, 0.0, -b.z)
	if forward.length() < 0.01:
		forward = Vector3(0, 0, -1)
	forward = forward.normalized()
	var right := Vector3(forward.z, 0, -forward.x)

	if building_id == "refinery":
		var cluster := _best_cluster()
		if cluster.is_empty():
			return Vector3.INF
		var cpos: Vector2 = cluster["pos"]
		var cradius: float = cluster["radius"]
		var to_base := (b - Vector3(cpos.x, 0, cpos.y))
		to_base.y = 0.0
		if to_base.length() < 0.01:
			to_base = Vector3(1, 0, 0)
		to_base = to_base.normalized()
		var anchor := Vector3(cpos.x, 0, cpos.y) + to_base * (cradius + 8.0)
		return _find_spot_near(anchor, 26.0, building_id)

	# Ordinary structures ring the base, away from the map edge.
	var rings := [26.0, 40.0, 54.0, 68.0]
	var start := randf() * TAU
	for r in rings:
		for i in 10:
			var a := start + TAU * float(i) / 10.0 + float(r) * 0.21
			var p := b + forward * float(r) * (0.35 + 0.65 * absf(sin(a))) \
				+ right * cos(a) * float(r) * 0.9
			p.y = 0.0
			p = world.clamp_to_map(p)
			if _valid_spot(building_id, p):
				return p
	return Vector3.INF

func _best_cluster() -> Dictionary:
	var best: Dictionary = {}
	var best_score := INF
	for c in world.ore_clusters:
		var cpos: Vector2 = c["pos"]
		var remaining := 0.0
		for n in world.ore_nodes:
			if is_instance_valid(n) and n.active \
					and Vector2(n.global_position.x, n.global_position.z).distance_to(cpos) \
					< float(c["radius"]):
				remaining += n.amount
		if remaining <= 0.0:
			continue
		var served := 0
		var f := Game.faction(team)
		if f != null:
			for b in f.buildings:
				if b.def_id == "refinery" and not b.dead:
					var bp := Vector2(b.global_position.x, b.global_position.z)
					if bp.distance_to(cpos) < float(b.def.get("gather_radius", 50.0)):
						served += 1
		var score := float(served) * 9000.0 - remaining
		if score < best_score:
			best_score = score
			best = c
	return best

func _find_spot_near(center: Vector3, spread: float, building_id: String) -> Vector3:
	var start := randf() * TAU
	for step in 5:
		var r := spread * float(step) / 4.0
		var count := 1 if step == 0 else 8
		for i in count:
			var a := start + TAU * float(i) / float(maxi(count, 1))
			var p := center + Vector3(cos(a) * r, 0.0, sin(a) * r)
			p = world.clamp_to_map(p)
			if _valid_spot(building_id, p):
				return p
	return Vector3.INF

func _valid_spot(building_id: String, p: Vector3) -> bool:
	var check := world.can_place(building_id, p, team)
	return bool(check["ok"])

func _facing_for(building_id: String, pos: Vector3) -> float:
	var b := base()
	if building_id == "defense_tower":
		var t := _threat_position()
		if t != Vector3.INF:
			return atan2(t.x - pos.x, t.z - pos.z)
	var enemy_base := world.base_pos(Game.other_team(team))
	return atan2(enemy_base.x - pos.x, enemy_base.z - pos.z)

# --- production ----------------------------------------------------------
func _produce_units() -> void:
	var f := Game.faction(team)
	if f == null:
		return
	if f.units.size() >= MAX_ARMY:
		return
	var want := _desired_unit()
	if want == "":
		return
	# Hold back ore for the next structure on the build list, but never at the
	# cost of having no army at all.
	var pending := _next_structure()
	var floor_ore := 150.0
	if pending != "" and f.units.size() >= MIN_ARMY:
		floor_ore = float(Defs.building_def(pending).get("cost", 0)) + reserve
	if f.ore < float(Defs.unit_def(want).get("cost", 0)) + floor_ore:
		return
	for b in f.buildings:
		if b.dead or not b.active or b.queue.size() >= 2:
			continue
		if b.enqueue(want):
			b.rally_point = staging_point()
			b.rally_set = true
			b.rally_point.y = world.terrain.height_at(b.rally_point.x, b.rally_point.z)
			return

func _desired_unit() -> String:
	var factories := _count("war_factory")
	var has_anti_vehicle := _unit_count("rocketeer") + _unit_count("missile_tank")
	var wants_tank := factories > 0
	if wants_tank and _unit_count("tank") < 5 + int(difficulty * 2.0):
		return "tank"
	if _unit_count("rifleman") < 6 + int(difficulty * 2.0):
		return "rifleman"
	if has_anti_vehicle < 2 and factories > 0 and _unit_count("tank") >= 3:
		return "rocketeer"
	if factories > 0 and _unit_count("missile_tank") < maxi(1, int(difficulty)):
		return "missile_tank"
	if factories > 0 and _unit_count("scout") < 2:
		return "scout"
	return ""

# --- army ----------------------------------------------------------------
func _manage_army() -> void:
	var f := Game.faction(team)
	if f == null:
		return
	var threat := _threat_position()
	if threat != Vector3.INF and _attacking:
		# Pull the wave home if the base is in danger.
		_recall(threat)
		_attacking = false
		_attack_group.clear()
		_wave_cooldown = 18.0
		return

	if not _attacking:
		_next_wave_in -= 0.5
		if _next_wave_in <= 0.0 and f.units.size() >= _wave_size():
			_launch_wave()
		return

	# End the wave when it is spent or has stalled far from home.
	var alive := 0
	var engaged := 0
	for u in _attack_group:
		if not is_instance_valid(u) or u.dead:
			continue
		alive += 1
		if is_instance_valid(u.target) and not u.target.dead:
			engaged += 1
	if alive == 0:
		_attacking = false
		_attack_group.clear()
		_next_wave_in = 45.0
	elif alive <= 1 and _wave_cooldown > 25.0:
		_recall(base())
		_attacking = false
		_attack_group.clear()
		_next_wave_in = 40.0
	elif engaged == 0 and _wave_cooldown > 70.0:
		_recall(base())
		_attacking = false
		_attack_group.clear()
		_next_wave_in = 40.0

func _wave_size() -> int:
	return 5 + _wave_number

func _launch_wave() -> void:
	var f := Game.faction(team)
	if f == null or f.units.is_empty():
		return
	_attack_group = f.units.duplicate()
	_wave_number += 1
	_attacking = true
	_wave_cooldown = 0.0
	var target := world.nearest_enemy_structure(
		world.base_pos(Game.other_team(team)), Game.other_team(team))
	var dest: Vector3 = target.global_position if target != null \
		else world.base_pos(Game.other_team(team))
	_order_group(_attack_group, dest, true)
	ai_event.emit("Enemy is attacking (wave %d, %d units)" % [_wave_number, _attack_group.size()])
	_next_wave_in = 120.0

func _recall(where: Vector3) -> void:
	_order_group(_attack_group, where, true)

func _order_group(group: Array, dest: Vector3, attacking: bool) -> void:
	var usable: Array[Unit] = []
	for u in group:
		# group is a snapshot of the army, so members can already be freed here.
		if not is_instance_valid(u) or u.dead:
			continue
		if u is Unit:
			usable.append(u as Unit)
	if usable.is_empty():
		return
	var spacing := 3.0
	for u in usable:
		spacing = maxf(spacing, u.radius() * 2.2 + 1.2)
	var dir := staging_point() - dest
	if dir.length_squared() < 0.01:
		dir = Vector3(0, 0, 1)
	dir = dir.normalized()
	var right := Vector3(-dir.z, 0, dir.x)
	var cols := maxi(1, int(ceil(sqrt(float(usable.size())))))
	for i in usable.size():
		var c := i % cols
		var r := i / cols
		var offset := right * (float(c) - (float(cols) - 1.0) * 0.5) * spacing \
			+ dir * float(r) * spacing * 0.9
		var p := world.clamp_to_map(dest + offset)
		p.y = world.terrain.height_at(p.x, p.z)
		if attacking:
			usable[i].order_attack_move(p)
		else:
			usable[i].order_move(p)

func _garrison() -> void:
	var f := Game.faction(team)
	if f == null:
		return
	var threat := _threat_position()
	if threat == Vector3.INF:
		return
	var responders: Array[Unit] = []
	for u in f.units:
		if u.dead or u in _attack_group:
			continue
		if u.global_position.distance_to(base()) < 140.0:
			responders.append(u)
	if responders.is_empty():
		return
	responders.sort_custom(func(a: Unit, b: Unit) -> bool:
		return a.global_position.distance_to(threat) \
			< b.global_position.distance_to(threat))
	var pick: Array = responders.slice(0, mini(6, responders.size()))
	_order_group(pick, threat, true)