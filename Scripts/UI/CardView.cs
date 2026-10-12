using System.Collections.Generic;
using System.Threading.Tasks;
using Godot;

namespace Realmshatter;

/// <summary>
/// Printed tabletop card (root of Scenes/UI/Card.tscn): the artwork fills the whole face (CardData.Art, or a
/// procedural painting while a card has no picture yet) inside a thin clan-coloured card-stock border. A printed
/// overlay (card_overlay.gdshader) adds the name bar, a rules panel (only when the card has rules text) and the
/// type plate at the bottom, whose outline shows the kind of card: notched ribbon = unit, pill = spell, pointed
/// hexagon = area spell, octagon = totem (Planted). Attack / health badges sit in the bottom corners, the shield
/// badge stacks above the health badge. The flavour description is only shown in the info panel.
/// Playable cards glow green, selected cards glow gold and lift. The root Control receives the mouse; the inner
/// "Body" animates.
/// </summary>
public partial class CardView : Control
{
	[Signal] public delegate void CardClickedEventHandler(CardView card);

	/// <summary>Emitted when the mouse enters (true) or leaves (false) the card.</summary>
	[Signal] public delegate void HoverChangedEventHandler(CardView card, bool hovered);

	private const float HoverRaise = 10f;
	private const float SelectedRaise = 22f;
	private const float TweenTime = 0.1f;
	private const int DescriptionMaxFont = 12;
	private const int DescriptionMinFont = 9;
	private const int NameMaxFont = 15;
	private const int StatsMaxFont = 11;
	/// <summary>Rules panel (x, y, w, h) drawn by card_overlay.gdshader; holds the rules text.</summary>
	private static readonly Vector4 TextRect = new Vector4(10f, 124f, 130f, 44f);
	/// <summary>Name bar (x, y, w, h) drawn by card_overlay.gdshader.</summary>
	private static readonly Vector4 NameRect = new Vector4(5f, 5f, 140f, 25f);
	/// <summary>Type plate (x, y, w, h) at the bottom; its outline depends on the card kind.</summary>
	private static readonly Vector4 PlateRect = new Vector4(38f, 186f, 74f, 20f);
	/// <summary>Painting centre offset (pixels, y down) so the subject sits above the rules panel.</summary>
	private static readonly Vector2 ArtFocusWithText = new Vector2(0f, -34f);
	private static readonly Vector2 ArtFocusNoText = new Vector2(0f, -16f);

	private static readonly Color UnitBannerColor = new Color(0.78f, 0.6f, 0.36f);
	/// <summary>Card colour of neutral (clan-less) cards: near-black card stock.</summary>
	private static readonly Color NeutralCardColor = new Color(0.14f, 0.13f, 0.125f);
	private static readonly Color RulesInk = new Color(0.16f, 0.1f, 0.05f);
	/// <summary>Every icon in the rules panel has the same size, however many there are.</summary>
	private const float RuleIconSize = 21f;
	private const int RuleFontSize = 12;
	private const float RuleIconGap = 2f;
	private const float RuleHGap = 5f;
	private const float RuleVGap = 1f;
	private const float RuleMinScale = 0.6f;
	private static readonly Color PlayableGlowColor = new Color(0.3f, 1f, 0.38f);
	private static readonly Color SelectedGlowColor = new Color(1f, 0.82f, 0.25f);
	private static readonly Color HoverGlowColor = new Color(1f, 0.9f, 0.6f);

	private Control _body;
	private Panel _glow;
	private ColorRect _frame;
	private ColorRect _art;
	private ColorRect _banner;
	private ColorRect _typePlate;
	private ColorRect _gem;
	private ColorRect _apBadge;
	private ColorRect _shieldBadge;
	private ColorRect _attackBadge;
	private ColorRect _healthBadge;
	private Label _nameLabel;
	private Label _statsLabel;
	private Label _descriptionLabel;
	private Label _typeLabel;
	private Label _costLabel;
	private Label _apLabel;
	private Label _shieldLabel;
	private Label _attackLabel;
	private Label _healthLabel;
	private RichTextLabel _richDescription;
	private VBoxContainer _rulesBox;
	private HFlowContainer _rulesFlow;
	private List<RuleItem> _ruleItems = new List<RuleItem>();
	private ShaderMaterial _frameMat;
	private ShaderMaterial _artMat;
	private ShaderMaterial _bannerMat;
	private ShaderMaterial _plateMat;
	private ShaderMaterial _overlayMat;
	private ColorRect _overlay;
	private StyleBoxFlat _glowStyle;
	private Tween _raiseTween;
	private Tween _revealTween;
	private readonly List<CanvasItem> _faceItems = new List<CanvasItem>();

	private int _apCost;
	private bool _playable = true;
	private bool _selected;
	private bool _hovered;
	private bool _revealing;
	private float _time;
	private float _revealGlow;

