using System.Collections.Generic;
using System.Threading.Tasks;
using Godot;

namespace Realmshatter;

/// <summary>
/// Renders the board (one stone/parchment shader surface with a glowing rune border around the
/// scoring zone), the wooden frame with gold trims and the table beneath, plus pulsing tile
/// highlights. Converts between grid and world coordinates and picks tiles under the mouse.
/// Grid X maps to world X, grid Y maps to world Z (row 0 = -Z = far side / player 1,
/// last row = +Z = near side / player 0). The board is centered at this node's origin;
/// tile tops lie on local y = 0.
/// </summary>
public partial class BoardView : Node3D
{
	/// <summary>Emitted on a left mouse click on a tile (not over UI).</summary>
	[Signal] public delegate void TileClickedEventHandler(Vector2I pos);

	/// <summary>Emitted when the hovered tile changes. (-1, -1) means the mouse left the board.</summary>
	[Signal] public delegate void TileHoveredEventHandler(Vector2I pos);

	[ExportGroup("Layout")]
	[Export] public float TileSize { get; set; } = 1.0f;
	[Export] public float TileGap { get; set; } = 0.05f;
	/// <summary>How much higher the crown field's tiles stand than the rest of the board (pieces stand on top).</summary>
	[Export] public float CrownLift { get; set; } = 0.045f;
	[Export] public float TileThickness { get; set; } = 0.2f;

	[ExportGroup("Tile Colors")]
	[Export] public Color NormalColor { get; set; } = new Color(0.5f, 0.47f, 0.42f);
	[Export] public Color ScoringZoneColor { get; set; } = new Color(0.88f, 0.74f, 0.47f);
	[Export] public Color Player0DeployColor { get; set; } = new Color(0.22f, 0.42f, 0.9f);
	[Export] public Color Player1DeployColor { get; set; } = new Color(0.9f, 0.26f, 0.2f);
	[Export] public Color BaseColor { get; set; } = new Color(0.12f, 0.1f, 0.09f);
	[Export] public Color RuneColor { get; set; } = new Color(1.0f, 0.68f, 0.24f);
	/// <summary>Brightness difference for the checkerboard pattern (0 = off).</summary>
	[Export(PropertyHint.Range, "0,0.3,0.01")] public float CheckerStrength { get; set; } = 0.05f;
	/// <summary>Optional material for the board surface; replaces the procedural board shader if set.</summary>
	[Export] public StandardMaterial3D TileMaterialTemplate { get; set; }

	[ExportGroup("Decoration")]
	[Export] public bool BuildDecoration { get; set; } = true;
	[Export] public float FrameWidth { get; set; } = 0.46f;
	[Export] public float FrameHeight { get; set; } = 0.14f;
	[Export] public Color WoodLight { get; set; } = new Color(0.55f, 0.32f, 0.16f);
	[Export] public Color WoodDark { get; set; } = new Color(0.22f, 0.11f, 0.05f);
	[Export] public Color TableLight { get; set; } = new Color(0.36f, 0.21f, 0.11f);
	[Export] public Color TableDark { get; set; } = new Color(0.13f, 0.07f, 0.035f);

	[ExportGroup("Highlight Colors")]
	[Export] public Color MoveHighlightColor { get; set; } = new Color(0.30f, 0.75f, 1.00f, 0.6f);
	[Export] public Color AttackHighlightColor { get; set; } = new Color(1.00f, 0.25f, 0.20f, 0.6f);
	[Export] public Color DeployHighlightColor { get; set; } = new Color(0.30f, 1.00f, 0.40f, 0.55f);
	[Export] public Color SpellHighlightColor { get; set; } = new Color(0.75f, 0.35f, 1.00f, 0.6f);
	[Export] public Color SelectedHighlightColor { get; set; } = new Color(1.00f, 0.85f, 0.30f, 0.65f);
	[Export] public Color HoverHighlightColor { get; set; } = new Color(1.00f, 0.95f, 0.85f, 0.45f);
	[Export] public Color RangeHighlightColor { get; set; } = new Color(0.25f, 0.95f, 0.95f, 0.42f);

	private readonly Dictionary<HighlightKind, List<MeshInstance3D>> _highlights = new Dictionary<HighlightKind, List<MeshInstance3D>>();
	private readonly Dictionary<HighlightKind, ShaderMaterial> _highlightMaterials = new Dictionary<HighlightKind, ShaderMaterial>();

