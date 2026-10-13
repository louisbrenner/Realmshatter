using System;
using System.Collections.Generic;

namespace Realmshatter;

/// <summary>
/// Command interface for the rules. All mutating calls validate first; on failure they return
/// false / null and set LastError. Turn flow:
/// StartGame (deal hands) -> [StartTurn: tile ticks (Lava/Healing), score VP, check win, set AP] -> Main phase
/// (PlayUnitCard / PlaySpellCard / PlaySpellOnTile / Act / ConvertVpToAp / Draw -> Draft phase ->
/// ChooseDraftCard -> Main) -> EndTurn (expire spells/statuses/tile effects, swap player, TurnNumber++, StartTurn).
/// Act resolves a piece's move + attack IMMEDIATELY (there is no end-of-turn resolution); every piece acts at
/// most once per turn. AP costs: cards (GetCardCost), Draw (GameConfig.DrawApCost), an action
/// (GameConfig.OrderApCost). Pieces are summoning sick on the turn they were summoned.
/// Up to GameConfig.MaxVpToApPerTurn VP can be converted into AP per turn (1:1). Player 1 gets
/// GameConfig.SecondPlayerFirstTurnBonusAp extra AP on its first turn.
/// </summary>
public sealed class TurnController
{
	public GameState State { get; }
	public string LastError { get; private set; } = "";

	/// <summary>Raised after a turn has started (after ticks/scoring/AP). Arg: player index.</summary>
	public event Action<int> TurnStarted;
	/// <summary>Raised when a player scores at turn start. Args: player index, points gained.</summary>
	public event Action<int, int> VictoryPointsScored;
	/// <summary>Raised when a draft offer is ready (after a successful Draw). Arg: player index.</summary>
	public event Action<int> DraftOffered;
	/// <summary>Raised after a piece action (Act) resolved, with its events.</summary>
	public event Action<IReadOnlyList<ResolutionEvent>> ActionResolved;
	/// <summary>Raised in EndTurn after spells / statuses / tile effects expired (before the next turn starts).</summary>
	public event Action<IReadOnlyList<ResolutionEvent>> TurnEnded;
	/// <summary>Raised at turn start (before scoring) when tile ticks produced events (Lava damage, healing).</summary>
	public event Action<IReadOnlyList<ResolutionEvent>> TurnStartResolved;
	/// <summary>Raised after a spell was cast (piece or tile spell) with its immediate events.</summary>
	public event Action<IReadOnlyList<ResolutionEvent>> SpellResolved;
	/// <summary>Raised when a winner is determined. Arg: winner index.</summary>
	public event Action<int> GameOver;
	/// <summary>Raised after any successful state change.</summary>
	public event Action StateChanged;

	private List<ResolutionEvent> _lastTurnStartEvents = new List<ResolutionEvent>();
	private List<ResolutionEvent> _lastSpellEvents = new List<ResolutionEvent>();
	private List<ResolutionEvent> _lastActionEvents = new List<ResolutionEvent>();

	/// <summary>Tile-tick events of the most recent turn start (Lava/Healing). Animate them after EndTurn's events.</summary>
	public IReadOnlyList<ResolutionEvent> LastTurnStartEvents => _lastTurnStartEvents;
	/// <summary>Immediate events of the most recently cast spell (SpellCast, Damaged, Healed, TileEffectApplied...).</summary>
	public IReadOnlyList<ResolutionEvent> LastSpellEvents => _lastSpellEvents;
	/// <summary>Events of the most recent piece action (Moved, Attacked, Damaged, Died...).</summary>
	public IReadOnlyList<ResolutionEvent> LastActionEvents => _lastActionEvents;

	public TurnController(GameState state)
	{
		State = state ?? throw new ArgumentNullException(nameof(state));
	}

	/// <summary>Deals starting hands and starts turn 1 for player 0.</summary>
	public void StartGame()
	{
		State.CurrentPlayerIndex = 0;
		State.TurnNumber = 1;
		State.Winner = -1;
		foreach (PlayerState player in State.Players)
		{
			for (int i = 0; i < State.Config.StartingHandSize && player.Deck.Count > 0; i++)
			{
				player.Hand.Add(DrawRandom(player.Deck));
			}
		}
		StartTurn();
	}

	/// <summary>
	/// Starts the current player's turn: tile ticks for its pieces (Lava damage / Healing, see
	/// LastTurnStartEvents), VP per own piece in the scoring zone (1, crown field HotZonePoints), win check,
	/// AP = BaseAp + sum of own ApBonus (+ second-player bonus on player 1's first turn), then Main phase.
	/// </summary>
	public void StartTurn()
	{
		int idx = State.CurrentPlayerIndex;
		PlayerState player = State.CurrentPlayer;
		player.TurnsStarted++;
		player.VpConvertedThisTurn = 0;

		_lastTurnStartEvents = OrderResolver.ResolveTurnStart(State, idx);
		_lastTurnStartEvents.AddRange(OrderResolver.ResolveBuildingsTurnStart(State, idx));
		_lastTurnStartEvents.AddRange(OrderResolver.ResolveAuras(State, idx));
		_lastTurnStartEvents.AddRange(OrderResolver.ResolveLegends(State, idx));
		if (_lastTurnStartEvents.Count > 0)
		{
			TurnStartResolved?.Invoke(_lastTurnStartEvents);
		}

		int scored = 0;
		int apBonus = 0;
		foreach (Piece p in State.GetPiecesOf(idx))
		{
			if (p.IsBuilding)
			{
				if (p.Building == BuildingType.ManaWell && !p.UnderConstruction)
				{
					apBonus += State.Config.ManaWellAp;
				}
				continue;
			}
			if (p.CanScore)
			{
				scored += State.Board.ScoreValue(p.Position);
			}
			apBonus += p.ApBonus;
		}
		if (scored > 0)
		{
			player.VictoryPoints += scored;
			VictoryPointsScored?.Invoke(idx, scored);
		}
		if (player.VictoryPoints >= State.Config.PointsTarget)
		{
			State.Winner = idx;
			State.Phase = GamePhase.GameOver;
			GameOver?.Invoke(idx);
			StateChanged?.Invoke();
			return;
		}

		player.ActionPoints = State.Config.BaseAp + apBonus + player.PendingAp + player.BonusApPerTurn;
		player.PendingAp = 0;
		if (idx == 1 && player.TurnsStarted == 1)
		{
			player.ActionPoints += Math.Max(0, State.Config.SecondPlayerFirstTurnBonusAp);
		}

		ReturnDraftOffer(player);
		State.Phase = GamePhase.Main;

		TurnStarted?.Invoke(idx);
		StateChanged?.Invoke();
	}

