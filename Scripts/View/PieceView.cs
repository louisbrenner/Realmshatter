using System.Collections.Generic;
using System.Threading.Tasks;
using Godot;

namespace Realmshatter;

/// <summary>
/// Minion-like token for one piece (root of Piece.tscn): oval portrait (card tint + class symbol, see ClassVisuals)
/// in a gold rim, owner-colored ring, attack (yellow, bottom-left) and health (red drop, bottom-right)
/// badges, a shield badge + golden bubble, a name below the token, a green "can act" glow and a
/// "Zzz" exhausted state. Everything fits inside one tile; the badge plates sit at fixed token-local
/// spots and are tilted toward the camera (BadgeTilt). All Play*/MoveTo helpers are awaitable.
/// </summary>
public partial class PieceView : Node3D
{
	/// <summary>How strongly the card tint is blended into the owner color for BodyColor (0..1).</summary>
	[Export(PropertyHint.Range, "0,1,0.05")] public float TintBlend { get; set; } = 0.3f;
	[Export] public float MoveDuration { get; set; } = 0.35f;
	[Export] public float AttackDuration { get; set; } = 0.3f;
	[Export] public float HopHeight { get; set; } = 0.28f;
	/// <summary>
	/// Orientation of the stat badges and name: 0 = lying flat on the token (facing up), 1 = facing the
	/// camera. In between they lie on the token, tilted toward the camera and turned upright on screen.
	/// </summary>
	[Export(PropertyHint.Range, "0,1,0.05")] public float BadgeTilt { get; set; } = 0.5f;
	/// <summary>Maximum world width of the name label (it shrinks to fit inside the tile).</summary>
	[Export] public float MaxNameWidth { get; set; } = 0.78f;
	/// <summary>World size of the keyword emblems (left edge of the token).</summary>
	[Export] public float KeywordIconSize { get; set; } = 0.34f;

	[ExportGroup("Colors")]
	[Export] public Color HitFlashColor { get; set; } = new Color(1f, 1f, 1f);
	[Export] public Color SelectedColor { get; set; } = new Color(1f, 0.82f, 0.3f);
	[Export] public Color OrderColor { get; set; } = new Color(0.35f, 0.75f, 1f);
	[Export] public Color CanActColor { get; set; } = new Color(0.25f, 1f, 0.35f);
	[Export] public Color AttackBadgeColor { get; set; } = new Color(0.98f, 0.66f, 0.1f);
	[Export] public Color HealthBadgeColor { get; set; } = new Color(0.92f, 0.13f, 0.1f);
	[Export] public Color ShieldBadgeColor { get; set; } = new Color(0.78f, 0.8f, 0.86f);
	[Export] public Color BuffedColor { get; set; } = new Color(0.45f, 1f, 0.4f);
	[Export] public Color DamagedColor { get; set; } = new Color(1f, 0.3f, 0.26f);

	private Node3D _visual;
	private Node3D _badges;
	private MeshInstance3D _canActGlow;
	private MeshInstance3D _selectionRing;
	private MeshInstance3D _base;
	private MeshInstance3D _ownerRing;
	private MeshInstance3D _portrait;
	private MeshInstance3D _shieldBubble;
	private MeshInstance3D _attackBadge;
	private MeshInstance3D _healthBadge;
	private MeshInstance3D _shieldBadge;
	private MeshInstance3D _orderIndicator;
	private Label3D _attackLabel;
	private Label3D _healthLabel;
	private Label3D _shieldLabel;
	private Label3D _nameLabel;
	private Label3D _zzzLabel;
	private Vector3 _zzzBase;
	/// <summary>The three drifting "z" letters of the sleep indicator (the first is the scene's ZzzLabel).</summary>
	private Label3D[] _zzz = System.Array.Empty<Label3D>();
	private const float ZzzCycle = 2.4f;
	private const float ZzzRise = 0.32f;
	private Node3D _attackPlate;
	private Node3D _healthPlate;
	private Node3D _shieldPlate;
	private Node3D _orderPlate;
	private Node3D _namePlate;
	private Node3D[] _plates;
	private readonly List<Node3D> _keywordPlates = new List<Node3D>();
	private CardData _shownSource;
	private bool _shownFirstHitUsed;
	private Node3D _buildingModel;
	private Node3D _scaffold;
	private bool _underConstruction;
	private Keyword _shownKeywords = Keyword.None;
	private int _shownLevel = -1;
	private float _namePixelSize;
	private Quaternion _plateRotation = new Quaternion(2f, 0f, 0f, 0f);

