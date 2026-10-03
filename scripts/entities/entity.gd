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
var last_attacker: Entity = null
var last_hit_time: float = -999.0
var damage_logged: float = 0.0

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
	damage_logged = 0.0

func display_name() -> String:
	return String(def.get("name", def_id))

func is_enemy_to(other: Entity) -> bool:
	return other != null and other.team != team

func faction() -> Faction:
	return Game.faction(team)

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
	hp -= amount
	damage_logged += amount
	last_hit_time = Game.elapsed
	if source != null and source.team != team:
		last_attacker = source
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

func heal(amount: float) -> void:
	hp = minf(max_hp, hp + amount)

func die(killer: Entity = null) -> void:
	if dead:
		return
	dead = true
	set_selected(false)
	visible = false
	if world != null and world.has_method("on_entity_died"):
		world.on_entity_died(self, killer)
	died.emit(self)
	queue_free()

# --- presentation helpers -------------------------------------------------
func build_health_bar(height: float, width: float) -> void:
	_hp_bar_w = width
	_hp_bar = MeshKit.empty("HealthBar", Vector3(0, height, 0), self)
	var bg_mat := MeshKit.mat_unique(Color(0.06, 0.06, 0.07), 1.0)
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bg_mat.no_depth_test = true
	bg_mat.render_priority = 4
	var bg := MeshKit.part(_hp_bar, MeshKit.box_mesh(Vector3(width, width * 0.14, 0.04)),
		Vector3.ZERO, bg_mat)
	bg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_hp_fill_mat = MeshKit.mat_unique(Color(0.35, 0.9, 0.35), 1.0)
	_hp_fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hp_fill_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
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

func _update_overlay(delta: float) -> void:
	if _hp_bar == null:
		return
	var frac := clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
	var want := frac < 0.999 or selected
	if _hp_bar.visible != want:
		_hp_bar.visible = want
	if not want:
		return
	var fw := _hp_bar_w * 0.92
	_hp_fill.scale.x = maxf(frac, 0.001)
	_hp_fill.position.x = -fw * 0.5 * (1.0 - frac)
	if frac > 0.6:
		_hp_fill_mat.albedo_color = Color(0.30, 0.85, 0.30)
	elif frac > 0.3:
		_hp_fill_mat.albedo_color = Color(0.95, 0.80, 0.20)
	else:
		_hp_fill_mat.albedo_color = Color(0.95, 0.25, 0.18)