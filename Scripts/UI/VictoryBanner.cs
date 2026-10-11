using Godot;

namespace Realmshatter;

/// <summary>
/// End-of-game crest: rotating light rays, a shield crest and a big ribbon with "VICTORY" (gold/blue)
/// or "DEFEAT" (dark red/grey), plus a subtitle. Call Present to (re)play the entrance animation.
/// </summary>
public partial class VictoryBanner : Control
{
	private bool _victory = true;
	private string _title = "VICTORY";
	private string _subtitle = "";
	private float _time;
	private float _intro;

	public override void _Ready()
	{
		MouseFilter = MouseFilterEnum.Ignore;
		CustomMinimumSize = new Vector2(520f, 300f);
	}

	/// <summary>Sets victory/defeat look and texts and restarts the entrance animation.</summary>
	public void Present(bool victory, string title, string subtitle)
	{
		_victory = victory;
		_title = title ?? (victory ? "VICTORY" : "DEFEAT");
		_subtitle = subtitle ?? "";
		_intro = 0f;
		_time = 0f;
		QueueRedraw();
	}

	public override void _Process(double delta)
	{
		float dt = (float)delta;
		_time += dt;
		_intro = Mathf.Min(1f, _intro + dt * 1.8f);
		if (IsVisibleInTree())
		{
			QueueRedraw();
		}
	}

	public override void _Draw()
	{
		Vector2 c = new Vector2(Size.X * 0.5f, Size.Y * 0.45f);
		float e = 1f - Mathf.Pow(1f - _intro, 3f);
		float scale = 0.6f + 0.4f * e + 0.06f * Mathf.Sin(Mathf.Clamp(_intro, 0f, 1f) * Mathf.Pi);
		Color main = _victory ? HudStyle.Gold : new Color(0.7f, 0.25f, 0.2f);
		Color dark = _victory ? new Color(0.16f, 0.3f, 0.6f) : new Color(0.25f, 0.2f, 0.2f);

		// Rays.
		if (_victory)
		{
			int rays = 18;
			for (int i = 0; i < rays; i++)
			{
				float a = _time * 0.25f + Mathf.Tau * i / rays;
				float len = 260f * e;
				Vector2 d1 = new Vector2(Mathf.Cos(a - 0.07f), Mathf.Sin(a - 0.07f));
				Vector2 d2 = new Vector2(Mathf.Cos(a + 0.07f), Mathf.Sin(a + 0.07f));
				DrawPolygon(new[] { c, c + d1 * len, c + d2 * len },
					new[] { new Color(1f, 0.9f, 0.55f, 0.35f * e), new Color(1f, 0.9f, 0.55f, 0f), new Color(1f, 0.9f, 0.55f, 0f) });
			}
		}
		HudStyle.FillEllipse(this, c, Vector2.One * 120f * e, new Color(main, 0.18f * e), 40);

		DrawSetTransform(c, 0f, Vector2.One * scale);
		// Shield crest.
		Vector2[] shield =
		{
			new Vector2(-80, -105), new Vector2(80, -105), new Vector2(86, -10), new Vector2(0, 95), new Vector2(-86, -10),
		};
		DrawColoredPolygon(shield, dark.Darkened(0.3f));
		Vector2[] innerShield = new Vector2[shield.Length];
		for (int i = 0; i < shield.Length; i++)
		{
			innerShield[i] = shield[i] * 0.84f;
		}
		DrawColoredPolygon(innerShield, dark);
		DrawPolyline(HudStyle.Close(shield), main, 5f, true);
		DrawPolyline(HudStyle.Close(innerShield), new Color(main, 0.6f), 2f, true);
		// Emblem: crossed swords (victory) or broken sword (defeat).
		Color steel = new Color(0.88f, 0.9f, 0.95f);
		if (_victory)
		{
			DrawSetTransform(c + new Vector2(0, -30f * scale), 0f, Vector2.One * scale);
			DrawLine(new Vector2(-38, 30), new Vector2(38, -60), steel, 7f, true);
			DrawLine(new Vector2(38, 30), new Vector2(-38, -60), steel, 7f, true);
			DrawLine(new Vector2(-50, 16), new Vector2(-24, 40), main, 6f, true);
			DrawLine(new Vector2(50, 16), new Vector2(24, 40), main, 6f, true);
			DrawSetTransform(c, 0f, Vector2.One * scale);
		}
		else
		{
			// Broken sword: hilt + lower blade with a jagged break, the tip fallen aside.
			Color blade = steel.Darkened(0.25f);
			DrawSetTransform(c + new Vector2(0, -48f * scale), 0f, Vector2.One * scale * 0.85f);
			DrawColoredPolygon(new[] { new Vector2(-7, 22), new Vector2(7, 22), new Vector2(7, -18), new Vector2(2, -10), new Vector2(-3, -22), new Vector2(-7, -14) }, blade);
			DrawColoredPolygon(new[] { new Vector2(-26, 22), new Vector2(26, 22), new Vector2(26, 31), new Vector2(-26, 31) }, main);
			DrawColoredPolygon(new[] { new Vector2(-5, 31), new Vector2(5, 31), new Vector2(5, 52), new Vector2(-5, 52) }, new Color(0.35f, 0.2f, 0.1f));
			DrawCircle(new Vector2(0, 57), 7f, main);
			DrawColoredPolygon(new[] { new Vector2(22, -34), new Vector2(30, -40), new Vector2(58, -78), new Vector2(26, -48), new Vector2(18, -40) }, blade.Darkened(0.15f));
			DrawSetTransform(c, 0f, Vector2.One * scale);
		}

		// Ribbon.
		float rw = 230f;
		float rh = 64f;
		float ry = 50f;
		Vector2[] tailL = { new Vector2(-rw - 40, ry - rh * 0.3f), new Vector2(-rw + 10, ry - rh * 0.3f), new Vector2(-rw + 10, ry + rh * 0.7f), new Vector2(-rw - 40, ry + rh * 0.7f), new Vector2(-rw - 22, ry + rh * 0.2f) };
		Vector2[] tailR = new Vector2[tailL.Length];
		for (int i = 0; i < tailL.Length; i++)
		{
			tailR[i] = new Vector2(-tailL[i].X, tailL[i].Y);
		}
		Color ribbon = _victory ? new Color(0.75f, 0.12f, 0.1f) : new Color(0.3f, 0.28f, 0.27f);
		DrawColoredPolygon(tailL, ribbon.Darkened(0.4f));
		DrawColoredPolygon(tailR, ribbon.Darkened(0.4f));
		Vector2[] body =
		{
			new Vector2(-rw, ry - rh * 0.5f), new Vector2(0, ry - rh * 0.5f - 12f), new Vector2(rw, ry - rh * 0.5f),
			new Vector2(rw, ry + rh * 0.5f), new Vector2(0, ry + rh * 0.5f - 12f), new Vector2(-rw, ry + rh * 0.5f),
		};
		DrawColoredPolygon(body, ribbon);
		DrawPolyline(HudStyle.Close(body), main, 3f, true);
		HudStyle.DrawTextCentered(this, _title, new Vector2(0, ry - 6f), 50, new Color(1f, 0.95f, 0.82f), 10, new Color(0.15f, 0.04f, 0.02f));
		DrawSetTransform(Vector2.Zero, 0f, Vector2.One);

		if (!string.IsNullOrEmpty(_subtitle))
		{
			HudStyle.DrawTextCentered(this, _subtitle, new Vector2(c.X, c.Y + 130f * scale), 20, new Color(HudStyle.TextLight, e), 5);
		}
	}
}