	/// <summary>The card currently shown by this view (null before Setup).</summary>
	public CardData Card { get; private set; }

	/// <summary>When true (set by HandView) the card does not raise/scale itself on hover or selection.</summary>
	public bool ManagedLayout { get; set; }

	/// <summary>True while the mouse is over the card.</summary>
	public bool IsHovered => _hovered;

	/// <summary>True if the card is shown as playable.</summary>
	public bool IsPlayable => _playable;

	/// <summary>True if the card is shown as selected.</summary>
	public bool IsSelected => _selected;

	/// <summary>Effective AP cost shown in the mana gem.</summary>
	public int ApCost => _apCost;

	public override void _Ready()
	{
		_body = GetNode<Control>("Body");
		_glow = GetNode<Panel>("Body/Glow");
		_frame = GetNode<ColorRect>("Body/Frame");
		_art = GetNode<ColorRect>("Body/Art");
		_banner = GetNode<ColorRect>("Body/Banner");
		_typePlate = GetNode<ColorRect>("Body/TypePlate");
		_gem = GetNode<ColorRect>("Body/Gem");
		_apBadge = GetNode<ColorRect>("Body/ApBadge");
		_shieldBadge = GetNode<ColorRect>("Body/ShieldBadge");
		_attackBadge = GetNode<ColorRect>("Body/AttackBadge");
		_healthBadge = GetNode<ColorRect>("Body/HealthBadge");
		_nameLabel = GetNode<Label>("Body/NameLabel");
		_statsLabel = GetNode<Label>("Body/StatsLabel");
		_descriptionLabel = GetNode<Label>("Body/DescriptionLabel");
		_typeLabel = GetNode<Label>("Body/TypeLabel");
		_costLabel = GetNode<Label>("Body/CostLabel");
		_apLabel = GetNode<Label>("Body/ApLabel");
		_shieldLabel = GetNode<Label>("Body/ShieldLabel");
		_attackLabel = GetNode<Label>("Body/AttackLabel");
		_healthLabel = GetNode<Label>("Body/HealthLabel");

		ApplySharpFonts();

		_frameMat = new ShaderMaterial { Shader = VfxAssets.GetShader("card_frame") };
		_frameMat.SetShaderParameter("card_size", Size.X > 0 ? Size : new Vector2(150, 210));
		_frame.Material = _frameMat;
		_artMat = new ShaderMaterial { Shader = VfxAssets.GetShader("card_art") };
		_artMat.SetShaderParameter("rect_size", _art.Size);
		_artMat.SetShaderParameter("frame_shape", 2);
		_art.Material = _artMat;
		_overlayMat = new ShaderMaterial { Shader = VfxAssets.GetShader("card_overlay") };
		_overlayMat.SetShaderParameter("card_size", Size.X > 0 ? Size : new Vector2(150, 210));
		_overlayMat.SetShaderParameter("name_rect", NameRect);
		_overlayMat.SetShaderParameter("text_rect", TextRect);
		_overlayMat.SetShaderParameter("plate_rect", PlateRect);
		_overlay = new ColorRect { Name = "Overlay", MouseFilter = MouseFilterEnum.Ignore, Material = _overlayMat };
		_overlay.SetAnchorsPreset(LayoutPreset.FullRect);
		_body.AddChild(_overlay);
		_body.MoveChild(_overlay, _art.GetIndex() + 1);
		// Drawn by the overlay now; the old ribbon / plate nodes and the stats line stay hidden.
		_banner.Visible = false;
		_typePlate.Visible = false;
		_statsLabel.Visible = false;
		_bannerMat = CreateBadgeMaterial(_banner, 4, UnitBannerColor);
		_plateMat = CreateBadgeMaterial(_typePlate, 5, new Color(0.42f, 0.36f, 0.3f));
		CreateBadgeMaterial(_gem, 3, new Color(0.22f, 0.5f, 1f));
		CreateBadgeMaterial(_apBadge, 6, new Color(0.2f, 0.65f, 0.25f));
		CreateBadgeMaterial(_shieldBadge, 2, new Color(0.78f, 0.8f, 0.86f));
		CreateBadgeMaterial(_attackBadge, 0, new Color(1f, 0.78f, 0.18f));
		CreateBadgeMaterial(_healthBadge, 1, new Color(0.92f, 0.13f, 0.1f));

		_glowStyle = new StyleBoxFlat
		{
			DrawCenter = false,
			BgColor = new Color(0, 0, 0, 0),
			BorderColor = PlayableGlowColor,
			ShadowColor = new Color(PlayableGlowColor, 0.85f),
			ShadowSize = 14,
			CornerDetail = 8,
			AntiAliasing = true,
		};
		_glowStyle.SetCornerRadiusAll(14);
		_glowStyle.SetBorderWidthAll(3);
		_glowStyle.SetExpandMarginAll(3);
		_glow.AddThemeStyleboxOverride("panel", _glowStyle);
		CreateKeywordNodes();

		foreach (Node child in _body.GetChildren())
		{
			if (child is CanvasItem item && child != _glow && child != _frame && child != _banner && child != _typePlate && child != _statsLabel)
			{
				_faceItems.Add(item);
			}
		}

		MouseFilter = MouseFilterEnum.Stop;
		MouseEntered += OnMouseEntered;
		MouseExited += OnMouseExited;

		Refresh();
	}

