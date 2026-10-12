using System;
using System.Collections.Generic;
using Godot;

namespace Realmshatter;

/// <summary>
/// The small town, drawn procedurally: grass with flowers, dirt roads, a cobblestone plaza with a fountain, one
/// house per clan (roof and banner in the clan colour, an enterable door with the hall's duel progress), market
/// stalls, trees and a fence around the map. Creates static collision bodies for everything solid. Purely visual +
/// collision; entering the halls is handled by OverworldMain.
/// </summary>
public partial class TownMap : Node2D
{
	/// <summary>A clan house: wall rectangle and clan.</summary>
	public readonly record struct House(Rect2 Body, Clan Clan);

	/// <summary>A market stall: counter rectangle and awning colour.</summary>
	public readonly record struct Stall(Rect2 Counter, Color Color);

	/// <summary>Size of the walkable town in pixels.</summary>
	public static readonly Vector2 MapSize = new Vector2(1920, 1280);
	public static readonly Vector2 PlazaCenter = new Vector2(960, 640);
	public const float PlazaRadius = 170f;
	public const float FountainRadius = 58f;

	private static readonly Color Grass = new Color(0.36f, 0.55f, 0.27f);
	private static readonly Color GrassDark = new Color(0.29f, 0.46f, 0.22f);
	private static readonly Color Dirt = new Color(0.62f, 0.5f, 0.34f);
	private static readonly Color DirtEdge = new Color(0.5f, 0.39f, 0.26f);
	private static readonly Color Cobble = new Color(0.62f, 0.6f, 0.56f);
	private static readonly Color CobbleDark = new Color(0.47f, 0.45f, 0.42f);
	private static readonly Color Wood = new Color(0.45f, 0.29f, 0.16f);
	private static readonly Color WoodDark = new Color(0.3f, 0.18f, 0.09f);
	private static readonly Color Wall = new Color(0.86f, 0.8f, 0.68f);
	private static readonly Color Water = new Color(0.32f, 0.6f, 0.88f);

	private readonly List<House> _houses = new List<House>
	{
		new House(new Rect2(200, 230, 240, 140), Clan.Fire),
		new House(new Rect2(1480, 230, 240, 140), Clan.Healing),
		new House(new Rect2(200, 880, 240, 140), Clan.Frost),
		new House(new Rect2(1480, 880, 240, 140), Clan.Storm),
		new House(new Rect2(1080, 170, 240, 140), Clan.Stone),
	};

	private readonly List<Stall> _stalls = new List<Stall>();
	private readonly List<Vector2> _reserved = new List<Vector2>();
	private readonly Dictionary<Clan, (int Beaten, int Total)> _progress = new Dictionary<Clan, (int, int)>();
	private readonly List<(Vector2 Pos, float Radius, float Shade)> _trees = new List<(Vector2, float, float)>();
	private readonly List<(Vector2 Pos, Color Color)> _flowers = new List<(Vector2, Color)>();
	private readonly List<(Vector2 Pos, float Size)> _tufts = new List<(Vector2, float)>();
	private float _time;

	/// <summary>Clan houses (for placing NPCs).</summary>
	public IReadOnlyList<House> Houses => _houses;

	/// <summary>House whose door glows (the player stands in front of it), or Clan.None.</summary>
	public Clan HighlightedDoor { get; set; } = Clan.None;

	/// <summary>Where the player stands in front of a house's door (just below the door step).</summary>
	public static Vector2 DoorOf(House h) => new Vector2(h.Body.GetCenter().X, h.Body.End.Y + 18f);

	/// <summary>Keeps trees and props away from a spot (an NPC stands there). Call before the node is ready.</summary>
	public void ReserveSpot(Vector2 position)
	{
		_reserved.Add(position);
	}

	/// <summary>Shows "beaten / total" duel stars on a house's door sign.</summary>
	public void SetHouseProgress(Clan clan, int beaten, int total)
	{
		_progress[clan] = (beaten, total);
		QueueRedraw();
	}

	/// <summary>Registers a market stall (counter drawn below the vendor, solid). Call before the node is ready.</summary>
	public void AddStall(Vector2 vendorPosition, Color color)
	{
		_stalls.Add(new Stall(new Rect2(vendorPosition.X - 70, vendorPosition.Y + 18, 140, 42), color));
	}

