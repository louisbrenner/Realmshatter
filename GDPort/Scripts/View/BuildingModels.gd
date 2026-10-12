class_name BuildingModels
extends RefCounted
## Small procedural 3D models of the buildings (sit on the piece token) and the construction scaffold.

const STONE := Color(0.62, 0.59, 0.54)
const STONE_DARK := Color(0.42, 0.4, 0.37)
const WOOD := Color(0.48, 0.31, 0.17)


## Model of a building type; tint = building colour, owner = owner colour (banner / band).
static func create(type: int, tint: Color, owner: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "Building"
	match type:
		BuildingType.TURRET:
			_add(root, _cyl(0.2, 0.26, 0.5, 16), _mat(STONE), Vector3(0, 0.25, 0))
			_add(root, _cyl(0.27, 0.27, 0.06, 16), _mat(owner, 0.6), Vector3(0, 0.3, 0))
			_add(root, _cyl(0.25, 0.23, 0.1, 16), _mat(STONE_DARK), Vector3(0, 0.55, 0))
			for i in range(6):
				var a: float = TAU * i / 6.0
				_add(root, _box(Vector3(0.08, 0.09, 0.08)), _mat(STONE), Vector3(cos(a) * 0.2, 0.64, sin(a) * 0.2))
			_add(root, _box(Vector3(0.05, 0.14, 0.2)), _mat(Color(0.1, 0.08, 0.06)), Vector3(0.21, 0.4, 0), 0.6)
		BuildingType.MANA_WELL:
			_add(root, _cyl(0.27, 0.3, 0.18, 20), _mat(STONE), Vector3(0, 0.09, 0))
			_add(root, _cyl(0.21, 0.21, 0.02, 20), _glow(Color(0.3, 0.65, 1.0), 1.6), Vector3(0, 0.18, 0))
			_add(root, _prism(Vector3(0.14, 0.32, 0.14)), _glow(Color(0.45, 0.75, 1.0), 2.4), Vector3(0, 0.36, 0))
			_add(root, _prism(Vector3(0.14, 0.2, 0.14)), _glow(Color(0.45, 0.75, 1.0), 2.4), Vector3(0, 0.12, 0), PI)
		BuildingType.SHRINE:
			_add(root, _box(Vector3(0.44, 0.08, 0.44)), _mat(STONE), Vector3(0, 0.04, 0))
			_add(root, _cyl(0.08, 0.1, 0.42, 12), _mat(Color(0.9, 0.86, 0.75)), Vector3(0, 0.29, 0))
			var sphere := SphereMesh.new()
			sphere.radius = 0.1
			sphere.height = 0.2
			_add(root, sphere, _glow(Color(1.0, 0.85, 0.4), 2.6), Vector3(0, 0.6, 0))
		BuildingType.BARRICADE:
			for i in range(-1, 2):
				_add(root, _cyl(0.06, 0.06, 0.6, 8), _mat(WOOD),
					Vector3(i * 0.15, 0.18, 0), 0.0, Vector3(0.9, 0, 0))
				_add(root, _cyl(0.0, 0.05, 0.16, 8), _mat(Color(0.75, 0.7, 0.62)),
					Vector3(i * 0.15, 0.42, -0.2), 0.0, Vector3(0.9, 0, 0))
			_add(root, _box(Vector3(0.5, 0.08, 0.08)), _mat(owner, 0.4), Vector3(0, 0.12, 0.05))
		BuildingType.OBELISK:
			_add(root, _box(Vector3(0.34, 0.08, 0.34)), _mat(STONE_DARK), Vector3(0, 0.04, 0))
			_add(root, _cyl(0.05, 0.14, 0.8, 4), _mat(Color(0.25, 0.2, 0.32)), Vector3(0, 0.48, 0), PI / 4.0)
			_add(root, _cyl(0.012, 0.035, 0.7, 4), _glow(tint, 2.2), Vector3(0, 0.5, 0.07), PI / 4.0)
	return root


## Wooden scaffold shown while a building is under construction.
static func create_scaffold() -> Node3D:
	var root := Node3D.new()
	root.name = "Scaffold"
	var pole := _cyl(0.018, 0.018, 0.55, 6)
	var bar := _box(Vector3(0.6, 0.025, 0.025))
	var wood: StandardMaterial3D = _mat(Color(0.62, 0.45, 0.26))
	for c: Vector2 in [Vector2(-0.28, -0.28), Vector2(0.28, -0.28), Vector2(-0.28, 0.28), Vector2(0.28, 0.28)]:
		_add(root, pole, wood, Vector3(c.x, 0.27, c.y))
	for y: float in [0.2, 0.45]:
		_add(root, bar, wood, Vector3(0, y, -0.28))
		_add(root, bar, wood, Vector3(0, y, 0.28))
		_add(root, bar, wood, Vector3(-0.28, y, 0), PI / 2.0)
		_add(root, bar, wood, Vector3(0.28, y, 0), PI / 2.0)
	return root


static func _add(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, yaw: float = 0.0, rotation: Variant = null) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rotation if rotation != null else Vector3(0, yaw, 0)
	parent.add_child(mi)


static func _cyl(top_radius: float, bottom_radius: float, height: float, radial_segments: int) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top_radius
	m.bottom_radius = bottom_radius
	m.height = height
	m.radial_segments = radial_segments
	return m


static func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func _prism(size: Vector3) -> PrismMesh:
	var m := PrismMesh.new()
	m.size = size
	return m


static func _mat(color: Color, emission: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	m.emission_enabled = emission > 0.0
	m.emission = color
	m.emission_energy_multiplier = emission
	return m


static func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.2
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m
