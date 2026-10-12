using System;
using System.Collections.Generic;
using Godot;

namespace Realmshatter;

/// <summary>
/// Draws order indicators on the board: a move arrow along the orthogonal path, a curved attack
/// arrow (red, or gold when it would hit an own piece) with a target reticle, and a numbered badge
/// (resolution order) over the piece. One extra, brighter "preview" set shows the order being planned.
/// Also draws predicted attack consequences (ShowAttackPreview: Arc / Pierce / Echo hits, damage numbers incl. friendly fire, kills,
/// pushes, pierce lines, new tile effects) and tile-spell area ghosts (ShowSpellAreaPreview).
/// Place it anywhere at the world origin (e.g. as a child of Main or the BoardView).
/// </summary>
public partial class OrderOverlay : Node3D
{
	[ExportGroup("Colors")]
	[Export] public Color MoveColor { get; set; } = new Color(0.35f, 0.8f, 1.0f);
	[Export] public Color AttackColor { get; set; } = new Color(1.0f, 0.26f, 0.18f);
	[Export] public Color ChainColor { get; set; } = new Color(1.0f, 0.76f, 0.2f);
	[Export] public Color BadgeColor { get; set; } = new Color(0.14f, 0.22f, 0.5f);
	[Export] public Color PushColor { get; set; } = new Color(1.0f, 0.62f, 0.3f);
	[Export] public Color PierceColor { get; set; } = new Color(0.85f, 0.93f, 1.0f);
	[Export] public Color HealColor { get; set; } = new Color(0.45f, 1.0f, 0.5f);
	[Export] public Color DamageSplatColor { get; set; } = new Color(0.85f, 0.1f, 0.08f);
	[Export] public Color ShieldSplatColor { get; set; } = new Color(0.75f, 0.6f, 0.25f);
	[Export] public Color FrostColor { get; set; } = new Color(0.55f, 0.85f, 1.0f);

	[ExportGroup("Shape")]
	[Export] public float ArrowWidth { get; set; } = 0.2f;
	[Export] public float HeadLength { get; set; } = 0.32f;
	[Export] public float HeadWidth { get; set; } = 0.48f;
	[Export] public float ArrowHeight { get; set; } = 0.07f;
	[Export] public float AttackArcHeight { get; set; } = 0.42f;
	[Export] public float CornerRadius { get; set; } = 0.32f;
	[Export] public float BadgeSize { get; set; } = 0.34f;
	/// <summary>Height of predicted damage numbers above the victim's tile.</summary>
	[Export] public float PreviewNumberHeight { get; set; } = 0.95f;
	/// <summary>Extra height of predicted secondary / pierce shot lines so they pass over the tokens.</summary>
	[Export] public float ShotLineHeight { get; set; } = 0.2f;

	private Node3D _ordersRoot;
	private Node3D _previewRoot;
	private Node3D _attackRoot;
	private Node3D _spellRoot;
	private readonly Dictionary<int, Node3D> _orderGroups = new Dictionary<int, Node3D>();
	private GameState _state;
	private int _previewPieceId = -1;
	private Func<Piece, GridPos, IReadOnlyList<GridPos>> _pathProvider;

	public override void _Ready()
	{
		EnsureRoots();
	}

	/// <summary>Remembers the game state used for path finding and friendly-fire detection in previews.</summary>
	public void SetState(GameState state)
	{
		_state = state;
	}

	/// <summary>Redraws the committed orders of every current-player piece.</summary>
	public void ShowOrders(GameState state, BoardView board)
	{
		ShowOrders(state, board, _pathProvider);
	}

	/// <summary>
	/// Redraws the committed orders of every current-player piece. pathProvider(piece, target) returns the
	/// rules path (tiles after the piece, ending with target), e.g. TurnController.GetPlannedPath; it is also
	/// remembered for later ShowPreview calls without an explicit path. Null = built-in v3 path finding.
	/// </summary>
	public void ShowOrders(GameState state, BoardView board, Func<Piece, GridPos, IReadOnlyList<GridPos>> pathProvider)
	{
		EnsureRoots();
		_state = state ?? _state;
		_pathProvider = pathProvider;
		ClearChildren(_ordersRoot);
		_orderGroups.Clear();
		if (state == null || board == null)
		{
			return;
		}
		// Actions resolve immediately, so there are no committed orders left to draw.
	}