	private ShaderMaterial _portraitMat;
	private ShaderMaterial _canActMat;
	private ShaderMaterial _selectMat;
	private StandardMaterial3D _ringMat;

	private Color _ownerColor = Colors.Gray;
	private Color _tint = Colors.White;
	private Color _bodyColor = Colors.Gray;
	private int _baseAttack;
	private int _baseHp;
	private int _maxHp;
	private bool _selected;
	private bool _hovered;
	private bool _canAct;
	private bool _exhausted;
	private float _time;
	private float _lift;
	private Vector3 _shake;
	private Tween _moveTween;
	private Tween _exhaustTween;

	/// <summary>Id of the core Piece this view represents (-1 before Setup).</summary>
	public int PieceId { get; private set; } = -1;

	/// <summary>Owner player index (from Setup).</summary>
	public int OwnerIndex { get; private set; }

	/// <summary>Owner color blended with the card tint (used for fragments etc.).</summary>
	public Color BodyColor => _bodyColor;

	/// <summary>The card tint.</summary>
	public Color TintColor => _tint;

	/// <summary>The owner color passed to Setup.</summary>
	public Color OwnerColor => _ownerColor;

	/// <summary>True while the green "can act" glow is shown.</summary>
	public bool CanAct => _canAct;

	/// <summary>True while the piece is shown exhausted (summoning sickness).</summary>
	public bool IsExhausted => _exhausted;

	/// <summary>Seconds after the start of PlayAttack at which the lunge hits.</summary>
	public float ImpactTime => AttackDuration * 0.45f;

	public override void _Ready()
	{
		EnsureNodes();
	}

	public override void _Process(double delta)
	{
		if (_visual == null)
		{
			return;
		}
		float dt = (float)delta;
		_time += dt;
		float target = _selected ? 0.09f + 0.025f * Mathf.Sin(_time * 3f) : (_hovered ? 0.05f : 0f);
		_lift = Mathf.Lerp(_lift, target, 1f - Mathf.Exp(-dt * 12f));
		_visual.Position = new Vector3(_shake.X, _lift + _shake.Y, _shake.Z);
		_badges.Position = new Vector3(_shake.X, _lift, _shake.Z);
		OrientPlates();
		if (_exhausted && _zzz.Length > 0)
		{
			AnimateZzz();
		}
	}

	/// <summary>Initializes portrait, colors, name and badges from a core piece.</summary>
	public void Setup(Piece piece, Color ownerColor)
	{
		EnsureNodes();
		PieceId = piece.Id;
		OwnerIndex = piece.OwnerIndex;
		Name = $"Piece_{piece.Id}";
		_ownerColor = ownerColor;
		_tint = piece.Source?.Tint ?? Colors.White;
		_tint = new Color(_tint.R, _tint.G, _tint.B);
		_bodyColor = ownerColor.Lerp(_tint, TintBlend);

		int role = piece.Role switch
		{
			UnitRole.Attack => 0,
			UnitRole.Utility => 1,
			_ => 2,
		};
		_portraitMat.SetShaderParameter("tint", _tint);
		_portraitMat.SetShaderParameter("role", role);
		_portraitMat.SetShaderParameter("glyph", ClassVisuals.ArtGlyph(piece.Source));
		_portraitMat.SetShaderParameter("seed", piece.Id * 0.37f);
		_ringMat.AlbedoColor = ownerColor;
		_ringMat.Emission = ownerColor;
		_nameLabel.Text = piece.Source?.Name ?? $"#{piece.Id}";
		_nameLabel.Modulate = ownerColor.Lerp(Colors.White, 0.55f);
		FitName();

		_maxHp = 0;
		Refresh(piece);
	}

