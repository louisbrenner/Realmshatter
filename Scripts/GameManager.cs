using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Godot;

namespace Realmshatter;

/// <summary>
/// Root script of Main.tscn. Wires the pure rules (GameState / TurnController) to the board view,
/// animator, order overlay, camera, HUD and the AI, and runs the human input state machine (player 0).
/// User args: --selftest prints the rules and AI self-tests, --autoplay lets a second SimpleAi
/// play the human side until game over and then quits (debug).
/// </summary>
public partial class GameManager : Node
{
	private const int HumanPlayer = 0;
	private const int AiPlayer = 1;
	private const int MaxAutomatedTurns = 1000;

	/// <summary>One committed order captured before EndTurn (for the "Order 2/4" resolution ticker).</summary>
	private sealed class OrderStep
	{
		public int PieceId;
		public string Text;
	}

	[ExportGroup("Rules")]
	[Export] public GameConfig Config { get; set; }
	[Export] public Godot.Collections.Array<CardData> PlayerDeck { get; set; } = new Godot.Collections.Array<CardData>();
	[Export] public Godot.Collections.Array<CardData> AiDeck { get; set; } = new Godot.Collections.Array<CardData>();
	/// <summary>Optional deck resource for the player; overrides PlayerDeck when set (e.g. Resources/Decks/StarterDeck.tres).</summary>
	[Export] public DeckData PlayerDeckData { get; set; }
	/// <summary>Optional deck resource for the AI; overrides AiDeck when set.</summary>
	[Export] public DeckData AiDeckData { get; set; }
	/// <summary>
	/// Themed decks offered on the deck selection screen at the start of every game (the AI plays a random other
	/// theme). When empty, PlayerDeckData / AiDeckData are used directly without a selection screen.
	/// </summary>
	[Export] public Godot.Collections.Array<DeckData> ThemeDecks { get; set; } = new Godot.Collections.Array<DeckData>();
	/// <summary>Random seed for draws (0 = random every game).</summary>
	[Export] public int Seed { get; set; } = 0;
	/// <summary>Pause in seconds before and after the AI plays its cards.</summary>
	[Export] public float AiStepDelay { get; set; } = 0.6f;

	[ExportGroup("Nodes")]
	[Export] public BoardView Board { get; set; }
	[Export] public BoardAnimator Animator { get; set; }
	[Export] public CameraRig CameraRig { get; set; }
	[Export] public Hud Hud { get; set; }
	/// <summary>Order arrows / numbers, planning and chain previews (created at the origin if not assigned).</summary>
	[Export] public OrderOverlay Overlay { get; set; }

	private GameState _state;
	private TurnController _controller;
	private SimpleAi _ai;
	private SimpleAi _autoplayAi;
	private bool _autoplay;
	private int _generation;

	private InputMode _mode = InputMode.Idle;
	private int _selectedHandIndex = -1;
	private CardData _selectedCard;
	private Piece _selectedPiece;
	private GridPos? _plannedMove;

	private readonly List<string> _pendingLog = new List<string>();
	private readonly Dictionary<int, string> _pieceNames = new Dictionary<int, string>();
	private readonly List<List<ResolutionEvent>> _capturedSpellEvents = new List<List<ResolutionEvent>>();
	private bool _captureSpells;
	private readonly List<GridPos> _pendingScoreTiles = new List<GridPos>();
	private int _pendingScorePlayer = -1;
	private DeckData _playerTheme;
	private DeckData _aiTheme;
	private GridPos? _hoverTile;
	private readonly Random _themeRandom = new Random();

	public override void _Ready()
	{
		if (Board == null || Animator == null || CameraRig == null || Hud == null)
		{
			GD.PushError("GameManager: Board, Animator, CameraRig and Hud must be assigned.");
			return;
		}
		AddChild(new Sfx { Name = "Sfx" });
		if (Overlay == null)
		{
			Overlay = new OrderOverlay { Name = "OrderOverlay" };
			AddChild(Overlay);
		}

		string[] userArgs = OS.GetCmdlineUserArgs();
		_autoplay = Array.IndexOf(userArgs, "--autoplay") >= 0;
		Sfx.Muted = _autoplay;
		if (Array.IndexOf(userArgs, "--selftest") >= 0)
		{
			GD.Print(RulesSelfTest.Run());
			GD.Print(AiSelfTest.Run());
		}
		if (_autoplay)
		{
			Engine.TimeScale = 8.0;
			GD.Print("GameManager: autoplay enabled (both sides played by SimpleAi).");
		}

		// Turn banners are driven explicitly (awaited at every turn start).
		Hud.AutoTurnBanner = false;
		Animator.DeckWorldProvider = GetDeckWorld;

		Board.TileClicked += OnTileClicked;
		Board.TileHovered += OnTileHovered;
		Hud.EndTurnPressed += OnEndTurnPressed;
		Hud.ViewTogglePressed += OnViewTogglePressed;
		Hud.CancelPressed += OnCancelPressed;
		Hud.RestartPressed += OnRestartPressed;
		Hud.DrawPressed += OnDrawPressed;
		Hud.ConvertVpPressed += OnConvertVpPressed;
		Hud.Hand.CardSelected += OnHandCardSelected;
		Hud.Draft.CardChosen += OnDraftCardChosen;
		Hud.DeckSelect.DeckChosen += OnDeckChosen;
		CameraRig.ViewModeChanged += OnViewModeChanged;
		OnViewModeChanged((int)CameraRig.Mode);

		BeginNewGame();
	}

	/// <summary>Shows the deck selection (when ThemeDecks are set and not autoplaying), otherwise starts right away.</summary>
	private void BeginNewGame()
	{
		List<DeckData> themes = ThemeList();
		if (themes.Count == 0)
		{
			StartNewGame();
			return;
		}
		if (_autoplay)
		{
			_playerTheme = themes[_themeRandom.Next(themes.Count)];
			_aiTheme = PickOtherTheme(themes, _playerTheme);
			StartNewGame();
			return;
		}
		ShowDeckSelection(themes);
	}

	/// <summary>Clears the table and shows the deck selection screen; the game starts in OnDeckChosen.</summary>
	private void ShowDeckSelection(List<DeckData> themes)
	{
		_generation++;
		UnsubscribeController();
		ResetSelection();
		_mode = InputMode.Busy;
		_hoverTile = null;

		GameConfig config = Config ?? new GameConfig();
		var fit = new Vector2(config.BoardWidth, config.BoardHeight);
		if (CameraRig.BoardFitSize != fit)
		{
			CameraRig.BoardFitSize = fit;
			CameraRig.SetMode(CameraRig.Mode, false);
		}
		Board.Build(new BoardState(config));
		Animator.ClearAll();
		Overlay.ClearAll();
		Hud.HideWinScreen();
		Hud.Draft.HidePopup();
		Hud.HideBoardInfo();
		Hud.Hand.ShowHand(new List<CardData>(), null, null);
		Hud.SetEndTurnEnabled(false);
		Hud.SetDrawEnabled(false);
		Hud.SetCancelEnabled(false);
		Hud.SetHint("");
		Hud.DeckSelect.Present(themes);
	}