	/// <summary>
	/// Shows the order currently being planned for a piece (brighter, animated). Hides that piece's
	/// committed order until ClearPreview. occupancy defaults to the state of the last ShowOrders/SetState.
	/// </summary>
	public void ShowPreview(Piece piece, GridPos? move, GridPos? attack, BoardView board, BoardState occupancy = null)
	{
		IReadOnlyList<GridPos> path = piece != null && move.HasValue && _pathProvider != null ? _pathProvider(piece, move.Value) : null;
		ShowPreview(piece, move, attack, board, path, occupancy);
	}

	/// <summary>
	/// ShowPreview with an explicit move path (tiles after the piece, ending with the move target, as returned by
	/// TurnController.GetPlannedPath). Null or empty = path finding fallback.
	/// </summary>
	public void ShowPreview(Piece piece, GridPos? move, GridPos? attack, BoardView board, IReadOnlyList<GridPos> path, BoardState occupancy = null)
	{
		EnsureRoots();
		ClearPreview();
		if (piece == null || board == null)
		{
			return;
		}
		_previewPieceId = piece.Id;
		if (_orderGroups.TryGetValue(piece.Id, out Node3D committed) && IsInstanceValid(committed))
		{
			committed.Visible = false;
		}
		BoardState boardState = occupancy ?? _state?.Board;
		BuildGroup(_previewRoot, piece, move, attack, board, boardState, true, PreviewNumber(piece), path);
	}

	/// <summary>Removes the planning preview and shows the piece's committed order again.</summary>
	public void ClearPreview()
	{
		EnsureRoots();
		ClearChildren(_previewRoot);
		if (_previewPieceId >= 0 && _orderGroups.TryGetValue(_previewPieceId, out Node3D committed) && IsInstanceValid(committed))
		{
			committed.Visible = true;
		}
		_previewPieceId = -1;
	}

	/// <summary>Removes all order indicators and every preview (planning, attack and spell area).</summary>
	public void ClearAll()
	{
		EnsureRoots();
		ClearChildren(_ordersRoot);
		ClearChildren(_previewRoot);
		ClearChildren(_attackRoot);
		ClearChildren(_spellRoot);
		_orderGroups.Clear();
		_previewPieceId = -1;
	}

	// ------------------------------------------------------------------ attack consequences preview

