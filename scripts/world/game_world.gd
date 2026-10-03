class_name GameWorld
extends Node3D
# Owns the battlefield: terrain, ore fields, every unit and structure, and the
# spatial queries that combat and steering rely on.

const CELL := 14.0

var terrain: Terrain
var effects: Node3D
var ore_root: Node3D
var unit_root: Node3D
var building_root: Node3D

var units: Array[Unit] = []
var buildings: Array[Building] = []
var ore_nodes: Array[OreNode] = []
var ore_clusters: Array[Dictionary] = []
var bases: Dictionary = {}
var map_seed: int = 20260101

var _unit_grid: Dictionary = {}
var _building_grid: Dictionary = {}
var _started: bool = false

const CLUSTER_SPECS := [
	{"pos": Vector2(-92, -96), "r": 17.0, "n": 5},
	{"pos": Vector2(-132, -76), "r": 15.0, "n": 4},
	{"pos": Vector2(92, 96), "r": 17.0, "n": 5},
	{"pos": Vector2(132, 76), "r": 15.0, "n": 4},
	{"pos": Vector2(-6, 8), "r": 20.0, "n": 6},
	{"pos": Vector2(-52, 52), "r": 16.0, "n": 4},
	{"pos": Vector2(52, -52), "r": 16.0, "n": 4},
	{"pos": Vector2(-160, 40), "r": 16.0, "n": 4},
	{"pos": Vector2(160, -40), "r": 16.0, "n": 4},
]

func map_half() -> float:
	return Terrain.MAP_SIZE * 0.5

func base_pos(team: int) -> Vector3:
	var p: Vector2 = bases.get(team, Vector2(-118, -112))
	return Vector3(p.x, 0.0, p.y)

# --- setup ---------------------------------------------------------------
func setup(seed_value: int) -> void:
	map_seed = seed_value
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	bases[Defs.TEAM_PLAYER] = Vector2(-118, -112)
	bases[Defs.TEAM_ENEMY] = Vector2(118, 112)

	var zones: Array[Dictionary] = []
	for spec in CLUSTER_SPECS:
		zones.append({
			"pos": spec["pos"], "radius": float(spec["r"]) + 8.0,
			"falloff": 20.0, "height": _raw_height(spec["pos"], seed_value),
		})
	for team in bases:
		var bp: Vector2 = bases[team]
		zones.append({"pos": bp, "radius": 30.0, "falloff": 26.0,
			"height": _raw_height(bp, seed_value)})

	terrain = Terrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.generate(seed_value, zones)

	ore_root = Node3D.new()
	ore_root.name = "OreFields"
	add_child(ore_root)
	unit_root = Node3D.new()
	unit_root.name = "Units"
	add_child(unit_root)
	building_root = Node3D.new()
	building_root.name = "Buildings"
	add_child(building_root)
	effects = Node3D.new()
	effects.name = "Effects"
	add_child(effects)

	_spawn_ore(rng)
	terrain.build_minmap_texture(256)
	Game.world = self

func _raw_height(p: Vector2, seed_value: int) -> float:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.0055
	n.fractal_octaves = 4
	n.fractal_lacunarity = 2.1
	n.fractal_gain = 0.48
	var roll := FastNoiseLite.new()
	roll.seed = seed_value + 91
	roll.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	roll.frequency = 0.0016
	return n.get_noise_2d(p.x, p.y) * 6.5 + roll.get_noise_2d(p.x, p.y) * 9.0

func _spawn_ore(rng: RandomNumberGenerator) -> void:
	for spec in CLUSTER_SPECS:
		var center: Vector2 = spec["pos"]
		ore_clusters.append({"pos": center, "radius": float(spec["r"])})
		var count := int(spec["n"])
		for i in count:
			var a := rng.randf() * TAU
			var d := sqrt(rng.randf()) * float(spec["r"])
			var x := center.x + cos(a) * d
			var z := center.y + sin(a) * d
			if not terrain.in_bounds(x, z):
				continue
			var p := Vector3(x, terrain.height_at(x, z), z)
			var node := OreNode.create(p)
			ore_root.add_child(node)
			ore_nodes.append(node)

func spawn_starting_base(team: int) -> void:
	var center := base_pos(team)
	var towards_center := Vector3(-center.x, 0.0, -center.z).normalized()
	var layout := [
		{"id": "refinery", "off": Vector3(0, 0, 21)},
		{"id": "barracks", "off": Vector3(-23, 0, 2)},
		{"id": "power_plant", "off": Vector3(-23, 0, -21)},
		{"id": "power_plant", "off": Vector3(2, 0, -23)},
	]
	var right := towards_center.cross(Vector3.UP).normalized()
	for entry in layout:
		var off: Vector3 = entry["off"]
		var pos := center + towards_center * off.z + right * off.x
		pos.y = terrain.height_at(pos.x, pos.z)
		var heading := atan2(towards_center.x, towards_center.z)
		spawn_building(String(entry["id"]), team, pos, heading, true)