	private Node3D _tileRoot;
	private Node3D _highlightRoot;
	private TileEffectLayer _tileEffects;
	private TerrainLayer _terrain;
	private Rect2I _crown;
	private Node3D _trapRoot;
	private readonly Dictionary<GridPos, (TrapType Type, Node3D Node)> _trapMarkers = new Dictionary<GridPos, (TrapType, Node3D)>();
	private PlaneMesh _highlightMesh;
	private int _width = 10;
	private int _height = 8;
	private Vector2I _hovered = new Vector2I(-1, -1);
	private readonly System.Collections.Generic.List<(MeshInstance3D Flame, OmniLight3D Light, float Seed)> _candles =
		new System.Collections.Generic.List<(MeshInstance3D, OmniLight3D, float)>();
	private float _time;

	/// <summary>Board width in tiles (from the last Build, default 10).</summary>
	public int Width => _width;

	/// <summary>Board height in tiles (from the last Build, default 8).</summary>
	public int Height => _height;

	public override void _Ready()
	{
		EnsureRoots();
	}

	/// <summary>(Re)creates the board surface and decoration for the given board and clears highlights.</summary>
	public void Build(BoardState board)
	{
		EnsureRoots();
		ClearHighlights();
		_tileEffects.ClearAll();
		foreach (Node child in _tileRoot.GetChildren())
		{
			child.QueueFree();
		}

		_width = board.Width;
		_crown = board.HotZone;
		_height = board.Height;
		float w = _width * TileSize;
		float h = _height * TileSize;

		// Physical board: one chamfered stone block per tile (real gaps, slight height / tilt variation).
		var surface = new MeshInstance3D
		{
			Name = "Surface",
			Mesh = TileMeshBuilder.Build(_width, _height, TileSize, TileGap, 0.05f, 0.1f, 11, (x, y) => IsCrown(x, y) ? CrownLift : 0f),
			MaterialOverride = CreateSurfaceMaterial(board),
			CastShadow = GeometryInstance3D.ShadowCastingSetting.On,
		};
		_tileRoot.AddChild(surface);

		// Dark bed the stones are set into (visible in the gaps).
		var baseInstance = new MeshInstance3D
		{
			Name = "BoardBase",
			Mesh = new BoxMesh { Size = new Vector3(w + 0.1f, TileThickness, h + 0.1f) },
			MaterialOverride = new StandardMaterial3D { AlbedoColor = BaseColor.Darkened(0.4f), Roughness = 1f },
			Position = new Vector3(0, -TileThickness * 0.5f - 0.07f, 0),
		};
		_tileRoot.AddChild(baseInstance);

		if (BuildDecoration)
		{
			BuildFrame(w, h);
			BuildTable();
			BuildProps(w, h);
		}

		_highlightMesh = new PlaneMesh { Size = new Vector2(TileSize, TileSize) };
		_terrain.ClearAll();
		SyncTerrain(board);
		foreach ((TrapType _, Node3D node) in _trapMarkers.Values)
		{
			node.QueueFree();
		}
		_trapMarkers.Clear();
	}

	/// <summary>Updates water, bridges and rocks from the board (rockMaxHp scales the rock height).</summary>
	public void SyncTerrain(BoardState board, int rockMaxHp = 3)
	{
		EnsureRoots();
		_terrain.Sync(board, GridToLocal, TileSize, rockMaxHp);
	}

	/// <summary>
	/// Shows the hidden traps of 'viewer' as faint jaw markers on their tiles; the opponent's traps stay invisible
	/// until they spring.
	/// </summary>
	public void SyncTraps(BoardState board, int viewer)
	{
		EnsureRoots();
		var stale = new List<GridPos>(_trapMarkers.Keys);
		foreach (Trap trap in board.Traps.Values)
		{
			if (trap.OwnerIndex != viewer)
			{
				continue;
			}
			stale.Remove(trap.Position);
			if (_trapMarkers.TryGetValue(trap.Position, out (TrapType Type, Node3D Node) existing) && existing.Type == trap.Type)
			{
				continue;
			}
			existing.Node?.QueueFree();
			MeshInstance3D marker = VfxAssets.CreateIcon((int)FxIconShape.Trap, TileSize * 0.56f, TrapInfo.GetColor(trap.Type),
				new Color(0.08f, 0.06f, 0.05f, 0.8f), true, 6);
			if (marker.MaterialOverride is ShaderMaterial mat)
			{
				mat.SetShaderParameter("billboard", false);
				mat.SetShaderParameter("alpha", 0.62f);
			}
			marker.Rotation = new Vector3(-Mathf.Pi * 0.5f, 0f, 0f);
			marker.Position = GridToLocal(trap.Position) + new Vector3(0f, 0.014f, 0f);
			_trapRoot.AddChild(marker);
			_trapMarkers[trap.Position] = (trap.Type, marker);
		}
		foreach (GridPos pos in stale)
		{
			_trapMarkers[pos].Node.QueueFree();
			_trapMarkers.Remove(pos);
		}
	}