	/// <summary>
	/// Draws the predicted consequences of one attack (TurnController.PredictAttack): Arc zaps / Echo strikes are
	/// dashed lightning arrows (gold = hits an own piece, red = an enemy), predicted damage numbers float above
	/// victims (friendly fire included, skull if lethal), heals (+N),
	/// Frost (snowflake), push arrows / blocked pushes, Pierce lines and ghost tiles for new tile effects.
	/// The direct attack arc itself is drawn by ShowPreview. Replaces the previous attack preview.
	/// </summary>
	public void ShowAttackPreview(ChainPreview preview, BoardView board, GameState state)
	{
		EnsureRoots();
		ClearAttackPreview();
		if (preview == null || !preview.IsValid || board == null)
		{
			return;
		}
		state ??= _state;
		var lift = new Vector3(0f, ArrowHeight + 0.02f, 0f);
		var victims = new Dictionary<int, (GridPos Tile, int Hp, int Shield, int Heal, bool Frozen, bool Friendly)>();
		var victimOrder = new List<int>();

		foreach (PredictedHit hit in preview.Hits)
		{
			Vector3 a = Local(board.GridToWorld(hit.From)) + lift;
			Vector3 b = Local(board.GridToWorld(hit.Tile)) + lift;
			bool hasTarget = hit.TargetPieceId >= 0;
			Color color = hit.IsFriendly ? ChainColor : AttackColor;
			if (hit.IsPierce)
			{
				AddPierceLine(a, b, hasTarget);
			}
			else if (hit.IsSecondary && hasTarget)
			{
				AddLightningArrow(a, b, color);
			}
			if (hasTarget && (hit.IsSecondary || hit.IsPierce))
			{
				AddMarker(_attackRoot, b + new Vector3(0, -0.035f, 0), color, 0, true);
			}
			if (!hasTarget)
			{
				continue;
			}
			if (!victims.TryGetValue(hit.TargetPieceId, out var v))
			{
				v = (hit.Tile, 0, 0, 0, false, hit.IsFriendly);
				victimOrder.Add(hit.TargetPieceId);
			}
			v.Hp += hit.HpLost;
			v.Shield += hit.ShieldAbsorbed;
			v.Heal += hit.Healed;
			v.Frozen |= (hit.Effects & HitEffect.Frozen) != 0;
			victims[hit.TargetPieceId] = v;
		}

		foreach (ResolutionEvent e in preview.Events)
		{
			if (e.Type == ResolutionEventType.Pushed)
			{
				AddPushArrow(Local(board.GridToWorld(e.From)) + lift, Local(board.GridToWorld(e.To)) + lift, false);
			}
			else if (e.Type == ResolutionEventType.PushBlocked)
			{
				Vector3 a = Local(board.GridToWorld(e.From)) + lift;
				Vector3 b = Local(board.GridToWorld(e.To)) + lift;
				AddPushArrow(a, a.Lerp(b, 0.62f), true);
			}
		}

		foreach (TileEffect effect in preview.NewTileEffects)
		{
			AddGhostTile(_attackRoot, board, effect.Position, effect.Type);
		}

		var killed = new HashSet<int>(preview.KilledPieceIds);
		foreach (int id in victimOrder)
		{
			var v = victims[id];
			Vector3 top = Local(board.GridToWorld(v.Tile)) + new Vector3(0f, PreviewNumberHeight, 0f);
			bool lethal = killed.Contains(id);
			if (v.Hp > 0 || v.Shield > 0)
			{
				AddDamageNumber(top, v.Hp > 0 ? $"-{v.Hp}" : $"-{v.Shield}", v.Hp > 0 ? DamageSplatColor : ShieldSplatColor, lethal);
			}
			else if (lethal)
			{
				AddDamageNumber(top, "", DamageSplatColor, true);
			}
			if (v.Heal > 0)
			{
				AddFloatingLabel(top + new Vector3(0f, v.Hp > 0 ? 0.36f : 0f, 0f), $"+{v.Heal}", HealColor, 64);
			}
			if (v.Frozen && !lethal)
			{
				AddIcon(top + new Vector3(-0.36f, -0.05f, 0f), FxIconShape.Snowflake, new Color(0.9f, 0.97f, 1f), new Color(0.2f, 0.5f, 0.85f, 0.95f), 0.28f);
			}
			if (lethal && state?.GetPiece(id) is Piece victim)
			{
				AddTileTint(Local(board.GridToWorld(v.Tile)), new Color(1f, 0.15f, 0.1f, 0.5f), victim.OwnerIndex);
			}
		}
	}

	/// <summary>Removes the attack consequences preview.</summary>
	public void ClearAttackPreview()
	{
		EnsureRoots();
		ClearChildren(_attackRoot);
	}

	/// <summary>
	/// Shows translucent ghosts of the tile effect a tile/area spell would create (lava, wall, healing runes) on
	/// the given tiles; type null/None shows violet target tiles. If occupancy is given, walls are not shown on
	/// occupied tiles (they cannot be placed there). Replaces the previous spell area preview.
	/// </summary>
	public void ShowSpellAreaPreview(IEnumerable<GridPos> tiles, TileEffectType? type, BoardView board, BoardState occupancy = null)
	{
		EnsureRoots();
		ClearSpellAreaPreview();
		if (tiles == null || board == null)
		{
			return;
		}
		TileEffectType t = type ?? TileEffectType.None;
		foreach (GridPos pos in tiles)
		{
			if (t != TileEffectType.None && occupancy != null && occupancy.IsInHotZone(pos))
			{
				continue; // tile effects never land on the crown field
			}
			if (t == TileEffectType.Wall && occupancy != null && occupancy.IsOccupied(pos))
			{
				AddIcon(Local(board.GridToWorld(pos)) + new Vector3(0, 0.6f, 0), FxIconShape.Cross, new Color(1f, 0.4f, 0.3f), new Color(0.15f, 0.05f, 0.04f, 0.85f), 0.3f, _spellRoot);
				continue;
			}
			AddGhostTile(_spellRoot, board, pos, t);
		}
	}

	/// <summary>Removes the spell area preview.</summary>
	public void ClearSpellAreaPreview()
	{
		EnsureRoots();
		ClearChildren(_spellRoot);
	}