	// ------------------------------------------------------------------ VP -> AP

	/// <summary>VP the current player converted into AP this turn.</summary>
	public int VpConvertedThisTurn => State.CurrentPlayer.VpConvertedThisTurn;

	/// <summary>Conversions the current player has left this turn (ignores whether it has VP).</summary>
	public int RemainingVpConversions => Math.Max(0, State.Config.MaxVpToApPerTurn - State.CurrentPlayer.VpConvertedThisTurn);

	/// <summary>True if the current player may convert 1 VP into 1 AP now (Main phase, VP >= 1, per-turn limit).</summary>
	public bool CanConvertVpToAp()
	{
		if (State.Phase != GamePhase.Main) return Fail("Not in main phase.");
		PlayerState player = State.CurrentPlayer;
		if (player.VictoryPoints < 1) return Fail("No victory points to convert.");
		if (RemainingVpConversions <= 0) return Fail($"Already converted {State.Config.MaxVpToApPerTurn} VP this turn.");
		return true;
	}

	/// <summary>Converts 1 VP into 1 AP for the current player (max GameConfig.MaxVpToApPerTurn per turn).</summary>
	public bool ConvertVpToAp()
	{
		if (!CanConvertVpToAp())
		{
			return false;
		}
		PlayerState player = State.CurrentPlayer;
		player.VictoryPoints -= 1;
		player.ActionPoints += 1;
		player.VpConvertedThisTurn++;
		StateChanged?.Invoke();
		return true;
	}

	// ------------------------------------------------------------------ draw / draft

	/// <summary>Checks whether the current player may use the Draw action (Main phase, non-empty deck, enough AP).</summary>
	public bool CanDraw()
	{
		if (State.Phase != GamePhase.Main) return Fail("Not in main phase.");
		PlayerState player = State.CurrentPlayer;
		if (player.Deck.Count == 0) return Fail("Deck is empty.");
		if (State.Config.DrawApCost > player.ActionPoints) return Fail("Not enough AP.");
		return true;
	}

	/// <summary>
	/// Pays GameConfig.DrawApCost and creates a draft offer of up to DraftOfferSize cards (Draft phase).
	/// Must be completed with ChooseDraftCard; it cannot be cancelled. Can be used several times per turn.
	/// </summary>
	public bool Draw()
	{
		if (!CanDraw())
		{
			return false;
		}
		PlayerState player = State.CurrentPlayer;
		player.ActionPoints -= State.Config.DrawApCost;
		ReturnDraftOffer(player);
		for (int i = 0; i < State.Config.DraftOfferSize && player.Deck.Count > 0; i++)
		{
			player.DraftOffer.Add(DrawRandom(player.Deck));
		}
		State.Phase = GamePhase.Draft;
		DraftOffered?.Invoke(State.CurrentPlayerIndex);
		StateChanged?.Invoke();
		return true;
	}

	/// <summary>Takes the offered card at offerIndex into the hand; the rest return to the deck. Returns to Main phase.</summary>
	public bool ChooseDraftCard(int offerIndex)
	{
		PlayerState player = State.CurrentPlayer;
		if (State.Phase != GamePhase.Draft)
		{
			return Fail("Not in draft phase.");
		}
		if (offerIndex < 0 || offerIndex >= player.DraftOffer.Count)
		{
			return Fail("Invalid draft index.");
		}
		CardData chosen = player.DraftOffer[offerIndex];
		player.DraftOffer.RemoveAt(offerIndex);
		player.Hand.Add(chosen);
		ReturnDraftOffer(player);
		State.Phase = GamePhase.Main;
		StateChanged?.Invoke();
		return true;
	}

	// ------------------------------------------------------------------ cards

	/// <summary>AP cost of a card: its ApCost if &gt; 0, else GameConfig.UnitApCost / SpellApCost.</summary>
	public int GetCardCost(CardData card)
	{
		if (card.ApCost > 0)
		{
			return card.ApCost;
		}
		return card.CardType == CardType.Spell ? State.Config.SpellApCost : State.Config.UnitApCost;
	}

	/// <summary>Checks whether the current player may deploy this unit card on pos (no side effects).</summary>
	public bool CanPlayUnitCard(CardData card, GridPos pos)
	{
		if (State.Phase != GamePhase.Main) return Fail("Not in main phase.");
		if (card == null || card.CardType != CardType.Unit) return Fail("Not a unit card.");
		PlayerState player = State.CurrentPlayer;
		if (!player.Hand.Contains(card)) return Fail("Card not in hand.");
		if (GetCardCost(card) > player.ActionPoints) return Fail("Not enough AP.");
		if (card.HasKeyword(Keyword.Planted))
		{
			if (!IsValidPlantTile(pos)) return Fail($"Planted units go within {State.Config.PlantRadius} tiles of one of your units (not on the crown).");
		}
		else if (!State.Board.IsInDeployZone(State.CurrentPlayerIndex, pos)) return Fail("Not in own deploy rows.");
		if (State.Board.IsWall(pos)) return Fail("A wall blocks this tile.");
		if (State.Board.IsOccupied(pos)) return Fail("Tile occupied.");
		return true;
	}

