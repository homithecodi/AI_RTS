class_name UnitModels
extends RefCounted

const COL_ARMOR := Color(0.29, 0.31, 0.34)
const COL_DARK := Color(0.12, 0.13, 0.15)
const COL_METAL := Color(0.55, 0.57, 0.60)
const COL_GLASS := Color(0.35, 0.55, 0.68)

static func build(unit_id: String, team: int) -> Dictionary:
	var paint := MeshKit.team_tint(team, COL_ARMOR)
	var paint_m := MeshKit.mat(paint, 0.7, 0.15)
	var dark_m := MeshKit.mat(COL_DARK, 0.9, 0.1)
	var metal_m := MeshKit.mat(COL_METAL, 0.4, 0.75)
	var glass_m := MeshKit.mat(COL_GLASS, 0.15, 0.6)
	var team_glow := MeshKit.mat(Defs.team_color(team), 0.4, 0.2,
		Defs.team_color(team), 2.2)

	var root := Node3D.new()
	root.name = "Model"
	match unit_id:
		"rifleman": return _rifleman(root, paint_m, dark_m, metal_m, team_glow)
		"rocketeer": return _rocketeer(root, paint_m, dark_m, metal_m, team_glow)
		"scout": return _scout(root, paint_m, dark_m, metal_m, glass_m)
		"tank": return _tank(root, paint_m, dark_m, metal_m, team_glow)
		"missile_tank": return _missile_tank(root, paint_m, dark_m, metal_m, team_glow)
	return {"root": root, "body": root, "turret": root, "muzzle": null, "wheels": []}

# Every model below is authored facing local +Z, matching the yaw convention used
# by Unit.facing: rotation.y = atan2(dir.x, dir.z).
static func _rifleman(root: Node3D, paint, dark, metal, glow) -> Dictionary:
	var body := MeshKit.empty("Body", Vector3.ZERO, root)
	MeshKit.box(body, Vector3(0.30, 0.92, 0.34), Vector3(-0.20, 0.46, 0.0), dark)
	MeshKit.box(body, Vector3(0.30, 0.92, 0.34), Vector3(0.20, 0.46, 0.0), dark)
	MeshKit.box(body, Vector3(0.26, 0.30, 0.42), Vector3(-0.20, 0.06, -0.06), dark)
	MeshKit.box(body, Vector3(0.26, 0.30, 0.42), Vector3(0.20, 0.06, -0.06), dark)
	MeshKit.box(body, Vector3(0.92, 1.00, 0.56), Vector3(0.0, 1.40, 0.0), paint)
	MeshKit.box(body, Vector3(0.98, 0.22, 0.60), Vector3(0.0, 1.72, 0.0), glow)
	MeshKit.box(body, Vector3(0.22, 0.72, 0.24), Vector3(-0.56, 1.42, -0.02), dark)
	MeshKit.box(body, Vector3(0.22, 0.72, 0.24), Vector3(0.56, 1.42, -0.10), dark)
	MeshKit.sphere(body, 0.27, Vector3(0.0, 2.06, 0.0), MeshKit.mat(Color(0.72, 0.58, 0.46)))
	MeshKit.sphere(body, 0.29, Vector3(0.0, 2.14, 0.0), paint)
	MeshKit.box(body, Vector3(0.11, 0.11, 1.30), Vector3(0.50, 1.34, 0.62), metal)
	MeshKit.box(body, Vector3(0.16, 0.26, 0.30), Vector3(0.50, 1.30, -0.02), dark)
	var muzzle := MeshKit.empty("Muzzle", Vector3(0.50, 1.34, 1.26), body)
	return {"root": root, "body": body, "turret": body, "muzzle": muzzle, "wheels": []}