	/// <summary>Removes the marker of a sprung trap right away.</summary>
	public void RemoveTrapMarker(GridPos pos)
	{
		if (_trapMarkers.TryGetValue(pos, out (TrapType Type, Node3D Node) marker))
		{
			marker.Node.QueueFree();
			_trapMarkers.Remove(pos);
		}
	}

	/// <summary>Shows a hit Rock with its remaining HP (0 = it crumbles).</summary>
	public void ShowRockHp(GridPos pos, int hp)
	{
		_terrain?.SetRockHp(pos, hp);
	}

	/// <summary>The layer that renders lava / wall / healing tiles (child "TileEffects").</summary>
	public TileEffectLayer TileEffects
	{
		get
		{
			EnsureRoots();
			return _tileEffects;
		}
	}

	/// <summary>
	/// Shows the board's tile effects: new effects appear animated, expired ones vanish, duration badges
	/// update. Uses the turn number of the last call (see the overload) for the remaining-turn badges.
	/// </summary>
	public void SyncTileEffects(BoardState board)
	{
		SyncTileEffects(board, -1, true);
	}

	/// <summary>SyncTileEffects with the current global turn number (for remaining turns) and optional animation.</summary>
	public void SyncTileEffects(BoardState board, int currentTurn, bool animate = true)
	{
		TileEffects.Sync(board, currentTurn, animate);
	}

	/// <summary>Animates a tile effect appearing on a tile (TileEffectApplied). Completes when it has formed.</summary>
	public Task AnimateTileEffectApplied(GridPos pos, TileEffectType type, int expiryTurn)
	{
		return TileEffects.PlayApplied(pos, type, expiryTurn);
	}

	/// <summary>Animates the tile effect on a tile vanishing (TileEffectExpired). Completes when it is gone.</summary>
	public Task AnimateTileEffectExpired(GridPos pos)
	{
		return TileEffects.PlayExpired(pos);
	}

	/// <summary>World position of the center of a tile's top surface.</summary>
	public Vector3 GridToWorld(GridPos pos)
	{
		Vector3 local = GridToLocal(pos);
		return IsInsideTree() ? ToGlobal(local) : local;
	}

	/// <summary>Grid position for a world point, or null if it lies outside the board.</summary>
	public GridPos? WorldToGrid(Vector3 world)
	{
		Vector3 local = IsInsideTree() ? ToLocal(world) : world;
		float fx = local.X / TileSize + _width * 0.5f;
		float fy = local.Z / TileSize + _height * 0.5f;
		int x = Mathf.FloorToInt(fx);
		int y = Mathf.FloorToInt(fy);
		if (x < 0 || y < 0 || x >= _width || y >= _height)
		{
			return null;
		}
		return new GridPos(x, y);
	}

	/// <summary>Tile under a screen position (ray vs. the board's y = 0 plane), or null.</summary>
	public GridPos? PickTile(Camera3D camera, Vector2 screenPos)
	{
		if (camera == null)
		{
			return null;
		}
		Vector3 origin = camera.ProjectRayOrigin(screenPos);
		Vector3 dir = camera.ProjectRayNormal(screenPos);
		var plane = new Plane(GlobalTransform.Basis.Y.Normalized(), GlobalPosition);
		Vector3? hit = plane.IntersectsRay(origin, dir);
		if (hit == null)
		{
			return null;
		}
		return WorldToGrid(hit.Value);
	}

