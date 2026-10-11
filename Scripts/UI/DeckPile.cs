using Godot;

namespace ProjectClaude;

/// <summary>
/// Draw button drawn as a deck pile: a stack of card backs (height grows with the deck count),
/// the remaining card count and a mana gem with the draw cost. Glows green while a draw is possible,
/// the top card lifts on hover. Pressing emits BaseButton.Pressed.
/// </summary>
public partial class DeckPile : Button
{
	private static readonly Color BackColor = new Color(0.32f, 0.16f, 0.1f);
	private static readonly Color BackLight = new Color(0.55f, 0.3f, 0.16f);

	private int _count;
	private int _cost = 1;
	private float _time;
	private float _hover;
	private float _drawAnim;
	private int _shownCount;

	/// <summary>Cards left in the deck.</summary>
	public int Count => _count;

	public override void _Ready()
	{
		FocusMode = FocusModeEnum.None;
		Flat = true;
		Text = "";
		MouseDefaultCursorShape = CursorShape.PointingHand;
		UpdateTooltip();
	}

	/// <summary>Sets the deck count and the AP cost of a draw.</summary>
	public void SetDeck(int count, int cost)
	{
		if (count < _shownCount && IsInsideTree())
		{
			_drawAnim = 1f;
		}
		_count = Mathf.Max(0, count);
		_shownCount = _count;
		_cost = cost;
		UpdateTooltip();
		QueueRedraw();
	}

	private void UpdateTooltip()
	{
		TooltipText = $"Draw (D): pay {_cost} AP, choose 1 of the offered cards. {_count} cards left in your deck.";
	}

	public override void _Process(double delta)
	{
		float dt = (float)delta;
		_time += dt;
		_hover = Mathf.MoveToward(_hover, IsHovered() && !Disabled ? 1f : 0f, dt * 8f);
		_drawAnim = Mathf.Max(0f, _drawAnim - dt * 2f);
		QueueRedraw();
	}

