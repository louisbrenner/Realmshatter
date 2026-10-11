using System.Collections.Generic;
using System.Threading.Tasks;
using Godot;

namespace ProjectClaude;

/// <summary>
/// Hearthstone-style card (root of Scenes/UI/Card.tscn): stone frame with gold trim, oval (unit) or
/// rounded (spell) art window, blue mana gem with the AP cost, name ribbon, parchment text box,
/// attack/health badges for units, shield and AP bonus mini badges. Playable cards glow green,
/// selected cards glow gold and lift. The root Control receives the mouse; the inner "Body" animates.
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
	/// <summary>Parchment text box (x, y, w, h) drawn by card_frame.gdshader; holds the stats line and the text.</summary>
	private static readonly Vector4 TextRect = new Vector4(11f, 106f, 128f, 80f);

	private static readonly Color UnitFrameColor = new Color(0.5f, 0.44f, 0.37f);
	private static readonly Color SpellFrameColor = new Color(0.38f, 0.34f, 0.54f);
	private static readonly Color UnitBannerColor = new Color(0.78f, 0.6f, 0.36f);
	private static readonly Color SpellBannerColor = new Color(0.6f, 0.5f, 0.82f);
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
	private HBoxContainer _keywordRow;
	private ShaderMaterial _frameMat;
	private ShaderMaterial _artMat;
	private ShaderMaterial _bannerMat;
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
		_frameMat.SetShaderParameter("art_rect", new Vector4(_art.Position.X, _art.Position.Y, _art.Size.X, _art.Size.Y));
		_frameMat.SetShaderParameter("text_rect", TextRect);
		_frame.Material = _frameMat;
		_artMat = new ShaderMaterial { Shader = VfxAssets.GetShader("card_art") };
		_artMat.SetShaderParameter("rect_size", _art.Size);
		_art.Material = _artMat;
		_bannerMat = CreateBadgeMaterial(_banner, 4, UnitBannerColor);
		CreateBadgeMaterial(_typePlate, 5, new Color(0.42f, 0.36f, 0.3f));
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
			if (child is CanvasItem item && child != _glow && child != _frame)
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
			_keywordRow.Visible = false;
			_artMat.SetShaderParameter("has_art", false);
			return;
		}

		bool unit = Card.CardType == CardType.Unit;
		Color tint = new Color(Card.Tint.R, Card.Tint.G, Card.Tint.B);
		_frameMat.SetShaderParameter("style", unit ? 0 : 1);
		_frameMat.SetShaderParameter("frame_color", unit ? UnitFrameColor : SpellFrameColor);
		_frameMat.SetShaderParameter("accent_color", tint);
		_bannerMat.SetShaderParameter("fill_color", unit ? UnitBannerColor : SpellBannerColor);

		_artMat.SetShaderParameter("has_art", Card.Art != null);
		if (Card.Art != null)
		{
			_artMat.SetShaderParameter("art_texture", Card.Art);
		}
		_artMat.SetShaderParameter("tint", tint);
		_artMat.SetShaderParameter("frame_shape", unit ? 0 : 1);
		_artMat.SetShaderParameter("emblem", unit ? RoleEmblem(Card.Role) : (SpellIsPositive(Card) ? 3 : 4));
		_artMat.SetShaderParameter("seed", (Mathf.Abs((Card.Name ?? "").GetHashCode()) % 1000) * 0.01f);

		_nameLabel.Text = string.IsNullOrEmpty(Card.Name) ? "(unnamed)" : Card.Name;
		_costLabel.Text = _apCost.ToString();
		_typeLabel.Text = unit ? Card.Role.ToString() : (Card.TargetsTile ? "Area Spell" : "Spell");
		_statsLabel.Text = unit ? $"Move {Card.Movement}  ·  Range {Card.Range}" : BuildSpellStats(Card);
		FitLabel(_nameLabel, NameMaxFont, 10);
		FitLabel(_statsLabel, StatsMaxFont, 8);
		_descriptionLabel.Text = "";
		_richDescription.Text = BuildDescriptionBbcode(Card);
		LayoutDescription(unit);
		BuildKeywordEmblems(Card);
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
		bool ap = unit && Card.ApBonus != 0;
		_apBadge.Visible = ap;
		_apLabel.Visible = ap;
		_apLabel.Text = FormatDelta(Card.ApBonus);
		_statsLabel.Modulate = Colors.White;
		if (!unit)
		{
			_statsLabel.Modulate = Card.TargetsTile ? TileEffectTextColor(Card.TileEffect)
				: (SpellIsPositive(Card) ? new Color(0.3f, 0.75f, 0.3f) : new Color(0.8f, 0.4f, 1f));
		}
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
	/// Places the card text inside the parchment box (narrower and shorter for units so the attack / health badges
	/// never cover it) and picks the largest font size at which the whole text fits.
	/// </summary>
	private void LayoutDescription(bool unit)
	{
		Vector2 pos = _descriptionLabel.Position;
		Vector2 size = _descriptionLabel.Size;
		if (unit)
		{
			pos.X += 4f;
			size.X -= 8f;
			size.Y -= 10f;
		}
		_richDescription.Position = pos;
		_richDescription.Size = size;
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

		_keywordRow = new HBoxContainer
		{
			Name = "KeywordRow",
			MouseFilter = MouseFilterEnum.Ignore,
			Alignment = BoxContainer.AlignmentMode.Center,
			Position = new Vector2(_art.Position.X, _art.Position.Y + _art.Size.Y - 32f),
			Size = new Vector2(_art.Size.X, 26f),
		};
		_keywordRow.AddThemeConstantOverride("separation", 2);
		_body.AddChild(_keywordRow);
		_body.MoveChild(_keywordRow, _banner.GetIndex());
	}

	private void BuildKeywordEmblems(CardData card)
	{
		foreach (Node child in _keywordRow.GetChildren())
		{
			_keywordRow.RemoveChild(child);
			child.QueueFree();
		}
		foreach (Keyword k in KeywordInfo.Split(card.Keywords))
		{
			var emblem = new ColorRect
			{
				CustomMinimumSize = new Vector2(26f, 26f),
				MouseFilter = MouseFilterEnum.Ignore,
				Material = CreateKeywordMaterial(k),
			};
			_keywordRow.AddChild(emblem);
			if (k == Keyword.Undying && card.Level > 0)
			{
				var lv = new Label
				{
					Text = $"+{card.Level}",
					Position = new Vector2(13f, 11f),
					MouseFilter = MouseFilterEnum.Ignore,
				};
				lv.AddThemeFontOverride("font", VfxAssets.CardTextBoldFont);
				lv.AddThemeFontSizeOverride("font_size", 11);
				lv.AddThemeColorOverride("font_color", new Color(0.75f, 1f, 0.9f));
				lv.AddThemeColorOverride("font_outline_color", new Color(0.03f, 0.08f, 0.07f));
				lv.AddThemeConstantOverride("outline_size", 4);
				emblem.AddChild(lv);
			}
		}
		_keywordRow.Visible = _keywordRow.GetChildCount() > 0 || card.Keywords != Keyword.None;
	}

	private static ShaderMaterial CreateKeywordMaterial(Keyword k)
	{
		var mat = new ShaderMaterial { Shader = VfxAssets.GetShader("keyword_icon") };
		mat.SetShaderParameter("shape", (int)KeywordVisuals.GetShape(k));
		mat.SetShaderParameter("fg_color", KeywordVisuals.GetForeground(k));
		mat.SetShaderParameter("bg_color", KeywordVisuals.GetBackground(k));
		return mat;
	}

	/// <summary>Description with bold keyword names first ("Burning. ..."), as BBCode.</summary>
	private static string BuildDescriptionBbcode(CardData card)
	{
		string text = card.Description ?? "";
		var heads = new List<string>();
		foreach (Keyword k in KeywordInfo.Split(card.Keywords))
		{
			string name = KeywordInfo.GetName(k);
			string trimmed = text.TrimStart();
			if (trimmed.StartsWith(name + ".") || trimmed.StartsWith(name + ":"))
			{
				text = trimmed.Substring(name.Length + 1).TrimStart();
			}
			heads.Add(k == Keyword.Undying && card.Level > 0 ? $"{name} +{card.Level}" : name);
		}
		string body = EscapeBbcode(text);
		string head = heads.Count > 0 ? $"[b]{string.Join(", ", heads)}.[/b] " : "";
		return $"[center]{head}{body}[/center]";
	}

	private static string EscapeBbcode(string text) => text.Replace("[", "[lb]");

	private static Color TileEffectTextColor(TileEffectType type) => type switch
	{
		TileEffectType.Lava => new Color(0.85f, 0.3f, 0.05f),
		TileEffectType.Wall => new Color(0.42f, 0.36f, 0.3f),
		TileEffectType.Healing => new Color(0.25f, 0.6f, 0.2f),
		_ => new Color(0.6f, 0.35f, 0.85f),
	};

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

	private static string BuildSpellStats(CardData card)
	{
		var parts = new List<string>();
		if (card.TargetsTile)
		{
			parts.Add(AreaName(card.AreaShape));
			if (card.SpellDamage > 0)
			{
				parts.Add($"{card.SpellDamage} dmg");
			}
			if (card.SpellHeal > 0)
			{
				parts.Add($"+{card.SpellHeal} HP");
			}
			if (card.TileEffect != TileEffectType.None)
			{
				parts.Add($"{KeywordInfo.GetTileEffectName(card.TileEffect)} {card.TileEffectDuration}T");
			}
			return string.Join(" · ", parts);
		}
		if (card.GrantStatus != StatusEffectType.None)
		{
			parts.Add(KeywordInfo.GetStatusName(card.GrantStatus));
		}
		AddDelta(parts, card.AttackDelta, "Atk");
		AddDelta(parts, card.HpDelta, "HP");
		AddDelta(parts, card.ShieldDelta, "Shield");
		AddDelta(parts, card.MovementDelta, "Move");
		AddDelta(parts, card.RangeDelta, "Range");
		return parts.Count > 0 ? string.Join("  ", parts) : "No stat change";
	}

	private static void AddDelta(List<string> parts, int value, string label)
	{
		if (value != 0)
		{
			parts.Add($"{FormatDelta(value)} {label}");
		}
	}

	private static string FormatDelta(int value) => value > 0 ? $"+{value}" : value.ToString();
}