	/// <summary>Updates attack/health/shield badges and the order indicator from the core piece.</summary>
	public void Refresh(Piece piece)
	{
		if (piece == null)
		{
			return;
		}
		EnsureNodes();
		_baseAttack = piece.BaseStats.Attack;
		_baseHp = piece.BaseStats.Hp;
		_maxHp = piece.MaxHp;
		SetAttack(piece.EffectiveAttack);
		SetStats(piece.CurrentHp, piece.TotalShield);
		SetKeywords(piece.Keywords, piece.Source?.Level ?? 0, piece.Source, piece.WasHit);
		if (piece.IsBuilding)
		{
			EnsureBuildingModel(piece);
			SetUnderConstruction(piece.UnderConstruction);
		}
	}

	/// <summary>Grows the building out of its scaffold when finished (or shrinks it back while under construction).</summary>
	public void SetUnderConstruction(bool underConstruction)
	{
		if (_buildingModel == null || _underConstruction == underConstruction)
		{
			return;
		}
		_underConstruction = underConstruction;
		_scaffold.Visible = true;
		Tween tween = CreateTween();
		tween.TweenProperty(_buildingModel, "scale", new Vector3(1f, underConstruction ? 0.35f : 1f, 1f), 0.45f)
			.SetTrans(Tween.TransitionType.Back).SetEase(Tween.EaseType.Out);
		tween.TweenCallback(Callable.From(() => _scaffold.Visible = _underConstruction));
	}

	private void EnsureBuildingModel(Piece piece)
	{
		if (_buildingModel != null)
		{
			return;
		}
		foreach (Label3D z in _zzz)
		{
			z.Visible = false;
		}
		_portrait.Visible = false;
		_buildingModel = BuildingModels.Create(piece.Building, piece.Source?.Tint ?? Colors.Gray, _ownerColor);
		_buildingModel.Position = new Vector3(0, 0.1f, 0);
		_buildingModel.Scale = new Vector3(1f, 0.35f, 1f);
		_visual.AddChild(_buildingModel);
		_scaffold = BuildingModels.CreateScaffold();
		_scaffold.Position = new Vector3(0, 0.1f, 0);
		_visual.AddChild(_scaffold);
		_underConstruction = true;
	}

	/// <summary>
	/// Shows one small emblem plate per keyword along the left edge of the token (flame = Burning,
	/// snowflake = Frost, fist = Push, spear = Pierce, cross = Mending, bolt = Arc, bell = Echo,
	/// skull = Undying; an Undying level is shown as "+N" beside the skull). The first-hit burst disappears once
	/// it has fired (firstHitUsed).
	/// </summary>
	public void SetKeywords(Keyword keywords, int level = 0, CardData source = null, bool firstHitUsed = false)
	{
		EnsureNodes();
		if (keywords == _shownKeywords && level == _shownLevel && source == _shownSource && firstHitUsed == _shownFirstHitUsed)
		{
			return;
		}
		_shownSource = source;
		_shownFirstHitUsed = firstHitUsed;
		_shownKeywords = keywords;
		_shownLevel = level;
		foreach (Node3D plate in _keywordPlates)
		{
			if (IsInstanceValid(plate))
			{
				plate.QueueFree();
			}
		}
		_keywordPlates.Clear();

		List<Keyword> list = KeywordInfo.Split(keywords);
		List<(FxIconShape Shape, Color Fg, Color Bg)> icons = source != null
			? KeywordVisuals.IconsFor(source, firstHitUsed)
			: list.ConvertAll(k => (KeywordVisuals.GetShape(k), KeywordVisuals.GetForeground(k), KeywordVisuals.GetBackground(k)));
		float step = KeywordIconSize * 0.92f;
		for (int i = 0; i < icons.Count; i++)
		{
			Keyword k = i < list.Count ? list[i] : Keyword.None;
			var plate = new Node3D { Name = $"Icon_{i}", Position = new Vector3(-0.36f, 0.21f, -0.2f - i * step) };
			_badges.AddChild(plate);
			MeshInstance3D icon = VfxAssets.CreateIcon((int)icons[i].Shape, KeywordIconSize, icons[i].Fg, icons[i].Bg, true, 31);
			var mat = (ShaderMaterial)icon.MaterialOverride;
			mat.SetShaderParameter("billboard", false);
			mat.SetShaderParameter("rim_color", new Color(0.86f, 0.66f, 0.3f));
			mat.SetShaderParameter("energy", 1.15f);
			plate.AddChild(icon);
			if (k == Keyword.Undying && level > 0)
			{
				Label3D lv = VfxAssets.CreateLabel($"+{level}", 40, 0.0034f, new Color(0.7f, 1f, 0.9f), 10, 33);
				lv.Billboard = BaseMaterial3D.BillboardModeEnum.Disabled;
				lv.Position = new Vector3(0.1f, -0.1f, 0.001f);
				plate.AddChild(lv);
			}
			_keywordPlates.Add(plate);
		}
		var all = new List<Node3D> { _attackPlate, _healthPlate, _shieldPlate, _orderPlate, _namePlate };
		all.AddRange(_keywordPlates);
		_plates = all.ToArray();
		_plateRotation = new Quaternion(2f, 0f, 0f, 0f);
	}