static func _rocketeer(root: Node3D, paint, dark, metal, glow) -> Dictionary:
	var body := MeshKit.empty("Body", Vector3.ZERO, root)
	MeshKit.box(body, Vector3(0.30, 0.90, 0.34), Vector3(-0.20, 0.45, 0.0), dark)
	MeshKit.box(body, Vector3(0.30, 0.90, 0.34), Vector3(0.20, 0.45, 0.0), dark)
	MeshKit.box(body, Vector3(0.26, 0.28, 0.42), Vector3(-0.20, 0.05, -0.06), dark)
	MeshKit.box(body, Vector3(0.26, 0.28, 0.42), Vector3(0.20, 0.05, -0.06), dark)
	MeshKit.box(body, Vector3(0.88, 0.98, 0.54), Vector3(0.0, 1.38, 0.0), paint)
	MeshKit.box(body, Vector3(0.66, 0.72, 0.34), Vector3(0.0, 1.40, -0.44), dark)
	MeshKit.box(body, Vector3(0.94, 0.20, 0.58), Vector3(0.0, 1.70, 0.0), glow)
	MeshKit.sphere(body, 0.26, Vector3(0.0, 2.02, 0.0), MeshKit.mat(Color(0.72, 0.58, 0.46)))
	MeshKit.sphere(body, 0.28, Vector3(0.0, 2.10, 0.0), paint)
	# shoulder launcher tube, held above the shoulder
	MeshKit.cyl(body, 0.16, 1.30, Vector3(0.34, 1.62, 0.62), metal, Vector3(1.15, 0, -0.12))
	MeshKit.box(body, Vector3(0.20, 0.22, 0.26), Vector3(0.28, 1.30, 0.10), dark)
	var muzzle := MeshKit.empty("Muzzle", Vector3(0.53, 1.86, 1.18), body)
	return {"root": root, "body": body, "turret": body, "muzzle": muzzle, "wheels": []}

static func _scout(root: Node3D, paint, dark, metal, glass) -> Dictionary:
	var body := MeshKit.empty("Body", Vector3.ZERO, root)
	var wheels: Array = []
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			wheels.append(MeshKit.wheel(body, 0.42, 0.32,
				Vector3(sx * 0.86, 0.42, sz * 1.06), dark))
	MeshKit.box(body, Vector3(1.62, 0.50, 3.30), Vector3(0.0, 0.76, 0.0), paint)
	MeshKit.box(body, Vector3(1.72, 0.16, 3.40), Vector3(0.0, 0.54, 0.0), dark)
	MeshKit.box(body, Vector3(1.46, 0.62, 1.50), Vector3(0.0, 1.30, -0.30), paint)
	MeshKit.box(body, Vector3(1.50, 0.42, 0.10), Vector3(0.0, 1.36, 0.46), glass)
	MeshKit.box(body, Vector3(0.10, 0.42, 1.30), Vector3(-0.74, 1.36, -0.30), glass)
	MeshKit.box(body, Vector3(0.10, 0.42, 1.30), Vector3(0.74, 1.36, -0.30), glass)
	MeshKit.box(body, Vector3(0.34, 0.10, 0.34), Vector3(0.0, 1.66, -0.30), dark)
	for sx in [-1.0, 1.0]:
		MeshKit.box(body, Vector3(0.26, 0.16, 0.10), Vector3(sx * 0.56, 0.92, 1.66),
			MeshKit.mat(Color(1.0, 0.94, 0.72), 0.3, 0.0, Color(1.0, 0.92, 0.6), 3.0))
	var turret := MeshKit.empty("Turret", Vector3(0.0, 1.72, -0.30), body)
	MeshKit.box(turret, Vector3(0.46, 0.34, 0.46), Vector3.ZERO, paint)
	MeshKit.cyl(turret, 0.075, 1.20, Vector3(0.0, 0.04, 0.78), metal, Vector3(PI * 0.5, 0, 0))
	var muzzle := MeshKit.empty("Muzzle", Vector3(0.0, 0.04, 1.36), turret)
	return {"root": root, "body": body, "turret": turret, "muzzle": muzzle, "wheels": wheels}

static func _tracks(root: Node3D, dark) -> void:
	var plate := MeshKit.mat(Color(0.18, 0.19, 0.2), 0.75, 0.3)
	for sx in [-1.0, 1.0]:
		MeshKit.box(root, Vector3(0.72, 0.80, 4.70), Vector3(sx * 1.52, 0.50, 0.0), dark)
		for i in 5:
			MeshKit.box(root, Vector3(0.78, 0.86, 0.16),
				Vector3(sx * 1.52, 0.50, -1.9 + i * 0.95), plate)

