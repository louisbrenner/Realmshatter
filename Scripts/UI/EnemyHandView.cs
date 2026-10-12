using Godot;

namespace Realmshatter;

/// <summary>The opponent's hand, face down: a centred fan of card backs with the card count (inside the enemy window).</summary>
public partial class EnemyHandView : Control
{
	[Export] public Vector2 CardSize { get; set; } = new Vector2(34, 48);
	[Export] public float Spacing { get; set; } = 18f;

	private int _count;
	private float _pop;
	private Tween _tween;

	/// <summary>Sets the number of cards; a change pops the fan briefly.</summary>
	public void SetCount(int count)
	{
		if (count == _count)
		{
			return;
		}
		_count = count;
		_tween?.Kill();
		_tween = CreateTween();
		_tween.TweenMethod(Callable.From<float>(v =>
		{
			_pop = v;
			QueueRedraw();
		}), 1f, 0f, 0.35f);
		QueueRedraw();
	}

	public override void _Draw()
	{
		int n = Mathf.Min(_count, 10);
		float total = n > 0 ? (n - 1) * Spacing + CardSize.X : 0f;
		float startX = (Size.X - total) * 0.5f;
		for (int i = 0; i < n; i++)
		{
			float off = i - (n - 1) * 0.5f;
			var center = new Vector2(startX + i * Spacing + CardSize.X * 0.5f, 6f + CardSize.Y * 0.5f + off * off * 0.6f - _pop * 6f);
			DrawSetTransform(center, Mathf.DegToRad(off * 4f), Vector2.One);
			var rect = new Rect2(-CardSize * 0.5f, CardSize);
			DrawColoredPolygon(HudStyle.RoundRect(rect.Grow(1.5f), 5f), new Color(0, 0, 0, 0.45f));
			DrawColoredPolygon(HudStyle.RoundRect(rect, 4f), new Color(0.27f, 0.14f, 0.08f));
			DrawColoredPolygon(HudStyle.RoundRect(rect.Grow(-3f), 3f), new Color(0.43f, 0.24f, 0.12f));
			DrawPolyline(HudStyle.Close(HudStyle.RoundRect(rect, 4f)), HudStyle.GoldDark, 1.5f, true);
			HudStyle.StrokeEllipse(this, Vector2.Zero, new Vector2(8f, 8f), new Color(HudStyle.Gold, 0.85f), 1.5f, 16);
			HudStyle.FillEllipse(this, Vector2.Zero, new Vector2(3.5f, 3.5f), HudStyle.Gold, 10);
		}
		DrawSetTransform(Vector2.Zero, 0f, Vector2.One);
		if (_count > 0)
		{
			HudStyle.DrawTextCentered(this, $"Hand: {_count}", new Vector2(Size.X * 0.5f, CardSize.Y + 18f), 13, HudStyle.TextLight, 4);
		}
	}
}