	private void OnDeckChosen(int index)
	{
		List<DeckData> themes = ThemeList();
		if (index < 0 || index >= themes.Count)
		{
			return;
		}
		_playerTheme = themes[index];
		_aiTheme = PickOtherTheme(themes, _playerTheme);
		StartNewGame();
	}

	private DeckData PickOtherTheme(List<DeckData> themes, DeckData exclude)
	{
		var others = themes.FindAll(d => d != exclude);
		return others.Count > 0 ? others[_themeRandom.Next(others.Count)] : exclude;
	}

	private List<DeckData> ThemeList()
	{
		var list = new List<DeckData>();
		if (ThemeDecks != null)
		{
			foreach (DeckData deck in ThemeDecks)
			{
				if (deck != null && deck.Cards.Count > 0)
				{
					list.Add(deck);
				}
			}
		}
		return list;
	}

	public override void _ExitTree()
	{
		_generation++;
		UnsubscribeController();
	}

	/// <summary>Creates a fresh game (state, controller, AI), rebuilds the board and starts turn 1.</summary>
	public void StartNewGame()
	{
		_generation++;
		int generation = _generation;
		UnsubscribeController();

		GameConfig config = Config ?? new GameConfig();
		DeckData playerDeck = _playerTheme ?? PlayerDeckData;
		DeckData aiDeck = _aiTheme ?? AiDeckData;
		List<CardData> deck0 = playerDeck != null ? ToList(playerDeck.Cards) : ToList(PlayerDeck);
		List<CardData> deck1 = aiDeck != null ? ToList(aiDeck.Cards) : ToList(AiDeck);
		if (deck0.Count == 0 || deck1.Count == 0)
		{
			GD.PushError("GameManager: PlayerDeck and AiDeck should contain cards.");
		}
		var random = Seed != 0 ? new Random(Seed) : new Random();

		_state = new GameState(config, deck0, deck1, random);
		_controller = new TurnController(_state);
		_ai = new SimpleAi(_controller, AiPlayer);
		_autoplayAi = _autoplay ? new SimpleAi(_controller, HumanPlayer) : null;
		SubscribeController();

		_pendingLog.Clear();
		_pieceNames.Clear();
		_capturedSpellEvents.Clear();
		_pendingScoreTiles.Clear();
		_pendingScorePlayer = -1;
		_hoverTile = null;
		ResetSelection();
		_mode = InputMode.Idle;
		if (playerDeck != null && aiDeck != null)
		{
			_pendingLog.Add($"Your deck: {playerDeck.Name}. AI deck: {aiDeck.Name}.");
		}

		var fit = new Vector2(config.BoardWidth, config.BoardHeight);
		if (CameraRig.BoardFitSize != fit)
		{
			CameraRig.BoardFitSize = fit;
			CameraRig.SetMode(CameraRig.Mode, false);
		}

		Board.Build(_state.Board);
		Animator.ClearAll();
		Animator.SyncAll(_state);
		Overlay.ClearAll();
		Overlay.SetState(_state);
		Hud.HideWinScreen();
		Hud.Draft.HidePopup();
		Hud.ClearLog();

		_controller.StartGame();
		FlushPendingLog();
		_ = RunGameAsync(generation);
	}

	/// <summary>Turn 1 intro (banner), then the automated turns / the human turn.</summary>
	private async Task RunGameAsync(int generation)
	{
		try
		{
			_mode = InputMode.Busy;
			Refresh();
			await TurnIntroAsync(generation);
			if (!IsCurrent(generation))
			{
				return;
			}
			_mode = InputMode.Idle;
			await RunAutomatedTurnsAsync(generation);
		}
		catch (Exception e)
		{
			GD.PushError($"GameManager: game start failed: {e}");
		}
	}

	// ------------------------------------------------------------------ controller events

	private void SubscribeController()
	{
		_controller.TurnStarted += OnTurnStarted;
		_controller.VictoryPointsScored += OnVictoryPointsScored;
		_controller.GameOver += OnGameOver;
		_controller.SpellResolved += OnSpellResolved;
	}

	private void UnsubscribeController()
	{
		if (_controller == null)
		{
			return;
		}
		_controller.TurnStarted -= OnTurnStarted;
		_controller.VictoryPointsScored -= OnVictoryPointsScored;
		_controller.GameOver -= OnGameOver;
		_controller.SpellResolved -= OnSpellResolved;
	}

	private void OnTurnStarted(int player)
	{
		_pendingLog.Add($"--- Turn {_state.TurnNumber}: {PlayerLabel(player)} ({_state.Players[player].ActionPoints} AP) ---");
		if (player == 1 && _state.Players[player].TurnsStarted == 1 && _state.Config.SecondPlayerFirstTurnBonusAp > 0)
		{
			_pendingLog.Add($"{PlayerLabel(player)} moves second: +{_state.Config.SecondPlayerFirstTurnBonusAp} AP this turn.");
		}
	}

	private void OnVictoryPointsScored(int player, int points)
	{
		_pendingLog.Add($"{PlayerLabel(player)} scored {points} VP (total {_state.Players[player].VictoryPoints}).");
		_pendingScorePlayer = player;
		_pendingScoreTiles.Clear();
		foreach (Piece p in _state.GetPiecesOf(player))
		{
			if (_state.Board.IsInScoringZone(p.Position))
			{
				_pendingScoreTiles.Add(p.Position);
			}
		}
	}

	private void OnGameOver(int winner)
	{
		_pendingLog.Add($"{PlayerLabel(winner)} reached {_state.Config.PointsTarget} VP and wins!");
	}

	private void OnSpellResolved(IReadOnlyList<ResolutionEvent> events)
	{
		if (_captureSpells && events != null)
		{
			_capturedSpellEvents.Add(new List<ResolutionEvent>(events));
		}
	}

	// ------------------------------------------------------------------ turn flow

	/// <summary>Plays all consecutive AI-controlled turns, then hands control to the human (or shows the win screen).</summary>
	private async Task RunAutomatedTurnsAsync(int generation)
	{
		try
		{
			int turns = 0;
			while (IsCurrent(generation) && _state.Winner < 0)
			{
				SimpleAi ai = GetAiFor(_state.CurrentPlayerIndex);
				if (ai == null)
				{
					break;
				}
				if (++turns > MaxAutomatedTurns)
				{
					GD.PushWarning("GameManager: automated turn limit reached.");
					if (_autoplay)
					{
						GD.Print("AUTOPLAY RESULT: turn limit reached without a winner.");
						GetTree().Quit();
					}
					return;
				}
				if (!await RunAiTurnAsync(ai, generation))
				{
					break;
				}
			}
			if (IsCurrent(generation))
			{
				EnterHumanTurnOrGameOver();
			}
		}
		catch (Exception e)
		{
			GD.PushError($"GameManager: automated turn failed: {e}");
		}
	}

