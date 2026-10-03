class_name Effects
extends RefCounted
# Pooled, self-cleaning visual effects. Every effect removes itself when done.
# All effect materials are unique instances because they get mutated while fading.
#
# Nothing here holds state: each call builds its geometry under the given parent
# (usually GameWorld.effects), animates it with a SceneTreeTween, and frees it. That
# keeps the main scene free of effect bookkeeping at the cost of a little garbage per
# shot, which is a good trade at these volumes.
#
# Because the nodes and the tween callbacks outlive a single frame, every mutation
# goes through a unique material rather than the shared MeshKit cache.

## A short emissive line from muzzle to target, for hitscan shots.
static func tracer(parent: Node3D, from: Vector3, to: Vector3, color: Color,
		width: float = 0.07, life: float = 0.11) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var seg := to - from
	var dist := seg.length()
	if dist < 0.08:
		return
	var dir := seg / dist
	if absf(dir.dot(Vector3.UP)) > 0.998:
		return
	var mi := MeshKit.part(parent, MeshKit.box_mesh(Vector3(width, width, 1.0)),
		Vector3.ZERO, MeshKit.mat_unique(color, 0.2, 0.0, color, 5.0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = (from + to) * 0.5
	mi.look_at(to, Vector3.UP)
	mi.scale = Vector3(1.0, 1.0, dist)
	_fade(mi, life, true)

## Bright pop at the muzzle, plus a light so the shot briefly lights the ground.
static func muzzle_flash(parent: Node3D, pos: Vector3, color: Color,
		size: float = 1.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var mi := MeshKit.part(parent, MeshKit.sphere_mesh(0.30 * size), pos,
		MeshKit.mat_unique(color, 0.2, 0.0, color, 8.0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pop(mi, 0.09, 2.6)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 3.0 * size
	light.omni_range = 7.0 * size
	light.shadow_enabled = false
	light.position = pos
	parent.add_child(light)
	_fade_light(light, 0.09)

## Fireball and smoke, both growing as they fade. size scales the whole effect, so
## a tank and a rifleman read differently at the same glance.
static func explosion(parent: Node3D, pos: Vector3, size: float = 1.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var fire := Color(1.0, 0.55, 0.15)
	var mi := MeshKit.part(parent, MeshKit.sphere_mesh(0.7 * size), pos,
		MeshKit.mat_unique(fire, 0.4, 0.0, fire, 6.0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pop(mi, 0.4, 3.4)
	var smoke := MeshKit.part(parent, MeshKit.sphere_mesh(0.5 * size),
		pos + Vector3(0, 0.5, 0), MeshKit.mat_unique(Color(0.22, 0.21, 0.20), 1.0, 0.0))
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pop(smoke, 0.85, 2.6)
	var light := OmniLight3D.new()
	light.light_color = fire
	light.light_energy = 5.0 * size
	light.omni_range = 13.0 * size
	light.shadow_enabled = false
	light.position = pos
	parent.add_child(light)
	_fade_light(light, 0.35)

## Flat expanding ring used when a structure finishes construction.
static func dust(parent: Node3D, pos: Vector3, size: float = 1.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var mi := MeshKit.part(parent, MeshKit.sphere_mesh(0.45 * size), pos,
		MeshKit.mat_unique(Color(0.66, 0.60, 0.47), 1.0, 0.0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pop(mi, 0.7, 2.8)

## Expand a mesh while fading it out, then free it.
static func _pop(node: Node3D, life: float, growth: float) -> void:
	var tree := node.get_tree()
	if tree == null:
		return
	var mat := node.material_override as StandardMaterial3D
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var start_scale := node.scale
	var tw := tree.create_tween()
	tw.set_parallel(true)
	tw.tween_property(node, "scale", start_scale * growth, life)
	tw.tween_property(mat, "albedo_color:a", 0.0, life)
	tw.chain().tween_callback(node.queue_free)

## Fade a mesh in place, optionally driving its emission as well as its alpha.
static func _fade(node: Node3D, life: float, emissive: bool) -> void:
	var tree := node.get_tree()
	if tree == null:
		return
	var mat := node.material_override as StandardMaterial3D
	if mat == null:
		return
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var tw := tree.create_tween()
	if emissive:
		tw.tween_property(mat, "emission_energy_multiplier", 0.0, life)
	else:
		tw.tween_property(mat, "albedo_color:a", 0.0, life)
	tw.tween_callback(node.queue_free)

## Fade a light out and free it.
static func _fade_light(light: Light3D, life: float) -> void:
	var tree := light.get_tree()
	if tree == null:
		return
	var tw := tree.create_tween()
	tw.tween_property(light, "light_energy", 0.0, life)
	tw.tween_callback(light.queue_free)

# Scattered debris left where a unit died.
## Persistent-ish debris: a scorch decal plus a few chunks that fall and settle. The
## chunks are freed by their own tween, so nothing accumulates.
static func wreck(parent: Node3D, origin: Vector3, size: float) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var tree := parent.get_tree()
	if tree == null:
		return
	var scorch := MeshKit.part(parent, MeshKit.sphere_mesh(0.9 * size),
		origin + Vector3(0, 0.06, 0),
		MeshKit.mat_unique(Color(0.14, 0.13, 0.12), 1.0, 0.0))
	scorch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := scorch.material_override as StandardMaterial3D
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var tw0 := tree.create_tween()
	tw0.tween_property(scorch, "scale", Vector3.ONE * 1.5, 1.6)
	tw0.tween_property(mat, "albedo_color:a", 0.0, 1.6)
	tw0.tween_callback(scorch.queue_free)

	var debris_mat := MeshKit.mat(Color(0.16, 0.15, 0.15), 0.9, 0.25)
	for i in 4:
		var chunk := MeshKit.part(parent,
			MeshKit.box_mesh(Vector3.ONE * randf_range(0.35, 0.9) * size),
			origin + Vector3(randf_range(-1.0, 1.0), randf_range(0.15, 0.7),
				randf_range(-1.0, 1.0)) * size,
			debris_mat, Vector3(randf() * TAU, randf() * TAU, randf() * TAU))
		var tw := tree.create_tween()
		tw.set_parallel(true)
		tw.tween_property(chunk, "position:y", origin.y + 0.05, 1.2)\
			.set_delay(randf() * 0.2)
		tw.tween_property(chunk, "rotation",
			Vector3(randf() * 5.0, randf() * 5.0, randf() * 5.0), 1.2)
		tw.chain().tween_callback(chunk.queue_free)