	/// <summary>Shows highlights of the given kind on the tiles, replacing previous highlights of that kind.</summary>
	public void ShowHighlights(IEnumerable<GridPos> tiles, HighlightKind kind)
	{
		EnsureRoots();
		ClearHighlights(kind);
		if (tiles == null)
		{
			return;
		}
		_highlightMesh ??= new PlaneMesh { Size = new Vector2(TileSize, TileSize) };

		if (!_highlights.TryGetValue(kind, out List<MeshInstance3D> list))
		{
			list = new List<MeshInstance3D>();
			_highlights[kind] = list;
		}

		float lift = kind == HighlightKind.Range ? 0.007f : 0.01f + 0.004f * (int)kind;
		ShaderMaterial material = GetHighlightMaterial(kind);
		foreach (GridPos pos in tiles)
		{
			if (pos.X < 0 || pos.Y < 0 || pos.X >= _width || pos.Y >= _height)
			{
				continue;
			}
			Vector3 local = GridToLocal(pos);
			var marker = new MeshInstance3D
			{
				Mesh = _highlightMesh,
				MaterialOverride = material,
				Position = new Vector3(local.X, lift, local.Z),
				CastShadow = GeometryInstance3D.ShadowCastingSetting.Off,
			};
			_highlightRoot.AddChild(marker);
			list.Add(marker);
		}
	}

	/// <summary>Removes all highlights of every kind.</summary>
	public void ClearHighlights()
	{
		foreach (HighlightKind kind in _highlights.Keys)
		{
			FreeList(_highlights[kind]);
		}
		_highlights.Clear();
	}

	/// <summary>Removes all highlights of one kind.</summary>
	public void ClearHighlights(HighlightKind kind)
	{
		if (_highlights.TryGetValue(kind, out List<MeshInstance3D> list))
		{
			FreeList(list);
		}
	}

	public override void _UnhandledInput(InputEvent @event)
	{
		Camera3D camera = GetViewport().GetCamera3D();
		if (camera == null)
		{
			return;
		}

		if (@event is InputEventMouseButton button && button.Pressed && button.ButtonIndex == MouseButton.Left)
		{
			GridPos? pos = PickTile(camera, button.Position);
			if (pos.HasValue)
			{
				EmitSignal(SignalName.TileClicked, pos.Value.ToVector2I());
				GetViewport().SetInputAsHandled();
			}
		}
		else if (@event is InputEventMouseMotion motion)
		{
			GridPos? pos = PickTile(camera, motion.Position);
			Vector2I hovered = pos.HasValue ? pos.Value.ToVector2I() : new Vector2I(-1, -1);
			if (hovered != _hovered)
			{
				_hovered = hovered;
				EmitSignal(SignalName.TileHovered, hovered);
			}
		}
	}

	private Vector3 GridToLocal(GridPos pos)
	{
		float x = (pos.X - (_width - 1) * 0.5f) * TileSize;
		float z = (pos.Y - (_height - 1) * 0.5f) * TileSize;
		return new Vector3(x, IsCrown(pos.X, pos.Y) ? CrownLift : 0f, z);
	}

	/// <summary>True for the crown field's tiles (they stand slightly raised).</summary>
	private bool IsCrown(int x, int y) =>
		_crown.Size.X > 0 && x >= _crown.Position.X && x < _crown.End.X && y >= _crown.Position.Y && y < _crown.End.Y;

	private Material CreateSurfaceMaterial(BoardState board)
	{
		if (TileMaterialTemplate != null)
		{
			return TileMaterialTemplate;
		}
		ShaderMaterial mat = VfxAssets.CreateMaterial("board_surface");
		Rect2I zone = board.ScoringZone;
		mat.SetShaderParameter("board_size", new Vector2(board.Width, board.Height));
		mat.SetShaderParameter("tile_size", TileSize);
		mat.SetShaderParameter("grout_width", 0.01f);
		mat.SetShaderParameter("scoring_rect", new Vector4(zone.Position.X, zone.Position.Y, zone.Size.X, zone.Size.Y));
		Rect2I hot = board.HotZone;
		mat.SetShaderParameter("hot_rect", new Vector4(hot.Position.X, hot.Position.Y, hot.Size.X, hot.Size.Y));
		mat.SetShaderParameter("deploy_rows", (float)board.DeployRows);
		mat.SetShaderParameter("stone_color", NormalColor);
		mat.SetShaderParameter("stone_dark", NormalColor.Darkened(0.45f));
		mat.SetShaderParameter("parchment_color", ScoringZoneColor);
		mat.SetShaderParameter("p0_tint", Player0DeployColor);
		mat.SetShaderParameter("p1_tint", Player1DeployColor);
		mat.SetShaderParameter("rune_color", RuneColor);
		mat.SetShaderParameter("checker", CheckerStrength);
		return mat;
	}