	/// <summary>One full AI turn: draft + cards + orders (animated), then EndTurn. False if it could not end the turn.</summary>
	private async Task<bool> RunAiTurnAsync(SimpleAi ai, int generation)
	{
		_mode = InputMode.Busy;
		Hud.Draft.HidePopup();
		Hud.SetHint($"{PlayerLabel(ai.PlayerIndex)} is thinking...");
		Refresh();
		UpdateOrderOverlay();

		await DelayAsync(AiStepDelay);
		if (!IsCurrent(generation))
		{
			return false;
		}

		CachePieceNames();
		_capturedSpellEvents.Clear();
		_captureSpells = true;
		List<AiAction> actions;
		try
		{
			actions = ai.TakeTurn();
		}
		finally
		{
			_captureSpells = false;
		}
		if (_state.Phase == GamePhase.Draft && _state.CurrentPlayer.DraftOffer.Count > 0)
		{
			_controller.ChooseDraftCard(0);
		}

		await AnimateAiActionsAsync(actions, generation);
		if (!IsCurrent(generation))
		{
			return false;
		}
		Animator.SyncAll(_state);
		CachePieceNames();
		FlushPendingLog();
		Refresh();
		UpdateOrderOverlay();

		await DelayAsync(AiStepDelay);
		if (!IsCurrent(generation))
		{
			return false;
		}
		return await EndTurnAsync(generation);
	}

	/// <summary>Logs and animates the AI's executed actions in order (summons, spell events).</summary>
	private async Task AnimateAiActionsAsync(List<AiAction> actions, int generation)
	{
		int spellIndex = 0;
		foreach (AiAction action in actions)
		{
			Log($"{PlayerLabel(action.PlayerIndex)}: {action.Description}");
			switch (action.Kind)
			{
				case AiActionKind.PlayUnit:
				{
					Piece piece = _state.GetPiece(action.PieceId);
					if (piece != null)
					{
						_pieceNames[piece.Id] = PieceNameFor(piece);
						Animator.SpawnView(piece);
						await Animator.PlaySummon(piece.Id);
					}
					break;
				}
				case AiActionKind.PlaySpell:
					if (spellIndex < _capturedSpellEvents.Count)
					{
						List<ResolutionEvent> events = _capturedSpellEvents[spellIndex++];
						await Animator.PlayEvents(events, _state, false);
						foreach (ResolutionEvent e in events)
						{
							if (e.Type != ResolutionEventType.SpellCast)
							{
								Log(DescribeEvent(e));
							}
						}
					}
					break;
				case AiActionKind.ConvertVp:
					Hud.ShowMessage($"{PlayerLabel(action.PlayerIndex)} converted 1 VP into 1 AP.");
					break;
			}
			if (!IsCurrent(generation))
			{
				return;
			}
		}
	}

	/// <summary>Ends the current turn, animates the resolution events order by order and logs them.</summary>
	private async Task<bool> EndTurnAsync(int generation)
	{
		if (_state.Phase != GamePhase.Main)
		{
			Hud.ShowMessage("You can only end the turn in the main phase.");
			return false;
		}

		_mode = InputMode.Busy;
		Hud.SetHint("Resolving orders...");
		Refresh();

		CachePieceNames();
		List<OrderStep> plan = BuildOrderPlan();
		List<ResolutionEvent> events = _controller.EndTurn();
		var turnStartEvents = new List<ResolutionEvent>(_controller.LastTurnStartEvents);

		Overlay.ClearAll();
		List<IReadOnlyList<ResolutionEvent>> groups = GroupEventsByOrder(events, plan, out List<int> groupSteps);
		await Animator.PlayEventGroups(groups, _state, gi =>
		{
			int step = groupSteps[gi];
			if (step >= 0)
			{
				Hud.ShowResolutionStep(step + 1, plan.Count, plan[step].Text);
			}
			else
			{
				Hud.HideResolutionStep();
			}
		}, turnStartEvents.Count == 0);
		Hud.HideResolutionStep();
		if (!IsCurrent(generation))
		{
			return false;
		}
		if (turnStartEvents.Count > 0)
		{
			// Lava / healing ticks at the start of the new turn.
			await Animator.PlayEvents(turnStartEvents, _state);
			if (!IsCurrent(generation))
			{
				return false;
			}
		}

		CachePieceNames();
		foreach (ResolutionEvent e in events)
		{
			Log(DescribeEvent(e));
		}
		foreach (ResolutionEvent e in turnStartEvents)
		{
			Log(DescribeEvent(e));
		}
		FlushPendingLog();
		Refresh();

		await TurnIntroAsync(generation);
		if (!IsCurrent(generation))
		{
			return false;
		}
		Refresh();
		return true;
	}

	/// <summary>Start of a turn: turn banner, then the VP scoring animation of the zone pieces.</summary>
	private async Task TurnIntroAsync(int generation)
	{
		if (_state.Winner < 0)
		{
			await Hud.ShowTurnBanner(_state.CurrentPlayerIndex, _state.TurnNumber);
			if (!IsCurrent(generation))
			{
				return;
			}
		}
		if (_pendingScorePlayer >= 0 && _pendingScoreTiles.Count > 0)
		{
			var tiles = new List<GridPos>(_pendingScoreTiles);
			int player = _pendingScorePlayer;
			_pendingScoreTiles.Clear();
			_pendingScorePlayer = -1;
			await Animator.PlayScore(tiles, player);
		}
		_pendingScorePlayer = -1;
	}

	private void EnterHumanTurnOrGameOver()
	{
		ResetSelection();
		Board.ClearHighlights();
		Animator.ClearSelection();
		Overlay.ClearPreview();
		Overlay.ClearAttackPreview();
		Overlay.ClearSpellAreaPreview();

		if (_state.Winner >= 0)
		{
			_mode = InputMode.Idle;
			Refresh();
			Hud.SetHint("Game over.");
			Hud.ShowWinScreen(_state.Winner);
			if (_autoplay)
			{
				GD.Print($"AUTOPLAY RESULT: winner = {PlayerLabel(_state.Winner)} after {_state.TurnNumber} turns, " +
					$"VP {_state.Players[0].VictoryPoints} : {_state.Players[1].VictoryPoints}, pieces alive {_state.Pieces.Count}.");
				GetTree().Quit();
			}
			return;
		}

		_mode = InputMode.Idle;
		// Turns start in Main phase; this only resumes an unfinished (already paid) draw.
		if (_state.CurrentPlayerIndex == HumanPlayer && _state.Phase == GamePhase.Draft && !_autoplay)
		{
			Hud.Draft.ShowOffer(_state.CurrentPlayer.DraftOffer, _controller.GetCardCost);
		}
		UpdateHint();
		Refresh();
		UpdateOrderOverlay();
	}