	public override void _Ready()
	{
		ZIndex = -10;
		GenerateScenery();
		BuildCollision();
	}

	public override void _Process(double delta)
	{
		_time += (float)delta;
		QueueRedraw();
	}

	/// <summary>True if a point is on a road, the plaza or near a building (no trees / props there).</summary>
	private bool IsBusy(Vector2 p, float margin)
	{
		if (Mathf.Abs(p.Y - 640) < 60 + margin || Mathf.Abs(p.X - 960) < 60 + margin)
		{
			return true;
		}
		if (p.DistanceTo(PlazaCenter) < PlazaRadius + 40 + margin)
		{
			return true;
		}
		foreach (House h in _houses)
		{
			if (h.Body.Grow(90 + margin).HasPoint(p))
			{
				return true;
			}
		}
		foreach (Vector2 r in _reserved)
		{
			if (r.DistanceTo(p) < 50 + margin)
			{
				return true;
			}
		}
		foreach (Stall s in _stalls)
		{
			var stallArea = new Rect2(s.Counter.Position - new Vector2(0, 100), s.Counter.Size + new Vector2(0, 100));
			if (stallArea.Grow(60 + margin).HasPoint(p))
			{
				return true;
			}
		}
		return p.X < 60 || p.Y < 60 || p.X > MapSize.X - 60 || p.Y > MapSize.Y - 60;
	}

	private void GenerateScenery()
	{
		var rng = new Random(7);
		for (int i = 0; i < 400 && _trees.Count < 46; i++)
		{
			var p = new Vector2(rng.Next(70, (int)MapSize.X - 70), rng.Next(70, (int)MapSize.Y - 70));
			if (IsBusy(p, 10))
			{
				continue;
			}
			bool clash = false;
			foreach ((Vector2 pos, float _, float _) in _trees)
			{
				clash |= pos.DistanceTo(p) < 70;
			}
			if (!clash)
			{
				_trees.Add((p, 22f + (float)rng.NextDouble() * 10f, (float)rng.NextDouble()));
			}
		}
		Color[] petals = { new Color(1f, 0.85f, 0.3f), new Color(1f, 0.5f, 0.6f), new Color(0.85f, 0.85f, 1f), new Color(1f, 1f, 1f) };
		for (int i = 0; i < 260; i++)
		{
			var p = new Vector2(rng.Next(40, (int)MapSize.X - 40), rng.Next(40, (int)MapSize.Y - 40));
			if (!IsBusy(p, -40))
			{
				_flowers.Add((p, petals[rng.Next(petals.Length)]));
			}
		}
		for (int i = 0; i < 700; i++)
		{
			var p = new Vector2(rng.Next(0, (int)MapSize.X), rng.Next(0, (int)MapSize.Y));
			_tufts.Add((p, 3f + (float)rng.NextDouble() * 4f));
		}
	}

	private void BuildCollision()
	{
		var body = new StaticBody2D { Name = "Solid" };
		AddChild(body);
		void Rect(Rect2 r)
		{
			body.AddChild(new CollisionShape2D
			{
				Shape = new RectangleShape2D { Size = r.Size },
				Position = r.GetCenter(),
			});
		}
		void Circle(Vector2 c, float radius)
		{
			body.AddChild(new CollisionShape2D { Shape = new CircleShape2D { Radius = radius }, Position = c });
		}
		// Map border (fence).
		Rect(new Rect2(-40, -40, MapSize.X + 80, 64));
		Rect(new Rect2(-40, MapSize.Y - 24, MapSize.X + 80, 64));
		Rect(new Rect2(-40, -40, 64, MapSize.Y + 80));
		Rect(new Rect2(MapSize.X - 24, -40, 64, MapSize.Y + 80));
		foreach (House h in _houses)
		{
			Rect(new Rect2(h.Body.Position + new Vector2(0, -50), h.Body.Size + new Vector2(0, 50)));
		}
		foreach (Stall s in _stalls)
		{
			Rect(s.Counter);
		}
		foreach ((Vector2 pos, float radius, float _) in _trees)
		{
			Circle(pos + new Vector2(0, radius * 0.5f), radius * 0.55f);
		}
		Circle(PlazaCenter, FountainRadius);
	}

