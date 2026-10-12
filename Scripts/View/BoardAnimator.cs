using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Godot;

namespace Realmshatter;

/// <summary>
/// Owns all PieceViews (id -> view), keeps them in sync with the GameState and plays
/// resolution events as awaitable animations with VFX (sparks, projectiles, damage numbers,
/// shatter, lightning, camera shake). Piece views and effects are parented to the BoardView.
/// Also drives the board's tile effects (BoardView.TileEffects) and the status icons
/// (StatusMarkers) for the v3 rules.
/// </summary>
public partial class BoardAnimator : Node
{
	[Export] public PackedScene PieceScene { get; set; }
	[Export] public BoardView Board { get; set; }
	/// <summary>Optional; if empty, the parent of the active Camera3D is used when it is a CameraRig.</summary>
	[Export] public CameraRig CameraRig { get; set; }
	[Export] public Color Player0Color { get; set; } = new Color(0.25f, 0.5f, 1.0f);
	[Export] public Color Player1Color { get; set; } = new Color(1.0f, 0.3f, 0.25f);
	[Export] public Color ChainFlashColor { get; set; } = new Color(1.0f, 0.85f, 0.2f);
	[Export] public Color DamageTextColor { get; set; } = new Color(1.0f, 0.35f, 0.3f);
	[Export] public Color InfoTextColor { get; set; } = new Color(0.8f, 0.8f, 1.0f);
	/// <summary>Pause between consecutive events, in seconds.</summary>
	[Export] public float EventPause { get; set; } = 0.08f;
	/// <summary>Global slow-down of the board animations: multiplies pauses, step/push tweens and piece move/attack times.</summary>
	[Export] public float AnimationPace { get; set; } = 1.3f;
	/// <summary>Player whose hidden traps are shown on the board (the human).</summary>
	[Export] public int TrapViewer { get; set; } = 0;

	[ExportGroup("VFX")]
	[Export] public Color ImpactColor { get; set; } = new Color(1.0f, 0.62f, 0.25f);
	[Export] public Color DamageSplatColor { get; set; } = new Color(0.85f, 0.1f, 0.08f);
	[Export] public Color ShieldColor { get; set; } = new Color(1.0f, 0.82f, 0.35f);
	[Export] public Color BuffColor { get; set; } = new Color(0.45f, 1.0f, 0.45f);
	[Export] public Color BuffSecondaryColor { get; set; } = new Color(1.0f, 0.85f, 0.35f);
	[Export] public Color DebuffColor { get; set; } = new Color(0.72f, 0.3f, 1.0f);
	[Export] public Color DebuffSecondaryColor { get; set; } = new Color(0.35f, 0.1f, 0.6f);
	[Export] public Color ScoreColor { get; set; } = new Color(1.0f, 0.84f, 0.3f);
	[Export] public Color DustColor { get; set; } = new Color(0.62f, 0.52f, 0.4f);
	[Export] public float ShakeStrength { get; set; } = 0.1f;
	/// <summary>If true, SyncAll shows summoning-sick pieces as exhausted (Piece.IsSummoningSick).</summary>
	[Export] public bool AutoSummoningSickness { get; set; } = true;

	[ExportGroup("Rules v3")]
	/// <summary>Seconds per tile when hopping along a move path.</summary>
	[Export] public float StepDuration { get; set; } = 0.13f;
	[Export] public float StepHopHeight { get; set; } = 0.2f;
	/// <summary>Seconds for a knockback / push slide.</summary>
	[Export] public float PushDuration { get; set; } = 0.16f;
	/// <summary>If true, SyncAll also syncs tile effects (BoardView.SyncTileEffects) and status markers.</summary>
	[Export] public bool AutoSyncBoardEffects { get; set; } = true;
	[Export] public Color HealTextColor { get; set; } = new Color(0.45f, 1.0f, 0.5f);
	[Export] public Color FrostColor { get; set; } = new Color(0.55f, 0.85f, 1.0f);
	[Export] public Color ChargeColor { get; set; } = new Color(0.78f, 0.62f, 1.0f);
	[Export] public Color EchoColor { get; set; } = new Color(1.0f, 0.78f, 0.4f);
	[Export] public Color PierceColor { get; set; } = new Color(0.85f, 0.92f, 1.0f);
	[Export] public Color SoulColor { get; set; } = new Color(0.55f, 1.0f, 0.9f);

	private readonly Dictionary<int, PieceView> _views = new Dictionary<int, PieceView>();
	private readonly Dictionary<int, Keyword> _keywords = new Dictionary<int, Keyword>();
	private readonly Dictionary<int, int> _owners = new Dictionary<int, int>();
	private readonly Dictionary<int, int> _shields = new Dictionary<int, int>();
	private readonly Dictionary<int, int> _ranges = new Dictionary<int, int>();
	private readonly Dictionary<int, Vector3> _deathPositions = new Dictionary<int, Vector3>();
	private readonly Dictionary<int, Tween> _motionTweens = new Dictionary<int, Tween>();
	private CameraRig _rig;
	private StatusMarkerLayer _statusMarkers;
	private GameState _playState;
	private GridPos? _lastPrimaryTile;

	/// <summary>All current views by piece id.</summary>
	public IReadOnlyDictionary<int, PieceView> Views => _views;

	/// <summary>True while PlayEvents is running.</summary>
	public bool IsPlaying { get; private set; }

	/// <summary>
	/// Optional: world position of a player's deck (cards of destroyed pieces fly there). Return null to use
	/// the default (beside the board on the owner's side).
	/// </summary>
	public Func<int, Vector3?> DeckWorldProvider { get; set; }

	/// <summary>Floating status icons (Frozen / Overcharged) above the pieces; created on first use under the Board.</summary>
	public StatusMarkerLayer StatusMarkers
	{
		get
		{
			if (_statusMarkers == null || !IsInstanceValid(_statusMarkers))
			{
				_statusMarkers = new StatusMarkerLayer { Name = "StatusMarkers", ViewResolver = id => GetView(id) };
				if (Board != null)
				{
					Board.AddChild(_statusMarkers);
				}
				else
				{
					AddChild(_statusMarkers);
				}
			}
			return _statusMarkers;
		}
	}

	/// <summary>Owner color for a player index.</summary>
	public Color GetOwnerColor(int playerIndex) => playerIndex == 0 ? Player0Color : Player1Color;

	/// <summary>Creates (or returns the existing) view for a piece and places it on its tile.</summary>
	public PieceView SpawnView(Piece piece)
	{
		if (piece == null)
		{
			return null;
		}
		CachePiece(piece);
		if (_views.TryGetValue(piece.Id, out PieceView existing) && IsInstanceValid(existing))
		{
			existing.Refresh(piece);
			return existing;
		}
		if (PieceScene == null || Board == null)
		{
			GD.PushError("BoardAnimator: PieceScene or Board is not assigned.");
			return null;
		}

		var view = PieceScene.Instantiate<PieceView>();
		view.MoveDuration *= AnimationPace;
		view.AttackDuration *= AnimationPace;
		Board.AddChild(view);
		view.Setup(piece, GetOwnerColor(piece.OwnerIndex));
		view.GlobalPosition = Board.GridToWorld(piece.Position);
		_views[piece.Id] = view;
		return view;
	}

	/// <summary>Removes and frees the view of a piece immediately (no animation).</summary>
	public void RemoveView(int id)
	{
		if (_views.TryGetValue(id, out PieceView view))
		{
			_views.Remove(id);
			if (IsInstanceValid(view))
			{
				view.QueueFree();
			}
		}
		_statusMarkers?.RemovePiece(id);
	}