	public override void _Draw()
	{
		var cardSize = new Vector2(Size.X * 0.62f, Size.Y * 0.7f);
		var origin = new Vector2((Size.X - cardSize.X) * 0.5f, Size.Y - cardSize.Y - 18f);
		int layers = _count <= 0 ? 0 : Mathf.Clamp(Mathf.CeilToInt(_count / 3f), 1, 6);
		bool live = !Disabled && _count > 0;
		float pulse = 0.5f + 0.5f * Mathf.Sin(_time * 3f);

		if (live)
		{
			var glowRect = new Rect2(origin - new Vector2(layers * 1.5f, layers * 2.5f), cardSize + new Vector2(layers * 3f, layers * 2.5f));
			for (int i = 3; i >= 1; i--)
			{
				DrawColoredPolygon(HudStyle.RoundRect(glowRect.Grow(i * 3f), 10f + i * 2f),
					new Color(HudStyle.ReadyGreen, (0.1f + 0.08f * pulse + 0.1f * _hover) * (4 - i) / 3f));
			}
		}

		if (layers == 0)
		{
			var empty = new Rect2(origin, cardSize);
			DrawColoredPolygon(HudStyle.RoundRect(empty, 8f), new Color(0f, 0f, 0f, 0.35f));
			DrawPolyline(HudStyle.Close(HudStyle.RoundRect(empty, 8f)), new Color(0.6f, 0.5f, 0.4f, 0.6f), 1.5f, true);
		}
		for (int i = 0; i < layers; i++)
		{
			bool top = i == layers - 1;
			float lift = top ? -6f * _hover : 0f;
			var offset = new Vector2(-i * 1.5f + (layers - 1) * 0.75f, -i * 2.5f + lift);
			DrawCardBack(new Rect2(origin + offset, cardSize), top, Disabled ? 0.7f : 1f);
		}

		// Card flying off the top on a draw.
		if (_drawAnim > 0f && layers > 0)
		{
			float t = 1f - _drawAnim;
			var offset = new Vector2(-60f * t, -layers * 2.5f - 40f * t);
			DrawSetTransform(origin + cardSize * 0.5f + offset, -0.5f * t, Vector2.One * (1f + 0.2f * t));
			Color m = new Color(1f, 1f, 1f, _drawAnim);
			DrawColoredPolygon(HudStyle.RoundRect(new Rect2(-cardSize * 0.5f, cardSize), 8f), new Color(BackLight, m.A));
			DrawSetTransform(Vector2.Zero, 0f, Vector2.One);
		}

		// Count badge.
		var badge = new Vector2(Size.X * 0.5f, Size.Y - 14f);
		var badgeRect = new Rect2(badge - new Vector2(26f, 11f), new Vector2(52f, 22f));
		DrawColoredPolygon(HudStyle.RoundRect(badgeRect, 10f), new Color(HudStyle.WoodDark, 0.95f));
		DrawPolyline(HudStyle.Close(HudStyle.RoundRect(badgeRect, 10f)), HudStyle.GoldDark, 1.5f, true);
		HudStyle.DrawTextCentered(this, _count.ToString(), badge, 15, HudStyle.TextLight, 3);

		// Cost gem (top-right).
		Vector2 gem = origin + new Vector2(cardSize.X - 2f, -layers * 2.5f + 4f);
		HudStyle.DrawCrystal(this, gem, 26f, 1f, live ? 0.25f * _hover : 0f, Disabled ? 0.7f : 1f);
		HudStyle.DrawTextCentered(this, _cost.ToString(), gem + new Vector2(0, 1f), 16, Colors.White, 4, new Color(0.02f, 0.05f, 0.16f));

		// Caption.
		HudStyle.DrawTextCentered(this, "DRAW", origin + new Vector2(cardSize.X * 0.5f, cardSize.Y * 0.5f - layers * 2.5f),
			16, live ? HudStyle.Gold : new Color(0.75f, 0.7f, 0.65f), 5);
	}

	private void DrawCardBack(Rect2 rect, bool top, float brightness)
	{
		Color back = BackColor * brightness;
		back.A = 1f;
		Vector2[] outer = HudStyle.RoundRect(rect, 8f);
		DrawColoredPolygon(outer, back);
		if (top)
		{
			Rect2 inner = rect.Grow(-5f);
			DrawColoredPolygon(HudStyle.RoundRect(inner, 5f), new Color(BackLight * brightness, 1f));
			Vector2 c = inner.GetCenter();
			// Ornament: gold diamond with a ring.
			HudStyle.StrokeEllipse(this, c, new Vector2(inner.Size.X * 0.32f, inner.Size.X * 0.32f), new Color(HudStyle.Gold, 0.8f), 2f, 28);
			Vector2[] diamond =
			{
				c + new Vector2(0, -inner.Size.Y * 0.28f), c + new Vector2(inner.Size.X * 0.18f, 0),
				c + new Vector2(0, inner.Size.Y * 0.28f), c + new Vector2(-inner.Size.X * 0.18f, 0),
			};
			DrawColoredPolygon(diamond, new Color(HudStyle.GoldDark, 0.85f));
			DrawPolyline(HudStyle.Close(diamond), HudStyle.Gold, 1.5f, true);
			DrawPolyline(HudStyle.Close(HudStyle.RoundRect(inner, 5f)), new Color(HudStyle.Gold, 0.7f), 1.2f, true);
		}
		DrawPolyline(HudStyle.Close(outer), new Color(0.12f, 0.06f, 0.03f), 1.5f, true);
		if (!top)
		{
			DrawLine(rect.Position + new Vector2(6f, 1f), new Vector2(rect.End.X - 6f, rect.Position.Y + 1f), new Color(0.7f, 0.5f, 0.3f, 0.6f), 1f);
		}
	}
}
