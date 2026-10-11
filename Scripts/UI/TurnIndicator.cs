using Godot;

namespace Realmshatter;

/// <summary>
/// Top-bar turn plaque: "TURN n" with a phase line, flanked by the two players' shields (YOU / AI).
/// The active player's shield glows; a chevron points toward the player who goes next.
/// </summary>
public partial class TurnIndicator : Control
{
	private int _turn = 1;
	private int _current;
	private string _phase = "";
	private float _time;
	private float _switch;

	public override void _Ready()
	{
		MouseFilter = MouseFilterEnum.Ignore;
	}

	/// <summary>Updates turn number, current player and the small phase caption.</summary>
	public void SetTurn(int turnNumber, int currentPlayer, string phase)
	{
		if (currentPlayer != _current)
		{
			_switch = 1f;
		}
		_turn = turnNumber;
		_current = currentPlayer;
		_phase = phase ?? "";
		QueueRedraw();
	}

	public override void _Process(double delta)
	{
		_time += (float)delta;
		_switch = Mathf.Max(0f, _switch - (float)delta * 2f);
		QueueRedraw();
	}

	public override void _Draw()
	{
		Vector2 c = Size * 0.5f;
		float plaqueW = Mathf.Min(Size.X - 120f, 200f);
		var plaque = new Rect2(c.X - plaqueW * 0.5f, 2f, plaqueW, Size.Y - 4f);

		// Plaque with banner tails.
		Vector2[] shape =
		{
			plaque.Position + new Vector2(14f, 0f), new Vector2(plaque.End.X - 14f, plaque.Position.Y),
			new Vector2(plaque.End.X, c.Y), new Vector2(plaque.End.X - 14f, plaque.End.Y),
			new Vector2(plaque.Position.X + 14f, plaque.End.Y), new Vector2(plaque.Position.X, c.Y),
		};
		DrawColoredPolygon(shape, new Color(HudStyle.WoodDark, 0.96f));
		DrawPolyline(HudStyle.Close(shape), HudStyle.GoldDark, 2f, true);
		Vector2[] inner = new Vector2[shape.Length];
		for (int i = 0; i < shape.Length; i++)
		{
			inner[i] = c + (shape[i] - c) * new Vector2(0.95f, 0.78f);
		}
		DrawPolyline(HudStyle.Close(inner), new Color(HudStyle.Gold, 0.35f), 1f, true);

		HudStyle.DrawTextCentered(this, $"TURN {_turn}", new Vector2(c.X, c.Y - (string.IsNullOrEmpty(_phase) ? 0f : 6f)), 19, HudStyle.Gold, 5);
		if (!string.IsNullOrEmpty(_phase))
		{
			HudStyle.DrawTextCentered(this, _phase, new Vector2(c.X, c.Y + 11f), 11, new Color(HudStyle.TextLight, 0.85f), 3);
		}

		DrawShield(new Vector2(plaque.Position.X - 26f, c.Y), 0, "YOU");
		DrawShield(new Vector2(plaque.End.X + 26f, c.Y), 1, "AI");

		// Chevron from the active player toward the next one.
		float dir = _current == 0 ? 1f : -1f;
		float slide = 3f * Mathf.Sin(_time * 4f);
		float side = _current == 0 ? plaque.Position.X + 22f : plaque.End.X - 22f;
		Color chevron = new Color(HudStyle.Accent(_current), 0.85f);
		for (int k = 0; k < 2; k++)
		{
			float x = side + dir * (k * 7f + slide);
			DrawPolyline(new[] { new Vector2(x - dir * 4f, c.Y - 6f), new Vector2(x + dir * 2f, c.Y), new Vector2(x - dir * 4f, c.Y + 6f) },
				chevron, 2.2f, true);
		}
	}

	private void DrawShield(Vector2 center, int player, string text)
	{
		bool active = player == _current;
		Color accent = HudStyle.Accent(player);
		float s = active ? 1f + 0.15f * _switch : 0.85f;
		float w = 16f * s;
		float h = 17f * s;
		Vector2[] shield =
		{
			center + new Vector2(-w, -h * 0.8f), center + new Vector2(w, -h * 0.8f), center + new Vector2(w, h * 0.1f),
			center + new Vector2(0, h), center + new Vector2(-w, h * 0.1f),
		};
		if (active)
		{
			float pulse = 0.5f + 0.5f * Mathf.Sin(_time * 3f);
			HudStyle.FillEllipse(this, center, new Vector2(w * 1.6f, h * 1.3f), new Color(accent, 0.18f + 0.14f * pulse), 24);
		}
		DrawColoredPolygon(shield, active ? accent.Darkened(0.35f) : new Color(0.22f, 0.2f, 0.19f, 0.9f));
		Vector2[] inner = new Vector2[shield.Length];
		for (int i = 0; i < shield.Length; i++)
		{
			inner[i] = center + (shield[i] - center) * 0.72f;
		}
		DrawColoredPolygon(inner, active ? accent : new Color(0.35f, 0.33f, 0.31f, 0.9f));
		DrawPolyline(HudStyle.Close(shield), active ? HudStyle.Gold : HudStyle.GoldDark, 2f, true);
		HudStyle.DrawTextCentered(this, text, center + new Vector2(0, -2f), active ? 10 : 9, Colors.White, 3);
	}
}