	/// <summary>The current player's committed orders in resolution order, with a short ticker text each.</summary>
	private List<OrderStep> BuildOrderPlan()
	{
		var pieces = new List<Piece>();
		foreach (Piece p in _state.GetPiecesOf(_state.CurrentPlayerIndex))
		{
			if (p.Order != null)
			{
				pieces.Add(p);
			}
		}
		pieces.Sort((a, b) => a.Order.OrderIndex.CompareTo(b.Order.OrderIndex));
		var plan = new List<OrderStep>();
		foreach (Piece p in pieces)
		{
			string who = $"{(p.OwnerIndex == HumanPlayer ? "Your" : "AI")} {PieceLabel(p)}";
			var parts = new List<string>();
			if (p.Order.MoveTarget.HasValue && p.Order.MoveTarget.Value != p.Position)
			{
				parts.Add("moves");
			}
			if (p.Order.AttackTarget.HasValue)
			{
				Piece target = _state.Board.GetPieceAt(p.Order.AttackTarget.Value);
				if (target == null || target == p)
				{
					parts.Add("attacks");
				}
				else if (target.OwnerIndex == p.OwnerIndex)
				{
					parts.Add($"triggers {PieceLabel(target)}");
				}
				else
				{
					parts.Add($"attacks {PieceLabel(target)}");
				}
			}
			plan.Add(new OrderStep { PieceId = p.Id, Text = parts.Count > 0 ? $"{who} {string.Join(" & ", parts)}" : $"{who} holds" });
		}
		return plan;
	}

	/// <summary>
	/// Splits the chronological resolution events into one group per resolved order (a group starts with the
	/// acting piece's move / attack) plus a trailing upkeep group (expiring spells, statuses, tile effects).
	/// groupSteps[i] = plan index of group i, or -1 for upkeep.
	/// </summary>
	private static List<IReadOnlyList<ResolutionEvent>> GroupEventsByOrder(List<ResolutionEvent> events, List<OrderStep> plan,
		out List<int> groupSteps)
	{
		var groups = new List<IReadOnlyList<ResolutionEvent>>();
		groupSteps = new List<int>();
		List<ResolutionEvent> current = null;
		int currentStep = int.MinValue;
		int lastPlanIndex = -1;
		for (int i = 0; i < events.Count; i++)
		{
			ResolutionEvent e = events[i];
			bool upkeep = e.Type == ResolutionEventType.SpellExpired || e.Type == ResolutionEventType.TileEffectExpired ||
				(e.Type == ResolutionEventType.StatusExpired && !e.IsChain);
			int step;
			if (upkeep)
			{
				step = -1;
			}
			else
			{
				int actor = -1;
				switch (e.Type)
				{
					case ResolutionEventType.Moved:
					case ResolutionEventType.MoveBlocked:
					case ResolutionEventType.AttackCancelled:
						actor = e.PieceId;
						break;
					case ResolutionEventType.Attacked:
						actor = e.IsChain || e.IsPierce ? -1 : e.PieceId;
						break;
					case ResolutionEventType.PushBlocked:
						ResolutionEvent next = i + 1 < events.Count ? events[i + 1] : null;
						if (next != null && (next.Type == ResolutionEventType.Moved || next.Type == ResolutionEventType.MoveBlocked) &&
							next.PieceId == e.OtherPieceId)
						{
							actor = e.OtherPieceId;
						}
						break;
				}
				step = currentStep == int.MinValue || currentStep < 0 ? Math.Max(lastPlanIndex, 0) : currentStep;
				if (actor >= 0)
				{
					for (int k = lastPlanIndex + 1; k < plan.Count; k++)
					{
						if (plan[k].PieceId == actor)
						{
							step = k;
							break;
						}
					}
				}
				if (plan.Count == 0)
				{
					step = -1;
				}
			}
			if (current == null || step != currentStep)
			{
				current = new List<ResolutionEvent>();
				groups.Add(current);
				groupSteps.Add(step);
				currentStep = step;
				if (step > lastPlanIndex)
				{
					lastPlanIndex = step;
				}
			}
			current.Add(e);
		}
		return groups;
	}

	// ------------------------------------------------------------------ HUD signal handlers

	private async void OnEndTurnPressed()
	{
		if (!CanHumanAct())
		{
			return;
		}
		int generation = _generation;
		try
		{
			CancelSelection();
			if (!await EndTurnAsync(generation) || !IsCurrent(generation))
			{
				if (IsCurrent(generation))
				{
					EnterHumanTurnOrGameOver();
				}
				return;
			}
			await RunAutomatedTurnsAsync(generation);
		}
		catch (Exception e)
		{
			GD.PushError($"GameManager: end turn failed: {e}");
		}
	}

	private void OnViewTogglePressed()
	{
		CameraRig.CycleMode();
	}

	private void OnViewModeChanged(int mode)
	{
		string name = (ViewMode)mode switch
		{
			ViewMode.TwoPointFiveD => "2.5D",
			ViewMode.ThreeD => "3D",
			_ => "2D",
		};
		Hud.SetViewModeLabel(name);
	}

	private void OnCancelPressed()
	{
		if (IsSelecting())
		{
			CancelSelection();
		}
	}

	private void OnRestartPressed()
	{
		BeginNewGame();
	}

	private void OnDrawPressed()
	{
		if (!CanHumanAct())
		{
			return;
		}
		CancelSelection();
		if (!_controller.Draw())
		{
			Hud.ShowMessage(_controller.LastError);
			return;
		}
		Log($"You paid {_state.Config.DrawApCost} AP to draw.");
		Hud.Draft.ShowOffer(_state.CurrentPlayer.DraftOffer, _controller.GetCardCost);
		UpdateHint();
		Refresh();
	}

	/// <summary>Converts 1 VP into 1 AP for the human (HUD conversion slots or keyboard C).</summary>
	public void OnConvertVpPressed()
	{
		if (!CanHumanAct())
		{
			return;
		}
		if (!_controller.ConvertVpToAp())
		{
			Hud.ShowMessage(_controller.LastError);
			return;
		}
		Log($"You converted 1 VP into 1 AP ({_controller.RemainingVpConversions} conversion(s) left this turn).");
		Hud.ShowMessage($"+1 AP for 1 VP ({_controller.RemainingVpConversions} left this turn).");
		UpdateHint();
		Refresh();
	}

	private void OnDraftCardChosen(int offerIndex)
	{
		if (_mode == InputMode.Busy || _state.CurrentPlayerIndex != HumanPlayer || _state.Phase != GamePhase.Draft)
		{
			return;
		}
		CardData card = offerIndex >= 0 && offerIndex < _state.CurrentPlayer.DraftOffer.Count
			? _state.CurrentPlayer.DraftOffer[offerIndex]
			: null;
		if (!_controller.ChooseDraftCard(offerIndex))
		{
			Hud.ShowMessage(_controller.LastError);
			return;
		}
		Log($"You kept {card?.Name ?? "a card"}.");
		// Deferred: the popup's cards are freed, and we are inside one of their click signals.
		Callable.From(AfterDraft).CallDeferred();
	}

	private void AfterDraft()
	{
		Hud.Draft.HidePopup();
		_mode = InputMode.Idle;
		UpdateHint();
		Refresh();
	}