static func _tank(root: Node3D, paint, dark, metal, glow) -> Dictionary:
	_tracks(root, dark)
	var body := MeshKit.empty("Body", Vector3.ZERO, root)
	MeshKit.box(body, Vector3(2.60, 0.72, 4.50), Vector3(0.0, 0.98, 0.0), paint)
	MeshKit.box(body, Vector3(2.74, 0.20, 4.20), Vector3(0.0, 1.36, 0.05), dark)
	MeshKit.box(body, Vector3(2.20, 0.30, 0.60), Vector3(0.0, 0.90, 2.42), dark)
	MeshKit.box(body, Vector3(1.60, 0.16, 0.16), Vector3(0.0, 1.52, 1.60), glow)
	MeshKit.box(body, Vector3(0.24, 0.24, 0.10), Vector3(0.0, 1.10, 2.72),
		MeshKit.mat(Color(1.0, 0.94, 0.72), 0.3, 0.0, Color(1.0, 0.92, 0.6), 2.5))

	var turret := MeshKit.empty("Turret", Vector3(0.0, 1.50, -0.20), body)
	MeshKit.box(turret, Vector3(1.90, 0.62, 2.10), Vector3(0.0, 0.30, 0.0), paint)
	MeshKit.box(turret, Vector3(1.98, 0.16, 1.60), Vector3(0.0, 0.62, -0.10), dark)
	MeshKit.box(turret, Vector3(0.60, 0.44, 0.70), Vector3(0.0, 0.80, 0.55), dark)
	MeshKit.cyl(turret, 0.17, 3.00, Vector3(0.0, 0.36, 1.85), metal, Vector3(PI * 0.5, 0, 0))
	MeshKit.cyl(turret, 0.24, 0.40, Vector3(0.0, 0.36, 0.45), dark, Vector3(PI * 0.5, 0, 0))
	var muzzle := MeshKit.empty("Muzzle", Vector3(0.0, 0.36, 3.30), turret)
	return {"root": root, "body": body, "turret": turret, "muzzle": muzzle, "wheels": []}

static func _missile_tank(root: Node3D, paint, dark, metal, glow) -> Dictionary:
	_tracks(root, dark)
	var body := MeshKit.empty("Body", Vector3.ZERO, root)
	MeshKit.box(body, Vector3(2.40, 0.66, 4.20), Vector3(0.0, 0.96, 0.0), paint)
	MeshKit.box(body, Vector3(2.54, 0.18, 3.90), Vector3(0.0, 1.30, 0.05), dark)
	MeshKit.box(body, Vector3(1.40, 0.14, 0.14), Vector3(0.0, 1.46, 1.40), glow)
	MeshKit.box(body, Vector3(2.00, 0.26, 0.50), Vector3(0.0, 0.88, 2.22), dark)

	var turret := MeshKit.empty("Turret", Vector3(0.0, 1.44, -0.30), body)
	MeshKit.box(turret, Vector3(1.80, 0.46, 1.70), Vector3(0.0, 0.22, 0.0), paint)
	MeshKit.box(turret, Vector3(1.10, 0.40, 0.40), Vector3(0.0, 0.50, -0.10), dark)
	for sx in [-1.0, 1.0]:
		MeshKit.box(turret, Vector3(0.34, 0.34, 1.70),
			Vector3(sx * 0.52, 0.52, 0.85), metal, Vector3(0.42, 0, 0))
		MeshKit.box(turret, Vector3(0.44, 0.44, 0.30),
			Vector3(sx * 0.52, 0.94, 1.44), dark, Vector3(0.42, 0, 0))
	var muzzle := MeshKit.empty("Muzzle", Vector3(0.0, 1.05, 1.80), turret)
	return {"root": root, "body": body, "turret": turret, "muzzle": muzzle, "wheels": []}