	public override void _Process(double delta)
	{
		_time += (float)delta;
		if (_glow == null)
		{
			return;
		}
		Color color;
		float strength;
		if (_selected)
		{
			color = SelectedGlowColor;
			strength = 0.85f + 0.15f * Mathf.Sin(_time * 5f);
		}
		else if (_playable)
		{
			color = PlayableGlowColor;
			strength = 0.6f + 0.25f * Mathf.Sin(_time * 3f);
		}
		else if (_hovered && !ManagedLayout)
		{
			color = HoverGlowColor;
			strength = 0.6f;
		}
		else
		{
			color = HoverGlowColor;
			strength = 0f;
		}
		if (_revealGlow > 0f)
		{
			color = color.Lerp(new Color(1f, 0.9f, 0.55f), _revealGlow);
			strength = Mathf.Max(strength, _revealGlow);
		}
		_glow.Visible = strength > 0.01f;
		if (_glow.Visible)
		{
			_glowStyle.BorderColor = new Color(color, Mathf.Clamp(strength, 0f, 1f));
			_glowStyle.ShadowColor = new Color(color, Mathf.Clamp(strength * 0.8f, 0f, 1f));
			_glowStyle.ShadowSize = (int)(10 + 10 * strength);
		}
	}

	/// <summary>Shows the given card with its effective AP cost.</summary>
	public void Setup(CardData card, int apCost)
	{
		Card = card;
		_apCost = apCost;
		if (IsNodeReady())
		{
			Refresh();
		}
	}

	/// <summary>Playable cards glow green; unplayable cards are slightly dimmed.</summary>
	public void SetPlayable(bool playable)
	{
		_playable = playable;
		Modulate = playable ? Colors.White : new Color(0.78f, 0.76f, 0.74f, 1f);
	}

	/// <summary>Highlights (gold glow) and, unless ManagedLayout, raises the card while it is selected.</summary>
	public void SetSelected(bool selected)
	{
		_selected = selected;
		if (IsNodeReady())
		{
			UpdateRaise();
		}
	}

	/// <summary>Dramatic reveal: fades in as a card back, flips to the face and flashes gold.</summary>
	public async Task PlayReveal(float delay)
	{
		if (!IsNodeReady())
		{
			return;
		}
		_revealing = true;
		_raiseTween?.Kill();
		_revealTween?.Kill();
		SetShowBack(true);
		_body.Position = new Vector2(0, -40f);
		_body.Scale = new Vector2(0.5f, 0.5f);
		_body.Modulate = new Color(1, 1, 1, 0);
		_body.Rotation = Mathf.DegToRad(-8f);

		_revealTween = CreateTween();
		_revealTween.TweenInterval(delay);
		_revealTween.SetParallel(true);
		_revealTween.TweenProperty(_body, "modulate:a", 1f, 0.15f);
		_revealTween.TweenProperty(_body, "scale", Vector2.One, 0.22f).SetTrans(Tween.TransitionType.Back).SetEase(Tween.EaseType.Out);
		_revealTween.TweenProperty(_body, "position:y", 0f, 0.22f).SetTrans(Tween.TransitionType.Back).SetEase(Tween.EaseType.Out);
		_revealTween.TweenProperty(_body, "rotation", 0f, 0.22f);
		_revealTween.Chain().TweenProperty(_body, "scale:x", 0f, 0.09f).SetTrans(Tween.TransitionType.Sine).SetEase(Tween.EaseType.In);
		_revealTween.Chain().TweenCallback(Callable.From(() =>
		{
			SetShowBack(false);
			_revealGlow = 1f;
			Sfx.Play(SfxId.CardFlip);
		}));
		_revealTween.Chain().TweenProperty(_body, "scale", new Vector2(1.1f, 1.1f), 0.12f).SetTrans(Tween.TransitionType.Back).SetEase(Tween.EaseType.Out);
		_revealTween.Chain().TweenProperty(_body, "scale", Vector2.One, 0.1f);
		_revealTween.Parallel().TweenMethod(Callable.From<float>(v => _revealGlow = v), 1f, 0f, 0.6f);
		await ToSignal(_revealTween, Tween.SignalName.Finished);
		_revealing = false;
		_revealGlow = 0f;
		UpdateRaise();
	}