	/// <summary>Updates the health and shield badges (health turns red when damaged, green when buffed).</summary>
	public void SetStats(int hp, int shield)
	{
		EnsureNodes();
		if (_maxHp <= 0)
		{
			_maxHp = hp;
			_baseHp = hp;
		}
		_healthLabel.Text = hp.ToString();
		_healthLabel.Modulate = hp < _maxHp ? DamagedColor : (_maxHp > _baseHp ? BuffedColor : Colors.White);
		bool hasShield = shield > 0;
		_shieldPlate.Visible = hasShield;
		_shieldLabel.Text = shield.ToString();
		_shieldBubble.Visible = hasShield;
	}

	/// <summary>Updates the attack badge (green when above the base attack, red when below).</summary>
	public void SetAttack(int attack)
	{
		EnsureNodes();
		_attackLabel.Text = attack.ToString();
		_attackLabel.Modulate = attack > _baseAttack ? BuffedColor : (attack < _baseAttack ? DamagedColor : Colors.White);
	}

	/// <summary>Shows or hides the golden selection glow and lifts the token.</summary>
	public void SetSelected(bool selected)
	{
		EnsureNodes();
		_selected = selected;
		_selectionRing.Visible = selected;
	}

	/// <summary>Slightly lifts the token while the mouse is over it (optional).</summary>
	public void SetHovered(bool hovered)
	{
		_hovered = hovered;
	}

	/// <summary>Shows or hides the small "has order" gem.</summary>
	public void SetHasOrder(bool hasOrder)
	{
		EnsureNodes();
		_orderPlate.Visible = hasOrder;
	}

	/// <summary>Green pulsing outline like a playable Hearthstone minion.</summary>
	public void SetCanAct(bool canAct)
	{
		EnsureNodes();
		_canAct = canAct;
		_canActGlow.Visible = canAct;
	}

	/// <summary>
	/// Sleep indicator: three small z's rise one after another from the top of the token, growing, drifting
	/// sideways and fading out, then start again.
	/// </summary>
	private void AnimateZzz()
	{
		for (int i = 0; i < _zzz.Length; i++)
		{
			float phase = Mathf.PosMod(_time / ZzzCycle + i / (float)_zzz.Length, 1f);
			float sway = 0.035f * Mathf.Sin(phase * Mathf.Tau + i);
			_zzz[i].Position = _zzzBase + new Vector3(phase * 0.1f + sway, phase * ZzzRise, 0f);
			_zzz[i].Scale = Vector3.One * (0.55f + 0.6f * phase);
			float alpha = Mathf.Sin(phase * Mathf.Pi);
			_zzz[i].Modulate = new Color(0.78f, 0.88f, 1f, alpha);
		}
	}

