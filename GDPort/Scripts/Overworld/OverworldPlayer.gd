class_name OverworldPlayer
extends CharacterBody2D
## The player's avatar in the town: top-down movement (WASD / arrow keys) with collision and a walk bob.

@export var speed: float = 230.0
@export var robe_color: Color = Color(0.22, 0.42, 0.85)
@export var accent_color: Color = Color(1.0, 0.82, 0.35)

## False while dialogue / shop / deck builder are open.
var input_enabled: bool = true

var _bob: float = 0.0
var _facing: float = 1.0
var _step_timer: float = 0.0


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 11.0
	shape.shape = circle
	shape.position = Vector2(0, -6)
	add_child(shape)


func _physics_process(delta: float) -> void:
	var dir := Vector2.ZERO
	if input_enabled:
		if Input.is_action_pressed("ui_left") or Input.is_physical_key_pressed(KEY_A):
			dir.x -= 1
		if Input.is_action_pressed("ui_right") or Input.is_physical_key_pressed(KEY_D):
			dir.x += 1
		if Input.is_action_pressed("ui_up") or Input.is_physical_key_pressed(KEY_W):
			dir.y -= 1
		if Input.is_action_pressed("ui_down") or Input.is_physical_key_pressed(KEY_S):
			dir.y += 1
	velocity = dir.normalized() * speed if dir.length_squared() > 0 else Vector2.ZERO
	move_and_slide()
	if velocity.length_squared() > 1.0:
		_bob += delta * 12.0
		if absf(velocity.x) > 1.0:
			_facing = signf(velocity.x)
		_step_timer -= delta
		if _step_timer <= 0.0:
			_step_timer = 0.32
			Sfx.play(SfxId.STEP, -8.0, 1.2)
	else:
		_bob = move_toward(_bob, roundf(_bob / PI) * PI, delta * 10.0)
	queue_redraw()


func _draw() -> void:
	PersonSprite.draw(self, Vector2.ZERO, robe_color, accent_color, _bob, _facing)
	PersonSprite.draw_label(self, Vector2(0, -58), "You", 14, Color(0.75, 0.88, 1.0))
