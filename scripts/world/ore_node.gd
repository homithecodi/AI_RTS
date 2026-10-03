class_name OreNode
extends Node3D
# A harvestable ore field: the bobbing crystals plus the remaining reserve that
# refineries drain.
#
# The node owns its own depletion behaviour, so a refinery only has to check `active`
# and call take(). pos_xz is kept separately from position because the minimap and
# the AI both work in 2D, and because the crystal layout is seeded from it, which
# makes the same field look identical every time the map is generated.

var amount: float = Defs.ORE_PER_NODE
var max_amount: float = Defs.ORE_PER_NODE
var radius: float = 4.2
var pos_xz: Vector2 = Vector2.ZERO
var active: bool = true
var _crystals: Array[MeshInstance3D] = []
var _base_scale: Array[Vector3] = []
var _bob_phase: float = 0.0

## Build a field with the given reserve. The caller is responsible for placing it on
## the terrain surface.
static func create(p: Vector3, ore: float = Defs.ORE_PER_NODE) -> OreNode:
	var n := OreNode.new()
	n.max_amount = ore
	n.amount = ore
	n.position = p
	n.pos_xz = Vector2(p.x, p.z)
	n._build()
	return n

## Scatter the crystals around the base plate. The seed is derived from the field
## position rather than random, so a given map always produces the same layout.
func _build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(pos_xz.x) * 71.0 + absf(pos_xz.y) * 137.0)
	var count := rng.randi_range(3, 6)
	var glow := MeshKit.mat(Color(0.95, 0.62, 0.16), 0.25, 0.35,
		Color(1.0, 0.72, 0.22), 1.9)
	var base_m := MeshKit.mat(Color(0.34, 0.30, 0.26), 0.9, 0.1)
	MeshKit.box(self, Vector3(radius * 1.7, 0.18, radius * 1.7), Vector3(0, 0.09, 0), base_m)
	for i in count:
		var a := TAU * float(i) / float(count) + rng.randf() * 0.7
		var d := rng.randf_range(0.0, radius * 0.62)
		var h := rng.randf_range(1.0, 2.3)
		var w := rng.randf_range(0.45, 0.85)
		var mi := MeshKit.box(self, Vector3(w, h, w * 0.8),
			Vector3(cos(a) * d, h * 0.5, sin(a) * d), glow,
			Vector3(rng.randf_range(-0.18, 0.18), rng.randf() * TAU, rng.randf_range(-0.18, 0.18)))
		_crystals.append(mi)
		_base_scale.append(Vector3.ONE)
	_bob_phase = rng.randf() * TAU

## Extract up to `ore` from the field and return what was actually available, which
## is less than requested once the reserve runs low. Empties the field for good.
func take(ore: float) -> float:
	var got := minf(amount, ore)
	amount -= got
	if amount <= 0.01 and active:
		active = false
		var spent := MeshKit.mat(Color(0.30, 0.28, 0.25), 0.95)
		for c in _crystals:
			c.material_override = spent
			c.scale = Vector3(0.6, 0.5, 0.6)
			c.position.y *= 0.5
	return got

# Gentle pulse so a field reads as active at a distance. Stops entirely once spent.
func _process(delta: float) -> void:
	if not active:
		return
	_bob_phase += delta * 1.3
	var pulse := 1.0 + sin(_bob_phase) * 0.035
	for c in _crystals:
		c.scale = Vector3(pulse, pulse, pulse)