	/// <summary>
	/// Planted units: the own deploy rows, or any tile within GameConfig.PlantRadius of one of the current player's
	/// units (buildings do not count). Never the crown field.
	/// </summary>
	private bool IsValidPlantTile(GridPos pos)
	{
		if (!State.Board.IsInside(pos) || State.Board.IsInHotZone(pos))
		{
			return false;
		}
		if (State.Board.IsInDeployZone(State.CurrentPlayerIndex, pos))
		{
			return true;
		}
		foreach (Piece p in State.GetPiecesOf(State.CurrentPlayerIndex))
		{
			if (!p.IsBuilding && p.Position.ManhattanDistance(pos) <= State.Config.PlantRadius)
			{
				return true;
			}
		}
		return false;
	}

	/// <summary>Deploys a unit card from the hand on pos. Returns the new piece, or null on failure.</summary>
	public Piece PlayUnitCard(CardData card, GridPos pos)
	{
		if (!CanPlayUnitCard(card, pos))
		{
			return null;
		}
		PlayerState player = State.CurrentPlayer;
		player.ActionPoints -= GetCardCost(card);
		player.Hand.Remove(card);
		Piece piece = State.SpawnPiece(card, State.CurrentPlayerIndex, pos);
		StateChanged?.Invoke();
		return piece;
	}

	/// <summary>
	/// Checks whether the current player may cast this spell on target (any living piece). For tile/area
	/// spells (CardData.TargetsTile) this checks CanPlaySpellOnTile(card, target.Position) instead.
	/// </summary>
	public bool CanPlaySpellCard(CardData card, Piece target)
	{
		if (card != null && card.TargetsTile)
		{
			if (target == null || State.GetPiece(target.Id) == null) return Fail("Invalid target.");
			return CanPlaySpellOnTile(card, target.Position);
		}
		if (!CheckSpellBasics(card)) return false;
		if (target == null || !target.IsAlive || State.GetPiece(target.Id) == null) return Fail("Invalid target.");
		if (!IsInSpellRange(target.Position)) return Fail($"Too far from your units (spells reach {State.Config.SpellCastRadius} tiles).");
		return true;
	}

	/// <summary>
	/// Casts a spell on a piece. Lasts until the end of the caster's next turn (ExpiryTurn = TurnNumber + 2).
	/// HpDelta changes max and current HP immediately (a spell never reduces HP below 1);
	/// ShieldDelta grants a temporary shield that absorbs damage first; GrantStatus adds a status
	/// (GameConfig.SpellStatusDuration). Tile/area spells are redirected to PlaySpellOnTile(card, target.Position).
	/// Immediate events: LastSpellEvents.
	/// </summary>
	public bool PlaySpellCard(CardData card, Piece target)
	{
		if (card != null && card.TargetsTile)
		{
			return CanPlaySpellCard(card, target) && PlaySpellOnTile(card, target.Position);
		}
		if (!CanPlaySpellCard(card, target))
		{
			return false;
		}
		PlayerState player = State.CurrentPlayer;
		player.ActionPoints -= GetCardCost(card);
		player.Hand.Remove(card);

		int power = SpellPower(target.Position);
		var events = new List<ResolutionEvent>
		{
			new ResolutionEvent
			{
				Type = ResolutionEventType.SpellCast,
				PieceId = target.Id,
				PlayerIndex = State.CurrentPlayerIndex,
				From = target.Position,
				To = target.Position,
				CardName = card.Name,
				Amount = power,
			},
		};
		SpellEffect effect = SpellEffect.FromCard(card, power);
		bool hasModifiers = effect.AttackDelta != 0 || effect.HpDelta != 0 || effect.ShieldDelta != 0
			|| effect.MovementDelta != 0 || effect.RangeDelta != 0;
		if (hasModifiers || (card.GrantStatus == StatusEffectType.None && card.ApGain <= 0))
		{
			target.ActiveSpells.Add(new ActiveSpell(card, effect, State.CurrentPlayerIndex, State.TurnNumber, State.TurnNumber + 2));
			target.CurrentHp = Math.Clamp(target.CurrentHp + effect.HpDelta, 1, target.MaxHp);
		}
		if (card.GrantStatus != StatusEffectType.None)
		{
			OrderResolver.ApplyStatus(State, target, card.GrantStatus, State.Config.SpellStatusDuration + power, card.Name, -1, events);
		}
		OrderResolver.GrantAp(State, State.CurrentPlayerIndex, card.ApGain, -1, card.Name, target.Position, events);
		FinishSpell(events);
		return true;
	}

	/// <summary>
	/// Checks whether the current player may cast a tile/area spell anchored at 'tile': Main phase, card in hand,
	/// enough AP, tile on the board, and (for Wall spells) at least one free tile in the area.
	/// </summary>
	public bool CanPlaySpellOnTile(CardData card, GridPos tile)
	{
		if (!CheckSpellBasics(card)) return false;
		if (!card.TargetsTile) return Fail("This spell targets a piece.");
		if (!State.Board.IsInside(tile)) return Fail("Invalid tile.");
		if (!IsInSpellRange(tile)) return Fail($"Too far from your units (spells reach {State.Config.SpellCastRadius} tiles).");
		if (card.TileEffect == TileEffectType.Wall && card.SpellDamage <= 0 && card.SpellHeal <= 0)
		{
			bool any = false;
			foreach (GridPos p in GetSpellAreaPreview(card, tile))
			{
				any |= !State.Board.IsOccupied(p);
			}
			if (!any) return Fail("No free tile for the wall.");
		}
		return true;
	}