	/// <summary>Returns the view of a piece, or null.</summary>
	public PieceView GetView(int id)
	{
		if (_views.TryGetValue(id, out PieceView view) && IsInstanceValid(view))
		{
			return view;
		}
		return null;
	}

	/// <summary>Removes all views (and status markers).</summary>
	public void ClearAll()
	{
		foreach (PieceView view in _views.Values)
		{
			if (IsInstanceValid(view))
			{
				view.QueueFree();
			}
		}
		_views.Clear();
		_motionTweens.Clear();
		_deathPositions.Clear();
		_statusMarkers?.ClearAll();
	}

	/// <summary>Deselects all views.</summary>
	public void ClearSelection()
	{
		foreach (PieceView view in _views.Values)
		{
			if (IsInstanceValid(view))
			{
				view.SetSelected(false);
			}
		}
	}

	/// <summary>Turns the green "can act" glow off on all views.</summary>
	public void ClearCanAct()
	{
		foreach (PieceView view in _views.Values)
		{
			if (IsInstanceValid(view))
			{
				view.SetCanAct(false);
			}
		}
	}

	/// <summary>
	/// Spawns views for pieces without one, removes views of pieces no longer in the state,
	/// refreshes stats/order indicators and snaps positions to the pieces' tiles. With AutoSyncBoardEffects
	/// (and not while PlayEvents runs) it also syncs the tile effects and the status markers.
	/// </summary>
	public void SyncAll(GameState state)
	{
		if (state == null || Board == null)
		{
			return;
		}
		var alive = new HashSet<int>();
		foreach (Piece piece in state.Pieces)
		{
			alive.Add(piece.Id);
			CachePiece(piece);
			PieceView view = GetView(piece.Id);
			if (view == null)
			{
				view = SpawnView(piece);
			}
			else
			{
				KillMotion(piece.Id);
				view.Refresh(piece);
				view.SnapTo(Board.GridToWorld(piece.Position));
			}
			if (view != null && AutoSummoningSickness)
			{
				view.SetExhausted(IsResting(piece, state));
			}
		}

		var stale = new List<int>();
		foreach (int id in _views.Keys)
		{
			if (!alive.Contains(id))
			{
				stale.Add(id);
			}
		}
		foreach (int id in stale)
		{
			RemoveView(id);
		}

		if (AutoSyncBoardEffects && !IsPlaying)
		{
			SyncBoardEffects(state);
		}
	}

	/// <summary>Sleeping z's on a piece: summoning sick, busy building, or already acted this turn.</summary>
	public static bool IsResting(Piece piece, GameState state) =>
		!piece.IsBuilding && (piece.IsSummoningSick(state.TurnNumber) || piece.ConstructingId >= 0 || piece.HasActed(state.TurnNumber));

	/// <summary>Updates only the sleeping z's of every piece (cheap; e.g. right after a deploy or an action).</summary>
	public void SyncExhausted(GameState state)
	{
		if (state == null || !AutoSummoningSickness)
		{
			return;
		}
		foreach (Piece piece in state.Pieces)
		{
			GetView(piece.Id)?.SetExhausted(IsResting(piece, state));
		}
	}

	/// <summary>Syncs tile effects (with the state's turn number for the duration badges) and status markers.</summary>
	public void SyncBoardEffects(GameState state)
	{
		if (state == null || Board == null)
		{
			return;
		}
		Board.SyncTileEffects(state.Board, state.TurnNumber, true);
		Board.SyncTerrain(state.Board, state.Config.RockHp);
		Board.SyncTraps(state.Board, TrapViewer);
		StatusMarkers.Sync(state, Board);
	}

	/// <summary>
	/// Animates resolution events in chronological order, then calls SyncAll(state) (which also syncs tile
	/// effects and status markers). Events referring to pieces without a view are skipped; unknown types are ignored.
	/// </summary>
	public Task PlayEvents(IReadOnlyList<ResolutionEvent> events, GameState state) => PlayEvents(events, state, true);

	/// <summary>
	/// Animates resolution events; syncAfter = false skips the final SyncAll (views keep their animated
	/// positions), e.g. when several event lists of one state change are played back to back.
	/// </summary>
	public async Task PlayEvents(IReadOnlyList<ResolutionEvent> events, GameState state, bool syncAfter)
	{
		var groups = new List<IReadOnlyList<ResolutionEvent>>();
		if (events != null)
		{
			groups.Add(events);
		}
		await PlayEventGroups(groups, state, null, syncAfter);
	}

	/// <summary>
	/// Plays several consecutive event lists (e.g. one per resolved order) as one sequence: tile effects and
	/// status icons are rewound once for all events, beforeGroup(index) is invoked before each non-empty group
	/// (e.g. to update a "Order 2/4" ticker), and SyncAll runs once at the end (if syncAfter).
	/// </summary>
	public async Task PlayEventGroups(IReadOnlyList<IReadOnlyList<ResolutionEvent>> groups, GameState state,
		Action<int> beforeGroup = null, bool syncAfter = true)
	{
		IsPlaying = true;
		ClearCanAct();
		_playState = state;
		if (state != null)
		{
			foreach (Piece piece in state.Pieces)
			{
				CachePiece(piece);
			}
		}
		if (groups != null && Board != null)
		{
			var all = new List<ResolutionEvent>();
			foreach (IReadOnlyList<ResolutionEvent> g in groups)
			{
				if (g != null)
				{
					all.AddRange(g);
				}
			}
			Board.TileEffects.PrepareForEvents(all);
			StatusMarkers.PrepareForEvents(all);
			for (int gi = 0; gi < groups.Count; gi++)
			{
				IReadOnlyList<ResolutionEvent> events = groups[gi];
				if (events == null || events.Count == 0)
				{
					continue;
				}
				try
				{
					beforeGroup?.Invoke(gi);
				}
				catch (Exception ex)
				{
					GD.PushWarning($"BoardAnimator: beforeGroup callback failed: {ex.Message}");
				}
				for (int i = 0; i < events.Count; i++)
				{
					if (events[i] == null)
					{
						continue;
					}
					try
					{
						await PlayEvent(events, i);
					}
					catch (Exception ex)
					{
						GD.PushWarning($"BoardAnimator: failed to animate {events[i]}: {ex.Message}");
					}
					if (EventPause > 0f)
					{
						await Delay(EventPause);
					}
				}
			}
		}
		IsPlaying = false;
		if (syncAfter)
		{
			SyncAll(state);
		}
		_playState = null;
	}

	/// <summary>Spawns a short popping, rising text at a world position (fire and forget).</summary>
	public void SpawnFloatingText(Vector3 world, string text, Color color)
	{
		Vfx.PopupText(Board, world, text, color, 60, 1.1f);
	}

	/// <summary>Shakes the camera rig (if one is found).</summary>
	public void Shake(float strength, float duration)
	{
		ResolveRig()?.Shake(strength, duration);
	}