# --- spawning ------------------------------------------------------------
func spawn_unit(unit_id: String, team: int, pos: Vector3,
		heading: float = 0.0) -> Unit:
	if units.size() >= 220:
		return null
	var u := Unit.spawn(unit_id, team, pos, self, heading)
	unit_root.add_child(u)
	units.append(u)
	_game_register_unit(u)
	refresh_unit_grid(u)
	return u

func spawn_building(building_id: String, team: int, pos: Vector3,
		heading: float = 0.0, instant: bool = false) -> Building:
	var b := Building.new()
	building_root.add_child(b)
	b.initialize(building_id, team, pos, self, heading, instant)
	buildings.append(b)
	_add_building_to_grid(b)
	return b

func _game_register_unit(u: Unit) -> void:
	Game.register_unit(u)
	if u.team == Defs.TEAM_PLAYER:
		var f := Game.faction(Defs.TEAM_PLAYER)
		if f != null and f.units.size() == 1:
			Game.selection_changed.emit()

# --- death handling ------------------------------------------------------
func on_entity_died(entity: Entity, _killer: Entity) -> void:
	if entity is Unit:
		var u := entity as Unit
		units.erase(u)
		_forget_unit(u)
		Game.unregister_unit(u)
		var f := Game.faction(u.team)
		if f != null:
			f.units_lost += 1
			if f.units.size() == 0:
				Game.selection_changed.emit()
	else:
		var b := entity as Building
		buildings.erase(b)
		_forget_building(b)
		Game.unregister_building(b)
	_check_defeat()

func _check_defeat() -> void:
	if not _started:
		return
	for team in [Defs.TEAM_PLAYER, Defs.TEAM_ENEMY]:
		var f := Game.faction(team)
		if f == null or f.defeated:
			continue
		if f.units.is_empty() and f.buildings.is_empty():
			f.defeated = true
			f.defeated_time = Game.elapsed
			Game.notify_resources(team)
			Game.check_victory()

func start() -> void:
	_started = true
	Game.started = true

# --- spatial queries -----------------------------------------------------
func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL)), int(floor(p.y / CELL)))

func refresh_unit_grid(u: Unit) -> void:
	if u.dead or not is_instance_valid(u):
		return
	var cell := _cell_of(Vector2(u.global_position.x, u.global_position.z))
	if cell == u._grid_cell:
		return
	if _unit_grid.has(u._grid_cell):
		var bucket: Array = _unit_grid[u._grid_cell]
		bucket.erase(u)
		if bucket.is_empty():
			_unit_grid.erase(u._grid_cell)
	if not _unit_grid.has(cell):
		_unit_grid[cell] = []
	var target: Array = _unit_grid[cell]
	target.append(u)
	u._grid_cell = cell

func _add_building_to_grid(b: Building) -> void:
	b._grid_cell = _cell_of(Vector2(b.global_position.x, b.global_position.z))
	for key in _building_cells(b):
		if not _building_grid.has(key):
			_building_grid[key] = []
		var arr: Array = _building_grid[key]
		if not arr.has(b):
			arr.append(b)

func _building_cells(b: Building) -> Array:
	var cell := b._grid_cell
	var span := int(ceil(float(b.def.get("footprint", 6.0)) * 0.75 / CELL)) + 1
	var out: Array = []
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			out.append(Vector2i(cell.x + dx, cell.y + dz))
	return out

# Entities queue_free() the moment they die, so the grids have to drop them
# before that happens: a freed instance left in a bucket makes every later
# spatial query dereference a dangling reference.
func _forget_unit(u: Unit) -> void:
	if _unit_grid.has(u._grid_cell):
		var bucket: Array = _unit_grid[u._grid_cell]
		bucket.erase(u)
		if bucket.is_empty():
			_unit_grid.erase(u._grid_cell)
	u._grid_cell = Vector2i(99999, 99999)

func _forget_building(b: Building) -> void:
	for key in _building_cells(b):
		if not _building_grid.has(key):
			continue
		var arr: Array = _building_grid[key]
		arr.erase(b)
		if arr.is_empty():
			_building_grid.erase(key)
	b._grid_cell = Vector2i(99999, 99999)

func query_units(pos: Vector3, radius: float) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	var base := _cell_of(Vector2(pos.x, pos.z))
	var span := int(ceil(radius / CELL))
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			var key := Vector2i(base.x + dx, base.y + dz)
			if not _unit_grid.has(key):
				continue
			var bucket: Array = _unit_grid[key]
			for u in bucket:
				if not is_instance_valid(u) or u.dead or seen.has(u):
					continue
				if u.global_position.distance_squared_to(pos) <= radius * radius:
					seen[u] = true
					out.append(u)
	return out

func query_buildings(pos: Vector3, radius: float) -> Array:
	var out: Array = []
	# Buildings are registered in every cell they can overlap, so a multi-cell
	# query would otherwise report the same building several times.
	var seen: Dictionary = {}
	var base := _cell_of(Vector2(pos.x, pos.z))
	var span := int(ceil(radius / CELL))
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			var key := Vector2i(base.x + dx, base.y + dz)
			if not _building_grid.has(key):
				continue
			var arr: Array = _building_grid[key]
			for b in arr:
				if not is_instance_valid(b) or b.dead or seen.has(b):
					continue
				if b.global_position.distance_squared_to(pos) <= radius * radius:
					seen[b] = true
					out.append(b)
	return out

