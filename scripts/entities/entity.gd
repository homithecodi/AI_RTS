class_name Entity
extends Node3D
# Shared base for every damageable thing on the battlefield.

signal died(entity: Entity)

var team: int = -1
var def_id: String = ""
var def: Dictionary = {}
var hp: float = 100.0
var max_hp: float = 100.0
var dead: bool = false
var world: GameWorld = null
var selected: bool = false

var _hp_bar: Node3D = null
var _hp_fill: MeshInstance3D = null
var _hp_fill_mat: StandardMaterial3D = null
var _hp_bar_w: float = 2.0
var _sel_ring: MeshInstance3D = null

func setup(d: Dictionary, in_team: int, w: Node3D) -> void:
	def = d
	def_id = String(d.get("id", ""))
	team = in_team
	world = w
	max_hp = float(d.get("hp", 100.0))
	hp = max_hp

func display_name() -> String:
	return String(def.get("name", def_id))

func aim_height() -> float:
	return float(def.get("height", 2.0)) * 0.45

func is_moving() -> bool:
	return false

func center() -> Vector3:
	return global_position + Vector3(0, aim_height(), 0)

func distance_to(other: Entity) -> float:
	return global_position.distance_to(other.global_position)

func take_damage(amount: float, by_team: int, source: Entity = null) -> void:
	if dead or amount <= 0.0:
		return
	if not is_instance_valid(source):
		source = null
	hp -= amount
	if source != null and source.team != team:
		on_damaged(source)
	var victim := Game.faction(team)
	if victim != null:
		victim.damage_taken += amount
	var attacker := Game.faction(by_team)
	if attacker != null and source != null and source.team == by_team:
		attacker.damage_dealt += amount
	if hp <= 0.0:
		die(source)

func on_damaged(_source: Entity) -> void:
	pass

func die(killer: Entity = null) -> void:
	if dead:
		return
	_finish_death(killer)

# Shared teardown for every damageable. Subclasses add their own death effects
# and then call this, so the bookkeeping lives in one place.
func _finish_death(killer: Entity) -> void:
	dead = true
	set_selected(false)
	visible = false
	if world != null and world.has_method("on_entity_died"):
		world.on_entity_died(self, killer)
	died.emit(self)
	queue_free()

# --- presentation helpers -------------------------------------------------
# The bar is turned towards the camera by hand in _update_overlay instead of
# using BILLBOARD_ENABLED: the billboard vertex shader rebuilds the model-view
# matrix from the camera basis and keeps only the translation, so it silently
# throws away the fill's scale and offset and every bar renders full width.
func build_health_bar(height: float, width: float) -> void:
	_hp_bar_w = width
	_hp_bar = MeshKit.empty("HealthBar", Vector3(0, height, 0), self)
	var bg_mat := MeshKit.mat_unique(Color(0.06, 0.06, 0.07), 1.0)
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.no_depth_test = true
	bg_mat.render_priority = 4
	var bg := MeshKit.part(_hp_bar, MeshKit.box_mesh(Vector3(width, width * 0.14, 0.04)),
		Vector3.ZERO, bg_mat)
	bg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_hp_fill_mat = MeshKit.mat_unique(Color(0.35, 0.9, 0.35), 1.0)
	_hp_fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hp_fill_mat.no_depth_test = true
	_hp_fill_mat.render_priority = 5
	var fw := width * 0.92
	_hp_fill = MeshKit.part(_hp_bar, MeshKit.box_mesh(Vector3(fw, width * 0.09, 0.05)),
		Vector3(0, 0, 0.03), _hp_fill_mat)
	_hp_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hp_bar.visible = false

func build_selection_ring(radius: float) -> void:
	var mat := MeshKit.mat_unique(Defs.team_color(team), 1.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.85
	mat.no_depth_test = true
	mat.render_priority = 3
	var torus := TorusMesh.new()
	torus.inner_radius = maxf(radius, 0.6)
	torus.outer_radius = torus.inner_radius + 0.14
	torus.rings = 28
	torus.ring_segments = 5
	_sel_ring = MeshKit.part(self, torus, Vector3(0, 0.12, 0), mat)
	_sel_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sel_ring.visible = false

func set_selected(value: bool) -> void:
	if selected == value:
		return
	selected = value
	if _sel_ring != null:
		_sel_ring.visible = value

func _update_overlay() -> void:
	if _hp_bar == null:
		return
	var frac := clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
	var want := frac < 0.999 or selected
	if _hp_bar.visible != want:
		_hp_bar.visible = want
	if not want:
		return
	_face_camera()
	var fw := _hp_bar_w * 0.92
	_hp_fill.scale.x = maxf(frac, 0.001)
	_hp_fill.position.x = -fw * 0.5 * (1.0 - frac)
	if frac > 0.6:
		_hp_fill_mat.albedo_color = Color(0.30, 0.85, 0.30)
	elif frac > 0.3:
		_hp_fill_mat.albedo_color = Color(0.95, 0.80, 0.20)
	else:
		_hp_fill_mat.albedo_color = Color(0.95, 0.25, 0.18)

# Yaw-only billboard so the bar's local +X stays screen-right, which is what the
# left-anchored fill offset above assumes.
#
# The bar is aimed along the camera's view direction, not at the camera's
# position: aiming at the position is a radial billboard, which makes every bar
# swing by a different amount as the camera pans or zooms. Sharing one view
# direction keeps all the bars coplanar and still, and they only turn when the
# camera itself turns.
#
# The aim still has to be expressed in the parent's frame: structures carry
# their heading on their own rotation.y, so a world yaw assigned straight to
# rotation.y would be added to that heading.
func _face_camera() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var cam := vp.get_camera_3d()
	if cam == null:
		return
	# The camera looks down its local -Z, so its local +Z points back out of the
	# screen: that is the direction a billboard's face should point, and it keeps
	# the bar's local +X aligned with screen-right.
	var aim: Vector3 = cam.global_transform.basis.z
	aim.y = 0.0
	if aim.length_squared() < 0.0001:
		return
	var parent := _hp_bar.get_parent() as Node3D
	if parent == null:
		_hp_bar.rotation.y = atan2(aim.x, aim.z)
		return
	var local := parent.global_transform.basis.inverse() * aim
	local.y = 0.0
	if local.length_squared() < 0.000001:
		return
	_hp_bar.rotation.y = atan2(local.x, local.z)