	/// <summary>Summon: the token slams down from above with a dust shockwave and a light flash.</summary>
	public async Task PlaySummon(int pieceId)
	{
		PieceView view = GetView(pieceId);
		if (view == null || Board == null)
		{
			return;
		}
		Vector3 rest = view.GlobalPosition;
		Color owner = view.OwnerColor;
		Vfx.GlowFlash(Board, rest + new Vector3(0, 1.6f, 0), owner.Lightened(0.5f), 1.4f, 0.25f);
		Sfx.Play(SfxId.Swing, -6f, 0.8f);
		await view.PlayDrop(2.4f, 0.22f);
		if (!IsInstanceValid(view))
		{
			return;
		}
		Sfx.Play(SfxId.Summon);
		Vfx.Shockwave(Board, rest + new Vector3(0, 0.03f, 0), new Color(1f, 0.88f, 0.65f), 1.5f, 0.45f, 0.1f);
		Vfx.DustRing(Board, rest, DustColor, 0.45f, 18);
		Vfx.Sparkle(Board, rest + new Vector3(0, 0.25f, 0), owner.Lightened(0.4f), 12, 0.6f, 0.5f);
		Vfx.LightFlash(Board, rest + new Vector3(0, 0.8f, 0), owner.Lightened(0.4f), 4f, 3.5f, 0.35f);
		Shake(ShakeStrength * 0.8f, 0.16f);
		await view.PlaySquash(1f);
	}

	/// <summary>Spell cast on a piece: glowing motes spiral in (green/gold buff or purple debuff) and burst.</summary>
	public async Task PlaySpellCast(int targetPieceId, bool positive)
	{
		PieceView view = GetView(targetPieceId);
		if (view == null || Board == null)
		{
			return;
		}
		Color primary = positive ? BuffColor : DebuffColor;
		Color secondary = positive ? BuffSecondaryColor : DebuffSecondaryColor;
		Sfx.Play(positive ? SfxId.BuffCast : SfxId.DebuffCast);
		Vfx.SpellSwirl(Board, view.GlobalPosition, primary, secondary, 0.5f);
		await Delay(0.5f);
		if (!IsInstanceValid(view))
		{
			return;
		}
		await view.PlayFlash(primary, 0.3f);
	}

	/// <summary>Scoring: coins and sparkles rise from the zone tiles with "+1" popups.</summary>
	public async Task PlayScore(IEnumerable<GridPos> tiles, int player, Func<GridPos, int> pointsAt = null)
	{
		if (Board == null || tiles == null)
		{
			return;
		}
		Color text = player == 0 ? Player0Color.Lerp(ScoreColor, 0.6f) : Player1Color.Lerp(ScoreColor, 0.6f);
		int count = 0;
		foreach (GridPos tile in tiles)
		{
			Vector3 pos = Board.GridToWorld(tile);
			Sfx.Play(SfxId.Coin, 0f, 1f + 0.04f * count);
			Vfx.CoinFountain(Board, pos);
			Vfx.GlowFlash(Board, pos + new Vector3(0, 0.3f, 0), ScoreColor, 1.4f, 0.3f);
			int points = pointsAt?.Invoke(tile) ?? 1;
			Vfx.PopupText(Board, pos, $"+{points}", text, points > 1 ? 88 : 72, 1.0f);
			if (points > 1)
			{
				Vfx.Sparkle(Board, pos + new Vector3(0, 0.5f, 0), ScoreColor, 18, 0.9f, 0.5f);
			}
			count++;
			await Delay(0.06f);
		}
		if (count > 0)
		{
			await Delay(0.45f);
		}
	}

	/// <summary>Small sparkle on a tile (e.g. for hover feedback); fire and forget.</summary>
	public void PlayHoverSparkle(GridPos tile)
	{
		if (Board != null)
		{
			Vfx.Sparkle(Board, Board.GridToWorld(tile) + new Vector3(0, 0.2f, 0), ScoreColor, 4, 0.5f, 0.3f);
		}
	}

	/// <summary>World position of a player's deck (DeckWorldProvider or beside the board on the owner's side).</summary>
	public Vector3 GetDeckWorld(int playerIndex)
	{
		Vector3? custom = DeckWorldProvider?.Invoke(playerIndex);
		if (custom.HasValue)
		{
			return custom.Value;
		}
		if (Board == null)
		{
			return Vector3.Zero;
		}
		float ts = Board.TileSize;
		var local = new Vector3((Board.Width * 0.5f + 1.1f) * ts, 0.6f, (playerIndex == 0 ? 1f : -1f) * (Board.Height * 0.5f + 0.2f) * ts);
		return Board.IsInsideTree() ? Board.ToGlobal(local) : local;
	}

	// ------------------------------------------------------------------ event dispatch

