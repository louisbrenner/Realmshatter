using Godot;

namespace Realmshatter;

/// <summary>
/// The inside of a clan hall, drawn procedurally like the town: plank floor, plastered back wall with timber, clan
/// banners and the hall's name, a fireplace, a carpet from the door to the leader's throne, side tables with
/// benches and torches. Creates collision for the walls and furniture. The room is placed at Origin (far away
/// from the town) so both maps never touch; NPC positions in NpcData are room-local (0..RoomSize).
/// </summary>
public partial class HouseInterior : Node2D
{
	/// <summary>Size of the room in pixels.</summary>
	public static readonly Vector2 RoomSize = new Vector2(960, 640);

	/// <summary>World position of the room's top-left corner.</summary>
	public static readonly Vector2 Origin = new Vector2(4000, 0);

	/// <summary>Room-local spot where the player appears when entering (just inside the door).</summary>
	public static readonly Vector2 EntryPoint = new Vector2(480, 560);

	/// <summary>Room-local area of the doorway: standing in it and walking down leaves the hall.</summary>
	public static readonly Rect2 Doorway = new Rect2(440, 575, 80, 60);

	private const float BackWall = 130f;
	private const float SideWall = 36f;
	private const float DoorWidth = 80f;

	private static readonly Color Plank = new Color(0.55f, 0.38f, 0.22f);
	private static readonly Color PlankDark = new Color(0.42f, 0.28f, 0.15f);
	private static readonly Color Plaster = new Color(0.82f, 0.75f, 0.62f);
	private static readonly Color Wood = new Color(0.45f, 0.29f, 0.16f);
	private static readonly Color WoodDark = new Color(0.28f, 0.17f, 0.08f);
	private static readonly Color Stone = new Color(0.55f, 0.53f, 0.5f);
	private static readonly Color StoneDark = new Color(0.38f, 0.36f, 0.34f);

	private static readonly Rect2 TableLeft = new Rect2(90, 300, 140, 56);
	private static readonly Rect2 TableRight = new Rect2(730, 300, 140, 56);
	private static readonly Rect2 Dais = new Rect2(400, 140, 160, 70);

	private float _time;

	/// <summary>Clan whose hall this is.</summary>
	public Clan Clan { get; private set; }

	/// <summary>Sets the clan (colours, name). Call before adding the node to the tree.</summary>
	public void Setup(Clan clan)
	{
		Clan = clan;
		Name = $"Hall_{clan}";
		Position = Origin;
	}

	/// <summary>True if a world position lies in the doorway.</summary>
	public bool IsInDoorway(Vector2 world) => Doorway.HasPoint(world - Origin);

	public override void _Ready()
	{
		ZIndex = -10;
		BuildCollision();
	}

	public override void _Process(double delta)
	{
		_time += (float)delta;
		QueueRedraw();
	}

	private void BuildCollision()
	{
		var body = new StaticBody2D { Name = "Solid" };
		AddChild(body);
		void Rect(Rect2 r)
		{
			body.AddChild(new CollisionShape2D { Shape = new RectangleShape2D { Size = r.Size }, Position = r.GetCenter() });
		}
		float doorLeft = (RoomSize.X - DoorWidth) / 2f;
		Rect(new Rect2(0, 0, RoomSize.X, BackWall));
		Rect(new Rect2(0, 0, SideWall, RoomSize.Y));
		Rect(new Rect2(RoomSize.X - SideWall, 0, SideWall, RoomSize.Y));
		Rect(new Rect2(0, RoomSize.Y - 40, doorLeft, 40));
		Rect(new Rect2(doorLeft + DoorWidth, RoomSize.Y - 40, doorLeft, 40));
		// Behind the doorway: the player can step into it, but not walk off the map.
		Rect(new Rect2(doorLeft, RoomSize.Y + 4, DoorWidth, 40));
		Rect(TableLeft);
		Rect(TableRight);
		Rect(new Rect2(Dais.Position.X + 50, Dais.Position.Y - 10, 60, 40));
	}

	public override void _Draw()
	{
		Color clan = ClanInfo.GetColor(Clan);
		DrawRect(new Rect2(-400, -300, RoomSize.X + 800, RoomSize.Y + 600), new Color(0.08f, 0.05f, 0.03f));
		DrawFloor();
		DrawCarpet(clan);
		DrawBackWall(clan);
		DrawRect(new Rect2(0, 0, SideWall, RoomSize.Y), WoodDark);
		DrawRect(new Rect2(RoomSize.X - SideWall, 0, SideWall, RoomSize.Y), WoodDark);
		DrawRect(new Rect2(SideWall - 6, BackWall, 6, RoomSize.Y - BackWall), Wood);
		DrawRect(new Rect2(RoomSize.X - SideWall, BackWall, 6, RoomSize.Y - BackWall), Wood);
		DrawFrontWall();
		DrawDais(clan);
		DrawTable(TableLeft);
		DrawTable(TableRight);
		foreach (Vector2 torch in new[] { new Vector2(SideWall + 14, 260), new Vector2(RoomSize.X - SideWall - 14, 260),
					 new Vector2(SideWall + 14, 470), new Vector2(RoomSize.X - SideWall - 14, 470) })
		{
			DrawTorch(torch);
		}
	}

