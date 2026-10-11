using System.Threading.Tasks;
using Godot;

namespace ProjectClaude;

/// <summary>
/// Screen-space HUD (root of Scenes/UI/Hud.tscn), Hearthstone styled: victory points as coin stacks,
/// action points as mana crystals with VP-to-AP conversion slots, a deck pile Draw button, a big
/// End Turn button, a turn plaque, parchment hint/toast ribbons, a collapsible combat log, turn
/// banners, a resolution ticker and a victory/defeat screen. The whole layout is designed for
/// ReferenceResolution and scaled uniformly to the window. It displays state and emits button
/// signals; it never changes the game state itself.
/// </summary>
public partial class Hud : CanvasLayer
{
	[Signal] public delegate void EndTurnPressedEventHandler();
	[Signal] public delegate void ViewTogglePressedEventHandler();
	[Signal] public delegate void CancelPressedEventHandler();
	[Signal] public delegate void RestartPressedEventHandler();
	[Signal] public delegate void DrawPressedEventHandler();
	/// <summary>The player clicked a VP-to-AP conversion slot (spend 1 VP for 1 AP).</summary>
	[Signal] public delegate void ConvertVpPressedEventHandler();

	private const int HumanPlayer = 0;
	private const int AiPlayer = 1;
	private const float HintSideMargin = 236f;
	private const int HintFontSize = 15;
	private const int HintMinFontSize = 13;

	/// <summary>Design resolution of the HUD layout; the HUD is scaled uniformly to fit the window.</summary>
	[Export] public Vector2 ReferenceResolution { get; set; } = new Vector2(1152, 648);
	/// <summary>Lower bound of the uniform UI scale (small windows).</summary>
	[Export] public float MinScale { get; set; } = 0.7f;
	/// <summary>Plays a turn banner automatically when UpdateState sees a new turn.</summary>
	[Export] public bool AutoTurnBanner { get; set; } = true;

	private Control _root;
	private TurnIndicator _turnIndicator;
	private Button _viewButton;
	private PanelContainer _hintRibbon;
	private Label _hintLabel;
	private PanelContainer _ticker;
	private Label _tickerLabel;
	private PanelContainer _toast;
	private Label _messageLabel;
	private VictoryCoinStack _playerCoins;
	private VictoryCoinStack _aiCoins;
	private Label _playerVpLabel;
	private Label _aiVpLabel;
	private ManaCrystalBar _playerMana;
	private ManaCrystalBar _aiMana;
	private VpConvertButton _vpConvert;
	private DeckPile _deckPile;
	private EndTurnButton _endTurnButton;
	private Button _cancelButton;
	private CombatLog _log;
	private TurnBanner _turnBanner;
	private Control _winScreen;
	private ColorRect _winDim;
	private VictoryBanner _victoryBanner;
	private Button _restartButton;

	private Tween _messageTween;
	private Tween _tickerTween;
	private Tween _winTween;
	private GameState _lastState;
	private int _lastTurn = -1;
	private int _lastPlayer = -1;
	private readonly int[] _turnMaxAp = new int[2];
	private readonly int[] _lastVp = { -1, -1 };
	private string _lastBannerKey = "";
	private Task _bannerTask = Task.CompletedTask;
	private InfoPanel _boardInfo;
	private InfoPanel _cardInfo;
	private CardView _cardInfoOwner;

	/// <summary>The hand display (Root/HandView).</summary>
	public HandView Hand { get; private set; }

	/// <summary>The draft popup (Root/DraftPopup).</summary>
	public DraftPopup Draft { get; private set; }

	/// <summary>The deck selection screen (created in code on top of the HUD).</summary>
	public DeckSelectScreen DeckSelect { get; private set; }

	/// <summary>Current uniform UI scale (window size / ReferenceResolution).</summary>
	public float UiScale { get; private set; } = 1f;

	/// <summary>Screen position (viewport pixels) of the center of the human's deck pile.</summary>
	public Vector2 DeckPileScreenPosition =>
		_deckPile != null ? _deckPile.GetGlobalTransformWithCanvas() * (_deckPile.Size * 0.5f) : Vector2.Zero;