	private async Task PlayEvent(IReadOnlyList<ResolutionEvent> events, int index)
	{
		ResolutionEvent e = events[index];
		ResolutionEventType? next = index + 1 < events.Count ? events[index + 1]?.Type : null;
		PieceView view = GetView(e.PieceId);
		switch (e.Type)
		{
			case ResolutionEventType.Moved:
				if (view != null)
				{
					await PlayMove(e, view);
				}
				break;

			case ResolutionEventType.MoveBlocked:
				if (view != null)
				{
					Sfx.PlayDelayed(SfxId.Blocked, 0.08f);
					SpawnFloatingText(view.GlobalPosition, "Blocked", InfoTextColor);
					await view.PlayBump(Board.GridToWorld(e.To));
				}
				break;

			case ResolutionEventType.Attacked:
				if (view != null)
				{
					if (e.IsPierce)
					{
						await PlayPierce(e, view);
					}
					else if (e.IsSecondary)
					{
						await PlaySecondaryHit(e);
					}
					else
					{
						_lastPrimaryTile = e.To;
						await PlayAttack(e, view);
					}
				}
				break;

			case ResolutionEventType.AttackCancelled:
				if (view != null)
				{
					Sfx.Play(SfxId.SpellFade);
					SpawnFloatingText(view.GlobalPosition, "Fizzled", new Color(0.7f, 0.7f, 0.7f));
				}
				break;

			case ResolutionEventType.Damaged:
				_shields[e.PieceId] = e.RemainingShield;
				if (view != null)
				{
					await PlayDamage(e, view);
				}
				break;

			case ResolutionEventType.Died:
				_statusMarkers?.RemovePiece(e.PieceId);
				if (view != null)
				{
					KillMotion(e.PieceId);
					_views.Remove(e.PieceId);
					Vector3 p = view.GlobalPosition + new Vector3(0, 0.15f, 0);
					_deathPositions[e.PieceId] = view.GlobalPosition;
					Sfx.Play(SfxId.Death);
					Vfx.Shatter(Board, p, view.BodyColor, view.TintColor);
					Vfx.LightFlash(Board, p + new Vector3(0, 0.6f, 0), new Color(1f, 0.75f, 0.45f), 5f, 3.5f, 0.4f);
					Shake(ShakeStrength * 1.3f, 0.25f);
					await view.PlayDeath();
				}
				else
				{
					_deathPositions[e.PieceId] = Board.GridToWorld(e.From);
				}
				break;

			case ResolutionEventType.SpellExpired:
				if (view != null)
				{
					Sfx.Play(SfxId.SpellFade);
					Vfx.Sparkle(Board, view.GlobalPosition + new Vector3(0, 0.3f, 0), new Color(0.75f, 0.65f, 1f), 14, 0.7f, 0.45f);
					Vfx.PopupText(Board, view.GlobalPosition, $"{e.SpellName} fades", InfoTextColor, 44, 1.0f);
					await Delay(0.15f);
				}
				break;

			case ResolutionEventType.Pushed:
				if (view != null)
				{
					await PlayPush(e, view, next == ResolutionEventType.Pushed);
				}
				break;

			case ResolutionEventType.PushBlocked:
				if (view != null)
				{
					await PlayPushBlocked(e, view);
				}
				break;

			case ResolutionEventType.Healed:
				await PlayHeal(e, view, false);
				break;

			case ResolutionEventType.TileHeal:
				await PlayHeal(e, view, true);
				break;

			case ResolutionEventType.ReturnedToDeck:
				await PlayReturnToDeck(e);
				break;

			case ResolutionEventType.TileEffectApplied:
			{
				Sfx.Play(e.TileEffect switch
				{
					TileEffectType.Lava => SfxId.Fire,
					TileEffectType.Wall => SfxId.WallRise,
					TileEffectType.Healing => SfxId.Heal,
					_ => SfxId.BuffCast,
				}, -3f);
				Task appear = Board.AnimateTileEffectApplied(e.To, e.TileEffect, e.ExpiryTurn);
				if (next == ResolutionEventType.TileEffectApplied)
				{
					await Delay(0.06f);
				}
				else
				{
					await appear;
				}
				break;
			}

			case ResolutionEventType.TileEffectExpired:
			{
				Sfx.Play(SfxId.TileFade);
				_ = Board.AnimateTileEffectExpired(e.To);
				await Delay(next == ResolutionEventType.TileEffectExpired ? 0.04f : 0.25f);
				break;
			}

			case ResolutionEventType.TileDamage when e.TileEffect == TileEffectType.Storm:
			{
				Vector3 pos = Board.GridToWorld(e.To);
				var storm = new Color(0.8f, 0.65f, 1f);
				Sfx.Play(SfxId.Zap);
				Vfx.Shockwave(Board, pos + new Vector3(0, 0.05f, 0), storm, 1.6f, 0.35f);
				Vfx.Sparkle(Board, pos + new Vector3(0, 0.3f, 0), storm, 14, 0.5f, 0.5f);
				Vfx.PopupText(Board, pos, "Storm!", storm, 50, 1.2f);
				Shake(ShakeStrength * 0.6f, 0.15f);
				await Delay(0.2f);
				break;
			}

			case ResolutionEventType.TileDamage:
			{
				Vector3 pos = Board.GridToWorld(e.To);
				Sfx.Play(SfxId.LavaBurn);
				RuleVfx.LavaEruption(Board, pos);
				Vfx.PopupText(Board, pos, "Lava!", RuleVfx.FireColor, 50, 1.25f);
				Shake(ShakeStrength * 0.7f, 0.15f);
				await Delay(0.2f);
				break;
			}

			case ResolutionEventType.StatusApplied:
				await PlayStatusApplied(e, view);
				break;

			case ResolutionEventType.StatusExpired:
				await PlayStatusExpired(e, view);
				break;

			case ResolutionEventType.SpellCast:
				if (e.Amount > 0)
				{
					Vector3 at = Board.GridToWorld(e.To) + new Vector3(0, 0.75f, 0);
					var arcane = new Color(0.75f, 0.55f, 1f);
					Vfx.Sparkle(Board, at, arcane, 18, 0.8f, 0.5f);
					Vfx.PopupText(Board, at, "Empowered!", arcane, 50, 1.1f);
				}
				await PlaySpellCastEvent(events, index);
				break;

			case ResolutionEventType.Deathrattle:
				await PlayDeathrattle(e);
				break;

			case ResolutionEventType.FirstHitTriggered:
				await PlayFirstHit(e, view);
				break;

			case ResolutionEventType.BuildingStarted:
				await PlayBuildingStarted(e);
				break;

			case ResolutionEventType.BuildingCompleted:
				if (view != null)
				{
					Sfx.Play(SfxId.WallRise, -2f, 1.2f);
					view.SetUnderConstruction(false);
					Vfx.Sparkle(Board, view.GlobalPosition + new Vector3(0, 0.5f, 0), ScoreColor, 16, 0.8f, 0.4f);
					Vfx.PopupText(Board, view.GlobalPosition + new Vector3(0, 0.4f, 0), $"{e.SpellName} ready!", ScoreColor, 50, 1.3f);
					await Delay(0.4f);
				}
				break;

			case ResolutionEventType.TrapSet:
				if (e.PlayerIndex == TrapViewer)
				{
					// Only the owner sees where it went.
					Vector3 at = Board.GridToWorld(e.To);
					Sfx.Play(SfxId.Land, -4f, 1.3f);
					Vfx.DustRing(Board, at, DustColor, 0.3f, 8);
					Vfx.PopupText(Board, at + new Vector3(0, 0.35f, 0), e.CardName, InfoTextColor, 40, 0.8f);
					await Delay(0.2f);
				}
				break;

			case ResolutionEventType.TrapTriggered:
			{
				Vector3 at = Board.GridToWorld(e.To);
				Color c = TrapInfo.GetColor(System.Enum.TryParse(e.SpellName, out TrapType type) ? type : TrapType.Spike);
				Sfx.Play(SfxId.Blocked, 0f, 0.8f);
				Sfx.Play(SfxId.MeleeHit, -2f, 0.7f);
				MeshInstance3D jaws = VfxAssets.CreateIcon((int)FxIconShape.Trap, 0.7f, c, new Color(0.08f, 0.06f, 0.05f, 0.9f));
				Board.AddChild(jaws);
				jaws.GlobalPosition = at + new Vector3(0, 0.55f, 0);
				Tween pop = jaws.CreateTween();
				pop.TweenProperty(jaws, "scale", Vector3.One * 1.3f, 0.12f).From(Vector3.One * 0.3f);
				pop.TweenInterval(0.45f);
				pop.TweenProperty(jaws, "scale", Vector3.One * 0.01f, 0.2f);
				pop.TweenCallback(Callable.From(jaws.QueueFree));
				Vfx.Shockwave(Board, at + new Vector3(0, 0.05f, 0), c, 0.9f, 0.4f);
				Vfx.PopupText(Board, at + new Vector3(0, 0.95f, 0), $"{e.CardName}!", c, 54, 1.1f);
				CameraRig?.Shake(ShakeStrength * 0.6f, 0.25f);
				Board.RemoveTrapMarker(e.To);
				await Delay(0.45f);
				break;
			}

			case ResolutionEventType.TerrainDamaged:
			{
				Vector3 at = Board.GridToWorld(e.To);
				bool crumbled = e.RemainingHp <= 0;
				Sfx.Play(SfxId.WallRise, crumbled ? 0f : -5f, crumbled ? 0.6f : 0.9f);
				Vfx.DustRing(Board, at, DustColor, crumbled ? 0.55f : 0.35f, crumbled ? 26 : 10);
				Vfx.PopupText(Board, at + new Vector3(0, 0.55f, 0), crumbled ? "Crumbles!" : $"-{e.Amount}", DustColor.Lightened(0.35f), 48, 1f);
				Board.ShowRockHp(e.To, e.RemainingHp);
				await Delay(crumbled ? 0.3f : 0.15f);
				break;
			}

			case ResolutionEventType.ApGained:
			{
				Vector3 at = Board.GridToWorld(e.From) + new Vector3(0, 0.45f, 0);
				var mana = new Color(0.45f, 0.75f, 1f);
				Sfx.Play(SfxId.Coin);
				Vfx.Sparkle(Board, at, mana, 12, 0.7f, 0.35f);
				Vfx.PopupText(Board, at, e.IsSecondary ? $"+{e.Amount} AP next turn" : $"+{e.Amount} AP", mana, 52, 1.2f);
				await Delay(0.3f);
				break;
			}

			case ResolutionEventType.AuraPulse:
				if (view != null)
				{
					Color c = ClanInfo.GetColor(System.Enum.TryParse(e.CardName, out Clan clan) ? clan : Clan.None);
					Sfx.Play(SfxId.BuffCast, -6f, 0.8f);
					Vfx.Shockwave(Board, view.GlobalPosition + new Vector3(0, 0.05f, 0), c, 2.6f, 0.5f, 0.1f);
					Vfx.PopupText(Board, view.GlobalPosition + new Vector3(0, 0.3f, 0), e.SpellName, c.Lightened(0.3f), 44, 1.1f);
					await Delay(0.3f);
				}
				break;

			default:
				break;
		}
	}