	private void DrawFloor()
	{
		for (float y = BackWall; y < RoomSize.Y; y += 24f)
		{
			int row = (int)(y / 24f);
			DrawRect(new Rect2(0, y, RoomSize.X, 24f), row % 2 == 0 ? Plank : Plank.Darkened(0.06f));
			DrawLine(new Vector2(0, y), new Vector2(RoomSize.X, y), PlankDark, 1.5f);
			for (float x = (row % 3) * 70f; x < RoomSize.X; x += 210f)
			{
				DrawLine(new Vector2(x, y), new Vector2(x, y + 24f), PlankDark, 1.5f);
			}
		}
	}

	private void DrawCarpet(Color clan)
	{
		var carpet = new Rect2(RoomSize.X / 2 - 60, Dais.End.Y - 10, 120, RoomSize.Y - Dais.End.Y);
		DrawRect(carpet, clan.Darkened(0.45f));
		DrawRect(carpet.Grow(-6), clan.Darkened(0.2f));
		for (float y = carpet.Position.Y + 30; y < carpet.End.Y - 20; y += 60)
		{
			Vector2 c = new Vector2(carpet.GetCenter().X, y);
			DrawColoredPolygon(new[] { c + new Vector2(0, -14), c + new Vector2(14, 0), c + new Vector2(0, 14), c + new Vector2(-14, 0) },
				clan.Lightened(0.25f));
		}
	}

	private void DrawBackWall(Color clan)
	{
		DrawRect(new Rect2(0, 0, RoomSize.X, BackWall), Plaster);
		DrawRect(new Rect2(0, 0, RoomSize.X, 14), WoodDark);
		DrawRect(new Rect2(0, BackWall - 12, RoomSize.X, 12), WoodDark);
		for (float x = 80; x < RoomSize.X; x += 160)
		{
			DrawRect(new Rect2(x - 5, 14, 10, BackWall - 26), WoodDark);
		}
		// Banners between the beams.
		foreach (float bx in new[] { 160f, 320f, 640f, 800f })
		{
			float sway = Mathf.Sin(_time * 1.6f + bx) * 2f;
			Vector2[] flag =
			{
				new Vector2(bx - 22, 26), new Vector2(bx + 22, 26), new Vector2(bx + 22 + sway, 92),
				new Vector2(bx + sway, 80), new Vector2(bx - 22 + sway, 92),
			};
			DrawColoredPolygon(flag, clan.Darkened(0.1f));
			DrawPolyline(HudStyle.Close(flag), clan.Darkened(0.5f), 2f, true);
			DrawCircle(new Vector2(bx + sway * 0.5f, 52), 9f, clan.Lightened(0.45f));
			DrawLine(new Vector2(bx - 26, 25), new Vector2(bx + 26, 25), WoodDark, 4f);
		}
		DrawFireplace(new Vector2(480, BackWall));
		string name = ClanInfo.GetName(Clan);
		Font font = VfxAssets.CardTextBoldFont;
		string title = $"Hall of the {name}";
		Vector2 size = font.GetStringSize(title, HorizontalAlignment.Left, -1, 20);
		Vector2 at = new Vector2(RoomSize.X / 2 - size.X / 2, 36);
		DrawStringOutline(font, at, title, HorizontalAlignment.Left, -1, 20, 6, new Color(0.1f, 0.06f, 0.03f));
		DrawString(font, at, title, HorizontalAlignment.Left, -1, 20, clan.Lightened(0.4f));
	}

	private void DrawFireplace(Vector2 bottom)
	{
		var outer = new Rect2(bottom.X - 70, bottom.Y - 82, 140, 82);
		DrawRect(outer, StoneDark);
		for (int i = 0; i < 6; i++)
		{
			DrawRect(new Rect2(outer.Position.X + 4 + (i % 3) * 45, outer.Position.Y + 4 + (i / 3) * 18, 42, 15), Stone);
		}
		var hearth = new Rect2(bottom.X - 42, bottom.Y - 46, 84, 46);
		DrawRect(hearth, new Color(0.1f, 0.06f, 0.04f));
		for (int i = 0; i < 5; i++)
		{
			float x = hearth.Position.X + 14 + i * 14;
			float h = 18 + 10 * Mathf.Sin(_time * 7f + i * 1.7f);
			Vector2 b = new Vector2(x, hearth.End.Y - 4);
			DrawColoredPolygon(new[] { b + new Vector2(-8, 0), b + new Vector2(0, -h), b + new Vector2(8, 0) }, new Color(1f, 0.5f, 0.12f, 0.9f));
			DrawColoredPolygon(new[] { b + new Vector2(-4, 0), b + new Vector2(0, -h * 0.55f), b + new Vector2(4, 0) }, new Color(1f, 0.9f, 0.45f));
		}
		DrawRect(new Rect2(hearth.Position.X + 6, hearth.End.Y - 6, hearth.Size.X - 12, 6), WoodDark);
	}

