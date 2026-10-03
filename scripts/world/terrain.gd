class_name Terrain
extends MeshInstance3D

const MAP_SIZE := 420.0
const GRID := 168
const STEP := MAP_SIZE / float(GRID)

var _heights := PackedFloat32Array()
var _half := MAP_SIZE * 0.5
var _patch := 0.0
var _flatten: Array[Dictionary] = []

var minimap_texture: ImageTexture = null

func _init() -> void:
	_heights.resize((GRID + 1) * (GRID + 1))

func generate(map_seed: int, flatten_zones: Array[Dictionary]) -> void:
	_flatten = flatten_zones.duplicate()

	var n := FastNoiseLite.new()
	n.seed = map_seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.0055
	n.fractal_octaves = 4
	n.fractal_lacunarity = 2.1
	n.fractal_gain = 0.48

	var roll := FastNoiseLite.new()
	roll.seed = map_seed + 91
	roll.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	roll.frequency = 0.0016

	_patch = float(map_seed % 4096) * 1.0 + 0.5

	var dn := FastNoiseLite.new()
	dn.seed = map_seed + 733
	dn.noise_type = FastNoiseLite.TYPE_SIMPLEX
	dn.frequency = 0.045

	for gz in GRID + 1:
		for gx in GRID + 1:
			var wx := -_half + gx * STEP
			var wz := -_half + gz * STEP
			var h := n.get_noise_2d(wx, wz) * 6.5
			h += roll.get_noise_2d(wx, wz) * 9.0
			_heights[gz * (GRID + 1) + gx] = h

	for zone in _flatten:
		_apply_flatten(zone)

	_build_mesh()

func _apply_flatten(zone: Dictionary) -> void:
	var center: Vector2 = zone["pos"]
	var radius: float = zone["radius"]
	var target: float = zone["height"]
	var falloff: float = zone.get("falloff", 18.0)
	var inner := radius
	var outer := radius + falloff

	var g0x := clampi(int((center.x - outer + _half) / STEP), 0, GRID)
	var g1x := clampi(int((center.x + outer + _half) / STEP), 0, GRID)
	var g0z := clampi(int((center.y - outer + _half) / STEP), 0, GRID)
	var g1z := clampi(int((center.y + outer + _half) / STEP), 0, GRID)

	for gz in range(g0z, g1z + 1):
		for gx in range(g0x, g1x + 1):
			var wx := -_half + gx * STEP
			var wz := -_half + gz * STEP
			var d := Vector2(wx, wz).distance_to(center)
			var t := 1.0
			if d > inner:
				t = 1.0 - smoothstep(inner, outer, d)
			var idx := gz * (GRID + 1) + gx
			_heights[idx] = lerpf(_heights[idx], target, t)

func height_at(x: float, z: float) -> float:
	var fx := clampf((x + _half) / STEP, 0.0, float(GRID))
	var fz := clampf((z + _half) / STEP, 0.0, float(GRID))
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	ix = clampi(ix, 0, GRID - 1)
	iz = clampi(iz, 0, GRID - 1)
	var row := GRID + 1
	var h00 := _heights[iz * row + ix]
	var h10 := _heights[iz * row + ix + 1]
	var h01 := _heights[(iz + 1) * row + ix]
	var h11 := _heights[(iz + 1) * row + ix + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)

func normal_at(x: float, z: float) -> Vector3:
	var d := STEP
	var hl := height_at(x - d, z)
	var hr := height_at(x + d, z)
	var hd := height_at(x, z - d)
	var hu := height_at(x, z + d)
	return Vector3(hl - hr, 2.0 * d, hd - hu).normalized()

func slope_at(x: float, z: float) -> float:
	return 1.0 - normal_at(x, z).y

func in_bounds(x: float, z: float) -> bool:
	return absf(x) <= _half - 6.0 and absf(z) <= _half - 6.0

func build_color(pos: Vector3, slope: float, patch: float, detail: float) -> Color:
	var grass_a := Color(0.255, 0.404, 0.196)
	var grass_b := Color(0.352, 0.451, 0.223)
	var dirt := Color(0.451, 0.384, 0.262)
	var rock := Color(0.42, 0.42, 0.44)
	var sand := Color(0.62, 0.56, 0.38)

	var c := grass_a.lerp(grass_b, clampf(patch * 0.5 + 0.5, 0.0, 1.0))
	c = c.lerp(dirt, clampf(detail * 0.5 + 0.5, 0.0, 1.0) * 0.55)
	if pos.y < -4.0:
		c = c.lerp(sand, clampf((-4.0 - pos.y) / 6.0, 0.0, 1.0) * 0.8)
	if slope > 0.22:
		c = c.lerp(rock, clampf((slope - 0.22) / 0.35, 0.0, 1.0))
	c = c.lerp(rock * 0.75, clampf((pos.y - 8.0) / 8.0, 0.0, 1.0) * 0.6)
	return c

