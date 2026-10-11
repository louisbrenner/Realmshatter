using Godot;

namespace ProjectClaude;

/// <summary>
/// Coin-to-crystal conversion slots next to the mana bar: one slot per allowed conversion this turn.
/// Available slots show a gold coin with an arrow into a crystal and glow while a conversion is
/// possible; used slots are greyed with a check mark. Pressing emits BaseButton.Pressed.
/// </summary>
public partial class VpConvertButton : Button
{
	[Export] public float SlotSize { get; set; } = 34f;
	[Export] public float Gap { get; set; } = 4f;

	private int _used;
	private int _max = 2;
	private bool _canConvert;
	private float _time;
	private float _pressFlash;

	/// <summary>Conversions already used this turn.</summary>
	public int Used => _used;

	/// <summary>Maximum conversions per turn.</summary>
	public int MaxPerTurn => _max;

	public override void _Ready()
	{
		FocusMode = FocusModeEnum.None;
		Flat = true;
		Text = "";
		MouseDefaultCursorShape = CursorShape.PointingHand;
		TooltipText = "Spend 1 VP for 1 AP (max 2 per turn)";
		MouseEntered += QueueRedraw;
		MouseExited += QueueRedraw;
		ButtonDown += () => _pressFlash = 1f;
	}

	/// <summary>Updates the slots. canConvert enables the button.</summary>
	public void SetState(int used, int maxPerTurn, bool canConvert)
	{
		int old = _used;
		_max = Mathf.Max(0, maxPerTurn);
		_used = Mathf.Clamp(used, 0, _max);
		_canConvert = canConvert && _used < _max;
		Disabled = !_canConvert;
		TooltipText = $"Spend 1 VP for 1 AP (max {_max} per turn) - {_max - _used} left this turn";
		if (_used > old)
		{
			_pressFlash = 1f;
		}
		Visible = _max > 0;
		CustomMinimumSize = ComputeSize();
		QueueRedraw();
	}

	private Vector2 ComputeSize()
	{
		int n = Mathf.Max(1, _max);
		return new Vector2(n * SlotSize + (n - 1) * Gap, SlotSize + 12f);
	}

	public override void _Process(double delta)
	{
		_time += (float)delta;
		_pressFlash = Mathf.Max(0f, _pressFlash - (float)delta * 2.5f);
		if (_canConvert || _pressFlash > 0f)
		{
			QueueRedraw();
		}
	}

	public override void _Draw()
	{
		bool hover = IsHovered() && !Disabled;
		float pulse = 0.5f + 0.5f * Mathf.Sin(_time * 3.5f);
		for (int i = 0; i < _max; i++)
		{
			float x = i * (SlotSize + Gap);
			var rect = new Rect2(x, 0f, SlotSize, SlotSize);
			bool used = i < _used;
			bool next = i == _used;
			bool live = !used && _canConvert;
			Color bg = used ? new Color(0.12f, 0.1f, 0.09f, 0.85f) : new Color(0.16f, 0.1f, 0.05f, 0.92f);
			Color border = used ? new Color(0.35f, 0.3f, 0.26f) : (live ? HudStyle.Gold : HudStyle.GoldDark);
			if (live && next)
			{
				float glow = hover ? 1f : 0.45f + 0.35f * pulse;
				DrawColoredPolygon(HudStyle.RoundRect(rect.Grow(3f), 9f), new Color(1f, 0.85f, 0.35f, 0.35f * glow));
			}
			DrawColoredPolygon(HudStyle.RoundRect(rect, 7f), bg);
			DrawPolyline(HudStyle.Close(HudStyle.RoundRect(rect, 7f)), border, 1.6f, true);

			float a = used ? 0.35f : (live ? 1f : 0.5f);
			Vector2 coinPos = rect.Position + new Vector2(SlotSize * 0.3f, SlotSize * 0.42f);
			HudStyle.DrawCoin(this, coinPos, SlotSize * 0.2f, 3f, a, live && next ? _pressFlash : 0f);
			Vector2 crystalPos = rect.Position + new Vector2(SlotSize * 0.74f, SlotSize * 0.5f);
			HudStyle.DrawCrystal(this, crystalPos, SlotSize * 0.42f, used ? 0f : 1f, live && hover ? 0.5f : 0f, a);
			// Arrow coin -> crystal.
			Vector2 from = rect.Position + new Vector2(SlotSize * 0.42f, SlotSize * 0.78f);
			Vector2 to = rect.Position + new Vector2(SlotSize * 0.62f, SlotSize * 0.78f);
			Color arrow = new Color(1f, 0.92f, 0.7f, a);
			DrawLine(from, to, arrow, 1.6f, true);
			DrawLine(to, to + new Vector2(-4f, -3f), arrow, 1.6f, true);
			DrawLine(to, to + new Vector2(-4f, 3f), arrow, 1.6f, true);
			if (used)
			{
				Vector2 c = rect.GetCenter();
				DrawPolyline(new[] { c + new Vector2(-7f, 0f), c + new Vector2(-2f, 6f), c + new Vector2(8f, -7f) },
					new Color(0.45f, 1f, 0.45f, 0.95f), 3f, true);
			}
		}
		HudStyle.DrawTextCentered(this, "VP > AP", new Vector2(Size.X * 0.5f, SlotSize + 6f), 10,
			_canConvert ? HudStyle.Gold : new Color(0.65f, 0.6f, 0.55f), 3);
	}
}
