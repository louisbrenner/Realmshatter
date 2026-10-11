using System.Collections.Generic;
using Godot;

namespace Realmshatter;

/// <summary>
/// Victory points as stacking gold coins: the target is split into columns (e.g. 20 = 4 stacks of 5),
/// faint slots show the remaining progress. Gained coins drop in with a bounce and a glint,
/// spent coins float up and fade.
/// </summary>
public partial class VictoryCoinStack : Control
{
	[Export] public float CoinRadius { get; set; } = 15f;
	[Export] public float CoinThickness { get; set; } = 5f;
	[Export] public float ColumnGap { get; set; } = 7f;
	[Export] public int MaxColumns { get; set; } = 5;
	[Export] public Color Accent { get; set; } = HudStyle.PlayerBlue;

	private const float DropHeight = 70f;
	private const float DropTime = 0.42f;
	private const float DropStagger = 0.09f;
	private const float LeaveTime = 0.45f;
	/// <summary>Drop progress value of a coin lying on its stack (negative = waiting, 0..1 = falling).</summary>
	private const float Resting = 2f;

	private int _target = 20;
	private int _points;
	private readonly List<float> _drop = new List<float>();
	private readonly List<float> _flash = new List<float>();
	private readonly List<(int Index, float T)> _leaving = new List<(int, float)>();
	private float _time;

	/// <summary>Victory points needed to win.</summary>
	public int Target
	{
		get => _target;
		set
		{
			_target = Mathf.Max(1, value);
			_points = Mathf.Min(_points, _target);
			SyncLists(_points);
			UpdateMinimumSize();
			QueueRedraw();
		}
	}

	/// <summary>Current points (clamped to the target for display).</summary>
	public int Points => _points;

	public override void _Ready()
	{
		MouseFilter = MouseFilterEnum.Ignore;
		SyncLists(_points);
	}

	/// <summary>Sets the points; animates coin drops (gain) or coins floating away (loss) unless animate is false.</summary>
	public void SetPoints(int points, bool animate = true)
	{
		points = Mathf.Clamp(points, 0, _target);
		int old = _points;
		_points = points;
		SyncLists(points);
		if (!animate || !IsInsideTree())
		{
			for (int i = 0; i < _drop.Count; i++)
			{
				_drop[i] = Resting;
			}
			_leaving.Clear();
			QueueRedraw();
			return;
		}
		for (int i = old; i < points; i++)
		{
			// Negative = waiting (stagger), 0..1 = falling.
			_drop[i] = -(i - old) * DropStagger / DropTime;
		}
		for (int i = points; i < old; i++)
		{
			_leaving.Add((i, 0f));
		}
		QueueRedraw();
	}

	public override Vector2 _GetMinimumSize()
	{
		GetLayout(out int cols, out int perStack);
		float w = cols * CoinRadius * 2f + (cols - 1) * ColumnGap + 4f;
		float h = perStack * CoinThickness + CoinRadius * 0.84f + CoinThickness + 6f;
		return new Vector2(w, h);
	}

	public override void _Process(double delta)
	{
		float dt = (float)delta;
		_time += dt;
		bool busy = false;
		for (int i = 0; i < _drop.Count; i++)
		{
			if (_drop[i] < 1f)
			{
				_drop[i] += dt / DropTime;
				if (_drop[i] >= 1f)
				{
					_drop[i] = Resting;
					_flash[i] = 1f;
				}
				busy = true;
			}
			if (_flash[i] > 0f)
			{
				_flash[i] = Mathf.Max(0f, _flash[i] - dt * 2.5f);
				busy = true;
			}
		}
		for (int i = _leaving.Count - 1; i >= 0; i--)
		{
			(int index, float t) = _leaving[i];
			t += dt / LeaveTime;
			if (t >= 1f)
			{
				_leaving.RemoveAt(i);
			}
			else
			{
				_leaving[i] = (index, t);
			}
			busy = true;
		}
		if (busy)
		{
			QueueRedraw();
		}
	}

