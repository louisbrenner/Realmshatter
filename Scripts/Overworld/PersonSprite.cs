using Godot;

namespace Realmshatter;

/// <summary>Draws a small top-down townsperson (shadow, robe, arms, head, hood/hat) on any CanvasItem.</summary>
public static class PersonSprite
{
	private static readonly Color Skin = new Color(0.95f, 0.78f, 0.62f);
	private static readonly Color Outline = new Color(0.12f, 0.08f, 0.05f);

	/// <summary>
	/// Draws the figure with its feet at 'feet'. bob = walk phase (0 = standing), facing = -1 left / 1 right,
	/// crown = gold crown instead of a hood (clan leaders), staff = carries a staff.
	/// </summary>
	public static void Draw(CanvasItem ci, Vector2 feet, Color robe, Color accent, float bob, float facing, bool crown = false, bool staff = false)
	{
		float lift = Mathf.Abs(Mathf.Sin(bob)) * 3f;
		Vector2 body = feet + new Vector2(0, -18 - lift);
		ci.DrawSetTransform(Vector2.Zero);
		HudStyle.FillEllipse(ci, feet + new Vector2(0, 1), new Vector2(14, 5), new Color(0, 0, 0, 0.28f), 16);

		// Legs.
		float step = Mathf.Sin(bob) * 4f;
		ci.DrawLine(feet + new Vector2(-5, -10 - lift), feet + new Vector2(-5 + step, -1), Outline, 4f);
		ci.DrawLine(feet + new Vector2(5, -10 - lift), feet + new Vector2(5 - step, -1), Outline, 4f);

		// Robe (trapezoid) with trim.
		Vector2[] robeShape =
		{
			body + new Vector2(-9, -10), body + new Vector2(9, -10), body + new Vector2(13, 10), body + new Vector2(-13, 10),
		};
		ci.DrawColoredPolygon(robeShape, robe);
		ci.DrawPolyline(new[] { robeShape[0], robeShape[1], robeShape[2], robeShape[3], robeShape[0] }, Outline, 1.5f, true);
		ci.DrawLine(body + new Vector2(-12, 7), body + new Vector2(12, 7), accent, 2.5f);
		ci.DrawLine(body + new Vector2(0, -9), body + new Vector2(0, 9), accent.Darkened(0.2f), 1.5f);

		// Arms.
		float swing = Mathf.Sin(bob) * 3f;
		ci.DrawLine(body + new Vector2(-9, -7), body + new Vector2(-14, 4 + swing), robe.Darkened(0.2f), 4f);
		ci.DrawLine(body + new Vector2(9, -7), body + new Vector2(14, 4 - swing), robe.Darkened(0.2f), 4f);
		if (staff)
		{
			Vector2 hand = body + new Vector2(14 * facing, 4);
			ci.DrawLine(hand + new Vector2(0, 10), hand + new Vector2(0, -30), new Color(0.4f, 0.26f, 0.12f), 3f);
			ci.DrawCircle(hand + new Vector2(0, -32), 4.5f, accent.Lightened(0.3f));
		}

		// Head.
		Vector2 head = body + new Vector2(0, -18);
		ci.DrawCircle(head, 9f, Outline);
		ci.DrawCircle(head, 7.8f, Skin);
		ci.DrawCircle(head + new Vector2(2.5f * facing + 1.5f, -1), 1.3f, Outline);
		ci.DrawCircle(head + new Vector2(2.5f * facing - 2.5f, -1), 1.3f, Outline);
		if (crown)
		{
			Vector2[] c =
			{
				head + new Vector2(-8, -5), head + new Vector2(-8, -14), head + new Vector2(-4, -9), head + new Vector2(0, -16),
				head + new Vector2(4, -9), head + new Vector2(8, -14), head + new Vector2(8, -5),
			};
			ci.DrawColoredPolygon(c, new Color(1f, 0.8f, 0.25f));
			ci.DrawPolyline(new[] { c[0], c[1], c[2], c[3], c[4], c[5], c[6], c[0] }, Outline, 1.2f, true);
		}
		else
		{
			// Hood.
			ci.DrawArc(head, 9f, Mathf.Pi * 1.05f, Mathf.Pi * 1.95f, 12, robe.Darkened(0.15f), 5f);
		}
	}

	/// <summary>Draws a text centred above a point with an outline (names, prompts).</summary>
	public static void DrawLabel(CanvasItem ci, Vector2 center, string text, int size, Color color)
	{
		Font font = VfxAssets.CardTextBoldFont;
		Vector2 s = font.GetStringSize(text, HorizontalAlignment.Left, -1, size);
		Vector2 at = new Vector2(center.X - s.X / 2, center.Y);
		ci.DrawStringOutline(font, at, text, HorizontalAlignment.Left, -1, size, 5, new Color(0.08f, 0.05f, 0.03f));
		ci.DrawString(font, at, text, HorizontalAlignment.Left, -1, size, color);
	}
}