	public override void _GuiInput(InputEvent @event)
	{
		if (@event is InputEventMouseButton mouse && mouse.Pressed && mouse.ButtonIndex == MouseButton.Left)
		{
			AcceptEvent();
			EmitSignal(SignalName.CardClicked, this);
		}
	}

	private void OnMouseEntered()
	{
		_hovered = true;
		if (!ManagedLayout)
		{
			ZIndex = 1;
			UpdateRaise();
		}
		EmitSignal(SignalName.HoverChanged, this, true);
	}

	private void OnMouseExited()
	{
		_hovered = false;
		if (!ManagedLayout)
		{
			ZIndex = 0;
			UpdateRaise();
		}
		EmitSignal(SignalName.HoverChanged, this, false);
	}

	private void SetShowBack(bool back)
	{
		_frameMat.SetShaderParameter("show_back", back);
		foreach (CanvasItem item in _faceItems)
		{
			item.Visible = !back;
		}
		if (!back)
		{
			Refresh();
		}
	}

	private void Refresh()
	{
		SetPlayable(_playable);
		UpdateRaise();

		if (Card == null)
		{
			_nameLabel.Text = "";
			_costLabel.Text = "";
			_typeLabel.Text = "";
			_statsLabel.Text = "";
			_descriptionLabel.Text = "";
			_richDescription.Text = "";
			TooltipText = "";
			_rulesBox.Visible = false;
			_artMat.SetShaderParameter("has_art", false);
			return;
		}

		bool unit = Card.CardType == CardType.Unit;
		bool planted = unit && Card.HasKeyword(Keyword.Planted);
		Color tint = new Color(Card.Tint.R, Card.Tint.G, Card.Tint.B);
		Color clan = Card.Clan == Clan.None ? NeutralCardColor : ClanInfo.GetColor(Card.Clan);
		// Legendary cards get a gold card stock border.
		_frameMat.SetShaderParameter("frame_color", Card.Rarity == CardRarity.Legendary ? new Color(0.95f, 0.72f, 0.3f) : clan.Darkened(0.12f));

		// Artwork: a real picture (CardData.Art) fills the face; without one the procedural painting stands in.
		_artMat.SetShaderParameter("has_art", Card.Art != null);
		if (Card.Art != null)
		{
			_artMat.SetShaderParameter("art_texture", Card.Art);
		}
		_artMat.SetShaderParameter("tint", tint);
		_artMat.SetShaderParameter("emblem", unit ? RoleEmblem(Card.Role) : (SpellIsPositive(Card) ? 3 : 4));
		_artMat.SetShaderParameter("glyph", ClassVisuals.ArtGlyph(Card));
		_artMat.SetShaderParameter("animate", Card.Rarity != CardRarity.Common);
		_artMat.SetShaderParameter("seed", (Mathf.Abs((Card.Name ?? "").GetHashCode()) % 1000) * 0.01f);

		// Rules panel: icons (keywords, triggers, stat changes, statuses, tile effects) with short values.
		_ruleItems = unit ? UnitRuleItems(Card) : SpellRuleItems(Card);
		int ruleItems = _ruleItems.Count;
		_rulesBox.Visible = ruleItems > 0;
		bool hasText = ruleItems > 0;
		_artMat.SetShaderParameter("focus", hasText ? ArtFocusWithText : ArtFocusNoText);
		_overlayMat.SetShaderParameter("has_text", hasText);
		_overlayMat.SetShaderParameter("clan_color", clan);
		_overlayMat.SetShaderParameter("rarity_color", CardEconomy.RarityColor(Card.Rarity));
		_overlayMat.SetShaderParameter("plate_shape", unit ? (planted ? 3 : 0) : (Card.TargetsTile ? 2 : 1));

		_nameLabel.Text = string.IsNullOrEmpty(Card.Name) ? "(unnamed)" : Card.Name;
		_costLabel.Text = _apCost.ToString();
		_typeLabel.Text = unit ? ClassInfo.ClassOrRole(Card) : (Card.TargetsTile ? "Area Spell" : "Spell");
		FitLabel(_typeLabel, 10, 7);
		FitLabel(_nameLabel, NameMaxFont, 8);
		_descriptionLabel.Text = "";
		_richDescription.Text = "";
		_richDescription.Visible = false;
		// Full rules are shown by the HUD's card info panel instead of a delayed native tooltip.
		TooltipText = "";

		_attackBadge.Visible = unit;
		_attackLabel.Visible = unit;
		_healthBadge.Visible = unit;
		_healthLabel.Visible = unit;
		_attackLabel.Text = Card.Attack.ToString();
		_healthLabel.Text = Card.Hp.ToString();
		bool shield = unit && Card.Shield > 0;
		_shieldBadge.Visible = shield;
		_shieldLabel.Visible = shield;
		_shieldLabel.Text = Card.Shield.ToString();
		LayoutDescription(shield);
		bool ap = unit && Card.ApBonus != 0;
		_apBadge.Visible = ap;
		_apLabel.Visible = ap;
		_apLabel.Text = FormatDelta(Card.ApBonus);
	}

