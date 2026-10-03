class_name MeshKit
extends RefCounted
# Small procedural mesh factory. Everything in this project is built from code,
# so there are no external model files to keep in sync.

static var _mat_cache: Dictionary = {}
static var _mesh_cache: Dictionary = {}

static func mat(color: Color, rough: float = 0.85, metal: float = 0.0,
		emis: Color = Color(0, 0, 0), emis_energy: float = 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f|%s|%.2f" % [color.to_html(), rough, metal, emis.to_html(), emis_energy]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := _make_mat(color, rough, metal, emis, emis_energy)
	_mat_cache[key] = m
	return m

# Never-cached material for one-off effects that get mutated while fading.
static func mat_unique(color: Color, rough: float = 0.85, metal: float = 0.0,
		emis: Color = Color(0, 0, 0), emis_energy: float = 0.0) -> StandardMaterial3D:
	return _make_mat(color, rough, metal, emis, emis_energy)

static func _make_mat(color: Color, rough: float, metal: float, emis: Color,
		emis_energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if emis_energy > 0.0:
		m.emission_enabled = true
		m.emission = emis
		m.emission_energy_multiplier = emis_energy
	return m

static func box_mesh(size: Vector3) -> BoxMesh:
	var key := "b%s" % size
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var m := BoxMesh.new()
	m.size = size
	_mesh_cache[key] = m
	return m

static func cyl_mesh(radius: float, height: float, sides: int = 12) -> CylinderMesh:
	var key := "c%.2f_%.2f_%d" % [radius, height, sides]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = sides
	m.rings = 1
	_mesh_cache[key] = m
	return m

static func sphere_mesh(radius: float) -> SphereMesh:
	var key := "s%.2f" % radius
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 12
	m.rings = 6
	_mesh_cache[key] = m
	return m

static func part(parent: Node3D, mesh: Mesh, pos: Vector3, material: Material,
		rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi

static func box(parent: Node3D, size: Vector3, pos: Vector3, material: Material,
		rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	return part(parent, box_mesh(size), pos, material, rot)

static func cyl(parent: Node3D, radius: float, height: float, pos: Vector3,
		material: Material, rot: Vector3 = Vector3.ZERO, sides: int = 12) -> MeshInstance3D:
	return part(parent, cyl_mesh(radius, height, sides), pos, material, rot)

static func sphere(parent: Node3D, radius: float, pos: Vector3,
		material: Material) -> MeshInstance3D:
	return part(parent, sphere_mesh(radius), pos, material)

static func wheel(parent: Node3D, radius: float, width: float, pos: Vector3,
		material: Material) -> MeshInstance3D:
	return cyl(parent, radius, width, pos, material, Vector3(0, 0, PI * 0.5), 14)

static func empty(name_hint: String, pos: Vector3, parent: Node3D) -> Node3D:
	var n := Node3D.new()
	n.name = name_hint
	n.position = pos
	parent.add_child(n)
	return n

# Trims a material so every team gets a distinct silhouette accent colour.
static func team_tint(team: int, base: Color) -> Color:
	var c := Defs.team_color(team)
	return Color(base.r * 0.35 + c.r * 0.65, base.g * 0.35 + c.g * 0.65,
		base.b * 0.35 + c.b * 0.65)