	/// <summary>
	/// Exhausted look (desaturated portrait + drifting z's): summoning sick, busy building, or already acted this
	/// turn.
	/// </summary>
	public void SetExhausted(bool exhausted)
	{
		EnsureNodes();
		if (_buildingModel != null)
		{
			exhausted = false;
		}
		if (_exhausted == exhausted)
		{
			return;
		}
		_exhausted = exhausted;
		foreach (Label3D z in _zzz)
		{
			z.Visible = exhausted;
		}
		_exhaustTween?.Kill();
		_exhaustTween = CreateTween();
		_exhaustTween.TweenMethod(Callable.From<float>(SetDesaturation),
			exhausted ? 0f : 0.75f, exhausted ? 0.75f : 0f, 0.3f);
	}

	/// <summary>Places the view immediately (no animation), cancelling a running move.</summary>
	public void SnapTo(Vector3 target)
	{
		if (_moveTween != null && _moveTween.IsValid())
		{
			_moveTween.Kill();
		}
		GlobalPosition = target;
	}

	/// <summary>Hops to a world position with a landing squash. Await to wait for arrival.</summary>
	public async Task MoveTo(Vector3 target)
	{
		if (_moveTween != null && _moveTween.IsValid())
		{
			_moveTween.Kill();
		}
		Vector3 start = GlobalPosition;
		float hop = HopHeight * Mathf.Min(1f, start.DistanceTo(target));
		_moveTween = CreateTween();
		_moveTween.TweenMethod(Callable.From<float>(t =>
		{
			GlobalPosition = start.Lerp(target, t) + Vector3.Up * hop * 4f * t * (1f - t);
		}), 0f, 1f, MoveDuration).SetTrans(Tween.TransitionType.Sine).SetEase(Tween.EaseType.InOut);
		await ToSignal(_moveTween, Tween.SignalName.Finished);
		_ = PlaySquash(0.6f);
	}

	/// <summary>Winds up, lunges toward a world position and returns. The hit lands at ImpactTime.</summary>
	public async Task PlayAttack(Vector3 targetWorld)
	{
		Vector3 start = GlobalPosition;
		var flat = new Vector3(targetWorld.X, start.Y, targetWorld.Z);
		Vector3 dir = flat - start;
		dir = dir.LengthSquared() > 0.0001f ? dir.Normalized() : Vector3.Forward;
		Vector3 windup = start - dir * 0.14f + new Vector3(0, 0.06f, 0);
		Vector3 lunge = start.Lerp(flat, 0.58f) + new Vector3(0, 0.12f, 0);
		Tween tween = CreateTween();
		tween.TweenProperty(this, "global_position", windup, AttackDuration * 0.25f)
			.SetTrans(Tween.TransitionType.Sine).SetEase(Tween.EaseType.Out);
		tween.TweenProperty(this, "global_position", lunge, AttackDuration * 0.2f)
			.SetTrans(Tween.TransitionType.Expo).SetEase(Tween.EaseType.In);
		tween.TweenProperty(this, "global_position", start, AttackDuration * 0.55f)
			.SetTrans(Tween.TransitionType.Quad).SetEase(Tween.EaseType.Out);
		await ToSignal(tween, Tween.SignalName.Finished);
	}

	/// <summary>Small recoil away from a target (ranged shot).</summary>
	public async Task PlayRecoil(Vector3 targetWorld)
	{
		Vector3 start = GlobalPosition;
		Vector3 dir = new Vector3(targetWorld.X - start.X, 0f, targetWorld.Z - start.Z);
		dir = dir.LengthSquared() > 0.0001f ? dir.Normalized() : Vector3.Forward;
		Tween tween = CreateTween();
		tween.TweenProperty(this, "global_position", start - dir * 0.1f + new Vector3(0, 0.04f, 0), 0.06f);
		tween.TweenProperty(this, "global_position", start, 0.16f).SetTrans(Tween.TransitionType.Quad).SetEase(Tween.EaseType.Out);
		await ToSignal(tween, Tween.SignalName.Finished);
	}