	public override void _Draw()
	{
		DrawRect(new Rect2(Vector2.Zero, MapSize), Grass);
		foreach ((Vector2 p, float s) in _tufts)
		{
			DrawLine(p, p + new Vector2(-1.5f, -s), GrassDark, 1.5f);
			DrawLine(p, p + new Vector2(1.5f, -s * 0.8f), GrassDark, 1.5f);
		}

		// Roads.
		DrawRect(new Rect2(40, 596, MapSize.X - 80, 88), DirtEdge);
		DrawRect(new Rect2(40, 600, MapSize.X - 80, 80), Dirt);
		DrawRect(new Rect2(916, 40, 88, MapSize.Y - 80), DirtEdge);
		DrawRect(new Rect2(920, 40, 80, MapSize.Y - 80), Dirt);
		foreach (House h in _houses)
		{
			// Side path from the house to the main road.
			float cx = h.Body.GetCenter().X;
			if (h.Body.End.Y < 600)
			{
				DrawRect(new Rect2(cx - 26, h.Body.End.Y, 52, 600 - h.Body.End.Y), Dirt);
			}
			else
			{
				DrawRect(new Rect2(cx - 26, 680, 52, h.Body.Position.Y - 680), Dirt);
			}
		}

		// Plaza with cobbles.
		DrawCircle(PlazaCenter, PlazaRadius + 6, CobbleDark);
		DrawCircle(PlazaCenter, PlazaRadius, Cobble);
		for (int ring = 1; ring <= 5; ring++)
		{
			float r = PlazaRadius * ring / 5.5f + 6f;
			int stones = 8 + ring * 7;
			for (int i = 0; i < stones; i++)
			{
				float a = Mathf.Tau * (i + ring * 0.37f) / stones;
				Vector2 c = PlazaCenter + new Vector2(Mathf.Cos(a), Mathf.Sin(a)) * r;
				DrawCircle(c, 6.5f, CobbleDark);
				DrawCircle(c, 5f, Cobble.Lightened(0.06f * ((i + ring) % 3)));
			}
		}
		DrawFountain();

		foreach ((Vector2 p, Color c) in _flowers)
		{
			DrawCircle(p, 3f, c);
			DrawCircle(p, 1.2f, new Color(1f, 0.9f, 0.3f));
		}
		foreach (Stall s in _stalls)
		{
			DrawStall(s);
		}
		foreach (House h in _houses)
		{
			DrawHouse(h);
		}
		foreach ((Vector2 pos, float radius, float shade) in _trees)
		{
			DrawTree(pos, radius, shade);
		}
		DrawFence();
	}

	private void DrawFountain()
	{
		Vector2 c = PlazaCenter;
		DrawCircle(c + new Vector2(0, 6), FountainRadius + 4, new Color(0, 0, 0, 0.2f));
		DrawCircle(c, FountainRadius, new Color(0.7f, 0.68f, 0.64f));
		DrawCircle(c, FountainRadius - 9, Water.Darkened(0.15f));
		for (int i = 0; i < 3; i++)
		{
			float r = (FountainRadius - 14) * Mathf.PosMod(_time * 0.35f + i / 3f, 1f);
			DrawArc(c, r, 0, Mathf.Tau, 32, new Color(0.8f, 0.92f, 1f, 0.5f * (1f - r / FountainRadius)), 2f);
		}
		DrawCircle(c, 16, new Color(0.74f, 0.72f, 0.68f));
		DrawCircle(c + new Vector2(0, -6), 8, new Color(0.85f, 0.95f, 1f, 0.9f));
	}

