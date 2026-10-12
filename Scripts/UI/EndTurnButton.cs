using Godot;

namespace Realmshatter;

/// <summary>
/// End Turn medallion: a brass ring with engraved hour marks around a glass hourglass, and a cloth ribbon with
/// the caption underneath. Your turn: warm amber face, the sand trickles slowly; nothing left to do: pulsing
/// green; enemy turn: dark crimson face and the hourglass flips and runs. Presses sink the medallion.
/// </summary>
public partial class EndTurnButton : Button
{
	private static readonly Color Brass = new Color(0.86f, 0.66f, 0.3f);
	private static readonly Color BrassDark = new Color(0.42f, 0.28f, 0.1f);
	private static readonly Color Glass = new Color(0.85f, 0.92f, 1f, 0.35f);
	private static readonly Color Sand = new Color(1f, 0.82f, 0.45f);

	private bool _playerTurn = true;
	private bool _nothingLeft;
	private float _time;
	private float _hover;
	private float _press;
	private float _flip;
	private float _sand = 0.7f;

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

	/// <summary>Sets whose turn it is (the hourglass flips).</summary>
	public void SetPlayerTurn(bool playerTurn)
	{
		if (_playerTurn == playerTurn)
		{
			return;
		}
		_playerTurn = playerTurn;
		_flip = 1f;
		_sand = 1f;
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
		_flip = Mathf.Max(0f, _flip - dt * 2.2f);
		_sand = Mathf.Max(0.05f, _sand - dt * (_playerTurn ? 0.01f : 0.12f));
		if (!_playerTurn && _sand <= 0.05f)
		{
			_sand = 1f;
			_flip = 1f;
		}
		float s = 1f + 0.035f * _hover - 0.05f * _press;
		Scale = new Vector2(s, s);
		QueueRedraw();
	}

	public override void _Draw()
	{
		float ribbonH = 30f;
		Vector2 c = new Vector2(Size.X * 0.5f, (Size.Y - ribbonH * 0.6f) * 0.5f);
		float r = Mathf.Min(Size.X * 0.5f - 6f, (Size.Y - ribbonH * 0.6f) * 0.5f - 6f);
		bool active = _playerTurn && !Disabled;
		float pulse = 0.5f + 0.5f * Mathf.Sin(_time * (_nothingLeft ? 4.5f : 2.2f));

		Color face;
		if (!_playerTurn)
		{
			face = new Color(0.36f, 0.08f, 0.07f);
		}
		else if (Disabled)
		{
			face = new Color(0.3f, 0.27f, 0.22f);
		}
		else if (_nothingLeft)
		{
			face = new Color(0.16f, 0.45f, 0.14f).Lerp(new Color(0.3f, 0.7f, 0.22f), pulse);
		}
		else
		{
			face = new Color(0.5f, 0.3f, 0.08f).Lerp(new Color(0.62f, 0.4f, 0.1f), _hover);
		}

		// Glow halo.
		if (active)
		{
			Color glow = _nothingLeft ? HudStyle.ReadyGreen : new Color(1f, 0.78f, 0.3f);
			float strength = Mathf.Max(_nothingLeft ? 0.5f + 0.5f * pulse : 0.25f + 0.15f * pulse, _hover * 0.7f);
			for (int i = 5; i >= 1; i--)
			{
				DrawCircle(c, r + i * 3f, new Color(glow, 0.08f * strength * (6 - i)));
			}
		}

		// Brass ring with bevel and hour marks.
		DrawCircle(c + new Vector2(0, 4f), r + 2f, new Color(0, 0, 0, 0.45f));
		DrawCircle(c, r + 1f, BrassDark);
		DrawCircle(c, r - 1f, Brass.Lerp(Colors.White, 0.12f * _hover));
		DrawArc(c, r - 3f, Mathf.Pi * 1.1f, Mathf.Pi * 1.9f, 24, new Color(1f, 0.95f, 0.75f, 0.6f), 2f, true);
		DrawCircle(c, r - 9f, BrassDark);
		for (int i = 0; i < 12; i++)
		{
			float a = Mathf.Tau * i / 12f;
			Vector2 dir = new Vector2(Mathf.Cos(a), Mathf.Sin(a));
			DrawLine(c + dir * (r - 7.5f), c + dir * (r - 3.5f), BrassDark, i % 3 == 0 ? 2.5f : 1.5f, true);
		}
		// Face.
		float fr = r - 11f;
		DrawCircle(c, fr, face.Darkened(0.3f));
		DrawCircle(c + new Vector2(0, -fr * 0.06f), fr * 0.94f, face);
		DrawCircle(c + new Vector2(-fr * 0.25f, -fr * 0.35f), fr * 0.45f, new Color(1f, 1f, 1f, 0.07f));

		DrawHourglass(c, fr * 0.62f);

		// Ribbon with caption.
		string caption = !_playerTurn ? "ENEMY TURN" : "END TURN";
		float rw = Size.X - 4f;
		var ribbon = new Rect2(new Vector2(2f, Size.Y - ribbonH - 2f), new Vector2(rw, ribbonH));
		Color cloth = !_playerTurn ? new Color(0.45f, 0.1f, 0.08f) : (_nothingLeft ? new Color(0.18f, 0.45f, 0.14f) : new Color(0.55f, 0.16f, 0.1f));
		Vector2[] tail =
		{
			ribbon.Position + new Vector2(-2f, 6f), ribbon.Position + new Vector2(14f, 6f), ribbon.Position + new Vector2(14f, ribbonH + 4f),
			ribbon.Position + new Vector2(-2f, ribbonH + 4f), ribbon.Position + new Vector2(5f, ribbonH * 0.5f + 5f),
		};
		DrawColoredPolygon(tail, cloth.Darkened(0.35f));
		Vector2[] tail2 = new Vector2[tail.Length];
		for (int i = 0; i < tail.Length; i++)
		{
			tail2[i] = new Vector2(Size.X - tail[i].X, tail[i].Y);
		}
		DrawColoredPolygon(tail2, cloth.Darkened(0.35f));
		var band = new Rect2(ribbon.Position + new Vector2(8f, 0f), new Vector2(rw - 16f, ribbonH));
		DrawRect(band, cloth);
		DrawRect(new Rect2(band.Position, new Vector2(band.Size.X, 3f)), cloth.Lightened(0.25f));
		DrawRect(new Rect2(band.Position + new Vector2(0, band.Size.Y - 3f), new Vector2(band.Size.X, 3f)), cloth.Darkened(0.3f));
		DrawRect(band, BrassDark, false, 1.5f);
		int size = 16;
		float fit = (band.Size.X - 12f) / Mathf.Max(1f, HudStyle.TextWidth(caption, size));
		if (fit < 1f)
		{
			size = Mathf.Max(10, Mathf.FloorToInt(size * fit));
		}
		HudStyle.DrawTextCentered(this, caption, band.GetCenter() + new Vector2(0, 1f), size, Disabled && _playerTurn ? new Color(0.8f, 0.76f, 0.7f) : Colors.White, 5,
			new Color(0.12f, 0.04f, 0.02f));
	}

