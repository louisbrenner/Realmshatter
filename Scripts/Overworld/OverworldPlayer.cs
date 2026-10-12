using Godot;

namespace Realmshatter;

/// <summary>The player's avatar in the town: top-down movement (WASD / arrow keys) with collision and a walk bob.</summary>
public partial class OverworldPlayer : CharacterBody2D
{
	[Export] public float Speed { get; set; } = 230f;
	[Export] public Color RobeColor { get; set; } = new Color(0.22f, 0.42f, 0.85f);
	[Export] public Color AccentColor { get; set; } = new Color(1f, 0.82f, 0.35f);

	/// <summary>False while dialogue / shop / deck builder are open.</summary>
	public bool InputEnabled { get; set; } = true;

	private float _bob;
	private float _facing = 1f;
	private float _stepTimer;

	public override void _Ready()
	{
		MotionMode = MotionModeEnum.Floating;
		AddChild(new CollisionShape2D { Shape = new CircleShape2D { Radius = 11f }, Position = new Vector2(0, -6) });
	}

	public override void _PhysicsProcess(double delta)
	{
		Vector2 dir = Vector2.Zero;
		if (InputEnabled)
		{
			if (Input.IsActionPressed("ui_left") || Input.IsPhysicalKeyPressed(Key.A)) dir.X -= 1;
			if (Input.IsActionPressed("ui_right") || Input.IsPhysicalKeyPressed(Key.D)) dir.X += 1;
			if (Input.IsActionPressed("ui_up") || Input.IsPhysicalKeyPressed(Key.W)) dir.Y -= 1;
			if (Input.IsActionPressed("ui_down") || Input.IsPhysicalKeyPressed(Key.S)) dir.Y += 1;
		}
		Velocity = dir.LengthSquared() > 0 ? dir.Normalized() * Speed : Vector2.Zero;
		MoveAndSlide();
		if (Velocity.LengthSquared() > 1f)
		{
			_bob += (float)delta * 12f;
			if (Mathf.Abs(Velocity.X) > 1f)
			{
				_facing = Mathf.Sign(Velocity.X);
			}
			_stepTimer -= (float)delta;
			if (_stepTimer <= 0f)
			{
				_stepTimer = 0.32f;
				Sfx.Play(SfxId.Step, -8f, 1.2f);
			}
		}
		else
		{
			_bob = Mathf.MoveToward(_bob, Mathf.Round(_bob / Mathf.Pi) * Mathf.Pi, (float)delta * 10f);
		}
		QueueRedraw();
	}

	public override void _Draw()
	{
		PersonSprite.Draw(this, Vector2.Zero, RobeColor, AccentColor, _bob, _facing);
		PersonSprite.DrawLabel(this, new Vector2(0, -58), "You", 14, new Color(0.75f, 0.88f, 1f));
	}
}