	/// <summary>
	/// Casts a tile/area spell: SpellCast event, SpellDamage to every enemy piece in the area, SpellHeal to every
	/// friendly piece in it, then TileEffect on every area tile for TileEffectDuration turns (walls skip occupied
	/// tiles). Immediate events: LastSpellEvents (also raised via SpellResolved).
	/// </summary>
	public bool PlaySpellOnTile(CardData card, GridPos tile)
	{
		if (!CanPlaySpellOnTile(card, tile))
		{
			return false;
		}
		int caster = State.CurrentPlayerIndex;
		PlayerState player = State.CurrentPlayer;
		player.ActionPoints -= GetCardCost(card);
		player.Hand.Remove(card);

		// Obelisk: +1 damage, healing and duration.
		int power = SpellPower(tile);
		int damage = SpellEffect.Boost(card.SpellDamage, power);
		int heal = SpellEffect.Boost(card.SpellHeal, power);
		int duration = card.TileEffectDuration + power;
		var events = new List<ResolutionEvent>
		{
			new ResolutionEvent { Type = ResolutionEventType.SpellCast, PlayerIndex = caster, From = tile, To = tile, CardName = card.Name, Amount = power },
		};
		List<GridPos> area = GetSpellAreaPreview(card, tile);
		foreach (GridPos p in area)
		{
			Piece piece = State.Board.GetPieceAt(p);
			if (piece == null)
			{
				if (damage > 0 && State.Board.GetTerrain(p) == TerrainType.Rock)
				{
					OrderResolver.DamageRock(State, p, damage, events);
				}
				continue;
			}
			if (piece.OwnerIndex != caster && damage > 0)
			{
				OrderResolver.ApplyDamage(State, piece, damage, -1, events);
			}
			else if (piece.OwnerIndex == caster && heal > 0)
			{
				OrderResolver.ApplyHeal(State, piece, heal, -1, events);
			}
		}
		if (card.SpellPush)
		{
			// Farthest pieces first so the inner ones are not blocked by their own neighbours.
			var pushed = new List<Piece>();
			foreach (GridPos p in area)
			{
				Piece piece = State.Board.GetPieceAt(p);
				if (piece != null)
				{
					pushed.Add(piece);
				}
			}
			pushed.Sort((a, b) => b.Position.ManhattanDistance(tile).CompareTo(a.Position.ManhattanDistance(tile)));
			foreach (Piece piece in pushed)
			{
				GridPos dir = piece.Position == tile
					? new GridPos(0, BoardState.ForwardDirection(caster))
					: OrderResolver.AttackDirection(tile, piece.Position);
				OrderResolver.PushPiece(State, piece, dir, -1, events);
			}
		}
		if (card.TileEffect != TileEffectType.None)
		{
			foreach (GridPos p in area)
			{
				OrderResolver.ApplyTileEffect(State, card.TileEffect, p, duration, caster, card.Name, -1, events);
			}
		}
		OrderResolver.GrantAp(State, caster, card.ApGain, -1, card.Name, tile, events);
		FinishSpell(events);
		return true;
	}

	/// <summary>Unified check: piece spells need a piece on 'tile', tile/area spells use CanPlaySpellOnTile.</summary>
	public bool CanCastSpellAt(CardData card, GridPos tile)
	{
		if (card != null && card.TargetsTile)
		{
			return CanPlaySpellOnTile(card, tile);
		}
		return CanPlaySpellCard(card, State.Board.GetPieceAt(tile));
	}

	/// <summary>Unified cast: piece spells on the piece standing on 'tile', tile/area spells on the tile.</summary>
	public bool CastSpellAt(CardData card, GridPos tile)
	{
		if (card != null && card.TargetsTile)
		{
			return PlaySpellOnTile(card, tile);
		}
		return PlaySpellCard(card, State.Board.GetPieceAt(tile));
	}

	/// <summary>Tiles a spell would affect when anchored at 'tile' (piece spells: just that tile). For highlights.</summary>
	public List<GridPos> GetSpellAreaPreview(CardData card, GridPos tile)
	{
		if (card == null || !State.Board.IsInside(tile))
		{
			return new List<GridPos>();
		}
		AreaShape shape = card.SpellTarget == SpellTargetType.Area ? card.AreaShape : AreaShape.Single;
		return State.Board.GetAreaTiles(tile, shape);
	}

	/// <summary>All tiles where CanCastSpellAt(card, tile) is true (for highlights).</summary>
	public List<GridPos> GetValidSpellTiles(CardData card)
	{
		var result = new List<GridPos>();
		for (int y = 0; y < State.Board.Height; y++)
		{
			for (int x = 0; x < State.Board.Width; x++)
			{
				var pos = new GridPos(x, y);
				if (CanCastSpellAt(card, pos))
				{
					result.Add(pos);
				}
			}
		}
		return result;
	}

	// ------------------------------------------------------------------ piece actions

	/// <summary>
	/// Valid move destinations for a piece (excluding its own tile). Friendly pieces do not block and may be a
	/// destination (they get pushed); enemies and walls block. Frozen pieces cannot move.
	/// </summary>
	public List<GridPos> GetValidMoveTargets(Piece piece) =>
		piece.ConstructingId >= 0 || piece.IsBuilding || piece.HasKeyword(Keyword.Planted)
			? new List<GridPos>()
			: State.Board.GetReachableTiles(piece.Position, piece.EffectiveMovement, piece.OwnerIndex);

	/// <summary>
	/// True if the current player may cast a spell centred on 'tile': within GameConfig.SpellCastRadius
	/// (Manhattan) of one of its units.
	/// </summary>
	public bool IsInSpellRange(GridPos tile)
	{
		foreach (Piece p in State.GetPiecesOf(State.CurrentPlayerIndex))
		{
			int d = p.Position.ManhattanDistance(tile);
			if (!p.IsBuilding && d <= State.Config.SpellCastRadius)
			{
				return true;
			}
		}
		return false;
	}