	public override void _Draw()
	{
		GetLayout(out int cols, out int perStack);
		float r = CoinRadius;
		float t = CoinThickness;
		float colW = r * 2f;
		float totalW = cols * colW + (cols - 1) * ColumnGap;
		float x0 = (Size.X - totalW) * 0.5f + r;
		float baseY = Size.Y - r * 0.42f - t - 3f;

		// Accent felt pad under the stacks.
		var pad = new Rect2(x0 - r - 2f, baseY - r * 0.1f, totalW + 4f, r * 0.84f + t + 4f);
		DrawColoredPolygon(HudStyle.RoundRect(pad, 6f), new Color(Accent.Darkened(0.65f), 0.55f));

		for (int c = 0; c < cols; c++)
		{
			float cx = x0 + c * (colW + ColumnGap);
			for (int k = 0; k < perStack; k++)
			{
				int index = c * perStack + k;
				if (index >= _target)
				{
					break;
				}
				var pos = new Vector2(cx, baseY - k * t);
				if (index >= _points)
				{
					if (!IsLeaving(index))
					{
						HudStyle.DrawCoin(this, pos, r, t, 1f, 0f, true);
					}
					continue;
				}
				float d = index < _drop.Count ? _drop[index] : Resting;
				if (d < 0f)
				{
					continue;
				}
				float offset = 0f;
				float alpha = 1f;
				if (d < 1f)
				{
					float e = BounceOut(d);
					offset = -DropHeight * (1f - e);
					alpha = Mathf.Clamp(d * 4f, 0f, 1f);
				}
				float flash = index < _flash.Count ? _flash[index] : 0f;
				HudStyle.DrawCoin(this, pos + new Vector2(0, offset), r, t, alpha, flash);
			}
			// Column complete: small shine above the stack.
			int top = (c + 1) * perStack;
			if (top <= _points && top <= _target)
			{
				float pulse = 0.5f + 0.5f * Mathf.Sin(_time * 3f + c);
				HudStyle.FillEllipse(this, new Vector2(cx, baseY - perStack * t - 2f), new Vector2(r * 0.35f, r * 0.12f),
					new Color(1f, 0.95f, 0.7f, 0.25f + 0.25f * pulse), 12);
			}
		}

		foreach ((int index, float lt) in _leaving)
		{
			int c = index / perStack;
			int k = index % perStack;
			float cx = x0 + c * (colW + ColumnGap);
			var pos = new Vector2(cx, baseY - k * t - lt * 40f);
			HudStyle.DrawCoin(this, pos, r * (1f + 0.3f * lt), t, 1f - lt, 0.6f);
		}
	}

	private bool IsLeaving(int index)
	{
		foreach ((int i, float _) in _leaving)
		{
			if (i == index)
			{
				return true;
			}
		}
		return false;
	}

	private void GetLayout(out int cols, out int perStack)
	{
		int maxCols = Mathf.Max(1, MaxColumns);
		cols = Mathf.Clamp(Mathf.CeilToInt(_target / 5f), 1, maxCols);
		perStack = Mathf.CeilToInt(_target / (float)cols);
	}

	private void SyncLists(int count)
	{
		while (_drop.Count < _target)
		{
			_drop.Add(Resting);
			_flash.Add(0f);
		}
		for (int i = count; i < _drop.Count; i++)
		{
			_drop[i] = Resting;
		}
	}

	private static float BounceOut(float x)
	{
		const float n1 = 7.5625f;
		const float d1 = 2.75f;
		if (x < 1f / d1)
		{
			return n1 * x * x;
		}
		if (x < 2f / d1)
		{
			x -= 1.5f / d1;
			return n1 * x * x + 0.75f;
		}
		if (x < 2.5f / d1)
		{
			x -= 2.25f / d1;
			return n1 * x * x + 0.9375f;
		}
		x -= 2.625f / d1;
		return n1 * x * x + 0.984375f;
	}
}
