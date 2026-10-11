using System;
using System.Collections.Generic;
using Godot;

namespace ProjectClaude;

/// <summary>
/// Floating status icons above pieces (Frozen = snowflake on an ice coin plus a frost ring on the ground,
/// Overcharged = crackling bolt on a violet coin). Independent of PieceView: markers follow the piece views
/// returned by ViewResolver every frame (so they ride along with move animations) and fall back to the
/// piece's tile. BoardAnimator creates one automatically (BoardAnimator.StatusMarkers) and syncs it in SyncAll.
/// </summary>
public partial class StatusMarkerLayer : Node3D
{
	private sealed class Marker
	{
		public Node3D Root;
		public Node3D IconRow;
		public MeshInstance3D FrostRing;
		public readonly Dictionary<StatusEffectType, Node3D> Icons = new Dictionary<StatusEffectType, Node3D>();
		public Vector3 Fallback;
		public float Phase;
	}

	private static readonly Color FrozenFg = new Color(0.9f, 0.97f, 1f);
	private static readonly Color FrozenBg = new Color(0.2f, 0.5f, 0.85f, 0.95f);
	private static readonly Color ChargeFg = new Color(1f, 0.95f, 0.55f);
	private static readonly Color ChargeBg = new Color(0.42f, 0.22f, 0.75f, 0.95f);

	private readonly Dictionary<int, Marker> _markers = new Dictionary<int, Marker>();
	private float _time;

	/// <summary>Returns the node (usually the PieceView) a piece's marker follows, or null.</summary>
	public Func<int, Node3D> ViewResolver { get; set; }

	/// <summary>Height of the icon row above the piece origin.</summary>
	[Export] public float IconHeight { get; set; } = 0.5f;

	/// <summary>Offset of the icon row toward the far (-Z) edge of the tile, so it does not cover the portrait in 2D.</summary>
	[Export] public float IconBackOffset { get; set; } = 0.44f;

	[Export] public float IconSize { get; set; } = 0.3f;

	/// <summary>Shows exactly the statuses of the living pieces in the state (pops new icons in, fades removed ones).</summary>
	public void Sync(GameState state, BoardView board)
	{
		if (state == null)
		{
			return;
		}
		var alive = new HashSet<int>();
		foreach (Piece piece in state.Pieces)
		{
			alive.Add(piece.Id);
			Vector3 fallback = board != null ? board.GridToWorld(piece.Position) : new Vector3(piece.Position.X, 0f, piece.Position.Y);
			foreach (StatusEffectType type in new[] { StatusEffectType.Frozen, StatusEffectType.Overcharged })
			{
				SetStatus(piece.Id, type, piece.HasStatus(type), fallback, true);
			}
			if (_markers.TryGetValue(piece.Id, out Marker m))
			{
				m.Fallback = fallback;
			}
		}
		var stale = new List<int>();
		foreach (int id in _markers.Keys)
		{
			if (!alive.Contains(id))
			{
				stale.Add(id);
			}
		}
		foreach (int id in stale)
		{
			RemovePiece(id);
		}
	}

	/// <summary>Adds or removes one status icon for a piece (used while events are played).</summary>
	public void SetStatus(int pieceId, StatusEffectType type, bool active, Vector3? fallbackWorld = null, bool animate = true)
	{
		if (type == StatusEffectType.None)
		{
			return;
		}
		_markers.TryGetValue(pieceId, out Marker marker);
		if (active)
		{
			if (marker == null)
			{
				marker = CreateMarker(pieceId, fallbackWorld ?? Vector3.Zero);
			}
			if (fallbackWorld.HasValue)
			{
				marker.Fallback = fallbackWorld.Value;
			}
			if (marker.Icons.ContainsKey(type))
			{
				return;
			}
			Node3D icon = CreateIcon(type);
			marker.IconRow.AddChild(icon);
			marker.Icons[type] = icon;
			if (type == StatusEffectType.Frozen)
			{
				marker.FrostRing.Visible = true;
				if (animate)
				{
					marker.FrostRing.Scale = Vector3.One * 0.2f;
					marker.FrostRing.CreateTween().TweenProperty(marker.FrostRing, "scale", Vector3.One, 0.3f)
						.SetTrans(Tween.TransitionType.Back).SetEase(Tween.EaseType.Out);
				}
			}
			if (animate)
			{
				icon.Scale = Vector3.One * 0.1f;
				Tween t = icon.CreateTween();
				t.TweenProperty(icon, "scale", Vector3.One * 1.3f, 0.14f).SetTrans(Tween.TransitionType.Back).SetEase(Tween.EaseType.Out);
				t.TweenProperty(icon, "scale", Vector3.One, 0.12f);
			}
			Layout(marker);
		}
		else if (marker != null && marker.Icons.TryGetValue(type, out Node3D icon))
		{
			marker.Icons.Remove(type);
			if (type == StatusEffectType.Frozen)
			{
				marker.FrostRing.Visible = false;
			}
			if (animate && IsInstanceValid(icon))
			{
				Tween t = icon.CreateTween();
				t.TweenProperty(icon, "scale", Vector3.One * 1.4f, 0.08f);
				t.TweenProperty(icon, "scale", Vector3.One * 0.01f, 0.16f).SetTrans(Tween.TransitionType.Quad).SetEase(Tween.EaseType.In);
				t.TweenCallback(Callable.From(icon.QueueFree));
			}
			else if (IsInstanceValid(icon))
			{
				icon.QueueFree();
			}
			Layout(marker);
		}
	}