	private void DrawFrontWall()
	{
		float doorLeft = (RoomSize.X - DoorWidth) / 2f;
		DrawRect(new Rect2(0, RoomSize.Y - 40, doorLeft, 40), WoodDark);
		DrawRect(new Rect2(doorLeft + DoorWidth, RoomSize.Y - 40, doorLeft, 40), WoodDark);
		DrawRect(new Rect2(0, RoomSize.Y - 40, RoomSize.X, 5), Wood);
		// Open doorway with daylight and a door mat.
		DrawRect(new Rect2(doorLeft, RoomSize.Y - 40, DoorWidth, 48), new Color(0.45f, 0.62f, 0.32f));
		DrawRect(new Rect2(doorLeft + 10, RoomSize.Y - 64, DoorWidth - 20, 22), new Color(0.6f, 0.45f, 0.28f));
		DrawRect(new Rect2(doorLeft - 6, RoomSize.Y - 44, 6, 48), Wood);
		DrawRect(new Rect2(doorLeft + DoorWidth, RoomSize.Y - 44, 6, 48), Wood);
	}

	private void DrawDais(Color clan)
	{
		DrawRect(new Rect2(Dais.Position + new Vector2(6, 8), Dais.Size), new Color(0, 0, 0, 0.25f));
		DrawRect(Dais, StoneDark);
		DrawRect(Dais.Grow(-5), Stone);
		// Throne.
		var back = new Rect2(Dais.GetCenter().X - 30, Dais.Position.Y - 34, 60, 64);
		DrawRect(back, WoodDark);
		DrawRect(back.Grow(-5), clan.Darkened(0.35f));
		DrawColoredPolygon(new[]
		{
			new Vector2(back.Position.X, back.Position.Y), new Vector2(back.GetCenter().X, back.Position.Y - 18),
			new Vector2(back.End.X, back.Position.Y),
		}, WoodDark);
		DrawCircle(new Vector2(back.GetCenter().X, back.Position.Y - 4), 6f, new Color(1f, 0.82f, 0.35f));
	}

	private void DrawTable(Rect2 t)
	{
		DrawRect(new Rect2(t.Position + new Vector2(6, 8), t.Size), new Color(0, 0, 0, 0.25f));
		DrawRect(new Rect2(t.Position.X, t.Position.Y - 18, t.Size.X, 12), WoodDark);
		DrawRect(new Rect2(t.Position.X, t.End.Y + 6, t.Size.X, 12), WoodDark);
		DrawRect(t, Wood);
		DrawRect(t, WoodDark, false, 3f);
		DrawLine(new Vector2(t.Position.X, t.GetCenter().Y), new Vector2(t.End.X, t.GetCenter().Y), WoodDark, 1.5f);
		// Mugs and a candle.
		DrawCircle(t.Position + new Vector2(28, 18), 6f, new Color(0.75f, 0.7f, 0.6f));
		DrawCircle(t.Position + new Vector2(t.Size.X - 30, 36), 6f, new Color(0.75f, 0.7f, 0.6f));
		Vector2 candle = t.GetCenter();
		DrawRect(new Rect2(candle.X - 3, candle.Y - 12, 6, 14), new Color(0.95f, 0.92f, 0.82f));
		float flick = 1f + 0.2f * Mathf.Sin(_time * 9f + t.Position.X);
		DrawCircle(candle + new Vector2(0, -15), 3.5f * flick, new Color(1f, 0.8f, 0.3f));
		DrawCircle(candle + new Vector2(0, -15), 14f * flick, new Color(1f, 0.75f, 0.3f, 0.12f));
	}

	private void DrawTorch(Vector2 p)
	{
		DrawRect(new Rect2(p.X - 3, p.Y - 6, 6, 22), WoodDark);
		float flick = 1f + 0.25f * Mathf.Sin(_time * 8f + p.Y);
		DrawCircle(p + new Vector2(0, -10), 30f * flick, new Color(1f, 0.7f, 0.3f, 0.1f));
		DrawCircle(p + new Vector2(0, -10), 7f * flick, new Color(1f, 0.55f, 0.15f));
		DrawCircle(p + new Vector2(0, -11), 3.5f * flick, new Color(1f, 0.92f, 0.5f));
	}
}