	// ------------------------------------------------------------------ order groups

	private static int PreviewNumber(Piece piece) => 0;

	private Node3D BuildGroup(Node3D parent, Piece piece, GridPos? move, GridPos? attack, BoardView board,
		BoardState occupancy, bool preview, int number, IReadOnlyList<GridPos> rulesPath = null)
	{
		var group = new Node3D { Name = $"Order_{piece.Id}" };
		parent.AddChild(group);
		GridPos start = piece.Position;
		GridPos from = move ?? start;
		var lift = new Vector3(0f, ArrowHeight, 0f);

		if (move.HasValue && move.Value != start)
		{
			List<GridPos> path;
			if (rulesPath != null && rulesPath.Count > 0)
			{
				path = new List<GridPos> { start };
				path.AddRange(rulesPath);
			}
			else
			{
				path = FindRulesPath(occupancy, piece, start, move.Value) ?? FindPath(occupancy, start, move.Value) ?? StraightPath(start, move.Value);
			}
			var points = new List<Vector3>(path.Count);
			foreach (GridPos p in path)
			{
				points.Add(Local(board.GridToWorld(p)) + lift);
			}
			List<Vector3> rounded = ArrowMeshBuilder.RoundCorners(points, CornerRadius);
			AddArrow(group, ArrowMeshBuilder.Trim(rounded, 0.34f, 0.1f), MoveColor, preview);
			AddMarker(group, Local(board.GridToWorld(move.Value)) + new Vector3(0, ArrowHeight - 0.02f, 0), MoveColor, 1, preview);

			// Ending on a friendly pushes it one tile along the last step.
			Piece occupant = occupancy?.GetPieceAt(move.Value);
			if (occupant != null && occupant.Id != piece.Id && occupant.OwnerIndex == piece.OwnerIndex && path.Count >= 2)
			{
				GridPos dir = path[path.Count - 1] - path[path.Count - 2];
				GridPos dest = move.Value + dir;
				bool blocked = !occupancy.IsPassable(dest) || (occupancy.GetPieceAt(dest) is Piece o && o.OwnerIndex != piece.OwnerIndex);
				Vector3 a = Local(board.GridToWorld(move.Value)) + lift;
				Vector3 b = Local(board.GridToWorld(dest)) + lift;
				AddPushArrow(group, a, blocked ? a.Lerp(b, 0.62f) : b, blocked);
			}
		}

		if (attack.HasValue)
		{
			Piece target = occupancy?.GetPieceAt(attack.Value);
			bool chain = target != null && target.OwnerIndex == piece.OwnerIndex && target.Id != piece.Id;
			Color color = chain ? ChainColor : AttackColor;
			Vector3 a = Local(board.GridToWorld(from)) + lift;
			Vector3 b = Local(board.GridToWorld(attack.Value)) + lift;
			float dist = a.DistanceTo(b);
			float height = AttackArcHeight * Mathf.Clamp(dist * 0.5f, 0.6f, 1.6f);
			List<Vector3> arc = ArrowMeshBuilder.Arc(a, b, height, 0.15f);
			AddArrow(group, ArrowMeshBuilder.Trim(arc, 0.3f, 0.3f), color, preview);
			AddMarker(group, b + new Vector3(0, -0.015f, 0), color, 0, preview);
		}

		if (number > 0)
		{
			AddNumberBadge(group, Local(board.GridToWorld(start)), number, preview);
		}
		return group;
	}

	private void AddArrow(Node3D group, List<Vector3> points, Color color, bool preview, float dash = 0f, float widthScale = 1f)
	{
		float width = (preview ? ArrowWidth * 1.15f : ArrowWidth) * widthScale;
		float headWidth = (preview ? HeadWidth * 1.1f : HeadWidth) * widthScale;
		ArrayMesh mesh = ArrowMeshBuilder.BuildArrow(points, width, HeadLength * Mathf.Max(0.6f, widthScale), headWidth);
		if (mesh == null)
		{
			return;
		}
		ShaderMaterial mat = VfxAssets.CreateMaterial("order_arrow", preview ? 9 : 8);
		mat.SetShaderParameter("color", color);
		mat.SetShaderParameter("speed", preview ? 2.4f : 0.8f);
		mat.SetShaderParameter("energy", preview ? 2.4f : 1.2f);
		mat.SetShaderParameter("opacity", preview ? 1.0f : 0.82f);
		mat.SetShaderParameter("pulse", preview ? 1.0f : 0.0f);
		mat.SetShaderParameter("dash", dash);
		group.AddChild(new MeshInstance3D
		{
			Mesh = mesh,
			MaterialOverride = mat,
			CastShadow = GeometryInstance3D.ShadowCastingSetting.Off,
		});
	}