	private void BuildFrame(float w, float h)
	{
		var frame = new Node3D { Name = "Frame" };
		_tileRoot.AddChild(frame);
		float fw = FrameWidth;
		float depth = 0.32f;
		float top = FrameHeight;
		float height = top + depth;
		float cy = top - height * 0.5f;

		ShaderMaterial woodX = CreateWoodMaterial(Vector3.Right);
		ShaderMaterial woodZ = CreateWoodMaterial(Vector3.Back);
		AddBox(frame, "FrameNear", new Vector3(w + 2f * fw, height, fw), new Vector3(0, cy, h * 0.5f + fw * 0.5f), woodX);
		AddBox(frame, "FrameFar", new Vector3(w + 2f * fw, height, fw), new Vector3(0, cy, -h * 0.5f - fw * 0.5f), woodX);
		AddBox(frame, "FrameLeft", new Vector3(fw, height, h), new Vector3(-w * 0.5f - fw * 0.5f, cy, 0), woodZ);
		AddBox(frame, "FrameRight", new Vector3(fw, height, h), new Vector3(w * 0.5f + fw * 0.5f, cy, 0), woodZ);

		// Gold trims: an inner lip around the board and an outer edge.
		StandardMaterial3D gold = VfxAssets.CreateGoldMaterial(0.15f);
		float t = 0.055f;
		float th = 0.05f;
		float ty = top + th * 0.5f - 0.01f;
		AddBox(frame, "TrimInnerNear", new Vector3(w + 2f * t, th, t), new Vector3(0, ty, h * 0.5f + t * 0.5f), gold);
		AddBox(frame, "TrimInnerFar", new Vector3(w + 2f * t, th, t), new Vector3(0, ty, -h * 0.5f - t * 0.5f), gold);
		AddBox(frame, "TrimInnerLeft", new Vector3(t, th, h), new Vector3(-w * 0.5f - t * 0.5f, ty, 0), gold);
		AddBox(frame, "TrimInnerRight", new Vector3(t, th, h), new Vector3(w * 0.5f + t * 0.5f, ty, 0), gold);
		float ow = w + 2f * fw;
		float oh = h + 2f * fw;
		AddBox(frame, "TrimOuterNear", new Vector3(ow, th * 0.7f, t), new Vector3(0, ty, oh * 0.5f - t * 0.5f), gold);
		AddBox(frame, "TrimOuterFar", new Vector3(ow, th * 0.7f, t), new Vector3(0, ty, -oh * 0.5f + t * 0.5f), gold);
		AddBox(frame, "TrimOuterLeft", new Vector3(t, th * 0.7f, oh), new Vector3(-ow * 0.5f + t * 0.5f, ty, 0), gold);
		AddBox(frame, "TrimOuterRight", new Vector3(t, th * 0.7f, oh), new Vector3(ow * 0.5f - t * 0.5f, ty, 0), gold);

		// Corner ornaments with owner-colored gems (near = player 0, far = player 1).
		var capMesh = new CylinderMesh { TopRadius = fw * 0.42f, BottomRadius = fw * 0.5f, Height = 0.1f, RadialSegments = 24, Rings = 1 };
		var gemMesh = new SphereMesh { Radius = fw * 0.22f, Height = fw * 0.3f, RadialSegments = 16, Rings = 8 };
		for (int i = 0; i < 4; i++)
		{
			float sx = (i % 2 == 0) ? -1f : 1f;
			float sz = (i < 2) ? 1f : -1f;
			var pos = new Vector3(sx * (w * 0.5f + fw * 0.5f), top + 0.05f, sz * (h * 0.5f + fw * 0.5f));
			frame.AddChild(new MeshInstance3D { Name = $"Corner{i}", Mesh = capMesh, MaterialOverride = gold, Position = pos });
			Color gemColor = sz > 0f ? Player0DeployColor : Player1DeployColor;
			var gemMat = new StandardMaterial3D
			{
				AlbedoColor = gemColor,
				Metallic = 0.2f,
				Roughness = 0.12f,
				EmissionEnabled = true,
				Emission = gemColor,
				EmissionEnergyMultiplier = 1.6f,
			};
			frame.AddChild(new MeshInstance3D
			{
				Name = $"Gem{i}",
				Mesh = gemMesh,
				MaterialOverride = gemMat,
				Position = pos + new Vector3(0, 0.07f, 0),
				CastShadow = GeometryInstance3D.ShadowCastingSetting.Off,
			});
		}

		// Small gold studs along the long sides.
		var studMesh = new SphereMesh { Radius = 0.045f, Height = 0.05f, RadialSegments = 10, Rings = 5 };
		for (int x = 1; x < _width; x++)
		{
			float px = (x - _width * 0.5f) * TileSize;
			frame.AddChild(new MeshInstance3D { Mesh = studMesh, MaterialOverride = gold, Position = new Vector3(px, top + 0.01f, h * 0.5f + fw * 0.55f) });
			frame.AddChild(new MeshInstance3D { Mesh = studMesh, MaterialOverride = gold, Position = new Vector3(px, top + 0.01f, -h * 0.5f - fw * 0.55f) });
		}
	}

