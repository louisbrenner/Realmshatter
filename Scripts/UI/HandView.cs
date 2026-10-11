using System;
using System.Collections.Generic;
using Godot;

namespace Realmshatter;

/// <summary>
/// Hearthstone-style fanned hand at the bottom of the screen. Cards overlap on an arc; the hovered
/// card straightens, enlarges and comes to the front while its neighbours move aside. Only displays
/// the hand and reports clicks; the GameManager decides what a selection means.
/// </summary>
public partial class HandView : HBoxContainer
{
	[Signal] public delegate void CardSelectedEventHandler(int handIndex);

	/// <summary>A hand card was hovered (true) or left (false); used for the card info panel.</summary>
	[Signal] public delegate void CardHoverChangedEventHandler(CardView card, bool hovered);

	[Export] public PackedScene CardScene { get; set; }
	[Export] public float CardSpacing { get; set; } = 100f;
	[Export] public float FanAngleDegrees { get; set; } = 4f;
	[Export] public float ArcDrop { get; set; } = 5f;
	[Export] public float HoverScale { get; set; } = 1.45f;
	/// <summary>Scale of resting (not hovered) cards; small so the board's bottom rows stay visible.</summary>
	[Export] public float RestScale { get; set; } = 0.8f;
	[Export] public float SelectedRise { get; set; } = 40f;
	/// <summary>How far resting cards sink below the hand area (Hearthstone-style peek); hovered cards rise fully.</summary>
	[Export] public float RestSink { get; set; } = 62f;
	[Export] public float PushAside { get; set; } = 60f;
	[Export] public float LayoutTweenTime { get; set; } = 0.14f;

	private readonly List<CardView> _cards = new List<CardView>();
	private readonly Dictionary<CardView, Tween> _tweens = new Dictionary<CardView, Tween>();
	private Control _fan;
	private int _selectedIndex = -1;
	private int _hoveredIndex = -1;
	private bool _orderQueued;

	/// <summary>Number of cards currently displayed.</summary>
	public int CardCount => _cards.Count;

	public override void _Ready()
	{
		MouseFilter = MouseFilterEnum.Ignore;
		EnsureFan();
	}

	/// <summary>
	/// Shows the hand and clears the selection. costOf returns the AP cost, canAfford decides the
	/// playable glow (unplayable cards still emit CardSelected). Existing card views are reused so
	/// cards slide to their new places; new cards are dealt in from the right.
	/// </summary>
	public void ShowHand(IReadOnlyList<CardData> hand, Func<CardData, int> costOf, Func<CardData, bool> canAfford)
	{
		EnsureFan();
		if (CardScene == null)
		{
			GD.PushError("HandView: CardScene is not assigned.");
			ClearCards();
			return;
		}
		if (hand == null)
		{
			ClearCards();
			return;
		}

		var unused = new List<CardView>(_cards);
		var ordered = new List<CardView>(hand.Count);
		var fresh = new HashSet<CardView>();
		foreach (CardData card in hand)
		{
			CardView view = unused.Find(v => v.Card == card);
			if (view != null)
			{
				unused.Remove(view);
			}
			else
			{
				view = CardScene.Instantiate<CardView>();
				view.ManagedLayout = true;
				_fan.AddChild(view);
				view.CardClicked += OnCardClicked;
				view.HoverChanged += OnCardHoverChanged;
				fresh.Add(view);
			}
			view.Setup(card, costOf != null ? costOf(card) : card.ApCost);
			view.SetPlayable(canAfford == null || canAfford(card));
			ordered.Add(view);
		}
		foreach (CardView view in unused)
		{
			FreeCard(view);
		}
		_cards.Clear();
		_cards.AddRange(ordered);

		Vector2 dealFrom = new Vector2(_fan.Size.X + 60f, _fan.Size.Y - 120f);
		int dealt = 0;
		foreach (CardView view in fresh)
		{
			view.Position = dealFrom;
			view.Rotation = Mathf.DegToRad(20f);
			if (dealt < 4)
			{
				Sfx.PlayDelayed(SfxId.CardDeal, dealt * 0.09f);
			}
			dealt++;
		}

		_hoveredIndex = _cards.FindIndex(v => v.IsHovered);
		_selectedIndex = -1;
		for (int i = 0; i < _cards.Count; i++)
		{
			_cards[i].SetSelected(false);
		}
		RestoreOrder();
		Relayout(true);
	}

	/// <summary>Highlights the card at the given hand index (-1 = no selection).</summary>
	public void SetSelectedIndex(int index)
	{
		_selectedIndex = index >= 0 && index < _cards.Count ? index : -1;
		for (int i = 0; i < _cards.Count; i++)
		{
			_cards[i].SetSelected(i == _selectedIndex);
		}
		Relayout(true);
	}

