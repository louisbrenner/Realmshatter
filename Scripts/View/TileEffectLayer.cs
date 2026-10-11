using System.Collections.Generic;
using System.Threading.Tasks;
using Godot;

namespace Realmshatter;

/// <summary>
/// Shows BoardState.TileEffects (lava, walls, healing runes) with duration badges. Created by BoardView
/// as its child "TileEffects". Sync diffs the shown visuals against a board and animates appear/expire;
/// PlayApplied / PlayExpired animate single tiles while resolution events are played.
/// </summary>
public partial class TileEffectLayer : Node3D
{
	private readonly Dictionary<GridPos, TileEffectVisual> _visuals = new Dictionary<GridPos, TileEffectVisual>();
	private readonly Dictionary<GridPos, int> _totals = new Dictionary<GridPos, int>();
	private BoardView _board;

	/// <summary>Global turn number used for the remaining-duration badges (TileEffect.RemainingTurns).</summary>
	public int CurrentTurn { get; set; } = 1;

	/// <summary>Number of tiles currently showing an effect.</summary>
	public int Count => _visuals.Count;

	/// <summary>Connects the layer to its board (for grid -> world conversion and tile size).</summary>
	public void Setup(BoardView board)
	{
		_board = board;
	}

	/// <summary>The effect type currently shown on a tile (None if nothing).</summary>
	public TileEffectType GetShownType(GridPos pos) =>
		_visuals.TryGetValue(pos, out TileEffectVisual v) && IsInstanceValid(v) ? v.Type : TileEffectType.None;

	/// <summary>
	/// Makes the shown effects match the board: new effects appear (animated if requested), effects that
	/// are gone vanish, replaced types swap, and duration badges are refreshed. currentTurn &lt; 0 keeps CurrentTurn.
	/// </summary>
	public void Sync(BoardState board, int currentTurn = -1, bool animate = true)
	{
		if (board == null)
		{
			return;
		}
		if (currentTurn >= 0)
		{
			CurrentTurn = currentTurn;
		}
		var seen = new HashSet<GridPos>();
		foreach (KeyValuePair<GridPos, TileEffect> kv in board.TileEffects)
		{
			TileEffect effect = kv.Value;
			if (effect == null || effect.Type == TileEffectType.None)
			{
				continue;
			}
			seen.Add(kv.Key);
			if (_visuals.TryGetValue(kv.Key, out TileEffectVisual existing) && IsInstanceValid(existing) && existing.Type == effect.Type)
			{
				if (existing.ExpiryTurn != effect.ExpiryTurn)
				{
					_totals[kv.Key] = effect.RemainingTurns(CurrentTurn);
					existing.Pulse();
				}
				existing.ExpiryTurn = effect.ExpiryTurn;
				UpdateBadge(kv.Key, existing);
				continue;
			}
			_ = ShowEffect(kv.Key, effect.Type, effect.ExpiryTurn, animate);
		}
		var stale = new List<GridPos>();
		foreach (GridPos pos in _visuals.Keys)
		{
			if (!seen.Contains(pos))
			{
				stale.Add(pos);
			}
		}
		foreach (GridPos pos in stale)
		{
			_ = HideEffect(pos, animate);
		}
	}

	/// <summary>Animates an effect appearing on a tile (replacing any other shown there). Completes when formed.</summary>
	public Task PlayApplied(GridPos pos, TileEffectType type, int expiryTurn) => ShowEffect(pos, type, expiryTurn, true);

	/// <summary>Animates the effect on a tile disappearing. Completes when it is gone.</summary>
	public Task PlayExpired(GridPos pos) => HideEffect(pos, true);

	/// <summary>
	/// "Rewinds" the shown effects to the state before a list of events (in case the view was synced to the
	/// final state already): tiles whose first event is TileEffectApplied are hidden, tiles whose first event
	/// is TileEffectExpired are shown, so that playing the events animates them correctly.
	/// </summary>
	public void PrepareForEvents(IReadOnlyList<ResolutionEvent> events)
	{
		if (events == null)
		{
			return;
		}
		var handled = new HashSet<GridPos>();
		foreach (ResolutionEvent e in events)
		{
			if (e.Type != ResolutionEventType.TileEffectApplied && e.Type != ResolutionEventType.TileEffectExpired)
			{
				continue;
			}
			if (!handled.Add(e.To))
			{
				continue;
			}
			if (e.Type == ResolutionEventType.TileEffectApplied)
			{
				if (_visuals.TryGetValue(e.To, out TileEffectVisual v) && IsInstanceValid(v) && v.Type == e.TileEffect && v.ExpiryTurn == e.ExpiryTurn)
				{
					_visuals.Remove(e.To);
					v.QueueFree();
				}
			}
			else if (GetShownType(e.To) == TileEffectType.None && e.TileEffect != TileEffectType.None)
			{
				_ = ShowEffect(e.To, e.TileEffect, -1, false);
			}
		}
	}

	/// <summary>Removes all visuals immediately.</summary>
	public void ClearAll()
	{
		foreach (TileEffectVisual v in _visuals.Values)
		{
			if (IsInstanceValid(v))
			{
				v.QueueFree();
			}
		}
		_visuals.Clear();
		_totals.Clear();
	}

	private async Task ShowEffect(GridPos pos, TileEffectType type, int expiryTurn, bool animate)
	{
		if (type == TileEffectType.None)
		{
			await HideEffect(pos, animate);
			return;
		}
		if (_visuals.TryGetValue(pos, out TileEffectVisual old) && IsInstanceValid(old))
		{
			if (old.Type == type)
			{
				old.ExpiryTurn = expiryTurn;
				_totals[pos] = Remaining(expiryTurn);
				UpdateBadge(pos, old);
				old.Pulse();
				return;
			}
			_visuals.Remove(pos);
			_ = old.PlayVanish();
		}
		var visual = new TileEffectVisual();
		visual.Setup(type, _board != null ? _board.TileSize : 1f, false, pos.X * 1.37f + pos.Y * 2.11f);
		visual.ExpiryTurn = expiryTurn;
		AddChild(visual);
		visual.GlobalPosition = _board != null ? _board.GridToWorld(pos) : new Vector3(pos.X, 0f, pos.Y);
		_visuals[pos] = visual;
		_totals[pos] = Remaining(expiryTurn);
		UpdateBadge(pos, visual);
		if (animate)
		{
			await visual.PlayAppear();
		}
		else
		{
			visual.ShowInstant();
		}
	}

	private async Task HideEffect(GridPos pos, bool animate)
	{
		if (!_visuals.TryGetValue(pos, out TileEffectVisual v))
		{
			return;
		}
		_visuals.Remove(pos);
		_totals.Remove(pos);
		if (!IsInstanceValid(v))
		{
			return;
		}
		if (animate)
		{
			await v.PlayVanish();
		}
		else
		{
			v.QueueFree();
		}
	}

	private int Remaining(int expiryTurn) => expiryTurn < 0 ? 0 : Mathf.Max(0, expiryTurn - CurrentTurn + 1);

	private void UpdateBadge(GridPos pos, TileEffectVisual v)
	{
		int remaining = Remaining(v.ExpiryTurn);
		_totals.TryGetValue(pos, out int total);
		v.SetRemaining(remaining, Mathf.Max(total, remaining));
	}
}