	/// <summary>All tiles where the current player may centre a spell (IsInSpellRange), for the cast range overlay.</summary>
	public List<GridPos> GetSpellRangeTiles()
	{
		var result = new List<GridPos>();
		for (int y = 0; y < State.Board.Height; y++)
		{
			for (int x = 0; x < State.Board.Width; x++)
			{
				var pos = new GridPos(x, y);
				if (IsInSpellRange(pos))
				{
					result.Add(pos);
				}
			}
		}
		return result;
	}

	/// <summary>
	/// Tiles a building standing on 'at' covers: Turret = its shooting range, Shrine = the 8 surrounding tiles,
	/// Obelisk = its spell cast radius; clan buildings add the 8 tiles their aura pulses onto. Empty for buildings
	/// without a range.
	/// </summary>
	public List<GridPos> GetBuildingRangeTiles(BuildingType type, GridPos at, int turretRange, Clan clan = Clan.None)
	{
		var result = new List<GridPos>();
		for (int y = 0; y < State.Board.Height; y++)
		{
			for (int x = 0; x < State.Board.Width; x++)
			{
				var pos = new GridPos(x, y);
				bool inRange = type switch
				{
					BuildingType.Turret => State.Board.IsInAttackRange(at, pos, turretRange),
					BuildingType.Shrine => pos != at && Math.Abs(pos.X - at.X) <= 1 && Math.Abs(pos.Y - at.Y) <= 1,
					BuildingType.Obelisk => at.ManhattanDistance(pos) <= State.Config.ObeliskEmpowerRadius,
					_ => false,
				};
				inRange |= clan != Clan.None && pos != at && Math.Abs(pos.X - at.X) <= 1 && Math.Abs(pos.Y - at.Y) <= 1;
				if (inRange)
				{
					result.Add(pos);
				}
			}
		}
		return result;
	}

	/// <summary>Trap a Trapper sets (by its clan), or null if the piece is no Trapper.</summary>
	public TrapType? GetTrapType(Piece piece) =>
		piece != null && !piece.IsBuilding && piece.HasKeyword(Keyword.Trapper) && piece.Source != null
			? TrapInfo.ForClan(piece.Source.Clan)
			: null;

	/// <summary>Free tiles next to 'from' (default: the piece's tile; 8 directions) where it could hide a trap.</summary>
	public List<GridPos> GetValidTrapTiles(Piece piece, GridPos? from = null)
	{
		var result = new List<GridPos>();
		if (piece == null)
		{
			return result;
		}
		GridPos at = from ?? piece.Position;
		for (int dy = -1; dy <= 1; dy++)
		{
			for (int dx = -1; dx <= 1; dx++)
			{
				var tile = new GridPos(at.X + dx, at.Y + dy);
				Piece occupant = State.Board.GetPieceAt(tile);
				if ((dx != 0 || dy != 0) && State.Board.IsPassable(tile) && (occupant == null || occupant == piece)
					&& State.Board.GetTrap(tile) == null && !State.Board.IsInHotZone(tile))
				{
					result.Add(tile);
				}
			}
		}
		return result;
	}

	/// <summary>Checks a trap command: commandable Trapper, AP, an optional reachable move first, a valid tile next to the destination.</summary>
	public bool CanSetTrap(Piece piece, GridPos tile, GridPos? move)
	{
		if (!CanCommand(piece)) return false;
		if (!GetTrapType(piece).HasValue) return Fail("This unit cannot set traps.");
		if (piece.ConstructingId >= 0) return Fail("Busy building.");
		if (State.Config.TrapApCost > State.CurrentPlayer.ActionPoints) return Fail("Not enough AP.");
		bool moves = move.HasValue && move.Value != piece.Position;
		if (moves && State.Board.FindPath(piece.Position, move.Value, piece.EffectiveMovement, piece.OwnerIndex) == null)
		{
			return Fail(piece.IsFrozen ? "Frozen - cannot move this turn." : "Move target not reachable.");
		}
		if (!GetValidTrapTiles(piece, moves ? move : null).Contains(tile) || (moves && tile == move.Value))
		{
			return Fail("Hide the trap on a free tile next to the unit.");
		}
		return true;
	}

	/// <summary>
	/// Trap command: pays GameConfig.TrapApCost and uses the piece's action. The piece first makes its move (if any,
	/// enemy traps may stop it), then hides its clan's trap on 'tile'. A Trapper keeps at most
	/// GameConfig.MaxTrapsPerTrapper traps; its oldest one disappears. Returns the events or null.
	/// </summary>
	public List<ResolutionEvent> SetTrap(Piece piece, GridPos tile, GridPos? move)
	{
		if (!CanSetTrap(piece, tile, move))
		{
			return null;
		}
		TrapType type = GetTrapType(piece).Value;
		State.CurrentPlayer.ActionPoints -= Math.Max(0, State.Config.TrapApCost);
		piece.ActedTurn = State.TurnNumber;
		var events = new List<ResolutionEvent>();
		if (move.HasValue && move.Value != piece.Position)
		{
			events.AddRange(OrderResolver.ResolveAction(State, piece, move, null));
		}
		bool adjacent = Math.Abs(tile.X - piece.Position.X) <= 1 && Math.Abs(tile.Y - piece.Position.Y) <= 1;
		if (piece.IsAlive && State.GetPiece(piece.Id) != null && adjacent && State.Board.IsPassable(tile)
			&& !State.Board.IsOccupied(tile) && State.Board.GetTrap(tile) == null)
		{
			var own = new List<Trap>();
			foreach (Trap t in State.Board.Traps.Values)
			{
				if (t.SourcePieceId == piece.Id)
				{
					own.Add(t);
				}
			}
			own.Sort((a, b) => a.Serial.CompareTo(b.Serial));
			for (int i = 0; i <= own.Count - Math.Max(1, State.Config.MaxTrapsPerTrapper); i++)
			{
				State.Board.RemoveTrap(own[i].Position);
			}
			State.Board.AddTrap(tile, piece.OwnerIndex, type, piece.Id);
			events.Add(new ResolutionEvent
			{
				Type = ResolutionEventType.TrapSet,
				PieceId = piece.Id,
				PlayerIndex = piece.OwnerIndex,
				From = piece.Position,
				To = tile,
				CardName = TrapInfo.GetName(type),
				SpellName = type.ToString(),
			});
		}
		_lastActionEvents = events;
		ActionResolved?.Invoke(_lastActionEvents);
		StateChanged?.Invoke();
		return _lastActionEvents;
	}