func ore_nodes_in_radius(pos: Vector3, radius: float) -> Array[OreNode]:
	var out: Array[OreNode] = []
	for n in ore_nodes:
		if not is_instance_valid(n) or not n.active:
			continue
		if n.global_position.distance_squared_to(pos) <= radius * radius:
			out.append(n)
	return out

# Prefers live units over structures, closest first.
func find_enemy_in_radius(pos: Vector3, radius: float,
		for_entity: Entity) -> Entity:
	var best: Entity = null
	var best_score := -1.0e9
	for u: Unit in query_units(pos, radius):
		if u.team == for_entity.team or u.dead:
			continue
		var score := 200.0 - pos.distance_to(u.global_position)
		if score > best_score:
			best_score = score
			best = u
	if best != null:
		return best
	for b: Building in query_buildings(pos, radius):
		if b.team == for_entity.team or b.dead:
			continue
		var score := 100.0 - pos.distance_to(b.global_position)
		if score > best_score:
			best_score = score
			best = b
	return best

func nearest_enemy_structure(pos: Vector3, team: int) -> Building:
	var best: Building = null
	var best_d := 1.0e20
	for b in buildings:
		if b.team == team or b.dead:
			continue
		var d := b.global_position.distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = b
	return best

func friendly_buildings_near(pos: Vector3, team: int, radius: float) -> Array:
	var out: Array = []
	for b in buildings:
		if b.team == team and not b.dead and b.global_position.distance_to(pos) <= radius:
			out.append(b)
	return out

func splash_damage(center: Vector3, radius: float, damage: float, team: int,
		source: Entity) -> void:
	for u: Unit in query_units(center, radius):
		if u.team == team:
			continue
		var falloff := 1.0 - (u.global_position.distance_to(center) / radius) * 0.55
		u.take_damage(damage * clampf(falloff, 0.25, 1.0), team, source)
	for b: Building in query_buildings(center, radius + 4.0):
		if b.team == team:
			continue
		var d: float = b.global_position.distance_to(center)
		if d > radius + float(b.def.get("footprint", 6.0)) * 0.5:
			continue
		var f: float = 1.0 - (d / (radius + 3.0)) * 0.5
		b.take_damage(damage * clampf(f, 0.25, 1.0), team, source)

# --- placement validation ------------------------------------------------
func can_place(building_id: String, pos: Vector3, team: int) -> Dictionary:
	var d := Defs.building_def(building_id)
	if d.is_empty():
		return {"ok": false, "reason": "Unknown structure"}
	var half_x := float(d.get("size_x", 8.0)) * 0.5
	var half_z := float(d.get("size_z", 8.0)) * 0.5
	var margin := 1.5
	if not terrain.in_bounds(pos.x, pos.z):
		return {"ok": false, "reason": "Outside the battlefield"}
	for corner in [
			Vector2(pos.x - half_x - margin, pos.z - half_z - margin),
			Vector2(pos.x + half_x + margin, pos.z + half_z + margin),
			Vector2(pos.x - half_x - margin, pos.z + half_z + margin),
			Vector2(pos.x + half_x + margin, pos.z - half_z - margin),
			Vector2(pos.x, pos.z)]:
		if not terrain.in_bounds(corner.x, corner.y):
			return {"ok": false, "reason": "Outside the battlefield"}
		if terrain.slope_at(corner.x, corner.y) > 0.17:
			return {"ok": false, "reason": "Ground is too steep"}
	var footprint := float(d.get("footprint", 8.0)) * 0.5
	for b in buildings:
		if b.dead:
			continue
		var other: float = maxf(float(b.def.get("footprint", 8.0)), footprint) + 1.2
		var bd: float = Vector2(b.global_position.x, b.global_position.z).distance_to(
			Vector2(pos.x, pos.z))
		if bd < other:
			return {"ok": false, "reason": "Too close to another structure"}
	var allow_ore := building_id == "refinery" or float(d.get("gather_radius", 0.0)) > 0.0
	for n in ore_nodes:
		if not is_instance_valid(n) or not n.active:
			continue
		if Vector2(n.global_position.x, n.global_position.z).distance_to(
				Vector2(pos.x, pos.z)) < n.radius + footprint * 0.55:
			if not allow_ore:
				return {"ok": false, "reason": "Blocked by an ore field"}
	return {"ok": true, "reason": ""}

func clamp_to_map(p: Vector3) -> Vector3:
	var h := map_half() - 6.0
	return Vector3(clampf(p.x, -h, h), 0.0, clampf(p.z, -h, h))

func total_ore() -> float:
	var total := 0.0
	for n in ore_nodes:
		if is_instance_valid(n):
			total += n.amount
	return total
