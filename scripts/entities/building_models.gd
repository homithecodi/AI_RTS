class_name BuildingModels
extends RefCounted

const COL_WALL := Color(0.56, 0.56, 0.58)
const COL_TRIM := Color(0.34, 0.36, 0.40)
const COL_DARK := Color(0.18, 0.19, 0.21)
const COL_GLASS := Color(0.30, 0.52, 0.66)

static func build(building_id: String, team: int) -> Dictionary:
	var paint := MeshKit.team_tint(team, COL_WALL)
	var paint_m := MeshKit.mat(paint, 0.75, 0.1)
	var trim_m := MeshKit.mat(COL_TRIM, 0.6, 0.5)
	var dark_m := MeshKit.mat(COL_DARK, 0.85, 0.1)
	var glass_m := MeshKit.mat(COL_GLASS, 0.15, 0.6)
	var team_glow := MeshKit.mat(Defs.team_color(team), 0.4, 0.1,
		Defs.team_color(team), 2.6)
	var metal := MeshKit.mat(Color(0.5, 0.52, 0.55), 0.35, 0.8)

	var root := Node3D.new()
	root.name = "Model"
	match building_id:
		"power_plant": return _power_plant(root, paint_m, trim_m, dark_m, team_glow, metal)
		"refinery": return _refinery(root, paint_m, trim_m, dark_m, team_glow, metal)
		"barracks": return _barracks(root, paint_m, trim_m, dark_m, glass_m, team_glow, metal)
		"war_factory": return _war_factory(root, paint_m, trim_m, dark_m, glass_m, team_glow, metal)
		"defense_tower": return _defense_tower(root, paint_m, trim_m, dark_m, team_glow, metal)
	return {"root": root, "turret": null, "muzzle": null, "beam": null}

static func _foundation(root: Node3D, sx: float, sz: float, trim) -> void:
	MeshKit.box(root, Vector3(sx + 1.4, 0.35, sz + 1.4), Vector3(0, 0.17, 0), trim)

static func _power_plant(root: Node3D, paint, trim, dark, glow, metal) -> Dictionary:
	_foundation(root, 8.0, 8.0, trim)
	MeshKit.box(root, Vector3(6.4, 2.4, 6.4), Vector3(0, 1.55, 0), paint)
	MeshKit.box(root, Vector3(6.8, 0.28, 6.8), Vector3(0, 2.86, 0), dark)
	for sx in [-1.0, 1.0]:
		MeshKit.cyl(root, 1.55, 3.6, Vector3(sx * 1.9, 4.5, 0), metal)
		MeshKit.cyl(root, 1.75, 0.35, Vector3(sx * 1.9, 6.28, 0), trim)
		MeshKit.cyl(root, 1.30, 0.28, Vector3(sx * 1.9, 6.5, 0), glow)
	MeshKit.box(root, Vector3(1.5, 2.9, 0.9), Vector3(0, 1.9, -3.0), dark)
	MeshKit.box(root, Vector3(4.4, 0.14, 0.14), Vector3(0, 3.05, 3.1), glow)
	MeshKit.box(root, Vector3(4.4, 0.14, 0.14), Vector3(0, 3.05, -3.1), glow)
	return {"root": root, "turret": null, "muzzle": null, "beam": null}

static func _refinery(root: Node3D, paint, trim, dark, glow, metal) -> Dictionary:
	_foundation(root, 10.0, 10.0, trim)
	MeshKit.box(root, Vector3(8.2, 1.0, 8.2), Vector3(0, 0.85, 0), paint)
	MeshKit.cyl(root, 2.5, 4.6, Vector3(0, 3.6, 0), paint)
	MeshKit.cyl(root, 2.7, 0.4, Vector3(0, 6.0, 0), trim)
	MeshKit.cyl(root, 2.1, 0.3, Vector3(0, 6.3, 0), glow)
	MeshKit.box(root, Vector3(0.5, 0.5, 0.5), Vector3(0, 6.6, 0), dark)
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI * 0.25
		var d := Vector3(cos(a), 0, sin(a))
		MeshKit.box(root, Vector3(1.1, 0.9, 4.6),
			d * 5.2 + Vector3(0, 1.05, 0), metal, Vector3(0, -a, 0))
		MeshKit.box(root, Vector3(0.5, 1.4, 0.5),
			d * 7.0 + Vector3(0, 1.5, 0), dark)
		MeshKit.box(root, Vector3(0.6, 0.6, 0.6),
			d * 7.0 + Vector3(0, 2.35, 0), glow)
	MeshKit.box(root, Vector3(8.0, 0.14, 0.14), Vector3(0, 1.45, 4.15), glow)
	return {"root": root, "turret": null, "muzzle": null, "beam": null}

