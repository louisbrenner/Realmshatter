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
	/// <summary>
	/// When the battle scene is launched without a pending town battle (BattleSession), switch to the overworld
	/// instead (ignored with --autoplay / --selftest, which keep the old deck-selection flow).
	/// </summary>
	[Export] public bool StartInOverworld { get; set; } = true;
	/// <summary>Random seed for draws (0 = random every game).</summary>
	[Export] public int Seed { get; set; } = 0;
	/// <summary>Pause in seconds before and after the AI plays its cards.</summary>
	[Export] public float AiStepDelay { get; set; } = 0.9f;
	/// <summary>Pause in seconds between two consecutive AI actions, so each one can be followed.</summary>
	[Export] public float AiActionPause { get; set; } = 0.4f;

	[ExportGroup("Nodes")]
	[Export] public BoardView Board { get; set; }
	[Export] public BoardAnimator Animator { get; set; }
	[Export] public CameraRig CameraRig { get; set; }
	[Export] public Hud Hud { get; set; }
	/// <summary>Move / attack planning arrows and attack previews (created at the origin if not assigned).</summary>
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
	private readonly List<List<ResolutionEvent>> _capturedActionEvents = new List<List<ResolutionEvent>>();
	private bool _captureSpells;
	private readonly List<GridPos> _pendingScoreTiles = new List<GridPos>();
	private int _pendingScorePlayer = -1;
	private DeckData _playerTheme;
	private DeckData _aiTheme;
	private GridPos? _hoverTile;
	/// <summary>Tiles already chosen for the current build (Barricades: up to two).</summary>
	private readonly List<GridPos> _buildTiles = new List<GridPos>();
	/// <summary>Hand card under the mouse (for the spell range overlay), or null.</summary>
	private CardData _hoveredHandCard;
	private List<GridPos> _rangeTiles = new List<GridPos>();
	private bool _returnToTown;
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
		bool selftest = Array.IndexOf(userArgs, "--selftest") >= 0;
		if (!BattleSession.IsActive && StartInOverworld && !_autoplay && !selftest && ResourceLoader.Exists(BattleSession.OverworldScene))
		{
			Callable.From(() => GetTree().ChangeSceneToFile(BattleSession.OverworldScene)).CallDeferred();
			return;
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
		Hud.Hand.CardHoverChanged += OnHandCardHoverChanged;
		Hud.Draft.CardChosen += OnDraftCardChosen;
		Hud.DeckSelect.DeckChosen += OnDeckChosen;
		CameraRig.ViewModeChanged += OnViewModeChanged;
		if (Array.IndexOf(userArgs, "--view=3d") >= 0)
		{
			CameraRig.SetMode(ViewMode.ThreeD, false);
		}
		else if (Array.IndexOf(userArgs, "--view=2.5d") >= 0)
		{
			CameraRig.SetMode(ViewMode.TwoPointFiveD, false);
		}
		OnViewModeChanged((int)CameraRig.Mode);

		BeginNewGame();
	}

	/// <summary>Shows the deck selection (when ThemeDecks are set and not autoplaying), otherwise starts right away.</summary>
	private void BeginNewGame()
	{
		if (BattleSession.IsActive)
		{
			// Town battle: the player's own deck against the NPC's deck, no deck selection.
			_playerTheme = BattleSession.BuildPlayerDeck();
			_aiTheme = BattleSession.Opponent.Deck;
			Hud.SetOpponentName(BattleSession.Opponent.Name);
			StartNewGame();
			return;
		}
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
		_rangeTiles.Clear();
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
		if (BattleSession.IsActive)
		{
			_state.Players[AiPlayer].BonusApPerTurn = BattleSession.Opponent.BonusApPerTurn;
		}
		MapGenerator.MapInfo map = MapGenerator.Generate(_state);
		_controller = new TurnController(_state);
		_ai = new SimpleAi(_controller, AiPlayer);
		_autoplayAi = _autoplay ? new SimpleAi(_controller, HumanPlayer) : null;
		SubscribeController();

		_pendingLog.Clear();
		_pieceNames.Clear();
		_capturedSpellEvents.Clear();
		_capturedActionEvents.Clear();
		_pendingScoreTiles.Clear();
		_pendingScorePlayer = -1;
		_hoverTile = null;
		ResetSelection();
		_mode = InputMode.Idle;
		if (playerDeck != null && aiDeck != null)
		{
			_pendingLog.Add($"Your deck: {playerDeck.Name}. AI deck: {aiDeck.Name}.");
		}
		_pendingLog.Add($"Battlefield: {map.Name}. {map.Description}");
		Hud.ShowMessage($"{map.Name} - {map.Description}", 4f);

		var fit = new Vector2(config.BoardWidth, config.BoardHeight);
		if (CameraRig.BoardFitSize != fit)
		{
			CameraRig.BoardFitSize = fit;
			CameraRig.SetMode(CameraRig.Mode, false);
		}

		Board.Build(_state.Board);
		Board.SyncTerrain(_state.Board, config.RockHp);
		_rangeTiles.Clear();
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
		_controller.ActionResolved += OnActionResolved;
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
		_controller.ActionResolved -= OnActionResolved;
	}

	private void OnTurnStarted(int player)
	{
		_pendingLog.Add($"--- Turn {_state.TurnNumber}: {PlayerLabel(player)} ({_state.Players[player].ActionPoints} AP) ---");
		if (player == 1 && _state.Players[player].TurnsStarted == 1 && _state.Config.SecondPlayerFirstTurnBonusAp > 0)
		{
			_pendingLog.Add($"{PlayerLabel(player)} moves second: +{_state.Config.SecondPlayerFirstTurnBonusAp} AP this turn.");
		}
		int wells = 0;
		foreach (Piece p in _state.GetPiecesOf(player))
		{
			wells += p.Building == BuildingType.ManaWell && !p.UnderConstruction ? 1 : 0;
		}
		if (wells > 0)
		{
			_pendingLog.Add($"{PlayerLabel(player)}: +{wells * _state.Config.ManaWellAp} AP from mana wells.");
		}
	}

	private void OnVictoryPointsScored(int player, int points)
	{
		_pendingLog.Add($"{PlayerLabel(player)} scored {points} VP (total {_state.Players[player].VictoryPoints}).");
		_pendingScorePlayer = player;
		_pendingScoreTiles.Clear();
		foreach (Piece p in _state.GetPiecesOf(player))
		{
			if (p.CanScore && _state.Board.IsInScoringZone(p.Position))
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

	private void OnActionResolved(IReadOnlyList<ResolutionEvent> events)
	{
		if (_captureSpells && events != null)
		{
			_capturedActionEvents.Add(new List<ResolutionEvent>(events));
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
		_capturedActionEvents.Clear();
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
		int actionIndex = 0;
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
				case AiActionKind.Command:
				case AiActionKind.Build:
				case AiActionKind.Trap:
					if (actionIndex < _capturedActionEvents.Count)
					{
						List<ResolutionEvent> events = _capturedActionEvents[actionIndex++];
						await Animator.PlayEvents(events, _state, false);
						foreach (ResolutionEvent e in events)
						{
							Log(DescribeEvent(e));
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
			await DelayAsync(AiActionPause);
			if (!IsCurrent(generation))
			{
				return;
			}
		}
	}

	/// <summary>Ends the current turn: animates the expiring effects and the next turn's tile ticks, logs them.</summary>
	private async Task<bool> EndTurnAsync(int generation)
	{
		if (_state.Phase != GamePhase.Main)
		{
			Hud.ShowMessage("You can only end the turn in the main phase.");
			return false;
		}

		_mode = InputMode.Busy;
		Hud.SetHint("Ending turn...");
		Refresh();

		CachePieceNames();
		List<ResolutionEvent> events = _controller.EndTurn();
		var turnStartEvents = new List<ResolutionEvent>(_controller.LastTurnStartEvents);

		Overlay.ClearAll();
		await Animator.PlayEvents(events, _state, turnStartEvents.Count == 0);
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
			BoardState board = _state.Board;
			await Animator.PlayScore(tiles, player, board.ScoreValue);
		}
		_pendingScorePlayer = -1;
	}

	private void EnterHumanTurnOrGameOver()
	{
		ResetSelection();
		ClearAllHighlights();
		Animator.ClearSelection();
		Overlay.ClearPreview();
		Overlay.ClearAttackPreview();
		Overlay.ClearSpellAreaPreview();

		if (_state.Winner >= 0)
		{
			_mode = InputMode.Idle;
			Refresh();
			Hud.SetHint("Game over.");
			if (BattleSession.IsActive)
			{
				string result = BattleSession.Complete(_state.Winner == HumanPlayer);
				_returnToTown = true;
				Hud.ShowWinScreen(_state.Winner, result, "Return to town");
			}
			else if (!_returnToTown)
			{
				Hud.ShowWinScreen(_state.Winner);
			}
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
		if (_returnToTown)
		{
			GetTree().ChangeSceneToFile(BattleSession.OverworldScene);
			return;
		}
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
			// Spells reach only GameConfig.SpellCastRadius tiles around your units: show where they may be centred.
			Board.ShowHighlights(tiles, HighlightKind.Spell);
			UpdateRangeHighlight();
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
				case Key.B:
					OnBuildPressed();
					GetViewport().SetInputAsHandled();
					break;
				case Key.T:
					OnTrapPressed();
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
		UpdateRangeHighlight();
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

	private void ClearAllHighlights()
	{
		Board.ClearHighlights();
		_rangeTiles.Clear();
	}

	private void OnHandCardHoverChanged(CardView card, bool hovered)
	{
		if (hovered)
		{
			_hoveredHandCard = card?.Card;
		}
		else if (card != null && card.Card == _hoveredHandCard)
		{
			_hoveredHandCard = null;
		}
		UpdateRangeHighlight();
	}

	/// <summary>
	/// Faint range overlay: the cast range of the selected (or hovered) spell card, the reach of a hovered building
	/// (Turret shots, Shrine heals, Obelisk cast radius) or of the building a Builder would place on the hovered tile.
	/// </summary>
	private void UpdateRangeHighlight()
	{
		var tiles = new List<GridPos>();
		bool humanMain = _state != null && _controller != null && _mode != InputMode.Busy && _state.Winner < 0
			&& _state.CurrentPlayerIndex == HumanPlayer && _state.Phase == GamePhase.Main;
		if (humanMain)
		{
			CardData spell = _mode == InputMode.CardSelected ? _selectedCard : (_mode == InputMode.Idle ? _hoveredHandCard : null);
			if (spell != null && spell.CardType == CardType.Spell)
			{
				tiles = _controller.GetSpellRangeTiles();
			}
			else if (_hoverTile.HasValue)
			{
				GridPos tile = _hoverTile.Value;
				Piece piece = _state.Board.GetPieceAt(tile);
				if (_mode == InputMode.Idle && piece != null && piece.IsBuilding)
				{
					tiles = _controller.GetBuildingRangeTiles(piece.Building, piece.Position, piece.EffectiveRange);
				}
				else if (_mode == InputMode.ChoosingBuild && _selectedPiece != null && _controller.GetValidBuildTiles(_selectedPiece, _plannedMove).Contains(tile))
				{
					BuildingType type = _controller.GetBuildType(_selectedPiece);
					tiles = _controller.GetBuildingRangeTiles(type, tile, BuildingInfo.GetCard(type).Range);
				}
			}
		}
		else if (_state != null && _hoverTile.HasValue && _state.Board.GetPieceAt(_hoverTile.Value) is Piece building && building.IsBuilding
			&& _controller != null && _state.Winner < 0)
		{
			// Buildings can be inspected while waiting for the opponent, too.
			tiles = _controller.GetBuildingRangeTiles(building.Building, building.Position, building.EffectiveRange);
		}
		if (tiles.Count == _rangeTiles.Count && tiles.TrueForAll(_rangeTiles.Contains))
		{
			return;
		}
		_rangeTiles = tiles;
		if (tiles.Count == 0)
		{
			Board.ClearHighlights(HighlightKind.Range);
		}
		else
		{
			Board.ShowHighlights(tiles, HighlightKind.Range);
		}
	}

	/// <summary>
	/// While choosing an attack: shows the planned order with the hovered attack arc and, for occupied targets,
	/// the predicted consequences (damage incl. friendly fire, kills, pushes, new tile effects).
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
		if (friendly && p.FriendlyHealed <= 0)
		{
			parts.Add($"hits your own {PieceLabel(target)}!");
		}
		if (p.EnemyHpLost > 0 || !friendly)
		{
			parts.Add($"{p.EnemyHpLost} enemy dmg");
		}
		if (p.EnemyKills > 0)
		{
			parts.Add($"{p.EnemyKills} kill{(p.EnemyKills > 1 ? "s" : "")}");
		}
		if (p.FriendlyHpLost > 0)
		{
			parts.Add($"{p.FriendlyHpLost} friendly dmg");
		}
		if (p.FriendlyKills > 0)
		{
			parts.Add($"{p.FriendlyKills} own piece{(p.FriendlyKills > 1 ? "s" : "")} die{(p.FriendlyKills > 1 ? "" : "s")}");
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
			case InputMode.ChoosingBuild:
				HandleBuildClick(pos);
				break;
			case InputMode.ChoosingTrap:
				HandleTrapClick(pos);
				break;
		}
	}

	/// <summary>
	/// Floating ability buttons beside the selected unit (currently: Build for Builders), docked on the side that
	/// hides the fewest tiles the player is choosing from. 'from' is the planned destination during the attack
	/// step (a unit may move and then build instead of attacking); null = its current tile. Unavailable abilities
	/// are shown greyed out with the reason as tooltip.
	/// </summary>
	private void ShowUnitActions(Piece piece, GridPos? from = null)
	{
		var abilities = new List<UnitActionBar.Ability>();
		BuildingType build = _controller.GetBuildType(piece);
		GridPos at = from ?? piece.Position;
		if (build != BuildingType.None)
		{
			int cost = BuildingInfo.GetCost(build);
			int turns = BuildingInfo.GetBuildTurns(build);
			int count = BuildingInfo.GetBuildCount(build);
			string reason = piece.ConstructingId >= 0 ? "Already building." :
				(cost > _state.CurrentPlayer.ActionPoints ? $"Needs {cost} AP." :
				(_controller.GetValidBuildTiles(piece, from).Count == 0 ? "No free tile next to it." : ""));
			string what = count > 1 ? $"{count} {BuildingInfo.GetName(build)}s" : BuildingInfo.GetName(build);
			abilities.Add(new UnitActionBar.Ability(FxIconShape.Hammer, $"Build {BuildingInfo.GetName(build)}", cost, reason.Length == 0,
				$"Build {what}: {BuildingInfo.GetDescription(build)} ({turns} turn{(turns > 1 ? "s" : "")}, B). Can follow a move instead of an attack." +
				(reason.Length > 0 ? $"\n{reason}" : ""), OnBuildPressed));
		}
		TrapType? trap = _controller.GetTrapType(piece);
		if (trap.HasValue)
		{
			int cost = _state.Config.TrapApCost;
			string reason = piece.ConstructingId >= 0 ? "Busy building." :
				(cost > _state.CurrentPlayer.ActionPoints ? $"Needs {cost} AP." :
				(_controller.GetValidTrapTiles(piece, from).Count == 0 ? "No free tile next to it." : ""));
			abilities.Add(new UnitActionBar.Ability(FxIconShape.Trap, "Set Trap", cost, reason.Length == 0,
				$"{TrapInfo.GetName(trap.Value)}: hidden from the enemy. An enemy stepping on it is stopped and takes {TrapInfo.Describe(trap.Value)} " +
				"(T). Can follow a move instead of an attack." + (reason.Length > 0 ? $"\n{reason}" : ""), OnTrapPressed));
		}
		if (abilities.Count == 0)
		{
			Hud.ActionBar.HideBar();
			return;
		}
		int id = piece.Id;
		bool moved = at != piece.Position;
		List<GridPos> keepVisible = from.HasValue ? _controller.GetValidAttackTargets(piece, at) : _controller.GetValidMoveTargets(piece);
		keepVisible.Add(at);
		Hud.ActionBar.ShowFor(() =>
		{
			PieceView view = Animator.GetView(id);
			Camera3D camera = CameraRig?.Camera ?? GetViewport()?.GetCamera3D();
			if (view == null || camera == null || !IsInstanceValid(view))
			{
				return null;
			}
			Vector3 body = (moved ? Board.GridToWorld(at) : view.GlobalPosition) + new Vector3(0, 0.3f, 0);
			if (camera.IsPositionBehind(body))
			{
				return null;
			}
			Vector2 center = camera.UnprojectPosition(body);
			float halfTile = camera.UnprojectPosition(Board.GridToWorld(at))
				.DistanceTo(camera.UnprojectPosition(Board.GridToWorld(new GridPos(at.X + 1, at.Y)))) * 0.5f;
			var avoid = new List<Vector2>(keepVisible.Count);
			foreach (GridPos pos in keepVisible)
			{
				avoid.Add(camera.UnprojectPosition(Board.GridToWorld(pos)));
			}
			return new UnitActionBar.Placement(center, halfTile, avoid);
		}, abilities);
	}

	/// <summary>
	/// Build mode: right after selecting the unit (build where it stands) or after choosing its move (the build
	/// replaces the attack). Green tiles around the destination are valid; Barricades take two clicks.
	/// </summary>
	private void OnBuildPressed()
	{
		Piece piece = _selectedPiece;
		if (!CanHumanAct() || piece == null || (_mode != InputMode.ChoosingMove && _mode != InputMode.ChoosingAttack))
		{
			return;
		}
		BuildingType type = _controller.GetBuildType(piece);
		if (type == BuildingType.None)
		{
			return;
		}
		if (_mode == InputMode.ChoosingMove)
		{
			_plannedMove = null;
		}
		List<GridPos> tiles = _controller.GetValidBuildTiles(piece, _plannedMove);
		if (tiles.Count == 0)
		{
			Hud.ShowMessage("No free tile next to this unit to build on.");
			return;
		}
		_mode = InputMode.ChoosingBuild;
		_buildTiles.Clear();
		Hud.ActionBar.HideBar();
		Board.ClearHighlights(HighlightKind.Move);
		Board.ClearHighlights(HighlightKind.Attack);
		Overlay.ClearAttackPreview();
		if (_plannedMove.HasValue)
		{
			Board.ShowHighlights(new[] { _plannedMove.Value }, HighlightKind.Move);
			Overlay.ShowPreview(piece, _plannedMove, null, Board, _controller.GetPlannedPath(piece, _plannedMove.Value), _state.Board);
		}
		else
		{
			Overlay.ClearPreview();
		}
		Board.ShowHighlights(tiles, HighlightKind.Deploy);
		UpdateRangeHighlight();
		UpdateBuildHint();
	}

	/// <summary>Trap mode: like building, right after selecting the Trapper or after choosing its move (replaces the attack).</summary>
	private void OnTrapPressed()
	{
		Piece piece = _selectedPiece;
		if (!CanHumanAct() || piece == null || (_mode != InputMode.ChoosingMove && _mode != InputMode.ChoosingAttack))
		{
			return;
		}
		TrapType? trap = _controller.GetTrapType(piece);
		if (!trap.HasValue)
		{
			return;
		}
		if (_mode == InputMode.ChoosingMove)
		{
			_plannedMove = null;
		}
		List<GridPos> tiles = _controller.GetValidTrapTiles(piece, _plannedMove);
		if (tiles.Count == 0)
		{
			Hud.ShowMessage("No free tile next to this unit for a trap.");
			return;
		}
		_mode = InputMode.ChoosingTrap;
		Hud.ActionBar.HideBar();
		Board.ClearHighlights(HighlightKind.Move);
		Board.ClearHighlights(HighlightKind.Attack);
		Overlay.ClearAttackPreview();
		if (_plannedMove.HasValue)
		{
			Board.ShowHighlights(new[] { _plannedMove.Value }, HighlightKind.Move);
			Overlay.ShowPreview(piece, _plannedMove, null, Board, _controller.GetPlannedPath(piece, _plannedMove.Value), _state.Board);
		}
		else
		{
			Overlay.ClearPreview();
		}
		Board.ShowHighlights(tiles, HighlightKind.Deploy);
		Hud.SetHint($"{PieceLabel(piece)}: click a green tile to hide a {TrapInfo.GetName(trap.Value)} ({_state.Config.TrapApCost} AP). Esc cancels.");
	}

	private void HandleTrapClick(GridPos pos)
	{
		Piece piece = _selectedPiece;
		if (piece == null)
		{
			CancelSelection();
			return;
		}
		GridPos? move = _plannedMove;
		CachePieceNames();
		List<ResolutionEvent> events = _controller.SetTrap(piece, pos, move);
		if (events == null)
		{
			Hud.ShowMessage(_controller.LastError);
			return;
		}
		TrapType trap = _controller.GetTrapType(piece) ?? TrapType.Spike;
		Log($"Your {PieceLabel(piece)} {(move.HasValue ? $"moves to {move.Value} and " : "")}hides a {TrapInfo.GetName(trap)} at {pos}.");
		CancelSelection();
		_ = AnimateSpellEventsAsync(new List<ResolutionEvent>(events), _generation);
	}

	private void UpdateBuildHint()
	{
		Piece piece = _selectedPiece;
		if (piece == null)
		{
			return;
		}
		BuildingType type = _controller.GetBuildType(piece);
		int count = BuildingInfo.GetBuildCount(type);
		string name = BuildingInfo.GetName(type);
		string first = count > 1 ? $"click green tiles for your {count} {name}s" : $"click a green tile to build a {name}";
		Hud.SetHint(_buildTiles.Count == 0
			? $"{PieceLabel(piece)}: {first} ({BuildingInfo.GetCost(type)} AP). Esc cancels."
			: $"{PieceLabel(piece)}: click a second green tile - or the marked tile again to build just one.");
	}

	private void HandleBuildClick(GridPos pos)
	{
		Piece piece = _selectedPiece;
		if (piece == null)
		{
			CancelSelection();
			return;
		}
		BuildingType type = _controller.GetBuildType(piece);
		List<GridPos> valid = _controller.GetValidBuildTiles(piece, _plannedMove);
		bool again = _buildTiles.Contains(pos);
		if (!again)
		{
			if (!valid.Contains(pos))
			{
				Hud.ShowMessage("Build on a green tile next to the unit.");
				return;
			}
			_buildTiles.Add(pos);
			int remaining = valid.FindAll(t => !_buildTiles.Contains(t)).Count;
			if (_buildTiles.Count < BuildingInfo.GetBuildCount(type) && remaining > 0)
			{
				// Barricades: mark the first tile and wait for the second.
				Sfx.Play(SfxId.CardPick);
				Board.ShowHighlights(_buildTiles, HighlightKind.Selected);
				Board.ShowHighlights(new[] { piece.Position }, HighlightKind.Hover);
				UpdateBuildHint();
				return;
			}
		}
		CachePieceNames();
		GridPos? move = _plannedMove;
		var tiles = new List<GridPos>(_buildTiles);
		List<ResolutionEvent> events = _controller.Build(piece, tiles, move);
		if (events == null)
		{
			Hud.ShowMessage(_controller.LastError);
			_buildTiles.Clear();
			return;
		}
		string where = string.Join(" and ", tiles);
		string what = tiles.Count > 1 ? $"{tiles.Count} {BuildingInfo.GetName(type)}s" : $"a {BuildingInfo.GetName(type)}";
		Log($"Your {PieceLabel(piece)} {(move.HasValue ? $"moves to {move.Value} and " : "")}starts building {what} at {where}.");
		CancelSelection();
		_ = AnimateSpellEventsAsync(new List<ResolutionEvent>(events), _generation);
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
			ClearAllHighlights();
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
		ExecuteAction(piece, _plannedMove, attack);
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
		if (_state.Config.OrderApCost > _state.CurrentPlayer.ActionPoints)
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
		ShowUnitActions(piece);
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
		ShowUnitActions(piece, move ?? piece.Position);
		UpdateHint();
	}

	/// <summary>Commands a piece: its move and attack resolve immediately and are animated right away.</summary>
	private void ExecuteAction(Piece piece, GridPos? move, GridPos? attack)
	{
		bool moves = move.HasValue && move.Value != piece.Position;
		if (!moves && !attack.HasValue)
		{
			CancelSelection();
			Hud.ShowMessage($"{PieceLabel(piece)} holds position (no AP spent).");
			return;
		}
		CachePieceNames();
		Piece target = attack.HasValue ? _state.Board.GetPieceAt(attack.Value) : null;
		List<ResolutionEvent> events = _controller.Act(piece, move, attack);
		if (events == null)
		{
			Hud.ShowMessage(_controller.LastError);
			return;
		}
		string text = moves ? $"moves to {move.Value}" : "stays";
		if (attack.HasValue)
		{
			text += target != null ? $" and attacks {PieceName(target.Id)}" : $" and attacks {attack.Value}";
		}
		Log($"Your {PieceLabel(piece)} {text}.");
		CancelSelection();
		_ = AnimateSpellEventsAsync(new List<ResolutionEvent>(events), _generation);
	}

	// ------------------------------------------------------------------ selection / UI helpers

	private bool IsSelecting() =>
		_mode == InputMode.CardSelected || _mode == InputMode.ChoosingMove || _mode == InputMode.ChoosingAttack
		|| _mode == InputMode.ChoosingBuild || _mode == InputMode.ChoosingTrap;

	private void ResetSelection()
	{
		_selectedHandIndex = -1;
		_selectedCard = null;
		_selectedPiece = null;
		_plannedMove = null;
		_buildTiles.Clear();
	}

	/// <summary>Clears any card/piece selection, highlights and previews and returns to Idle (not while Busy).</summary>
	private void CancelSelection()
	{
		ResetSelection();
		if (_mode != InputMode.Busy)
		{
			_mode = InputMode.Idle;
		}
		ClearAllHighlights();
		Animator.ClearSelection();
		Overlay.ClearPreview();
		Overlay.ClearAttackPreview();
		Overlay.ClearSpellAreaPreview();
		Hud.Hand.SetSelectedIndex(-1);
		Hud.SetCancelEnabled(false);
		Hud.ActionBar.HideBar();
		UpdateRangeHighlight();
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
		InfoSheet sheet = piece != null ? InfoText.Piece(piece, _state, HumanPlayer) : InfoText.Tile(tile, _state, HumanPlayer);
		Hud.ShowBoardInfo(sheet);
	}

	/// <summary>Green glow on the human's pieces that can still be commanded this turn (no order yet, enough AP).</summary>
	private void UpdateCanAct()
	{
		Animator.SyncExhausted(_state);
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
			bool canAct = humanMain && piece.OwnerIndex == HumanPlayer && !piece.HasActed(_state.TurnNumber) &&
				ap >= _state.Config.OrderApCost && _controller.CanCommand(piece);
			view.SetCanAct(canAct);
		}
	}

	/// <summary>Clears the order overlay (actions resolve immediately; nothing stays queued).</summary>
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
				Hud.SetHint($"{PieceLabelWithKeywords(_selectedPiece)}: click red to attack now (own pieces take damage too), elsewhere = move only.");
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
			ResolutionEventType.Attacked => $"{name} {(e.IsSecondary ? "zaps" : "attacks")} {e.To}" +
				(e.OtherPieceId >= 0 ? $" ({PieceName(e.OtherPieceId)})" : ""),
			ResolutionEventType.AttackCancelled => $"{name}'s attack on {e.To} is cancelled",
			ResolutionEventType.Damaged => $"{name} takes {e.HpLost} damage" +
				(e.ShieldAbsorbed > 0 ? $" ({e.ShieldAbsorbed} blocked)" : "") + $", HP {e.RemainingHp}",
			ResolutionEventType.Died => $"{name} dies",
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
			ResolutionEventType.StatusExpired => e.IsSecondary
				? $"{name} releases its {KeywordInfo.GetStatusName(e.Status)} charge"
				: $"{name} is no longer {KeywordInfo.GetStatusName(e.Status)}",
			ResolutionEventType.SpellCast => $"{PlayerLabel(e.PlayerIndex)} cast {e.CardName} at {e.To}{(e.Amount > 0 ? " (empowered by an Obelisk)" : "")}",
			ResolutionEventType.Deathrattle => $"Deathrattle of {e.CardName}: {e.SpellName}",
			ResolutionEventType.BuildingStarted => $"{name} starts building a {e.SpellName} at {e.To}",
			ResolutionEventType.BuildingCompleted => $"{e.SpellName} at {e.To} is finished",
			ResolutionEventType.AuraPulse => $"{name}'s {e.SpellName} pulses",
			ResolutionEventType.FirstHitTriggered => $"{name} is hit for the first time: {e.SpellName}",
			ResolutionEventType.TrapSet => e.PlayerIndex == HumanPlayer ? $"{name} hides a {e.CardName} at {e.To}" : "AI hides a trap somewhere",
			ResolutionEventType.TrapTriggered => $"{name} steps into {(e.PlayerIndex == HumanPlayer ? "your" : "an enemy")} {e.CardName} at {e.To}!",
			ResolutionEventType.TerrainDamaged => e.RemainingHp <= 0 ? $"The rock at {e.To} crumbles" : $"The rock at {e.To} takes {e.Amount} damage ({e.RemainingHp} HP left)",
			ResolutionEventType.ApGained => $"{PlayerLabel(e.PlayerIndex)} gain{(e.PlayerIndex == HumanPlayer ? "" : "s")} {e.Amount} AP" +
				$"{(e.IsSecondary ? " next turn" : "")} ({e.CardName})",
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