	private void EnsureFan()
	{
		if (_fan != null)
		{
			return;
		}
		_fan = new Control
		{
			Name = "Fan",
			MouseFilter = MouseFilterEnum.Ignore,
			SizeFlagsHorizontal = SizeFlags.ExpandFill,
			SizeFlagsVertical = SizeFlags.ExpandFill,
		};
		AddChild(_fan);
		_fan.Resized += () => Relayout(false);
	}

	private void Relayout(bool animate)
	{
		if (_fan == null)
		{
			return;
		}
		int n = _cards.Count;
		if (n == 0 || _fan.Size.X < 1f)
		{
			return;
		}
		Vector2 cardSize = _cards[0].Size.X > 0 ? _cards[0].Size : new Vector2(150, 210);
		float width = Mathf.Max(cardSize.X, _fan.Size.X);
		float spacing = n > 1 ? Mathf.Min(CardSpacing, (width - cardSize.X * RestScale) / (n - 1)) : 0f;
		float center = _fan.Size.X * 0.5f;
		float hoverY = _fan.Size.Y - cardSize.Y;
		float baseY = hoverY + RestSink;

		for (int i = 0; i < n; i++)
		{
			CardView card = _cards[i];
			card.PivotOffset = new Vector2(cardSize.X * 0.5f, cardSize.Y);
			float off = i - (n - 1) * 0.5f;
			float x = center + off * spacing;
			float y = baseY + off * off * ArcDrop;
			float angle = Mathf.DegToRad(off * FanAngleDegrees);
			float scale = RestScale;
			if (_hoveredIndex >= 0 && i != _hoveredIndex)
			{
				int d = i - _hoveredIndex;
				x += Mathf.Sign(d) * PushAside / Mathf.Abs(d);
			}
			if (i == _hoveredIndex)
			{
				angle = 0f;
				scale = HoverScale;
				y = hoverY;
			}
			else if (i == _selectedIndex)
			{
				y -= SelectedRise;
				scale = RestScale * 1.06f;
				angle *= 0.5f;
			}
			var pos = new Vector2(x - cardSize.X * 0.5f, y);
			if (_tweens.TryGetValue(card, out Tween old) && old.IsValid())
			{
				old.Kill();
			}
			if (!animate)
			{
				card.Position = pos;
				card.Rotation = angle;
				card.Scale = new Vector2(scale, scale);
				continue;
			}
			Tween tween = card.CreateTween();
			tween.SetParallel(true);
			tween.SetTrans(Tween.TransitionType.Cubic).SetEase(Tween.EaseType.Out);
			tween.TweenProperty(card, "position", pos, LayoutTweenTime);
			tween.TweenProperty(card, "rotation", angle, LayoutTweenTime);
			tween.TweenProperty(card, "scale", new Vector2(scale, scale), LayoutTweenTime);
			_tweens[card] = tween;
		}
	}

	private void RestoreOrder()
	{
		// Deferred: hover signals can arrive while the fan is busy adding children.
		if (_orderQueued)
		{
			return;
		}
		_orderQueued = true;
		Callable.From(ApplyOrder).CallDeferred();
	}

	private void ApplyOrder()
	{
		_orderQueued = false;
		if (_fan == null || !IsInstanceValid(_fan))
		{
			return;
		}
		for (int i = 0; i < _cards.Count; i++)
		{
			if (IsInstanceValid(_cards[i]) && _cards[i].GetParent() == _fan)
			{
				_fan.MoveChild(_cards[i], Mathf.Min(i, _fan.GetChildCount() - 1));
			}
		}
		if (_hoveredIndex >= 0 && _hoveredIndex < _cards.Count && IsInstanceValid(_cards[_hoveredIndex]) && _cards[_hoveredIndex].GetParent() == _fan)
		{
			_fan.MoveChild(_cards[_hoveredIndex], -1);
		}
	}

	private void OnCardHoverChanged(CardView card, bool hovered)
	{
		int index = _cards.IndexOf(card);
		if (index < 0)
		{
			return;
		}
		if (hovered)
		{
			_hoveredIndex = index;
			Sfx.Play(SfxId.CardHover);
		}
		else if (_hoveredIndex == index)
		{
			_hoveredIndex = -1;
		}
		RestoreOrder();
		Relayout(true);
		EmitSignal(SignalName.CardHoverChanged, card, hovered);
	}

	private void OnCardClicked(CardView card)
	{
		int index = _cards.IndexOf(card);
		if (index >= 0)
		{
			Sfx.Play(SfxId.CardPick);
			EmitSignal(SignalName.CardSelected, index);
		}
	}

	private void FreeCard(CardView view)
	{
		_tweens.Remove(view);
		view.CardClicked -= OnCardClicked;
		view.HoverChanged -= OnCardHoverChanged;
		if (view.GetParent() != null)
		{
			view.GetParent().RemoveChild(view);
		}
		view.QueueFree();
	}

	private void ClearCards()
	{
		foreach (CardView view in _cards)
		{
			FreeCard(view);
		}
		_cards.Clear();
		_hoveredIndex = -1;
		_selectedIndex = -1;
	}
}
