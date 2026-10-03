class_name Projectile
extends Node3D

var target_point: Vector3
var target_entity: Entity = null
var damage: float = 10.0
var splash: float = 0.0
var speed: float = 42.0
var team: int = 0
var color: Color = Color(1.0, 0.75, 0.35)
var world: Node3D = null
var shooter: Entity = null
var _mesh: MeshInstance3D = null
var _light: OmniLight3D = null
var _life: float = 8.0

static func fire(parent: Node3D, from: Vector3, target: Entity, dmg: float,
		splash_radius: float, in_team: int, w: GameWorld,
		from_entity: Entity) -> Projectile:
	var p := Projectile.new()
	p.team = in_team
	p.damage = dmg
	p.splash = splash_radius
	p.world = w
	p.shooter = from_entity
	p.color = Defs.team_color(in_team).lerp(Color(1.0, 0.8, 0.4), 0.55)
	p.position = from
	p.target_entity = target
	p.target_point = from + Vector3(0, 0, -1)
	if target != null and not target.dead:
		# Lead the target a little so fast movers are not always missed.
		p.target_point = target.global_position + Vector3(0, target.aim_height(), 0)
		if target.is_moving():
			p.target_point += target.velocity * clampf(
				from.distance_to(p.target_point) / p.speed, 0.0, 1.2)
	p._build()
	parent.add_child(p)
	return p

func _build() -> void:
	_mesh = MeshKit.part(self, MeshKit.sphere_mesh(0.22), Vector3.ZERO,
		MeshKit.mat_unique(color, 0.2, 0.0, color, 6.0))
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var trail := MeshKit.part(_mesh, MeshKit.cyl_mesh(0.09, 1.6),
		Vector3(0, 0, 0.8),
		MeshKit.mat_unique(color.lerp(Color.WHITE, 0.3), 0.2, 0.0, color, 3.0))
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	trail.rotation_degrees.x = -90.0
	_light = OmniLight3D.new()
	_light.light_color = color
	_light.light_energy = 1.6
	_light.omni_range = 5.0
	_light.shadow_enabled = false
	add_child(_light)

func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	if is_instance_valid(target_entity) and not target_entity.dead:
		target_point = target_entity.global_position + Vector3(0, target_entity.aim_height(), 0)
	var to := target_point - global_position
	var dist := to.length()
	var step := speed * delta
	if dist <= step or _life <= 0.05:
		_impact()
		return
	global_position += to / dist * step
	if absf(to.normalized().dot(Vector3.UP)) < 0.999:
		look_at(global_position + to, Vector3.UP)

func _impact() -> void:
	var parent := get_parent()
	Effects.muzzle_flash(parent, global_position, color, 1.4)
	# The shooter may have died while this shell was in the air.
	var src: Entity = shooter if is_instance_valid(shooter) else null
	if splash > 0.1 and world != null and world.has_method("splash_damage"):
		world.splash_damage(global_position, splash, damage, team, src)
	elif is_instance_valid(target_entity) and not target_entity.dead:
		target_entity.take_damage(damage, team, src)
	queue_free()