	private static void AddMarker(Node3D group, Vector3 localPos, Color color, int pattern, bool preview)
	{
		ShaderMaterial mat = VfxAssets.CreateMaterial("reticle", 7);
		mat.SetShaderParameter("color", color);
		mat.SetShaderParameter("pattern", pattern);
		mat.SetShaderParameter("opacity", preview ? 1.0f : 0.75f);
		mat.SetShaderParameter("spin", pattern == 0 ? (preview ? 2.2f : 1.0f) : 0.6f);
		group.AddChild(new MeshInstance3D
		{
			Mesh = new PlaneMesh { Size = new Vector2(0.95f, 0.95f) },
			MaterialOverride = mat,
			Position = localPos,
			CastShadow = GeometryInstance3D.ShadowCastingSetting.Off,
		});
	}

	private void AddNumberBadge(Node3D group, Vector3 pieceLocal, int number, bool preview)
	{
		var root = new Node3D { Name = "OrderNumber", Position = pieceLocal + new Vector3(0.36f, 0.24f, -0.37f) };
		group.AddChild(root);
		MeshInstance3D badge = VfxAssets.CreateBadge(3, BadgeSize, preview ? BadgeColor.Lightened(0.25f) : BadgeColor, 34);
		root.AddChild(badge);
		Label3D label = VfxAssets.CreateLabel(number.ToString(), 64, 0.0027f * BadgeSize / 0.26f, Colors.White, 12, 36);
		root.AddChild(label);
		if (preview)
		{
			Tween tween = root.CreateTween().SetLoops();
			tween.TweenProperty(root, "scale", Vector3.One * 1.15f, 0.35f).SetTrans(Tween.TransitionType.Sine);
			tween.TweenProperty(root, "scale", Vector3.One, 0.35f).SetTrans(Tween.TransitionType.Sine);
		}
	}

	// ------------------------------------------------------------------ attack preview parts

	private void AddLightningArrow(Vector3 a, Vector3 b, Color color)
	{
		float dist = a.DistanceTo(b);
		int segments = Mathf.Max(4, Mathf.RoundToInt(dist * 5f));
		var up = new Vector3(0f, ShotLineHeight, 0f);
		List<Vector3> zig = ArrowMeshBuilder.Zigzag(a + up, b + up, 0.08f, segments, a.X * 3.1f + a.Z * 1.7f);
		AddArrow(_attackRoot, ArrowMeshBuilder.Trim(zig, 0.32f, 0.3f), color, true, 3.2f, 0.75f);
	}

	private void AddPierceLine(Vector3 a, Vector3 b, bool hasTarget)
	{
		Vector3 dir = b - a;
		Vector3 end = b + (dir.LengthSquared() > 0.0001f ? dir.Normalized() * 0.2f : Vector3.Zero);
		var up = new Vector3(0f, ShotLineHeight + 0.04f, 0f);
		var line = new List<Vector3> { a + up, end + up };
		AddArrow(_attackRoot, ArrowMeshBuilder.Trim(line, 0.3f, 0f), hasTarget ? PierceColor : PierceColor.Darkened(0.3f), true, 0f, 0.45f);
	}

	private void AddPushArrow(Vector3 a, Vector3 b, bool blocked)
	{
		AddPushArrow(_attackRoot, a, b, blocked);
	}

	private void AddPushArrow(Node3D parent, Vector3 a, Vector3 b, bool blocked)
	{
		var line = new List<Vector3> { a + new Vector3(0, 0.06f, 0), b + new Vector3(0, 0.06f, 0) };
		var group = new Node3D { Name = blocked ? "PushBlocked" : "Push" };
		parent.AddChild(group);
		AddArrow(group, ArrowMeshBuilder.Trim(line, 0.22f, blocked ? 0f : 0.12f), blocked ? PushColor.Darkened(0.25f) : PushColor, true, 0f, 0.85f);
		if (blocked)
		{
			AddIcon(b + new Vector3(0, 0.3f, 0), FxIconShape.Cross, new Color(1f, 0.45f, 0.35f), new Color(0.15f, 0.05f, 0.04f, 0.85f), 0.26f, group);
		}
	}