	/// <summary>Short nudge toward a world position and back (e.g. blocked move).</summary>
	public async Task PlayBump(Vector3 towardWorld)
	{
		Vector3 start = GlobalPosition;
		Vector3 dir = new Vector3(towardWorld.X - start.X, 0f, towardWorld.Z - start.Z);
		dir = dir.LengthSquared() > 0.0001f ? dir.Normalized() : Vector3.Forward;
		Tween tween = CreateTween();
		tween.TweenProperty(this, "global_position", start + dir * 0.2f, 0.08f).SetTrans(Tween.TransitionType.Quad).SetEase(Tween.EaseType.Out);
		tween.TweenProperty(this, "global_position", start, 0.14f).SetTrans(Tween.TransitionType.Back).SetEase(Tween.EaseType.Out);
		await ToSignal(tween, Tween.SignalName.Finished);
	}

	/// <summary>Flashes the portrait white, shakes and squashes the token.</summary>
	public async Task PlayHit()
	{
		EnsureNodes();
		_portraitMat.SetShaderParameter("flash_color", HitFlashColor);
		Tween flash = CreateTween();
		flash.TweenMethod(Callable.From<float>(SetFlash), 1f, 0f, 0.3f);
		Tween shake = CreateTween();
		shake.TweenMethod(Callable.From<float>(t =>
		{
			_shake = new Vector3(Mathf.Sin(t * 42f), 0f, Mathf.Cos(t * 33f) * 0.6f) * 0.09f * (1f - t);
		}), 0f, 1f, 0.26f);
		shake.TweenCallback(Callable.From(() => _shake = Vector3.Zero));
		Tween punch = CreateTween();
		punch.TweenProperty(_visual, "scale", new Vector3(1.14f, 0.82f, 1.14f), 0.05f);
		punch.TweenProperty(_visual, "scale", Vector3.One, 0.22f).SetTrans(Tween.TransitionType.Elastic).SetEase(Tween.EaseType.Out);
		await ToSignal(flash, Tween.SignalName.Finished);
	}

	/// <summary>Briefly tints the portrait with a color (e.g. chain trigger) and pulses its scale.</summary>
	public async Task PlayFlash(Color color, float duration = 0.35f)
	{
		EnsureNodes();
		_portraitMat.SetShaderParameter("flash_color", color);
		Tween tween = CreateTween();
		tween.SetParallel(true);
		tween.TweenMethod(Callable.From<float>(SetFlash), 0.85f, 0f, duration);
		tween.TweenProperty(_visual, "scale", Vector3.One * 1.18f, duration * 0.4f).SetTrans(Tween.TransitionType.Back).SetEase(Tween.EaseType.Out);
		tween.Chain().TweenProperty(_visual, "scale", Vector3.One, duration * 0.6f);
		await ToSignal(tween, Tween.SignalName.Finished);
	}

	/// <summary>Squash-and-stretch bounce of the token (landing).</summary>
	public async Task PlaySquash(float amount = 1f)
	{
		EnsureNodes();
		Tween tween = CreateTween();
		tween.TweenProperty(_visual, "scale", new Vector3(1f + 0.25f * amount, 1f - 0.35f * amount, 1f + 0.25f * amount), 0.06f);
		tween.TweenProperty(_visual, "scale", Vector3.One, 0.3f).SetTrans(Tween.TransitionType.Elastic).SetEase(Tween.EaseType.Out);
		await ToSignal(tween, Tween.SignalName.Finished);
	}

	/// <summary>Drops the token from above onto its current position. Completes on impact.</summary>
	public async Task PlayDrop(float height = 2.2f, float duration = 0.22f)
	{
		EnsureNodes();
		if (_moveTween != null && _moveTween.IsValid())
		{
			_moveTween.Kill();
		}
		Vector3 rest = GlobalPosition;
		GlobalPosition = rest + Vector3.Up * height;
		_visual.Scale = new Vector3(0.82f, 1.3f, 0.82f);
		Tween tween = CreateTween();
		tween.SetParallel(true);
		tween.TweenProperty(this, "global_position", rest, duration).SetTrans(Tween.TransitionType.Quad).SetEase(Tween.EaseType.In);
		tween.TweenProperty(_visual, "scale", new Vector3(0.92f, 1.12f, 0.92f), duration);
		await ToSignal(tween, Tween.SignalName.Finished);
	}