	/// <summary>
	/// Spell power bonus for a spell of the current player aimed at 'target': 1 if one of its finished Obelisks
	/// stands within GameConfig.ObeliskEmpowerRadius, else 0 (several Obelisks do not stack).
	/// </summary>
	public int SpellPower(GridPos target)
	{
		foreach (Piece p in State.GetPiecesOf(State.CurrentPlayerIndex))
		{
			if (p.Building == BuildingType.Obelisk && !p.UnderConstruction && p.Position.ManhattanDistance(target) <= State.Config.ObeliskEmpowerRadius)
			{
				return 1;
			}
		}
		return 0;
	}

	/// <summary>The building this piece could construct (None if it is no Builder or its class builds nothing).</summary>
	public BuildingType GetBuildType(Piece piece) =>
		piece != null && !piece.IsBuilding && piece.HasKeyword(Keyword.Builder) && piece.Source != null
			? BuildingInfo.ForClass(piece.Source.Class)
			: BuildingType.None;

	/// <summary>
	/// Free tiles next to 'from' (default: the piece's tile; 8 directions) where the piece could build after
	/// moving there. The piece's own current tile counts as free when it builds from somewhere else.
	/// </summary>
	public List<GridPos> GetValidBuildTiles(Piece piece, GridPos? from = null)
	{
		var result = new List<GridPos>();
		if (piece == null)
		{
			return result;
		}
		GridPos at = from ?? piece.Position;
		for (int dy = -1; dy <= 1; dy++)
		{
			for (int dx = -1; dx <= 1; dx++)
			{
				var tile = new GridPos(at.X + dx, at.Y + dy);
				Piece occupant = State.Board.GetPieceAt(tile);
				if ((dx != 0 || dy != 0) && State.Board.IsPassable(tile) && (occupant == null || occupant == piece)
					&& !State.Board.IsInDeployZone(1 - piece.OwnerIndex, tile) && !State.Board.IsInHotZone(tile))
				{
					result.Add(tile);
				}
			}
		}
		return result;
	}

	/// <summary>CanBuild with a single tile and no move.</summary>
	public bool CanBuild(Piece piece, GridPos tile) => CanBuild(piece, new[] { tile }, null);

	/// <summary>
	/// Checks a build command: commandable Builder, not already building, enough AP, an optional reachable move
	/// first (the build replaces the attack), and 1..BuildingInfo.GetBuildCount distinct free tiles next to the
	/// destination.
	/// </summary>
	public bool CanBuild(Piece piece, IReadOnlyList<GridPos> tiles, GridPos? move)
	{
		if (!CanCommand(piece)) return false;
		BuildingType type = GetBuildType(piece);
		if (type == BuildingType.None) return Fail("This unit cannot build.");
		if (piece.ConstructingId >= 0) return Fail("Already building something.");
		if (BuildingInfo.GetCost(type) > State.CurrentPlayer.ActionPoints) return Fail("Not enough AP.");
		bool moves = move.HasValue && move.Value != piece.Position;
		if (moves && State.Board.FindPath(piece.Position, move.Value, piece.EffectiveMovement, piece.OwnerIndex) == null)
		{
			return Fail(piece.IsFrozen ? "Frozen - cannot move this turn." : "Move target not reachable.");
		}
		if (tiles == null || tiles.Count == 0 || tiles.Count > BuildingInfo.GetBuildCount(type)) return Fail("Choose where to build.");
		List<GridPos> valid = GetValidBuildTiles(piece, moves ? move : null);
		var seen = new HashSet<GridPos>();
		foreach (GridPos tile in tiles)
		{
			if (!seen.Add(tile) || !valid.Contains(tile) || (moves && tile == move.Value))
			{
				return Fail("Build on free tiles next to the unit.");
			}
		}
		return true;
	}

	/// <summary>Build on one tile without moving.</summary>
	public List<ResolutionEvent> Build(Piece piece, GridPos tile) => Build(piece, new[] { tile }, null);

