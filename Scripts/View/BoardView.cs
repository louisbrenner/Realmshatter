using System.Collections.Generic;
using System.Threading.Tasks;
using Godot;

namespace ProjectClaude;

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
	[Export] public float TileGap { get; set; } = 0.06f;
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

	private readonly Dictionary<HighlightKind, List<MeshInstance3D>> _highlights = new Dictionary<HighlightKind, List<MeshInstance3D>>();
	private readonly Dictionary<HighlightKind, ShaderMaterial> _highlightMaterials = new Dictionary<HighlightKind, ShaderMaterial>();

	private Node3D _tileRoot;
	private Node3D _highlightRoot;
	private TileEffectLayer _tileEffects;
	private PlaneMesh _highlightMesh;
	private int _width = 10;
	private int _height = 8;
	private Vector2I _hovered = new Vector2I(-1, -1);

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
		_height = board.Height;
		float w = _width * TileSize;
		float h = _height * TileSize;

		var surface = new MeshInstance3D
		{
			Name = "Surface",
			Mesh = new PlaneMesh { Size = new Vector2(w, h) },
			MaterialOverride = CreateSurfaceMaterial(board),
			CastShadow = GeometryInstance3D.ShadowCastingSetting.Off,
		};
		_tileRoot.AddChild(surface);

		var baseInstance = new MeshInstance3D
		{
			Name = "BoardBase",
			Mesh = new BoxMesh { Size = new Vector3(w + 0.1f, TileThickness, h + 0.1f) },
			MaterialOverride = new StandardMaterial3D { AlbedoColor = BaseColor, Roughness = 0.9f },
			Position = new Vector3(0, -TileThickness * 0.5f - 0.005f, 0),
		};
		_tileRoot.AddChild(baseInstance);

		if (BuildDecoration)
		{
			BuildFrame(w, h);
			BuildTable();
		}

		_highlightMesh = new PlaneMesh { Size = new Vector2(TileSize, TileSize) };
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

		float lift = 0.01f + 0.004f * (int)kind;
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
		return new Vector3(x, 0f, z);
	}

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
		mat.SetShaderParameter("grout_width", Mathf.Clamp(TileGap / Mathf.Max(0.01f, TileSize), 0.01f, 0.3f));
		mat.SetShaderParameter("scoring_rect", new Vector4(zone.Position.X, zone.Position.Y, zone.Size.X, zone.Size.Y));
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
			_ => HoverHighlightColor,
		};
		int pattern = kind switch
		{
			HighlightKind.Attack => 1,
			HighlightKind.Hover => 2,
			HighlightKind.Selected => 3,
			_ => 0,
		};
		mat = VfxAssets.CreateMaterial("highlight", (int)kind);
		mat.SetShaderParameter("color", color);
		mat.SetShaderParameter("pattern", pattern);
		mat.SetShaderParameter("pulse_speed", kind == HighlightKind.Hover ? 5f : 3f);
		_highlightMaterials[kind] = mat;
		return mat;
	}
}