	private void OnHandCardSelected(int handIndex)
	{
		if (!CanHumanAct())
		{
			if (_mode != InputMode.Busy && _state.Winner < 0)
			{
				Hud.ShowMessage("Wait for your main phase.");
			}
			return;
		}
		List<CardData> hand = _state.Players[HumanPlayer].Hand;
		if (handIndex < 0 || handIndex >= hand.Count)
		{
			return;
		}
		if (_mode == InputMode.CardSelected && _selectedHandIndex == handIndex)
		{
			CancelSelection();
			return;
		}

		CardData card = hand[handIndex];
		int cost = _controller.GetCardCost(card);
		if (cost > _state.CurrentPlayer.ActionPoints)
		{
			Hud.ShowMessage($"Not enough AP: {card.Name} costs {cost}.");
			return;
		}

		CancelSelection();
		_mode = InputMode.CardSelected;
		_selectedHandIndex = handIndex;
		_selectedCard = card;
		Hud.Hand.SetSelectedIndex(handIndex);

		var tiles = new List<GridPos>();
		if (card.CardType == CardType.Unit)
		{
			for (int y = 0; y < _state.Board.Height; y++)
			{
				for (int x = 0; x < _state.Board.Width; x++)
				{
					var pos = new GridPos(x, y);
					if (_controller.CanPlayUnitCard(card, pos))
					{
						tiles.Add(pos);
					}
				}
			}
			Board.ShowHighlights(tiles, HighlightKind.Deploy);
			if (tiles.Count == 0)
			{
				Hud.ShowMessage("No free tile in your back rows.");
			}
		}
		else
		{
			tiles = _controller.GetValidSpellTiles(card);
			// Area spells can target (almost) any tile: the hover preview shows the area instead of a board-wide highlight.
			if (!card.TargetsTile)
			{
				Board.ShowHighlights(tiles, HighlightKind.Spell);
			}
			if (tiles.Count == 0)
			{
				Hud.ShowMessage(card.TargetsTile ? "There is no valid tile for this spell." : "There is no piece to target.");
			}
		}
		Hud.SetCancelEnabled(true);
		UpdateHint();
	}

	// ------------------------------------------------------------------ board input

	public override void _UnhandledInput(InputEvent @event)
	{
		if (@event is InputEventMouseButton button && button.Pressed && button.ButtonIndex == MouseButton.Right)
		{
			if (IsSelecting())
			{
				CancelSelection();
				GetViewport().SetInputAsHandled();
			}
			return;
		}

		if (@event is InputEventKey key && key.Pressed && !key.Echo)
		{
			switch (key.Keycode)
			{
				case Key.Escape:
					if (IsSelecting())
					{
						CancelSelection();
					}
					GetViewport().SetInputAsHandled();
					break;
				case Key.V:
					OnViewTogglePressed();
					GetViewport().SetInputAsHandled();
					break;
				case Key.D:
					OnDrawPressed();
					GetViewport().SetInputAsHandled();
					break;
				case Key.C:
					OnConvertVpPressed();
					GetViewport().SetInputAsHandled();
					break;
				case Key.Enter:
				case Key.KpEnter:
				case Key.Space:
					OnEndTurnPressed();
					GetViewport().SetInputAsHandled();
					break;
			}
		}
	}

	private void OnTileHovered(Vector2I pos)
	{
		_hoverTile = pos.X < 0 ? null : GridPos.FromVector2I(pos);
		UpdateBoardInfo();
		if (pos.X < 0 || _mode == InputMode.Busy || _state == null)
		{
			Board.ClearHighlights(HighlightKind.Hover);
			Overlay.ClearAttackPreview();
			Overlay.ClearSpellAreaPreview();
			if (_mode != InputMode.Busy)
			{
				UpdateHint();
			}
			return;
		}
		var tile = GridPos.FromVector2I(pos);
		switch (_mode)
		{
			case InputMode.CardSelected when _selectedCard != null && _selectedCard.TargetsTile:
			{
				List<GridPos> area = _controller.GetSpellAreaPreview(_selectedCard, tile);
				Board.ShowHighlights(area, HighlightKind.Hover);
				if (_controller.CanCastSpellAt(_selectedCard, tile))
				{
					Overlay.ShowSpellAreaPreview(area, _selectedCard.TileEffect, Board, _state.Board);
				}
				else
				{
					Overlay.ClearSpellAreaPreview();
				}
				return;
			}
			case InputMode.ChoosingMove when _selectedPiece != null:
				Board.ShowHighlights(new[] { tile }, HighlightKind.Hover);
				if (tile != _selectedPiece.Position && _controller.GetValidMoveTargets(_selectedPiece).Contains(tile))
				{
					Overlay.ShowPreview(_selectedPiece, tile, null, Board, _controller.GetPlannedPath(_selectedPiece, tile), _state.Board);
				}
				else
				{
					Overlay.ShowPreview(_selectedPiece, null, null, Board, (IReadOnlyList<GridPos>)null, _state.Board);
				}
				return;
			case InputMode.ChoosingAttack when _selectedPiece != null:
				Board.ShowHighlights(new[] { tile }, HighlightKind.Hover);
				ShowAttackPlanPreview(tile);
				return;
			case InputMode.Idle:
			{
				Board.ShowHighlights(new[] { tile }, HighlightKind.Hover);
				Piece piece = _state.Board.GetPieceAt(tile);
				if (piece != null)
				{
					Hud.SetHint(DescribePieceShort(piece));
				}
				else
				{
					UpdateHint();
				}
				return;
			}
			default:
				Board.ShowHighlights(new[] { tile }, HighlightKind.Hover);
				return;
		}
	}

	/// <summary>
	/// While choosing an attack: shows the planned order with the hovered attack arc and, for occupied targets,
	/// the predicted consequences (chain shots of triggered friendlies, damage, kills, pushes, new tile effects).
	/// </summary>
	private void ShowAttackPlanPreview(GridPos tile)
	{
		GridPos from = _plannedMove ?? _selectedPiece.Position;
		IReadOnlyList<GridPos> path = _plannedMove.HasValue ? _controller.GetPlannedPath(_selectedPiece, _plannedMove.Value) : null;
		bool valid = tile != from && _controller.GetValidAttackTargets(_selectedPiece, from).Contains(tile);
		Overlay.ShowPreview(_selectedPiece, _plannedMove, valid ? tile : (GridPos?)null, Board, path, _state.Board);
		if (!valid || !_state.Board.IsOccupied(tile))
		{
			Overlay.ClearAttackPreview();
			UpdateHint();
			return;
		}
		ChainPreview p = _controller.PredictAttack(_selectedPiece, from, tile);
		if (p == null || !p.IsValid)
		{
			Overlay.ClearAttackPreview();
			UpdateHint();
			return;
		}
		Overlay.ShowAttackPreview(p, Board, _state);
		Hud.SetHint(DescribeChainPreview(p, tile));
	}

	private string DescribeChainPreview(ChainPreview p, GridPos tile)
	{
		Piece target = _state.Board.GetPieceAt(tile);
		bool friendly = target != null && target.OwnerIndex == HumanPlayer && target != _selectedPiece;
		var parts = new List<string>();
		if (friendly)
		{
			parts.Add($"triggers {PieceLabel(target)}");
		}
		parts.Add($"{p.EnemyHpLost} enemy dmg");
		if (p.EnemyKills > 0)
		{
			parts.Add($"{p.EnemyKills} kill{(p.EnemyKills > 1 ? "s" : "")}");
		}
		if (p.TriggeredPieceIds.Count > 0 && !(friendly && p.TriggeredPieceIds.Count == 1))
		{
			parts.Add($"{p.TriggeredPieceIds.Count} chain{(p.TriggeredPieceIds.Count > 1 ? "s" : "")}");
		}
		if (p.FriendlyHealed > 0)
		{
			parts.Add($"+{p.FriendlyHealed} healed");
		}
		if (p.NewTileEffects.Count > 0)
		{
			parts.Add($"{p.NewTileEffects.Count} tile effect{(p.NewTileEffects.Count > 1 ? "s" : "")}");
		}
		return $"Preview: {string.Join(", ", parts)}. Click to confirm.";
	}