	/// <summary>Collapses the token quickly (the animator adds the shatter VFX) and frees it.</summary>
	public async Task PlayDeath()
	{
		EnsureNodes();
		if (_moveTween != null && _moveTween.IsValid())
		{
			_moveTween.Kill();
		}
		_badges.Visible = false;
		_canActGlow.Visible = false;
		_selectionRing.Visible = false;
		Tween tween = CreateTween();
		tween.SetParallel(true);
		tween.TweenProperty(_visual, "scale", new Vector3(0.01f, 0.01f, 0.01f), 0.18f)
			.SetTrans(Tween.TransitionType.Back).SetEase(Tween.EaseType.In);
		tween.TweenProperty(_visual, "rotation:y", _visual.Rotation.Y + Mathf.Pi, 0.18f);
		await ToSignal(tween, Tween.SignalName.Finished);
		QueueFree();
	}

	private void SetFlash(float value)
	{
		_portraitMat?.SetShaderParameter("flash", value);
	}

	private void SetDesaturation(float value)
	{
		_portraitMat?.SetShaderParameter("desaturate", value);
		_portraitMat?.SetShaderParameter("brightness", 1f - value * 0.3f);
	}

	private void EnsureNodes()
	{
		if (_visual != null)
		{
			return;
		}
		_visual = GetNode<Node3D>("Visual");
		_badges = GetNode<Node3D>("Badges");
		_canActGlow = GetNode<MeshInstance3D>("Visual/CanActGlow");
		_selectionRing = GetNode<MeshInstance3D>("Visual/SelectionRing");
		_base = GetNode<MeshInstance3D>("Visual/Token/Base");
		_ownerRing = GetNode<MeshInstance3D>("Visual/Token/OwnerRing");
		_portrait = GetNode<MeshInstance3D>("Visual/Token/Portrait");
		_shieldBubble = GetNode<MeshInstance3D>("Visual/ShieldBubble");
		_attackPlate = GetNode<Node3D>("Badges/AttackPlate");
		_healthPlate = GetNode<Node3D>("Badges/HealthPlate");
		_shieldPlate = GetNode<Node3D>("Badges/ShieldPlate");
		_orderPlate = GetNode<Node3D>("Badges/OrderPlate");
		_namePlate = GetNode<Node3D>("Badges/NamePlate");
		_plates = new[] { _attackPlate, _healthPlate, _shieldPlate, _orderPlate, _namePlate };
		_attackBadge = GetNode<MeshInstance3D>("Badges/AttackPlate/Badge");
		_healthBadge = GetNode<MeshInstance3D>("Badges/HealthPlate/Badge");
		_shieldBadge = GetNode<MeshInstance3D>("Badges/ShieldPlate/Badge");
		_orderIndicator = GetNode<MeshInstance3D>("Badges/OrderPlate/Badge");
		_attackLabel = GetNode<Label3D>("Badges/AttackPlate/Label");
		_healthLabel = GetNode<Label3D>("Badges/HealthPlate/Label");
		_shieldLabel = GetNode<Label3D>("Badges/ShieldPlate/Label");
		_nameLabel = GetNode<Label3D>("Badges/NamePlate/Label");
		_zzzLabel = GetNode<Label3D>("Badges/ZzzLabel");
		// Badge numbers: lining figures, centred on their badge.
		foreach (Label3D number in new[] { _attackLabel, _healthLabel, _shieldLabel })
		{
			number.Font = VfxAssets.NumberFont;
			number.VerticalAlignment = VerticalAlignment.Center;
			// Label3D offsets point up: lift the digits by how far their ink sits below the line centre.
			number.Offset = new Vector2(0f, VfxAssets.DigitDrop(number.FontSize));
		}
		_namePixelSize = _nameLabel.PixelSize;
		// Sleep indicator: start just above the token's top edge and build three single "z" letters.
		_zzzBase = new Vector3(0.08f, 0.42f, -0.12f);
		_zzzLabel.Text = "z";
		_zzzLabel.Visible = false;
		var letters = new List<Label3D> { _zzzLabel };
		for (int i = 1; i < 3; i++)
		{
			var copy = (Label3D)_zzzLabel.Duplicate();
			copy.Name = $"ZzzLabel{i + 1}";
			_zzzLabel.GetParent().AddChild(copy);
			letters.Add(copy);
		}
		_zzz = letters.ToArray();

		_base.MaterialOverride = VfxAssets.CreateGoldMaterial(0.06f);
		_ringMat = new StandardMaterial3D
		{
			AlbedoColor = _ownerColor,
			Metallic = 0.3f,
			Roughness = 0.3f,
			EmissionEnabled = true,
			Emission = _ownerColor,
			EmissionEnergyMultiplier = 0.9f,
		};
		_ownerRing.MaterialOverride = _ringMat;

		_portraitMat = VfxAssets.CreateMaterial("piece_portrait");
		_portrait.MaterialOverride = _portraitMat;

		_canActMat = VfxAssets.CreateMaterial("aura", 2);
		_canActMat.SetShaderParameter("color", CanActColor);
		_canActMat.SetShaderParameter("inner", 0.6f);
		_canActMat.SetShaderParameter("width", 0.22f);
		_canActMat.SetShaderParameter("energy", 2.6f);
		_canActGlow.MaterialOverride = _canActMat;

		_selectMat = VfxAssets.CreateMaterial("aura", 3);
		_selectMat.SetShaderParameter("color", SelectedColor);
		_selectMat.SetShaderParameter("inner", 0.55f);
		_selectMat.SetShaderParameter("width", 0.3f);
		_selectMat.SetShaderParameter("energy", 3.2f);
		_selectMat.SetShaderParameter("pulse_speed", 5f);
		_selectionRing.MaterialOverride = _selectMat;

		_shieldBubble.MaterialOverride = VfxAssets.CreateMaterial("shield_bubble", 5);

		_attackBadge.MaterialOverride = CreateBadgeMaterial(7, AttackBadgeColor);
		_healthBadge.MaterialOverride = CreateBadgeMaterial(8, HealthBadgeColor);
		_shieldBadge.MaterialOverride = CreateBadgeMaterial(9, ShieldBadgeColor);
		_orderIndicator.MaterialOverride = CreateBadgeMaterial(5, OrderColor);
	}