	private void DrawHouse(House h)
	{
		Rect2 b = h.Body;
		Color clan = ClanInfo.GetColor(h.Clan);
		DrawRect(new Rect2(b.Position + new Vector2(10, 12), b.Size), new Color(0, 0, 0, 0.25f));
		DrawRect(b, Wall);
		for (int y = 1; y < 5; y++)
		{
			DrawLine(new Vector2(b.Position.X, b.Position.Y + y * b.Size.Y / 5), new Vector2(b.End.X, b.Position.Y + y * b.Size.Y / 5),
				Wall.Darkened(0.08f), 1f);
		}
		// Timber frame.
		DrawRect(b, WoodDark, false, 4f);
		DrawLine(new Vector2(b.Position.X, b.Position.Y + 40), new Vector2(b.End.X, b.Position.Y + 40), WoodDark, 4f);
		// Roof.
		Vector2[] roof =
		{
			new Vector2(b.Position.X - 18, b.Position.Y + 8), new Vector2(b.GetCenter().X, b.Position.Y - 62),
			new Vector2(b.End.X + 18, b.Position.Y + 8),
		};
		DrawColoredPolygon(roof, clan.Darkened(0.25f));
		for (int i = 1; i < 6; i++)
		{
			float t = i / 6f;
			DrawLine(roof[0].Lerp(roof[1], t), roof[2].Lerp(roof[1], t), clan.Darkened(0.4f), 2f);
		}
		DrawPolyline(new[] { roof[0], roof[1], roof[2] }, clan.Darkened(0.55f), 3f, true);
		// Door (glows when the player can enter), door step and windows.
		float cx = b.GetCenter().X;
		if (HighlightedDoor == h.Clan)
		{
			float pulse = 0.5f + 0.5f * Mathf.Sin(_time * 5f);
			DrawRect(new Rect2(cx - 26, b.End.Y - 64, 52, 64), new Color(1f, 0.85f, 0.45f, 0.35f + 0.3f * pulse));
		}
		DrawRect(new Rect2(cx - 20, b.End.Y - 58, 40, 58), WoodDark);
		DrawRect(new Rect2(cx - 16, b.End.Y - 54, 32, 54), Wood);
		DrawLine(new Vector2(cx, b.End.Y - 54), new Vector2(cx, b.End.Y), WoodDark, 1.5f);
		DrawCircle(new Vector2(cx + 9, b.End.Y - 28), 2.5f, new Color(1f, 0.85f, 0.4f));
		DrawRect(new Rect2(cx - 28, b.End.Y, 56, 8), CobbleDark);
		DrawRect(new Rect2(cx - 26, b.End.Y, 52, 6), Cobble);
		if (_progress.TryGetValue(h.Clan, out (int Beaten, int Total) prog) && prog.Total > 0)
		{
			// Sign above the door: one star per duelist of the hall, gold once beaten.
			float w = prog.Total * 14f + 8f;
			var sign = new Rect2(cx - w / 2, b.End.Y - 80, w, 18);
			DrawRect(sign, WoodDark);
			DrawRect(sign.Grow(-2), Wood);
			for (int i = 0; i < prog.Total; i++)
			{
				Color star = i < prog.Beaten ? new Color(1f, 0.82f, 0.3f) : new Color(0.3f, 0.2f, 0.12f);
				DrawStar(new Vector2(sign.Position.X + 11 + i * 14, sign.GetCenter().Y), 5.5f, star);
			}
		}
		foreach (float wx in new[] { b.Position.X + 30, b.End.X - 70 })
		{
			DrawRect(new Rect2(wx, b.Position.Y + 58, 40, 32), WoodDark);
			float glow = 0.75f + 0.25f * Mathf.Sin(_time * 2f + wx);
			DrawRect(new Rect2(wx + 4, b.Position.Y + 62, 32, 24), new Color(1f, 0.85f, 0.45f) * glow);
			DrawLine(new Vector2(wx + 20, b.Position.Y + 62), new Vector2(wx + 20, b.Position.Y + 86), WoodDark, 2f);
		}
		// Clan banner.
		Vector2 pole = new Vector2(b.End.X + 26, b.End.Y);
		DrawLine(pole, pole + new Vector2(0, -110), WoodDark, 4f);
		float wave = Mathf.Sin(_time * 3f) * 4f;
		Vector2[] flag =
		{
			pole + new Vector2(2, -106), pole + new Vector2(46 + wave, -100), pole + new Vector2(40 + wave * 0.5f, -84),
			pole + new Vector2(46 + wave, -66), pole + new Vector2(2, -70),
		};
		DrawColoredPolygon(flag, clan);
		DrawPolyline(new[] { flag[0], flag[1], flag[2], flag[3], flag[4] }, clan.Darkened(0.4f), 1.5f, true);
		Font font = VfxAssets.CardTextBoldFont;
		string name = ClanInfo.GetName(h.Clan);
		Vector2 size = font.GetStringSize(name, HorizontalAlignment.Left, -1, 18);
		Vector2 at = new Vector2(cx - size.X / 2, b.Position.Y + 28);
		DrawStringOutline(font, at, name, HorizontalAlignment.Left, -1, 18, 6, new Color(0.1f, 0.06f, 0.03f));
		DrawString(font, at, name, HorizontalAlignment.Left, -1, 18, clan.Lightened(0.35f));
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
	}