	private void OnTileClicked(Vector2I v)
	{
		if (!CanHumanAct())
		{
			return;
		}
		var pos = GridPos.FromVector2I(v);
		switch (_mode)
		{
			case InputMode.Idle:
				HandleIdleClick(pos);
				break;
			case InputMode.CardSelected:
				HandleCardTargetClick(pos);
				break;
			case InputMode.ChoosingMove:
				HandleMoveClick(pos);
				break;
			case InputMode.ChoosingAttack:
				HandleAttackClick(pos);
				break;
		}
	}

	private void HandleIdleClick(GridPos pos)
	{
		Piece piece = _state.Board.GetPieceAt(pos);
		if (piece == null)
		{
			return;
		}
		if (piece.OwnerIndex == HumanPlayer)
		{
			SelectPiece(piece);
		}
		else
		{
			Hud.ShowMessage(DescribePiece(piece), 3.5f);
		}
	}

	private void HandleCardTargetClick(GridPos pos)
	{
		CardData card = _selectedCard;
		if (card == null)
		{
			CancelSelection();
			return;
		}

		if (card.CardType == CardType.Unit)
		{
			Piece piece = _controller.PlayUnitCard(card, pos);
			if (piece == null)
			{
				Hud.ShowMessage(_controller.LastError);
				return;
			}
			Animator.SpawnView(piece);
			_ = Animator.PlaySummon(piece.Id);
			CachePieceNames();
			Log($"You deployed {card.Name} at {pos}.");
			CancelSelection();
			Refresh();
			return;
		}

		CachePieceNames();
		bool cast;
		string targetText;
		if (card.TargetsTile)
		{
			cast = _controller.PlaySpellOnTile(card, pos);
			targetText = pos.ToString();
		}
		else
		{
			Piece target = _state.Board.GetPieceAt(pos);
			cast = _controller.PlaySpellCard(card, target);
			targetText = target != null ? PieceName(target.Id) : pos.ToString();
		}
		if (!cast)
		{
			Hud.ShowMessage(_controller.LastError);
			return;
		}
		Log($"You cast {card.Name} on {targetText}.");
		CancelSelection();
		_ = AnimateSpellEventsAsync(new List<ResolutionEvent>(_controller.LastSpellEvents), _generation);
	}

	/// <summary>
	/// Animates the immediate events of a spell (cast VFX, damage, deaths, heals, tile effects) BEFORE the
	/// views are synced, so killed pieces play their death, then refreshes the HUD and order arrows.
	/// </summary>
	private async Task AnimateSpellEventsAsync(List<ResolutionEvent> events, int generation)
	{
		try
		{
			_mode = InputMode.Busy;
			Board.ClearHighlights();
			await Animator.PlayEvents(events, _state);
			if (!IsCurrent(generation))
			{
				return;
			}
			foreach (ResolutionEvent e in events)
			{
				if (e.Type != ResolutionEventType.SpellCast)
				{
					Log(DescribeEvent(e));
				}
			}
			_mode = InputMode.Idle;
			UpdateHint();
			Refresh();
			UpdateOrderOverlay();
		}
		catch (Exception e)
		{
			GD.PushError($"GameManager: spell animation failed: {e}");
			_mode = InputMode.Idle;
		}
	}

	private void HandleMoveClick(GridPos pos)
	{
		Piece piece = _selectedPiece;
		if (piece == null || _state.GetPiece(piece.Id) == null)
		{
			CancelSelection();
			return;
		}

		if (pos == piece.Position)
		{
			BeginAttackStep(null);
			return;
		}
		if (_controller.GetValidMoveTargets(piece).Contains(pos))
		{
			BeginAttackStep(pos);
			return;
		}

		Piece other = _state.Board.GetPieceAt(pos);
		if (other != null && other.OwnerIndex == HumanPlayer)
		{
			SelectPiece(other);
		}
		else if (other != null)
		{
			Hud.ShowMessage(DescribePiece(other), 3.5f);
		}
		else
		{
			Hud.ShowMessage("Out of movement range. Click a blue tile or the piece itself to stay.");
		}
	}

	private void HandleAttackClick(GridPos pos)
	{
		Piece piece = _selectedPiece;
		if (piece == null || _state.GetPiece(piece.Id) == null)
		{
			CancelSelection();
			return;
		}
		GridPos from = _plannedMove ?? piece.Position;
		GridPos? attack = null;
		if (pos != from && _controller.GetValidAttackTargets(piece, from).Contains(pos))
		{
			attack = pos;
		}
		IssueOrder(piece, _plannedMove, attack);
	}

	private void SelectPiece(Piece piece)
	{
		if (!_controller.CanCommand(piece))
		{
			Hud.ShowMessage(piece.IsSummoningSick(_state.TurnNumber)
				? $"{PieceLabel(piece)}: Summoning sick - can act next turn."
				: _controller.LastError, 3f);
			return;
		}
		if (piece.Order == null && _state.Config.OrderApCost > _state.CurrentPlayer.ActionPoints)
		{
			Hud.ShowMessage($"Not enough AP: commanding {PieceLabel(piece)} costs {_state.Config.OrderApCost} AP.", 3f);
			return;
		}
		CancelSelection();
		_mode = InputMode.ChoosingMove;
		_selectedPiece = piece;
		_plannedMove = null;

		Animator.GetView(piece.Id)?.SetSelected(true);
		Board.ShowHighlights(new[] { piece.Position }, HighlightKind.Selected);
		Board.ShowHighlights(_controller.GetValidMoveTargets(piece), HighlightKind.Move);
		Overlay.ShowPreview(piece, null, null, Board, (IReadOnlyList<GridPos>)null, _state.Board);
		Hud.SetCancelEnabled(true);
		UpdateHint();
	}

	private void BeginAttackStep(GridPos? move)
	{
		Piece piece = _selectedPiece;
		_mode = InputMode.ChoosingAttack;
		_plannedMove = move;
		GridPos from = move ?? piece.Position;

		Board.ClearHighlights(HighlightKind.Move);
		if (move.HasValue)
		{
			Board.ShowHighlights(new[] { move.Value }, HighlightKind.Move);
		}
		Board.ShowHighlights(_controller.GetValidAttackTargets(piece, from), HighlightKind.Attack);
		IReadOnlyList<GridPos> path = move.HasValue ? _controller.GetPlannedPath(piece, move.Value) : null;
		Overlay.ShowPreview(piece, move, null, Board, path, _state.Board);
		UpdateHint();
	}