	// ------------------------------------------------------------------ movement

	private async Task PlayMove(ResolutionEvent e, PieceView view)
	{
		var points = new List<Vector3> { view.GlobalPosition };
		if (e.Path != null && e.Path.Count > 0)
		{
			foreach (GridPos p in e.Path)
			{
				points.Add(Board.GridToWorld(p));
			}
		}
		else
		{
			points.Add(Board.GridToWorld(e.To));
		}
		int steps = points.Count - 1;
		if (steps <= 0)
		{
			return;
		}
		KillMotion(e.PieceId);
		int lastStep = 0;
		Tween tween = view.CreateTween();
		_motionTweens[e.PieceId] = tween;
		tween.TweenMethod(Callable.From<float>(t =>
		{
			if (!IsInstanceValid(view))
			{
				return;
			}
			float f = t * steps;
			int seg = Mathf.Min((int)f, steps - 1);
			float u = f - seg;
			float eased = u * u * (3f - 2f * u);
			if (seg > lastStep)
			{
				lastStep = seg;
				Vfx.DustRing(Board, points[seg], DustColor, 0.25f, 6);
				Sfx.Play(SfxId.Step);
			}
			view.GlobalPosition = points[seg].Lerp(points[seg + 1], eased) + Vector3.Up * StepHopHeight * 4f * u * (1f - u);
		}), 0f, 1f, StepDuration * steps * AnimationPace);
		await ToSignal(tween, Tween.SignalName.Finished);
		_motionTweens.Remove(e.PieceId);
		if (!IsInstanceValid(view))
		{
			return;
		}
		view.GlobalPosition = points[steps];
		Vfx.DustRing(Board, points[steps], DustColor, 0.35f, 10);
		Sfx.Play(SfxId.Land);
		_ = view.PlaySquash(0.6f);
	}

	private async Task PlayPush(ResolutionEvent e, PieceView view, bool quick)
	{
		Vector3 from = Board.GridToWorld(e.From);
		Vector3 to = Board.GridToWorld(e.To);
		Vector3 dir = to - from;
		dir = dir.LengthSquared() > 0.0001f ? dir.Normalized() : Vector3.Forward;
		Vector3 impact = from - dir * 0.45f + new Vector3(0, 0.3f, 0);
		bool knockback = HasKeyword(e.OtherPieceId, Keyword.Push) && OwnerOf(e.OtherPieceId) != OwnerOf(e.PieceId);
		Sfx.Play(SfxId.Push, knockback ? 0f : -4f);
		Vfx.ImpactSparks(Board, impact, knockback ? ImpactColor : new Color(1f, 0.95f, 0.8f), knockback ? 26 : 12, knockback ? 0.9f : 0.5f);
		Vfx.SmokePuff(Board, impact - new Vector3(0, 0.2f, 0), DustColor, 5, 0.45f);
		Shake(ShakeStrength * (knockback ? 0.9f : 0.5f), 0.12f);
		if (knockback)
		{
			Vfx.PopupText(Board, from, "Knockback!", ImpactColor, 48, 1.15f);
		}
		KillMotion(e.PieceId);
		view.GlobalPosition = from;
		Tween tween = view.CreateTween();
		_motionTweens[e.PieceId] = tween;
		tween.TweenMethod(Callable.From<float>(t =>
		{
			if (IsInstanceValid(view))
			{
				view.GlobalPosition = from.Lerp(to, t) + Vector3.Up * 0.08f * 4f * t * (1f - t);
			}
		}), 0f, 1f, PushDuration * AnimationPace).SetTrans(Tween.TransitionType.Expo).SetEase(Tween.EaseType.Out);
		Vfx.DustRing(Board, from, DustColor, 0.3f, 8);
		if (quick)
		{
			await Delay(0.05f);
			return;
		}
		await ToSignal(tween, Tween.SignalName.Finished);
		_motionTweens.Remove(e.PieceId);
		if (!IsInstanceValid(view))
		{
			return;
		}
		Vfx.DustRing(Board, to, DustColor, 0.35f, 10);
		_ = view.PlaySquash(0.7f);
	}

	private async Task PlayPushBlocked(ResolutionEvent e, PieceView view)
	{
		Vector3 from = view.GlobalPosition;
		Vector3 to = Board.GridToWorld(e.To);
		Vector3 dir = to - from;
		dir.Y = 0f;
		dir = dir.LengthSquared() > 0.0001f ? dir.Normalized() : Vector3.Forward;
		Vector3 edge = from + dir * 0.5f + new Vector3(0, 0.3f, 0);
		Task bump = view.PlayBump(to);
		await Delay(0.07f);
		Sfx.Play(SfxId.Blocked);
		Vfx.ImpactSparks(Board, edge, new Color(0.9f, 0.9f, 1f), 14, 0.6f);
		Vfx.Shockwave(Board, new Vector3(edge.X, 0.05f, edge.Z), new Color(1f, 0.9f, 0.7f), 0.7f, 0.25f, 0.12f);
		Vfx.PopupText(Board, from, "Blocked!", InfoTextColor, 48, 1.1f);
		Shake(ShakeStrength * 0.6f, 0.12f);
		await bump;
	}

	// ------------------------------------------------------------------ combat

	private async Task PlayAttack(ResolutionEvent e, PieceView view)
	{
		Vector3 from = view.GlobalPosition;
		Vector3 target = Board.GridToWorld(e.To);
		bool hasTarget = e.OtherPieceId >= 0;
		bool enemyTarget = hasTarget && OwnerOf(e.OtherPieceId) != OwnerOf(e.PieceId);
		bool burning = HasKeyword(e.PieceId, Keyword.Burning);
		bool frost = HasKeyword(e.PieceId, Keyword.Frost);
		bool ranged = e.From.ManhattanDistance(e.To) > 1;
		Color color = e.IsSecondary ? ChainFlashColor : ImpactColor;
		if (burning)
		{
			color = RuleVfx.FireColor;
		}
		else if (frost)
		{
			color = FrostColor;
		}
		if (ranged)
		{
			_ = view.PlayRecoil(target);
			Color bolt = burning ? RuleVfx.FireColor : frost ? FrostColor
				: e.IsSecondary ? ChainFlashColor : view.OwnerColor.Lerp(new Color(1f, 0.75f, 0.35f), 0.55f);
			float duration = 0.12f + 0.045f * e.From.ManhattanDistance(e.To);
			Sfx.Play(e.IsSecondary ? SfxId.Zap : SfxId.Shoot, e.IsSecondary ? -4f : 0f);
			if (burning)
			{
				Sfx.Play(SfxId.Fire, -8f, 1.3f);
			}
			await Vfx.Projectile(Board, from + new Vector3(0, 0.45f, 0), target + new Vector3(0, 0.35f, 0), bolt, duration);
			Sfx.Play(hasTarget ? SfxId.ArrowHit : SfxId.Step, hasTarget ? 0f : -2f);
			Vfx.ImpactSparks(Board, target + new Vector3(0, 0.35f, 0), bolt, hasTarget ? 36 : 16, hasTarget ? 1f : 0.6f);
			Vfx.LightFlash(Board, target + new Vector3(0, 0.6f, 0), bolt, 3f, 2.5f, 0.25f);
			if (hasTarget)
			{
				Shake(ShakeStrength * 0.7f, 0.15f);
			}
			PlayKeywordImpact(target, enemyTarget, burning, frost);
			return;
		}

		Task lunge = view.PlayAttack(target);
		Sfx.Play(SfxId.Swing);
		await Delay(view.ImpactTime);
		Sfx.Play(hasTarget ? SfxId.MeleeHit : SfxId.Land);
		Vector3 impact = from.Lerp(target, 0.75f) + new Vector3(0, 0.3f, 0);
		Vfx.ImpactSparks(Board, impact, color, hasTarget ? 44 : 18, hasTarget ? 1.1f : 0.6f);
		if (hasTarget)
		{
			Vfx.LightFlash(Board, impact + new Vector3(0, 0.4f, 0), color, 3.5f, 2.5f, 0.22f);
			Shake(ShakeStrength, 0.18f);
		}
		else
		{
			Vfx.DustRing(Board, target, DustColor, 0.3f, 8);
		}
		PlayKeywordImpact(target, enemyTarget, burning, frost);
		await lunge;
	}

