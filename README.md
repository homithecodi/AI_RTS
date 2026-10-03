# Generals

A small real-time-strategy game in Godot 4 (GDScript). You command a blue base on
one corner of a procedural map, build an economy out of ore refineries, and destroy
every red structure to win. A single AI opponent builds and attacks on its own.

Everything is generated in code: terrain, units, structures, effects and UI. There
are no model or texture files to keep in sync, which is why `scripts/fx/mesh_kit.gd`
exists.

## Running

Open the folder in Godot 4.x and press play, or:

```
godot --path .
```

`project.godot` declares a single autoload, `Game` (`scripts/core/game_state.gd`).
Every script reaches shared state through it.

## Controls

| Input | Action |
| --- | --- |
| `W A S D` / arrows | pan the camera |
| Mouse to screen edge | pan |
| `Q` / `E`, middle-drag | rotate the camera |
| Wheel, `+` / `-` | zoom (also tilts) |
| `Home` | centre on the last event |
| Left click | select, or place a structure / set a rally point |
| Right click | move / attack-move; cancels placement |
| Drag box | select units |
| `F` | arm attack-move for the next order |
| `X` | stop |
| `H` | select all combat units |
| `1` / `2` | assign / recall control group |
| `Space`, `[` / `]` | pause, game speed |

The bindings are registered in code by `Defs.setup_input()`, not in the project
settings, so they are identical on every machine.

## Architecture

```
scripts/
  main.gd                  assembles the scene and owns the frame-to-frame services
  core/
    defs.gd                all balance data (unit/structure tables) + input bindings
    game_state.gd          Game autoload: factions, match state, registry, signals
    faction.gd             one side's roster, ore, power and income
  world/
    terrain.gd             heightfield generation, mesh, raycasts, minimap texture
    game_world.gd          battlefield root: spawning, spatial queries, splash damage
    ore_node.gd            a harvestable ore field
  entities/
    entity.gd              shared base: hp, damage, health bar, selection ring, death
    unit.gd                mobile unit: orders, steering, combat
    building.gd            structure: construction, production queue, income, turret
    unit_models.gd         procedural meshes for units
    building_models.gd     procedural meshes for structures
  player/
    player_controller.gd   input handling, selection, placement, control groups
    rts_camera.gd          orbit rig, panning, picking
  ui/
    hud.gd                 resource bar, selection panel, production panel, messages
    minimap.gd             map overview, markers, camera frustum
  ai/
    enemy_ai.gd            the opposing base: build order, waves, defence
  fx/
    mesh_kit.gd            cached material and mesh factory
    effects.gd             explosions, tracers, dust, wrecks (self-freeing)
    projectile.gd          homing projectiles
scenes/main.tscn           the only scene; everything else is built in code
```

Data flows in one direction: `main.gd` wires the objects together and then gets out
of the way. `Game` owns cross-cutting state, `GameWorld` owns the battlefield,
entities own their own behaviour, and the UI reads state but never mutates it.

## Conventions worth knowing

These are the rules that are easy to break by accident. They are also commented at
each relevant site in the code.

### Heading: `rotation.y = atan2(dir.x, dir.z)`

Every model is built pointing down **local +Z**, and yaw is measured from +Z. So to
face a direction `d`, use `rotation.y = atan2(d.x, d.z)` — note the argument order,
which is the reverse of the common `atan2(x, -z)` form.

- Unit body yaw: `Unit.facing`. Turret yaw is stored in world space and converted to
  a local offset at draw time: `turret.rotation.y = wrapf(_turret_yaw - facing, ...)`.
- Structure yaw: `Building.rotation.y` (`heading`), passed in at spawn.

Consequence: anything that orients itself from a world direction must use
`atan2(d.x, d.z)`, and any hand-authored model part that should point "forward"
belongs at positive z.

### Minimap compass: +X is east, +Z is north

`Terrain.world_to_map()` maps `+Z` to the **top** of the map. That matches the
in-game briefing ("Enemy base is to the north-east") and the fact that the enemy base
sits at `(+X, +Z)`. If you change the mapping you must change
`build_minimap_texture()` with it or the texture and the markers disagree.

The minimap is fixed north-up; it does not rotate with the camera. The drawn camera
frustum is what ties it to the current view.

### The spatial grid must never hold a freed entity

`GameWorld` keeps units and structures in a uniform grid for range queries. Entities
`queue_free()` in the same frame they die, so `on_entity_died()` **evicts them from the
grid before that happens** (`_forget_unit` / `_forget_building`). A freed instance
left in a bucket is dereferenced by every subsequent query, which floods the log with
`previously freed` errors and looks like a crash.

The same rule applies anywhere a reference outlives a frame: selection
(`PlayerController.live_selection()`), projectile targets, AI group snapshots
(`EnemyAI._order_group()`), and damage sources (`Entity.take_damage()`).

### Death goes through `Entity._finish_death()`

Subclasses override `die()` to spawn effects and then call `_finish_death()`, which
owns the bookkeeping: flag, deselect, hide, deregister, emit `died`, free. Anything
that needs to react to a death should connect to the `died` signal rather than
reordering `die()`.

### `Game` outlives the scene

Autoloads are not re-instantiated by `reload_current_scene()`. `Game.reset_match()`
drops every reference into the old scene (and resets ore, power, clock and speed) and
is called from the PLAY AGAIN button before the reload.

## Engine notes that cost real debugging time

These are Godot behaviours, not project rules, but they shaped the code:

- **A billboard discards the node transform.** With `BILLBOARD_ENABLED` the shader
  rebuilds the model-view matrix from the camera basis and keeps only the
  translation, so `scale` and rotation on that node are silently ignored
  (`billboard_keep_scale` defaults to `false`). The health bar therefore yaws itself
  toward the camera in `_face_camera()` instead of using a material billboard.
- **Aim a billboard along the view direction, not at the camera position.** Aiming at
  the position is a radial billboard: every bar swings by a different amount as the
  camera pans, which looks like the bars are wriggling.
- **Triangle winding.** Godot treats a triangle as front-facing when its geometric
  normal points *away* from the viewer. An upward-facing quad must therefore be wound
  `a,b,c` — the opposite of the OpenGL habit. `Terrain._build_mesh()` is written
  that way deliberately.
- **`is` and property access on a freed object do not return null**, they raise
  `previously freed` errors. Check `is_instance_valid()` *before* the type test, not
  after — the type test is itself the thing that blows up.
- **`Node3D.velocity` does not exist** outside physics bodies; read the unit's own
  `velocity`.

## Tuning the game

All balance lives in `Defs.UNITS` and `Defs.BUILDINGS`; nothing is hard-coded
elsewhere. Adding a unit means adding an entry (plus a branch in `UnitModels.build()`
for its mesh if it is a new silhouette) and referencing it from a structure's
`units` list.