	// ------------------------------------------------------------------ keywords

	/// <summary>All card labels use the MSDF serif so they stay crisp at every hand / hover / HUD scale.</summary>
	private void ApplySharpFonts()
	{
		foreach (Node child in _body.GetChildren())
		{
			if (child is Label label)
			{
				label.AddThemeFontOverride("font", VfxAssets.CardTextBoldFont);
			}
		}
		// Badge numbers: lining figures, centred in their badge (label box = badge box, ink centred via margins).
		var pairs = new (Label Number, ColorRect Badge)[]
		{
			(_costLabel, _gem), (_attackLabel, _attackBadge), (_healthLabel, _healthBadge), (_shieldLabel, _shieldBadge), (_apLabel, _apBadge),
		};
		foreach ((Label number, ColorRect badge) in pairs)
		{
			number.AddThemeFontOverride("font", VfxAssets.NumberFont);
			number.VerticalAlignment = VerticalAlignment.Center;
			number.HorizontalAlignment = HorizontalAlignment.Center;
			number.Position = badge.Position;
			number.Size = badge.Size;
			float drop = VfxAssets.DigitDrop(number.GetThemeFontSize("font_size"));
			number.AddThemeStyleboxOverride("normal", new StyleBoxEmpty
			{
				ContentMarginTop = Mathf.Max(0f, -drop * 2f),
				ContentMarginBottom = Mathf.Max(0f, drop * 2f),
			});
		}
	}

	/// <summary>Shrinks a single-line label's font until the text fits its width.</summary>
	private static void FitLabel(Label label, int maxSize, int minSize)
	{
		Font font = VfxAssets.CardTextBoldFont;
		float width = label.Size.X - 4f;
		int size = maxSize;
		while (size > minSize && font.GetStringSize(label.Text, HorizontalAlignment.Left, -1, size).X > width)
		{
			size--;
		}
		label.AddThemeFontSizeOverride("font_size", size);
	}

	/// <summary>
	/// Places the rules text inside the rules panel (leaving room on the right for the shield badge, which overlaps
	/// the panel's corner) and picks the largest font size at which the whole text fits; the rule icons are built
	/// at the largest scale at which all their rows fit the panel.
	/// </summary>
	private void LayoutDescription(bool shield)
	{
		Vector2 pos = _descriptionLabel.Position;
		Vector2 size = _descriptionLabel.Size;
		if (shield)
		{
			size.X -= 18f;
		}
		_richDescription.Position = pos;
		_richDescription.Size = size;
		// The icon box keeps clear of the shield badge, which overlaps the panel's right corner.
		_rulesBox.Position = new Vector2(TextRect.X + 3f, TextRect.Y + 2f);
		_rulesBox.Size = new Vector2(TextRect.Z - 6f - (shield ? 20f : 0f), TextRect.W - 4f);
		BuildRuleIcons(_ruleItems, FitRuleScale(_ruleItems, _rulesBox.Size));
		for (int fontSize = DescriptionMaxFont; fontSize >= DescriptionMinFont; fontSize--)
		{
			_richDescription.AddThemeFontSizeOverride("normal_font_size", fontSize);
			_richDescription.AddThemeFontSizeOverride("bold_font_size", fontSize);
			if (_richDescription.GetContentHeight() <= size.Y)
			{
				break;
			}
		}
	}

