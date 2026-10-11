using System;
using System.Collections.Generic;

namespace ProjectClaude;

/// <summary>
/// Command interface for the rules. All mutating calls validate first; on failure they return
/// false / null and set LastError. Turn flow:
/// StartGame (deal hands) -> [StartTurn: tile ticks (Lava/Healing), score VP, check win, set AP] -> Main phase
/// (PlayUnitCard / PlaySpellCard / PlaySpellOnTile / SetOrder / ConvertVpToAp / Draw -> Draft phase ->
/// ChooseDraftCard -> Main) -> EndTurn (resolve orders, expire spells/statuses/tile effects, swap player,
/// TurnNumber++, StartTurn).
/// AP costs: cards (GetCardCost), Draw (GameConfig.DrawApCost), a NEW order (GameConfig.OrderApCost;
/// replacing is free, clearing refunds). Pieces are summoning sick on the turn they were summoned.
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
	/// <summary>Raised after orders were resolved in EndTurn (before the next turn starts).</summary>
	public event Action<IReadOnlyList<ResolutionEvent>> OrdersResolved;
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

	/// <summary>Tile-tick events of the most recent turn start (Lava/Healing). Animate them after EndTurn's events.</summary>
	public IReadOnlyList<ResolutionEvent> LastTurnStartEvents => _lastTurnStartEvents;
	/// <summary>Immediate events of the most recently cast spell (SpellCast, Damaged, Healed, TileEffectApplied...).</summary>
	public IReadOnlyList<ResolutionEvent> LastSpellEvents => _lastSpellEvents;

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
	/// LastTurnStartEvents), +1 VP per own piece in the scoring zone, win check,
	/// AP = BaseAp + sum of own ApBonus (+ second-player bonus on player 1's first turn), then Main phase.
	/// </summary>
	public void StartTurn()
	{
		int idx = State.CurrentPlayerIndex;
		PlayerState player = State.CurrentPlayer;
		State.ResetOrderIndex();
		player.TurnsStarted++;
		player.VpConvertedThisTurn = 0;

		_lastTurnStartEvents = OrderResolver.ResolveTurnStart(State, idx);
		if (_lastTurnStartEvents.Count > 0)
		{
			TurnStartResolved?.Invoke(_lastTurnStartEvents);
		}

		int scored = 0;
		int apBonus = 0;
		foreach (Piece p in State.GetPiecesOf(idx))
		{
			if (State.Board.IsInScoringZone(p.Position))
			{
				scored++;
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

		player.ActionPoints = State.Config.BaseAp + apBonus;
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
		if (!State.Board.IsInDeployZone(State.CurrentPlayerIndex, pos)) return Fail("Not in own deploy rows.");
		if (State.Board.IsWall(pos)) return Fail("A wall blocks this tile.");
		if (State.Board.IsOccupied(pos)) return Fail("Tile occupied.");
		return true;
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
			},
		};
		SpellEffect effect = SpellEffect.FromCard(card);
		bool hasModifiers = effect.AttackDelta != 0 || effect.HpDelta != 0 || effect.ShieldDelta != 0
			|| effect.MovementDelta != 0 || effect.RangeDelta != 0;
		if (hasModifiers || card.GrantStatus == StatusEffectType.None)
		{
			target.ActiveSpells.Add(new ActiveSpell(card, effect, State.CurrentPlayerIndex, State.TurnNumber, State.TurnNumber + 2));
			target.CurrentHp = Math.Clamp(target.CurrentHp + effect.HpDelta, 1, target.MaxHp);
		}
		if (card.GrantStatus != StatusEffectType.None)
		{
			OrderResolver.ApplyStatus(State, target, card.GrantStatus, State.Config.SpellStatusDuration, card.Name, -1, events);
		}
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

		var events = new List<ResolutionEvent>
		{
			new ResolutionEvent { Type = ResolutionEventType.SpellCast, PlayerIndex = caster, From = tile, To = tile, CardName = card.Name },
		};
		List<GridPos> area = GetSpellAreaPreview(card, tile);
		foreach (GridPos p in area)
		{
			Piece piece = State.Board.GetPieceAt(p);
			if (piece == null)
			{
				continue;
			}
			if (piece.OwnerIndex != caster && card.SpellDamage > 0)
			{
				OrderResolver.ApplyDamage(State, piece, card.SpellDamage, -1, events);
			}
			else if (piece.OwnerIndex == caster && card.SpellHeal > 0)
			{
				OrderResolver.ApplyHeal(State, piece, card.SpellHeal, -1, events);
			}
		}
		if (card.TileEffect != TileEffectType.None)
		{
			foreach (GridPos p in area)
			{
				OrderResolver.ApplyTileEffect(State, card.TileEffect, p, card.TileEffectDuration, caster, card.Name, -1, events);
			}
		}
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

	// ------------------------------------------------------------------ orders

	/// <summary>
	/// Valid move destinations for a piece (excluding its own tile). Friendly pieces do not block and may be a
	/// destination (they get pushed at resolution); enemies and walls block. Frozen pieces cannot move.
	/// </summary>
	public List<GridPos> GetValidMoveTargets(Piece piece) =>
		State.Board.GetReachableTiles(piece.Position, piece.EffectiveMovement, piece.OwnerIndex);

	/// <summary>
	/// Planned shortest path for a move (same rules as GetValidMoveTargets): the tiles after the piece's position,
	/// ending with target. Empty if target is the current tile or unreachable. Other orders are not simulated.
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
	/// True if the current player may give this piece orders now: Main phase, own living piece,
	/// not summoning sick. Does not check AP.
	/// </summary>
	public bool CanCommand(Piece piece)
	{
		if (State.Phase != GamePhase.Main) return Fail("Not in main phase.");
		if (piece == null || State.GetPiece(piece.Id) == null) return Fail("Invalid piece.");
		if (piece.OwnerIndex != State.CurrentPlayerIndex) return Fail("Not your piece.");
		if (piece.IsSummoningSick(State.TurnNumber)) return Fail("Summoning sick - can act next turn.");
		return true;
	}

	/// <summary>
	/// Checks an order without applying it. A new order needs GameConfig.OrderApCost AP; replacing an
	/// existing order or clearing it (null/null) needs none. Moves follow GetValidMoveTargets.
	/// </summary>
	public bool CanSetOrder(Piece piece, GridPos? move, GridPos? attack)
	{
		if (!CanCommand(piece)) return false;
		bool isNew = piece.Order == null && (move.HasValue || attack.HasValue);
		if (isNew && State.Config.OrderApCost > State.CurrentPlayer.ActionPoints) return Fail("Not enough AP.");
		if (move.HasValue && move.Value != piece.Position
			&& State.Board.FindPath(piece.Position, move.Value, piece.EffectiveMovement, piece.OwnerIndex) == null)
		{
			return Fail(piece.IsFrozen ? "Frozen - cannot move this turn." : "Move target not reachable.");
		}
		GridPos attackFrom = move ?? piece.Position;
		if (attack.HasValue && !State.Board.IsInAttackRange(attackFrom, attack.Value, piece.EffectiveRange))
		{
			return Fail("Attack target out of range.");
		}
		return true;
	}

	/// <summary>
	/// Queues (or replaces) the order of a piece. A new order costs GameConfig.OrderApCost and gets the next
	/// order index; replacing an existing order is free and keeps its index. Passing null for both clears
	/// the order and refunds its AP.
	/// </summary>
	public bool SetOrder(Piece piece, GridPos? move, GridPos? attack)
	{
		if (!CanSetOrder(piece, move, attack))
		{
			return false;
		}
		if (!move.HasValue && !attack.HasValue)
		{
			RemoveOrderWithRefund(piece);
		}
		else if (piece.Order != null)
		{
			piece.Order.MoveTarget = move;
			piece.Order.AttackTarget = attack;
		}
		else
		{
			int cost = Math.Max(0, State.Config.OrderApCost);
			State.CurrentPlayer.ActionPoints -= cost;
			piece.Order = new PieceOrder(move, attack, State.TakeOrderIndex()) { ApPaid = cost };
		}
		StateChanged?.Invoke();
		return true;
	}

	/// <summary>Removes the queued order of a piece and refunds the AP paid for it (current player's turn only).</summary>
	public void ClearOrder(Piece piece)
	{
		if (piece != null && piece.Order != null)
		{
			RemoveOrderWithRefund(piece);
			StateChanged?.Invoke();
		}
	}

	/// <summary>
	/// Predicts what ONE attack of 'attacker' standing at 'fromPos' on tile 'target' would cause, on a clone of
	/// the CURRENT board: chains, damage, kills, keyword effects. Other queued orders are NOT simulated (it is a
	/// preview of that single attack). If fromPos holds a friendly, the planned move is simulated (push).
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

	private void RemoveOrderWithRefund(Piece piece)
	{
		if (piece.Order == null)
		{
			return;
		}
		if (piece.OwnerIndex == State.CurrentPlayerIndex && State.Phase == GamePhase.Main)
		{
			State.CurrentPlayer.ActionPoints += piece.Order.ApPaid;
		}
		piece.Order = null;
	}

	// ------------------------------------------------------------------ end of turn

	/// <summary>
	/// Ends the current turn: resolves the current player's orders, clears orders (no refund), expires spells,
	/// statuses and tile effects with ExpiryTurn &lt;= TurnNumber, swaps player, increments TurnNumber and starts
	/// the next turn (its tile ticks are in LastTurnStartEvents). Returns the resolution events (empty list if
	/// the call was invalid).
	/// </summary>
	public List<ResolutionEvent> EndTurn()
	{
		if (State.Phase != GamePhase.Main)
		{
			Fail("Can only end the turn in main phase.");
			return new List<ResolutionEvent>();
		}
		State.Phase = GamePhase.Resolving;
		List<ResolutionEvent> events = OrderResolver.Resolve(State, State.CurrentPlayerIndex);

		foreach (Piece p in State.Pieces)
		{
			p.Order = null;
		}
		ExpireSpells(events);
		ExpireStatuses(events);
		ExpireTileEffects(events);
		OrdersResolved?.Invoke(events);

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