	private void BuildTable()
	{
		ShaderMaterial wood = VfxAssets.CreateMaterial("wood");
		wood.SetShaderParameter("wood_light", TableLight);
		wood.SetShaderParameter("wood_dark", TableDark);
		wood.SetShaderParameter("grain_axis", Vector3.Right);
		wood.SetShaderParameter("plank_width", 1.1f);
		wood.SetShaderParameter("grain_scale", 0.8f);
		wood.SetShaderParameter("roughness_value", 0.6f);
		var table = new MeshInstance3D
		{
			Name = "Table",
			Mesh = new PlaneMesh { Size = new Vector2(80f, 60f) },
			MaterialOverride = wood,
			Position = new Vector3(0, -0.18f, 0),
		};
		_tileRoot.AddChild(table);
	}

	/// <summary>
	/// Table dressing that makes the scene feel physical: a stitched leather play mat under the board, two candles
	/// with flickering light, coin stacks and a closed rule book.
	/// </summary>
	private void BuildProps(float w, float h)
	{
		_candles.Clear();
		var props = new Node3D { Name = "Props" };
		_tileRoot.AddChild(props);
		float fw = FrameWidth;
		float matW = w + 2f * fw + 1.6f;
		float matH = h + 2f * fw + 1.6f;

		var noise = new FastNoiseLite { Frequency = 0.09f, FractalOctaves = 4, Seed = 3 };
		var leather = new StandardMaterial3D
		{
			AlbedoColor = new Color(0.3f, 0.12f, 0.07f),
			Roughness = 0.72f,
			NormalEnabled = true,
			NormalTexture = new NoiseTexture2D { Noise = noise, AsNormalMap = true, BumpStrength = 3f, Width = 512, Height = 512, Seamless = true },
			NormalScale = 0.6f,
			Uv1Scale = new Vector3(3f, 3f, 3f),
		};
		props.AddChild(new MeshInstance3D
		{
			Name = "Mat",
			Mesh = new BoxMesh { Size = new Vector3(matW, 0.03f, matH) },
			MaterialOverride = leather,
			Position = new Vector3(0, -0.165f, 0),
		});
		// Stitching along the mat border.
		var stitch = new StandardMaterial3D { AlbedoColor = new Color(0.82f, 0.68f, 0.42f), Roughness = 0.9f };
		var stitchMesh = new BoxMesh { Size = new Vector3(0.14f, 0.012f, 0.03f) };
		for (float x = -matW * 0.5f + 0.3f; x < matW * 0.5f - 0.2f; x += 0.3f)
		{
			props.AddChild(new MeshInstance3D { Mesh = stitchMesh, MaterialOverride = stitch, Position = new Vector3(x, -0.146f, -matH * 0.5f + 0.18f) });
			props.AddChild(new MeshInstance3D { Mesh = stitchMesh, MaterialOverride = stitch, Position = new Vector3(x, -0.146f, matH * 0.5f - 0.18f) });
		}
		for (float z = -matH * 0.5f + 0.3f; z < matH * 0.5f - 0.2f; z += 0.3f)
		{
			props.AddChild(new MeshInstance3D { Mesh = stitchMesh, MaterialOverride = stitch, Position = new Vector3(-matW * 0.5f + 0.18f, -0.146f, z), Rotation = new Vector3(0, Mathf.Pi / 2f, 0) });
			props.AddChild(new MeshInstance3D { Mesh = stitchMesh, MaterialOverride = stitch, Position = new Vector3(matW * 0.5f - 0.18f, -0.146f, z), Rotation = new Vector3(0, Mathf.Pi / 2f, 0) });
		}

		float sideX = matW * 0.5f + 0.9f;
		AddCandle(props, new Vector3(-sideX, -0.18f, -h * 0.3f), 0.9f);
		AddCandle(props, new Vector3(sideX, -0.18f, -h * 0.3f), 1.1f);
		AddCandle(props, new Vector3(sideX + 0.35f, -0.18f, -h * 0.3f + 0.35f), 0.6f);

		StandardMaterial3D gold = VfxAssets.CreateGoldMaterial(0.05f);
		var coin = new CylinderMesh { TopRadius = 0.16f, BottomRadius = 0.16f, Height = 0.04f, RadialSegments = 20 };
		var rng = new RandomNumberGenerator { Seed = 5 };
		foreach ((Vector3 basePos, int count) in new[] { (new Vector3(-sideX + 0.2f, -0.16f, h * 0.32f), 7), (new Vector3(-sideX - 0.25f, -0.16f, h * 0.32f + 0.3f), 4) })
		{
			for (int i = 0; i < count; i++)
			{
				props.AddChild(new MeshInstance3D
				{
					Mesh = coin,
					MaterialOverride = gold,
					Position = basePos + new Vector3(rng.RandfRange(-0.02f, 0.02f), i * 0.042f, rng.RandfRange(-0.02f, 0.02f)),
				});
			}
		}

		var book = new Node3D { Position = new Vector3(sideX + 0.1f, -0.18f, h * 0.25f), Rotation = new Vector3(0, 0.35f, 0) };
		props.AddChild(book);
		book.AddChild(new MeshInstance3D
		{
			Mesh = new BoxMesh { Size = new Vector3(1.1f, 0.22f, 1.5f) },
			MaterialOverride = new StandardMaterial3D { AlbedoColor = new Color(0.36f, 0.1f, 0.08f), Roughness = 0.6f },
			Position = new Vector3(0, 0.11f, 0),
		});
		book.AddChild(new MeshInstance3D
		{
			Mesh = new BoxMesh { Size = new Vector3(1.0f, 0.16f, 1.44f) },
			MaterialOverride = new StandardMaterial3D { AlbedoColor = new Color(0.92f, 0.86f, 0.72f), Roughness = 0.95f },
			Position = new Vector3(0.04f, 0.11f, 0),
		});
		book.AddChild(new MeshInstance3D
		{
			Mesh = new BoxMesh { Size = new Vector3(0.6f, 0.01f, 0.08f) },
			MaterialOverride = gold,
			Position = new Vector3(0, 0.225f, -0.4f),
		});
	}

