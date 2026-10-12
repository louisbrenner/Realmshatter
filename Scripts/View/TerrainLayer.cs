using System.Collections.Generic;
using Godot;

namespace Realmshatter;

/// <summary>
/// Renders the permanent terrain of the board (child of BoardView): flowing water, wooden plank bridges over it and
/// breakable rocks, which shrink as they lose HP. Sync() diffs against the BoardState, so it can be called after
/// every resolved action (a crumbled rock simply disappears; the animator plays its dust).
/// </summary>
public partial class TerrainLayer : Node3D
{
	private static readonly Color PlankColor = new Color(0.5f, 0.33f, 0.18f);
	private static readonly Color RailColor = new Color(0.36f, 0.23f, 0.12f);

	private readonly Dictionary<GridPos, (TerrainType Type, int Hp, Node3D Node)> _nodes = new Dictionary<GridPos, (TerrainType, int, Node3D)>();
	private readonly List<Node3D> _decor = new List<Node3D>();
	private ShaderMaterial _water;
	private StandardMaterial3D _plank;
	private StandardMaterial3D _rail;
	private System.Func<GridPos, Vector3> _toLocal;
	private float _tileSize = 1f;
	private int _rockMaxHp = 3;

	/// <summary>Removes every terrain node.</summary>
	public void ClearAll()
	{
		foreach ((TerrainType _, int _, Node3D node) in _nodes.Values)
		{
			node.QueueFree();
		}
		_nodes.Clear();
		foreach (Node3D node in _decor)
		{
			node.QueueFree();
		}
		_decor.Clear();
	}

	/// <summary>Brings the visuals in line with the board's terrain. 'toLocal' maps a tile to its top centre.</summary>
	public void Sync(BoardState board, System.Func<GridPos, Vector3> toLocal, float tileSize, int rockMaxHp)
	{
		_toLocal = toLocal;
		_tileSize = tileSize;
		_rockMaxHp = rockMaxHp;
		if (_decor.Count == 0)
		{
			foreach (KeyValuePair<GridPos, TerrainType> kv in board.Decor)
			{
				Node3D node = CreateDecor(kv.Value, tileSize, kv.Key);
				node.Position = toLocal(kv.Key);
				AddChild(node);
				_decor.Add(node);
			}
		}
		var stale = new List<GridPos>(_nodes.Keys);
		foreach (KeyValuePair<GridPos, TerrainType> kv in board.Terrain)
		{
			GridPos pos = kv.Key;
			int hp = board.GetTerrainHp(pos);
			stale.Remove(pos);
			if (_nodes.TryGetValue(pos, out (TerrainType Type, int Hp, Node3D Node) existing))
			{
				if (existing.Type == kv.Value && existing.Hp == hp)
				{
					continue;
				}
				existing.Node.QueueFree();
			}
			Node3D node = Create(kv.Value, hp, rockMaxHp, tileSize, pos);
			node.Position = toLocal(pos);
			AddChild(node);
			_nodes[pos] = (kv.Value, hp, node);
		}
		foreach (GridPos pos in stale)
		{
			_nodes[pos].Node.QueueFree();
			_nodes.Remove(pos);
		}
	}

	/// <summary>Shows a hit Rock with its new HP right away (0 = it crumbles and disappears).</summary>
	public void SetRockHp(GridPos pos, int hp)
	{
		if (!_nodes.TryGetValue(pos, out (TerrainType Type, int Hp, Node3D Node) existing) || existing.Type != TerrainType.Rock)
		{
			return;
		}
		existing.Node.QueueFree();
		_nodes.Remove(pos);
		if (hp > 0 && _toLocal != null)
		{
			Node3D node = Create(TerrainType.Rock, hp, _rockMaxHp, _tileSize, pos);
			node.Position = _toLocal(pos);
			AddChild(node);
			_nodes[pos] = (TerrainType.Rock, hp, node);
		}
	}

	private Node3D Create(TerrainType type, int hp, int maxHp, float ts, GridPos pos)
	{
		var root = new Node3D { Name = $"{type}_{pos.X}_{pos.Y}" };
		float seed = pos.X * 12.9898f + pos.Y * 78.233f;
		switch (type)
		{
			case TerrainType.Water:
				root.AddChild(WaterPlane(ts, 0.005f));
				break;
			case TerrainType.Bridge:
				BuildBridge(root, ts, seed);
				break;
			case TerrainType.Rock:
				BuildRock(root, ts, hp, maxHp, seed);
				break;
		}
		return root;
	}

	/// <summary>
	/// Visual-only terrain on the crown field: a river becomes a shallow ford with stepping stones, a wall low
	/// rubble - it plays as plain ground.
	/// </summary>
	private Node3D CreateDecor(TerrainType type, float ts, GridPos pos)
	{
		var root = new Node3D { Name = $"Decor{type}_{pos.X}_{pos.Y}" };
		float seed = pos.X * 12.9898f + pos.Y * 78.233f;
		var rng = new RandomNumberGenerator { Seed = (ulong)Mathf.Abs(seed * 1000f) + 5ul };
		ShaderMaterial stone = VfxAssets.CreateMaterial("stone_wall");
		stone.SetShaderParameter("seed", seed % 10f);
		if (type == TerrainType.Water)
		{
			MeshInstance3D ford = WaterPlane(ts * 0.96f, 0.004f);
			ford.Transparency = 0.6f;
			root.AddChild(ford);
		}
		int stones = type == TerrainType.Water ? 3 : 6;
		for (int i = 0; i < stones; i++)
		{
			float s = type == TerrainType.Water ? rng.RandfRange(0.16f, 0.22f) : rng.RandfRange(0.07f, 0.13f);
			var mi = new MeshInstance3D
			{
				Mesh = new BoxMesh { Size = new Vector3(s * 1.2f, 0.025f, s) },
				MaterialOverride = stone,
				Position = new Vector3(rng.RandfRange(-0.32f, 0.32f) * ts, -0.004f, rng.RandfRange(-0.32f, 0.32f) * ts),
				Rotation = new Vector3(0f, rng.RandfRange(0f, Mathf.Tau), 0f),
				CastShadow = GeometryInstance3D.ShadowCastingSetting.Off,
			};
			mi.SetInstanceShaderParameter("top_size", new Vector2(s * 1.2f, s));
			root.AddChild(mi);
		}
		return root;
	}