	private void IssueOrder(Piece piece, GridPos? move, GridPos? attack)
	{
		bool hadOrder = piece.Order != null;
		int apBefore = _state.CurrentPlayer.ActionPoints;
		Piece target = attack.HasValue ? _state.Board.GetPieceAt(attack.Value) : null;
		if (!_controller.SetOrder(piece, move, attack))
		{
			Hud.ShowMessage(_controller.LastError);
			return;
		}
		int apDelta = _state.CurrentPlayer.ActionPoints - apBefore;
		string apText = apDelta < 0 ? $", {-apDelta} AP" : (apDelta > 0 ? $", +{apDelta} AP refunded" : "");

		string name = PieceLabel(piece);
		if (piece.Order == null)
		{
			Hud.ShowMessage(hadOrder ? $"{name}: order cleared{apText}." : $"{name} holds position.");
		}
		else
		{
			string text = move.HasValue ? $"move to {move.Value}" : "stay";
			if (attack.HasValue)
			{
				text += target != null && target.OwnerIndex == HumanPlayer && target != piece
					? $", chain via {PieceLabel(target)}"
					: $", attack {attack.Value}";
			}
			Hud.ShowMessage($"{name}: {text} (order {piece.Order.OrderIndex + 1}{apText}).");
		}
		Animator.GetView(piece.Id)?.SetHasOrder(piece.Order != null);
		CancelSelection();
		Refresh();
		UpdateOrderOverlay();
	}

	// ------------------------------------------------------------------ selection / UI helpers

	private bool IsSelecting() =>
		_mode == InputMode.CardSelected || _mode == InputMode.ChoosingMove || _mode == InputMode.ChoosingAttack;

	private void ResetSelection()
	{
		_selectedHandIndex = -1;
		_selectedCard = null;
		_selectedPiece = null;
		_plannedMove = null;
	}

	/// <summary>Clears any card/piece selection, highlights and previews and returns to Idle (not while Busy).</summary>
	private void CancelSelection()
	{
		ResetSelection();
		if (_mode != InputMode.Busy)
		{
			_mode = InputMode.Idle;
		}
		Board.ClearHighlights();
		Animator.ClearSelection();
		Overlay.ClearPreview();
		Overlay.ClearAttackPreview();
		Overlay.ClearSpellAreaPreview();
		Hud.Hand.SetSelectedIndex(-1);
		Hud.SetCancelEnabled(false);
		UpdateHint();
	}

	private bool CanHumanAct() =>
		_state != null &&
		!_autoplay &&
		_mode != InputMode.Busy &&
		_state.Winner < 0 &&
		_state.CurrentPlayerIndex == HumanPlayer &&
		_state.Phase == GamePhase.Main;

	/// <summary>Refreshes the HUD labels, the human hand, the button states and the "can act" glows.</summary>
	private void Refresh()
	{
		if (_state == null)
		{
			return;
		}
		Hud.UpdateState(_state);

		bool canAct = CanHumanAct();
		PlayerState human = _state.Players[HumanPlayer];
		Hud.Hand.ShowHand(human.Hand, _controller.GetCardCost,
			card => canAct && _controller.GetCardCost(card) <= human.ActionPoints);
		if (_mode == InputMode.CardSelected)
		{
			Hud.Hand.SetSelectedIndex(_selectedHandIndex);
		}
		Hud.SetEndTurnEnabled(canAct);
		Hud.SetCancelEnabled(canAct && IsSelecting());
		Hud.SetDrawEnabled(canAct && _controller.CanDraw());
		UpdateCanAct();
		UpdateBoardInfo();
	}

	/// <summary>
	/// Hover info for the tile under the mouse: the piece standing there (stats, keywords, spells, statuses,
	/// order) or the tile effect on it. Hidden while animations run (the state is already ahead of the view).
	/// </summary>
	private void UpdateBoardInfo()
	{
		if (_state == null || _mode == InputMode.Busy || !_hoverTile.HasValue || Hud.DeckSelect.Visible)
		{
			Hud.HideBoardInfo();
			return;
		}
		GridPos tile = _hoverTile.Value;
		Piece piece = _state.Board.GetPieceAt(tile);
		string text = piece != null ? InfoText.Piece(piece, _state, HumanPlayer) : InfoText.Tile(tile, _state, HumanPlayer);
		Hud.ShowBoardInfo(text);
	}

	/// <summary>Green glow on the human's pieces that can still be commanded this turn (no order yet, enough AP).</summary>
	private void UpdateCanAct()
	{
		if (Animator.IsPlaying)
		{
			return;
		}
		bool humanMain = CanHumanAct();
		int ap = _state.Players[HumanPlayer].ActionPoints;
		foreach (Piece piece in _state.Pieces)
		{
			PieceView view = Animator.GetView(piece.Id);
			if (view == null)
			{
				continue;
			}
			bool canAct = humanMain && piece.OwnerIndex == HumanPlayer && piece.Order == null &&
				ap >= _state.Config.OrderApCost && _controller.CanCommand(piece);
			view.SetCanAct(canAct);
		}
	}

	/// <summary>Redraws the committed order arrows / numbers of the current player.</summary>
	private void UpdateOrderOverlay()
	{
		if (_state == null)
		{
			return;
		}
		Overlay.ShowOrders(_state, Board, (p, t) => _controller.GetPlannedPath(p, t));
	}

	private void UpdateHint()
	{
		if (_state == null)
		{
			return;
		}
		if (_state.Winner >= 0)
		{
			Hud.SetHint("Game over.");
			return;
		}
		switch (_mode)
		{
			case InputMode.Busy:
				return;
			case InputMode.CardSelected:
				if (_selectedCard != null && _selectedCard.CardType == CardType.Spell)
				{
					Hud.SetHint(_selectedCard.TargetsTile
						? $"{_selectedCard.Name}: click a tile to cast it. Esc cancels."
						: $"{_selectedCard.Name}: click a piece to cast it. Esc cancels.");
				}
				else
				{
					Hud.SetHint($"{_selectedCard?.Name}: click a green tile to deploy. Esc cancels.");
				}
				return;
			case InputMode.ChoosingMove:
				Hud.SetHint($"{PieceLabelWithKeywords(_selectedPiece)}: click a blue tile (own pieces get pushed) or itself to stay.");
				return;
			case InputMode.ChoosingAttack:
				Hud.SetHint($"{PieceLabelWithKeywords(_selectedPiece)}: click red to attack (own piece = chain), else move only.");
				return;
		}

		if (_state.CurrentPlayerIndex != HumanPlayer || _autoplay)
		{
			Hud.SetHint($"{PlayerLabel(_state.CurrentPlayerIndex)}'s turn.");
		}
		else if (_state.Phase == GamePhase.Draft)
		{
			Hud.SetHint("Choose a card to keep.");
		}
		else
		{
			Hud.SetHint($"Play cards or command pieces ({_state.Config.OrderApCost} AP). D: draw, C: VP->AP, Enter: end turn.");
		}
	}