	private void AddTriggerGlow(Vector3 tileLocal)
	{
		ShaderMaterial mat = VfxAssets.CreateMaterial("highlight", 6);
		mat.SetShaderParameter("color", new Color(ChainColor.R, ChainColor.G, ChainColor.B, 0.85f));
		mat.SetShaderParameter("pattern", 3);
		mat.SetShaderParameter("pulse_speed", 6f);
		mat.SetShaderParameter("energy", 3f);
		_attackRoot.AddChild(new MeshInstance3D
		{
			Name = "TriggerGlow",
			Mesh = new PlaneMesh { Size = new Vector2(1f, 1f) },
			MaterialOverride = mat,
			Position = tileLocal + new Vector3(0, 0.035f, 0),
			CastShadow = GeometryInstance3D.ShadowCastingSetting.Off,
		});
		var glow = new MeshInstance3D { Mesh = VfxAssets.GlowQuad, Scale = Vector3.One * 1.3f, Position = tileLocal + new Vector3(0, 0.35f, 0), CastShadow = GeometryInstance3D.ShadowCastingSetting.Off };
		glow.SetInstanceShaderParameter("tint", new Color(ChainColor.R, ChainColor.G, ChainColor.B, 0.35f));
		_attackRoot.AddChild(glow);
		AddIcon(tileLocal + new Vector3(0.36f, 0.62f, -0.3f), FxIconShape.Bolt, new Color(1f, 0.95f, 0.6f), new Color(0.55f, 0.35f, 0.05f, 0.95f), 0.26f);
	}

	private void AddTileTint(Vector3 tileLocal, Color color, int ownerIndex)
	{
		ShaderMaterial mat = VfxAssets.CreateMaterial("highlight", 5);
		mat.SetShaderParameter("color", color);
		mat.SetShaderParameter("pattern", 1);
		mat.SetShaderParameter("pulse_speed", 5f + ownerIndex * 0.01f);
		_attackRoot.AddChild(new MeshInstance3D
		{
			Mesh = new PlaneMesh { Size = new Vector2(1f, 1f) },
			MaterialOverride = mat,
			Position = tileLocal + new Vector3(0, 0.03f, 0),
			CastShadow = GeometryInstance3D.ShadowCastingSetting.Off,
		});
	}

	private void AddDamageNumber(Vector3 localPos, string text, Color splat, bool lethal)
	{
		var root = new Node3D { Name = "PredictedDamage", Position = localPos };
		_attackRoot.AddChild(root);
		if (!string.IsNullOrEmpty(text))
		{
			MeshInstance3D badge = VfxAssets.CreateBadge(4, 0.6f, splat, 40);
			root.AddChild(badge);
			root.AddChild(VfxAssets.CreateLabel(text, 80, 0.0036f, Colors.White, 16, 42));
		}
		if (lethal)
		{
			float x = string.IsNullOrEmpty(text) ? 0f : 0.4f;
			MeshInstance3D skull = VfxAssets.CreateIcon((int)FxIconShape.Skull, 0.4f, new Color(0.97f, 0.94f, 0.88f), new Color(0.35f, 0.04f, 0.03f, 0.95f), true, 43);
			skull.Position = new Vector3(x, 0.02f, 0f);
			root.AddChild(skull);
		}
		Tween tween = root.CreateTween().SetLoops();
		tween.TweenProperty(root, "scale", Vector3.One * 1.1f, 0.4f).SetTrans(Tween.TransitionType.Sine);
		tween.TweenProperty(root, "scale", Vector3.One, 0.4f).SetTrans(Tween.TransitionType.Sine);
	}

	private void AddFloatingLabel(Vector3 localPos, string text, Color color, int size)
	{
		Label3D label = VfxAssets.CreateLabel(text, size, 0.0036f, color, 16, 42);
		label.Position = localPos;
		_attackRoot.AddChild(label);
	}

