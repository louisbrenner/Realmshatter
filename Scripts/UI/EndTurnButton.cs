using Godot;

namespace Realmshatter;

/// <summary>
/// Big oval stone End Turn button (Hearthstone style). Yellow glowing "END TURN" while it is your
/// turn, pulsing green when you have nothing left to do, grey "ENEMY TURN" while the AI acts.
/// </summary>
public partial class EndTurnButton : Button
{
	private static readonly Color YellowGlow = new Color(1f, 0.82f, 0.25f);

	private bool _playerTurn = true;
	private bool _nothingLeft;
	private float _time;
	private float _hover;
	private float _press;
	private float _flip;
	private string _caption = "END TURN";

	/// <summary>True while it is the human player's turn.</summary>
	public bool IsPlayerTurn => _playerTurn;

	public override void _Ready()
	{
		FocusMode = FocusModeEnum.None;
		Flat = true;
		Text = "";
		MouseDefaultCursorShape = CursorShape.PointingHand;
		PivotOffset = Size * 0.5f;
		Resized += () => PivotOffset = Size * 0.5f;
	}

	/// <summary>Sets whose turn it is (flips the caption with a short animation).</summary>
	public void SetPlayerTurn(bool playerTurn)
	{
		if (_playerTurn == playerTurn)
		{
			return;
		}
		_playerTurn = playerTurn;
		_flip = 1f;
		QueueRedraw();
	}

	/// <summary>Green "you're done" glow (e.g. no AP left).</summary>
	public void SetNothingLeft(bool nothingLeft)
	{
		_nothingLeft = nothingLeft;
		QueueRedraw();
	}

	public override void _Process(double delta)
	{
		float dt = (float)delta;
		_time += dt;
		bool hovered = IsHovered() && !Disabled;
		_hover = Mathf.MoveToward(_hover, hovered ? 1f : 0f, dt * 8f);
		_press = Mathf.MoveToward(_press, ButtonPressed || (hovered && Input.IsMouseButtonPressed(MouseButton.Left)) ? 1f : 0f, dt * 14f);
		_flip = Mathf.Max(0f, _flip - dt * 3f);
		float s = (1f + 0.04f * _hover - 0.05f * _press) * (1f - 0.12f * Mathf.Sin(_flip * Mathf.Pi));
		Scale = new Vector2(s, s);
		QueueRedraw();
	}

	public override void _Draw()
	{
		Vector2 c = Size * 0.5f;
		var r = new Vector2(Size.X * 0.5f - 8f, Size.Y * 0.5f - 7f);
		bool active = _playerTurn && !Disabled;
		float pulse = 0.5f + 0.5f * Mathf.Sin(_time * (_nothingLeft ? 4.5f : 2.5f));

		if (active)
		{
			Color glow = _nothingLeft ? HudStyle.ReadyGreen : YellowGlow;
			float strength = _nothingLeft ? 0.55f + 0.45f * pulse : 0.35f + 0.2f * pulse;
			strength = Mathf.Max(strength, _hover * 0.8f);
			for (int i = 4; i >= 1; i--)
			{
				HudStyle.FillEllipse(this, c, r + Vector2.One * (i * 2.2f + 1f), new Color(glow, 0.12f * strength * (5 - i)), 40);
			}
		}

		// Stone rim with bevel.
		HudStyle.FillEllipse(this, c + new Vector2(0, 3f), r + new Vector2(2f, 2f), new Color(0f, 0f, 0f, 0.5f), 40);
		HudStyle.FillEllipse(this, c, r + new Vector2(1f, 1f), new Color(0.2f, 0.17f, 0.15f), 40);
		HudStyle.FillEllipse(this, c, r, new Color(0.55f, 0.52f, 0.48f), 40);
		HudStyle.FillEllipse(this, c + new Vector2(0, 1.5f), r - new Vector2(5f, 5f), new Color(0.3f, 0.28f, 0.26f), 40);

		// Face.
		Color face;
		Color faceLight;
		if (!_playerTurn)
		{
			face = new Color(0.36f, 0.35f, 0.34f);
			faceLight = new Color(0.5f, 0.49f, 0.47f);
		}
		else if (Disabled)
		{
			face = new Color(0.45f, 0.4f, 0.3f);
			faceLight = new Color(0.58f, 0.53f, 0.42f);
		}
		else if (_nothingLeft)
		{
			face = new Color(0.25f, 0.62f, 0.2f);
			faceLight = new Color(0.55f, 0.9f, 0.4f);
		}
		else
		{
			face = new Color(0.85f, 0.62f, 0.12f);
			faceLight = new Color(1f, 0.86f, 0.4f);
		}
		face = face.Lerp(faceLight, _hover * 0.35f);
		Vector2 fr = r - new Vector2(7f, 7f);
		HudStyle.FillEllipse(this, c, fr, face.Darkened(0.25f), 40);
		HudStyle.FillEllipse(this, c + new Vector2(0, -fr.Y * 0.18f), fr * new Vector2(0.92f, 0.72f), face, 40);
		HudStyle.FillEllipse(this, c + new Vector2(0, -fr.Y * 0.42f), fr * new Vector2(0.7f, 0.3f), new Color(faceLight, 0.6f), 32);
		HudStyle.StrokeEllipse(this, c, fr, new Color(0.15f, 0.1f, 0.05f, 0.9f), 2f, 40);

		// Rim rivets.
		for (int i = 0; i < 10; i++)
		{
			float a = Mathf.Tau * i / 10f + 0.3f;
			Vector2 p = c + new Vector2(Mathf.Cos(a) * (r.X - 3f), Mathf.Sin(a) * (r.Y - 3f));
			DrawCircle(p, 1.8f, new Color(0.75f, 0.7f, 0.62f));
		}

		string caption = !_playerTurn ? "ENEMY TURN" : "END TURN";
		Color text = !_playerTurn ? new Color(0.82f, 0.8f, 0.78f) : (Disabled ? new Color(0.9f, 0.86f, 0.76f) : Colors.White);
		int size = Mathf.RoundToInt(Mathf.Clamp(Size.Y * 0.3f, 12f, 30f));
		float fit = (fr.X * 1.7f) / Mathf.Max(1f, HudStyle.TextWidth(caption, size));
		if (fit < 1f)
		{
			size = Mathf.Max(10, Mathf.FloorToInt(size * fit));
		}
		_caption = caption;
		HudStyle.DrawTextCentered(this, _caption, c + new Vector2(0, 1f), size, text, 6, new Color(0.12f, 0.07f, 0.02f));
	}
}