	public override void _Ready()
	{
		_root = GetNode<Control>("Root");
		_turnIndicator = GetNode<TurnIndicator>("Root/TopBar/TurnIndicator");
		_viewButton = GetNode<Button>("Root/TopBar/ViewButton");
		_hintRibbon = GetNode<PanelContainer>("Root/TopStack/HintRow/HintRibbon");
		_hintLabel = GetNode<Label>("Root/TopStack/HintRow/HintRibbon/HintLabel");
		_ticker = GetNode<PanelContainer>("Root/TopStack/TickerRow/Ticker");
		_tickerLabel = GetNode<Label>("Root/TopStack/TickerRow/Ticker/TickerLabel");
		_toast = GetNode<PanelContainer>("Root/TopStack/ToastRow/Toast");
		_messageLabel = GetNode<Label>("Root/TopStack/ToastRow/Toast/MessageLabel");
		_aiCoins = GetNode<VictoryCoinStack>("Root/AiPanel/VBox/Coins");
		_aiVpLabel = GetNode<Label>("Root/AiPanel/VBox/Header/VpLabel");
		_aiMana = GetNode<ManaCrystalBar>("Root/AiPanel/VBox/Mana");
		_playerCoins = GetNode<VictoryCoinStack>("Root/PlayerPanel/VBox/Coins");
		_playerVpLabel = GetNode<Label>("Root/PlayerPanel/VBox/Header/VpLabel");
		_playerMana = GetNode<ManaCrystalBar>("Root/ManaPanel/HBox/ManaBar");
		_vpConvert = GetNode<VpConvertButton>("Root/ManaPanel/HBox/VpConvert");
		_deckPile = GetNode<DeckPile>("Root/DeckPile");
		_endTurnButton = GetNode<EndTurnButton>("Root/EndTurnButton");
		_cancelButton = GetNode<Button>("Root/CancelButton");
		_log = GetNode<CombatLog>("Root/LogPanel");
		_turnBanner = GetNode<TurnBanner>("Root/TurnBanner");
		_winScreen = GetNode<Control>("Root/WinScreen");
		_winDim = GetNode<ColorRect>("Root/WinScreen/Dim");
		_victoryBanner = GetNode<VictoryBanner>("Root/WinScreen/Center/VBox/Banner");
		_restartButton = GetNode<Button>("Root/WinScreen/Center/VBox/RestartButton");
		Hand = GetNode<HandView>("Root/HandView");
		Draft = GetNode<DraftPopup>("Root/DraftPopup");

		_root.Theme = HudStyle.CreateTheme();
		ApplyStyles();

		_endTurnButton.Pressed += () =>
		{
			Sfx.Play(SfxId.EndTurn);
			EmitSignal(SignalName.EndTurnPressed);
		};
		_viewButton.Pressed += () =>
		{
			Sfx.Play(SfxId.ButtonClick);
			EmitSignal(SignalName.ViewTogglePressed);
		};
		_cancelButton.Pressed += () =>
		{
			Sfx.Play(SfxId.ButtonClick);
			EmitSignal(SignalName.CancelPressed);
		};
		_restartButton.Pressed += () =>
		{
			Sfx.Play(SfxId.ButtonClick);
			EmitSignal(SignalName.RestartPressed);
		};
		_deckPile.Pressed += () =>
		{
			Sfx.Play(SfxId.CardPick);
			EmitSignal(SignalName.DrawPressed);
		};
		_vpConvert.Pressed += () =>
		{
			Sfx.Play(SfxId.Coin);
			EmitSignal(SignalName.ConvertVpPressed);
		};

		DeckSelect = new DeckSelectScreen { Name = "DeckSelect", CardScene = Hand.CardScene };
		_root.AddChild(DeckSelect);
		_boardInfo = new InfoPanel { Name = "BoardInfo", TextWidth = 250f };
		_root.AddChild(_boardInfo);
		_cardInfo = new InfoPanel { Name = "CardInfo", TextWidth = 240f };
		_root.AddChild(_cardInfo);
		Hand.CardHoverChanged += OnCardHoverChanged;
		Draft.CardHoverChanged += OnCardHoverChanged;

		_toast.Visible = false;
		_ticker.Visible = false;
		_winScreen.Visible = false;
		_hintRibbon.Visible = false;
		SetCancelEnabled(false);
		_vpConvert.SetState(0, 2, false);

		GetViewport().SizeChanged += ApplyScale;
		ApplyScale();
	}

	public override void _ExitTree()
	{
		Viewport viewport = GetViewport();
		if (viewport != null)
		{
			viewport.SizeChanged -= ApplyScale;
		}
	}