	/// <summary>
	/// Build command: pays the building's AP cost and uses the piece's action. The piece first makes its move (if
	/// any; it resolves like a normal move, Turrets may shoot), then places its building(s) on the given tiles next
	/// to it (Barricades: up to two) and stays pinned until they are finished (BuildingInfo.GetBuildTurns own turns
	/// later). Returns the events or null.
	/// </summary>
	public List<ResolutionEvent> Build(Piece piece, IReadOnlyList<GridPos> tiles, GridPos? move)
	{
		if (!CanBuild(piece, tiles, move))
		{
			return null;
		}
		BuildingType type = GetBuildType(piece);
		State.CurrentPlayer.ActionPoints -= BuildingInfo.GetCost(type);
		piece.ActedTurn = State.TurnNumber;
		var events = new List<ResolutionEvent>();
		if (move.HasValue && move.Value != piece.Position)
		{
			events.AddRange(OrderResolver.ResolveAction(State, piece, move, null));
		}
		if (piece.IsAlive && State.GetPiece(piece.Id) != null)
		{
			foreach (GridPos tile in tiles)
			{
				// A push chain or a Turret shot during the move may have changed the board: skip blocked tiles.
				if (!State.Board.IsPassable(tile) || State.Board.IsOccupied(tile)
					|| System.Math.Abs(tile.X - piece.Position.X) > 1 || System.Math.Abs(tile.Y - piece.Position.Y) > 1)
				{
					continue;
				}
				Piece building = State.SpawnBuilding(type, piece.OwnerIndex, tile, State.TurnNumber + 2 * BuildingInfo.GetBuildTurns(type), piece.Id,
					piece.Source.Clan);
				if (piece.ConstructingId < 0)
				{
					piece.ConstructingId = building.Id;
				}
				events.Add(new ResolutionEvent
				{
					Type = ResolutionEventType.BuildingStarted,
					PieceId = piece.Id,
					OtherPieceId = building.Id,
					PlayerIndex = piece.OwnerIndex,
					From = piece.Position,
					To = tile,
					SpellName = BuildingInfo.GetName(type, piece.Source.Clan),
					ExpiryTurn = building.CompleteTurn,
				});
			}
		}
		_lastActionEvents = events;
		ActionResolved?.Invoke(_lastActionEvents);
		StateChanged?.Invoke();
		return _lastActionEvents;
	}

	/// <summary>
	/// Shortest path for a move (same rules as GetValidMoveTargets): the tiles after the piece's position,
	/// ending with target. Empty if target is the current tile or unreachable.
	/// </summary>
	public List<GridPos> GetPlannedPath(Piece piece, GridPos target)
	{
		if (piece == null)
		{
			return new List<GridPos>();
		}
		return State.Board.FindPath(piece.Position, target, piece.EffectiveMovement, piece.OwnerIndex) ?? new List<GridPos>();
	}

	/// <summary>Valid attack tiles for a piece standing at fromPos (default: its current position).</summary>
	public List<GridPos> GetValidAttackTargets(Piece piece, GridPos? fromPos = null) =>
		State.Board.GetTilesInRange(fromPos ?? piece.Position, piece.EffectiveRange);

	/// <summary>
	/// True if the current player may command this piece now: Main phase, own living piece, not summoning sick,
	/// not acted yet this turn. Does not check AP.
	/// </summary>
	public bool CanCommand(Piece piece)
	{
		if (State.Phase != GamePhase.Main) return Fail("Not in main phase.");
		if (piece == null || State.GetPiece(piece.Id) == null) return Fail("Invalid piece.");
		if (piece.OwnerIndex != State.CurrentPlayerIndex) return Fail("Not your piece.");
		if (piece.IsSummoningSick(State.TurnNumber)) return Fail("Summoning sick - can act next turn.");
		if (piece.IsBuilding) return Fail("Buildings cannot be commanded.");
		if (piece.HasActed(State.TurnNumber)) return Fail("Already acted this turn.");
		return true;
	}

	/// <summary>
	/// Checks an action without applying it: CanCommand, GameConfig.OrderApCost AP, the move must be reachable
	/// (GetValidMoveTargets) and the attack tile in range from the destination. At least a move or an attack.
	/// </summary>
	public bool CanAct(Piece piece, GridPos? move, GridPos? attack)
	{
		if (!CanCommand(piece)) return false;
		bool moves = move.HasValue && move.Value != piece.Position;
		if (!moves && !attack.HasValue) return Fail("Nothing to do.");
		if (State.Config.OrderApCost > State.CurrentPlayer.ActionPoints) return Fail("Not enough AP.");
		if (moves && piece.ConstructingId >= 0) return Fail("Busy building - it cannot move until the building is finished.");
		if (moves && State.Board.FindPath(piece.Position, move.Value, piece.EffectiveMovement, piece.OwnerIndex) == null)
		{
			return Fail(piece.IsFrozen ? "Frozen - cannot move this turn." : "Move target not reachable.");
		}
		GridPos attackFrom = move ?? piece.Position;
		if (attack.HasValue && (attack.Value == attackFrom || !State.Board.IsInAttackRange(attackFrom, attack.Value, piece.EffectiveRange)))
		{
			return Fail("Attack target out of range.");
		}
		return true;
	}

	/// <summary>
	/// Commands a piece: pays GameConfig.OrderApCost, then its move and attack resolve IMMEDIATELY (friendly fire
	/// included). The piece cannot act again this turn. Returns the events (also LastActionEvents and
	/// ActionResolved), or null if the action is invalid (see LastError).
	/// </summary>
	public List<ResolutionEvent> Act(Piece piece, GridPos? move, GridPos? attack)
	{
		if (!CanAct(piece, move, attack))
		{
			return null;
		}
		State.CurrentPlayer.ActionPoints -= Math.Max(0, State.Config.OrderApCost);
		piece.ActedTurn = State.TurnNumber;
		GridPos? realMove = move.HasValue && move.Value != piece.Position ? move : null;
		_lastActionEvents = OrderResolver.ResolveAction(State, piece, realMove, attack);
		ActionResolved?.Invoke(_lastActionEvents);
		StateChanged?.Invoke();
		return _lastActionEvents;
	}

