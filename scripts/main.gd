extends Node3D
# Assembles the environment, the battlefield, the camera rig, the player
# controller, the enemy AI and the HUD.

var world: GameWorld
var camera: RTSCamera
var controller: PlayerController
var ai: EnemyAI
var hud: HUD

@export var map_seed: int = 20260101
@export var ai_difficulty: float = 1.0

func _ready() -> void:
	_setup_environment()
	_setup_world()
	_setup_camera()
	_setup_players()
	_setup_hud()
	world.start()
	_push_intro_messages()

func _setup_environment() -> void:
	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY

	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.16, 0.30, 0.52)
	sky_material.sky_horizon_color = Color(0.62, 0.68, 0.72)
	sky_material.ground_bottom_color = Color(0.20, 0.20, 0.19)
	sky_material.ground_horizon_color = Color(0.52, 0.52, 0.48)
	sky_material.sun_angle_max = 22.0
	sky_material.sun_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = sky_material
	e.sky = sky

	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 1.0
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.0
	e.ssao_enabled = false
	e.glow_enabled = true
	e.glow_intensity = 0.45
	e.glow_bloom = 0.12
	e.fog_enabled = true
	e.fog_light_color = Color(0.63, 0.70, 0.76)
	e.fog_density = 0.0016
	e.fog_sky_affect = 0.25
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-54, -126, 0)
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.97, 0.90)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 190.0
	sun.directional_shadow_blend_splits = true
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.rotation_degrees = Vector3(-28, 46, 0)
	fill.light_energy = 0.28
	fill.light_color = Color(0.74, 0.82, 1.0)
	fill.shadow_enabled = false
	add_child(fill)

func _setup_world() -> void:
	world = GameWorld.new()
	world.name = "World"
	add_child(world)
	world.setup(map_seed)
	world.spawn_starting_base(Defs.TEAM_PLAYER)
	world.spawn_starting_base(Defs.TEAM_ENEMY)

func _setup_camera() -> void:
	camera = RTSCamera.new()
	camera.name = "CameraRig"
	add_child(camera)
	camera.setup(world, world.base_pos(Defs.TEAM_PLAYER))
	camera.focus_on(world.base_pos(Defs.TEAM_PLAYER))

func _setup_players() -> void:
	controller = PlayerController.new()
	controller.name = "PlayerController"
	add_child(controller)
	controller.setup(world, camera)

	ai = EnemyAI.new()
	ai.name = "EnemyAI"
	add_child(ai)
	ai.setup(world, ai_difficulty)

func _setup_hud() -> void:
	hud = HUD.new()
	hud.name = "HUD"
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(hud)
	hud.setup(world, camera, controller, ai)
	hud.minimap.setup(world, camera, controller)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var ev := event as InputEventKey
		if not ev.pressed or ev.echo:
			return
		match ev.keycode:
			KEY_SPACE:
				Game.toggle_pause()
			KEY_BRACKETRIGHT:
				Game.cycle_speed(1)
			KEY_BRACKETLEFT:
				Game.cycle_speed(-1)
			KEY_F1:
				hud.toggle_help()
			KEY_ESCAPE:
				if Game.match_over:
					hud.restart()

func _push_intro_messages() -> void:
	hud.notify("Enemy base is to the north-east. Destroy every red structure to win.")
	hud.notify("Ore funds construction. Power keeps your base running.")