static func _barracks(root: Node3D, paint, trim, dark, glass, glow, metal) -> Dictionary:
	_foundation(root, 8.0, 7.0, trim)
	MeshKit.box(root, Vector3(7.2, 3.2, 6.2), Vector3(0, 1.95, 0), paint)
	MeshKit.box(root, Vector3(7.8, 0.36, 6.8), Vector3(0, 3.72, 0), dark)
	MeshKit.box(root, Vector3(1.5, 0.9, 0.16), Vector3(-2.1, 2.3, 3.13), glass)
	MeshKit.box(root, Vector3(1.5, 0.9, 0.16), Vector3(2.1, 2.3, 3.13), glass)
	MeshKit.box(root, Vector3(2.0, 2.3, 0.18), Vector3(0, 1.5, 3.13), dark)
	MeshKit.box(root, Vector3(7.2, 0.18, 0.18), Vector3(0, 3.5, 3.2), glow)
	MeshKit.box(root, Vector3(2.4, 0.12, 2.4), Vector3(2.2, 3.98, -1.2), metal)
	MeshKit.cyl(root, 0.06, 1.6, Vector3(3.2, 4.7, -1.2), metal)
	MeshKit.box(root, Vector3(1.6, 0.06, 0.06), Vector3(2.8, 5.4, -1.2), glow)
	return {"root": root, "turret": null, "muzzle": null, "beam": null}

static func _war_factory(root: Node3D, paint, trim, dark, glass, glow, metal) -> Dictionary:
	_foundation(root, 12.0, 9.0, trim)
	MeshKit.box(root, Vector3(10.6, 4.0, 8.2), Vector3(0, 2.35, 0), paint)
	MeshKit.box(root, Vector3(11.2, 0.4, 8.8), Vector3(0, 4.55, 0), dark)
	# roll-up door
	MeshKit.box(root, Vector3(4.4, 3.0, 0.24), Vector3(0, 1.85, 4.14), dark)
	for i in 6:
		MeshKit.box(root, Vector3(4.2, 0.16, 0.10), Vector3(0, 0.7 + i * 0.46, 4.26), trim)
	MeshKit.box(root, Vector3(1.3, 0.8, 0.16), Vector3(-3.6, 3.1, 4.14), glass)
	MeshKit.box(root, Vector3(1.3, 0.8, 0.16), Vector3(3.6, 3.1, 4.14), glass)
	MeshKit.box(root, Vector3(9.6, 0.16, 0.16), Vector3(0, 4.25, 4.25), glow)
	# rooftop crane
	MeshKit.cyl(root, 0.22, 3.4, Vector3(-4.3, 6.1, -1.6), metal)
	MeshKit.box(root, Vector3(0.4, 0.4, 5.6), Vector3(-4.3, 7.7, -1.6), trim)
	MeshKit.box(root, Vector3(0.16, 0.16, 5.2), Vector3(-4.3, 7.4, -1.6), glow)
	MeshKit.box(root, Vector3(1.6, 0.5, 1.2), Vector3(3.4, 5.1, -1.8), metal)
	MeshKit.cyl(root, 0.7, 2.4, Vector3(4.6, 5.6, 2.6), trim)
	MeshKit.cyl(root, 0.55, 0.3, Vector3(4.6, 6.9, 2.6), glow)
	return {"root": root, "turret": null, "muzzle": null, "beam": null}

static func _defense_tower(root: Node3D, paint, trim, dark, glow, metal) -> Dictionary:
	MeshKit.cyl(root, 2.1, 1.0, Vector3(0, 0.5, 0), trim)
	MeshKit.cyl(root, 1.5, 0.25, Vector3(0, 1.05, 0), glow)
	MeshKit.box(root, Vector3(1.3, 4.2, 1.3), Vector3(0, 3.1, 0), paint)
	MeshKit.box(root, Vector3(1.6, 0.3, 1.6), Vector3(0, 5.1, 0), dark)
	var turret := MeshKit.empty("Turret", Vector3(0, 5.5, 0), root)
	MeshKit.box(turret, Vector3(1.7, 0.7, 1.9), Vector3(0, 0.2, 0), paint)
	MeshKit.box(turret, Vector3(1.8, 0.16, 1.4), Vector3(0, 0.6, 0.1), dark)
	for sx in [-1.0, 1.0]:
		MeshKit.cyl(turret, 0.10, 1.60, Vector3(sx * 0.30, 0.25, -1.20), metal,
			Vector3(-PI * 0.5, 0, 0))
	var muzzle := MeshKit.empty("Muzzle", Vector3(0.0, 0.25, -1.95), turret)
	return {"root": root, "turret": turret, "muzzle": muzzle, "beam": null}