	/// <summary>Where cards of destroyed pieces fly to: the human's HUD deck pile (projected into the world), AI = default.</summary>
	private Vector3? GetDeckWorld(int player)
	{
		if (player != HumanPlayer || Hud == null || !IsInsideTree())
		{
			return null;
		}
		Camera3D camera = CameraRig?.Camera ?? GetViewport()?.GetCamera3D();
		Vector2 screen = Hud.DeckPileScreenPosition;
		if (camera == null || screen == Vector2.Zero)
		{
			return null;
		}
		float depth = camera.GlobalPosition.DistanceTo(Board.GlobalPosition) * 0.7f;
		return camera.ProjectPosition(screen, depth);
	}

	private async Task DelayAsync(float seconds)
	{
		if (seconds <= 0f)
		{
			return;
		}
		await ToSignal(GetTree().CreateTimer(seconds), SceneTreeTimer.SignalName.Timeout);
	}

	private bool IsCurrent(int generation) => generation == _generation && IsInsideTree();

	private SimpleAi GetAiFor(int player)
	{
		if (player == AiPlayer)
		{
			return _ai;
		}
		return player == HumanPlayer ? _autoplayAi : null;
	}

	private void Log(string line)
	{
		Hud.Log(line);
		if (_autoplay)
		{
			GD.Print(line);
		}
	}

	private void FlushPendingLog()
	{
		foreach (string line in _pendingLog)
		{
			Log(line);
		}
		_pendingLog.Clear();
	}

	private void CachePieceNames()
	{
		foreach (Piece p in _state.Pieces)
		{
			_pieceNames[p.Id] = PieceNameFor(p);
		}
	}

	private static string PieceNameFor(Piece p) => $"{(p.OwnerIndex == HumanPlayer ? "your" : "AI")} {p.Source?.Name ?? "piece"}";

	private string PieceName(int id)
	{
		if (id < 0)
		{
			return "empty tile";
		}
		return _pieceNames.TryGetValue(id, out string name) ? name : $"piece #{id}";
	}

	private static string PieceLabel(Piece piece) => piece?.Source?.Name ?? "Piece";

	private static string PieceLabelWithKeywords(Piece piece) =>
		piece != null && piece.Keywords != Keyword.None ? $"{PieceLabel(piece)} [{KeywordInfo.Format(piece.Keywords)}]" : PieceLabel(piece);

	private static string PlayerLabel(int player) => player == HumanPlayer ? "You" : "AI";

	/// <summary>One-line piece info for the hint ribbon (hover).</summary>
	private string DescribePieceShort(Piece p)
	{
		string text = $"{(p.OwnerIndex == HumanPlayer ? "Your" : "AI")} {PieceLabel(p)}: {p.CurrentHp}/{p.MaxHp} HP, " +
			$"{p.EffectiveAttack} Atk, {p.EffectiveMovement} Mov, {p.EffectiveRange} Rng";
		if (p.TotalShield > 0)
		{
			text += $", {p.TotalShield} Shield";
		}
		if (p.Keywords != Keyword.None)
		{
			text += $" - {KeywordInfo.Format(p.Keywords)}";
		}
		if (p.IsFrozen)
		{
			text += " - Frozen";
		}
		if (p.HasStatus(StatusEffectType.Overcharged))
		{
			text += " - Overcharged";
		}
		if (p.IsSummoningSick(_state.TurnNumber))
		{
			text += " (Zzz)";
		}
		return text;
	}

	private static string DescribePiece(Piece p)
	{
		string text = $"{(p.OwnerIndex == HumanPlayer ? "Your" : "AI")} {p.Source?.Name}: HP {p.CurrentHp}/{p.MaxHp}, Shield {p.TotalShield}, " +
			$"Atk {p.EffectiveAttack}, Mov {p.EffectiveMovement}, Rng {p.EffectiveRange}" +
			(p.ActiveSpells.Count > 0 ? $", {p.ActiveSpells.Count} spell(s)" : "") +
			(p.IsFrozen ? ", Frozen" : "") +
			(p.HasStatus(StatusEffectType.Overcharged) ? ", Overcharged" : "");
		foreach (Keyword k in KeywordInfo.Split(p.Keywords))
		{
			text += $"\n{KeywordInfo.GetName(k)}: {KeywordInfo.GetDescription(k)}";
		}
		return text;
	}

	private string DescribeEvent(ResolutionEvent e)
	{
		string name = PieceName(e.PieceId);
		return e.Type switch
		{
			ResolutionEventType.Moved => $"{name} moves {e.From} -> {e.To}",
			ResolutionEventType.MoveBlocked => $"{name} is blocked moving to {e.To}",
			ResolutionEventType.Attacked => $"{name} {(e.IsChain ? "chain-fires" : "attacks")} {e.To}" +
				(e.OtherPieceId >= 0 ? $" ({PieceName(e.OtherPieceId)})" : ""),
			ResolutionEventType.AttackCancelled => $"{name}'s attack on {e.To} is cancelled",
			ResolutionEventType.Damaged => $"{name} takes {e.HpLost} damage" +
				(e.ShieldAbsorbed > 0 ? $" ({e.ShieldAbsorbed} blocked)" : "") + $", HP {e.RemainingHp}",
			ResolutionEventType.Died => $"{name} dies",
			ResolutionEventType.ChainTriggered => $"{name} is triggered by {PieceName(e.OtherPieceId)}",
			ResolutionEventType.SpellExpired => $"{e.SpellName} on {name} expired",
			ResolutionEventType.Pushed => $"{name} is pushed {e.From} -> {e.To} by {PieceName(e.OtherPieceId)}",
			ResolutionEventType.PushBlocked => $"{name} cannot be pushed to {e.To}",
			ResolutionEventType.Healed => $"{name} is healed +{e.Amount}, HP {e.RemainingHp}",
			ResolutionEventType.ReturnedToDeck => e.Amount > 0
				? $"{name} rises again: {e.CardName} returns to {PlayerLabel(e.PlayerIndex)}'s deck"
				: $"{e.CardName} returns to {PlayerLabel(e.PlayerIndex)}'s deck",
			ResolutionEventType.TileEffectApplied => $"{KeywordInfo.GetTileEffectName(e.TileEffect)} appears at {e.To} ({e.Amount} turns)",
			ResolutionEventType.TileEffectExpired => $"{KeywordInfo.GetTileEffectName(e.TileEffect)} at {e.To} fades",
			ResolutionEventType.TileDamage => $"{name} burns on lava ({e.Amount})",
			ResolutionEventType.TileHeal => $"{name} is healed +{e.Amount} by the sanctuary, HP {e.RemainingHp}",
			ResolutionEventType.StatusApplied => $"{name} is {KeywordInfo.GetStatusName(e.Status)}",
			ResolutionEventType.StatusExpired => e.IsChain
				? $"{name} releases its {KeywordInfo.GetStatusName(e.Status)} charge"
				: $"{name} is no longer {KeywordInfo.GetStatusName(e.Status)}",
			ResolutionEventType.SpellCast => $"{PlayerLabel(e.PlayerIndex)} cast {e.CardName} at {e.To}",
			_ => e.Type.ToString(),
		};
	}

	private static List<CardData> ToList(Godot.Collections.Array<CardData> cards)
	{
		var list = new List<CardData>();
		if (cards == null)
		{
			return list;
		}
		foreach (CardData card in cards)
		{
			if (card != null)
			{
				list.Add(card);
			}
		}
		return list;
	}
}
