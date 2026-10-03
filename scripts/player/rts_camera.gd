class_name RTSCamera
extends Node3D
# Classic RTS rig: a focus point on the ground with an orbit chain attached to
# it, and a Camera3D hanging off the end of that chain.

const MIN_DIST := 26.0
const MAX_DIST := 190.0
const MIN_PITCH := -1.36
const MAX_PITCH := -0.60
const PAN_SPEED := 46.0
const EDGE_MARGIN := 14.0

var camera: Camera3D
var focus: Node3D
var yaw_node: Node3D
var pitch_node: Node3D

var world: GameWorld = null
var yaw: float = 0.0
var pitch: float = -0.86
var distance: float = 78.0
var pan_velocity := Vector3.ZERO
var edge_scroll: bool = true
var _dragging := false
var _last_mouse := Vector2.ZERO

func _ready() -> void:
	focus = Node3D.new()
	focus.name = "Focus"
	add_child(focus)
	yaw_node = Node3D.new()
	yaw_node.name = "Yaw"
	focus.add_child(yaw_node)
	pitch_node = Node3D.new()
	pitch_node.name = "Pitch"
	yaw_node.add_child(pitch_node)

	camera = Camera3D.new()
	camera.name = "Camera"
	camera.near = 0.4
	camera.far = 1400.0
	camera.fov = 62.0
	camera.current = true
	pitch_node.add_child(camera)
	_apply()

func setup(w: GameWorld, start_pos: Vector3) -> void:
	world = w
	# The rig orbits behind the focus point, so the yaw has to point the camera
	# back from the map edge towards the middle: yaw = atan2(pos.x, pos.z) puts
	# the camera on the far side of start_pos looking at the enemy base.
	yaw = atan2(start_pos.x, start_pos.z)
	focus_on(start_pos)

## Push the current yaw, pitch and distance onto the rig nodes.
##
## Nothing else writes to those nodes, and it is not called every frame: the pitch and
## distance only change on input, and yaw only when rotating. Anything that sets
## yaw/pitch/distance from code must call this or the change will not appear.
func _apply() -> void:
	yaw_node.rotation.y = yaw
	pitch_node.rotation.x = pitch
	camera.position = Vector3(0, 0, distance)

## Move the focus point, clamped to the playable area and dropped onto the terrain.
func focus_on(p: Vector3) -> void:
	var clamped := _clamp(p)
	focus.position = clamped
	if world != null and world.terrain != null:
		focus.position.y = world.terrain.height_at(clamped.x, clamped.z) + 1.5
	_apply()

func focus_point() -> Vector3:
	return focus.global_position

func _clamp(p: Vector3) -> Vector3:
	var h := 200.0
	if world != null:
		h = world.map_half() - 12.0
	return Vector3(clampf(p.x, -h, h), p.y, clampf(p.z, -h, h))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom(-1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom(1)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
			_last_mouse = mb.position
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		var delta := mm.position - _last_mouse
		_last_mouse = mm.position
		yaw -= delta.x * 0.006
		pitch = clampf(pitch - delta.y * 0.005, MIN_PITCH, MAX_PITCH)
		_apply()

## Zoom, which also tilts the camera towards a steeper angle. Zooming out flattens
## the view to show more of the map; zooming in tilts down for a close view.
func _zoom(direction: float) -> void:
	distance = clampf(distance * (1.0 + direction * 0.12), MIN_DIST, MAX_DIST)
	pitch = clampf(lerpf(pitch, -0.95, 0.14 * absf(direction)), MIN_PITCH, MAX_PITCH)
	_apply()

func _process(delta: float) -> void:
	var pan := Vector3.ZERO
	var speed := PAN_SPEED * (0.35 + distance / MAX_DIST * 1.15)
	var forward := Vector3(-sin(yaw), 0, -cos(yaw))
	# Screen right of `forward` with up = +Y: right = up x forward, not forward x up.
	var right := Vector3(-forward.z, 0, forward.x)
	if Input.is_action_pressed(&"cam_left"):
		pan -= right
	if Input.is_action_pressed(&"cam_right"):
		pan += right
	if Input.is_action_pressed(&"cam_up"):
		pan += forward
	if Input.is_action_pressed(&"cam_down"):
		pan -= forward
	if edge_scroll:
		pan += _edge_delta() * speed
	if pan.length() > 0.001:
		pan = pan.normalized() * speed
	pan_velocity = pan_velocity.lerp(pan, 1.0 - exp(-14.0 * delta))
	focus.position += pan_velocity * delta
	var h := 205.0 if world == null else world.map_half() - 6.0
	focus.position.x = clampf(focus.position.x, -h, h)
	focus.position.z = clampf(focus.position.z, -h, h)
	if world != null and world.terrain != null:
		focus.position.y = world.terrain.height_at(focus.position.x, focus.position.z) + 1.5

	var rot := 0.0
	if Input.is_action_pressed(&"cam_rotate_left"):
		rot -= 1.0
	if Input.is_action_pressed(&"cam_rotate_right"):
		rot += 1.0
	if rot != 0.0:
		yaw += rot * delta * 1.9
		_apply()

func _edge_delta() -> Vector3:
	var vp := get_viewport()
	if vp == null:
		return Vector3.ZERO
	var size := vp.get_visible_rect().size
	var m := vp.get_mouse_position()
	var dir := Vector2.ZERO
	if m.x <= EDGE_MARGIN:
		dir.x -= 1.0
	elif m.x >= size.x - EDGE_MARGIN:
		dir.x += 1.0
	if m.y <= EDGE_MARGIN:
		dir.y += 1.0
	elif m.y >= size.y - EDGE_MARGIN:
		dir.y -= 1.0
	if dir == Vector2.ZERO:
		return Vector3.ZERO
	var forward := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(-forward.z, 0, forward.x)
	return (right * dir.x + forward * dir.y).normalized()

# --- picking helpers -----------------------------------------------------
## Screen position to the ground point under it, for picking. Returns an empty
## dictionary when the ray misses the terrain (pointing at the sky).
func ray_to_ground(screen_pos: Vector2) -> Dictionary:
	if world == null or world.terrain == null:
		return {}
	return world.terrain.raycast(camera.project_ray_origin(screen_pos),
		camera.project_ray_normal(screen_pos))

## Screen position for a world point, or (0,0) when it is behind the camera.
func project_ground(p: Vector3) -> Vector2:
	return camera.unproject_position(p)

# True when a world point is both in front of the camera and inside the view.
## True when a world point falls inside the viewport, used to cull off-screen units
## during box selection.
func is_point_visible(p: Vector3) -> bool:
	var xf := camera.global_transform
	if xf.basis.z.dot(p - xf.origin) >= 0.0:
		return false
	var vp := get_viewport()
	if vp == null:
		return false
	return vp.get_visible_rect().has_point(camera.unproject_position(p))