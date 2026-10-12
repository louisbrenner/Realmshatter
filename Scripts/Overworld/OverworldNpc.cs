using Godot;

namespace Realmshatter;

/// <summary>
/// A townsperson in the overworld: a duelist (NpcData) or a vendor (VendorData). Draws itself in its clan colour
/// with name and title, shows a "!" until beaten (a gold star afterwards, a padlock while it still waits for other
/// duels) and blocks movement.
/// </summary>
public partial class OverworldNpc : Node2D
{
	/// <summary>Duelist data (null for vendors).</summary>
	public NpcData Npc { get; private set; }

	/// <summary>Vendor data (null for duelists).</summary>
	public VendorData Vendor { get; private set; }

	/// <summary>True while the player stands close enough to talk.</summary>
	public bool Highlighted { get; set; }

	private float _time;
	private float _facing = 1f;

	/// <summary>Sets up a duelist.</summary>
	public void SetupNpc(NpcData npc)
	{
		Npc = npc;
		Position = npc.Position;
		Name = $"Npc_{npc.Id}";
	}

	/// <summary>Sets up a vendor.</summary>
	public void SetupVendor(VendorData vendor)
	{
		Vendor = vendor;
		Position = vendor.Position;
		Name = $"Vendor_{vendor.Id}";
	}

	/// <summary>Display name.</summary>
	public string DisplayName => Npc?.Name ?? Vendor?.Name ?? "";

	public override void _Ready()
	{
		var body = new StaticBody2D();
		body.AddChild(new CollisionShape2D { Shape = new CircleShape2D { Radius = 14f }, Position = new Vector2(0, -6) });
		AddChild(body);
		_time = (float)GD.RandRange(0.0, 10.0);
	}

	/// <summary>Turns toward a world position (when talking).</summary>
	public void FaceToward(Vector2 target)
	{
		_facing = target.X < GlobalPosition.X ? -1f : 1f;
	}

	public override void _Process(double delta)
	{
		_time += (float)delta;
		QueueRedraw();
	}

	public override void _Draw()
	{
		Color robe;
		Color accent;
		bool leader = false;
		string title;
		if (Npc != null)
		{
			robe = ClanInfo.GetColor(Npc.Clan).Darkened(0.15f);
			accent = ClanInfo.GetColor(Npc.Clan).Lightened(0.4f);
			leader = Npc.Title.Contains("Leader");
			title = Npc.Title;
		}
		else
		{
			robe = Vendor?.Color ?? Colors.Gray;
			accent = new Color(1f, 0.85f, 0.45f);
			title = Vendor?.Title ?? "";
		}
		if (Highlighted)
		{
			float pulse = 0.5f + 0.5f * Mathf.Sin(_time * 5f);
			HudStyle.StrokeEllipse(this, new Vector2(0, 1), new Vector2(22, 9), new Color(1f, 0.9f, 0.5f, 0.6f + 0.4f * pulse), 2.5f, 24);
		}
		float idle = Mathf.Sin(_time * 1.5f) * 0.3f;
		PersonSprite.Draw(this, Vector2.Zero, robe, accent, idle, _facing, leader, Npc != null && Npc.Clan != Clan.None);

		Color nameColor = Npc != null ? ClanInfo.GetColor(Npc.Clan).Lightened(0.35f) : new Color(1f, 0.88f, 0.55f);
		// Vendors stand under their stall awning: lift their labels above it.
		float lift = Vendor != null ? -50f : 0f;
		PersonSprite.DrawLabel(this, new Vector2(0, -62 + lift), DisplayName, 14, nameColor);
		PersonSprite.DrawLabel(this, new Vector2(0, -78 + lift), title, 11, new Color(0.92f, 0.88f, 0.8f));

		float hover = Mathf.Sin(_time * 3f) * 3f + lift;
		if (Npc != null)
		{
			if (PlayerProfile.HasDefeated(Npc.Id))
			{
				DrawStar(new Vector2(0, -98 + hover), 8f, new Color(1f, 0.82f, 0.3f));
			}
			else if (!BattleSession.IsUnlocked(Npc, out int _, out int _))
			{
				DrawLock(new Vector2(0, -100 + hover));
			}
			else
			{
				DrawCircle(new Vector2(0, -102 + hover), 10f, new Color(0.1f, 0.06f, 0.03f));
				DrawCircle(new Vector2(0, -102 + hover), 8.5f, new Color(1f, 0.85f, 0.3f));
				PersonSprite.DrawLabel(this, new Vector2(0, -96 + hover), "!", 14, new Color(0.25f, 0.12f, 0.04f));
			}
		}
		else
		{
			DrawCircle(new Vector2(0, -102 + hover), 9.5f, new Color(0.1f, 0.06f, 0.03f));
			DrawCircle(new Vector2(0, -102 + hover), 8f, new Color(0.98f, 0.8f, 0.3f));
			PersonSprite.DrawLabel(this, new Vector2(0, -97 + hover), "$", 12, new Color(0.35f, 0.2f, 0.05f));
		}
	}

	private void DrawLock(Vector2 c)
	{
		var outline = new Color(0.1f, 0.06f, 0.03f);
		DrawArc(c + new Vector2(0, -4), 5.5f, Mathf.Pi, Mathf.Tau, 12, outline, 4.5f);
		DrawArc(c + new Vector2(0, -4), 5.5f, Mathf.Pi, Mathf.Tau, 12, new Color(0.7f, 0.7f, 0.74f), 2.2f);
		DrawRect(new Rect2(c.X - 9, c.Y - 5, 18, 14), outline);
		DrawRect(new Rect2(c.X - 7.5f, c.Y - 3.5f, 15, 11), new Color(0.62f, 0.6f, 0.66f));
		DrawCircle(c + new Vector2(0, 1.5f), 2f, outline);
	}

	private void DrawStar(Vector2 c, float r, Color color)
	{
		var pts = new Vector2[10];
		for (int i = 0; i < 10; i++)
		{
			float a = -Mathf.Pi / 2 + i * Mathf.Pi / 5;
			float rr = i % 2 == 0 ? r : r * 0.45f;
			pts[i] = c + new Vector2(Mathf.Cos(a), Mathf.Sin(a)) * rr;
		}
		DrawColoredPolygon(pts, color);
		DrawPolyline(HudStyle.Close(pts), new Color(0.3f, 0.18f, 0.05f), 1.2f, true);
	}
}