	private void AddIcon(Vector3 localPos, FxIconShape shape, Color fg, Color bg, float size, Node3D parent = null)
	{
		MeshInstance3D icon = VfxAssets.CreateIcon((int)shape, size, fg, bg, true, 41);
		icon.Position = localPos;
		(parent ?? _attackRoot).AddChild(icon);
	}

	private void AddGhostTile(Node3D parent, BoardView board, GridPos pos, TileEffectType type)
	{
		var ghost = new TileEffectVisual();
		ghost.Setup(type, board.TileSize, true, pos.X * 1.37f + pos.Y * 2.11f);
		parent.AddChild(ghost);
		ghost.Position = Local(board.GridToWorld(pos));
		_ = ghost.PlayAppear();
	}

	// ------------------------------------------------------------------ path finding

	/// <summary>v3 move rules path (friendlies passable, enemies/walls block), start..goal inclusive, or null.</summary>
	private static List<GridPos> FindRulesPath(BoardState board, Piece piece, GridPos start, GridPos goal)
	{
		if (board == null || piece == null || !board.IsInside(goal))
		{
			return null;
		}
		List<GridPos> tail = board.FindPath(start, goal, 64, piece.OwnerIndex);
		if (tail == null || tail.Count == 0)
		{
			return null;
		}
		var path = new List<GridPos> { start };
		path.AddRange(tail);
		return path;
	}

	/// <summary>Orthogonal shortest path (start..goal inclusive) around occupied tiles, preferring straight runs.</summary>
	private static List<GridPos> FindPath(BoardState board, GridPos start, GridPos goal)
	{
		if (board == null || !board.IsInside(goal))
		{
			return null;
		}
		var dist = new Dictionary<GridPos, int> { [start] = 0 };
		var queue = new Queue<GridPos>();
		queue.Enqueue(start);
		while (queue.Count > 0)
		{
			GridPos cur = queue.Dequeue();
			if (cur == goal)
			{
				break;
			}
			foreach (GridPos n in cur.Neighbors())
			{
				if (!board.IsInside(n) || dist.ContainsKey(n) || (board.IsOccupied(n) && n != goal))
				{
					continue;
				}
				dist[n] = dist[cur] + 1;
				queue.Enqueue(n);
			}
		}
		if (!dist.ContainsKey(goal))
		{
			return null;
		}

		var path = new List<GridPos> { goal };
		GridPos current = goal;
		GridPos lastDir = new GridPos(0, 0);
		int guard = 0;
		while (current != start && guard++ < 256)
		{
			int want = dist[current] - 1;
			GridPos best = current;
			bool found = false;
			foreach (GridPos d in GridPos.OrthogonalDirections)
			{
				GridPos n = current + d;
				if (!dist.TryGetValue(n, out int nd) || nd != want)
				{
					continue;
				}
				if (!found || d == lastDir)
				{
					best = n;
					found = true;
					if (d == lastDir)
					{
						break;
					}
				}
			}
			if (!found)
			{
				return null;
			}
			lastDir = best - current;
			current = best;
			path.Add(current);
		}
		path.Reverse();
		return path;
	}

	private static List<GridPos> StraightPath(GridPos start, GridPos goal)
	{
		var path = new List<GridPos> { start };
		if (start.X != goal.X)
		{
			path.Add(new GridPos(goal.X, start.Y));
		}
		if (start.Y != goal.Y || path[path.Count - 1] != goal)
		{
			path.Add(goal);
		}
		return path;
	}

	private Vector3 Local(Vector3 world) => IsInsideTree() ? ToLocal(world) : world;

	private void EnsureRoots()
	{
		if (_ordersRoot == null)
		{
			_ordersRoot = new Node3D { Name = "Orders" };
			AddChild(_ordersRoot);
		}
		if (_previewRoot == null)
		{
			_previewRoot = new Node3D { Name = "Preview" };
			AddChild(_previewRoot);
		}
		if (_attackRoot == null)
		{
			_attackRoot = new Node3D { Name = "AttackPreview" };
			AddChild(_attackRoot);
		}
		if (_spellRoot == null)
		{
			_spellRoot = new Node3D { Name = "SpellPreview" };
			AddChild(_spellRoot);
		}
	}

	private static void ClearChildren(Node node)
	{
		foreach (Node child in node.GetChildren())
		{
			child.QueueFree();
		}
	}
}