	private void PlayKeywordImpact(Vector3 target, bool enemyTarget, bool burning, bool frost)
	{
		if (!enemyTarget)
		{
			return;
		}
		if (burning)
		{
			RuleVfx.FireBurst(Board, target, 1f);
		}
		if (frost)
		{
			Vfx.Sparkle(Board, target + new Vector3(0, 0.35f, 0), FrostColor, 14, 0.6f, 0.4f);
		}
	}

	private async Task PlayPierce(ResolutionEvent e, PieceView view)
	{
		Vector3 from = view.GlobalPosition + new Vector3(0, 0.4f, 0);
		Vector3 to = Board.GridToWorld(e.To) + new Vector3(0, 0.35f, 0);
		Vector3 dir = to - from;
		Vector3 end = to + (dir.LengthSquared() > 0.0001f ? dir.Normalized() * 0.35f : Vector3.Zero);
		_ = view.PlayRecoil(to);
		Sfx.Play(SfxId.Swing, 0f, 1.4f);
		RuleVfx.Beam(Board, from, end, PierceColor, 0.42f, 0.28f);
		Vfx.PopupText(Board, Board.GridToWorld(e.To), "Pierce!", PierceColor, 48, 1.3f);
		await Delay(0.09f);
		bool hasTarget = e.OtherPieceId >= 0;
		if (hasTarget)
		{
			Sfx.Play(SfxId.MeleeHit, -2f, 1.15f);
		}
		Vfx.ImpactSparks(Board, to, PierceColor, hasTarget ? 34 : 14, hasTarget ? 1f : 0.6f);
		if (hasTarget)
		{
			Shake(ShakeStrength * 0.8f, 0.15f);
		}
		PlayKeywordImpact(Board.GridToWorld(e.To), hasTarget && OwnerOf(e.OtherPieceId) != OwnerOf(e.PieceId),
			HasKeyword(e.PieceId, Keyword.Burning), HasKeyword(e.PieceId, Keyword.Frost));
		await Delay(0.1f);
	}

	private async Task PlayDamage(ResolutionEvent e, PieceView view)
	{
		view.SetStats(e.RemainingHp, e.RemainingShield);
		Vector3 p = view.GlobalPosition;
		if (e.HpLost > 0)
		{
			Sfx.Play(SfxId.Damage);
		}
		if (e.ShieldAbsorbed > 0)
		{
			Sfx.Play(e.RemainingShield <= 0 ? SfxId.ShieldBreak : SfxId.ShieldBlock);
		}
		if (e.ShieldAbsorbed > 0)
		{
			if (e.RemainingShield <= 0)
			{
				Vfx.ShieldShatter(Board, p + new Vector3(0, 0.3f, 0));
			}
			else
			{
				Vfx.ShieldBlock(Board, p + new Vector3(0, 0.3f, 0));
			}
		}
		if (e.HpLost > 0)
		{
			Vfx.DamageNumber(Board, p, $"-{e.HpLost}", DamageSplatColor);
		}
		else if (e.ShieldAbsorbed > 0)
		{
			Vfx.DamageNumber(Board, p, $"-{e.ShieldAbsorbed}", ShieldColor.Darkened(0.25f));
		}
		if (e.HpLost > 0)
		{
			await view.PlayHit();
		}
		else
		{
			await view.PlayFlash(ShieldColor, 0.25f);
		}
	}

	/// <summary>
	/// Secondary hit of an attack: the Echo strike on the same tile (brass rings) or an Arc zap jumping from the
	/// main target to a neighbouring piece (lightning, hits friend and foe alike).
	/// </summary>
	private async Task PlaySecondaryHit(ResolutionEvent e)
	{
		Vector3 target = Board.GridToWorld(e.To);
		bool echo = HasKeyword(e.PieceId, Keyword.Echo) && _lastPrimaryTile.HasValue && e.To == _lastPrimaryTile.Value;
		if (echo)
		{
			Sfx.Play(SfxId.EchoRing);
			RuleVfx.EchoRing(Board, target, EchoColor);
			Vfx.PopupText(Board, target, "Echo!", EchoColor, 50, 1.3f);
			await Delay(0.18f);
			Sfx.Play(e.OtherPieceId >= 0 ? SfxId.MeleeHit : SfxId.Step, -5f, 1.2f);
			Vfx.ImpactSparks(Board, target + new Vector3(0, 0.35f, 0), EchoColor, e.OtherPieceId >= 0 ? 20 : 8, 0.6f);
			return;
		}
		Vector3 from = _lastPrimaryTile.HasValue ? Board.GridToWorld(_lastPrimaryTile.Value) : target;
		Sfx.Play(SfxId.Zap);
		Vfx.Lightning(Board, from + new Vector3(0, 0.35f, 0), target + new Vector3(0, 0.35f, 0), ChainFlashColor.Lerp(Colors.White, 0.3f), 0.4f);
		RuleVfx.ChargeCrackle(Board, target + new Vector3(0, 0.35f, 0), ChainFlashColor, 4, 0.5f, 0.3f);
		Vfx.PopupText(Board, target, "Arc!", ChainFlashColor.Lightened(0.3f), 46, 1.3f);
		await Delay(0.15f);
	}

	// ------------------------------------------------------------------ heal / status / deck

	private async Task PlayHeal(ResolutionEvent e, PieceView view, bool fromTile)
	{
		Vector3 pos = view != null ? view.GlobalPosition : Board.GridToWorld(e.To);
		if (view != null)
		{
			_shields.TryGetValue(e.PieceId, out int shield);
			view.SetStats(e.RemainingHp, shield);
		}
		Sfx.Play(SfxId.Heal, fromTile ? -4f : 0f);
		RuleVfx.HealBurst(Board, pos);
		if (fromTile)
		{
			Vfx.Shockwave(Board, pos + new Vector3(0, 0.04f, 0), RuleVfx.HealGold, 1.2f, 0.5f, 0.08f);
		}
		Vfx.PopupText(Board, pos, $"+{e.Amount}", HealTextColor, 76, 1.0f);
		if (view != null)
		{
			await view.PlayFlash(HealTextColor, 0.3f);
		}
		else
		{
			await Delay(0.25f);
		}
	}