	private void AddCandle(Node3D parent, Vector3 basePos, float height)
	{
		var wax = new StandardMaterial3D { AlbedoColor = new Color(0.93f, 0.88f, 0.76f), Roughness = 0.5f, SubsurfScatterEnabled = true, SubsurfScatterStrength = 0.6f };
		parent.AddChild(new MeshInstance3D
		{
			Mesh = new CylinderMesh { TopRadius = 0.13f, BottomRadius = 0.2f, Height = 0.06f, RadialSegments = 16 },
			MaterialOverride = VfxAssets.CreateGoldMaterial(0.03f),
			Position = basePos + new Vector3(0, 0.03f, 0),
		});
		parent.AddChild(new MeshInstance3D
		{
			Mesh = new CylinderMesh { TopRadius = 0.1f, BottomRadius = 0.11f, Height = height, RadialSegments = 16 },
			MaterialOverride = wax,
			Position = basePos + new Vector3(0, 0.06f + height * 0.5f, 0),
		});
		var flameMat = new StandardMaterial3D
		{
			AlbedoColor = new Color(1f, 0.75f, 0.35f),
			EmissionEnabled = true,
			Emission = new Color(1f, 0.6f, 0.2f),
			EmissionEnergyMultiplier = 6f,
			ShadingMode = BaseMaterial3D.ShadingModeEnum.Unshaded,
		};
		var flame = new MeshInstance3D
		{
			Mesh = new SphereMesh { Radius = 0.045f, Height = 0.16f, RadialSegments = 10, Rings = 6 },
			MaterialOverride = flameMat,
			Position = basePos + new Vector3(0, 0.06f + height + 0.08f, 0),
			CastShadow = GeometryInstance3D.ShadowCastingSetting.Off,
		};
		parent.AddChild(flame);
		var light = new OmniLight3D
		{
			LightColor = new Color(1f, 0.66f, 0.32f),
			LightEnergy = 0.9f,
			OmniRange = 4.5f,
			ShadowEnabled = false,
			Position = flame.Position + new Vector3(0, 0.1f, 0),
		};
		parent.AddChild(light);
		_candles.Add((flame, light, (float)GD.RandRange(0.0, 10.0)));
	}

