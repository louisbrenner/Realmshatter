using System.Threading.Tasks;
using Godot;

namespace Realmshatter;

/// <summary>
/// Full-width sweeping banner for turn changes ("YOUR TURN" / "ENEMY TURN" + turn number).
/// The ribbon sweeps in from the left, the title pops, holds and the banner fades out to the right.
/// Play is awaitable; a new Play replaces a running one.
/// </summary>
public partial class TurnBanner : Control
{
	[Export] public float Duration { get; set; } = 1.25f;

	private string _title = "";
	private string _subtitle = "";
	private Color _accent = HudStyle.PlayerBlue;
	private float _t = 1f;
	private float _time;
	private Tween _tween;
	private TaskCompletionSource<bool> _pending;

	/// <summary>True while a banner animation runs.</summary>
	public bool IsPlaying => _tween != null && _tween.IsValid() && _tween.IsRunning();

	public override void _Ready()
	{
		MouseFilter = MouseFilterEnum.Ignore;
		Visible = false;
	}

	/// <summary>Plays the banner; completes when it has faded out.</summary>
	public Task Play(string title, string subtitle, Color accent)
	{
		_tween?.Kill();
		_pending?.TrySetResult(true);
		var pending = new TaskCompletionSource<bool>();
		_pending = pending;
		_title = title ?? "";
		_subtitle = subtitle ?? "";
		_accent = accent;
		_t = 0f;
		Visible = true;
		_tween = CreateTween();
		_tween.TweenMethod(Callable.From<float>(v =>
		{
			_t = v;
			QueueRedraw();
		}), 0f, 1f, Mathf.Max(0.3f, Duration));
		_tween.TweenCallback(Callable.From(() =>
		{
			Visible = false;
			pending.TrySetResult(true);
		}));
		return pending.Task;
	}

	public override void _ExitTree()
	{
		_pending?.TrySetResult(true);
	}

	public override void _Process(double delta)
	{
		_time += (float)delta;
		if (Visible)
		{
			QueueRedraw();
		}
	}

	public override void _Draw()
	{
		if (_t >= 1f)
		{
			return;
		}
		// Phases: 0..0.22 sweep in, 0.22..0.75 hold, 0.75..1 fade out.
		float inT = Mathf.Clamp(_t / 0.22f, 0f, 1f);
		float outT = Mathf.Clamp((_t - 0.75f) / 0.25f, 0f, 1f);
		float sweep = 1f - Mathf.Pow(1f - inT, 3f);
		float alpha = 1f - outT;
		float cy = Size.Y * 0.44f;
		float h = 96f;
		float w = Size.X;

		// Dim band.
		var band = new Rect2(0f, cy - h * 0.9f, w, h * 1.8f);
		DrawRect(band, new Color(0f, 0f, 0f, 0.35f * alpha * sweep));

		// Ribbon (grows from the center outward, slides right while fading).
		float half = w * 0.5f * sweep;
		float shift = outT * 80f;
		float cx = w * 0.5f + shift;
		Color body = _accent.Darkened(0.45f);
		// The notched ribbon is only a valid (simple) polygon while it is wider than its two notches;
		// at the very start of the sweep (or in a zero-sized control) it would be degenerate/self-intersecting.
		float notch = Mathf.Min(24f, half * 0.4f);
		if (half > 4f && h > 1f && w > 1f)
		{
			Vector2[] ribbon =
			{
				new Vector2(cx - half, cy - h * 0.5f), new Vector2(cx + half, cy - h * 0.5f),
				new Vector2(cx + half - notch, cy), new Vector2(cx + half, cy + h * 0.5f),
				new Vector2(cx - half, cy + h * 0.5f), new Vector2(cx - half + notch, cy),
			};
			DrawColoredPolygon(ribbon, new Color(body, 0.92f * alpha));
		}
		DrawRect(new Rect2(cx - half, cy - h * 0.5f, half * 2f, 5f), new Color(HudStyle.Gold, alpha));
		DrawRect(new Rect2(cx - half, cy + h * 0.5f - 5f, half * 2f, 5f), new Color(HudStyle.Gold, alpha));
		DrawRect(new Rect2(cx - half, cy - h * 0.5f + 8f, half * 2f, 1.5f), new Color(HudStyle.Gold, 0.5f * alpha));
		DrawRect(new Rect2(cx - half, cy + h * 0.5f - 9.5f, half * 2f, 1.5f), new Color(HudStyle.Gold, 0.5f * alpha));

		// Light streak sweeping across.
		float streakX = Mathf.Lerp(-200f, w + 200f, Mathf.Clamp(_t / 0.6f, 0f, 1f));
		Vector2[] streak =
		{
			new Vector2(streakX - 40f, cy - h * 0.5f + 5f), new Vector2(streakX + 10f, cy - h * 0.5f + 5f),
			new Vector2(streakX - 10f, cy + h * 0.5f - 5f), new Vector2(streakX - 60f, cy + h * 0.5f - 5f),
		};
		if (h > 12f)
		{
			DrawColoredPolygon(streak, new Color(1f, 1f, 1f, 0.18f * alpha));
		}

		// Title pop.
		float pop = inT < 1f ? 0f : Mathf.Clamp((_t - 0.22f) / 0.18f, 0f, 1f);
		float scale = 1f + 0.35f * (1f - EaseOutBack(pop));
		float titleAlpha = alpha * Mathf.Clamp((_t - 0.12f) / 0.12f, 0f, 1f);
		int size = Mathf.RoundToInt(52f * scale);
		HudStyle.DrawTextCentered(this, _title, new Vector2(cx, cy - 10f), size, new Color(1f, 0.95f, 0.8f, titleAlpha), 10,
			new Color(0.08f, 0.04f, 0.01f, titleAlpha));
		HudStyle.DrawTextCentered(this, _subtitle, new Vector2(cx, cy + 30f), 20, new Color(HudStyle.Gold, titleAlpha), 5,
			new Color(0.08f, 0.04f, 0.01f, titleAlpha));
	}

	private static float EaseOutBack(float x)
	{
		const float c1 = 1.70158f;
		const float c3 = c1 + 1f;
		return 1f + c3 * Mathf.Pow(x - 1f, 3f) + c1 * Mathf.Pow(x - 1f, 2f);
	}
}