	private void CreateKeywordNodes()
	{
		_richDescription = new RichTextLabel
		{
			Name = "RichDescription",
			BbcodeEnabled = true,
			ScrollActive = false,
			FitContent = false,
			ClipContents = true,
			AutowrapMode = TextServer.AutowrapMode.WordSmart,
			VerticalAlignment = VerticalAlignment.Center,
			MouseFilter = MouseFilterEnum.Ignore,
			Position = _descriptionLabel.Position,
			Size = _descriptionLabel.Size,
		};
		_richDescription.AddThemeFontOverride("normal_font", VfxAssets.CardTextFont);
		_richDescription.AddThemeFontOverride("bold_font", VfxAssets.CardTextBoldFont);
		_richDescription.AddThemeFontSizeOverride("normal_font_size", DescriptionMaxFont);
		_richDescription.AddThemeFontSizeOverride("bold_font_size", DescriptionMaxFont);
		_richDescription.AddThemeColorOverride("default_color", new Color(0.13f, 0.08f, 0.03f));
		_richDescription.AddThemeConstantOverride("outline_size", 0);
		_richDescription.AddThemeConstantOverride("line_separation", 0);
		_body.AddChild(_richDescription);
		_body.MoveChild(_richDescription, _descriptionLabel.GetIndex() + 1);

		_rulesBox = new VBoxContainer
		{
			Name = "RulesBox",
			MouseFilter = MouseFilterEnum.Ignore,
			Alignment = BoxContainer.AlignmentMode.Center,
			Position = new Vector2(TextRect.X + 3f, TextRect.Y + 2f),
			Size = new Vector2(TextRect.Z - 6f, TextRect.W - 4f),
			Visible = false,
		};
		_rulesFlow = new HFlowContainer
		{
			Name = "RulesFlow",
			MouseFilter = MouseFilterEnum.Ignore,
			Alignment = FlowContainer.AlignmentMode.Center,
			SizeFlagsHorizontal = SizeFlags.ExpandFill,
		};
		_rulesFlow.AddThemeConstantOverride("h_separation", (int)RuleHGap);
		_rulesFlow.AddThemeConstantOverride("v_separation", (int)RuleVGap);
		_rulesBox.AddChild(_rulesFlow);
		_body.AddChild(_rulesBox);
		_body.MoveChild(_rulesBox, _richDescription.GetIndex() + 1);
	}

	/// <summary>
	/// One entry of the rules panel: a keyword emblem (Glyph = FxIconShape) or a card badge (Badge = card_badge shape:
	/// 0 attack, 1 health, 2 shield), its colours, an optional value / name next to it and an optional small overlay
	/// (Undying level). Glyph and Badge both -1 = plain text.
	/// </summary>
	private readonly record struct RuleItem(int Glyph, int Badge, Color Fg, Color Bg, string Label, string Overlay = "");

	private static RuleItem Emblem(FxIconShape shape, Color fg, Color bg, string label = "") => new RuleItem((int)shape, -1, fg, bg, label);
	private static RuleItem StatBadge(int badge, Color fill, string label) => new RuleItem(-1, badge, fill, fill, label);

	private static readonly Color AttackFill = new Color(1f, 0.66f, 0.2f);
	private static readonly Color HealthFill = new Color(0.86f, 0.12f, 0.1f);
	private static readonly Color ShieldFill = new Color(0.78f, 0.8f, 0.86f);

	/// <summary>Unit rules: one emblem per keyword (the icon replaces the name; Builder adds its building, Undying its level), then triggers.</summary>
	private static List<RuleItem> UnitRuleItems(CardData card)
	{
		var items = new List<RuleItem>();
		foreach (Keyword k in KeywordInfo.Split(card.Keywords))
		{
			Color fg = KeywordVisuals.GetForeground(k);
			Color bg = KeywordVisuals.GetBackground(k);
			if (k == Keyword.Aura)
			{
				fg = ClanInfo.GetColor(card.Clan).Lightened(0.35f);
				bg = ClanInfo.GetColor(card.Clan).Darkened(0.65f);
			}
			string label = k == Keyword.Builder && BuildingInfo.ForClass(card.Class) != BuildingType.None
				? BuildingInfo.GetName(BuildingInfo.ForClass(card.Class))
				: (k == Keyword.Trapper ? TrapInfo.GetName(TrapInfo.ForClan(card.Clan)) : "");
			string overlay = k == Keyword.Undying && card.Level > 0 ? $"+{card.Level}" : "";
			items.Add(new RuleItem((int)KeywordVisuals.GetShape(k), -1, fg, bg, label, overlay));
		}
		if (card.Legend != LegendEffect.None)
		{
			items.Add(Emblem(LegendInfo.GetShape(card.Legend), LegendInfo.GetColor(card.Legend), LegendInfo.EmblemBackground, LegendInfo.GetName(card.Legend)));
		}
		foreach (string line in TriggerInfo.CardFaceLines(card))
		{
			int colon = line.IndexOf(':');
			string head = colon >= 0 ? line[..colon] : line;
			string effect = colon >= 0 ? line[(colon + 1)..].Trim() : "";
			if (head == "First hit")
			{
				items.Add(Emblem(FxIconShape.Burst, new Color(1f, 0.82f, 0.45f), new Color(0.45f, 0.16f, 0.08f, 0.97f), effect));
			}
			else if (head == "Deathrattle")
			{
				items.Add(Emblem(FxIconShape.Tomb, new Color(0.85f, 0.85f, 0.95f), new Color(0.18f, 0.16f, 0.26f, 0.97f), effect));
			}
		}
		return items;
	}