	public override void _Process(double delta)
	{
		// The board only reports hovers while the mouse is not over UI: hide its info when a control takes over.
		if (_boardInfo != null && _boardInfo.Visible &&
			(GetViewport().GuiGetHoveredControl() != null || (_cardInfo != null && _cardInfo.Visible)))
		{
			_boardInfo.HidePanel();
		}
	}

	/// <summary>Shows the board hover info (BBCode, see InfoText) next to the mouse; empty text hides it.</summary>
	public void ShowBoardInfo(string bbcode)
	{
		if (string.IsNullOrEmpty(bbcode) || (_cardInfo != null && _cardInfo.Visible) || GetViewport().GuiGetHoveredControl() != null)
		{
			_boardInfo.HidePanel();
			return;
		}
		_boardInfo.ShowAtCursor(bbcode);
	}

	/// <summary>Hides the board hover info.</summary>
	public void HideBoardInfo()
	{
		_boardInfo?.HidePanel();
	}

	private void OnCardHoverChanged(CardView card, bool hovered)
	{
		if (hovered && card?.Card != null)
		{
			_cardInfoOwner = card;
			_boardInfo.HidePanel();
			_cardInfo.ShowBeside(card, InfoText.Card(card.Card, card.ApCost));
		}
		else if (card == _cardInfoOwner)
		{
			_cardInfoOwner = null;
			_cardInfo.HidePanel();
		}
	}

	/// <summary>
	/// Refreshes everything derivable from the state: VP coin stacks, AP crystals of both players,
	/// VP conversion slots, deck pile, turn plaque, End Turn button state and (optionally) the turn banner.
	/// </summary>
	public void UpdateState(GameState state)
	{
		if (state == null)
		{
			return;
		}
		bool newGame = !ReferenceEquals(state, _lastState);
		int current = state.CurrentPlayerIndex;
		bool newTurn = newGame || state.TurnNumber != _lastTurn || current != _lastPlayer;
		if (newGame)
		{
			_turnMaxAp[0] = 0;
			_turnMaxAp[1] = 0;
			_lastBannerKey = "";
		}

		int target = state.Config.PointsTarget;
		PlayerState human = state.Players[HumanPlayer];
		PlayerState ai = state.Players[AiPlayer];
		_playerCoins.Target = target;
		_aiCoins.Target = target;
		UpdateVp(HumanPlayer, human.VictoryPoints, target, !newGame);
		UpdateVp(AiPlayer, ai.VictoryPoints, target, !newGame);

		if (newTurn && current >= 0 && current < _turnMaxAp.Length)
		{
			_turnMaxAp[current] = state.CurrentPlayer.ActionPoints;
		}
		for (int p = 0; p < _turnMaxAp.Length; p++)
		{
			_turnMaxAp[p] = Mathf.Max(Mathf.Max(_turnMaxAp[p], state.Players[p].ActionPoints), state.Config.BaseAp);
		}
		_playerMana.MinSlots = state.Config.BaseAp;
		_aiMana.MinSlots = state.Config.BaseAp;
		_playerMana.SetValues(human.ActionPoints, _turnMaxAp[HumanPlayer], !newGame);
		_aiMana.SetValues(ai.ActionPoints, _turnMaxAp[AiPlayer], !newGame);

		bool humanMain = current == HumanPlayer && state.Phase == GamePhase.Main && state.Winner < 0;
		int maxConvert = state.Config.MaxVpToApPerTurn;
		_vpConvert.SetState(human.VpConvertedThisTurn, maxConvert,
			humanMain && human.VictoryPoints > 0 && human.VpConvertedThisTurn < maxConvert);

		_deckPile.SetDeck(human.Deck.Count, state.Config.DrawApCost);
		_endTurnButton.SetPlayerTurn(current == HumanPlayer);
		_endTurnButton.SetNothingLeft(humanMain && human.ActionPoints <= 0);
		_turnIndicator.SetTurn(state.TurnNumber, current, PhaseCaption(state));

		_lastState = state;
		_lastTurn = state.TurnNumber;
		_lastPlayer = current;

		if (AutoTurnBanner && newTurn && state.Winner < 0 && state.Phase != GamePhase.NotStarted)
		{
			_ = ShowTurnBanner(current, state.TurnNumber);
		}
	}

	/// <summary>Sets the human player's AP crystals explicitly (current / maximum this turn).</summary>
	public void SetActionPoints(int current, int max)
	{
		_turnMaxAp[HumanPlayer] = Mathf.Max(max, current);
		_playerMana.SetValues(current, _turnMaxAp[HumanPlayer]);
	}