	private static ShaderMaterial CreateBadgeMaterial(int shape, Color fill)
	{
		ShaderMaterial mat = VfxAssets.CreateMaterial("badge", 28);
		mat.SetShaderParameter("shape", shape);
		mat.SetShaderParameter("fill_color", fill);
		mat.SetShaderParameter("billboard", false);
		return mat;
	}

	/// <summary>
	/// Orients all badge plates: blend between lying flat (turned so the text is upright on screen)
	/// and facing the camera by BadgeTilt. Positions stay token-local, so badges never drift off the tile.
	/// </summary>
	private void OrientPlates()
	{
		Camera3D camera = GetViewport()?.GetCamera3D();
		if (camera == null || _plates == null)
		{
			return;
		}
		Basis camBasis = camera.GlobalBasis.Orthonormalized();
		Vector3 right = new Vector3(camBasis.X.X, 0f, camBasis.X.Z);
		right = right.LengthSquared() > 1e-5f ? right.Normalized() : Vector3.Right;
		Vector3 normal = Vector3.Up;
		var flat = new Basis(right, normal.Cross(right), normal);
		Quaternion q = flat.GetRotationQuaternion().Slerp(camBasis.GetRotationQuaternion(), Mathf.Clamp(BadgeTilt, 0f, 1f));
		if (q.IsEqualApprox(_plateRotation))
		{
			return;
		}
		_plateRotation = q;
		var basis = new Basis(q);
		foreach (Node3D plate in _plates)
		{
			plate.GlobalBasis = basis;
		}
	}

	/// <summary>Shrinks the name label so it fits inside the tile.</summary>
	private void FitName()
	{
		Font font = _nameLabel.Font ?? VfxAssets.CardFont;
		_nameLabel.PixelSize = _namePixelSize;
		if (font == null)
		{
			return;
		}
		float width = font.GetStringSize(_nameLabel.Text, HorizontalAlignment.Left, -1, _nameLabel.FontSize).X * _namePixelSize;
		if (width > MaxNameWidth && width > 0f)
		{
			_nameLabel.PixelSize = _namePixelSize * MaxNameWidth / width;
		}
	}
}