	private void DrawHourglass(Vector2 c, float h)
	{
		float angle = Mathf.Pi * Mathf.SmoothStep(0f, 1f, 1f - _flip);
		DrawSetTransform(c, _flip > 0f ? angle : 0f, Vector2.One);
		float w = h * 0.62f;
		Color frame = new Color(0.32f, 0.2f, 0.08f);
		// Glass bulbs.
		Vector2[] glass =
		{
			new Vector2(-w, -h * 0.85f), new Vector2(w, -h * 0.85f), new Vector2(w * 0.18f, -h * 0.05f), new Vector2(w * 0.18f, h * 0.05f),
			new Vector2(w, h * 0.85f), new Vector2(-w, h * 0.85f), new Vector2(-w * 0.18f, h * 0.05f), new Vector2(-w * 0.18f, -h * 0.05f),
		};
		DrawColoredPolygon(glass, Glass);
		// Sand: top bulb holds _sand, bottom the rest.
		float top = Mathf.Clamp(_sand, 0f, 1f);
		if (top > 0.02f)
		{
			float ty = -h * 0.05f - h * 0.8f * top;
			float tw = Mathf.Lerp(w * 0.18f, w, top);
			DrawColoredPolygon(new[] { new Vector2(-tw, ty), new Vector2(tw, ty), new Vector2(w * 0.12f, -h * 0.06f), new Vector2(-w * 0.12f, -h * 0.06f) }, Sand);
		}
		float bottom = 1f - top;
		float by = h * 0.85f - h * 0.7f * bottom;
		DrawColoredPolygon(new[] { new Vector2(-w * 0.9f, h * 0.84f), new Vector2(w * 0.9f, h * 0.84f), new Vector2(0f, by) }, Sand.Darkened(0.1f));
		if (top > 0.02f)
		{
			DrawLine(new Vector2(0, -h * 0.05f), new Vector2(0, by), Sand, 1.5f);
		}
		DrawPolyline(new[] { glass[0], glass[1], glass[2], glass[3], glass[4], glass[5], glass[6], glass[7], glass[0] }, new Color(1f, 1f, 1f, 0.55f), 1.5f, true);
		// Wooden caps and posts.
		DrawRect(new Rect2(-w - 4f, -h - 4f, (w + 4f) * 2f, 7f), frame);
		DrawRect(new Rect2(-w - 4f, h - 3f, (w + 4f) * 2f, 7f), frame);
		DrawLine(new Vector2(-w - 2f, -h), new Vector2(-w - 2f, h), frame, 2.5f);
		DrawLine(new Vector2(w + 2f, -h), new Vector2(w + 2f, h), frame, 2.5f);
		DrawSetTransform(Vector2.Zero, 0f, Vector2.One);
	}
}