	public override void _Process(double delta)
	{
		_time += (float)delta;
		foreach ((MeshInstance3D flame, OmniLight3D light, float seed) in _candles)
		{
			if (!IsInstanceValid(flame))
			{
				continue;
			}
			float f = 0.85f + 0.1f * Mathf.Sin(_time * 9f + seed) + 0.06f * Mathf.Sin(_time * 23f + seed * 2f);
			light.LightEnergy = 0.9f * f;
			flame.Scale = new Vector3(1f, 0.9f + 0.2f * f, 1f);
		}
	}

	private ShaderMaterial CreateWoodMaterial(Vector3 grainAxis)
	{
		ShaderMaterial wood = VfxAssets.CreateMaterial("wood");
		wood.SetShaderParameter("wood_light", WoodLight);
		wood.SetShaderParameter("wood_dark", WoodDark);
		wood.SetShaderParameter("grain_axis", grainAxis);
		wood.SetShaderParameter("grain_scale", 1.6f);
		return wood;
	}

	private static void AddBox(Node3D parent, string name, Vector3 size, Vector3 pos, Material material)
	{
		parent.AddChild(new MeshInstance3D
		{
			Name = name,
			Mesh = new BoxMesh { Size = size },
			MaterialOverride = material,
			Position = pos,
		});
	}

	private void EnsureRoots()
	{
		if (_tileRoot == null)
		{
			_tileRoot = new Node3D { Name = "Tiles" };
			AddChild(_tileRoot);
		}
		if (_terrain == null)
		{
			_terrain = new TerrainLayer { Name = "Terrain" };
			AddChild(_terrain);
		}
		if (_trapRoot == null)
		{
			_trapRoot = new Node3D { Name = "Traps" };
			AddChild(_trapRoot);
		}
		if (_tileEffects == null)
		{
			_tileEffects = new TileEffectLayer { Name = "TileEffects" };
			_tileEffects.Setup(this);
			AddChild(_tileEffects);
		}
		if (_highlightRoot == null)
		{
			_highlightRoot = new Node3D { Name = "Highlights" };
			AddChild(_highlightRoot);
		}
	}

	private static void FreeList(List<MeshInstance3D> list)
	{
		foreach (MeshInstance3D m in list)
		{
			if (IsInstanceValid(m))
			{
				m.QueueFree();
			}
		}
		list.Clear();
	}

	private ShaderMaterial GetHighlightMaterial(HighlightKind kind)
	{
		if (_highlightMaterials.TryGetValue(kind, out ShaderMaterial mat))
		{
			return mat;
		}
		Color color = kind switch
		{
			HighlightKind.Move => MoveHighlightColor,
			HighlightKind.Attack => AttackHighlightColor,
			HighlightKind.Deploy => DeployHighlightColor,
			HighlightKind.Spell => SpellHighlightColor,
			HighlightKind.Selected => SelectedHighlightColor,
			HighlightKind.Range => RangeHighlightColor,
			_ => HoverHighlightColor,
		};
		int pattern = kind switch
		{
			HighlightKind.Attack => 1,
			HighlightKind.Hover => 2,
			HighlightKind.Selected => 3,
			HighlightKind.Range => 4,
			_ => 0,
		};
		mat = VfxAssets.CreateMaterial("highlight", kind == HighlightKind.Range ? -1 : (int)kind);
		mat.SetShaderParameter("color", color);
		mat.SetShaderParameter("pattern", pattern);
		mat.SetShaderParameter("pulse_speed", kind == HighlightKind.Hover ? 5f : 3f);
		_highlightMaterials[kind] = mat;
		return mat;
	}
}
