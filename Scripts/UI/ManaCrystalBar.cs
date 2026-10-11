using System.Collections.Generic;
using Godot;

namespace Realmshatter;

/// <summary>
/// Hearthstone-style row of mana crystals for action points: "current/max" text followed by
/// filled (glowing blue) and empty (dark socket) crystals. Filling pops a crystal in with a flash,
/// spending drains it with a burst.
/// </summary>
public partial class ManaCrystalBar : Control
{
	[Export] public float CrystalSize { get; set; } = 24f;
	[Export] public float Gap { get; set; } = 4f;
	[Export] public int FontSize { get; set; } = 22;
	[Export] public bool ShowText { get; set; } = true;
	/// <summary>Minimum number of crystal slots drawn (e.g. the base AP per turn).</summary>
	[Export] public int MinSlots { get; set; } = 3;

	private float TextWidth => FontSize * 2.7f;
	private int _current;
	private int _max;
	private readonly List<float> _fill = new List<float>();
	private readonly List<float> _flash = new List<float>();
	private readonly List<float> _burst = new List<float>();
	private float _time;
	private float _textPulse;

	/// <summary>Current action points.</summary>
	public int Current => _current;

	/// <summary>Maximum action points this turn (number of slots).</summary>
	public int Max => _max;

	public override void _Ready()
	{
		MouseFilter = MouseFilterEnum.Ignore;
	}

	/// <summary>Sets current and maximum AP; animates the difference unless animate is false.</summary>
	public void SetValues(int current, int max, bool animate = true)
	{
		current = Mathf.Max(0, current);
		max = Mathf.Max(current, max);
		bool changed = current != _current || max != _max;
		_current = current;
		_max = max;
		int slots = SlotCount;
		while (_fill.Count < slots)
		{
			_fill.Add(0f);
			_flash.Add(0f);
			_burst.Add(0f);
		}
		if (!animate || !IsInsideTree())
		{
			for (int i = 0; i < _fill.Count; i++)
			{
				_fill[i] = i < current ? 1f : 0f;
			}
		}
		else if (changed)
		{
			_textPulse = 1f;
		}
		UpdateMinimumSize();
		QueueRedraw();
	}

	private int SlotCount => Mathf.Max(Mathf.Max(_max, _current), MinSlots);

	public override Vector2 _GetMinimumSize()
	{
		int slots = SlotCount;
		float w = (ShowText ? TextWidth : 0f) + slots * CrystalSize + (slots - 1) * Gap + 6f;
		return new Vector2(w, CrystalSize * 1.4f);
	}

	public override void _Process(double delta)
	{
		float dt = (float)delta;
		_time += dt;
		bool busy = _textPulse > 0f;
		_textPulse = Mathf.Max(0f, _textPulse - dt * 2.5f);
		for (int i = 0; i < _fill.Count; i++)
		{
			float target = i < _current ? 1f : 0f;
			if (!Mathf.IsEqualApprox(_fill[i], target))
			{
				// Staggered: crystals further right react slightly later.
				float speed = target > _fill[i] ? 4f : 5f;
				float before = _fill[i];
				_fill[i] = Mathf.MoveToward(_fill[i], target, dt * speed);
				if (target > before && _fill[i] >= 1f)
				{
					_flash[i] = 1f;
				}
				if (target < before && before >= 0.999f)
				{
					_burst[i] = 1f;
				}
				busy = true;
			}
			if (_flash[i] > 0f || _burst[i] > 0f)
			{
				_flash[i] = Mathf.Max(0f, _flash[i] - dt * 3f);
				_burst[i] = Mathf.Max(0f, _burst[i] - dt * 2.5f);
				busy = true;
			}
		}
		if (busy || _current > 0)
		{
			QueueRedraw();
		}
	}

	public override void _Draw()
	{
		float x = 2f;
		float cy = Size.Y * 0.5f;
		if (ShowText)
		{
			float scale = 1f + 0.25f * _textPulse;
			HudStyle.DrawTextCentered(this, $"{_current}/{_max}", new Vector2(x + TextWidth * 0.5f, cy),
				Mathf.RoundToInt(FontSize * scale), new Color(0.85f, 0.95f, 1f), 5, new Color(0.02f, 0.05f, 0.16f));
			x += TextWidth;
		}
		int slots = SlotCount;
		for (int i = 0; i < slots; i++)
		{
			float fill = i < _fill.Count ? _fill[i] : 0f;
			float flash = i < _flash.Count ? _flash[i] : 0f;
			float burst = i < _burst.Count ? _burst[i] : 0f;
			var c = new Vector2(x + CrystalSize * 0.5f, cy);
			// Gentle shimmer on full crystals.
			float shimmer = fill >= 0.999f ? 0.12f * Mathf.Max(0f, Mathf.Sin(_time * 2.2f - i * 0.6f)) : 0f;
			float pop = 1f + 0.18f * flash;
			bool extra = i >= _max;
			HudStyle.DrawCrystal(this, c, CrystalSize * pop, fill, Mathf.Max(flash, shimmer), extra ? 0.75f : 1f);
			if (burst > 0f)
			{
				HudStyle.StrokeEllipse(this, c, Vector2.One * CrystalSize * (0.4f + 0.6f * (1f - burst)),
					new Color(0.7f, 0.9f, 1f, burst), 2f, 20);
			}
			x += CrystalSize + Gap;
		}
	}
}
