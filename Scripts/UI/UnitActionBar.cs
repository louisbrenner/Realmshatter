using System;
using System.Collections.Generic;
using Godot;

namespace Realmshatter;

/// <summary>
/// Floating row of round ability buttons beside the selected unit (e.g. Build). It follows the unit's screen
/// position every frame (a provider returns the placement, null hides the bar) and docks as close to the unit as
/// possible without covering any of the tiles the player is choosing from (its move or attack targets): it searches
/// the 8 directions in growing rings and takes the nearest free spot on screen.
/// Each button shows a glyph, an AP cost badge and a tooltip; unavailable abilities are greyed out with the reason as tooltip.
/// </summary>
public partial class UnitActionBar : Control
{
	/// <summary>One ability shown on the bar.</summary>
	public readonly record struct Ability(FxIconShape Icon, string Label, int Cost, bool Enabled, string Tooltip, Action OnPressed);

	/// <summary>
	/// Where to dock, in viewport pixels: the unit's centre, half a tile's on-screen size (gap to the unit) and the
	/// screen points (tile centres) the bar should not cover.
	/// </summary>
	public readonly record struct Placement(Vector2 Center, float HalfTile, IReadOnlyList<Vector2> Avoid);

	/// <summary>Docking directions in order of preference: right, left, below, above, then the diagonals.</summary>
	private static readonly Vector2[] Sides =
	{
		new Vector2(1, 0), new Vector2(-1, 0), new Vector2(0, 1), new Vector2(0, -1),
		new Vector2(1, 1).Normalized(), new Vector2(-1, 1).Normalized(), new Vector2(1, -1).Normalized(), new Vector2(-1, -1).Normalized(),
	};

	private const float ButtonSize = 46f;
	private const float Spacing = 8f;

	private Func<Placement?> _placement;
	private readonly List<Button> _buttons = new List<Button>();
	private float _appear;
	private int _side = -1;
	private int _ring = -1;

	/// <summary>How many rings (one tile apart) the search may move outward from the unit.</summary>
	private const int MaxRings = 12;
	/// <summary>Width of the caption that hangs out on both sides of the buttons.</summary>
	private const float CaptionOverhang = 20f;

	public override void _Ready()
	{
		MouseFilter = MouseFilterEnum.Ignore;
		Visible = false;
	}

	/// <summary>Shows the abilities docked beside the unit described by 'placement' (re-evaluated every frame).</summary>
	public void ShowFor(Func<Placement?> placement, IReadOnlyList<Ability> abilities)
	{
		Clear();
		_placement = placement;
		_side = -1;
		_ring = -1;
		if (abilities == null || abilities.Count == 0)
		{
			Visible = false;
			return;
		}
		foreach (Ability ability in abilities)
		{
			_buttons.Add(CreateButton(ability));
		}
		Size = new Vector2(abilities.Count * ButtonSize + (abilities.Count - 1) * Spacing, ButtonSize + 18f);
		_appear = 0f;
		Visible = true;
		UpdatePosition();
	}

	/// <summary>Hides the bar.</summary>
	public void HideBar()
	{
		Clear();
		Visible = false;
		_placement = null;
	}

	public override void _Process(double delta)
	{
		if (!Visible)
		{
			return;
		}
		_appear = Mathf.Min(1f, _appear + (float)delta * 7f);
		float s = 0.6f + 0.4f * Mathf.Sin(_appear * Mathf.Pi * 0.5f);
		PivotOffset = Size * 0.5f;
		Scale = new Vector2(s, s);
		Modulate = new Color(1, 1, 1, _appear);
		UpdatePosition();
	}

	private void UpdatePosition()
	{
		Placement? placement = _placement?.Invoke();
		if (!placement.HasValue || GetParent() is not Control parent)
		{
			Visible = false;
			return;
		}
		Transform2D toLocal = parent.GetGlobalTransform().AffineInverse();
		Vector2 center = toLocal * placement.Value.Center;
		float halfTile = placement.Value.HalfTile * toLocal.Scale.X;
		var avoid = new List<Vector2>();
		if (placement.Value.Avoid != null)
		{
			foreach (Vector2 p in placement.Value.Avoid)
			{
				avoid.Add(toLocal * p);
			}
		}

		// Every candidate (8 directions x growing rings) is scored: covering any wanted tile is by far the worst,
		// then leaving the screen, then the distance from the unit, then the direction preference. The current spot
		// gets a small bonus so the bar does not flicker between equally good spots while the camera moves.
		int bestSide = 0;
		int bestRing = 0;
		float bestScore = float.MaxValue;
		for (int ring = 0; ring < MaxRings; ring++)
		{
			for (int i = 0; i < Sides.Length; i++)
			{
				Rect2 rect = RectFor(center, Sides[i], halfTile, ring);
				// The bar's full footprint (caption included), grown by a tile half: any overlap with a tile counts.
				Rect2 footprint = rect.Grow(halfTile * 0.95f).GrowIndividual(CaptionOverhang, 0f, CaptionOverhang, 0f);
				int covered = 0;
				foreach (Vector2 p in avoid)
				{
					if (footprint.HasPoint(p))
					{
						covered++;
					}
				}
				bool offScreen = rect.Position.X - CaptionOverhang < 0f || rect.Position.Y < 0f
					|| rect.End.X + CaptionOverhang > parent.Size.X || rect.End.Y > parent.Size.Y;
				float score = covered * 1000f + (offScreen ? 500f : 0f) + ring * 10f + i
					- (i == _side && ring == _ring ? 4f : 0f);
				if (score < bestScore)
				{
					bestScore = score;
					bestSide = i;
					bestRing = ring;
				}
			}
		}
		_side = bestSide;
		_ring = bestRing;
		Position = RectFor(center, Sides[bestSide], halfTile, bestRing).Position;
	}

