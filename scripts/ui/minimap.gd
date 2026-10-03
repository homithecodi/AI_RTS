class_name Minimap
extends Control

var world: GameWorld = null
var camera: RTSCamera = null
var controller: PlayerController = null

var _redraw_timer: float = 0.0
var _faction: Faction = null

func setup(w: GameWorld, cam: RTSCamera, ctrl: PlayerController) -> void:
	world = w
	camera = cam
	controller = ctrl
	custom_minimum_size = Vector2(236, 236)
	size = Vector2(236, 236)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_faction = Game.faction(Defs.TEAM_PLAYER)

func _process(delta: float) -> void:
	_redraw_timer -= delta
	if _redraw_timer <= 0.0:
		_redraw_timer = 0.1
		queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if world == null or camera == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			camera.focus_on(_map_to_world(mb.position))
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			var dest := _map_to_world(mb.position)
			if controller != null:
					var units := controller.selected_units()
					if not units.is_empty():
						controller.command_move(units, dest, false)
						emit_status("Moving %d units" % units.size())

func emit_status(text: String) -> void:
	if controller != null:
		controller.emit_status(text)

func _uv_to_local(uv: Vector2) -> Vector2:
	return uv * size

func _map_to_world(local_pos: Vector2) -> Vector3:
	var uv := (local_pos / size).clamp(Vector2.ZERO, Vector2.ONE)
	return world.terrain.map_to_world(uv.x, uv.y)

func _draw() -> void:
	if world == null or world.terrain == null:
		return
	var rect := Rect2(Vector2.ZERO, size)
	if world.terrain.minimap_texture != null:
		draw_texture_rect(world.terrain.minimap_texture, rect, false)
	else:
		draw_rect(rect, Color(0.15, 0.18, 0.14))

	# Ore fields
	for c in world.ore_clusters:
		var cpos: Vector2 = c["pos"]
		var p := _uv_to_local(world.terrain.world_to_map(cpos.x, cpos.y))
		var r := float(c["radius"]) / Terrain.MAP_SIZE * size.x
		draw_circle(p, r, Color(0.95, 0.66, 0.18, 0.30))
		draw_arc(p, r, 0, TAU, 18, Color(0.98, 0.75, 0.25, 0.65), 1.0)

	# Structures
	for b in world.buildings:
		if b.dead:
			continue
		var bp := _uv_to_local(world.terrain.world_to_map(b.global_position.x, b.global_position.z))
		var col := Defs.team_color(b.team)
		var w := float(b.def.get("size_x", 8.0)) / Terrain.MAP_SIZE * size.x
		var h := float(b.def.get("size_z", 8.0)) / Terrain.MAP_SIZE * size.y
		draw_rect(Rect2(bp - Vector2(w, h) * 0.5, Vector2(maxf(w, 3.0), maxf(h, 3.0))),
			col.darkened(0.15))
		draw_rect(Rect2(bp - Vector2(w, h) * 0.5, Vector2(maxf(w, 3.0), maxf(h, 3.0))),
			col.lightened(0.3), false, 1.0)
		if not b.active:
			draw_line(bp, bp, Color(1, 1, 1, 0.8), 1.0)

	# Units
	for u in world.units:
		if u.dead:
			continue
		var up := _uv_to_local(world.terrain.world_to_map(u.global_position.x, u.global_position.z))
		var col2 := Defs.team_color(u.team)
		draw_circle(up, 2.4 if u.def_id != "tank" else 3.0, col2)
		if u.selected:
			draw_arc(up, 4.6, 0, TAU, 12, Color(0.4, 1.0, 0.5, 0.95), 1.0)

	_draw_camera_frustum(rect)
	draw_rect(rect, Color(0.05, 0.06, 0.05, 0.9), false, 2.0)

func _draw_camera_frustum(rect: Rect2) -> void:
	if camera == null or camera.camera == null:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var screen := vp.get_visible_rect().size
	var corners := [Vector2.ZERO, Vector2(screen.x, 0),
		Vector2(screen.x, screen.y), Vector2(0, screen.y)]
	var pts: Array[Vector2] = []
	for c in corners:
		var hit := camera.ray_to_ground(c)
		if hit.is_empty():
			pts.append(camera.project_ground(camera.focus_point()))
			continue
		var p: Vector3 = hit["point"]
		var uv := world.terrain.world_to_map(p.x, p.z)
		pts.append(_uv_to_local(uv).clamp(Vector2.ZERO, size))
	for i in 4:
		draw_line(pts[i], pts[(i + 1) % 4], Color(1, 1, 1, 0.55), 1.0)
	var center := _uv_to_local(world.terrain.world_to_map(
		camera.focus_point().x, camera.focus_point().z))
	draw_line(center - Vector2(5, 0), center + Vector2(5, 0), Color(1, 1, 1, 0.7), 1.0)
	draw_line(center - Vector2(0, 5), center + Vector2(0, 5), Color(1, 1, 1, 0.7), 1.0)