	private MeshInstance3D WaterPlane(float ts, float y)
	{
		_water ??= VfxAssets.CreateMaterial("tile_water");
		return new MeshInstance3D
		{
			Mesh = new PlaneMesh { Size = new Vector2(ts, ts) },
			MaterialOverride = _water,
			Position = new Vector3(0, y, 0),
			CastShadow = GeometryInstance3D.ShadowCastingSetting.Off,
		};
	}

	/// <summary>Water underneath, planks across the river (crossing runs along the board's Z axis) and low side rails.</summary>
	private void BuildBridge(Node3D root, float ts, float seed)
	{
		_plank ??= new StandardMaterial3D { AlbedoColor = PlankColor, Roughness = 0.9f };
		_rail ??= new StandardMaterial3D { AlbedoColor = RailColor, Roughness = 0.9f };
		root.AddChild(WaterPlane(ts, -0.01f));
		const int planks = 5;
		float step = ts / planks;
		for (int i = 0; i < planks; i++)
		{
			float jitter = 0.01f * Mathf.Sin(seed + i * 1.7f);
			root.AddChild(new MeshInstance3D
			{
				Mesh = new BoxMesh { Size = new Vector3(ts * 0.78f, 0.03f, step * 0.86f) },
				MaterialOverride = _plank,
				Position = new Vector3(jitter, -0.008f, -ts * 0.5f + step * (i + 0.5f)),
				Rotation = new Vector3(0f, 0.03f * Mathf.Sin(seed * 0.7f + i), 0f),
			});
		}
		foreach (float side in new[] { -1f, 1f })
		{
			root.AddChild(new MeshInstance3D
			{
				Mesh = new BoxMesh { Size = new Vector3(0.04f, 0.05f, ts * 0.96f) },
				MaterialOverride = _rail,
				Position = new Vector3(side * ts * 0.43f, 0.03f, 0f),
			});
			for (int k = 0; k < 2; k++)
			{
				root.AddChild(new MeshInstance3D
				{
					Mesh = new BoxMesh { Size = new Vector3(0.06f, 0.1f, 0.06f) },
					MaterialOverride = _rail,
					Position = new Vector3(side * ts * 0.43f, 0.04f, (k == 0 ? -1f : 1f) * ts * 0.4f),
				});
			}
		}
	}

	/// <summary>A rough boulder wall; lower and more broken the less HP it has left.</summary>
	private static void BuildRock(Node3D root, float ts, int hp, int maxHp, float seed)
	{
		float health = maxHp > 0 ? Mathf.Clamp(hp / (float)maxHp, 0.2f, 1f) : 1f;
		float height = 0.22f + 0.36f * health;
		var rng = new RandomNumberGenerator { Seed = (ulong)Mathf.Abs(seed * 1000f) + 3ul };
		ShaderMaterial stone = VfxAssets.CreateMaterial("stone_wall");
		stone.SetShaderParameter("seed", seed % 10f);
		void AddBlock(Vector3 size, Vector3 pos, Vector3 rot)
		{
			var mi = new MeshInstance3D { Mesh = new BoxMesh { Size = size }, MaterialOverride = stone, Position = pos, Rotation = rot };
			mi.SetInstanceShaderParameter("top_size", new Vector2(size.X, size.Z));
			root.AddChild(mi);
		}
		AddBlock(new Vector3(0.8f * ts, height, 0.74f * ts), new Vector3(0, height * 0.5f, 0), new Vector3(0, rng.RandfRange(-0.15f, 0.15f), 0));
		AddBlock(new Vector3(0.5f * ts, height * 0.45f, 0.46f * ts), new Vector3(rng.RandfRange(-0.12f, 0.12f) * ts, height + height * 0.2f, rng.RandfRange(-0.1f, 0.1f) * ts),
			new Vector3(rng.RandfRange(-0.12f, 0.12f), rng.RandfRange(0f, Mathf.Tau), rng.RandfRange(-0.12f, 0.12f)));
		int chips = 3 + Mathf.RoundToInt((1f - health) * 4f);
		for (int i = 0; i < chips; i++)
		{
			float ang = Mathf.Tau * i / chips + rng.RandfRange(-0.4f, 0.4f);
			float s = rng.RandfRange(0.07f, 0.14f);
			AddBlock(new Vector3(s * 1.3f, s * 0.8f, s), new Vector3(Mathf.Cos(ang) * 0.42f * ts, s * 0.35f, Mathf.Sin(ang) * 0.42f * ts),
				new Vector3(rng.RandfRange(-0.4f, 0.4f), rng.RandfRange(0f, Mathf.Tau), rng.RandfRange(-0.4f, 0.4f)));
		}
	}
}