	/// <summary>Spell rules: area (text), damage / heal / push, tile effect with its duration, stat changes, status, AP.</summary>
	private static List<RuleItem> SpellRuleItems(CardData card)
	{
		var items = new List<RuleItem>();
		if (card.TargetsTile)
		{
			items.Add(new RuleItem(-1, -1, RulesInk, RulesInk, AreaName(card.SpellTarget == SpellTargetType.Tile ? AreaShape.Single : card.AreaShape)));
			if (card.SpellDamage > 0)
			{
				items.Add(Emblem(FxIconShape.Burst, new Color(1f, 0.75f, 0.4f), new Color(0.5f, 0.1f, 0.06f, 0.97f), card.SpellDamage.ToString()));
			}
			if (card.SpellHeal > 0)
			{
				items.Add(StatBadge(1, HealthFill, $"+{card.SpellHeal}"));
			}
			if (card.SpellPush)
			{
				items.Add(Emblem(FxIconShape.Fist, KeywordVisuals.GetForeground(Keyword.Push), KeywordVisuals.GetBackground(Keyword.Push)));
			}
			if (card.TileEffect != TileEffectType.None)
			{
				(FxIconShape shape, Color fg, Color bg) = card.TileEffect switch
				{
					TileEffectType.Lava => (FxIconShape.Flame, new Color(1f, 0.55f, 0.15f), new Color(0.42f, 0.1f, 0.03f, 0.97f)),
					TileEffectType.Healing => (FxIconShape.Plus, new Color(0.55f, 1f, 0.55f), new Color(0.1f, 0.38f, 0.14f, 0.97f)),
					_ => (FxIconShape.Bricks, new Color(0.88f, 0.82f, 0.72f), new Color(0.3f, 0.27f, 0.24f, 0.97f)),
				};
				items.Add(Emblem(shape, fg, bg, $"{card.TileEffectDuration}T"));
			}
		}
		else
		{
			AddStat(items, card.AttackDelta, 0, AttackFill);
			AddStat(items, card.HpDelta, 1, HealthFill);
			AddStat(items, card.ShieldDelta, 2, ShieldFill);
			if (card.MovementDelta != 0)
			{
				items.Add(Emblem(FxIconShape.Chevrons, new Color(0.75f, 1f, 0.7f), new Color(0.14f, 0.32f, 0.16f, 0.97f), FormatDelta(card.MovementDelta)));
			}
			if (card.RangeDelta != 0)
			{
				items.Add(Emblem(FxIconShape.Crosshair, new Color(1f, 0.88f, 0.65f), new Color(0.38f, 0.22f, 0.1f, 0.97f), FormatDelta(card.RangeDelta)));
			}
			if (card.GrantStatus == StatusEffectType.Frozen)
			{
				items.Add(Emblem(FxIconShape.Snowflake, KeywordVisuals.GetForeground(Keyword.Frost), KeywordVisuals.GetBackground(Keyword.Frost)));
			}
			else if (card.GrantStatus == StatusEffectType.Overcharged)
			{
				items.Add(Emblem(FxIconShape.Bolt, KeywordVisuals.GetForeground(Keyword.Arc), KeywordVisuals.GetBackground(Keyword.Arc), "x2"));
			}
		}
		if (card.ApGain > 0)
		{
			items.Add(Emblem(FxIconShape.Gem, KeywordVisuals.GetForeground(Keyword.Plunder), KeywordVisuals.GetBackground(Keyword.Plunder), $"+{card.ApGain}"));
		}
		return items;
	}

	private static void AddStat(List<RuleItem> items, int value, int badge, Color fill)
	{
		if (value != 0)
		{
			items.Add(StatBadge(badge, fill, FormatDelta(value)));
		}
	}

	/// <summary>
	/// Largest scale (1 = full size, down to RuleMinScale) at which the rule items, flowed into rows like the
	/// HFlowContainer does, fit the rules panel (long trigger names on legendaries / epics would overflow it).
	/// </summary>
	private static float FitRuleScale(List<RuleItem> items, Vector2 box)
	{
		Font font = VfxAssets.CardTextBoldFont;
		for (float scale = 1f; scale > RuleMinScale; scale -= 0.05f)
		{
			float icon = RuleIconSize * scale;
			int fontSize = Mathf.Max(7, Mathf.RoundToInt(RuleFontSize * scale));
			float rowHeight = Mathf.Max(icon, font.GetHeight(fontSize));
			int rows = 1;
			float x = 0f;
			foreach (RuleItem rule in items)
			{
				bool hasIcon = rule.Glyph >= 0 || rule.Badge >= 0;
				float w = (hasIcon ? icon : 0f) + (hasIcon && rule.Label.Length > 0 ? RuleIconGap : 0f)
					+ (rule.Label.Length > 0 ? font.GetStringSize(rule.Label, HorizontalAlignment.Left, -1, fontSize).X : 0f);
				if (x > 0f && x + RuleHGap + w > box.X)
				{
					rows++;
					x = w;
				}
				else
				{
					x += (x > 0f ? RuleHGap : 0f) + w;
				}
			}
			if (rows * rowHeight + (rows - 1) * RuleVGap <= box.Y)
			{
				return scale;
			}
		}
		return RuleMinScale;
	}