	/// <summary>Updates the VP-to-AP conversion slots (used this turn, maximum per turn, clickable).</summary>
	public void SetVpConversion(int usedThisTurn, int maxPerTurn, bool canConvert)
	{
		_vpConvert.SetState(usedThisTurn, maxPerTurn, canConvert);
	}

	/// <summary>Green "nothing left to do" glow on the End Turn button.</summary>
	public void SetEndTurnHighlight(bool nothingLeft)
	{
		_endTurnButton.SetNothingLeft(nothingLeft);
	}

	/// <summary>Updates the deck pile count and draw cost explicitly.</summary>
	public void SetDeckCount(int count, int drawCost)
	{
		_deckPile.SetDeck(count, drawCost);
	}

	/// <summary>
	/// Plays the big "YOUR TURN" / "ENEMY TURN" banner (~1.25 s). Awaitable. Repeated calls for the same
	/// player and turn (e.g. the automatic one from UpdateState) return the running banner instead.
	/// </summary>
	public Task ShowTurnBanner(int player, int turnNumber)
	{
		string key = $"{player}:{turnNumber}";
		if (key == _lastBannerKey)
		{
			return _bannerTask;
		}
		_lastBannerKey = key;
		bool human = player == HumanPlayer;
		Sfx.Play(human ? SfxId.TurnStart : SfxId.TurnEnemy);
		_bannerTask = _turnBanner.Play(human ? "YOUR TURN" : "ENEMY TURN", $"Turn {turnNumber}", HudStyle.Accent(player));
		return _bannerTask;
	}

	/// <summary>
	/// Shows the small resolution ticker, e.g. "Order 2/4: Swordsman attacks". index is 1-based;
	/// total &lt;= 0 omits the count. Hides itself a few seconds after the last step.
	/// </summary>
	public void ShowResolutionStep(int index, int total, string text)
	{
		string head = total > 0 ? $"Order {index}/{total}" : $"Step {index}";
		_tickerLabel.Text = string.IsNullOrEmpty(text) ? head : $"{head}  -  {text}";
		_ticker.Visible = true;
		_ticker.PivotOffset = _ticker.Size * 0.5f;
		_tickerTween?.Kill();
		_ticker.Modulate = Colors.White;
		_ticker.Scale = new Vector2(1.08f, 1.08f);
		_tickerTween = CreateTween();
		_tickerTween.TweenProperty(_ticker, "scale", Vector2.One, 0.15f).SetTrans(Tween.TransitionType.Back).SetEase(Tween.EaseType.Out);
		_tickerTween.TweenInterval(3f);
		_tickerTween.TweenProperty(_ticker, "modulate:a", 0f, 0.4f);
		_tickerTween.TweenCallback(Callable.From(() => _ticker.Visible = false));
	}

	/// <summary>Shows the resolution ticker without an order count.</summary>
	public void ShowResolutionStep(int index, string text) => ShowResolutionStep(index, 0, text);

	/// <summary>Hides the resolution ticker.</summary>
	public void HideResolutionStep()
	{
		_tickerTween?.Kill();
		_tickerTween = CreateTween();
		_tickerTween.TweenProperty(_ticker, "modulate:a", 0f, 0.25f);
		_tickerTween.TweenCallback(Callable.From(() => _ticker.Visible = false));
	}

	/// <summary>Sets the parchment hint ribbon below the top bar (empty string hides it).</summary>
	public void SetHint(string text)
	{
		text ??= "";
		_hintLabel.Text = text;
		_hintRibbon.Visible = text.Length > 0;
		// Fit between the side panels: shrink the font a little, then wrap.
		float maxWidth = Mathf.Max(240f, _root.Size.X - 2f * HintSideMargin);
		int size = HintFontSize;
		while (size > HintMinFontSize && HudStyle.TextWidth(text, size) > maxWidth)
		{
			size--;
		}
		_hintLabel.AddThemeFontSizeOverride("font_size", size);
		bool wrap = HudStyle.TextWidth(text, size) > maxWidth;
		_hintLabel.AutowrapMode = wrap ? TextServer.AutowrapMode.WordSmart : TextServer.AutowrapMode.Off;
		_hintLabel.CustomMinimumSize = wrap ? new Vector2(maxWidth, 0f) : Vector2.Zero;
	}