	/// <summary>
	/// Predicts what ONE attack of 'attacker' standing at 'fromPos' on tile 'target' would cause, on a clone of
	/// the CURRENT board: damage (friendly fire included), kills, keyword effects. If fromPos holds a friendly,
	/// the planned move is simulated (push).
	/// Does not check AP / summoning sickness; IsValid is false if the attack is impossible (range etc.).
	/// </summary>
	public ChainPreview PredictAttack(Piece attacker, GridPos fromPos, GridPos target)
	{
		var invalid = new ChainPreview { AttackerId = attacker?.Id ?? -1, From = fromPos, Target = target, IsValid = false };
		if (attacker == null || State.GetPiece(attacker.Id) == null)
		{
			return invalid;
		}
		if (!State.Board.IsInAttackRange(fromPos, target, attacker.EffectiveRange))
		{
			return invalid;
		}
		var owners = new Dictionary<int, int>();
		foreach (Piece p in State.Pieces)
		{
			owners[p.Id] = p.OwnerIndex;
		}

		GameState clone = State.Clone();
		Piece a = clone.GetPiece(attacker.Id);
		if (fromPos != a.Position)
		{
			Piece occupant = clone.Board.GetPieceAt(fromPos);
			if (occupant == null && clone.Board.IsPassable(fromPos))
			{
				clone.Board.MovePiece(a, fromPos);
			}
			else if (occupant != null && occupant.OwnerIndex == a.OwnerIndex)
			{
				OrderResolver.SimulateMove(clone, a, fromPos);
			}
			if (a.Position != fromPos)
			{
				return invalid;
			}
		}
		List<ResolutionEvent> events = OrderResolver.SimulateAttack(clone, a, target);
		return ChainPreview.FromEvents(attacker.Id, fromPos, target, attacker.OwnerIndex, owners, events);
	}

	/// <summary>PredictAttack from the attacker's current position.</summary>
	public ChainPreview PredictAttack(Piece attacker, GridPos target) =>
		PredictAttack(attacker, attacker?.Position ?? target, target);

	// ------------------------------------------------------------------ end of turn

	/// <summary>
	/// Ends the current turn: expires spells, statuses and tile effects with ExpiryTurn &lt;= TurnNumber, swaps
	/// player, increments TurnNumber and starts the next turn (its tile ticks are in LastTurnStartEvents).
	/// Returns the expiry events (empty list if the call was invalid). Piece actions were already resolved by Act.
	/// </summary>
	public List<ResolutionEvent> EndTurn()
	{
		if (State.Phase != GamePhase.Main)
		{
			Fail("Can only end the turn in main phase.");
			return new List<ResolutionEvent>();
		}
		State.Phase = GamePhase.Resolving;
		var events = new List<ResolutionEvent>();
		ExpireSpells(events);
		ExpireStatuses(events);
		ExpireTileEffects(events);
		TurnEnded?.Invoke(events);

		State.CurrentPlayerIndex = 1 - State.CurrentPlayerIndex;
		State.TurnNumber++;
		StartTurn();
		return events;
	}

	private void ExpireSpells(List<ResolutionEvent> events)
	{
		int turn = State.TurnNumber;
		foreach (Piece p in State.Pieces)
		{
			for (int i = p.ActiveSpells.Count - 1; i >= 0; i--)
			{
				ActiveSpell spell = p.ActiveSpells[i];
				if (spell.ExpiryTurn > turn)
				{
					continue;
				}
				p.ActiveSpells.RemoveAt(i);
				events.Add(new ResolutionEvent
				{
					Type = ResolutionEventType.SpellExpired,
					PieceId = p.Id,
					From = p.Position,
					To = p.Position,
					SpellName = spell.Source?.Name ?? "",
				});
			}
			p.CurrentHp = Math.Clamp(p.CurrentHp, 1, p.MaxHp);
		}
	}

	private void ExpireStatuses(List<ResolutionEvent> events)
	{
		int turn = State.TurnNumber;
		foreach (Piece p in State.Pieces)
		{
			for (int i = p.StatusEffects.Count - 1; i >= 0; i--)
			{
				StatusEffect status = p.StatusEffects[i];
				if (status.ExpiryTurn > turn)
				{
					continue;
				}
				p.StatusEffects.RemoveAt(i);
				events.Add(new ResolutionEvent
				{
					Type = ResolutionEventType.StatusExpired,
					PieceId = p.Id,
					From = p.Position,
					To = p.Position,
					Status = status.Type,
				});
			}
		}
	}

	private void ExpireTileEffects(List<ResolutionEvent> events)
	{
		int turn = State.TurnNumber;
		var expired = new List<TileEffect>();
		foreach (TileEffect effect in State.Board.TileEffects.Values)
		{
			if (effect.ExpiryTurn <= turn)
			{
				expired.Add(effect);
			}
		}
		expired.Sort((a, b) => a.Position.Y != b.Position.Y ? a.Position.Y.CompareTo(b.Position.Y) : a.Position.X.CompareTo(b.Position.X));
		foreach (TileEffect effect in expired)
		{
			State.Board.RemoveTileEffect(effect.Position);
			events.Add(new ResolutionEvent
			{
				Type = ResolutionEventType.TileEffectExpired,
				From = effect.Position,
				To = effect.Position,
				TileEffect = effect.Type,
				CardName = effect.SourceName,
			});
		}
	}

	// ------------------------------------------------------------------ helpers

	private bool CheckSpellBasics(CardData card)
	{
		if (State.Phase != GamePhase.Main) return Fail("Not in main phase.");
		if (card == null || card.CardType != CardType.Spell) return Fail("Not a spell card.");
		PlayerState player = State.CurrentPlayer;
		if (!player.Hand.Contains(card)) return Fail("Card not in hand.");
		if (GetCardCost(card) > player.ActionPoints) return Fail("Not enough AP.");
		return true;
	}

	private void FinishSpell(List<ResolutionEvent> events)
	{
		_lastSpellEvents = events;
		SpellResolved?.Invoke(events);
		StateChanged?.Invoke();
	}

	private void ReturnDraftOffer(PlayerState player)
	{
		player.Deck.AddRange(player.DraftOffer);
		player.DraftOffer.Clear();
	}

	private CardData DrawRandom(List<CardData> deck)
	{
		int i = State.Random.Next(deck.Count);
		CardData card = deck[i];
		deck.RemoveAt(i);
		return card;
	}

	private bool Fail(string reason)
	{
		LastError = reason;
		return false;
	}
}