	/// <summary>Fills the rules panel with the given items (icon + value) at a size scale; returns their number (0 = no panel).</summary>
	private int BuildRuleIcons(List<RuleItem> items, float scale = 1f)
	{
		foreach (Node child in _rulesFlow.GetChildren())
		{
			_rulesFlow.RemoveChild(child);
			child.QueueFree();
		}
		float size = RuleIconSize * scale;
		int fontSize = Mathf.Max(7, Mathf.RoundToInt(RuleFontSize * scale));
		foreach (RuleItem rule in items)
		{
			var item = new HBoxContainer { MouseFilter = MouseFilterEnum.Ignore };
			item.AddThemeConstantOverride("separation", (int)RuleIconGap);
			if (rule.Glyph >= 0 || rule.Badge >= 0)
			{
				var icon = new ColorRect
				{
					CustomMinimumSize = new Vector2(size, size),
					Size = new Vector2(size, size),
					MouseFilter = MouseFilterEnum.Ignore,
					SizeFlagsVertical = SizeFlags.ShrinkCenter,
				};
				if (rule.Glyph >= 0)
				{
					var mat = new ShaderMaterial { Shader = VfxAssets.GetShader("keyword_icon") };
					mat.SetShaderParameter("shape", rule.Glyph);
					mat.SetShaderParameter("fg_color", rule.Fg);
					mat.SetShaderParameter("bg_color", rule.Bg);
					icon.Material = mat;
				}
				else
				{
					CreateBadgeMaterial(icon, rule.Badge, rule.Fg);
				}
				if (rule.Overlay.Length > 0)
				{
					var lv = new Label { Text = rule.Overlay, Position = new Vector2(size * 0.5f, size * 0.42f), MouseFilter = MouseFilterEnum.Ignore };
					lv.AddThemeFontOverride("font", VfxAssets.CardTextBoldFont);
					lv.AddThemeFontSizeOverride("font_size", 10);
					lv.AddThemeColorOverride("font_color", new Color(0.75f, 1f, 0.9f));
					lv.AddThemeColorOverride("font_outline_color", new Color(0.03f, 0.08f, 0.07f));
					lv.AddThemeConstantOverride("outline_size", 4);
					icon.AddChild(lv);
				}
				item.AddChild(icon);
			}
			if (rule.Label.Length > 0)
			{
				var text = new Label { Text = rule.Label, MouseFilter = MouseFilterEnum.Ignore, VerticalAlignment = VerticalAlignment.Center };
				text.AddThemeFontOverride("font", VfxAssets.CardTextBoldFont);
				text.AddThemeFontSizeOverride("font_size", fontSize);
				text.AddThemeColorOverride("font_color", RulesInk);
				text.AddThemeConstantOverride("outline_size", 0);
				item.AddChild(text);
			}
			_rulesFlow.AddChild(item);
		}
		return items.Count;
	}

	private static string AreaName(AreaShape shape) => shape switch
	{
		AreaShape.Plus => "Cross",
		AreaShape.Row3 => "Row 3",
		AreaShape.Column3 => "Col 3",
		AreaShape.Square2 => "2x2",
		_ => "1 tile",
	};

	private void UpdateRaise()
	{
		if (_body == null || _revealing)
		{
			return;
		}
		float targetY = 0f;
		float scale = 1f;
		if (!ManagedLayout)
		{
			targetY = _selected ? -SelectedRaise : (_hovered ? -HoverRaise : 0f);
			scale = _selected ? 1.06f : (_hovered ? 1.05f : 1f);
		}
		_raiseTween?.Kill();
		_raiseTween = CreateTween();
		_raiseTween.SetParallel(true);
		_raiseTween.TweenProperty(_body, "position:y", targetY, TweenTime);
		_raiseTween.TweenProperty(_body, "scale", new Vector2(scale, scale), TweenTime);
	}

	private static ShaderMaterial CreateBadgeMaterial(ColorRect rect, int shape, Color fill)
	{
		var mat = new ShaderMaterial { Shader = VfxAssets.GetShader("card_badge") };
		mat.SetShaderParameter("shape", shape);
		mat.SetShaderParameter("fill_color", fill);
		mat.SetShaderParameter("rect_size", rect.Size);
		rect.Material = mat;
		return mat;
	}

	private static int RoleEmblem(UnitRole role) => role switch
	{
		UnitRole.Attack => 0,
		UnitRole.Utility => 1,
		_ => 2,
	};

	private static bool SpellIsPositive(CardData card) =>
		card.AttackDelta + card.HpDelta + card.ShieldDelta + card.MovementDelta + card.RangeDelta >= 0;

	private static string FormatDelta(int value) => value > 0 ? $"+{value}" : value.ToString();
}