	/// <summary>Shows a temporary toast ribbon that pops in and fades out after the given time.</summary>
	public void ShowMessage(string text, float seconds = 2f)
	{
		_messageTween?.Kill();
		_messageLabel.Text = text ?? "";
		_toast.Visible = !string.IsNullOrEmpty(text);
		_toast.Modulate = Colors.White;
		_toast.PivotOffset = _toast.Size * 0.5f;
		_toast.Scale = new Vector2(0.85f, 0.85f);

		_messageTween = CreateTween();
		_messageTween.TweenProperty(_toast, "scale", Vector2.One, 0.18f).SetTrans(Tween.TransitionType.Back).SetEase(Tween.EaseType.Out);
		_messageTween.TweenInterval(Mathf.Max(0.1f, seconds));
		_messageTween.TweenProperty(_toast, "modulate:a", 0f, 0.4f);
		_messageTween.TweenCallback(Callable.From(() => _toast.Visible = false));
	}

	/// <summary>Sets the view toggle button caption, e.g. "2D" -> "View: 2D".</summary>
	public void SetViewModeLabel(string modeName)
	{
		_viewButton.Text = $"View: {modeName}";
	}

	/// <summary>Enables or disables the End Turn button.</summary>
	public void SetEndTurnEnabled(bool enabled)
	{
		_endTurnButton.Disabled = !enabled;
	}

	/// <summary>Enables or disables the Draw button (deck pile).</summary>
	public void SetDrawEnabled(bool enabled)
	{
		_deckPile.Disabled = !enabled;
	}

	/// <summary>Enables or disables the Cancel button (it fades out while disabled).</summary>
	public void SetCancelEnabled(bool enabled)
	{
		_cancelButton.Disabled = !enabled;
		_cancelButton.Modulate = new Color(1f, 1f, 1f, enabled ? 1f : 0.35f);
	}

	/// <summary>Appends a line to the combat log.</summary>
	public void Log(string line)
	{
		_log.AddLine(line);
	}

	/// <summary>Clears the combat log.</summary>
	public void ClearLog()
	{
		_log.Clear();
	}

	/// <summary>Shows the victory/defeat screen for the given player index (0 = you, 1 = AI).</summary>
	public void ShowWinScreen(int winner)
	{
		Draft.HidePopup();
		bool victory = winner == HumanPlayer;
		Sfx.Play(victory ? SfxId.Victory : SfxId.Defeat);
		string subtitle = winner == HumanPlayer ? "You reached the victory points target!"
			: (winner == AiPlayer ? "The AI reached the victory points target." : "Game over");
		_victoryBanner.Present(victory, victory ? "VICTORY" : "DEFEAT", subtitle);
		_winScreen.Visible = true;
		_winTween?.Kill();
		_winScreen.Modulate = new Color(1f, 1f, 1f, 0f);
		_winTween = CreateTween();
		_winTween.TweenProperty(_winScreen, "modulate:a", 1f, 0.35f);
		_winDim.Color = victory ? new Color(0.05f, 0.03f, 0f, 0.7f) : new Color(0f, 0f, 0f, 0.78f);
	}

	/// <summary>Hides the win overlay (e.g. after a restart).</summary>
	public void HideWinScreen()
	{
		_winTween?.Kill();
		_winScreen.Visible = false;
	}

	private void UpdateVp(int player, int vp, int target, bool animate)
	{
		VictoryCoinStack coins = player == HumanPlayer ? _playerCoins : _aiCoins;
		Label label = player == HumanPlayer ? _playerVpLabel : _aiVpLabel;
		coins.SetPoints(vp, animate && _lastVp[player] >= 0);
		label.Text = $"{vp} / {target}";
		if (animate && _lastVp[player] >= 0 && vp != _lastVp[player])
		{
			label.PivotOffset = label.Size * 0.5f;
			label.Scale = new Vector2(1.35f, 1.35f);
			Tween tween = label.CreateTween();
			tween.TweenProperty(label, "scale", Vector2.One, 0.35f).SetTrans(Tween.TransitionType.Back).SetEase(Tween.EaseType.Out);
		}
		_lastVp[player] = vp;
	}

	private static string PhaseCaption(GameState state)
	{
		bool human = state.CurrentPlayerIndex == HumanPlayer;
		return state.Phase switch
		{
			GamePhase.Draft => human ? "Choose a card" : "AI drafts",
			GamePhase.Main => human ? "Your move" : "AI is planning",
			GamePhase.Resolving => "Resolving orders",
			GamePhase.GameOver => "Game over",
			_ => "",
		};
	}