func _build_mesh() -> void:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx_arr := PackedInt32Array()
	var row := GRID + 1

	var pn := FastNoiseLite.new()
	pn.seed = int(_patch)
	pn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	pn.frequency = 0.012

	var dn := FastNoiseLite.new()
	dn.seed = int(_patch) + 55
	dn.noise_type = FastNoiseLite.TYPE_SIMPLEX
	dn.frequency = 0.05

	verts.resize(row * row)
	norms.resize(row * row)
	cols.resize(row * row)
	uvs.resize(row * row)

	for gz in row:
		for gx in row:
			var i := gz * row + gx
			var x := -_half + gx * STEP
			var z := -_half + gz * STEP
			var h := _heights[i]
			var p := Vector3(x, h, z)
			verts[i] = p
			norms[i] = normal_at(x, z)
			uvs[i] = Vector2(float(gx) / float(GRID), float(gz) / float(GRID))
			cols[i] = build_color(p, 1.0 - norms[i].y, pn.get_noise_2d(x, z), dn.get_noise_2d(x, z))

	for gz in GRID:
		for gx in GRID:
			var a := gz * row + gx
			var b := a + 1
			var c := a + row
			var d := c + 1
			# A triangle is front-facing when its geometric normal points away from
			# the viewer, so an upward-facing quad has to be wound a-b-c, not a-c-b.
			idx_arr.append_array([a, b, c, b, d, c])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx_arr

	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	m.surface_set_material(0, terrain_material())
	mesh = m

func terrain_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat

# Ray march against the heightfield. Returns {point, normal} or an empty dict.
func raycast(origin: Vector3, dir: Vector3, max_dist: float = 1200.0) -> Dictionary:
	var t := 0.0
	var step := 3.0
	var prev_t := 0.0
	var p := origin
	if p.y <= height_at(p.x, p.z):
		return {"point": p, "normal": normal_at(p.x, p.z)}
	while t < max_dist:
		prev_t = t
		t += step
		p = origin + dir * t
		if absf(p.x) > _half + 60.0 or absf(p.z) > _half + 60.0:
			if t > 80.0:
				return {}
		var diff := p.y - height_at(p.x, p.z)
		if diff <= 0.0:
			var lo := prev_t
			var hi := t
			for _i in 14:
				var mid := (lo + hi) * 0.5
				var pm := origin + dir * mid
				if pm.y - height_at(pm.x, pm.z) > 0.0:
					lo = mid
				else:
					hi = mid
			var hit := origin + dir * hi
			return {"point": hit, "normal": normal_at(hit.x, hit.z)}
		step = minf(step * 1.12, 9.0)
	return {}

func build_minmap_texture(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var pn := FastNoiseLite.new()
	pn.seed = int(_patch)
	pn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	pn.frequency = 0.012
	var dn := FastNoiseLite.new()
	dn.seed = int(_patch) + 55
	dn.noise_type = FastNoiseLite.TYPE_SIMPLEX
	dn.frequency = 0.05
	var shade := 0.72
	for j in size:
		for i in size:
			var x := -_half + (float(i) + 0.5) / float(size) * MAP_SIZE
			# Row 0 is the top of the map, which is +z (north), matching
			# world_to_map above.
			var z := _half - (float(j) + 0.5) / float(size) * MAP_SIZE
			var h := height_at(x, z)
			var nrm := normal_at(x, z)
			var p := Vector3(x, h, z)
			var c := build_color(p, 1.0 - nrm.y, pn.get_noise_2d(x, z), dn.get_noise_2d(x, z))
			# simple hill shading
			var light := clampf(0.55 + nrm.dot(Vector3(0.4, 0.8, 0.3)) * shade, 0.25, 1.35)
			c = Color(clampf(c.r * light, 0, 1), clampf(c.g * light, 0, 1), clampf(c.b * light, 0, 1))
			img.set_pixel(i, j, c)
	minimap_texture = ImageTexture.create_from_image(img)
	return minimap_texture

# Minimap orientation: +x is east and +z is north, which is the compass the rest
# of the game describes itself in (the enemy base is +x,+z, i.e. north-east).
# So world_to_map has to put +z at the TOP of the map, not the bottom.
func world_to_map(x: float, z: float) -> Vector2:
	return Vector2(
		clampf((x + _half) / MAP_SIZE, 0.0, 1.0),
		clampf((_half - z) / MAP_SIZE, 0.0, 1.0)
	)

func map_to_world(u: float, v: float) -> Vector3:
	var x := u * MAP_SIZE - _half
	var z := _half - v * MAP_SIZE
	return Vector3(x, height_at(x, z), z)