	private async Task PlayStatusApplied(ResolutionEvent e, PieceView view)
	{
		Vector3 pos = view != null ? view.GlobalPosition : Board.GridToWorld(e.To);
		StatusMarkers.SetStatus(e.PieceId, e.Status, true, pos, true);
		switch (e.Status)
		{
			case StatusEffectType.Frozen:
				Sfx.Play(SfxId.Freeze);
				RuleVfx.IceBurst(Board, pos);
				Vfx.PopupText(Board, pos, "Frozen!", FrostColor, 56, 1.2f);
				if (view != null)
				{
					await view.PlayFlash(FrostColor, 0.3f);
				}
				break;
			case StatusEffectType.Overcharged:
				Sfx.Play(SfxId.Charge);
				RuleVfx.ChargeCrackle(Board, pos + new Vector3(0, 0.35f, 0), ChargeColor, 6, 0.6f, 0.4f);
				Vfx.PopupText(Board, pos, "Overcharged!", ChargeColor, 56, 1.2f);
				if (view != null)
				{
					await view.PlayFlash(ChargeColor, 0.3f);
				}
				break;
			default:
				await Delay(0.1f);
				break;
		}
	}

	private async Task PlayStatusExpired(ResolutionEvent e, PieceView view)
	{
		Vector3 pos = view != null ? view.GlobalPosition : Board.GridToWorld(e.To);
		StatusMarkers.SetStatus(e.PieceId, e.Status, false, null, true);
		if (e.Status == StatusEffectType.Overcharged && e.IsSecondary)
		{
			Sfx.Play(SfxId.ChargeRelease);
			RuleVfx.ChargeCrackle(Board, pos + new Vector3(0, 0.35f, 0), ChargeColor.Lightened(0.3f), 8, 0.95f, 0.45f);
			Vfx.GlowFlash(Board, pos + new Vector3(0, 0.4f, 0), Colors.White, 2.4f, 0.25f);
			Vfx.Shockwave(Board, pos + new Vector3(0, 0.05f, 0), ChargeColor, 1.8f, 0.4f, 0.1f);
			Vfx.PopupText(Board, pos, "Overcharge x2!", ChargeColor.Lightened(0.35f), 62, 1.55f);
			Shake(ShakeStrength * 0.9f, 0.18f);
			await Delay(0.25f);
		}
		else if (e.Status == StatusEffectType.Frozen)
		{
			Sfx.Play(SfxId.Thaw);
			RuleVfx.Thaw(Board, pos);
			await Delay(0.08f);
		}
	}

	private async Task PlayReturnToDeck(ResolutionEvent e)
	{
		Vector3 from = _deathPositions.TryGetValue(e.PieceId, out Vector3 d) ? d : Board.GridToWorld(e.From);
		int player = e.PlayerIndex >= 0 ? e.PlayerIndex : OwnerOf(e.PieceId);
		Vector3 deck = GetDeckWorld(Mathf.Max(0, player));
		if (e.Amount > 0)
		{
			Sfx.Play(SfxId.Soul);
			Vfx.PopupText(Board, from, "Returns stronger!", SoulColor, 54, 1.25f);
			Vfx.PopupText(Board, from + new Vector3(0, -0.32f, 0), $"{e.CardName}", SoulColor.Lightened(0.4f), 40, 1.25f);
			Vfx.GlowFlash(Board, from + new Vector3(0, 0.3f, 0), SoulColor, 1.8f, 0.4f);
			Vfx.Sparkle(Board, from + new Vector3(0, 0.3f, 0), SoulColor, 16, 0.8f, 0.4f);
			_ = RuleVfx.SoulWisp(Board, from + new Vector3(0, 0.3f, 0), deck, 0.85f);
			await Delay(0.5f);
		}
		else
		{
			Sfx.Play(SfxId.CardDeal);
			_ = RuleVfx.CardToDeck(Board, from + new Vector3(0, 0.3f, 0), deck, GetOwnerColor(Mathf.Max(0, player)), 0.6f);
			await Delay(0.22f);
		}
	}

	private async Task PlaySpellCastEvent(IReadOnlyList<ResolutionEvent> events, int index)
	{
		ResolutionEvent e = events[index];
		if (e.PieceId >= 0)
		{
			// Buff look on the caster's own pieces, debuff look on enemy pieces.
			int owner = OwnerOf(e.PieceId);
			bool positive = e.PlayerIndex < 0 || owner < 0 || owner == e.PlayerIndex;
			if (!string.IsNullOrEmpty(e.CardName) && GetView(e.PieceId) is PieceView target)
			{
				Vfx.PopupText(Board, target.GlobalPosition + new Vector3(0, 0.25f, 0), e.CardName,
					positive ? BuffColor : DebuffColor, 50, 1.2f);
			}
			await PlaySpellCast(e.PieceId, positive);
			return;
		}
		Vector3 anchor = Board.GridToWorld(e.To);
		TileEffectType type = TileEffectType.None;
		var tiles = new List<Vector3>();
		for (int i = index + 1; i < events.Count; i++)
		{
			ResolutionEvent n = events[i];
			if (n == null || n.Type == ResolutionEventType.SpellCast)
			{
				break;
			}
			if (n.Type == ResolutionEventType.TileEffectApplied)
			{
				type = n.TileEffect;
				tiles.Add(Board.GridToWorld(n.To));
			}
		}
		Color nameColor = type switch
		{
			TileEffectType.Lava => RuleVfx.FireColor.Lightened(0.2f),
			TileEffectType.Wall => new Color(0.9f, 0.84f, 0.72f),
			TileEffectType.Healing => HealTextColor,
			_ => new Color(0.85f, 0.65f, 1f),
		};
		if (!string.IsNullOrEmpty(e.CardName))
		{
			Vfx.PopupText(Board, anchor, e.CardName, nameColor, 58, 1.5f);
		}
		switch (type)
		{
			case TileEffectType.Lava:
			{
				Sfx.Play(SfxId.MeteorFall);
				await RuleVfx.Meteor(Board, anchor + new Vector3(1.6f, 7.5f, -2.6f), anchor + new Vector3(0, 0.15f, 0), 0.36f);
				Sfx.Play(SfxId.Explosion);
				Vfx.ImpactSparks(Board, anchor + new Vector3(0, 0.3f, 0), RuleVfx.FireColor, 60, 1.5f);
				RuleVfx.FireBurst(Board, anchor, 1.6f);
				Vfx.Shockwave(Board, anchor + new Vector3(0, 0.05f, 0), RuleVfx.FireColor, 3.2f, 0.5f, 0.1f);
				Vfx.SmokePuff(Board, anchor + new Vector3(0, 0.3f, 0), new Color(0.2f, 0.15f, 0.12f), 16, 1.2f);
				Vfx.LightFlash(Board, anchor + new Vector3(0, 1f, 0), RuleVfx.FireColor, 8f, 6f, 0.5f);
				Shake(ShakeStrength * 2.2f, 0.32f);
				await Delay(0.08f);
				break;
			}
			case TileEffectType.Wall:
				RuleVfx.MagicCircle(Board, anchor, new Color(0.85f, 0.78f, 0.6f));
				foreach (Vector3 t in tiles)
				{
					Vfx.DustRing(Board, t, DustColor, 0.45f, 12);
				}
				Shake(ShakeStrength * 1.3f, 0.35f);
				await Delay(0.15f);
				break;
			case TileEffectType.Healing:
				RuleVfx.MagicCircle(Board, anchor, RuleVfx.HealGold);
				foreach (Vector3 t in tiles)
				{
					Vfx.GlowFlash(Board, t + new Vector3(0, 0.8f, 0), RuleVfx.HealGold, 1.6f, 0.45f);
					Vfx.Sparkle(Board, t + new Vector3(0, 0.9f, 0), RuleVfx.HealColor, 10, 0.9f, 0.3f);
				}
				Vfx.LightFlash(Board, anchor + new Vector3(0, 1.2f, 0), RuleVfx.HealGold, 5f, 5f, 0.5f);
				await Delay(0.25f);
				break;
			default:
				Sfx.Play(SfxId.BuffCast);
				RuleVfx.MagicCircle(Board, anchor, new Color(0.75f, 0.45f, 1f));
				await Delay(0.2f);
				break;
		}
	}