	/// <summary>
	/// Bar rectangle on the given side of the unit: one tile-half plus a small gap away from its centre, pushed
	/// 'ring' more tiles outward.
	/// </summary>
	private Rect2 RectFor(Vector2 center, Vector2 side, float halfTile, int ring)
	{
		Vector2 half = Size * 0.5f;
		float reach = halfTile * (1.15f + 2f * ring) + Mathf.Abs(side.X) * (half.X + CaptionOverhang) + Mathf.Abs(side.Y) * half.Y;
		Vector2 c = center + side * reach;
		return new Rect2(c - half, Size);
	}

	private Button CreateButton(Ability ability)
	{
		var button = new Button
		{
			Flat = true,
			FocusMode = FocusModeEnum.None,
			CustomMinimumSize = new Vector2(ButtonSize, ButtonSize),
			Size = new Vector2(ButtonSize, ButtonSize),
			Position = new Vector2(_buttons.Count * (ButtonSize + Spacing), 0f),
			TooltipText = ability.Tooltip,
			Disabled = !ability.Enabled,
			MouseDefaultCursorShape = ability.Enabled ? CursorShape.PointingHand : CursorShape.Arrow,
		};
		var icon = new ColorRect
		{
			MouseFilter = MouseFilterEnum.Ignore,
			Size = new Vector2(ButtonSize, ButtonSize),
			Material = IconMaterial(ability),
		};
		button.AddChild(icon);
		if (ability.Cost > 0)
		{
			var badge = new Label
			{
				Text = ability.Cost.ToString(),
				HorizontalAlignment = HorizontalAlignment.Center,
				VerticalAlignment = VerticalAlignment.Center,
				Position = new Vector2(ButtonSize - 18f, -4f),
				Size = new Vector2(22f, 22f),
				MouseFilter = MouseFilterEnum.Ignore,
			};
			badge.AddThemeFontOverride("font", VfxAssets.CardTextBoldFont);
			badge.AddThemeFontSizeOverride("font_size", 14);
			badge.AddThemeColorOverride("font_color", Colors.White);
			badge.AddThemeColorOverride("font_outline_color", new Color(0.02f, 0.06f, 0.2f));
			badge.AddThemeConstantOverride("outline_size", 5);
			var gem = new Panel { Position = badge.Position, Size = badge.Size, MouseFilter = MouseFilterEnum.Ignore };
			gem.AddThemeStyleboxOverride("panel", HudStyle.Box(HudStyle.ManaBlue, HudStyle.ManaLight, 11, 2, 2));
			button.AddChild(gem);
			button.AddChild(badge);
		}
		var caption = new Label
		{
			Text = ability.Label,
			HorizontalAlignment = HorizontalAlignment.Center,
			Position = new Vector2(-20f, ButtonSize - 2f),
			Size = new Vector2(ButtonSize + 40f, 18f),
			MouseFilter = MouseFilterEnum.Ignore,
		};
		caption.AddThemeFontOverride("font", VfxAssets.CardTextBoldFont);
		caption.AddThemeFontSizeOverride("font_size", 12);
		caption.AddThemeColorOverride("font_color", ability.Enabled ? HudStyle.TextLight : new Color(0.7f, 0.65f, 0.6f));
		caption.AddThemeConstantOverride("outline_size", 4);
		button.AddChild(caption);
		button.MouseEntered += () =>
		{
			if (!button.Disabled)
			{
				Sfx.Play(SfxId.CardHover);
				icon.Scale = new Vector2(1.08f, 1.08f);
			}
		};
		button.MouseExited += () => icon.Scale = Vector2.One;
		icon.PivotOffset = new Vector2(ButtonSize, ButtonSize) * 0.5f;
		button.Pressed += () =>
		{
			Sfx.Play(SfxId.ButtonClick);
			ability.OnPressed?.Invoke();
		};
		AddChild(button);
		return button;
	}

	private static ShaderMaterial IconMaterial(Ability ability)
	{
		var mat = new ShaderMaterial { Shader = VfxAssets.GetShader("keyword_icon") };
		mat.SetShaderParameter("shape", (int)ability.Icon);
		mat.SetShaderParameter("fg_color", ability.Enabled ? new Color(1f, 0.9f, 0.7f) : new Color(0.6f, 0.58f, 0.55f));
		mat.SetShaderParameter("bg_color", ability.Enabled ? new Color(0.36f, 0.22f, 0.1f, 0.97f) : new Color(0.22f, 0.2f, 0.19f, 0.97f));
		mat.SetShaderParameter("rim_color", ability.Enabled ? new Color(1f, 0.8f, 0.38f) : new Color(0.5f, 0.47f, 0.43f));
		return mat;
	}

	private void Clear()
	{
		foreach (Button b in _buttons)
		{
			b.QueueFree();
		}
		_buttons.Clear();
	}
}