	private void ApplyScale()
	{
		if (_root == null)
		{
			return;
		}
		Vector2 viewport = GetViewport().GetVisibleRect().Size;
		Vector2 reference = new Vector2(Mathf.Max(1f, ReferenceResolution.X), Mathf.Max(1f, ReferenceResolution.Y));
		float scale = Mathf.Max(MinScale, Mathf.Min(viewport.X / reference.X, viewport.Y / reference.Y));
		UiScale = scale;
		_root.Position = Vector2.Zero;
		_root.Scale = new Vector2(scale, scale);
		_root.Size = viewport / scale;
	}

	private void ApplyStyles()
	{
		var topBar = GetNode<Panel>("Root/TopBar");
		StyleBoxFlat bar = HudStyle.Box(new Color(HudStyle.WoodDark, 0.92f), HudStyle.GoldDark, 0, 0, 10, 0.55f);
		bar.BorderWidthBottom = 3;
		bar.BorderColor = HudStyle.GoldDark;
		topBar.AddThemeStyleboxOverride("panel", bar);

		_hintRibbon.AddThemeStyleboxOverride("panel", HudStyle.ParchmentPanel(20, 5));
		_hintLabel.AddThemeColorOverride("font_color", HudStyle.Ink);
		_hintLabel.AddThemeConstantOverride("outline_size", 0);
		_hintLabel.AddThemeFontSizeOverride("font_size", 15);

		StyleBoxFlat toast = HudStyle.ParchmentPanel(26, 8);
		toast.BorderColor = new Color(0.6f, 0.2f, 0.08f);
		toast.SetBorderWidthAll(3);
		_toast.AddThemeStyleboxOverride("panel", toast);
		_messageLabel.AddThemeColorOverride("font_color", new Color(0.45f, 0.1f, 0.04f));
		_messageLabel.AddThemeConstantOverride("outline_size", 0);
		_messageLabel.AddThemeFontSizeOverride("font_size", 18);

		StyleBoxFlat ticker = HudStyle.Box(new Color(0.1f, 0.06f, 0.03f, 0.92f), HudStyle.Gold, 14, 2, 8);
		ticker.ContentMarginLeft = 16;
		ticker.ContentMarginRight = 16;
		ticker.ContentMarginTop = 3;
		ticker.ContentMarginBottom = 3;
		_ticker.AddThemeStyleboxOverride("panel", ticker);
		_tickerLabel.AddThemeColorOverride("font_color", HudStyle.Gold);
		_tickerLabel.AddThemeFontSizeOverride("font_size", 15);
		_tickerLabel.AddThemeConstantOverride("outline_size", 4);

		GetNode<PanelContainer>("Root/AiPanel").AddThemeStyleboxOverride("panel", HudStyle.WoodPanel(HudStyle.EnemyRed, 8));
		GetNode<PanelContainer>("Root/PlayerPanel").AddThemeStyleboxOverride("panel", HudStyle.WoodPanel(HudStyle.PlayerBlue, 8));
		GetNode<PanelContainer>("Root/ManaPanel").AddThemeStyleboxOverride("panel", HudStyle.WoodPanel(HudStyle.ManaBlue, 6));
		StyleHeader(GetNode<Label>("Root/AiPanel/VBox/Header/NameLabel"), HudStyle.EnemyRed);
		StyleHeader(GetNode<Label>("Root/PlayerPanel/VBox/Header/NameLabel"), HudStyle.PlayerBlue);
		StyleVp(_aiVpLabel);
		StyleVp(_playerVpLabel);

		_viewButton.AddThemeFontSizeOverride("font_size", 14);
		_cancelButton.AddThemeFontSizeOverride("font_size", 14);
		_restartButton.AddThemeFontSizeOverride("font_size", 20);
	}

	private static void StyleHeader(Label label, Color accent)
	{
		label.AddThemeColorOverride("font_color", accent.Lerp(Colors.White, 0.25f));
		label.AddThemeFontSizeOverride("font_size", 16);
		label.AddThemeConstantOverride("outline_size", 5);
	}

	private static void StyleVp(Label label)
	{
		label.AddThemeColorOverride("font_color", HudStyle.Gold);
		label.AddThemeFontSizeOverride("font_size", 18);
		label.AddThemeConstantOverride("outline_size", 5);
		label.HorizontalAlignment = HorizontalAlignment.Right;
	}
}