	private void DrawStall(Stall s)
	{
		Rect2 r = s.Counter;
		DrawRect(new Rect2(r.Position + new Vector2(6, 8), r.Size), new Color(0, 0, 0, 0.22f));
		DrawRect(r, Wood);
		DrawRect(r, WoodDark, false, 3f);
		for (int i = 0; i < 5; i++)
		{
			var crate = new Rect2(r.Position.X + 10 + i * 26, r.Position.Y + 8, 18, 14);
			DrawRect(crate, new Color(0.85f, 0.75f, 0.5f).Darkened(0.1f * (i % 2)));
		}
		// Striped awning behind the vendor.
		var awning = new Rect2(r.Position.X - 8, r.Position.Y - 92, r.Size.X + 16, 26);
		for (int i = 0; i < 8; i++)
		{
			DrawRect(new Rect2(awning.Position.X + i * awning.Size.X / 8, awning.Position.Y, awning.Size.X / 8 + 1, awning.Size.Y),
				i % 2 == 0 ? s.Color : new Color(0.95f, 0.92f, 0.85f));
		}
		DrawRect(awning, WoodDark, false, 2f);
		DrawLine(new Vector2(r.Position.X - 4, awning.End.Y), new Vector2(r.Position.X - 4, r.End.Y), WoodDark, 4f);
		DrawLine(new Vector2(r.End.X + 4, awning.End.Y), new Vector2(r.End.X + 4, r.End.Y), WoodDark, 4f);
	}

	private void DrawTree(Vector2 pos, float radius, float shade)
	{
		DrawCircle(pos + new Vector2(6, radius * 0.7f), radius * 0.8f, new Color(0, 0, 0, 0.22f));
		DrawRect(new Rect2(pos.X - 5, pos.Y, 10, radius * 0.9f), WoodDark);
		Color leaf = new Color(0.2f, 0.42f, 0.18f).Lerp(new Color(0.3f, 0.52f, 0.2f), shade);
		float sway = Mathf.Sin(_time * 1.3f + pos.X * 0.01f) * 1.5f;
		DrawCircle(pos + new Vector2(sway, -radius * 0.2f), radius, leaf.Darkened(0.2f));
		DrawCircle(pos + new Vector2(-radius * 0.35f + sway, -radius * 0.4f), radius * 0.7f, leaf);
		DrawCircle(pos + new Vector2(radius * 0.3f + sway, -radius * 0.55f), radius * 0.55f, leaf.Lightened(0.12f));
	}

	private void DrawFence()
	{
		for (float x = 20; x < MapSize.X - 10; x += 34)
		{
			DrawFencePost(new Vector2(x, 22));
			DrawFencePost(new Vector2(x, MapSize.Y - 18));
		}
		for (float y = 20; y < MapSize.Y - 10; y += 34)
		{
			DrawFencePost(new Vector2(18, y));
			DrawFencePost(new Vector2(MapSize.X - 18, y));
		}
		DrawRect(new Rect2(10, 10, MapSize.X - 20, MapSize.Y - 20), WoodDark, false, 3f);
	}

	private void DrawFencePost(Vector2 p)
	{
		DrawRect(new Rect2(p.X - 4, p.Y - 10, 8, 18), Wood);
		DrawRect(new Rect2(p.X - 4, p.Y - 10, 8, 18), WoodDark, false, 1.5f);
	}
}