	/// <summary>True if the piece currently shows the status icon.</summary>
	public bool HasStatus(int pieceId, StatusEffectType type) =>
		_markers.TryGetValue(pieceId, out Marker m) && m.Icons.ContainsKey(type);

	/// <summary>
	/// "Rewinds" icons to the state before a list of events: pieces whose first event for a status is
	/// StatusApplied lose that icon, StatusExpired gets it back, so playing the events animates them.
	/// </summary>
	public void PrepareForEvents(IReadOnlyList<ResolutionEvent> events)
	{
		if (events == null)
		{
			return;
		}
		var handled = new HashSet<(int, StatusEffectType)>();
		foreach (ResolutionEvent e in events)
		{
			if (e.Type != ResolutionEventType.StatusApplied && e.Type != ResolutionEventType.StatusExpired)
			{
				continue;
			}
			if (!handled.Add((e.PieceId, e.Status)))
			{
				continue;
			}
			SetStatus(e.PieceId, e.Status, e.Type == ResolutionEventType.StatusExpired, null, false);
		}
	}

	/// <summary>Removes all icons of a piece immediately.</summary>
	public void RemovePiece(int pieceId)
	{
		if (_markers.TryGetValue(pieceId, out Marker m))
		{
			_markers.Remove(pieceId);
			if (IsInstanceValid(m.Root))
			{
				m.Root.QueueFree();
			}
		}
	}

	/// <summary>Removes every marker.</summary>
	public void ClearAll()
	{
		foreach (Marker m in _markers.Values)
		{
			if (IsInstanceValid(m.Root))
			{
				m.Root.QueueFree();
			}
		}
		_markers.Clear();
	}

	public override void _Process(double delta)
	{
		_time += (float)delta;
		foreach (KeyValuePair<int, Marker> kv in _markers)
		{
			Marker m = kv.Value;
			if (!IsInstanceValid(m.Root))
			{
				continue;
			}
			Node3D view = ViewResolver?.Invoke(kv.Key);
			Vector3 basePos = view != null && IsInstanceValid(view) ? view.GlobalPosition : m.Fallback;
			m.Root.GlobalPosition = basePos;
			bool any = m.Icons.Count > 0;
			m.Root.Visible = any;
			float bob = Mathf.Sin(_time * 2.4f + m.Phase) * 0.03f;
			m.IconRow.Position = new Vector3(0f, IconHeight + bob, -IconBackOffset);
			if (m.FrostRing.Visible)
			{
				m.FrostRing.Rotation = new Vector3(0f, _time * 0.25f + m.Phase, 0f);
			}
		}
	}

	private Marker CreateMarker(int pieceId, Vector3 fallback)
	{
		var root = new Node3D { Name = $"Status_{pieceId}" };
		AddChild(root);
		root.GlobalPosition = fallback;
		var row = new Node3D { Name = "Icons", Position = new Vector3(0f, IconHeight, -IconBackOffset) };
		root.AddChild(row);
		MeshInstance3D ring = VfxAssets.CreateIcon((int)FxIconShape.FrostRing, 1.0f, new Color(0.6f, 0.88f, 1f, 0.55f), new Color(0, 0, 0, 0), false, 3);
		var ringMat = (ShaderMaterial)ring.MaterialOverride;
		ringMat.SetShaderParameter("billboard", false);
		ringMat.SetShaderParameter("energy", 1.1f);
		ring.Mesh = new PlaneMesh { Size = new Vector2(1.18f, 1.18f) };
		ring.Position = new Vector3(0f, 0.025f, -0.03f);
		ring.Visible = false;
		root.AddChild(ring);
		var marker = new Marker { Root = root, IconRow = row, FrostRing = ring, Fallback = fallback, Phase = pieceId * 1.7f };
		_markers[pieceId] = marker;
		return marker;
	}

	private Node3D CreateIcon(StatusEffectType type)
	{
		var holder = new Node3D { Name = type.ToString() };
		bool frozen = type == StatusEffectType.Frozen;
		MeshInstance3D icon = VfxAssets.CreateIcon(frozen ? (int)FxIconShape.Snowflake : (int)FxIconShape.Bolt, IconSize,
			frozen ? FrozenFg : ChargeFg, frozen ? FrozenBg : ChargeBg, true, 31);
		var mat = (ShaderMaterial)icon.MaterialOverride;
		mat.SetShaderParameter("energy", frozen ? 1.2f : 1.6f);
		if (frozen)
		{
			mat.SetShaderParameter("spin", 0.4f);
		}
		holder.AddChild(icon);
		var glow = new MeshInstance3D { Mesh = VfxAssets.GlowQuad, Scale = Vector3.One * IconSize * 1.7f, CastShadow = GeometryInstance3D.ShadowCastingSetting.Off };
		glow.SetInstanceShaderParameter("tint", frozen ? new Color(0.4f, 0.75f, 1f, 0.55f) : new Color(0.75f, 0.55f, 1f, 0.6f));
		holder.AddChild(glow);
		return holder;
	}

	private void Layout(Marker m)
	{
		int n = m.Icons.Count;
		int i = 0;
		foreach (StatusEffectType type in new[] { StatusEffectType.Frozen, StatusEffectType.Overcharged })
		{
			if (!m.Icons.TryGetValue(type, out Node3D icon))
			{
				continue;
			}
			float x = (i - (n - 1) * 0.5f) * IconSize * 1.05f;
			icon.Position = new Vector3(x, 0f, 0f);
			i++;
		}
	}
}