	// ------------------------------------------------------------------ triggers

	/// <summary>Deathrattle: a ghostly flash on the death tile, the effect's name, then its own visual.</summary>
	private async Task PlayDeathrattle(ResolutionEvent e)
	{
		Vector3 pos = Board.GridToWorld(e.From);
		Color color = e.SpellName switch
		{
			"Explode" => RuleVfx.FireColor,
			"Lava Pool" => RuleVfx.FireColor,
			"Last Blessing" => HealTextColor,
			"Rubble" => DustColor.Lightened(0.3f),
			"Last Word" => SoulColor,
			_ => new Color(0.85f, 0.9f, 1f),
		};
		Vfx.PopupText(Board, pos + new Vector3(0, 0.35f, 0), $"Deathrattle: {e.SpellName}", color, 52, 1.5f);
		Vfx.GlowFlash(Board, pos + new Vector3(0, 0.4f, 0), color, 2.2f, 0.35f);
		switch (e.SpellName)
		{
			case "Explode":
				Sfx.Play(SfxId.Explosion, -3f, 1.2f);
				RuleVfx.FireBurst(Board, pos, 1.4f);
				Vfx.Shockwave(Board, pos + new Vector3(0, 0.05f, 0), RuleVfx.FireColor, 2.4f, 0.4f, 0.1f);
				Vfx.SmokePuff(Board, pos + new Vector3(0, 0.3f, 0), new Color(0.2f, 0.15f, 0.12f), 12, 1f);
				Shake(ShakeStrength * 1.8f, 0.28f);
				break;
			case "Shockwave":
				Sfx.Play(SfxId.Push, 0f, 0.8f);
				Vfx.Shockwave(Board, pos + new Vector3(0, 0.05f, 0), new Color(1f, 0.9f, 0.7f), 2.6f, 0.4f, 0.12f);
				Vfx.DustRing(Board, pos, DustColor, 0.8f, 20);
				Shake(ShakeStrength * 1.2f, 0.2f);
				break;
			case "Last Blessing":
				Sfx.Play(SfxId.Heal);
				Vfx.Shockwave(Board, pos + new Vector3(0, 0.05f, 0), RuleVfx.HealGold, 3f, 0.6f, 0.08f);
				break;
			case "Last Word":
				Sfx.Play(SfxId.CardDeal);
				Vfx.Sparkle(Board, pos + new Vector3(0, 0.4f, 0), SoulColor, 16, 0.8f, 0.4f);
				break;
			default:
				Sfx.Play(SfxId.SpellFade, 4f);
				break;
		}
		await Delay(0.35f);
	}

	/// <summary>A building appears next to its builder: the token drops in as a scaffold with hammering.</summary>
	private async Task PlayBuildingStarted(ResolutionEvent e)
	{
		Piece building = _playState?.GetPiece(e.OtherPieceId);
		if (building == null)
		{
			return;
		}
		PieceView view = SpawnView(building);
		if (view == null)
		{
			return;
		}
		Sfx.Play(SfxId.Summon, -4f, 1.1f);
		Sfx.PlayDelayed(SfxId.Blocked, 0.25f, -6f, 1.3f);
		Sfx.PlayDelayed(SfxId.Blocked, 0.45f, -6f, 1.4f);
		Vfx.DustRing(Board, view.GlobalPosition, DustColor, 0.6f, 18);
		int turns = building.CompleteTurn > building.SummonedTurn ? (building.CompleteTurn - building.SummonedTurn) / 2 : 1;
		Vfx.PopupText(Board, view.GlobalPosition + new Vector3(0, 0.4f, 0), $"Building {e.SpellName} ({turns} turns)", new Color(1f, 0.85f, 0.55f), 46, 1.4f);
		await view.PlaySquash(0.8f);
	}

	/// <summary>First-hit effect: a burst on the piece and the effect's name; stat changes update the token.</summary>
	private async Task PlayFirstHit(ResolutionEvent e, PieceView view)
	{
		Vector3 pos = view != null ? view.GlobalPosition : Board.GridToWorld(e.To);
		Color color = e.SpellName switch
		{
			"Thorns" => new Color(0.55f, 0.9f, 0.35f),
			"Harden" => ShieldColor,
			"Enrage" => new Color(1f, 0.35f, 0.2f),
			_ => new Color(0.9f, 0.85f, 0.7f),
		};
		string text = e.SpellName switch
		{
			"Harden" => $"Harden +{e.Amount}",
			"Enrage" => $"Enrage +{e.Amount} Atk",
			_ => $"{e.SpellName}!",
		};
		Vfx.PopupText(Board, pos + new Vector3(0, 0.3f, 0), text, color, 50, 1.3f);
		Vfx.Sparkle(Board, pos + new Vector3(0, 0.35f, 0), color, 14, 0.7f, 0.4f);
		if (e.SpellName == "Shockwave")
		{
			Sfx.Play(SfxId.Push, 0f, 0.9f);
			Vfx.Shockwave(Board, pos + new Vector3(0, 0.05f, 0), new Color(1f, 0.9f, 0.7f), 2.2f, 0.35f, 0.12f);
		}
		else if (e.SpellName == "Harden")
		{
			Sfx.Play(SfxId.ShieldBlock);
		}
		else
		{
			Sfx.Play(SfxId.BuffCast, -2f);
		}
		if (view != null)
		{
			view.SetStats(e.RemainingHp, e.RemainingShield);
			if (_playState?.GetPiece(e.PieceId) is Piece live)
			{
				view.SetAttack(live.EffectiveAttack);
			}
			await view.PlayFlash(color, 0.25f);
		}
		else
		{
			await Delay(0.2f);
		}
	}

	// ------------------------------------------------------------------ helpers

	private void CachePiece(Piece piece)
	{
		_keywords[piece.Id] = piece.Keywords;
		_owners[piece.Id] = piece.OwnerIndex;
		_shields[piece.Id] = piece.TotalShield;
		_ranges[piece.Id] = piece.EffectiveRange;
	}

	private bool HasKeyword(int pieceId, Keyword keyword) =>
		_keywords.TryGetValue(pieceId, out Keyword k) && keyword != Keyword.None && (k & keyword) == keyword;

	private int OwnerOf(int pieceId) => _owners.TryGetValue(pieceId, out int o) ? o : -1;

	private void KillMotion(int pieceId)
	{
		if (_motionTweens.TryGetValue(pieceId, out Tween t))
		{
			if (t != null && t.IsValid())
			{
				t.Kill();
			}
			_motionTweens.Remove(pieceId);
		}
	}

	private CameraRig ResolveRig()
	{
		if (CameraRig != null && IsInstanceValid(CameraRig))
		{
			return CameraRig;
		}
		if (_rig != null && IsInstanceValid(_rig))
		{
			return _rig;
		}
		_rig = GetViewport()?.GetCamera3D()?.GetParent() as CameraRig;
		return _rig;
	}

	private async Task Delay(float seconds)
	{
		if (seconds <= 0f || !IsInsideTree())
		{
			return;
		}
		await ToSignal(GetTree().CreateTimer(seconds * AnimationPace), SceneTreeTimer.SignalName.Timeout);
	}
}
